import XCTest
import CoreGraphics
@testable import Prompter

final class PromptIndicatorTests: XCTestCase {
    func testPulseRequiresFreshVoiceAlignmentAndPlayback() {
        func state(_ audio: Double? = 10, _ match: Double? = 10, _ speaking: Bool = true,
                   _ playing: Bool = true, _ paused: Bool = false) -> PromptIndicatorState {
            .make(progress: 0.4, level: 0.8, sampleAt: audio, alignedAt: match, speaking: speaking,
                  playing: playing, interactionPaused: paused, completed: false, at: 10.1)
        }
        XCTAssertEqual(state().pulse, 0.8)
        XCTAssertEqual(state(9).pulse, 0)
        XCTAssertEqual(state(10, 8).pulse, 0)
        XCTAssertEqual(state(nil).pulse, 0)
        XCTAssertEqual(state(10, nil).pulse, 0)
        XCTAssertEqual(state(10, 10, false).pulse, 0)
        XCTAssertEqual(state(10, 10, true, false).pulse, 0)
        XCTAssertEqual(state(10, 10, true, true, true).pulse, 0)
        XCTAssertEqual(state().progress, 0.4, "Loudness never changes reading progress")
    }

    func testIndicatorClampsInvalidSignalsAndCompletionDoesNotPulseAsSpeech() {
        let state = PromptIndicatorState.make(progress: .nan, level: .infinity, sampleAt: 10, alignedAt: 10,
                                              speaking: true, playing: true, interactionPaused: false, completed: false, at: 10)
        XCTAssertEqual(state.progress, 0); XCTAssertEqual(state.pulse, 0)
        let complete = PromptIndicatorState.make(progress: 0.98, level: 1, sampleAt: 10, alignedAt: 10,
                                                 speaking: true, playing: true, interactionPaused: false, completed: true, at: 10)
        XCTAssertEqual(complete.progress, 1); XCTAssertEqual(complete.pulse, 0)
    }

    func testQuietSpeechHasVisibleEnvelopeAndDecayIsSlowerThanAttack() {
        var envelope = SpeechLevelEnvelope()
        for _ in 0..<4 { _ = envelope.update(rms: 0.001, deltaTime: 0.05) }
        let quiet = envelope.level
        XCTAssertGreaterThan(quiet, 0.2, "The old -50dB display floor would make this valid quiet voice invisible")
        let after = envelope.update(rms: 0, deltaTime: 0.05)
        XCTAssertGreaterThan(after, quiet * 0.7)
        XCTAssertLessThan(after, quiet)
        for _ in 0..<80 { _ = envelope.update(rms: 0, deltaTime: 0.05) }
        XCTAssertEqual(envelope.level, 0)
    }

    func testMeterMailboxRejectsOldCaptureAfterStopAndRestart() {
        let input = SpeechLevelInput(); let old = UUID(); let new = UUID()
        input.begin(old); input.push(rms: 0.01, at: 1, capture: old)
        XCTAssertEqual(input.latest()?.time, 1)
        input.begin(new); input.push(rms: 0.1, at: 2, capture: old)
        XCTAssertNil(input.latest())
        input.push(rms: 0.002, at: 3, capture: new)
        XCTAssertEqual(input.latest()?.time, 3)
        input.begin(nil); input.push(rms: 1, at: 4, capture: new)
        XCTAssertNil(input.latest())
    }

    func testIPhone16ProGeometryRotatesToBothEdgesAndHidesInPortrait() throws {
        let size = CGSize(width: 874, height: 402)
        let left = try XCTUnwrap(IslandIndicatorGeometry.frame(size: size, cameraOnLeft: true, model: "iPhone17,1"))
        let right = try XCTUnwrap(IslandIndicatorGeometry.frame(size: size, cameraOnLeft: false, model: "iPhone17,1"))
        XCTAssertEqual(left.midY, 201)
        XCTAssertEqual(left.midX + right.midX, size.width, accuracy: 0.001)
        XCTAssertEqual(left.width, right.width)
        XCTAssertGreaterThan(left.height, left.width * 3)
        XCTAssertEqual(left.midX, (7.71 - 2.44) * 402 / 66.57, accuracy: 0.001)
        XCTAssertNil(IslandIndicatorGeometry.frame(size: CGSize(width: 402, height: 874), cameraOnLeft: true, model: "iPhone17,1"))
        let path = IslandIndicatorGeometry.path(in: left)
        var first: CGPoint?
        path.applyWithBlock { pointer in
            if first == nil && pointer.pointee.type == .moveToPoint { first = pointer.pointee.points[0] }
        }
        XCTAssertEqual(try XCTUnwrap(first).x, left.midX, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(first).y, left.minY, accuracy: 0.001)
        XCTAssertEqual(path.boundingBoxOfPath.width, left.width, accuracy: 0.001)
        XCTAssertEqual(path.boundingBoxOfPath.height, left.height, accuracy: 0.001)
    }

    func testCalibrationChangesOnlyGeometryAndNormalizesCorruptValues() throws {
        let invalid = IslandIndicatorCalibration(edgeOffset: .nan, verticalOffset: 999, lengthAdjustment: -999, thicknessAdjustment: .infinity).normalized
        XCTAssertEqual(invalid.edgeOffset, 0); XCTAssertEqual(invalid.verticalOffset, 24)
        XCTAssertEqual(invalid.lengthAdjustment, -24); XCTAssertEqual(invalid.thicknessAdjustment, 0)
        let size = CGSize(width: 874, height: 402)
        let original = try XCTUnwrap(IslandIndicatorGeometry.frame(size: size, cameraOnLeft: false, model: "iPhone17,1"))
        let moved = try XCTUnwrap(IslandIndicatorGeometry.frame(size: size, cameraOnLeft: false, model: "iPhone17,1",
                                                                calibration: .init(edgeOffset: 4, verticalOffset: 3, lengthAdjustment: 6, thicknessAdjustment: 2)))
        XCTAssertEqual(moved.midX, original.midX - 4, accuracy: 0.001)
        XCTAssertEqual(moved.midY, original.midY + 3, accuracy: 0.001)
        XCTAssertEqual(moved.height, original.height + 6, accuracy: 0.001)
        XCTAssertEqual(moved.width, original.width + 2, accuracy: 0.001)
    }

    @MainActor
    func testReadingProgressCanGoBackAfterCompletionWithoutConfusingLateLayoutReports() {
        let progress = PromptReadingProgress()
        progress.update(0.97); progress.complete(); progress.update(0.97)
        XCTAssertTrue(progress.completed); XCTAssertEqual(progress.value, 1)
        progress.update(0.7)
        XCTAssertFalse(progress.completed); XCTAssertEqual(progress.value, 0.7)
        progress.update(0)
        XCTAssertEqual(progress.value, 0)
    }

    @MainActor
    func testCalibrationPersistsLocallyAndIsExcludedFromTransferSettings() throws {
        let suite = "indicator-test-\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.islandCalibration = .init(edgeOffset: 3, lengthAdjustment: 4)
        settings.flush()
        XCTAssertEqual(AppSettings(defaults: defaults).islandCalibration.edgeOffset, 3)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(settings.data), encoding: .utf8))
        XCTAssertFalse(json.contains("islandCalibration"))
        XCTAssertTrue(try JSONDecoder().decode(SettingsData.self, from: Data("{}".utf8)).islandIndicatorEnabled)
    }
}
