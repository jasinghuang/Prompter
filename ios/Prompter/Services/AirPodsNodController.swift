import Combine
import CoreMotion
import Foundation
import OSLog

/// Owns the native sensor only while the player is eligible, or during explicit calibration.
/// Recognition runs on a serial queue; the main actor receives discrete events, never a 50 Hz stream.
@MainActor
final class AirPodsNodController: ObservableObject {
    @Published private(set) var status = "连接支持头部运动的 AirPods 后使用"
    @Published private(set) var capturing = false
    @Published private(set) var captureInstruction = ""
    @Published private(set) var captures: [HeadCalibrationCapture] = []
    @Published private(set) var candidate: HeadGestureCalibration?
    @Published private(set) var verified = false
    @Published private(set) var calibrationError: String?
    @Published private(set) var available = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var motionReady = false
    @Published private(set) var lastAttemptHint: String?
    @Published private(set) var diagnostics = NodDiagnostics()
    @Published private(set) var calibrationAction: HeadCalibrationAction? = .down
    @Published private(set) var calibrationProgress = HeadCalibrationProgress(stage: .idle, fraction: 0, hint: "准备好后，点击开始。")
    @Published private(set) var calibrationProblem: HeadCalibrationProblem?
    @Published private(set) var lastCompletedAction: HeadCalibrationAction?
    @Published private(set) var habitSamples: [DeliberateNodDetector.AcceptedNod] = []
    @Published private(set) var habitSkipped = false
    var learningHabit: Bool { candidate != nil && !verified && !habitSkipped && habitSamples.count < 3 }
    let nods = PassthroughSubject<NodPlaybackTrigger, Never>()
    let notices = PassthroughSubject<String, Never>()

    // Even stop/query calls on a newly created manager can enter Core Motion's authorization path.
    // Do not instantiate it at all until the user explicitly opts in or opens calibration.
    private var source: (any HeadphoneMotionSource)?
    private var sourceID = UUID()
    private let sourceFactory: @MainActor () -> any HeadphoneMotionSource
    private let clock: () -> Double
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.jasing.prompter.head-motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var generation = UUID()
    private var recognitionEpoch = UUID()
    private var watchdog: Task<Void, Never>?
    private var health = HeadMotionStreamHealth()
    private var desiredProfile: HeadGestureCalibration?
    private var suspended = true
    private var calibrationSession = false
    private var running = false
    private var activeProcessor: Processor?
    private var pipeline: Pipeline?
    private var activeProcessorID: UUID?
    private var lastSensorLocation: Int?

    private final class Processor: @unchecked Sendable {
        // Confined to queue, never accessed from the main actor after initialization.
        var recorder: HeadCalibrationRecorder?
        var detector: DeliberateNodDetector?
        let verification: Bool
        let learning: Bool
        let id = UUID()
        var lastStage: HeadCalibrationStage?
        var lastReport = -Double.infinity
        var suppressUntil = 0.0
        var epoch = UUID()
        var locomotionDetected = false
        init(recorder: HeadCalibrationRecorder? = nil, detector: DeliberateNodDetector? = nil, verification: Bool = false, learning: Bool = false) {
            self.recorder = recorder; self.detector = detector; self.verification = verification; self.learning = learning
        }
    }
    private final class Pipeline: @unchecked Sendable {
        // Owned by one live native stream; only its serial operation queue mutates these fields.
        var processor: Processor?
        var lastHeartbeat = -Double.infinity
        var diagnosticsEnabled: Bool
        var lastDiagnosticCondition: NodDiagnostics.Condition?
        var hasSeenSample = false
        init(_ processor: Processor, diagnosticsEnabled: Bool) {
            self.processor = processor; self.diagnosticsEnabled = diagnosticsEnabled
        }
    }
    private enum Event: Sendable {
        case alive(Bool, phase: DeliberateNodDetector.Phase?, postureOff: Bool, unsteady: Bool, suppressed: Bool, time: Double, sensorLocation: Int)
        case progress(HeadCalibrationProgress), captured(HeadCalibrationCapture)
        case failure(String, issue: NodDiagnostics.ServiceIssue = .unavailable)
        case nod(UUID, DeliberateNodDetector.AcceptedNod)
        case rejected(DeliberateNodDetector.RejectedAttempt)
        case observation(NodDiagnostics.Condition, Double)
        case handoff(UUID, Int, Double, withinStream: Bool)
    }

    init(sourceFactory: @escaping @MainActor () -> any HeadphoneMotionSource = { HeadphoneMotionSources.make() },
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.sourceFactory = sourceFactory; self.clock = clock
    }

    private func motionSource() -> any HeadphoneMotionSource {
        if let source { return source }
        let source = sourceFactory()
        self.source = source; sourceID = UUID()
        return source
    }

    func setDiagnosticsRecording(_ recording: Bool) {
        if recording {
            diagnostics.begin(at: clock())
            diagnostics.observe(calibrationSession ? .calibrating : desiredProfile == nil ? .disabled : suspended ? .suspended : .waitingData, at: clock())
        } else { diagnostics.end(at: clock()) }
        if let pipeline {
            queue.addOperation { pipeline.diagnosticsEnabled = recording; pipeline.lastDiagnosticCondition = nil }
        }
    }

    func clearDiagnostics() {
        diagnostics.clear(at: clock())
        if diagnostics.recording {
            diagnostics.observe(calibrationSession ? .calibrating : desiredProfile == nil ? .disabled : suspended ? .suspended : .waitingData, at: clock())
        }
        if let pipeline { queue.addOperation { pipeline.lastDiagnosticCondition = nil } }
    }

    func markUnresponsiveNod() { diagnostics.markMiss(at: clock()) }
    func markLastNodFalsePositive() { diagnostics.markLastResponseFalse(at: clock()) }
    func undoDiagnosticMark() { diagnostics.undoMark() }
    var diagnosticsExport: String? { try? diagnostics.exportJSON(at: clock()) }
    var diagnosticObservedSeconds: [NodDiagnostics.Condition: Double] { diagnostics.observedSeconds(at: clock()) }

    func confirmNodApplied(_ trigger: NodPlaybackTrigger, playing: Bool) {
        diagnostics.applied(id: trigger.id, playing: playing, at: clock())
    }
    func discardNod(_ trigger: NodPlaybackTrigger) { diagnostics.notApplied(id: trigger.id) }

    func configure(profile: HeadGestureCalibration?, suspended: Bool) {
        let changed = profile != desiredProfile || self.suspended != suspended
        desiredProfile = profile?.valid == true ? profile : nil
        self.suspended = suspended
        guard !calibrationSession else { return }
        if desiredProfile == nil || suspended {
            diagnostics.observe(desiredProfile == nil ? .disabled : .suspended, at: clock())
            stop()
            status = desiredProfile == nil ? "点头控制已关闭" : "已开启，返回提词正文后生效。"
            return
        }
        if changed || !running { startMonitoring() }
    }

    func rearm() {
        guard !calibrationSession, desiredProfile != nil, !suspended else { return }
        // Manual touches cancel any queued candidate. A recognized nod keeps its own cooldown;
        // it must not also pay this suppression period and a second full settling period.
        guard let processor = activeProcessor else { return }
        let until = clock() + 0.35
        diagnostics.observe(.manualSuppression, at: clock())
        let epoch = UUID()
        recognitionEpoch = epoch
        queue.addOperation {
            processor.detector?.reset()
            processor.suppressUntil = until
            processor.epoch = epoch
        }
    }

    func refreshConnection() {
        updateAvailability()
        if !calibrationSession && !suspended && desiredProfile != nil { startMonitoring() }
    }

    func shutdown() {
        diagnostics.end(at: clock())
        calibrationSession = false; capturing = false; desiredProfile = nil; suspended = true
        stop()
    }

    func beginCalibration() {
        diagnostics.observe(.calibrating, at: clock())
        stop(); capturing = false; calibrationSession = true
        captures = []; candidate = nil; verified = false; calibrationError = nil
        habitSamples = []; habitSkipped = false
        calibrationAction = .down; calibrationProblem = nil; lastCompletedAction = nil
        calibrationProgress = .init(stage: .idle, fraction: 0, hint: "点击开始后，先保持不动，等大字提示你做动作。")
        updateAvailability()
    }

    func endCalibration() {
        stop(); capturing = false; calibrationSession = false
        if !suspended && desiredProfile != nil { startMonitoring() }
        else {
            diagnostics.observe(desiredProfile == nil ? .disabled : .suspended, at: clock())
            if desiredProfile != nil { status = "已开启，返回提词正文后生效。" }
        }
    }

    func interruptCalibration() {
        guard calibrationSession else { return }
        stop(); capturing = false
        calibrationError = "校准已暂停。回到应用后，点重试继续当前动作。"
        calibrationProgress = .init(stage: .idle, fraction: 0, hint: "已完成的动作已保留。")
    }

    func retryCalibration() {
        guard calibrationSession else { return }
        if capturing {
            capturing = false; activeProcessorID = nil; activeProcessor = nil
            if let pipeline { queue.addOperation { pipeline.processor = nil } }
        }
        calibrationError = nil; updateAvailability()
        if candidate != nil { startTest() } else { startCapture() }
    }

    func restartCalibration() { beginCalibration() }

    func selectCalibrationAction(_ action: HeadCalibrationAction) {
        guard calibrationSession, !capturing, action.rawValue < captures.count else { return }
        calibrationAction = action; candidate = nil; verified = false
        habitSamples = []; habitSkipped = false
        calibrationError = nil
        calibrationProgress = .init(stage: .idle, fraction: 0, hint: "只重做\(action.shortTitle)，其他动作的记录会保留。")
    }

    var completedCalibrationActions: Set<HeadCalibrationAction> {
        var result = Set(HeadCalibrationAction.allCases.prefix(captures.count))
        if let calibrationAction, calibrationAction.rawValue < captures.count { result.remove(calibrationAction) }
        return result
    }

    private func updateAvailability() {
        let source = motionSource()
        available = source.available
        permissionDenied = [.denied, .restricted].contains(source.authorization)
        switch source.authorization {
        case .denied, .restricted:
            status = "未获运动权限，请在系统设置中允许“运动与健身”访问。"
        default:
            // Availability is a capability check, not proof that a live sample stream exists.
            status = motionReady ? "耳机已连接" : available ? "戴好 AirPods，点开始" : "请连接并戴好 AirPods"
        }
    }

    func startCapture() {
        guard calibrationSession, !capturing, let action = calibrationAction else { return }
        updateAvailability()
        guard permissionPermitsStart else { calibrationError = status; return }
        capturing = true; calibrationError = nil
        captureInstruction = "正在等待耳机运动数据…"
        calibrationProgress = .init(stage: motionReady ? .preparing : .connecting, fraction: 0, hint: "先看向屏幕正面，等提示再动。")
        start(Processor(recorder: .init(action: action, neutralReference: action == .down ? nil : captures.first?.gravity)))
        #if DEBUG
        (source as? CalibrationDemoMotionSource)?.perform(action, verification: false)
        #endif
    }

    func startTest() {
        guard let candidate, calibrationSession, !capturing else { return }
        updateAvailability()
        guard permissionPermitsStart else { calibrationError = status; return }
        capturing = true; calibrationError = nil
        captureInstruction = "正在等待耳机运动数据…"
        calibrationProgress = .init(stage: motionReady ? .preparing : .connecting, fraction: 0,
                                    hint: "先保持静止，等提示开始后，再自然地点头一下并回正。")
        let learning = learningHabit
        start(Processor(detector: .init(calibration: candidate, learningEndpoint: learning), verification: true, learning: learning))
        #if DEBUG
        (source as? CalibrationDemoMotionSource)?.perform(.down, verification: true)
        #endif
    }

    func skipHabitLearning() {
        guard calibrationSession, candidate != nil, !verified else { return }
        capturing = false; activeProcessorID = nil; recognitionEpoch = UUID()
        habitSkipped = true; candidate?.habit = nil
        startTest()
    }

    private var permissionPermitsStart: Bool {
        let auth = motionSource().authorization
        return auth != .denied && auth != .restricted && available
    }

    private func startMonitoring() {
        guard let desiredProfile else { return }
        updateAvailability()
        if permissionPermitsStart { start(Processor(detector: .init(calibration: desiredProfile))) }
        else {
            diagnostics.observe(.unavailable, at: clock())
            diagnostics.serviceIssue(permissionDenied ? .permissionDenied : .unavailable, message: status, at: clock())
            stop()
            // Connection events allow recovery without polling or reading sensors while disconnected.
            observeConnections()
        }
    }

    private func start(_ processor: Processor) {
        if calibrationSession, running, let pipeline {
            // Preserve the native reference frame and sensor across all six actions.
            activeProcessor = processor; activeProcessorID = processor.id
            recognitionEpoch = processor.epoch
            queue.addOperation { pipeline.processor = processor }
            return
        }
        stop()
        let source = motionSource()
        let token = generation
        activeProcessor = processor
        activeProcessorID = processor.id
        recognitionEpoch = UUID(); processor.epoch = recognitionEpoch
        let pipeline = Pipeline(processor, diagnosticsEnabled: diagnostics.recording && !calibrationSession)
        self.pipeline = pipeline
        running = true; health.start(at: clock())
        status = "正在等待耳机运动数据…"
        if !calibrationSession { diagnostics.observe(.waitingData, at: clock()) }
        source.start(on: queue, motion: { [weak self] sample, error in
            if let error {
                Task { @MainActor [weak self] in self?.receive(.failure(error), token: token) }
                return
            }
            guard let sample else { return }
            let processor = pipeline.processor
            // Native fusion may briefly be uninitialized. Do not treat a bad calibration frame
            // as a user mistake or count it as a healthy heartbeat; sustained loss times out.
            if !sample.valid && (processor == nil || processor?.recorder != nil) { return }
            var event: Event?
            if let processor {
                processor.locomotionDetected = sample.locomotionDetected
                if processor.recorder != nil {
                    switch processor.recorder?.process(sample) {
                    case .progress(let progress):
                        if progress.stage != processor.lastStage || sample.time - processor.lastReport >= 0.1 {
                            processor.lastStage = progress.stage; event = .progress(progress)
                        }
                    case .captured(let capture): event = .captured(capture); pipeline.processor = nil
                    case .failed(let message): event = .failure(message); pipeline.processor = nil
                    default: break
                    }
                } else if let detector = processor.detector, processor.verification,
                          sample.sensorLocation != detector.calibration.sensorLocation {
                    event = .failure("耳机运动传感器已变化，请重新校准后使用。", issue: .sensorChanged)
                } else if !sample.valid {
                    event = .failure("耳机运动数据异常，请检查连接后重试。", issue: .invalidData)
                } else if sample.time >= processor.suppressUntil {
                    if let detector = processor.detector, sample.sensorLocation != detector.sensorLocation {
                        processor.epoch = UUID()
                        let change = Event.handoff(processor.epoch, sample.sensorLocation, sample.time, withinStream: pipeline.hasSeenSample)
                        let id = processor.id
                        Task { @MainActor [weak self] in self?.receive(change, token: token, processorID: id) }
                    }
                    if processor.detector?.process(sample) == true, let accepted = processor.detector?.lastAccepted {
                        event = .nod(processor.epoch, accepted)
                        if processor.verification { pipeline.processor = nil }
                    }
                    else if processor.verification, let phase = processor.detector?.phase {
                        let progress: HeadCalibrationProgress
                        switch phase {
                        case .settling: progress = .init(stage: .preparing, fraction: 0, hint: "先停稳片刻，再等提示点头；六个动作不用重做。")
                        case .armed: progress = .init(stage: .verifying, fraction: 0, hint: "现在自然地点头一下，再回正。")
                        case .descending: progress = .init(stage: .performing, fraction: 0.5, hint: "点头一下，然后回正。")
                        case .returning: progress = .init(stage: .returning, fraction: 0.8, hint: "轻轻回正，再停留一下。")
                        case .cooldown: progress = .init(stage: .verified, fraction: 1, hint: "点头识别成功。")
                        }
                        if progress.stage != processor.lastStage {
                            processor.lastStage = progress.stage; event = .progress(progress)
                        }
                    }
                    if let rejected = processor.detector?.lastRejection, rejected.time == sample.time {
                        event = .rejected(rejected)
                    }
                }
                if let event {
                    processor.lastReport = sample.time
                    let id = processor.id
                    Task { @MainActor [weak self] in self?.receive(event, token: token, processorID: id) }
                }
            }
            if pipeline.diagnosticsEnabled, sample.valid, let processor, processor.detector != nil, !processor.verification {
                let condition = NodDiagnostics.Condition.observing(moving: sample.locomotionDetected, phase: processor.detector?.phase,
                    postureOff: processor.detector?.startingPostureOff == true,
                    unsteady: sample.acceleration.length >= 0.45 || sample.rate.length >= 4,
                    suppressed: sample.time < processor.suppressUntil)
                if condition != pipeline.lastDiagnosticCondition {
                    pipeline.lastDiagnosticCondition = condition
                    Task { @MainActor [weak self] in self?.receive(.observation(condition, sample.time), token: token) }
                }
            }
            if sample.valid && sample.time - pipeline.lastHeartbeat >= 0.5 {
                pipeline.lastHeartbeat = sample.time
                let phase = processor?.detector?.phase
                let postureOff = processor?.detector?.startingPostureOff ?? false
                let unsteady = sample.acceleration.length >= 0.45 || sample.rate.length >= 4
                let suppressed = sample.time < (processor?.suppressUntil ?? 0)
                Task { @MainActor [weak self] in
                    self?.receive(.alive(sample.locomotionDetected, phase: phase, postureOff: postureOff, unsteady: unsteady,
                                         suppressed: suppressed, time: sample.time, sensorLocation: sample.sensorLocation), token: token)
                }
            }
            if sample.valid { pipeline.hasSeenSample = true }
        }, connection: connectionHandler())
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.generation == token else { return }
                self.checkStreamHealth()
            }
        }
    }

    private func receive(_ event: Event, token: UUID, processorID: UUID? = nil) {
        guard token == generation, processorID == nil || processorID == activeProcessorID else { return }
        switch event {
        case .failure: break
        default:
            health.receivedSample(at: clock())
            if !motionReady {
                motionReady = true
                if capturing {
                    captureInstruction = calibrationAction != nil ? "先看向正面，保持静止约 1 秒" : "坐稳看向正面，再明确地点头一下并回正"
                }
            }
        }
        switch event {
        case .alive(let moving, let phase, let postureOff, let unsteady, let suppressed, let time, let sensorLocation):
            lastSensorLocation = sensorLocation
            if calibrationSession {
                status = moving ? "请先坐稳" : "耳机已连接"
            } else {
                let condition = NodDiagnostics.Condition.observing(moving: moving, phase: phase, postureOff: postureOff,
                                                                  unsteady: unsteady, suppressed: suppressed)
                diagnostics.observe(condition, at: time)
                if moving { status = "检测到走动，请停稳后再点头。" }
                else if postureOff { status = "请看向屏幕正面，再停稳片刻。" }
                else if unsteady { status = "动作稍快或有晃动，请先停稳。" }
                else {
                    switch phase {
                    case .armed: status = "点头控制已就绪"
                    case .descending: status = "已检测到低头，请回正。"
                    case .returning: status = "请回正并停留一下。"
                    case .cooldown: status = "点头已响应，稍后可再点头。"
                    default: status = "点头控制：请先停稳片刻。"
                    }
                }
            }
        case .progress(let progress):
            calibrationProgress = progress; captureInstruction = progress.hint
        case .observation(let condition, let time):
            if !calibrationSession { diagnostics.observe(condition, at: time) }
        case .handoff(let epoch, let location, let time, let withinStream):
            recognitionEpoch = epoch; lastAttemptHint = nil
            status = "耳机已切换，请先停稳片刻。"
            if withinStream || (lastSensorLocation != nil && lastSensorLocation != location) {
                diagnostics.sensorChanged(to: location, at: time)
            }
            lastSensorLocation = location
        case .rejected(let attempt):
            if !calibrationSession { diagnostics.rejected(attempt) }
            lastAttemptHint = attempt.reason.hint
            // Discrete, local diagnostics only. Never log or persist the motion stream.
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.jasing.prompter", category: "NodRecognition")
            logger.info("Rejected nod: \(attempt.reason.rawValue, privacy: .public), peak=\(attempt.peakDegrees), duration=\(attempt.duration)")
            if calibrationSession {
                calibrationProgress = .init(stage: .preparing, fraction: 0, hint: attempt.reason.hint)
            }
        case .failure(let message, let issue):
            let denied = source.map { [.denied, .restricted].contains($0.authorization) } ?? permissionDenied
            let message = denied ? "未获运动权限，请在系统设置中允许“运动与健身”访问。" : message
            if !calibrationSession {
                diagnostics.serviceIssue(denied ? .permissionDenied : issue, message: message, at: clock())
                diagnostics.observe(issue == .interrupted || issue == .noInitialData ? .interrupted : .unavailable, at: clock())
            }
            stop(); capturing = false; status = message
            permissionDenied = denied
            if calibrationSession { calibrationError = message }
            else if desiredProfile != nil && !suspended {
                notices.send(message)
                observeConnections()
            }
            calibrationProgress = .init(stage: .idle, fraction: 0, hint: "已完成的其他动作会保留。")
        case .captured(let capture):
            guard let action = calibrationAction else { return }
            activeProcessor = nil; activeProcessorID = nil; capturing = false
            if action.rawValue < captures.count { captures[action.rawValue] = capture }
            else { captures.append(capture) }
            lastCompletedAction = action
            status = "耳机已连接"
            calibrationProblem = HeadGestureCalibration.problem(in: captures)
            if let problem = calibrationProblem {
                calibrationAction = problem.action; candidate = nil; calibrationError = problem.message
                calibrationProgress = .init(stage: .idle, fraction: 0, hint: "只需调整这一项，其余记录已保留。")
            } else if captures.count == 6 {
                candidate = HeadGestureCalibration.build(captures)
                if candidate == nil {
                    calibrationAction = .down
                    calibrationError = "点头方向还不能稳定组合。其他记录已保留，先重做低头，也可点选其他动作。"
                    calibrationProgress = .init(stage: .idle, fraction: 0, hint: "其他动作无需重做。")
                } else {
                    calibrationAction = nil; calibrationError = nil
                    calibrationProgress = .init(stage: .completed, fraction: 1, hint: "六个动作已通过检查，最后试一次点头。")
                }
            } else {
                calibrationAction = HeadCalibrationAction.allCases[captures.count]
                calibrationError = nil
                calibrationProgress = .init(stage: .completed, fraction: 1, hint: "\(action.shortTitle)已完成。准备好后，继续下一个动作。")
            }
        case .nod(let epoch, let accepted):
            guard epoch == recognitionEpoch else { return }
            lastAttemptHint = nil
            if calibrationSession {
                if activeProcessor?.learning == true {
                    habitSamples.append(accepted); capturing = false
                    activeProcessor = nil; activeProcessorID = nil; recognitionEpoch = UUID()
                    if habitSamples.count == 3 { candidate?.habit = NodHabitProfile.learn(habitSamples) }
                    calibrationProgress = .init(stage: .completed, fraction: Double(habitSamples.count) / 3,
                        hint: habitSamples.count < 3 ? "这次已记录，准备好后继续下一次自然点头。" : "适配已记录，再用一次新的点头验证。")
                } else {
                    verified = true; capturing = false; stop()
                    calibrationProgress = .init(stage: .verified, fraction: 1, hint: "可以开启点头控制了。")
                }
            }
            else {
                let trigger = NodPlaybackTrigger(id: UUID())
                diagnostics.detected(accepted, id: trigger.id)
                diagnostics.observe(.cooldown, at: accepted.time)
                nods.send(trigger)
            }
        }
    }

    private func stop() {
        generation = UUID(); watchdog?.cancel(); watchdog = nil
        sourceID = UUID(); running = false; motionReady = false; health.stop()
        // Invalidate both callback tokens before native stop can enqueue a disconnect event.
        source?.stop(); source = nil
        activeProcessor = nil
        activeProcessorID = nil; pipeline = nil
    }

    private func connectionHandler() -> @Sendable (Bool) -> Void {
        let id = sourceID
        return { [weak self] connected in
            Task { @MainActor [weak self] in self?.receiveConnection(connected, sourceID: id) }
        }
    }

    private func observeConnections() {
        guard !permissionDenied, !calibrationSession, desiredProfile != nil, !suspended else { return }
        motionSource().observeConnections(connectionHandler())
    }

    private func receiveConnection(_ connected: Bool, sourceID: UUID) {
        guard sourceID == self.sourceID else { return }
        if connected {
            if !running && !calibrationSession && !suspended && desiredProfile != nil && source?.available == true { startMonitoring() }
            else if !motionReady { status = "耳机运动服务已连接，正在等待实时数据…" }
        } else if running {
            // Startup and service switches can produce transient/stale disconnect hints.
            // Keep the stream alive. Fresh samples clear the hint; only sustained loss fails.
            rearm()
            if !health.hasRecentSample(at: clock()) { status = "正在等待耳机运动数据，请保持佩戴。" }
        }
    }

    func checkStreamHealth() {
        guard running, let source else { return }
        let authorization = source.authorization
        if [.denied, .restricted].contains(authorization) {
            receive(.failure("未获运动权限，请在系统设置中允许“运动与健身”访问。"), token: generation)
            return
        }
        health.waitForPermission(at: clock(), pending: authorization == .notDetermined)
        if let message = health.timeout(at: clock()) {
            receive(.failure(message, issue: motionReady ? .interrupted : .noInitialData), token: generation)
        }
    }
}
