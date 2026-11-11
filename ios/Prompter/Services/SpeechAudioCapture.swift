import AVFoundation

struct SpeechAudioCaptureStart {
    var state: SpeechAudioInputState
    var configurationObject: AnyObject?
}

protocol SpeechAudioCaptureBackend: AnyObject {
    func start(receive: @escaping ([Float], Double, TimeInterval) -> Void) throws -> SpeechAudioCaptureStart
    func snapshot() -> SpeechAudioInputState
    func stop()
}

private final class SystemSpeechAudioCapture: SpeechAudioCaptureBackend {
    private let request: CaptureRequest
    private var engine: AVAudioEngine?
    private var hasTap = false
    init(request: CaptureRequest) { self.request = request }

    func start(receive: @escaping ([Float], Double, TimeInterval) -> Void) throws -> SpeechAudioCaptureStart {
        guard request.isActive else { throw CancellationError() }
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
            throw SpeechCaptureError.input
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let frames = Int(buffer.frameLength)
            let count = Int(buffer.format.channelCount)
            var samples = [Float](repeating: 0, count: frames)
            for channel in 0..<count {
                for frame in 0..<frames {
                    let value = buffer.format.isInterleaved ? channels[0][frame * count + channel] : channels[channel][frame]
                    samples[frame] += value / Float(count)
                }
            }
            receive(samples, buffer.format.sampleRate, ProcessInfo.processInfo.systemUptime)
        }
        hasTap = true
        guard request.isActive else { throw CancellationError() }
        engine.prepare()
        guard request.isActive else { throw CancellationError() }
        try engine.start()
        guard engine.isRunning else { throw SpeechCaptureError.input }
        return .init(state: snapshot(), configurationObject: engine)
    }

    func snapshot() -> SpeechAudioInputState {
        guard let engine else { return .init(portIDs: [], sampleRate: 0, channels: 0, running: false) }
        let format = engine.inputNode.outputFormat(forBus: 0)
        return .init(portIDs: AVAudioSession.sharedInstance().currentRoute.inputs.map(\.uid).sorted(),
                     sampleRate: format.sampleRate, channels: Int(format.channelCount), running: engine.isRunning)
    }

    func stop() {
        guard let engine else { return }
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0) }
        hasTap = false
        self.engine = nil
    }
}

/// One capture generation. Cancellation rejects late audio immediately; its
/// queued cleanup also runs when start() finishes after the screen was closed.
final class SpeechAudioCapture: @unchecked Sendable {
    private let queue: CaptureWorkQueue
    private let backend: any SpeechAudioCaptureBackend
    private let request: CaptureRequest

    init(queue: CaptureWorkQueue = .audio, backend: (any SpeechAudioCaptureBackend)? = nil) {
        let request = CaptureRequest()
        self.request = request
        self.queue = queue
        self.backend = backend ?? SystemSpeechAudioCapture(request: request)
    }
    deinit {
        request.cancel()
        let backend = backend
        queue.enqueue { backend.stop() }
    }

    func start(receive: @escaping ([Float], Double, TimeInterval) -> Void) async throws -> SpeechAudioCaptureStart {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await queue.perform {
                guard self.request.isActive else { throw CancellationError() }
                do {
                    let started = try self.backend.start { [request = self.request] samples, rate, time in
                        guard request.isActive else { return }
                        receive(samples, rate, time)
                    }
                    guard self.request.isActive else { throw CancellationError() }
                    return started
                } catch { self.backend.stop(); throw error }
            }
        } onCancel: { self.stop() }
    }
    func snapshot() async throws -> SpeechAudioInputState {
        try await queue.perform { self.backend.snapshot() }
    }
    func stop() {
        request.cancel()
        queue.enqueue { self.backend.stop() }
    }
    func waitUntilStopped() async { await queue.drain() }
}
