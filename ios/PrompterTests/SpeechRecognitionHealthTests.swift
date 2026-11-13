import XCTest
@testable import Prompter

private actor NativeShutdownGate {
    let started: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    init(started: XCTestExpectation) { self.started = started }
    func wait() async {
        calls += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
    func finish() { continuation?.resume(); continuation = nil }
}

private final class HeldNativeRecognizer: LocalSpeechRecognizer, SpeechRecognizerShutdown {
    let gate: NativeShutdownGate
    init(gate: NativeShutdownGate) { self.gate = gate }
    func accept(_ samples: [Float]) throws -> SpeechRecognitionResult? { nil }
    func resetForReposition() throws { }
    func shutdown() async { await gate.wait() }
}

private final class HeldReadyRecognizer: LocalSpeechRecognizer, SpeechRecognizerReadiness {
    var readiness: Task<Void, Error>
    let next: Task<Void, Error>
    init(first: Task<Void, Error>, next: Task<Void, Error>) { readiness = first; self.next = next }
    func accept(_ samples: [Float]) throws -> SpeechRecognitionResult? { nil }
    func resetForReposition() throws { readiness = next }
}

final class SpeechRecognitionHealthTests: XCTestCase {
    func testSilenceDoesNotImplyBrokenRecognitionService() {
        var health = SpeechRecognitionHealth()
        for i in 0..<1000 { health.observeAudio(at: Double(i) * 0.1, voice: false) }
        XCTAssertFalse(health.hasTimedOut(at: 100))
        XCTAssertFalse(health.isWaitingForText(at: 100))
    }

    func testUnansweredSpeechIsShownThenTimesOutEvenAfterSpeakerPauses() {
        var health = SpeechRecognitionHealth()
        for i in 0..<30 { health.observeAudio(at: Double(i) * 0.1, voice: true) }
        XCTAssertTrue(health.isWaitingForText(at: 3))
        XCTAssertFalse(health.hasTimedOut(at: 9.9))
        health.observeAudio(at: 3, voice: false)
        XCTAssertTrue(health.hasTimedOut(at: 10))
    }

    func testShortVoiceBlipCannotTriggerServiceFailure() {
        var health = SpeechRecognitionHealth()
        health.observeAudio(at: 0, voice: false)
        health.observeAudio(at: 0.1, voice: true)
        health.observeAudio(at: 0.2, voice: false)
        XCTAssertFalse(health.hasTimedOut(at: 100))
    }

    func testBriefNoiseBeforeLongSilenceDoesNotConsumeNextSpeechDeadline() {
        var health = SpeechRecognitionHealth()
        health.observeAudio(at: 0, voice: false)
        health.observeAudio(at: 0.1, voice: true)
        for i in 0..<30 { health.observeAudio(at: 100 + Double(i) * 0.1, voice: true) }
        XCTAssertFalse(health.hasTimedOut(at: 109.9))
        XCTAssertTrue(health.hasTimedOut(at: 110))
    }

    func testTextResponseResetsPendingSpeechRegardlessOfScriptMatch() {
        var health = SpeechRecognitionHealth()
        for i in 0..<30 { health.observeAudio(at: Double(i) * 0.1, voice: true) }
        health.receivedText()
        for i in 30..<1000 { health.observeAudio(at: Double(i) * 0.1, voice: false) }
        XCTAssertFalse(health.hasTimedOut(at: 100))
        XCTAssertFalse(health.isWaitingForText(at: 100))
    }

    func testFreshSpeechAfterLongPauseGetsItsOwnDeadline() {
        var health = SpeechRecognitionHealth()
        for i in 0..<30 { health.observeAudio(at: Double(i) * 0.1, voice: true) }
        health.receivedText()
        for i in 0..<30 { health.observeAudio(at: 100 + Double(i) * 0.1, voice: true) }
        XCTAssertFalse(health.hasTimedOut(at: 109.9))
        XCTAssertTrue(health.hasTimedOut(at: 110))
    }

    func testSegmentedModelHasLongerAllowanceAndInvalidTimestampsAreIgnored() {
        var health = SpeechRecognitionHealth(timeout: 15)
        health.observeAudio(at: .nan, voice: true)
        for i in 0..<30 { health.observeAudio(at: Double(i) * 0.1, voice: true) }
        health.observeAudio(at: -10, voice: true)
        XCTAssertFalse(health.hasTimedOut(at: 10))
        XCTAssertTrue(health.hasTimedOut(at: 15))
    }

    @MainActor
    func testPipelineWaitsForNativeShutdownAndRepeatedStopKeepsTheBarrier() async throws {
        let started = expectation(description: "native service cleanup started")
        let gate = NativeShutdownGate(started: started)
        let recognizer = HeldNativeRecognizer(gate: gate)
        let pipeline = SpeechRecognitionPipeline()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pipeline.prepare(directory: FileManager.default.temporaryDirectory, kind: .apple,
                             appleFactory: { recognizer }) { continuation.resume(with: $0) }
        }
        pipeline.stop()
        pipeline.stop()
        await fulfillment(of: [started], timeout: 3)
        var finished = false
        let waiting = Task { await pipeline.waitUntilStopped(); finished = true }
        await Task.yield()
        XCTAssertFalse(finished, "Replacement must not race an unfinished native service cleanup")
        await gate.finish()
        await waiting.value
        XCTAssertTrue(finished)
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
    }
    @MainActor
    func testPreparationWaitsForReadinessAndStoppedPipelineCannotBecomeReady() async {
        let started = expectation(description: "preparation started")
        let gate = NativeShutdownGate(started: started)
        let task = Task<Void, Error> { await gate.wait() }
        let recognizer = HeldReadyRecognizer(first: task, next: task)
        let pipeline = SpeechRecognitionPipeline()
        let completed = expectation(description: "preparation completed")
        pipeline.prepare(directory: FileManager.default.temporaryDirectory, kind: .apple, appleFactory: { recognizer }) { result in
            if case .success = result { XCTFail("Stopped preparation must not become ready") }
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 3)
        pipeline.stop()
        await gate.finish()
        await fulfillment(of: [completed], timeout: 3)
        await pipeline.waitUntilStopped()
    }

    @MainActor
    func testResumeKeepsAudioSuspendedUntilReplacementRecognizerIsReady() async throws {
        let started = expectation(description: "replacement preparation started")
        let gate = NativeShutdownGate(started: started)
        let task = Task<Void, Error> { await gate.wait() }
        let recognizer = HeldReadyRecognizer(first: Task {}, next: task)
        let pipeline = SpeechRecognitionPipeline()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pipeline.prepare(directory: FileManager.default.temporaryDirectory, kind: .apple,
                             appleFactory: { recognizer }) { continuation.resume(with: $0) }
        }
        pipeline.suspend()
        let completed = expectation(description: "replacement ready")
        let audio = expectation(description: "suspended audio must not be processed")
        audio.isInverted = true
        pipeline.onEvent = { _ in audio.fulfill() }
        pipeline.resume { result in
            if case .failure(let error) = result { XCTFail("Resume failed: \(error)") }
            completed.fulfill()
        }
        await fulfillment(of: [started], timeout: 3)
        pipeline.submit(samples: Array(repeating: 0, count: 1024), sampleRate: 48_000,
                        capturedAt: ProcessInfo.processInfo.systemUptime)
        await fulfillment(of: [audio], timeout: 0.15)
        await gate.finish()
        await fulfillment(of: [completed], timeout: 3)
        pipeline.stop()
        await pipeline.waitUntilStopped()
    }

}
