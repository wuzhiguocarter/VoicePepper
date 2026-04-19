import AVFoundation
import Foundation

// MARK: - Recording Item

struct RecordingItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let duration: TimeInterval   // 秒
    let createdAt: Date
    let transcriptionURL: URL?   // 配对的 .txt 转录文本文件
    let transcriptJSONURL: URL?  // 配对的结构化 transcript JSON 文件

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

    /// 按需从配对的 .txt 文件读取转录文本
    var transcriptionText: String? {
        guard let txtURL = transcriptionURL else { return nil }
        return try? String(contentsOf: txtURL, encoding: .utf8)
    }

    var speakerAttributedTranscript: SpeakerAttributedTranscriptDocument? {
        guard let jsonURL = transcriptJSONURL else { return nil }
        return RecordingFileService.loadTranscriptDocument(from: jsonURL)
    }

    var preferredTranscriptionText: String? {
        if let structured = speakerAttributedTranscript?.formattedText, !structured.isEmpty {
            return structured
        }
        return transcriptionText
    }

    static func == (lhs: RecordingItem, rhs: RecordingItem) -> Bool {
        lhs.id == rhs.id
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
                    let txtURL = Self.txtURL(for: url)
                    let jsonURL = Self.transcriptJSONURL(for: url)
                    let hasTranscription = FileManager.default.fileExists(atPath: txtURL.path)
                    let hasTranscriptJSON = FileManager.default.fileExists(atPath: jsonURL.path)
                    return RecordingItem(
                        id: UUID(),
                        url: url,
                        duration: duration,
                        createdAt: createdAt,
                        transcriptionURL: hasTranscription ? txtURL : nil,
                        transcriptJSONURL: hasTranscriptJSON ? jsonURL : nil
                    )
                }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            NSLog("[RecordingFileService] 无法枚举录音目录: %@", error.localizedDescription)
        }
    }

    // MARK: 保存

    /// 将整个会话的完整 PCM 样本异步写为一个 WAV 文件（合并所有 VAD 段）。
    /// 同时将转录条目保存为同名 .txt 文件，并尽力生成结构化 transcript JSON。
    func save(
        session: RecordingSessionData,
        transcriptionEntries: [TranscriptionEntry] = [],
        diarizationService: FluidAudioDiarizationService? = nil,
        sampleRate: Double = 16000
    ) async {
        guard !session.samples.isEmpty else { return }
        let outputURL = makeOutputURL()
        do {
            let duration = try await Task.detached(priority: .utility) {
                try Self.writeWAV(samples: session.samples, sampleRate: sampleRate, to: outputURL)
            }.value

            var txtURL: URL? = nil
            if !transcriptionEntries.isEmpty {
                txtURL = Self.txtURL(for: outputURL)
                let text = transcriptionEntries.map { entry in
                    let f = DateFormatter()
                    f.dateFormat = "HH:mm:ss"
                    return "[\(f.string(from: entry.timestamp))] \(entry.text)"
                }.joined(separator: "\n")
                try text.write(to: txtURL!, atomically: true, encoding: .utf8)
            }

            var transcriptJSONURL: URL? = nil
            if let diarizationService, !transcriptionEntries.isEmpty {
                do {
                    if let transcript = try await diarizationService.buildTranscript(
                        recordingURL: outputURL,
                        transcriptionEntries: transcriptionEntries,
                        session: session
                    ) {
                        transcriptJSONURL = Self.transcriptJSONURL(for: outputURL)
                        try Self.writeTranscriptDocument(transcript, to: transcriptJSONURL!)
                    }
                } catch {
                    NSLog("[RecordingFileService] diarization 失败，回退纯文本: %@", error.localizedDescription)
                }
            }

            let item = RecordingItem(
                id: UUID(),
                url: outputURL,
                duration: duration,
                createdAt: Date(),
                transcriptionURL: txtURL,
                transcriptJSONURL: transcriptJSONURL
            )
            recordings.insert(item, at: 0)
            NSLog("[RecordingFileService] 已保存: %@ (%.1fs)", outputURL.lastPathComponent, duration)
        } catch {
            NSLog("[RecordingFileService] 写盘失败: %@", error.localizedDescription)
        }
    }

    /// 实验性模式：用 TimelineMerger snapshot 的 RealtimeTranscriptChunk 列表落盘。
    func saveWithRealtimeChunks(
        session: RecordingSessionData,
        chunks: [RealtimeTranscriptChunk],
        sampleRate: Double = 16000
    ) async {
        guard !session.samples.isEmpty else { return }
        let outputURL = makeOutputURL()
        do {
            let duration = try await Task.detached(priority: .utility) {
                try Self.writeWAV(samples: session.samples, sampleRate: sampleRate, to: outputURL)
            }.value

            var txtURL: URL? = nil
            if !chunks.isEmpty {
                txtURL = Self.txtURL(for: outputURL)
                let text = chunks.map { "[\($0.speakerLabel ?? "?")] \($0.text)" }.joined(separator: "\n")
                try text.write(to: txtURL!, atomically: true, encoding: .utf8)
            }

            var transcriptJSONURL: URL? = nil
            if !chunks.isEmpty {
                let attrChunks = chunks.map { chunk in
                    SpeakerAttributedTranscriptChunk(
                        text: chunk.text,
                        timestamp: session.startedAt.addingTimeInterval(chunk.startTimeSeconds),
                        relativeTimeSeconds: chunk.startTimeSeconds,
                        speakerLabel: chunk.speakerLabel,
                        startTimeSeconds: chunk.startTimeSeconds,
                        endTimeSeconds: chunk.endTimeSeconds
                    )
                }
                let speakerLabels = Set(chunks.compactMap(\.speakerLabel))
                let diarizationSegments = speakerLabels.map { label -> SpeakerDiarizationSegment in
                    let matching = chunks.filter { $0.speakerLabel == label }
                    let start = matching.map(\.startTimeSeconds).min() ?? 0
                    let end = matching.map(\.endTimeSeconds).max() ?? 0
                    return SpeakerDiarizationSegment(speakerLabel: label, startTimeSeconds: start, endTimeSeconds: end)
                }
                let document = SpeakerAttributedTranscriptDocument(
                    fullText: chunks.map(\.text).joined(separator: "\n"),
                    chunks: attrChunks,
                    diarizationSegments: diarizationSegments,
                    engineMetadata: SpeechEngineMetadata(asrEngine: "whisperkit", diarizationEngine: "speakerkit")
                )
                transcriptJSONURL = Self.transcriptJSONURL(for: outputURL)
                try Self.writeTranscriptDocument(document, to: transcriptJSONURL!)
            }

            let item = RecordingItem(
                id: UUID(),
                url: outputURL,
                duration: duration,
                createdAt: Date(),
                transcriptionURL: txtURL,
                transcriptJSONURL: transcriptJSONURL
            )
            recordings.insert(item, at: 0)
            NSLog("[RecordingFileService] 已保存(experimental): %@ (%.1fs, %d chunks)", outputURL.lastPathComponent, duration, chunks.count)
        } catch {
            NSLog("[RecordingFileService] 写盘失败: %@", error.localizedDescription)
        }
    }

    /// 根据录音文件 URL 推导配对的 .txt 文件 URL
    private static func txtURL(for recordingURL: URL) -> URL {
        let name = recordingURL.deletingPathExtension().lastPathComponent
        return recordingURL.deletingLastPathComponent().appendingPathComponent("\(name).txt")
    }

    static func transcriptJSONURL(for recordingURL: URL) -> URL {
        let name = recordingURL.deletingPathExtension().lastPathComponent
        return recordingURL.deletingLastPathComponent().appendingPathComponent("\(name).json")
    }

    // MARK: 删除

    func delete(item: RecordingItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
        } catch {
            NSLog("[RecordingFileService] 删除失败: %@", error.localizedDescription)
        }
        // 同步删除配对的转录文本文件
        if let txtURL = item.transcriptionURL {
            try? FileManager.default.removeItem(at: txtURL)
        }
        if let jsonURL = item.transcriptJSONURL {
            try? FileManager.default.removeItem(at: jsonURL)
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

    private static func writeTranscriptDocument(
        _ transcript: SpeakerAttributedTranscriptDocument,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcript)
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func loadTranscriptDocument(from url: URL) -> SpeakerAttributedTranscriptDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SpeakerAttributedTranscriptDocument.self, from: data)
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
