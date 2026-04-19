import Foundation
import WhisperKit

actor WhisperKitASRService {
    private let config: WhisperKitConfig
    private var whisperKit: WhisperKit?
    private var pendingTask: Task<Void, Never>?

    private var callback: (@Sendable (ASRTranscriptEvent) -> Void)?

    func setCallback(_ cb: @Sendable @escaping (ASRTranscriptEvent) -> Void) {
        callback = cb
    }

    init(config: WhisperKitConfig? = nil) {
        self.config = config ?? WhisperKitConfig(
            model: "tiny",
            verbose: false,
            load: true,
            download: true
        )
    }

    /// Enqueue a segment for serial transcription. Each call chains after the previous.
    func enqueue(_ segment: AudioSegment) {
        let previous = pendingTask
        pendingTask = Task {
            await previous?.value
            await processSegment(segment)
        }
    }

    private func processSegment(_ segment: AudioSegment) async {
        do {
            let events = try await transcribe(audioSamples: segment.samples)
            let cb = callback
            for event in events where !event.text.isEmpty {
                cb?(event)
            }
        } catch {
            NSLog("[WhisperKitASRService] 转录失败: %@", error.localizedDescription)
        }
    }

    private func prepareIfNeeded() async throws {
        guard whisperKit == nil else { return }
        whisperKit = try await WhisperKit(config)
    }

    private func transcribe(audioSamples: [Float]) async throws -> [ASRTranscriptEvent] {
        try await prepareIfNeeded()
        guard let whisperKit else { return [] }

        let options = DecodingOptions(wordTimestamps: true)
        let results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)

        return results.flatMap { result in
            result.segments.map { segment in
                ASRTranscriptEvent(
                    id: UUID(),
                    startTimeSeconds: Double(segment.start),
                    endTimeSeconds: Double(segment.end),
                    text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isFinal: true
                )
            }
        }
    }
}
