import Foundation
import FluidAudio
import VoicePepperCore

@available(macOS 14.0, *)
actor FluidAudioDiarizationService {
    private let manager: OfflineDiarizerManager
    private var isPrepared = false

    init(config: OfflineDiarizerConfig = OfflineDiarizerConfig()) {
        self.manager = OfflineDiarizerManager(config: config)
    }

    func buildTranscript(
        recordingURL: URL,
        transcriptionEntries: [TranscriptionEntry],
        session: RecordingSessionData
    ) async throws -> SpeakerAttributedTranscriptDocument? {
        guard !transcriptionEntries.isEmpty else { return nil }

        try await prepareIfNeeded()
        let result = try await manager.process(recordingURL)

        let diarizationSegments = result.segments.map {
            SpeakerDiarizationSegment(
                speakerLabel: $0.speakerId,
                startTimeSeconds: Double($0.startTimeSeconds),
                endTimeSeconds: Double($0.endTimeSeconds),
                qualityScore: $0.qualityScore
            )
        }

        let chunks = transcriptionEntries.map { entry in
            let relativeTimeSeconds = relativeTime(for: entry, in: session)
            let matchedSegment = bestSegment(for: relativeTimeSeconds, segments: diarizationSegments)

            return SpeakerAttributedTranscriptChunk(
                text: entry.text,
                timestamp: entry.timestamp,
                relativeTimeSeconds: relativeTimeSeconds,
                speakerLabel: matchedSegment?.speakerLabel,
                startTimeSeconds: matchedSegment?.startTimeSeconds,
                endTimeSeconds: matchedSegment?.endTimeSeconds
            )
        }

        let fullText = chunks.map(\.text).joined(separator: "\n")
        return SpeakerAttributedTranscriptDocument(
            fullText: fullText,
            chunks: chunks,
            diarizationSegments: diarizationSegments,
            engineMetadata: SpeechEngineMetadata(
                asrEngine: "whisper.cpp",
                diarizationEngine: "FluidAudio"
            )
        )
    }

    private func prepareIfNeeded() async throws {
        guard !isPrepared else { return }
        try await manager.prepareModels()
        isPrepared = true
    }

    private func relativeTime(for entry: TranscriptionEntry, in session: RecordingSessionData) -> Double {
        let sessionDuration = max(session.duration, 0.1)
        let raw = entry.timestamp.timeIntervalSince(session.startedAt)
        return min(max(raw, 0), sessionDuration)
    }

    private func bestSegment(
        for relativeTimeSeconds: Double,
        segments: [SpeakerDiarizationSegment]
    ) -> SpeakerDiarizationSegment? {
        guard !segments.isEmpty else { return nil }

        if let containing = segments.first(where: { $0.contains(timeSeconds: relativeTimeSeconds) }) {
            return containing
        }

        return segments.min {
            distance(from: relativeTimeSeconds, to: $0) < distance(from: relativeTimeSeconds, to: $1)
        }
    }

    private func distance(from time: Double, to segment: SpeakerDiarizationSegment) -> Double {
        if segment.contains(timeSeconds: time) { return 0 }
        if time < segment.startTimeSeconds { return segment.startTimeSeconds - time }
        return time - segment.endTimeSeconds
    }
}
