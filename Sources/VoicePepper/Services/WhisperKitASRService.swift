import Foundation
import WhisperKit

@available(macOS 14.0, *)
actor WhisperKitASRService {
    private let config: WhisperKitConfig
    private var whisperKit: WhisperKit?

    init(config: WhisperKitConfig? = nil) {
        self.config = config ?? WhisperKitConfig(
            model: "tiny",
            verbose: false,
            load: false,
            download: false
        )
    }

    func prepareIfNeeded() async throws {
        guard whisperKit == nil else { return }
        whisperKit = try await WhisperKit(config)
    }

    func transcribe(audioSamples: [Float]) async throws -> [ASRTranscriptEvent] {
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
