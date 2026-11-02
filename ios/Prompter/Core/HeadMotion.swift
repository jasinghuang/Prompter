import Foundation

/// Value types keep Core Motion objects off the UI thread and the recognizer testable.
struct MotionVector: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var z: Double
    static let zero = Self(x: 0, y: 0, z: 0)
    var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
    var length: Double { sqrt(dot(self)) }
    var unit: Self { length > 0.00001 ? self * (1 / length) : .zero }
    func dot(_ v: Self) -> Double { x * v.x + y * v.y + z * v.z }
    func cross(_ v: Self) -> Self { .init(x: y * v.z - z * v.y, y: z * v.x - x * v.z, z: x * v.y - y * v.x) }
    static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: Self, b: Self) -> Self { a + b * -1 }
    static func * (a: Self, b: Double) -> Self { .init(x: a.x * b, y: a.y * b, z: a.z * b) }
    func angle(to v: Self) -> Double { atan2(cross(v).length, dot(v)) }
    func signedAngle(to v: Self, around axis: Self) -> Double {
        // Project onto the rotation plane. atan2 preserves signs and angles beyond 90°.
        let a = (self - axis * dot(axis)).unit
        let b = (v - axis * v.dot(axis)).unit
        return atan2(a.cross(b).dot(axis), a.dot(b))
    }
}

struct MotionQuaternion: Equatable, Sendable {
    var x: Double = 0, y: Double = 0, z: Double = 0, w: Double = 1
    var finite: Bool { [x, y, z, w].allSatisfy(\.isFinite) }
    func angle(to other: Self) -> Double {
        let norm = sqrt((x*x + y*y + z*z + w*w) * (other.x*other.x + other.y*other.y + other.z*other.z + other.w*other.w))
        guard norm > 0.5 else { return .infinity }
        return 2 * acos(min(1, abs((x*other.x + y*other.y + z*other.z + w*other.w) / norm)))
    }
}

struct HeadMotionSample: Sendable {
    var time: Double
    var gravity: MotionVector
    var rate: MotionVector // radians / second, in the headphone frame
    var acceleration: MotionVector // user acceleration, g
    var attitude = MotionQuaternion() // short relative rotations for yaw calibration only
    var sensorLocation: Int = 0
    var locomotionDetected = false // Optional native headphone activity veto on iOS 18+.
    var valid: Bool {
        time.isFinite && gravity.finite && (0.8...1.2).contains(gravity.length)
            && rate.finite && acceleration.finite && attitude.finite
    }
    var still: Bool { rate.length < 0.16 && acceleration.length < 0.035 }
}

enum HeadCalibrationAction: Int, CaseIterable, Codable, Sendable {
    case down, up, tiltRight, tiltLeft, turnRight, turnLeft
    var title: String {
        switch self {
        case .down: return "轻轻低头"
        case .up: return "轻轻抬头"
        case .tiltRight: return "向右歪头"
        case .tiltLeft: return "向左歪头"
        case .turnRight: return "向右转头"
        case .turnLeft: return "向左转头"
        }
    }
    var instruction: String {
        switch self {
        case .down: return "下巴向胸口靠近一点，再回到正面。"
        case .up: return "下巴轻轻抬起，再回到正面。"
        case .tiltRight: return "脸仍朝正前方，右耳向右肩靠近一点，再回正；不用碰到肩膀。"
        case .tiltLeft: return "脸仍朝正前方，左耳向左肩靠近一点，再回正；不用碰到肩膀。"
        case .turnRight: return "脸转向右边，下巴大致保持水平，再回到正面。"
        case .turnLeft: return "脸转向左边，下巴大致保持水平，再回到正面。"
        }
    }
    var icon: String {
        switch self {
        case .down: return "arrow.down"
        case .up: return "arrow.up"
        case .tiltRight: return "arrow.down.right"
        case .tiltLeft: return "arrow.down.left"
        case .turnRight: return "arrow.turn.up.right"
        case .turnLeft: return "arrow.turn.up.left"
        }
    }
    var isTurn: Bool { self == .turnRight || self == .turnLeft }
    var shortTitle: String {
        ["低头", "抬头", "右歪头", "左歪头", "右转头", "左转头"][rawValue]
    }
}

struct HeadCalibrationCapture: Sendable {
    var gravity: MotionVector
    var axis: MotionVector
    var angle: Double
    var sensorLocation: Int
}

struct HeadCalibrationProblem: Equatable, Sendable {
    var action: HeadCalibrationAction
    var related: [HeadCalibrationAction]
    var message: String
    var requiresRestart = false
}

enum HeadCalibrationStage: Equatable, Sendable {
    case idle, connecting, preparing, performing, returning, completed, verifying, verified
    var title: String {
        switch self {
        case .idle: return "准备好后开始"
        case .connecting: return "正在连接耳机"
        case .preparing: return "先看正面，保持不动"
        case .performing: return "现在开始动作"
        case .returning: return "幅度已够，请回正"
        case .completed: return "这个动作完成了"
        case .verifying: return "点头一下，再回正"
        case .verified: return "点头识别成功"
        }
    }
}

struct HeadCalibrationProgress: Equatable, Sendable {
    var stage: HeadCalibrationStage
    var fraction: Double
    var hint: String
}

struct HeadGestureCalibration: Codable, Equatable, Sendable {
    var version = 1
    var neutral: MotionVector
    var pitchAxis: MotionVector
    var rollAxis: MotionVector
    var yawAxis: MotionVector
    var ranges: [Double] // six comfortable observed excursions, radians; not medical ROM
    var sensorLocation: Int
    var date: Date = Date()
    var habit: NodHabitProfile? = nil

    var valid: Bool {
        version == 1 && neutral.finite && pitchAxis.finite && rollAxis.finite && yawAxis.finite
            && [neutral, pitchAxis, rollAxis, yawAxis].allSatisfy { abs($0.length - 1) < 0.02 }
            && abs(neutral.dot(pitchAxis)) < 0.1 && abs(neutral.dot(rollAxis)) < 0.1
            && abs(pitchAxis.dot(rollAxis)) < 0.1 && abs(neutral.dot(yawAxis)) > 0.85
            && ranges.count == 6 && ranges.allSatisfy { $0.isFinite && $0 >= 6 * .pi / 180 && $0 < 85 * .pi / 180 }
    }

    /// Validate immediately after each step, with one actionable retry instead of losing six captures.
    static func problem(in captures: [HeadCalibrationCapture]) -> HeadCalibrationProblem? {
        guard let first = captures.first else { return nil }
        for (index, capture) in captures.enumerated() {
            let action = HeadCalibrationAction.allCases[min(index, 5)]
            if capture.sensorLocation != first.sensorLocation {
                return .init(action: action, related: [action], message: "耳机运动数据源发生了变化，不能合并两套坐标。请保持双耳佩戴；可重试这个动作，或重新佩戴后从头校准。", requiresRestart: true)
            }
            if !capture.axis.finite || abs(capture.axis.length - 1) > 0.02 || !capture.gravity.finite
                || abs(capture.gravity.length - 1) > 0.02 || !capture.angle.isFinite
                || !(6 * .pi / 180 ..< 85 * .pi / 180).contains(capture.angle) {
                return .init(action: action, related: [action], message: "\(action.shortTitle)的数据不完整，只需重做这个动作。其他记录已保留。")
            }
            if first.gravity.angle(to: capture.gravity) > 18 * .pi / 180 {
                return .init(action: action, related: [action], message: "\(action.shortTitle)开始时的位置与第一次相差较大。看向屏幕正面后，只重做这个动作。")
            }
        }
        for (a, b) in [(0, 1), (2, 3), (4, 5)] where captures.count > b {
            if captures[a].axis.dot(captures[b].axis) > -0.4 {
                let first = HeadCalibrationAction.allCases[a], second = HeadCalibrationAction.allCases[b]
                return .init(action: second, related: [first, second], message: "\(first.shortTitle)和\(second.shortTitle)的方向记录太接近。先重做\(second.shortTitle)，其余动作已保留；也可选择重做\(first.shortTitle)。")
            }
        }
        if captures.count >= 4 {
            let pitch = (captures[0].axis - captures[1].axis).unit
            let roll = (captures[2].axis - captures[3].axis).unit
            if abs(pitch.dot(roll)) > 0.65 {
                return .init(action: .tiltRight, related: [.tiltRight, .tiltLeft], message: "歪头与点头的方向记录太接近。歪头时脸仍朝前、耳朵靠近肩膀，只重做需要调整的歪头动作。")
            }
        }
        for index in [4, 5] where captures.count > index {
            if abs(first.gravity.unit.dot(captures[index].axis)) < 0.7 {
                let action = HeadCalibrationAction.allCases[index]
                return .init(action: action, related: [action], message: "\(action.shortTitle)时混入了较多低头或歪头。下巴大致保持水平，只重做这个动作。")
            }
        }
        return nil
    }

    static func build(_ captures: [HeadCalibrationCapture]) -> Self? {
        guard captures.count == 6, problem(in: captures) == nil else { return nil }
        let neutral = captures[0].gravity.unit
        let rawPitch = (captures[0].axis - captures[1].axis).unit
        // Fit a common reference plane before orthogonalizing. Small posture differences
        // between actions must not invalidate otherwise distinct, repeatable axes.
        let pitch = (rawPitch - neutral * rawPitch.dot(neutral)).unit
        let rawRoll = (captures[2].axis - captures[3].axis).unit
        let inPlane = rawRoll - neutral * rawRoll.dot(neutral)
        let roll = (inPlane - pitch * inPlane.dot(pitch)).unit
        let rawYaw = (captures[4].axis - captures[5].axis).unit
        let yaw = neutral * (rawYaw.dot(neutral) < 0 ? -1 : 1)
        let result = Self(neutral: neutral, pitchAxis: pitch, rollAxis: roll, yawAxis: yaw,
                          ranges: captures.map(\.angle), sensorLocation: captures[0].sensorLocation)
        return result.valid ? result : nil
    }
}

/// One instructed movement: establish neutral → excursion → return and settle.
/// Samples arrive on one serial operation queue. No timers, UI updates or Euler angles here.
struct HeadCalibrationRecorder {
    let action: HeadCalibrationAction
    var neutralReference: MotionVector?
    private var previousTime: Double?
    private var started: Double?
    private var stillSince: Double?
    private var neutralSum = MotionVector.zero
    private var neutralCount = 0.0
    private var origin: HeadMotionSample?
    private var integrated = MotionVector.zero
    private var peak: HeadCalibrationCapture?
    private var returnedSince: Double?
    private var excursionDuration = 0.0
    private var pauseUntil = 0.0

    init(action: HeadCalibrationAction, neutralReference: MotionVector? = nil) {
        self.action = action; self.neutralReference = neutralReference
    }

    enum Update { case progress(HeadCalibrationProgress), captured(HeadCalibrationCapture), failed(String) }
    private mutating func resetAttempt() {
        stillSince = nil; neutralSum = .zero; neutralCount = 0
        origin = nil; integrated = .zero; peak = nil; returnedSince = nil; excursionDuration = 0
    }
    private func update(_ stage: HeadCalibrationStage, _ fraction: Double, _ hint: String) -> Update {
        .progress(.init(stage: stage, fraction: min(1, max(0, fraction)), hint: hint))
    }
    mutating func process(_ sample: HeadMotionSample) -> Update {
        guard sample.valid else { return .failed("运动数据异常，请重新尝试。") }
        let dt = previousTime.map { sample.time - $0 } ?? 0
        previousTime = sample.time
        if dt < 0 || dt > 0.3 {
            resetAttempt()
            return update(.preparing, 0, "数据刚才短暂中断，先保持不动，当前动作会重新开始。")
        }
        if started == nil { started = sample.time }
        if sample.time - (started ?? sample.time) > 30 { return .failed("这个动作还没记录完整。看向正面后重试，已完成的其他动作会保留。") }
        guard !sample.locomotionDetected, sample.acceleration.length < 0.22, sample.rate.length < 5 else {
            resetAttempt(); pauseUntil = sample.time + 0.25
            return update(.preparing, 0, "先坐稳，轻缓一点；不用退出，保持不动后继续。")
        }
        if sample.time < pauseUntil { return update(.preparing, 0, "先保持不动，准备好后会提示你开始。") }
        let calm = sample.rate.length < 0.25 && sample.acceleration.length < 0.06
        if origin == nil {
            guard calm else {
                stillSince = nil; neutralSum = .zero; neutralCount = 0
                return update(.preparing, 0, "先不要做动作，等下方进度走满。")
            }
            if let reference = neutralReference, reference.angle(to: sample.gravity) > 18 * .pi / 180 {
                stillSince = nil; neutralSum = .zero; neutralCount = 0
                return update(.preparing, 0, "稍微调整到看向屏幕正面的位置。")
            }
            if neutralCount > 0 && neutralSum.unit.angle(to: sample.gravity) > 3 * .pi / 180 {
                stillSince = nil; neutralSum = .zero; neutralCount = 0
            }
            if stillSince == nil { stillSince = sample.time }
            neutralSum = neutralSum + sample.gravity; neutralCount += 1
            let progress = (sample.time - (stillSince ?? sample.time)) / 0.65
            if progress >= 1 {
                var averaged = sample; averaged.gravity = neutralSum.unit
                origin = averaged
                return update(.performing, 0, action.instruction)
            }
            return update(.preparing, progress, "等进度走满，再按大字提示做动作。")
        }
        guard let origin else { return update(.preparing, 0, "请看向正面。") }
        guard origin.sensorLocation == sample.sensorLocation else { return .failed("耳机传感器发生变化，请重新校准。") }
        let tilt = origin.gravity.angle(to: sample.gravity)
        let angle = action.isTurn ? origin.attitude.angle(to: sample.attitude) : tilt
        if angle < 2 * .pi / 180 && peak == nil { integrated = .zero }
        else { integrated = integrated + sample.rate * dt }
        if action.isTurn && tilt > 14 * .pi / 180 {
            resetAttempt()
            return update(.preparing, 0, "转头时保持头部直立；回正后会重新提示开始。")
        }
        let threshold = (action.isTurn ? 12.0 : 7.0) * .pi / 180
        if angle > (peak?.angle ?? threshold), angle < 80 * .pi / 180 {
            peak = .init(gravity: origin.gravity.unit,
                         axis: action.isTurn ? integrated.unit : origin.gravity.cross(sample.gravity).unit,
                         angle: angle, sensorLocation: sample.sensorLocation)
        }
        if peak != nil && angle >= threshold * 0.8 { excursionDuration += dt }
        let excursionConfirmed = excursionDuration >= 0.06
        let returnTolerance = min(7, max(5, (peak?.angle ?? 0) * 180 / .pi * 0.22)) * .pi / 180
        if let peak, excursionConfirmed, angle < returnTolerance, calm {
            if returnedSince == nil { returnedSince = sample.time }
            let progress = (sample.time - (returnedSince ?? sample.time)) / 0.22
            if progress >= 1 { return .captured(peak) }
            return update(.returning, progress, "已经回正，再停留一下就完成。")
        } else { returnedSince = nil }
        if peak != nil && excursionConfirmed { return update(.returning, 0, "幅度已经足够，不必继续转；轻轻回到屏幕正面。") }
        return update(.performing, angle / threshold, action.instruction)
    }
}

/// Conservative single-nod rhythm recognizer. No integration of attitude over a session.
/// A complete down/return cycle is required; locomotion and off-axis rotation veto the cycle.
struct DeliberateNodDetector {
    enum Phase: Equatable, Sendable { case settling, armed, descending, returning, cooldown }
    enum Rejection: String, Sendable {
        case small, slow, offAxis, incomplete, impact, walking, interrupted
        var hint: String {
            switch self {
            case .small: return "点头幅度较小，请稍微多低一点头。"
            case .slow: return "这次动作较慢，请自然地点一下头再回正。"
            case .offAxis: return "这次伴随歪头或转头，请朝正前方点头。"
            case .incomplete: return "这次没有完整回正，请回到看屏幕的位置。"
            case .impact: return "这次晃动较大，请坐稳后再点头。"
            case .walking: return "检测到走动，请停稳后再点头。"
            case .interrupted: return "这次耳机数据不连续，请停稳后重试。"
            }
        }
    }
    struct RejectedAttempt: Equatable, Sendable {
        var reason: Rejection
        var time: Double
        var peakDegrees: Double
        var duration: Double
    }
    struct AcceptedNod: Equatable, Sendable {
        var time: Double
        var peakDegrees: Double
        var duration: Double
        var returnStartedAt: Double
        var toleratedReturnDisturbanceSeconds: Double = 0
        var returnOffsetDegrees: Double = 0
    }
    private struct ReturnWindow {
        let startedAt: Double
        var quietSince: Double
        var quietDuration = 0.0
        var disturbedDuration = 0.0
        var previousWasQuiet = true
        var disturbanceEnded = false
    }
    let calibration: HeadGestureCalibration
    private let learningEndpoint: Bool
    private(set) var sensorLocation: Int
    private(set) var phase: Phase = .settling
    private(set) var lastRejection: RejectedAttempt?
    private(set) var lastAccepted: AcceptedNod?
    private var previousTime: Double?
    private var filtered: MotionVector?
    private var baseline: MotionVector?
    private var stillSince: Double?
    private var phaseTime = 0.0
    private var cycleTime = 0.0
    private var peak = 0.0
    private var pitchEnergy = 0.0
    private var otherEnergy = 0.0
    private var yawTravel = 0.0
    private var returnWindow: ReturnWindow?
    private var cooldownUntil = 0.0
    private var previousPitch = 0.0
    private var armingReference: MotionVector?
    private var restCandidate: MotionVector?
    private var restCandidateSince: Double?
    private(set) var startingPostureOff = false

    /// Bounded relative to the last deliberately armed pose, not the previous correction.
    var restAdjustmentDegrees: Double {
        guard let armingReference, let baseline else { return 0 }
        return armingReference.angle(to: baseline) * 180 / .pi
    }

    init(calibration: HeadGestureCalibration, learningEndpoint: Bool = false) {
        self.calibration = calibration; self.learningEndpoint = learningEndpoint
        sensorLocation = calibration.sensorLocation
    }
    mutating func reset() {
        phase = .settling; previousTime = nil; filtered = nil; baseline = nil; stillSince = nil
        returnWindow = nil; peak = 0; previousPitch = 0
        startingPostureOff = false
        lastAccepted = nil
        armingReference = nil; restCandidate = nil; restCandidateSince = nil
    }

    private mutating func updateRestReference(_ gravity: MotionVector, sample: HeadMotionSample, roll: Double, quiet: Bool) {
        guard let baseline, let armingReference else { return }
        let maxAdjustment = 12 * Double.pi / 180
        let displacement = baseline.angle(to: gravity)
        if displacement < 1.5 * .pi / 180 && quiet {
            restCandidate = nil; restCandidateSince = nil
            let next = (baseline * 0.995 + gravity * 0.005).unit
            if armingReference.angle(to: next) <= maxAdjustment { self.baseline = next }
            return
        }
        // A changed resting pose is not a new coordinate system. Learn it only while
        // armed and measurably still; never absorb an in-flight nod or chase unlimited drift.
        guard displacement <= 8 * .pi / 180, abs(roll) <= 6 * .pi / 180,
              armingReference.angle(to: gravity) <= maxAdjustment,
              sample.rate.length < 0.12, sample.acceleration.length < 0.04 else {
            restCandidate = nil; restCandidateSince = nil
            return
        }
        if restCandidate == nil || restCandidate!.angle(to: gravity) > 0.8 * .pi / 180 {
            restCandidate = gravity; restCandidateSince = sample.time
        }
        if sample.time - (restCandidateSince ?? sample.time) >= 0.65 {
            self.baseline = gravity; previousPitch = 0
            restCandidate = nil; restCandidateSince = nil
        }
    }
    private mutating func reject(_ reason: Rejection, at time: Double) {
        if phase == .descending || phase == .returning {
            lastRejection = .init(reason: reason, time: time, peakDegrees: peak * 180 / .pi, duration: time - cycleTime)
        }
        reset()
    }

    /// Count only intervals with quiet samples at both ends. One mild burst may pause
    /// accumulation; neither its duration nor the first recovery interval earns quiet time.
    /// Hard vetoes are evaluated before this window and still discard the entire candidate.
    private mutating func stableReturn(at time: Double, dt: Double, quiet: Bool, mild: Bool) -> Bool {
        guard var window = returnWindow else {
            if quiet { returnWindow = .init(startedAt: time, quietSince: time) }
            return false
        }
        guard time - window.startedAt <= 0.20 + 0.000001, quiet || mild else {
            returnWindow = quiet ? .init(startedAt: time, quietSince: time) : nil
            return false
        }
        if quiet {
            if window.previousWasQuiet { window.quietDuration += dt }
            else { window.quietSince = time; window.disturbanceEnded = true }
            window.previousWasQuiet = true
        } else {
            guard !window.disturbanceEnded, window.disturbedDuration + dt <= 0.04 + 0.000001 else {
                returnWindow = nil; return false
            }
            window.disturbedDuration += dt
            window.previousWasQuiet = false
        }
        returnWindow = window
        return quiet && window.quietDuration >= 0.10 && time - window.quietSince >= 0.04 - 0.000001
    }
    mutating func process(_ sample: HeadMotionSample) -> Bool {
        guard calibration.valid, sample.valid else { reset(); return false }
        if sample.sensorLocation != sensorLocation {
            // Reuse learned axes, but never carry an unfinished gesture or filter history
            // across a source change. The new source must establish fresh stillness.
            sensorLocation = sample.sensorLocation; reset()
        }
        guard !sample.locomotionDetected else { reject(.walking, at: sample.time); return false }
        let dt = previousTime.map { sample.time - $0 } ?? 0
        previousTime = sample.time
        guard dt > 0 && dt <= 0.16 else {
            reject(.interrupted, at: sample.time)
            previousTime = sample.time; filtered = sample.gravity.unit; return false
        }
        let alpha = 1 - exp(-dt / 0.045)
        filtered = ((filtered ?? sample.gravity) * (1 - alpha) + sample.gravity * alpha).unit
        guard let gravity = filtered else { reset(); return false }
        // Head rotation itself produces userAcceleration. The former 0.12 g single-frame
        // veto discarded a real nod near its peak. Use quiet endpoints + native locomotion
        // + axis/rhythm checks; reserve this per-frame veto for an abrupt impact.
        guard sample.acceleration.length < 0.45, sample.rate.length < 4 else {
            reject(.impact, at: sample.time); return false
        }
        guard calibration.neutral.angle(to: baseline ?? gravity) < 38 * .pi / 180 else {
            reset(); previousTime = sample.time; filtered = gravity
            startingPostureOff = true; return false
        }
        startingPostureOff = false
        let quiet = sample.rate.length < 0.30 && sample.acceleration.length < 0.06
        if phase == .settling || phase == .cooldown {
            if quiet {
                if let baseline, baseline.angle(to: gravity) > 2.5 * .pi / 180 { stillSince = nil }
                if stillSince == nil { stillSince = sample.time; baseline = gravity }
                if sample.time - (stillSince ?? sample.time) >= 0.45,
                   phase != .cooldown || sample.time >= cooldownUntil {
                    phase = .armed; baseline = gravity; previousPitch = 0
                    armingReference = gravity; restCandidate = nil; restCandidateSince = nil
                }
            } else { stillSince = nil; if phase != .cooldown { baseline = nil } }
            return false
        }
        guard let baseline else { reset(); return false }
        let pitch = baseline.signedAngle(to: gravity, around: calibration.pitchAxis)
        let roll = baseline.signedAngle(to: gravity, around: calibration.rollAxis)
        let pitchRate = abs(sample.rate.dot(calibration.pitchAxis))
        let yawRate = abs(sample.rate.dot(gravity))
        let otherRate = (sample.rate - calibration.pitchAxis * sample.rate.dot(calibration.pitchAxis)).length
        let rollTolerance = min(15 * .pi / 180, max(8 * .pi / 180, abs(pitch) * 0.35))
        guard abs(roll) < rollTolerance, yawRate < 0.65, pitch > -10 * .pi / 180 else {
            reject(.offAxis, at: sample.time); return false
        }
        let lastPitch = previousPitch
        previousPitch = pitch
        if phase == .armed {
            if pitch >= 2 * .pi / 180 {
                phase = .descending; cycleTime = sample.time; phaseTime = sample.time
                peak = pitch; pitchEnergy = 0; otherEnergy = 0; yawTravel = 0; returnWindow = nil
                restCandidate = nil; restCandidateSince = nil
            } else {
                updateRestReference(gravity, sample: sample, roll: roll, quiet: quiet)
            }
            return false
        }
        pitchEnergy += pitchRate * dt
        otherEnergy += otherRate * dt
        yawTravel += yawRate * dt
        // Six-direction calibration learns the coordinate frame and comfortable envelope,
        // not the minimum amplitude of every control gesture. A 46° calibration must not
        // force a 12° control nod. Require a complete >=6° downward excursion instead.
        let threshold: Double = 6 * .pi / 180
        let maximum = min(85, max(22, calibration.ranges[0] * 180 / .pi * 1.5)) * .pi / 180
        guard sample.time - cycleTime < 1.85 else {
            reject(phase == .returning ? .incomplete : .slow, at: sample.time); return false
        }
        guard yawTravel < 8 * .pi / 180, pitch < maximum else {
            reject(.offAxis, at: sample.time); return false
        }
        if phase == .descending {
            peak = max(peak, pitch)
            guard sample.time - phaseTime < 0.95 else { reject(.slow, at: sample.time); return false }
            if peak < threshold, pitch < peak - 1 * .pi / 180, quiet {
                reject(.small, at: sample.time); return false
            }
            if peak >= threshold && pitch < peak - 2 * .pi / 180 && (pitch - lastPitch) / dt < -0.06 {
                guard sample.time - cycleTime > 0.08 else { reject(.impact, at: sample.time); return false }
                phase = .returning; phaseTime = sample.time
            }
        } else if phase == .returning {
            if pitch > peak + 2 * .pi / 180 { reject(.incomplete, at: sample.time); return false }
            // People do not return to an identical three-degree pose after every nod.
            // Require a quiet endpoint within a bounded fraction of the observed excursion.
            let standard = min(7 * .pi / 180, max(4 * .pi / 180, peak * 0.25))
            let personal = calibration.habit.flatMap { $0.valid ? $0.returnToleranceDegrees : nil } ?? 4
            let tolerance = learningEndpoint ? 7 * .pi / 180 : max(standard, personal * .pi / 180)
            if abs(pitch) <= tolerance {
                let quiet = sample.rate.length < (learningEndpoint ? 0.16 : 0.35)
                    && sample.acceleration.length < (learningEndpoint ? 0.04 : 0.07)
                let mild = sample.rate.length < 0.55 && sample.acceleration.length < 0.10
                if stableReturn(at: sample.time, dt: dt, quiet: quiet, mild: mild),
                   sample.time - cycleTime >= 0.26,
                   sample.time - phaseTime >= 0.08 {
                    guard pitchEnergy > 0.12, pitchEnergy > otherEnergy * 1.8 else {
                        reject(.offAxis, at: sample.time); return false
                    }
                    phase = .cooldown; cooldownUntil = sample.time + 0.85
                    lastAccepted = .init(time: sample.time, peakDegrees: peak * 180 / .pi,
                                         duration: sample.time - cycleTime,
                                         returnStartedAt: returnWindow?.startedAt ?? sample.time,
                                         toleratedReturnDisturbanceSeconds: returnWindow?.disturbedDuration ?? 0,
                                         returnOffsetDegrees: abs(pitch) * 180 / .pi)
                    stillSince = nil; self.baseline = gravity; lastRejection = nil
                    return true
                }
            } else { returnWindow = nil }
        }
        return false
    }
}
