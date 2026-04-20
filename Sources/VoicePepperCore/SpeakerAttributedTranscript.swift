import Foundation

public struct RecordingSessionData: Sendable {
    public let samples: [Float]
    public let startedAt: Date
    public let endedAt: Date

    public var duration: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
    }

    public init(samples: [Float], startedAt: Date, endedAt: Date) {
        self.samples = samples
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct SpeakerAttributedTranscriptDocument: Codable, Equatable {
    public let schemaVersion: Int
    public let createdAt: Date
    public let fullText: String
    public let chunks: [SpeakerAttributedTranscriptChunk]
    public let diarizationSegments: [SpeakerDiarizationSegment]
    public let speakerCount: Int
    public let engineMetadata: SpeechEngineMetadata?

    public init(
        schemaVersion: Int = 1,
        createdAt: Date = Date(),
        fullText: String,
        chunks: [SpeakerAttributedTranscriptChunk],
        diarizationSegments: [SpeakerDiarizationSegment],
        engineMetadata: SpeechEngineMetadata? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.fullText = fullText
        self.chunks = chunks
        self.diarizationSegments = diarizationSegments
        self.speakerCount = Set(diarizationSegments.map(\.speakerLabel)).count
        self.engineMetadata = engineMetadata
    }

    public var formattedText: String {
        chunks.map(\.formattedLine).joined(separator: "\n")
    }
}

public struct SpeakerAttributedTranscriptChunk: Codable, Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let relativeTimeSeconds: Double?
    public let speakerLabel: String?
    public let speakerProfileID: String?
    public let startTimeSeconds: Double?
    public let endTimeSeconds: Double?

    public init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date,
        relativeTimeSeconds: Double?,
        speakerLabel: String?,
        speakerProfileID: String? = nil,
        startTimeSeconds: Double?,
        endTimeSeconds: Double?
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.relativeTimeSeconds = relativeTimeSeconds
        self.speakerLabel = speakerLabel
        self.speakerProfileID = speakerProfileID
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
    }

    public var formattedLine: String {
        let prefix = speakerLabel.map { "[\($0)] " } ?? ""
        return "\(prefix)\(text)"
    }
}

public struct SpeakerDiarizationSegment: Codable, Equatable, Identifiable {
    public let id: UUID
    public let speakerLabel: String
    public let startTimeSeconds: Double
    public let endTimeSeconds: Double
    public let qualityScore: Float?

    public init(
        id: UUID = UUID(),
        speakerLabel: String,
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        qualityScore: Float? = nil
    ) {
        self.id = id
        self.speakerLabel = speakerLabel
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.qualityScore = qualityScore
    }

    public func contains(timeSeconds: Double) -> Bool {
        timeSeconds >= startTimeSeconds && timeSeconds <= endTimeSeconds
    }
}

public struct SpeechEngineMetadata: Codable, Equatable, Sendable {
    public let asrEngine: String
    public let diarizationEngine: String
    public let modelVersion: String?
    public let localeIdentifier: String?

    public init(
        asrEngine: String,
        diarizationEngine: String,
        modelVersion: String? = nil,
        localeIdentifier: String? = nil
    ) {
        self.asrEngine = asrEngine
        self.diarizationEngine = diarizationEngine
        self.modelVersion = modelVersion
        self.localeIdentifier = localeIdentifier
    }
}
