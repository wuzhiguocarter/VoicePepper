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

/// 负责将录音会话 PCM 样本持久化为 M4A 文件，并管理历史录音列表。
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
                .filter { $0.pathExtension.lowercased() == "m4a" }
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

    /// 将整个会话的完整 PCM 样本异步写为一个 M4A 文件（合并所有 VAD 段）。
    func save(samples: [Float], sampleRate: Double = 16000) {
        guard !samples.isEmpty else { return }
        let outputURL = makeOutputURL()
        // 用 Task 保持 @MainActor 上下文，I/O 通过内层 Task.detached 在后台执行
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let duration = try await Task.detached(priority: .utility) {
                    try Self.writeM4A(samples: samples, sampleRate: sampleRate, to: outputURL)
                }.value
                let item = RecordingItem(id: UUID(), url: outputURL, duration: duration, createdAt: Date())
                self.recordings.insert(item, at: 0)
                NSLog("[RecordingFileService] 已保存: %@", outputURL.lastPathComponent)
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
        let name = "Recording_\(formatter.string(from: Date())).m4a"
        return storageDirectory.appendingPathComponent(name)
    }

    private static func durationOf(url: URL) -> TimeInterval {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    // MARK: 写盘（nonisolated，可在任意线程调用）

    /// 将 Float32 PCM 样本写入 M4A（AAC 编码），返回实际时长（秒）。
    private nonisolated static func writeM4A(samples: [Float], sampleRate: Double, to outputURL: URL) throws -> TimeInterval {
        let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000
        ]

        let audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: aacSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // 分块写入避免单次申请超大 PCM buffer
        let chunkSize = 65_536
        var offset = 0

        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            let chunkCount = end - offset
            let chunk = Array(samples[offset..<end])

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: pcmFormat,
                frameCapacity: AVAudioFrameCount(chunkCount)
            ) else { break }

            buffer.frameLength = AVAudioFrameCount(chunkCount)
            if let channelData = buffer.floatChannelData {
                chunk.withUnsafeBufferPointer { ptr in
                    channelData[0].update(from: ptr.baseAddress!, count: chunkCount)
                }
            }

            try audioFile.write(from: buffer)
            offset = end
        }

        return Double(samples.count) / sampleRate
    }
}
