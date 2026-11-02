import CoreMotion
import Foundation
import OSLog

/// Native transport boundary. Injectable so startup/disconnect ordering can be tested without AirPods.
@MainActor
protocol HeadphoneMotionSource: AnyObject {
    var available: Bool { get }
    var authorization: CMAuthorizationStatus { get }
    func start(on queue: OperationQueue,
               motion: @escaping @Sendable (HeadMotionSample?, String?) -> Void,
               connection: @escaping @Sendable (Bool) -> Void)
    func observeConnections(_ connection: @escaping @Sendable (Bool) -> Void)
    func stop()
}

@MainActor
final class NativeHeadphoneMotionSource: HeadphoneMotionSource {
    private let manager = CMHeadphoneMotionManager()
    private var delegate: ConnectionDelegate?
    private var activityMonitor: AnyObject?
    private var motionRequested = false
    private var connectionRequested = false
    var available: Bool { manager.isDeviceMotionAvailable }
    var authorization: CMAuthorizationStatus { CMHeadphoneMotionManager.authorizationStatus() }

    private final class ConnectionDelegate: NSObject, CMHeadphoneMotionManagerDelegate, @unchecked Sendable {
        let receive: @Sendable (Bool) -> Void
        init(_ receive: @escaping @Sendable (Bool) -> Void) { self.receive = receive }
        func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) { receive(true) }
        func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) { receive(false) }
    }
    private final class ActivityState: @unchecked Sendable {
        // Only read/written on the supplied serial operation queue.
        var moving = false
    }

    func start(on queue: OperationQueue,
               motion: @escaping @Sendable (HeadMotionSample?, String?) -> Void,
               connection: @escaping @Sendable (Bool) -> Void) {
        let delegate = ConnectionDelegate(connection)
        self.delegate = delegate; manager.delegate = delegate
        let activityState = ActivityState()
        if #available(iOS 18.0, *) {
            let activity = CMHeadphoneActivityManager()
            if activity.isActivityAvailable {
                activityMonitor = activity
                activity.startActivityUpdates(to: queue) { activity, error in
                    guard error == nil, let activity else { return }
                    activityState.moving = activity.walking || activity.running
                }
            }
        }
        // Motion updates already deliver connection delegate events. Do not start a second
        // connection-status service alongside them or stop/restart an idle native stream.
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.jasing.prompter", category: "AirPodsMotion")
        motionRequested = true
        manager.startDeviceMotionUpdates(to: queue) { data, error in
            if let error {
                let native = error as NSError
                logger.error("Headphone motion service error: \(native.domain, privacy: .public) / \(native.code)")
                motion(nil, "耳机运动数据不可用，请检查运动权限后重试。")
                return
            }
            // A callback without data is not proof of a Bluetooth disconnection.
            guard let data else { return }
            let q = data.attitude.quaternion
            var sample = HeadMotionSample(time: data.timestamp,
                gravity: .init(x: data.gravity.x, y: data.gravity.y, z: data.gravity.z),
                rate: .init(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z),
                acceleration: .init(x: data.userAcceleration.x, y: data.userAcceleration.y, z: data.userAcceleration.z),
                attitude: .init(x: q.x, y: q.y, z: q.z, w: q.w), sensorLocation: data.sensorLocation.rawValue)
            sample.locomotionDetected = activityState.moving
            motion(sample, nil)
        }
    }

    func observeConnections(_ connection: @escaping @Sendable (Bool) -> Void) {
        let delegate = ConnectionDelegate(connection)
        self.delegate = delegate; manager.delegate = delegate
        if !connectionRequested {
            connectionRequested = true
            manager.startConnectionStatusUpdates()
        }
    }

    func stop() {
        // Detach before stopping. Each subsequent stream uses a new source/delegate instance.
        manager.delegate = nil; delegate = nil
        if motionRequested { manager.stopDeviceMotionUpdates() }
        if connectionRequested { manager.stopConnectionStatusUpdates() }
        motionRequested = false; connectionRequested = false
        if #available(iOS 18.0, *) { (activityMonitor as? CMHeadphoneActivityManager)?.stopActivityUpdates() }
        activityMonitor = nil
    }
}

/// Connection notifications are hints; valid samples and elapsed time establish stream health.
struct HeadMotionStreamHealth {
    private(set) var startedAt: Double?
    private(set) var lastSampleAt: Double?
    private(set) var permissionPending = false
    static let startupGrace = 10.0
    static let interruptionGrace = 3.0

    mutating func start(at time: Double) { startedAt = time; lastSampleAt = nil; permissionPending = false }
    mutating func receivedSample(at time: Double) { lastSampleAt = time }
    mutating func stop() { startedAt = nil; lastSampleAt = nil; permissionPending = false }
    mutating func waitForPermission(at time: Double, pending: Bool) {
        if pending || permissionPending { startedAt = time }
        permissionPending = pending
    }
    func hasRecentSample(at time: Double) -> Bool {
        lastSampleAt.map { time - $0 < Self.interruptionGrace } ?? false
    }
    func timeout(at time: Double) -> String? {
        guard !permissionPending, let startedAt else { return nil }
        if let lastSampleAt {
            return time - lastSampleAt >= Self.interruptionGrace
                ? "耳机运动数据持续中断，请检查佩戴和连接后重试。" : nil
        }
        return time - startedAt >= Self.startupGrace
            ? "尚未收到耳机运动数据。请确认耳机支持头部运动、已正确佩戴，并允许运动权限后重试。" : nil
    }
}
