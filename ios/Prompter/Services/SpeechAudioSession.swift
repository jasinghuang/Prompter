import AVFoundation
import Foundation

@MainActor
protocol SpeechAudioSessionBackend {
    func activate() async throws
    func deactivate() async throws
}

/// iOS 27 provides nonblocking activation APIs. Keep the iOS 17 fallback, and
/// category configuration, off the main thread rather than wrapping synchronous
/// calls in a main-actor Task (which would still block the UI).
@MainActor
private final class SystemSpeechAudioSession: SpeechAudioSessionBackend {
    private let queue = DispatchQueue(label: "prompter.audio-session", qos: .userInitiated)

    func activate() async throws {
        let session = AVAudioSession.sharedInstance()
        try await background {
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        }
        if #available(iOS 27.0, *) {
            guard try await session.activate(options: []) else { throw SpeechCaptureError.input }
        } else {
            try await background { try session.setActive(true) }
        }
    }

    func deactivate() async throws {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            guard try await session.deactivate(options: [.notifyOthersOnDeactivation]) else {
                throw SpeechCaptureError.input
            }
        } else {
            try await background { try session.setActive(false, options: .notifyOthersOnDeactivation) }
        }
    }

    private func background(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do { try work(); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// AVAudioSession is app-wide. Chain entire asynchronous operations, including
/// their completions, so a cancelled activation is released before the next one.
/// An actor by itself would not provide this ordering across suspension points.
@MainActor
final class SpeechAudioSessionCoordinator {
    static let shared = SpeechAudioSessionCoordinator()
    private let backend: any SpeechAudioSessionBackend
    private var tail: Task<Void, Never>?
    private var requestedOwner: UUID?
    private var activeOwner: UUID?

    init(backend: (any SpeechAudioSessionBackend)? = nil) {
        self.backend = backend ?? SystemSpeechAudioSession()
    }

    func activate(owner: UUID) async throws {
        try Task.checkCancellation()
        let previous = tail
        requestedOwner = owner
        let activation = Task { @MainActor in
            await previous?.value
            guard self.requestedOwner == owner else { throw CancellationError() }
            self.activeOwner = owner
            do {
                try await self.backend.activate()
            } catch {
                // Activation may have configured hardware before failing.
                try? await self.backend.deactivate()
                self.activeOwner = nil
                throw error
            }
        }
        tail = Task { _ = try? await activation.value }
        try await withTaskCancellationHandler {
            try await activation.value
            try Task.checkCancellation()
        } onCancel: {
            // Never cancel the underlying hardware operation halfway through;
            // enqueue its cleanup after completion instead.
            Task { @MainActor in self.release(owner: owner) }
        }
    }

    func release(owner: UUID) {
        guard requestedOwner == owner else { return }
        requestedOwner = nil
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            guard self.activeOwner == owner else { return }
            try? await self.backend.deactivate()
            self.activeOwner = nil
        }
    }

    func waitForIdle() async { await tail?.value }
}
