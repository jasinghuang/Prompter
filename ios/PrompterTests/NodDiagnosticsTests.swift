import XCTest
@testable import Prompter

final class NodDiagnosticsTests: XCTestCase {
    private func nod(at time: Double) -> DeliberateNodDetector.AcceptedNod {
        .init(time: time, peakDegrees: 12, duration: 0.8, returnStartedAt: time - 0.1)
    }
    func testDiagnosticsDefaultOffAndDoNotInferIntentFromFrames() {
        var d = NodDiagnostics()
        d.observe(.ready, at: 100); d.detected(nod(at: 101), id: UUID()); d.markMiss(at: 102)
        XCTAssertFalse(d.recording); XCTAssertFalse(d.canMark)
        XCTAssertTrue(d.entries.isEmpty); XCTAssertEqual(d.counts, .init())
        d.begin(at: 100); d.observe(.settling, at: 100)
        for t in 101...120 { d.observe(.settling, at: Double(t)) }
        XCTAssertEqual(d.counts.manualMisses, 0, "未就绪帧不能自动变成用户点头失败")
        XCTAssertEqual(d.entries.count, 1, "同一状态的每个心跳不应重复生成事件")
    }
    func testObservedDurationsPauseAndResumeWithoutCountingRecordingGap() {
        var d = NodDiagnostics()
        d.begin(at: 100); d.observe(.settling, at: 100); d.observe(.ready, at: 102)
        d.observe(.suspended, at: 105); d.end(at: 110)
        d.begin(at: 120); d.observe(.cooldown, at: 120); d.end(at: 121)
        let seconds = d.observedSeconds(at: 1000)
        XCTAssertEqual(seconds[.settling], 2)
        XCTAssertEqual(seconds[.ready], 3)
        XCTAssertEqual(seconds[.suspended], 5)
        XCTAssertEqual(seconds[.cooldown], 1)
        XCTAssertEqual(d.lastPlaybackObservation?.condition, .cooldown)
    }
    func testActualPlaybackAcknowledgmentIsSeparateAndIdempotent() {
        var d = NodDiagnostics(); d.begin(at: 100)
        let id = UUID(); d.detected(nod(at: 101), id: id); d.detected(nod(at: 101), id: id)
        XCTAssertEqual(d.counts.detected, 1); XCTAssertEqual(d.counts.applied, 0)
        d.applied(id: UUID(), playing: true, at: 101.2)
        XCTAssertEqual(d.counts.applied, 0)
        d.applied(id: id, playing: true, at: 101.2); d.applied(id: id, playing: true, at: 101.3)
        XCTAssertEqual(d.counts.applied, 1)
        XCTAssertEqual(d.entries.last?.applicationDelayMs ?? 0, 200, accuracy: 0.0001)
        XCTAssertEqual(d.entries.last?.returnToAppliedMs ?? 0, 300, accuracy: 0.0001)
        let ignored = UUID(); d.detected(nod(at: 102), id: ignored); d.notApplied(id: ignored); d.notApplied(id: ignored)
        XCTAssertEqual(d.counts.detected, 2); XCTAssertEqual(d.counts.applied, 1); XCTAssertEqual(d.counts.notApplied, 1)
    }
    func testExportDescribesReturnDisturbanceWithoutStoringMotionSamples() throws {
        var d = NodDiagnostics(); d.begin(at: 100)
        var accepted = nod(at: 101); accepted.toleratedReturnDisturbanceSeconds = 0.02
        let id = UUID(); d.detected(accepted, id: id); d.applied(id: id, playing: true, at: 101.1)
        let json = try JSONSerialization.jsonObject(with: Data(d.exportJSON(at: 102).utf8)) as! [String: Any]
        let response = try XCTUnwrap(json["latestAppliedResponse"] as? [String: Any])
        XCTAssertEqual(response["toleratedReturnDisturbanceMs"] as? Double, 20)
        XCTAssertNil(response["rawSamples"])
    }
    func testMissMarkUsesPreSettingsObservationWithoutAssertingACause() {
        var d = NodDiagnostics(); d.begin(at: 100)
        d.observe(.cooldown, at: 101); d.observe(.suspended, at: 102); d.markMiss(at: 120)
        let mark = d.entries.last
        XCTAssertEqual(d.counts.manualMisses, 1); XCTAssertEqual(d.counts.rejected, 0)
        XCTAssertEqual(mark?.condition, .cooldown); XCTAssertEqual(mark?.contextObservedAt, 101)
        XCTAssertNil(mark?.reason); XCTAssertNil(mark?.linkedEntryID)
        d.undoMark(); XCTAssertEqual(d.counts.manualMisses, 0)
        XCTAssertFalse(d.canUndoMark)
    }
    func testFalsePositiveLabelsReferToActualResponsesAndUndoSafely() {
        var d = NodDiagnostics(); d.begin(at: 100)
        d.markLastResponseFalse(at: 101); XCTAssertEqual(d.counts.manualFalsePositives, 0)
        let id = UUID(); d.detected(nod(at: 102), id: id)
        d.markLastResponseFalse(at: 102); XCTAssertEqual(d.counts.manualFalsePositives, 0)
        d.applied(id: id, playing: true, at: 102.1)
        d.markLastResponseFalse(at: 103); d.markLastResponseFalse(at: 104)
        XCTAssertEqual(d.counts.manualFalsePositives, 1)
        XCTAssertEqual(d.entries.last?.linkedEntryID, id)
        d.markMiss(at: 105); d.undoMark()
        XCTAssertEqual(d.counts.manualFalsePositives, 1); XCTAssertFalse(d.canMarkFalsePositive)
        d.undoMark(); XCTAssertEqual(d.counts.manualFalsePositives, 0); XCTAssertTrue(d.canMarkFalsePositive)
    }
    func testHistoryIsBoundedButTotalsAndLastResponseSurviveEviction() throws {
        var d = NodDiagnostics(); d.begin(at: 100)
        let id = UUID(); d.detected(nod(at: 101), id: id); d.applied(id: id, playing: true, at: 101.1)
        for n in 0..<300 {
            let a = DeliberateNodDetector.RejectedAttempt(reason: .small, time: Double(102 + n), peakDegrees: 4, duration: 0.5)
            d.rejected(a); d.rejected(a)
        }
        XCTAssertEqual(d.entries.count, NodDiagnostics.historyLimit)
        XCTAssertEqual(d.counts.rejected, 300); XCTAssertEqual(d.rejectionCounts["small"], 300)
        d.markLastResponseFalse(at: 500)
        XCTAssertEqual(d.counts.manualFalsePositives, 1)
        let json = try JSONSerialization.jsonObject(with: Data(d.exportJSON(at: 500).utf8)) as! [String: Any]
        XCTAssertEqual((json["latestAppliedResponse"] as? [String: Any])?["id"] as? String, id.uuidString)
        XCTAssertNil(json["successRate"]); XCTAssertNil(json["accuracy"]); XCTAssertNil(json["rawSamples"])
    }
    func testClearKeepsRecordingChoiceAndRejectsDecisionsBeforeNewWindow() {
        var d = NodDiagnostics(); d.begin(at: 100); d.markMiss(at: 101); d.clear(at: 200)
        XCTAssertTrue(d.recording); XCTAssertEqual(d.counts, .init()); XCTAssertTrue(d.entries.isEmpty)
        d.detected(nod(at: 199), id: UUID())
        d.rejected(.init(reason: .slow, time: 199, peakDegrees: 12, duration: 2))
        XCTAssertEqual(d.counts, .init())
        d.end(at: 201); d.clear(at: 202)
        XCTAssertFalse(d.recording); XCTAssertFalse(d.canMark)
    }
    func testBackwardOrNonfiniteObservationDoesNotCorruptDurations() throws {
        var d = NodDiagnostics(); d.begin(at: 100); d.observe(.ready, at: 101)
        d.observe(.settling, at: 99); d.observe(.cooldown, at: .nan); d.observe(.suspended, at: 103)
        XCTAssertEqual(d.observedSeconds(at: 104)[.ready], 2)
        XCTAssertEqual(d.lastPlaybackObservation?.condition, .ready)
        XCTAssertNoThrow(try d.exportJSON(at: 104))
    }
}
