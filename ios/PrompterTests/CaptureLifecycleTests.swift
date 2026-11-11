import AVFoundation
import UIKit
import XCTest
@testable import Prompter

private final class CaptureEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var values: [String] { lock.lock(); defer { lock.unlock() }; return entries }
    func add(_ value: String) { lock.lock(); entries.append(value); lock.unlock() }
}

private final class ControlledMicrophone: SpeechAudioCaptureBackend {
    let unblock = DispatchSemaphore(value: 0)
    var started: (() -> Void)?
    var hold = false
    var fail = false
    let name: String
    let events: CaptureEvents
    private var active = false
    init(_ name: String, events: CaptureEvents) { self.name = name; self.events = events }
    func start(receive: @escaping ([Float], Double, TimeInterval) -> Void) throws -> SpeechAudioCaptureStart {
        events.add(Thread.isMainThread ? "main-thread-hardware" : name + ".start")
        active = true
        started?()
        if hold { _ = unblock.wait(timeout: .now() + 3) }
        receive([0.5], 16_000, 1)
        if fail { throw SpeechCaptureError.input }
        return .init(state: snapshot(), configurationObject: nil)
    }
    func snapshot() -> SpeechAudioInputState {
        .init(portIDs: ["builtin"], sampleRate: 16_000, channels: 1, running: active)
    }
    func stop() {
        guard active else { return }
        events.add(Thread.isMainThread ? "main-thread-hardware" : name + ".stop")
        active = false
    }
}

@MainActor
final class CaptureLifecycleTests: XCTestCase {
    func testBlockedStartKeepsMainActorResponsiveAndLateStartStopsBeforeReplacement() async throws {
        let events = CaptureEvents()
        let queue = CaptureWorkQueue(label: "test.microphone-lifecycle")
        let firstBackend = ControlledMicrophone("first", events: events)
        firstBackend.hold = true
        let starting = expectation(description: "hardware start in progress")
        firstBackend.started = { starting.fulfill() }
        let first = SpeechAudioCapture(queue: queue, backend: firstBackend)
        let operation = Task { try await first.start { _, _, _ in events.add("stale-audio") } }
        await fulfillment(of: [starting], timeout: 2)
        let heartbeat = expectation(description: "main actor is responsive during hardware start")
        DispatchQueue.main.async { heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 1)
        operation.cancel()
        first.stop()
        let second = SpeechAudioCapture(queue: queue, backend: ControlledMicrophone("second", events: events))
        let restart = Task { try await second.start { _, _, _ in events.add("fresh-audio") } }
        firstBackend.unblock.signal()
        do { _ = try await operation.value; XCTFail("A cancelled late start must not succeed") }
        catch { XCTAssertTrue(error is CancellationError) }
        _ = try await restart.value
        second.stop()
        await second.waitUntilStopped()
        XCTAssertEqual(events.values, ["first.start", "first.stop", "second.start", "fresh-audio", "second.stop"])
    }

    func testFailedHardwareStartReleasesPartialCaptureBeforeRetry() async throws {
        let events = CaptureEvents()
        let queue = CaptureWorkQueue(label: "test.failed-capture")
        let backend = ControlledMicrophone("failed", events: events)
        backend.fail = true
        let capture = SpeechAudioCapture(queue: queue, backend: backend)
        do { _ = try await capture.start { _, _, _ in }; XCTFail("Expected hardware failure") }
        catch { XCTAssertTrue(error is SpeechCaptureError) }
        capture.stop()
        let retry = SpeechAudioCapture(queue: queue, backend: ControlledMicrophone("retry", events: events))
        _ = try await retry.start { _, _, _ in }
        retry.stop()
        await retry.waitUntilStopped()
        XCTAssertEqual(events.values, ["failed.start", "failed.stop", "retry.start", "retry.stop"])
    }

    func testStoppedCaptureNeverOpensHardwareWhenAwaitedLater() async {
        let events = CaptureEvents()
        let capture = SpeechAudioCapture(queue: CaptureWorkQueue(label: "test.already-stopped"),
                                         backend: ControlledMicrophone("cancelled", events: events))
        capture.stop()
        do { _ = try await capture.start { _, _, _ in }; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await capture.waitUntilStopped()
        XCTAssertTrue(events.values.isEmpty)
    }

    func testCameraFailuresDistinguishResetAndPressureForRecovery() {
        XCTAssertTrue(MirrorCameraFailure.runtime(.mediaServicesWereReset).localizedDescription.contains("重置"))
        XCTAssertTrue(MirrorCameraFailure.interrupted(.videoDeviceNotAvailableDueToSystemPressure).localizedDescription.contains("温度"))
        XCTAssertTrue(MirrorCameraFailure.previewTimeout.localizedDescription.contains("没有传回预览画面"))
    }

    func testCameraRuntimeResetIsReportedAndOldSessionNotificationsAreIgnored() async throws {
        try await assertCameraFailure(notification: AVCaptureSession.runtimeErrorNotification,
            userInfo: [AVCaptureSessionErrorKey: AVError(.mediaServicesWereReset)], expectedMessage: "重置")
    }

    func testCameraPressureInterruptionIsReportedForRecovery() async throws {
        try await assertCameraFailure(notification: AVCaptureSession.wasInterruptedNotification,
            userInfo: [AVCaptureSessionInterruptionReasonKey:
                NSNumber(value: AVCaptureSession.InterruptionReason.videoDeviceNotAvailableDueToSystemPressure.rawValue)],
            expectedMessage: "温度")
    }

    private func assertCameraFailure(notification: Notification.Name, userInfo: [AnyHashable: Any], expectedMessage: String) async throws {
        let session = NSObject()
        let failed = expectation(description: "camera error delivered")
        var messages: [String] = []
        let observer = MirrorCameraSessionObserver(session: session) { error in
            XCTAssertTrue(Thread.isMainThread)
            messages.append(error.localizedDescription)
            failed.fulfill()
        }
        NotificationCenter.default.post(name: notification, object: session, userInfo: userInfo)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertTrue(messages.first?.contains(expectedMessage) == true, messages.joined(separator: " | "))
        observer.stop()
        NotificationCenter.default.post(name: notification, object: session, userInfo: userInfo)
        await Task.yield()
        XCTAssertEqual(messages.count, 1, "Old session callbacks cannot change the stopped view")
    }

    func testQueuedCameraNotificationIsDiscardedAfterStop() async {
        let session = NSObject()
        var failures = 0
        let observer = MirrorCameraSessionObserver(session: session) { _ in failures += 1 }
        NotificationCenter.default.post(name: AVCaptureSession.runtimeErrorNotification, object: session)
        observer.stop()
        await Task.yield()
        XCTAssertEqual(failures, 0)
    }
}
