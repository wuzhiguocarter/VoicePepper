import XCTest
import Foundation
@testable import VoicePepperCore

final class TimelineMergerTests: XCTestCase {

    // MARK: - applyASREvent

    func testAppendNewASREvent() async {
        let merger = TimelineMerger()
        let event = makeASR(start: 0, end: 1, text: "你好")
        _ = await merger.applyASREvent(event, source: .filePlayback)
        let chunks = await merger.snapshot()
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "你好")
    }

    func testUpdateExistingASREvent() async {
        let merger = TimelineMerger()
        let id = UUID()
        let first = makeASR(id: id, start: 0, end: 1, text: "初始")
        let second = makeASR(id: id, start: 0, end: 1.5, text: "更新")
        _ = await merger.applyASREvent(first, source: .filePlayback)
        _ = await merger.applyASREvent(second, source: .filePlayback)
        let chunks = await merger.snapshot()
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "更新")
        XCTAssertEqual(chunks[0].endTimeSeconds, 1.5)
    }

    func testMultipleASREventsSortedByTime() async {
        let merger = TimelineMerger()
        _ = await merger.applyASREvent(makeASR(start: 2, end: 3, text: "B"), source: .filePlayback)
        _ = await merger.applyASREvent(makeASR(start: 0, end: 1, text: "A"), source: .filePlayback)
        let chunks = await merger.snapshot()
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].text, "A")
        XCTAssertEqual(chunks[1].text, "B")
    }

    // MARK: - applySpeakerEvent

    func testSpeakerMatchesOverlappingASR() async {
        let merger = TimelineMerger()
        _ = await merger.applyASREvent(makeASR(start: 0, end: 2, text: "hello"), source: .filePlayback)
        let speaker = makeSpeaker(start: 0, end: 2, label: "S0")
        _ = await merger.applySpeakerEvent(speaker)
        let chunks = await merger.snapshot()
        XCTAssertEqual(chunks[0].speakerLabel, "S0")
    }

    func testSpeakerMatchesNearestASRWhenNoOverlap() async {
        let merger = TimelineMerger()
        _ = await merger.applyASREvent(makeASR(start: 5, end: 7, text: "far"), source: .filePlayback)
        let speaker = makeSpeaker(start: 0, end: 2, label: "S1")
        _ = await merger.applySpeakerEvent(speaker)
        let chunks = await merger.snapshot()
        XCTAssertEqual(chunks[0].speakerLabel, "S1")
    }

    func testSpeakerEventWithNoChunksDoesNotCrash() async {
        let merger = TimelineMerger()
        let speaker = makeSpeaker(start: 0, end: 1, label: "S0")
        let result = await merger.applySpeakerEvent(speaker)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - snapshot

    func testSnapshotEmptyInitially() async {
        let merger = TimelineMerger()
        let chunks = await merger.snapshot()
        XCTAssertTrue(chunks.isEmpty)
    }

    func testSnapshotIsIdempotent() async {
        let merger = TimelineMerger()
        _ = await merger.applyASREvent(makeASR(start: 0, end: 1, text: "test"), source: .filePlayback)
        let first = await merger.snapshot()
        let second = await merger.snapshot()
        XCTAssertEqual(first, second)
    }

    // MARK: - helpers

    private func makeASR(
        id: UUID = UUID(),
        start: Double,
        end: Double,
        text: String,
        isFinal: Bool = true
    ) -> ASRTranscriptEvent {
        ASRTranscriptEvent(id: id, startTimeSeconds: start, endTimeSeconds: end, text: text, isFinal: isFinal)
    }

    private func makeSpeaker(
        id: UUID = UUID(),
        start: Double,
        end: Double,
        label: String,
        confidence: Float? = nil
    ) -> SpeakerSegmentEvent {
        SpeakerSegmentEvent(id: id, startTimeSeconds: start, endTimeSeconds: end, speakerLabel: label, confidence: confidence)
    }
}
