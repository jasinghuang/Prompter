import XCTest
@testable import Prompter

@MainActor
private final class ControlledAudioSession: SpeechAudioSessionBackend {
    var events: [String] = []
    var activationStarted: (() -> Void)?
    var deactivationFinished: (() -> Void)?
    var holdFirstActivation = true
    var failActivation = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var activations = 0

    func activate() async throws {
        activations += 1
        events.append("activate")
        if holdFirstActivation && activations == 1 {
            await withCheckedContinuation {
                continuation = $0
                activationStarted?()
            }
        } else { activationStarted?() }
        if failActivation { throw SpeechCaptureError.input }
    }

    func finishActivation() {
        continuation?.resume()
        continuation = nil
    }

    func deactivate() async throws {
        events.append("deactivate")
        deactivationFinished?()
    }
}

@MainActor
final class SpeechAudioSessionTests: XCTestCase {
    func testDeactivationWaitsForEngineTeardownBeforeNextActivation() async throws {
        let backend = ControlledAudioSession()
        backend.holdFirstActivation = false
        let coordinator = SpeechAudioSessionCoordinator(backend: backend)
        let owner = UUID()
        try await coordinator.activate(owner: owner)
        let cleanupStarted = expectation(description: "capture graph is stopping")
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        coordinator.release(owner: owner, after: {
            cleanupStarted.fulfill()
            for await _ in stream { }
        })
        await fulfillment(of: [cleanupStarted], timeout: 2)
        let next = UUID()
        let restart = Task { try await coordinator.activate(owner: next) }
        XCTAssertEqual(backend.events, ["activate"], "Audio deactivation must not race a blocked graph teardown")
        continuation.finish()
        try await restart.value
        XCTAssertEqual(backend.events, ["activate", "deactivate", "activate"])
        coordinator.release(owner: next)
        await coordinator.waitForIdle()
    }

    func testRapidStopAndRestartSerializesHardwareAndIgnoresStaleRelease() async throws {
        let backend = ControlledAudioSession()
        let started = expectation(description: "activation is in flight")
        backend.activationStarted = { started.fulfill() }
        let coordinator = SpeechAudioSessionCoordinator(backend: backend)
        let firstOwner = UUID(), secondOwner = UUID()
        let first = Task { try await coordinator.activate(owner: firstOwner) }
        await fulfillment(of: [started], timeout: 3)
        backend.activationStarted = nil
        coordinator.release(owner: firstOwner)
        let secondScheduled = expectation(description: "restart requested")
        let second = Task {
            secondScheduled.fulfill()
            try await coordinator.activate(owner: secondOwner)
        }
        await fulfillment(of: [secondScheduled], timeout: 3)
        XCTAssertEqual(backend.events, ["activate"], "Stop and restart must not block the UI or overlap hardware calls")
        backend.finishActivation()
        try await first.value
        try await second.value
        await coordinator.waitForIdle()
        XCTAssertEqual(backend.events, ["activate", "deactivate", "activate"])
        coordinator.release(owner: firstOwner)
        await coordinator.waitForIdle()
        XCTAssertEqual(backend.events, ["activate", "deactivate", "activate"], "An old session cannot deactivate its replacement")
        coordinator.release(owner: secondOwner)
        coordinator.release(owner: secondOwner)
        await coordinator.waitForIdle()
        XCTAssertEqual(backend.events, ["activate", "deactivate", "activate", "deactivate"])
    }

    func testCancellationDuringActivationAlwaysReleasesAfterCompletion() async throws {
        let backend = ControlledAudioSession()
        let started = expectation(description: "activation started")
        let released = expectation(description: "cancelled activation released")
        backend.activationStarted = { started.fulfill() }
        backend.deactivationFinished = { released.fulfill() }
        let coordinator = SpeechAudioSessionCoordinator(backend: backend)
        let operation = Task { try await coordinator.activate(owner: UUID()) }
        await fulfillment(of: [started], timeout: 3)
        operation.cancel()
        XCTAssertEqual(backend.events, ["activate"])
        backend.finishActivation()
        do { try await operation.value; XCTFail("Cancelled activation must not succeed") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [released], timeout: 3)
        await coordinator.waitForIdle()
        XCTAssertEqual(backend.events, ["activate", "deactivate"])
    }

    func testFailedActivationCleansUpAndAllowsRetry() async throws {
        let backend = ControlledAudioSession()
        backend.holdFirstActivation = false
        backend.failActivation = true
        let coordinator = SpeechAudioSessionCoordinator(backend: backend)
        let first = UUID()
        do { try await coordinator.activate(owner: first); XCTFail("Expected activation error") }
        catch { XCTAssertTrue(error is SpeechCaptureError) }
        coordinator.release(owner: first)
        await coordinator.waitForIdle()
        XCTAssertEqual(backend.events, ["activate", "deactivate"])
        backend.failActivation = false
        let next = UUID()
        try await coordinator.activate(owner: next)
        coordinator.release(owner: next)
        await coordinator.waitForIdle()
        XCTAssertEqual(backend.events, ["activate", "deactivate", "activate", "deactivate"])
    }

    func testAlreadyCancelledActivationDoesNotTouchAudioHardware() async {
        let backend = ControlledAudioSession()
        let coordinator = SpeechAudioSessionCoordinator(backend: backend)
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await coordinator.activate(owner: UUID())
        }
        do { try await operation.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await coordinator.waitForIdle()
        XCTAssertTrue(backend.events.isEmpty)
    }

    func testStoppingControllerDuringActivationDoesNotOpenMicrophoneAfterwards() async throws {
        let backend = ControlledAudioSession()
        let started = expectation(description: "controller waiting for audio activation")
        backend.activationStarted = { started.fulfill() }
        let coordinator = SpeechAudioSessionCoordinator(backend: backend)
        let controller = SpeechFollowController(requestPermission: { true }, audioSession: coordinator)
        let model = try XCTUnwrap(Bundle.main.url(forResource: "ParaformerModel", withExtension: nil))
        let operation = Task { await controller.start(content: "今天开始本地语音跟随", startUTF16: 0, modelDirectory: model) }
        await fulfillment(of: [started], timeout: 5)
        controller.stop()
        controller.stop()
        XCTAssertEqual(controller.status, "轻点正文开始语音跟随")
        backend.finishActivation()
        await operation.value
        await coordinator.waitForIdle()
        XCTAssertEqual(backend.events, ["activate", "deactivate"])
        XCTAssertFalse(controller.isAdvancing)
        XCTAssertNil(controller.target)
        XCTAssertNil(controller.errorMessage)
    }
}
