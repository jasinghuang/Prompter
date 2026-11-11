import Foundation

/// A frame-rate independent position follower. ASR updates its destination;
/// only the display clock advances the position. Speed/acceleration limits keep
/// delayed batches from producing a sudden catch-up jump or spring overshoot.
struct SpeechScrollMotion {
    private(set) var position: Double = 0
    private(set) var velocity: Double = 0
    private var plannedTarget: Double?
    private var destination = 0.0
    private var settling = false
    private var remaining = 0.0
    private var speedLimit = 0.0
    private var acceleration = 0.0

    mutating func reset(to position: Double) {
        self.position = position
        velocity = 0
        plannedTarget = nil
        remaining = 0
    }

    /// The final speed governor may render less than the pursuit proposal.
    /// Rebase position without restarting the proposal's planning/velocity.
    mutating func rebasePosition(to position: Double) { self.position = position }

    /// Apply a floor to this frame's total movement, rather than adding drift
    /// on top of ASR pursuit. Retain its velocity for the next target's ramp.
    mutating func applyMinimumMotion(from previousPosition: Double, distance: Double, speed: Double,
                                     maximumPosition: Double) -> Double {
        let minimum = min(maximumPosition, previousPosition + max(0, distance))
        if minimum > position {
            position = minimum
            velocity = max(velocity, speed)
            plannedTarget = nil
        }
        return position
    }

    mutating func advance(toward target: Double, deltaTime: Double, lineHeight: Double, linesPerSecond: Double = 1,
                          minimumPosition: Double? = nil, settlementRemaining: Double? = nil, allowed: Bool) -> Double {
        guard allowed, target.isFinite, deltaTime.isFinite, deltaTime > 0 else {
            velocity = 0
            plannedTarget = nil
            return position
        }
        let dt = min(deltaTime, 0.05)
        let isSettling = settlementRemaining != nil
        if target != plannedTarget || isSettling != settling {
            plannedTarget = target
            settling = isSettling
            // The optional one-line lead is breathing room, not a deadline.
            // Only the confirmed line falling below the reading zone is urgent.
            let boundary = min(target, minimumPosition ?? target - lineHeight)
            let overdue = max(0, boundary - position)
            destination = target
            if let settlementRemaining {
                remaining = min(0.22, max(0.035, settlementRemaining))
                // Once the line is in place, brake gently instead of racing to
                // complete the optional lead before the silence deadline.
                destination = min(target, max(boundary, position + max(0, velocity) * remaining / 2))
                destination = max(position, destination)
            } else {
                remaining = min(0.7, max(0.42, 0.9 / max(0.1, linesPerSecond)))
                if overdue > 0.1 {
                    remaining = min(remaining, max(0.22, 0.26 * abs(target - position) / overdue))
                }
            }
            let distance = abs(destination - position)
            let normal = lineHeight * min(6, max(1.3, linesPerSecond * 1.2))
            speedLimit = min(max(60, lineHeight * (isSettling ? 18 : 16)), max(normal, distance / max(0.035, remaining * 0.85)))
            acceleration = speedLimit * (overdue > lineHeight ? 16 : 7)
        }
        let distance = destination - position
        guard abs(distance) > 0.1 else { position = destination; velocity = 0; return position }
        let maximumChange = acceleration * dt
        if abs(distance) <= maximumChange * dt / 2 && abs(velocity) <= maximumChange {
            position = destination; velocity = 0; remaining = 0
            return position
        }
        // Brake before the destination, so arriving does not discard a large
        // velocity in one frame. The time-step margin keeps 60/120Hz aligned.
        let brakingSpeed = max(0, sqrt(2 * acceleration * abs(distance)) - maximumChange)
        let allowedSpeed = min(speedLimit, brakingSpeed)
        let desiredVelocity = min(allowedSpeed, max(-allowedSpeed, distance / max(0.035, remaining)))
        let previousVelocity = velocity
        velocity += min(maximumChange, max(-maximumChange, desiredVelocity - velocity))
        if velocity * distance < 0 { velocity = 0 }
        let step = (previousVelocity + velocity) * 0.5 * dt
        if step * distance < 0 { velocity = 0; return position }
        if abs(step) >= abs(distance) { position = destination; velocity = 0 }
        else { position += step }
        remaining = max(0, remaining - dt)
        return position
    }
}

/// Start adjusting immediately, with a critically damped ~2s transition.
/// All filtering applies to rendered motion, including ASR catch-up pulses.
struct SpeechScrollSpeed {
    private(set) var velocity = 0.0
    private var acceleration = 0.0
    private var initialized = false
    private var pauseStartedAt: TimeInterval?
    private var pauseVelocity = 0.0
    private var pauseFloor = 0.0

    mutating func reset() { self = .init() }

    static func pauseBoundary(position: Double, confirmedDestination: Double, velocity: Double, lineHeight: Double) -> Double {
        let floor = min(max(0, velocity), SpeechPauseContinuation.cruisingSpeed(lineHeight: lineHeight))
        // Integral of the two easing phases: 1s at the initial velocity plus
        // 3s at the floor. Include motion already beyond the confirmed target.
        let stop = position + max(0, velocity) + 3 * floor
        return min(confirmedDestination + lineHeight * 4, max(confirmedDestination + lineHeight * 1.6, stop))
    }

    mutating func advance(requested: Double, floor: Double, at time: TimeInterval, deltaTime: Double,
                          lineHeight: Double, initialSpeed: Double? = nil, pause: SpeechPauseContinuation?, remainingDistance: Double,
                          allowed: Bool) -> Double {
        guard allowed, deltaTime > 0, deltaTime.isFinite else { reset(); return 0 }
        let dt = min(0.05, deltaTime)
        if !initialized {
            initialized = true
            velocity = max(floor, min(max(floor, lineHeight * 3), initialSpeed ?? floor))
        }
        let previous = velocity
        if let pause {
            if pauseStartedAt != pause.startedAt {
                pauseStartedAt = pause.startedAt
                pauseVelocity = velocity
                pauseFloor = min(floor, velocity)
            }
            let age = max(0, time - pause.startedAt)
            func ease(_ x: Double) -> Double {
                let t = min(1, max(0, x))
                return t * t * (3 - 2 * t)
            }
            // First spend 2s approaching the cruising floor, then spend 4s
            // approaching zero. Both joins have zero acceleration.
            velocity = age < 2
                ? pauseVelocity + (pauseFloor - pauseVelocity) * ease(age / 2)
                : pauseFloor * (1 - ease((age - 2) / 4))
            acceleration = 0
        } else {
            pauseStartedAt = nil
            let wanted = max(floor, min(max(floor, lineHeight * 3), requested))
            // Exact integration keeps 60/120Hz equivalent. With omega=2.4 a
            // sustained change is ~95% complete after 2s, with no waiting gate.
            let omega = 2.4
            let error = velocity - wanted
            let intermediate = (acceleration + omega * error) * dt
            let decay = exp(-omega * dt)
            velocity = max(0, wanted + (error + intermediate) * decay)
            acceleration = (acceleration - omega * intermediate) * decay
        }
        // Brake gently before the finite lookahead boundary, including when
        // speech continues but alignment has stopped making progress.
        let room = max(0, remainingDistance)
        let braking = sqrt(2 * max(12, lineHeight * 0.4) * room)
        if velocity > braking { velocity = braking; acceleration = min(0, acceleration) }
        let distance = min(room, max(0, (previous + velocity) * 0.5 * dt))
        if distance >= room { velocity = 0; acceleration = 0 }
        return distance
    }
}

/// A short continuation after confirmed speech. Absolute
/// times bound it even if SwiftUI's stop flag arrives late. It is visual motion,
/// never a new recognition/matcher position or an unbounded silence autopilot.
struct SpeechPauseContinuation: Equatable {
    static let duration = 6.0
    static let maximumLineFraction = 1.6
    private static let rampDown = 4.0
    let startedAt: TimeInterval
    var until: TimeInterval { startedAt + Self.duration }

    static func cruisingSpeed(lineHeight: Double) -> Double {
        min(32, max(0, lineHeight) * 0.28)
    }

    func speed(at time: TimeInterval, lineHeight: Double) -> Double {
        let age = time - startedAt
        guard age >= 0, age < Self.duration else { return 0 }
        // Speech already runs at this floor: entering a pause must not restart
        // from zero, which would introduce another visible stop between words.
        return Self.cruisingSpeed(lineHeight: lineHeight) * min(1, (Self.duration - age) / Self.rampDown)
    }

    func distance(from start: TimeInterval, to end: TimeInterval, lineHeight: Double) -> Double {
        func integral(_ time: TimeInterval) -> Double {
            let age = min(Self.duration, max(0, time - startedAt))
            let fadeStart = Self.duration - Self.rampDown
            if age <= fadeStart { return age }
            let tail = age - fadeStart
            return fadeStart + tail - tail * tail / (2 * Self.rampDown)
        }
        guard end > start else { return 0 }
        return max(0, integral(end) - integral(start)) * Self.cruisingSpeed(lineHeight: lineHeight)
    }
}

/// Position-first settlement is limited to already matched text. A silent room
/// cannot start it without recent speech, and touching still freezes instantly.
struct SpeechFollowSettlement {
    private(set) var until: TimeInterval?
    private(set) var pendingEnd = false
    private var confirmedOffset: Int?
    private var confirmedAt: TimeInterval?
    private var pauseBegan: TimeInterval?

    mutating func matched(offset: Int, final: Bool, reachedEnd: Bool, at time: TimeInterval) {
        if confirmedOffset == nil || offset > confirmedOffset! {
            confirmedOffset = offset
            confirmedAt = time
            until = time + 0.3
        }
        if final {
            pendingEnd = reachedEnd
            if reachedEnd { confirmedAt = time; until = time + 0.3 }
        }
    }
    mutating func voiceStopped(at time: TimeInterval) {
        pauseBegan = time
        if let confirmedAt, time - confirmedAt <= 1.5 { until = time + 0.3 }
    }
    mutating func voiceResumed() { pauseBegan = nil }
    func pauseContinuation(at time: TimeInterval, lastVoice: TimeInterval?) -> SpeechPauseContinuation? {
        guard !pendingEnd, let pauseBegan, let confirmedAt, let lastVoice,
              pauseBegan >= lastVoice, pauseBegan - lastVoice < 0.65,
              confirmedAt >= pauseBegan - 1.5, confirmedAt <= time,
              time >= pauseBegan else { return nil }
        let window = SpeechPauseContinuation(startedAt: pauseBegan)
        return time < window.until ? window : nil
    }
    func canSettle(at time: TimeInterval, lastVoice: TimeInterval?) -> Bool {
        guard let until, let lastVoice else { return false }
        return time < until && time - lastVoice < 2 && time >= lastVoice
    }
    func completionReady(delta: Double?, voice: Bool, at time: TimeInterval) -> Bool {
        guard pendingEnd else { return false }
        if let delta, delta <= 0 { return true }
        return !voice && until.map { time >= $0 } == true
    }
}

/// The 1.5s delay starts at finger-up. Inertia may delay handoff, but ending
/// inertia never restarts the delay. A fresh touch cancels the old handoff.
struct SpeechTouchHandoff {
    private(set) var isSuspended = false
    private var touching = false
    private var scrolling = false
    private var resumeAt: TimeInterval?

    mutating func touchBegan() { isSuspended = true; touching = true; resumeAt = nil }
    mutating func touchEnded(at time: TimeInterval) { touching = false; resumeAt = time + 1.5 }
    mutating func scrollingBegan() { isSuspended = true; scrolling = true }
    mutating func scrollingEnded() { scrolling = false }
    func delayUntilResume(at time: TimeInterval) -> TimeInterval? {
        guard isSuspended, !touching, !scrolling, let resumeAt else { return nil }
        return max(0, resumeAt - time)
    }
    mutating func reset() { self = .init() }
}
