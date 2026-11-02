import Combine
import CoreMotion
import XCTest
@testable import Prompter

@MainActor
final class AirPodsConnectionTests: XCTestCase {
    private final class Clock { var now = 100.0 }
    private final class Source: HeadphoneMotionSource {
        var available = true
        var authorization: CMAuthorizationStatus = .authorized
        var starts = 0, stops = 0, observations = 0
        var onStartDisconnect = false
        var queue: OperationQueue?
        var motion: (@Sendable (HeadMotionSample?, String?) -> Void)?
        var connection: (@Sendable (Bool) -> Void)?
        func start(on queue: OperationQueue,
                   motion: @escaping @Sendable (HeadMotionSample?, String?) -> Void,
                   connection: @escaping @Sendable (Bool) -> Void) {
            starts += 1; self.queue = queue; self.motion = motion; self.connection = connection
            if onStartDisconnect { connection(false) }
        }
        func observeConnections(_ connection: @escaping @Sendable (Bool) -> Void) {
            observations += 1; self.connection = connection
        }
        func stop() {
            stops += 1
            connection?(false) // Model a native notification queued by teardown.
            // Retain handlers deliberately: tests can deliver delayed callbacks after stop.
        }
        func emit(_ sample: HeadMotionSample? = nil, error: String? = nil) {
            let receive = motion
            queue?.addOperation { receive?(sample, error) }
        }
    }
    @MainActor private final class Factory {
        var sources: [Source] = []
        var disconnectOnStart = false
        var authorization: CMAuthorizationStatus = .authorized
        func make() -> Source {
            let source = Source(); source.onStartDisconnect = disconnectOnStart
            source.authorization = authorization
            sources.append(source); return source
        }
    }
    private func sample(at time: Double = 100, pitch: Double = 0, rate: Double = 0) -> HeadMotionSample {
        let angle = pitch * .pi / 180
        return .init(time: time, gravity: .init(x: 0, y: sin(angle), z: -cos(angle)),
                     rate: .init(x: rate * .pi / 180, y: 0, z: 0), acceleration: .zero, sensorLocation: 1)
    }
    private var profile: HeadGestureCalibration {
        .init(neutral: .init(x: 0, y: 0, z: -1), pitchAxis: .init(x: 1, y: 0, z: 0),
              rollAxis: .init(x: 0, y: 1, z: 0), yawAxis: .init(x: 0, y: 0, z: 1),
              ranges: [20, 20, 20, 20, 30, 30].map { $0 * .pi / 180 }, sensorLocation: 1)
    }
    private func settle() async { try? await Task.sleep(for: .milliseconds(30)) }
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    func testDisabledFeatureDoesNotCreateNativeManager() {
        let factory = Factory()
        let controller = AirPodsNodController(sourceFactory: { factory.make() })
        controller.configure(profile: nil, suspended: true)
        controller.setDiagnosticsRecording(true)
        controller.markUnresponsiveNod()
        controller.setDiagnosticsRecording(false)
        controller.shutdown()
        XCTAssertTrue(factory.sources.isEmpty)
    }

    func testCapabilityDoesNotClaimLiveAirPodsConnection() {
        let factory = Factory()
        let controller = AirPodsNodController(sourceFactory: { factory.make() })
        defer { controller.shutdown() }
        controller.beginCalibration()
        XCTAssertTrue(controller.available)
        XCTAssertFalse(controller.motionReady)
        XCTAssertFalse(controller.status.contains("已连接"))
        XCTAssertTrue(factory.sources.allSatisfy { $0.starts == 0 })
    }

    func testStartDisconnectHintDoesNotAbortFirstCalibrationMovement() async {
        let factory = Factory(); factory.disconnectOnStart = true
        let clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.beginCalibration(); controller.startCapture()
        await settle()
        XCTAssertTrue(controller.capturing)
        XCTAssertNil(controller.calibrationError)
        XCTAssertFalse(controller.motionReady)
        let source = factory.sources.last!
        // Stillness, a comfortable down-and-return, then stable neutral.
        for t in stride(from: 0.0, through: 3.0, by: 0.02) {
            let u = (t - 1.1) / 0.65
            let active = (0...1).contains(u)
            source.emit(sample(at: 100 + t,
                pitch: active ? 16 * pow(sin(.pi * u), 2) : 0,
                rate: active ? 16 * .pi / 0.65 * sin(2 * .pi * u) : 0))
        }
        await waitUntil { controller.captures.count == 1 }
        XCTAssertNil(controller.calibrationError)
        XCTAssertFalse(controller.capturing)
        XCTAssertFalse(controller.status.contains("已断开"))
    }

    func testDelayedFirstSampleHasStartupGraceAndConfirmsReady() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.beginCalibration(); controller.startCapture()
        clock.now += 5
        controller.checkStreamHealth()
        factory.sources.last?.connection?(false)
        await settle()
        XCTAssertTrue(controller.capturing); XCTAssertNil(controller.calibrationError)
        factory.sources.last?.emit(sample(at: clock.now))
        await waitUntil { controller.motionReady }
        XCTAssertNil(controller.calibrationError)
        XCTAssertEqual(controller.calibrationProgress.stage, .preparing)
    }

    func testOldConnectionAndErrorCallbacksCannotStopNewSession() async {
        let factory = Factory()
        let controller = AirPodsNodController(sourceFactory: { factory.make() })
        defer { controller.shutdown() }
        controller.beginCalibration(); controller.startCapture()
        let old = factory.sources.last!
        controller.interruptCalibration()
        controller.startCapture()
        let current = factory.sources.last!
        XCTAssertFalse(old === current)
        old.connection?(false); old.connection?(true)
        old.emit(error: "过期数据错误")
        current.emit(sample())
        await waitUntil { controller.motionReady }
        await settle()
        XCTAssertTrue(controller.capturing); XCTAssertNil(controller.calibrationError)
        XCTAssertEqual(current.stops, 0)
    }

    func testFreshSamplesSurviveDisconnectHintAndMissingCallback() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.beginCalibration(); controller.startCapture()
        let source = factory.sources.last!
        source.emit(sample())
        await waitUntil { controller.motionReady }
        source.connection?(false); source.emit(nil)
        await settle()
        controller.checkStreamHealth()
        XCTAssertTrue(controller.capturing); XCTAssertNil(controller.calibrationError)
        XCTAssertTrue(controller.motionReady)
        XCTAssertEqual(source.stops, 0)
    }

    func testNoInitialDataReportsUnconfirmedStreamNotBluetoothDisconnection() {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.beginCalibration(); controller.startCapture()
        clock.now += HeadMotionStreamHealth.startupGrace + 0.1
        controller.checkStreamHealth()
        XCTAssertFalse(controller.capturing)
        XCTAssertTrue(controller.calibrationError?.contains("尚未收到") == true)
        XCTAssertFalse(controller.status.contains("已断开"))
    }

    func testSustainedDataLossStopsRecognitionAndReconnectionCanRecover() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        var nods = 0
        let subscription = controller.nods.sink { _ in nods += 1 }
        defer { subscription.cancel() }
        controller.configure(profile: profile, suspended: false)
        factory.sources.last?.emit(sample())
        await waitUntil { controller.motionReady }
        clock.now += HeadMotionStreamHealth.interruptionGrace + 0.1
        controller.checkStreamHealth()
        XCTAssertFalse(controller.motionReady)
        XCTAssertTrue(controller.status.contains("持续中断"))
        let observer = factory.sources.last!
        XCTAssertEqual(observer.observations, 1)
        observer.connection?(true)
        await waitUntil { factory.sources.last?.starts == 1 }
        factory.sources.last?.emit(sample(at: clock.now))
        await waitUntil { controller.motionReady }
        XCTAssertEqual(nods, 0)
    }

    func testPermissionPromptDoesNotConsumeFirstSampleGrace() {
        let factory = Factory(), clock = Clock()
        factory.authorization = .notDetermined
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.beginCalibration(); controller.startCapture()
        clock.now += 30; controller.checkStreamHealth()
        clock.now += 30; controller.checkStreamHealth()
        XCTAssertTrue(controller.capturing); XCTAssertNil(controller.calibrationError)
        factory.sources.last?.authorization = .authorized
        clock.now += 1; controller.checkStreamHealth()
        clock.now += 5; controller.checkStreamHealth()
        XCTAssertTrue(controller.capturing); XCTAssertNil(controller.calibrationError)
    }

    func testPermissionRevocationHasSpecificMessageAndSettingsAction() {
        let factory = Factory()
        let controller = AirPodsNodController(sourceFactory: { factory.make() })
        defer { controller.shutdown() }
        controller.beginCalibration(); controller.startCapture()
        factory.sources.last?.authorization = .denied
        controller.checkStreamHealth()
        XCTAssertFalse(controller.capturing)
        XCTAssertTrue(controller.permissionDenied)
        XCTAssertTrue(controller.calibrationError?.contains("运动权限") == true)
    }

    func testShutdownIgnoresPendingConnectionNotifications() async {
        let factory = Factory()
        let controller = AirPodsNodController(sourceFactory: { factory.make() })
        controller.beginCalibration(); controller.startCapture()
        let old = factory.sources.last!
        controller.endCalibration()
        old.connection?(false); old.emit(error: "过期错误")
        await settle()
        XCTAssertFalse(controller.motionReady)
        XCTAssertFalse(controller.capturing)
        XCTAssertNil(controller.calibrationError)
        XCTAssertTrue(factory.sources.last === old)
    }

    private func movement(_ source: Source, action: HeadCalibrationAction, start: Double, duration: Double = 1, amplitude: Double = 20, sensor: Int = 1) {
        for t in stride(from: 0.0, through: 3.5, by: 0.02) {
            var s = sample(at: start + t)
            s.sensorLocation = sensor
            let u = (t - 1.1) / duration
            if (0...1).contains(u) {
                let sign = [HeadCalibrationAction.up, .tiltLeft, .turnLeft].contains(action) ? -1.0 : 1.0
                let a = (action.isTurn ? 30.0 : amplitude) * sign * .pi / 180
                let angle = a * pow(sin(.pi * u), 2)
                let rate = a * .pi / duration * sin(2 * .pi * u)
                switch action {
                case .down, .up: s.gravity = .init(x: 0, y: sin(angle), z: -cos(angle)); s.rate.x = rate
                case .tiltRight, .tiltLeft: s.gravity = .init(x: -sin(angle), y: 0, z: -cos(angle)); s.rate.y = rate
                case .turnRight, .turnLeft: s.attitude = .init(z: sin(angle / 2), w: cos(angle / 2)); s.rate.z = rate
                }
            }
            source.emit(s)
        }
    }

    func testAllSixActionsAndVerificationUseOneNativeStream() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.setDiagnosticsRecording(true)
        controller.beginCalibration(); controller.startCapture()
        let source = factory.sources.last!
        for action in HeadCalibrationAction.allCases {
            if action != .down { controller.startCapture() }
            movement(source, action: action, start: 100 + Double(action.rawValue) * 4)
            await waitUntil { !controller.capturing }
            XCTAssertNil(controller.calibrationError)
            XCTAssertTrue(factory.sources.last === source)
            XCTAssertEqual(source.starts, 1); XCTAssertEqual(source.stops, 0)
        }
        XCTAssertEqual(controller.captures.count, 6)
        XCTAssertNotNil(controller.candidate)
        XCTAssertNil(controller.calibrationAction)
        for index in 0..<3 {
            controller.startTest()
            XCTAssertEqual(controller.calibrationProgress.stage, .preparing, "先等待静稳，不能提前提示开始动作")
            movement(source, action: .down, start: 124 + Double(index) * 4, duration: 0.65)
            await waitUntil { !controller.capturing }
            XCTAssertEqual(controller.habitSamples.count, index + 1)
            XCTAssertFalse(controller.verified, "训练不等于独立验证通过")
        }
        let learned = controller.candidate?.habit
        XCTAssertNotNil(learned)
        controller.startTest()
        movement(source, action: .down, start: 136, duration: 0.65, amplitude: 28)
        await waitUntil { controller.verified }
        XCTAssertEqual(controller.candidate?.habit, learned, "最终验证不能再修改拟合参数")
        XCTAssertEqual(controller.calibrationProgress.stage, .verified)
        XCTAssertEqual(source.starts, 1)
        XCTAssertEqual(controller.diagnostics.counts.detected, 0)
        XCTAssertEqual(controller.diagnostics.counts.applied, 0)
        XCTAssertEqual(controller.diagnostics.counts.rejected, 0, "校准和最终试点头不进入播放诊断计数")
    }

    func testEarHandoffReusesCalibrationWithoutRestartOrPlaybackFromTheSwitch() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.configure(profile: profile, suspended: false)
        controller.setDiagnosticsRecording(true)
        var events = 0
        let subscription = controller.nods.sink { _ in events += 1 }
        defer { subscription.cancel() }
        let source = factory.sources.last!
        for t in stride(from: 100.0, through: 101.2, by: 0.02) { source.emit(sample(at: t)) }
        await waitUntil { controller.status.contains("已就绪") }
        var changed = sample(at: 101.22, pitch: 8); changed.sensorLocation = 2
        source.emit(changed)
        await waitUntil { controller.diagnostics.counts.sensorChanges == 1 }
        XCTAssertEqual(events, 0)
        XCTAssertEqual(source.starts, 1); XCTAssertEqual(source.stops, 0)
        XCTAssertFalse(controller.status.contains("重新校准"))
        movement(source, action: .down, start: 102, duration: 0.8, amplitude: 8, sensor: 2)
        await waitUntil { events == 1 }
        XCTAssertEqual(controller.diagnostics.counts.serviceIssues, 0)
        XCTAssertEqual(controller.diagnostics.counts.sensorChanges, 1)
        controller.configure(profile: profile, suspended: true)
        controller.configure(profile: profile, suspended: false)
        movement(factory.sources.last!, action: .down, start: 106, duration: 0.8, amplitude: 8, sensor: 2)
        await waitUntil { events == 2 }
        XCTAssertEqual(controller.diagnostics.counts.sensorChanges, 1, "设置回来不重复统计同一耳的来源变化")
    }

    func testSkippingHabitDuringCaptureKeepsSixActionsAndDropsOldLearningEvents() async {
        let factory = Factory()
        let controller = AirPodsNodController(sourceFactory: { factory.make() })
        defer { controller.shutdown() }
        controller.beginCalibration()
        for action in HeadCalibrationAction.allCases {
            controller.startCapture()
            movement(factory.sources.last!, action: action, start: 100 + Double(action.rawValue) * 4)
            await waitUntil { !controller.capturing }
        }
        controller.startTest()
        movement(factory.sources.last!, action: .down, start: 124, duration: 0.65)
        controller.skipHabitLearning()
        XCTAssertTrue(controller.habitSkipped)
        movement(factory.sources.last!, action: .down, start: 128, duration: 0.65)
        await waitUntil { controller.verified }
        XCTAssertEqual(controller.captures.count, 6)
        XCTAssertNil(controller.candidate?.habit)
        XCTAssertEqual(controller.habitSamples.count, 0)
    }

    func testHandoffCoincidingWithHeartbeatIsCountedOncePerActualChange() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.configure(profile: profile, suspended: false)
        controller.setDiagnosticsRecording(true)
        let source = factory.sources.last!
        source.emit(sample(at: 100))
        await waitUntil { controller.motionReady }
        for i in 1...3 {
            var s = sample(at: 100 + Double(i) * 0.5); s.sensorLocation = i % 2 == 1 ? 2 : 1
            source.emit(s)
        }
        await waitUntil { controller.diagnostics.counts.sensorChanges == 3 }
        XCTAssertEqual(controller.diagnostics.counts.serviceIssues, 0)
        XCTAssertEqual(source.starts, 1); XCTAssertEqual(source.stops, 0)
    }

    func testWrongPairOnlyRetriesThatActionAndPreservesCompletedCaptures() async {
        let factory = Factory()
        let controller = AirPodsNodController(sourceFactory: { factory.make() })
        defer { controller.shutdown() }
        controller.beginCalibration(); controller.startCapture()
        let source = factory.sources.last!
        movement(source, action: .down, start: 100)
        await waitUntil { !controller.capturing }
        let originalDown = controller.captures[0]
        controller.startCapture()
        movement(source, action: .down, start: 104) // Incorrectly repeat down for the up instruction.
        await waitUntil { controller.calibrationProblem != nil }
        XCTAssertEqual(controller.calibrationAction, .up)
        XCTAssertEqual(controller.completedCalibrationActions, [.down])
        XCTAssertEqual(controller.captures.count, 2)
        controller.retryCalibration()
        movement(source, action: .up, start: 108)
        await waitUntil { !controller.capturing }
        XCTAssertNil(controller.calibrationProblem)
        XCTAssertNil(controller.calibrationError)
        XCTAssertEqual(controller.calibrationAction, .tiltRight)
        XCTAssertEqual(controller.captures.count, 2, "重试替换当前记录，不追加重复动作")
        XCTAssertEqual(controller.captures[0].axis, originalDown.axis)
        XCTAssertEqual(controller.captures[0].angle, originalDown.angle)
        XCTAssertTrue(factory.sources.last === source)
    }

    func testUninitializedCalibrationFrameDoesNotBecomeUserFailureOrReadyState() async {
        let factory = Factory()
        let controller = AirPodsNodController(sourceFactory: { factory.make() })
        defer { controller.shutdown() }
        controller.beginCalibration(); controller.startCapture()
        let source = factory.sources.last!
        var bad = sample(); bad.gravity = .zero
        source.emit(bad)
        await settle()
        XCTAssertTrue(controller.capturing)
        XCTAssertFalse(controller.motionReady)
        XCTAssertNil(controller.calibrationError)
        movement(source, action: .down, start: 101)
        await waitUntil { !controller.capturing }
        XCTAssertEqual(controller.captures.count, 1)
        XCTAssertNil(controller.calibrationError)
    }

    func testPlaybackStatusRequiresArmingAndExplainsWalkingOrStartingPosture() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.configure(profile: profile, suspended: false)
        let source = factory.sources.last!
        source.emit(sample())
        await waitUntil { controller.motionReady }
        XCTAssertFalse(controller.status.contains("已就绪"), "收到数据不等于已经进入手势待命")
        for t in stride(from: 100.02, through: 101.2, by: 0.02) { source.emit(sample(at: t)) }
        await waitUntil { controller.status.contains("已就绪") }
        var walking = sample(at: 101.8); walking.locomotionDetected = true
        source.emit(walking)
        await waitUntil { controller.status.contains("走动") }
        for t in stride(from: 102.2, through: 103.5, by: 0.02) { source.emit(sample(at: t, pitch: 45)) }
        await waitUntil { controller.status.contains("看向屏幕正面") }
    }

    func testRejectedPlaybackAttemptRemainsInspectableInSettingsAndClearsOnSuccess() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.configure(profile: profile, suspended: false)
        let source = factory.sources.last!
        movement(source, action: .down, start: 100, duration: 0.8, amplitude: 4)
        await waitUntil { controller.lastAttemptHint != nil }
        XCTAssertTrue(controller.lastAttemptHint?.contains("幅度较小") == true)
        controller.configure(profile: profile, suspended: true)
        XCTAssertTrue(controller.lastAttemptHint?.contains("幅度较小") == true)
        controller.configure(profile: profile, suspended: false)
        movement(factory.sources.last!, action: .down, start: 104, duration: 0.8, amplitude: 8)
        await waitUntil { controller.lastAttemptHint == nil }
    }

    func testDiagnosticsCountActualUIAcknowledgmentsAndKeepMarksAcrossSettings() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.configure(profile: profile, suspended: false)
        controller.setDiagnosticsRecording(true)
        let subscription = controller.nods.sink { trigger in controller.confirmNodApplied(trigger, playing: true) }
        defer { subscription.cancel() }
        movement(factory.sources.last!, action: .down, start: 100, duration: 0.8, amplitude: 8)
        clock.now = 104
        await waitUntil { controller.diagnostics.counts.applied == 1 }
        XCTAssertEqual(controller.diagnostics.counts.detected, 1)
        controller.configure(profile: profile, suspended: true)
        controller.markUnresponsiveNod(); controller.markLastNodFalsePositive()
        XCTAssertEqual(controller.diagnostics.counts.manualMisses, 1)
        XCTAssertEqual(controller.diagnostics.counts.manualFalsePositives, 1)
        XCTAssertNotEqual(controller.diagnostics.entries.first { $0.kind == .manualMiss }?.condition, .suspended)
        controller.undoDiagnosticMark()
        XCTAssertEqual(controller.diagnostics.counts.manualFalsePositives, 0)
    }

    func testDiagnosticsObserveSuppressionWithoutInventingFailedAttempts() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.configure(profile: profile, suspended: false)
        controller.setDiagnosticsRecording(true)
        controller.rearm()
        factory.sources.last!.emit(sample(at: 100.1))
        await waitUntil { controller.motionReady }
        XCTAssertEqual(controller.diagnostics.lastPlaybackObservation?.condition, .manualSuppression)
        XCTAssertEqual(controller.diagnostics.counts.detected, 0)
        XCTAssertEqual(controller.diagnostics.counts.rejected, 0)
        XCTAssertEqual(controller.diagnostics.counts.manualMisses, 0)
    }

    func testDiagnosticsClassifyServiceLossAndIgnoreStoppedStreamCallbacks() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.configure(profile: profile, suspended: false)
        controller.setDiagnosticsRecording(true)
        let source = factory.sources.last!
        source.emit(sample())
        await waitUntil { controller.motionReady }
        clock.now = 104
        controller.checkStreamHealth()
        XCTAssertEqual(controller.diagnostics.counts.serviceIssues, 1)
        XCTAssertEqual(controller.diagnostics.entries.first { $0.kind == .serviceIssue }?.reason, "interrupted")
        source.emit(error: "上一轮服务错误")
        source.emit(sample(at: 104.5, pitch: 20, rate: 50))
        await settle()
        XCTAssertEqual(controller.diagnostics.counts.serviceIssues, 1)
        XCTAssertEqual(controller.diagnostics.counts.detected, 0)
    }

    func testDiagnosticsCaptureShortBlockBetweenStatusHeartbeats() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.configure(profile: profile, suspended: false)
        controller.setDiagnosticsRecording(true)
        let source = factory.sources.last!
        source.emit(sample(at: 100))
        var impact = sample(at: 100.1); impact.acceleration.y = 0.5
        source.emit(impact); source.emit(sample(at: 100.12))
        await waitUntil { controller.diagnostics.entries.contains { $0.kind == .state && $0.condition == .impact } }
        XCTAssertEqual(controller.diagnostics.counts.rejected, 0, "候选尚未开始，晃动只记状态，不捏造失败尝试")
        XCTAssertEqual(controller.diagnostics.counts.manualMisses, 0)
    }

    func testClearingDiagnosticsDoesNotRestartOrResetPlaybackRecognition() async {
        let factory = Factory(), clock = Clock()
        let controller = AirPodsNodController(sourceFactory: { factory.make() }, clock: { clock.now })
        defer { controller.shutdown() }
        controller.configure(profile: profile, suspended: false)
        controller.setDiagnosticsRecording(true)
        let source = factory.sources.last!
        for t in stride(from: 100.0, through: 101.2, by: 0.02) { source.emit(sample(at: t)) }
        await waitUntil { controller.diagnostics.lastPlaybackObservation?.condition == .ready }
        clock.now = 101.21; controller.clearDiagnostics()
        XCTAssertEqual(controller.diagnostics.lastPlaybackObservation?.condition, .waitingData)
        source.emit(sample(at: 101.22))
        await waitUntil { controller.diagnostics.lastPlaybackObservation?.condition == .ready }
        XCTAssertTrue(controller.diagnostics.recording)
        XCTAssertEqual(source.starts, 1); XCTAssertEqual(source.stops, 0)
        XCTAssertEqual(controller.diagnostics.counts, .init())
    }
}
