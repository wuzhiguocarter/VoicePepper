import AVFoundation
import Foundation

// MARK: - Recording Item

struct RecordingItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let duration: TimeInterval   // 秒
    let createdAt: Date

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: createdAt)
    }

    var formattedDuration: String {
        let total = Int(duration)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Recording File Service

/// 负责将录音会话 PCM 样本持久化为 WAV 文件，并管理历史录音列表。
/// 使用 PCM 直写（无需 AAC 编码），AVAudioPlayer 原生支持 WAV 回放。
@MainActor
final class RecordingFileService: ObservableObject {

    // MARK: 存储目录

    /// ~/Library/Application Support/VoicePepper/Recordings/
    var storageDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("VoicePepper/Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: 列表

    @Published private(set) var recordings: [RecordingItem] = []

    func loadRecordings() {
        let dir = storageDirectory
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
            recordings = urls
                // 同时支持 wav（新格式）和旧的空 m4a 文件（排除零字节文件）
                .filter {
                    let ext = $0.pathExtension.lowercased()
                    guard ext == "wav" || ext == "m4a" else { return false }
                    let size = (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) ?? 0
                    return size > 0
                }
                .compactMap { url -> RecordingItem? in
                    let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    let createdAt = attrs?.contentModificationDate ?? Date()
                    let duration = Self.durationOf(url: url)
                    return RecordingItem(id: UUID(), url: url, duration: duration, createdAt: createdAt)
                }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            NSLog("[RecordingFileService] 无法枚举录音目录: %@", error.localizedDescription)
        }
    }

    // MARK: 保存

    /// 将整个会话的完整 PCM 样本异步写为一个 WAV 文件（合并所有 VAD 段）。
    func save(samples: [Float], sampleRate: Double = 16000) {
        guard !samples.isEmpty else { return }
        let outputURL = makeOutputURL()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let duration = try await Task.detached(priority: .utility) {
                    try Self.writeWAV(samples: samples, sampleRate: sampleRate, to: outputURL)
                }.value
                let item = RecordingItem(id: UUID(), url: outputURL, duration: duration, createdAt: Date())
                self.recordings.insert(item, at: 0)
                NSLog("[RecordingFileService] 已保存: %@ (%.1fs)", outputURL.lastPathComponent, duration)
            } catch {
                NSLog("[RecordingFileService] 写盘失败: %@", error.localizedDescription)
            }
        }
    }

    // MARK: 删除

    func delete(item: RecordingItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
        } catch {
            NSLog("[RecordingFileService] 删除失败: %@", error.localizedDescription)
        }
        recordings.removeAll { $0.id == item.id }
    }

    // MARK: 私有工具

    private func makeOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "Recording_\(formatter.string(from: Date())).wav"
        return storageDirectory.appendingPathComponent(name)
    }

    private static func durationOf(url: URL) -> TimeInterval {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = audioFile.processingFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return Double(audioFile.length) / sampleRate
    }

    // MARK: 写盘（nonisolated，在后台线程调用）

    /// 将 Float32 PCM 样本写入 WAV 文件，返回实际时长（秒）。
    /// WAV 格式直写，无需 AAC 编码，兼容所有 macOS 版本。
    private nonisolated static func writeWAV(samples: [Float], sampleRate: Double, to outputURL: URL) throws -> TimeInterval {
        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let audioFile = try AVAudioFile(forWriting: outputURL, settings: wavSettings)

        let chunkSize = 65_536
        var offset = 0

        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            let chunkCount = end - offset

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: pcmFormat,
                frameCapacity: AVAudioFrameCount(chunkCount)
            ) else { break }

            buffer.frameLength = AVAudioFrameCount(chunkCount)
            if let channelData = buffer.floatChannelData {
                samples.withUnsafeBufferPointer { ptr in
                    channelData[0].update(from: ptr.baseAddress! + offset, count: chunkCount)
                }
            }

            try audioFile.write(from: buffer)
            offset = end
        }

        return Double(samples.count) / sampleRate
    }
}
