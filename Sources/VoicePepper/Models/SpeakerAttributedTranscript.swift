import Foundation

struct RecordingSessionData: Sendable {
    let samples: [Float]
    let startedAt: Date
    let endedAt: Date

    var duration: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
    }
}

struct SpeakerAttributedTranscriptDocument: Codable, Equatable {
    let schemaVersion: Int
    let createdAt: Date
    let fullText: String
    let chunks: [SpeakerAttributedTranscriptChunk]
    let diarizationSegments: [SpeakerDiarizationSegment]
    let speakerCount: Int

    init(
        schemaVersion: Int = 1,
        createdAt: Date = Date(),
        fullText: String,
        chunks: [SpeakerAttributedTranscriptChunk],
        diarizationSegments: [SpeakerDiarizationSegment]
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.fullText = fullText
        self.chunks = chunks
        self.diarizationSegments = diarizationSegments
        self.speakerCount = Set(diarizationSegments.map(\.speakerLabel)).count
    }

    var formattedText: String {
        chunks.map(\.formattedLine).joined(separator: "\n")
    }
}

struct SpeakerAttributedTranscriptChunk: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date
    let relativeTimeSeconds: Double?
    let speakerLabel: String?
    let speakerProfileID: String?
    let startTimeSeconds: Double?
    let endTimeSeconds: Double?

    init(
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

    var formattedLine: String {
        let prefix = speakerLabel.map { "[\($0)] " } ?? ""
        return "\(prefix)\(text)"
    }
}

struct SpeakerDiarizationSegment: Codable, Equatable, Identifiable {
    let id: UUID
    let speakerLabel: String
    let startTimeSeconds: Double
    let endTimeSeconds: Double
    let qualityScore: Float?

    init(
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

    func contains(timeSeconds: Double) -> Bool {
        timeSeconds >= startTimeSeconds && timeSeconds <= endTimeSeconds
    }
}
