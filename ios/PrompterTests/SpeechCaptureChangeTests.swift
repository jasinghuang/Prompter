import XCTest
@testable import Prompter

final class SpeechCaptureChangeTests: XCTestCase {
    private let microphone = SpeechAudioInputState(portIDs: ["builtin"], sampleRate: 48_000, channels: 1, running: true)

    func testDelayedCategoryAndOutputNotificationsKeepHealthyMicrophoneRunning() {
        // iPhone 16 Pro reproducer: categoryChange (reason=3) arrives after
        // engine.start(), while the same built-in microphone is still running.
        XCTAssertEqual(SpeechAudioChangeAction.evaluate(.route, previous: microphone, current: microphone), .keepRecording)
        XCTAssertEqual(SpeechAudioChangeAction.evaluate(.configuration, previous: microphone, current: microphone), .keepRecording)
    }

    func testEndedInterruptionDoesNotPauseAnAlreadyHealthySession() {
        XCTAssertEqual(SpeechAudioChangeAction.evaluate(.interruptionEnded, previous: microphone, current: microphone), .keepRecording)
        XCTAssertEqual(SpeechAudioChangeAction.evaluate(.interruptionBegan, previous: microphone, current: microphone), .pause(.interrupted))
    }

    func testRealMicrophoneSwitchAndMissingInputStillPause() {
        var switched = microphone
        switched.portIDs = ["bluetooth-headset"]
        XCTAssertEqual(SpeechAudioChangeAction.evaluate(.route, previous: microphone, current: switched), .pause(.inputChanged))
        var missing = microphone
        missing.portIDs = []
        XCTAssertEqual(SpeechAudioChangeAction.evaluate(.route, previous: microphone, current: missing), .pause(.input))
    }

    func testStoppedEngineAndHardwareFormatChangesRebuildInsteadOfFalseInterruption() {
        var stopped = microphone
        stopped.running = false
        XCTAssertEqual(SpeechAudioChangeAction.evaluate(.configuration, previous: microphone, current: stopped), .rebuildEngine)
        var changedRate = microphone
        changedRate.sampleRate = 44_100
        XCTAssertEqual(SpeechAudioChangeAction.evaluate(.configuration, previous: microphone, current: changedRate), .rebuildEngine)
        var stereo = microphone
        stereo.channels = 2
        XCTAssertEqual(SpeechAudioChangeAction.evaluate(.configuration, previous: microphone, current: stereo), .rebuildEngine)
    }

    func testMediaServiceLossCannotBeIgnoredAsAHealthyRoute() {
        XCTAssertEqual(SpeechAudioChangeAction.evaluate(.mediaServices, previous: microphone, current: microphone), .pause(.mediaServices))
    }

    func testRecoveryIsBoundedButAllowsLaterIndependentChanges() {
        var budget = SpeechCaptureRecoveryBudget()
        XCTAssertTrue(budget.request(at: 10))
        XCTAssertTrue(budget.request(at: 10.5))
        XCTAssertFalse(budget.request(at: 11))
        XCTAssertTrue(budget.request(at: 15.1))
    }
}
