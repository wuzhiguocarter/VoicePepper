import Foundation
import SpeakerKit

@available(macOS 14.0, *)
actor SpeakerKitDiarizationService {
    private let config: PyannoteConfig
    private var speakerKit: SpeakerKit?

    init(config: PyannoteConfig? = nil) {
        self.config = config ?? PyannoteConfig(
            download: false,
            load: false,
            verbose: false
        )
    }

    func prepareIfNeeded() async throws {
        guard speakerKit == nil else { return }
        speakerKit = try await SpeakerKit(config)
    }

    func diarize(audioSamples: [Float]) async throws -> [SpeakerSegmentEvent] {
        try await prepareIfNeeded()
        guard let speakerKit else { return [] }

        let result = try await speakerKit.diarize(audioArray: audioSamples)
        return result.segments.map { segment in
            let speakerLabel = segment.speaker.speakerId.map { "S\($0)" } ?? "UNKNOWN"
            return SpeakerSegmentEvent(
                id: segment.id,
                startTimeSeconds: Double(segment.startTime),
                endTimeSeconds: Double(segment.endTime),
                speakerLabel: speakerLabel,
                confidence: nil
            )
        }
    }
}
