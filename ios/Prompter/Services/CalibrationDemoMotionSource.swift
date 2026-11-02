import CoreMotion
import Foundation

@MainActor
enum HeadphoneMotionSources {
    static func make() -> any HeadphoneMotionSource {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-simulateNodCalibration") { return CalibrationDemoMotionSource() }
        #endif
        return NativeHeadphoneMotionSource()
    }
}

#if DEBUG
/// Explicit UI-test/preview transport. Never compiled into Release; no claim of physical AirPods validation.
@MainActor
final class CalibrationDemoMotionSource: HeadphoneMotionSource {
    var available: Bool { true }
    var authorization: CMAuthorizationStatus { .authorized }
    private var task: Task<Void, Never>?
    private var action: HeadCalibrationAction?
    private var began = 0.0
    private var verification = false
    private var injectedBadUp = false
    private var streamBegan = 0.0

    func perform(_ requested: HeadCalibrationAction, verification: Bool) {
        var action = requested
        if requested == .up && !injectedBadUp && ProcessInfo.processInfo.arguments.contains("-calibrationBadUpOnce") {
            action = .down; injectedBadUp = true
        }
        self.action = action; self.verification = verification
        began = ProcessInfo.processInfo.systemUptime
    }

    func start(on queue: OperationQueue,
               motion: @escaping @Sendable (HeadMotionSample?, String?) -> Void,
               connection: @escaping @Sendable (Bool) -> Void) {
        connection(true)
        streamBegan = ProcessInfo.processInfo.systemUptime
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let sample = self.sample(at: ProcessInfo.processInfo.systemUptime)
                queue.addOperation { motion(sample, nil) }
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            }
        }
    }
    func observeConnections(_ connection: @escaping @Sendable (Bool) -> Void) { connection(true) }
    func stop() { task?.cancel(); task = nil }

    private func sample(at time: Double) -> HeadMotionSample {
        var result = HeadMotionSample(time: time, gravity: .init(x: 0, y: 0, z: -1),
                                      rate: .zero, acceleration: .zero, sensorLocation: 1)
        if action == nil && ProcessInfo.processInfo.arguments.contains("-simulateNodPlayback") {
            let shifted = ProcessInfo.processInfo.arguments.contains("-simulateNodRestShift")
            let streamTime = time - streamBegan
            if ProcessInfo.processInfo.arguments.contains("-simulateEarHandoff"), streamTime >= 1.8 {
                result.sensorLocation = 2
            }
            let shiftProgress = min(1, max(0, (streamTime - 0.9) / 0.6))
            let restingAngle = shifted ? -5 * (1 - cos(.pi * shiftProgress)) / 2 : 0
            let restingRate = shifted && (0.9...1.5).contains(streamTime) ? -5 * .pi / 1.2 * sin(.pi * shiftProgress) : 0
            let restingRadians = restingAngle * .pi / 180
            result.gravity = .init(x: 0, y: sin(restingRadians), z: -cos(restingRadians))
            result.rate.x = restingRate * .pi / 180
            let elapsed = streamTime - (shifted ? 2.8 : 2)
            guard elapsed >= 0 else { return result }
            let large = ProcessInfo.processInfo.arguments.contains("-simulateLargeNodCalibration")
            let natural = ProcessInfo.processInfo.arguments.contains("-simulateNaturalNodPlayback")
            let second = Int(elapsed / 6) % 2 == 1
            let duration = natural ? (second ? 0.8 : 1.2) : large ? 0.8 : 0.65
            let amplitude = natural ? (second ? 30.0 : 8.0) : large ? 40.0 : 20.0
            let u = elapsed.truncatingRemainder(dividingBy: 6) / duration
            let active = u <= 1
            let offset = natural ? (second ? 4.0 : 2.0) * min(1, u) : 0
            let angle = (restingAngle + (active ? amplitude * pow(sin(.pi * u), 2) + offset : offset)) * .pi / 180
            let rate = active ? (amplitude * .pi / duration * sin(2 * .pi * u) + (natural ? (second ? 4.0 : 2.0) / duration : 0)) * .pi / 180 : 0
            result.gravity = .init(x: 0, y: sin(angle), z: -cos(angle)); result.rate.x = rate
            if natural && active {
                result.acceleration.y = 0.1 / 9.80665 * amplitude * .pi / 180 * 2 * .pi * .pi / (duration * duration) * cos(2 * .pi * u)
            }
            return result
        }
        guard let action else { return result }
        let duration = verification ? 0.65 : 2.2
        let u = (time - began - 1.4) / duration
        guard (0...1).contains(u) else { return result }
        let largeCalibration = !verification && action == .down && ProcessInfo.processInfo.arguments.contains("-simulateLargeNodCalibration")
        let amplitude = (action.isTurn ? 30.0 : largeCalibration ? 46.0 : 20.0) * .pi / 180
        let sign = [HeadCalibrationAction.up, .tiltLeft, .turnLeft].contains(action) ? -1.0 : 1.0
        let angle = sign * amplitude * pow(sin(.pi * u), 2)
        let rate = sign * amplitude * .pi / duration * sin(2 * .pi * u)
        switch action {
        case .down, .up:
            result.gravity = .init(x: 0, y: sin(angle), z: -cos(angle))
            result.rate.x = rate
        case .tiltRight, .tiltLeft:
            result.gravity = .init(x: -sin(angle), y: 0, z: -cos(angle))
            result.rate.y = rate
        case .turnRight, .turnLeft:
            result.attitude = .init(z: sin(angle / 2), w: cos(angle / 2))
            result.rate.z = rate
        }
        return result
    }
}
#endif
