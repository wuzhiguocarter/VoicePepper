import Foundation

struct AudioFrame: Sendable, Equatable {
    let id: UUID
    let samples: [Float]
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let source: RecordingSource

    init(
        id: UUID = UUID(),
        samples: [Float],
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        source: RecordingSource
    ) {
        self.id = id
        self.samples = samples
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.source = source
    }
}

struct ASRTranscriptEvent: Sendable, Identifiable, Equatable {
    let id: UUID
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let text: String
    let isFinal: Bool
}

struct SpeakerSegmentEvent: Sendable, Identifiable, Equatable {
    let id: UUID
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let speakerLabel: String
    let confidence: Float?
}

struct RealtimeTranscriptChunk: Sendable, Identifiable, Equatable {
    let id: UUID
    var startTimeSeconds: Double
    var endTimeSeconds: Double
    var text: String
    var isFinal: Bool
    var speakerLabel: String?
    var speakerConfidence: Float?
    var source: RecordingSource
}
