import Foundation

actor TimelineMerger {
    private var chunks: [RealtimeTranscriptChunk] = []
    private var speakerEvents: [SpeakerSegmentEvent] = []

    func applyASREvent(
        _ event: ASRTranscriptEvent,
        source: RecordingSource
    ) -> [RealtimeTranscriptChunk] {
        let matchingSpeaker = bestSpeakerEvent(
            forStart: event.startTimeSeconds,
            end: event.endTimeSeconds
        )

        if let index = chunks.firstIndex(where: { $0.id == event.id }) {
            chunks[index].startTimeSeconds = event.startTimeSeconds
            chunks[index].endTimeSeconds = event.endTimeSeconds
            chunks[index].text = event.text
            chunks[index].isFinal = event.isFinal
            chunks[index].speakerLabel = matchingSpeaker?.speakerLabel
            chunks[index].speakerConfidence = matchingSpeaker?.confidence
        } else {
            chunks.append(
                RealtimeTranscriptChunk(
                    id: event.id,
                    startTimeSeconds: event.startTimeSeconds,
                    endTimeSeconds: event.endTimeSeconds,
                    text: event.text,
                    isFinal: event.isFinal,
                    speakerLabel: matchingSpeaker?.speakerLabel,
                    speakerConfidence: matchingSpeaker?.confidence,
                    source: source
                )
            )
        }

        chunks.sort { $0.startTimeSeconds < $1.startTimeSeconds }
        return chunks
    }

    func applySpeakerEvent(_ event: SpeakerSegmentEvent) -> [RealtimeTranscriptChunk] {
        if !speakerEvents.contains(where: { $0.id == event.id }) {
            speakerEvents.append(event)
        }

        for index in chunks.indices {
            let chunk = chunks[index]
            if let bestMatch = bestSpeakerEvent(forStart: chunk.startTimeSeconds, end: chunk.endTimeSeconds) {
                chunks[index].speakerLabel = bestMatch.speakerLabel
                chunks[index].speakerConfidence = bestMatch.confidence
            }
        }

        return chunks
    }

    func snapshot() -> [RealtimeTranscriptChunk] {
        chunks
    }

    private func bestSpeakerEvent(forStart start: Double, end: Double) -> SpeakerSegmentEvent? {
        let overlapping = speakerEvents
            .map { event in (event, overlapDuration(startA: start, endA: end, startB: event.startTimeSeconds, endB: event.endTimeSeconds)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }

        if let best = overlapping.first?.0 {
            return best
        }

        let midpoint = (start + end) / 2
        return speakerEvents.min {
            distance(midpoint, to: $0) < distance(midpoint, to: $1)
        }
    }

    private func overlapDuration(startA: Double, endA: Double, startB: Double, endB: Double) -> Double {
        max(0, min(endA, endB) - max(startA, startB))
    }

    private func distance(_ time: Double, to event: SpeakerSegmentEvent) -> Double {
        if time < event.startTimeSeconds { return event.startTimeSeconds - time }
        if time > event.endTimeSeconds { return time - event.endTimeSeconds }
        return 0
    }
}
