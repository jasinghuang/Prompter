import AVFoundation
import UIKit

/// Owns notification registration and rejects already-enqueued callbacks after
/// stop. The view independently checks which capture generation is visible.
@MainActor
final class MirrorCameraSessionObserver {
    private var observers: [NSObjectProtocol] = []
    private let request = CaptureRequest()

    init(session: AnyObject, failure: @escaping (MirrorCameraFailure) -> Void) {
        func observe(_ name: Notification.Name, object: Any?, map: @escaping (Notification) -> MirrorCameraFailure) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [request] notification in
                Task { @MainActor in
                    guard request.isActive else { return }
                    failure(map(notification))
                }
            })
        }
        observe(AVCaptureSession.runtimeErrorNotification, object: session) { notification in
            .runtime((notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code)
        }
        observe(AVCaptureSession.wasInterruptedNotification, object: session) { notification in
            let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)
                .flatMap { AVCaptureSession.InterruptionReason(rawValue: $0.intValue) }
            return .interrupted(reason)
        }
        observe(AVCaptureSession.didStopRunningNotification, object: session) { _ in .startFailed }
        observe(UIApplication.didEnterBackgroundNotification, object: nil) { _ in
            .interrupted(.videoDeviceNotAvailableInBackground)
        }
    }
    func stop() {
        request.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
    deinit {
        request.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
