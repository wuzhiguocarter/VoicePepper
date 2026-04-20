import Foundation
import SpeakerKit

public actor SpeakerKitDiarizationService {
    private let config: PyannoteConfig
    private var speakerKit: SpeakerKit?
    private var pendingTask: Task<Void, Never>?
    private var callback: (@Sendable ([SpeakerSegmentEvent]) -> Void)?

    public func setCallback(_ cb: @Sendable @escaping ([SpeakerSegmentEvent]) -> Void) {
        callback = cb
    }

    public init(config: PyannoteConfig? = nil) {
        self.config = config ?? PyannoteConfig(
            download: true,
            load: true,
            verbose: false
        )
    }

    /// 等待所有待处理 diarization 任务完成
    public func waitUntilIdle() async {
        await pendingTask?.value
    }

    /// Enqueue a segment for serial diarization. Each call chains after the previous.
    public func enqueue(_ segment: AudioSegment) {
        let previous = pendingTask
        pendingTask = Task {
            await previous?.value
            await processSegment(segment)
        }
    }

    private func processSegment(_ segment: AudioSegment) async {
        do {
            let events = try await diarize(audioSamples: segment.samples)
            let cb = callback
            if !events.isEmpty {
                cb?(events)
            }
        } catch {
            NSLog("[SpeakerKitDiarizationService] diarization 失败: %@", error.localizedDescription)
        }
    }

    private func prepareIfNeeded() async throws {
        guard speakerKit == nil else { return }
        speakerKit = try await SpeakerKit(config)
    }

    public func diarize(audioSamples: [Float]) async throws -> [SpeakerSegmentEvent] {
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
