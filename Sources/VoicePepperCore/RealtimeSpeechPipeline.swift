import Foundation

public struct AudioFrame: Sendable, Equatable {
    public let id: UUID
    public let samples: [Float]
    public let startTimeSeconds: Double
    public let endTimeSeconds: Double
    public let source: RecordingSource

    public init(
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

public struct AudioSegment: Sendable {
    public let samples: [Float]
    public let capturedAt: Date

    public init(samples: [Float], capturedAt: Date) {
        self.samples = samples
        self.capturedAt = capturedAt
    }
}

public struct ASRTranscriptEvent: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let startTimeSeconds: Double
    public let endTimeSeconds: Double
    public let text: String
    public let isFinal: Bool

    public init(id: UUID, startTimeSeconds: Double, endTimeSeconds: Double, text: String, isFinal: Bool) {
        self.id = id
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.text = text
        self.isFinal = isFinal
    }
}

public struct SpeakerSegmentEvent: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let startTimeSeconds: Double
    public let endTimeSeconds: Double
    public let speakerLabel: String
    public let confidence: Float?

    public init(id: UUID, startTimeSeconds: Double, endTimeSeconds: Double, speakerLabel: String, confidence: Float?) {
        self.id = id
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.speakerLabel = speakerLabel
        self.confidence = confidence
    }
}

public struct RealtimeTranscriptChunk: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var startTimeSeconds: Double
    public var endTimeSeconds: Double
    public var text: String
    public var isFinal: Bool
    public var speakerLabel: String?
    public var speakerConfidence: Float?
    public var source: RecordingSource

    public init(
        id: UUID,
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        text: String,
        isFinal: Bool,
        speakerLabel: String? = nil,
        speakerConfidence: Float? = nil,
        source: RecordingSource
    ) {
        self.id = id
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.text = text
        self.isFinal = isFinal
        self.speakerLabel = speakerLabel
        self.speakerConfidence = speakerConfidence
        self.source = source
    }
}
