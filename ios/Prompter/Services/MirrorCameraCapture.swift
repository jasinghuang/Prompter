import AVFoundation

enum MirrorCameraFailure: LocalizedError {
    case unavailable, startFailed, previewTimeout
    case runtime(AVError.Code?)
    case interrupted(AVCaptureSession.InterruptionReason?)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "未能打开前置摄像头，请确认系统相机可用后重试"
        case .startFailed: return "摄像头未能启动，请稍后重试"
        case .previewTimeout: return "摄像头没有传回预览画面，已释放设备。请确认系统相机可用后重试"
        case .runtime(.mediaServicesWereReset): return "系统相机服务已重置，已释放设备。请重试"
        case .runtime: return "摄像头运行出错，已释放设备。请重试"
        case .interrupted(.videoDeviceNotAvailableDueToSystemPressure):
            return "设备负载或温度过高，相机已暂停。请稍后重试"
        case .interrupted(.videoDeviceInUseByAnotherClient), .interrupted(.audioDeviceInUseByAnotherClient):
            return "相机被其他应用占用，已暂停。请稍后重试"
        case .interrupted: return "相机预览已被系统中断，已释放设备。请重试"
        }
    }
}

/// Queue-confined video-only capture. Old sessions finish stopping before a
/// replacement can configure the same camera, including rapid close/retry.
final class MirrorCameraCapture: @unchecked Sendable {
    let session = AVCaptureSession()
    private let request = CaptureRequest()
    private let queue = CaptureWorkQueue.camera

    deinit {
        request.cancel()
        let session = session
        queue.enqueue { Self.release(session) }
    }

    func start() async throws -> AVCaptureDevice {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await queue.perform {
                guard self.request.isActive else { throw CancellationError() }
                do {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                        throw MirrorCameraFailure.unavailable
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    self.session.automaticallyConfiguresApplicationAudioSession = false
                    if self.session.canSetSessionPreset(.hd1280x720) { self.session.sessionPreset = .hd1280x720 }
                    guard self.session.canAddInput(input) else {
                        self.session.commitConfiguration()
                        throw MirrorCameraFailure.unavailable
                    }
                    self.session.addInput(input)
                    self.session.commitConfiguration()
                    guard self.request.isActive else { throw CancellationError() }
                    self.session.startRunning()
                    guard self.request.isActive else { throw CancellationError() }
                    guard self.session.isRunning else { throw MirrorCameraFailure.startFailed }
                    return device
                } catch { Self.release(self.session); throw error }
            }
        } onCancel: { self.stop() }
    }

    func stop() {
        request.cancel()
        let session = session
        queue.enqueue { Self.release(session) }
    }
    func waitUntilStopped() async { await queue.drain() }

    private static func release(_ session: AVCaptureSession) {
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
    }
}
