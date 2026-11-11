import Foundation
import Combine

/// One small mailbox shared with the existing audio tap. Capture generations
/// reject stale callbacks after route rebuilds or stopping a session.
final class SpeechLevelInput: @unchecked Sendable {
    private let lock = NSLock()
    private var capture: UUID?
    private var sample: (rms: Float, time: TimeInterval)?
    func begin(_ id: UUID?) { lock.lock(); defer { lock.unlock() }; capture = id; sample = nil }
    func push(rms: Float, at time: TimeInterval, capture id: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard capture == id else { return }
        sample = (rms, time)
    }
    func latest() -> (rms: Float, time: TimeInterval)? { lock.lock(); defer { lock.unlock() }; return sample }
}

@MainActor
final class SpeechAudioMeter: ObservableObject {
    @Published private(set) var level = 0.0
    @Published private(set) var sampledAt: TimeInterval?
    nonisolated let input = SpeechLevelInput()
    private var clock: Task<Void, Never>?
    private var envelope = SpeechLevelEnvelope()
    private var capture: UUID?
    private var displayActive = false

    func start(capture: UUID) {
        stop()
        self.capture = capture
        input.begin(capture)
        if displayActive { startClock() }
    }

    /// Visibility changes only affect visual work, never capture or VAD.
    func setDisplayActive(_ active: Bool) {
        guard active != displayActive else { return }
        displayActive = active
        stopClock()
        if active && capture != nil { startClock() }
    }

    private func startClock() {
        clock = Task { @MainActor [weak self] in
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let sample = self.input.latest()
                let fresh = sample.map { now >= $0.time && now - $0.time < 0.2 } ?? false
                self.sampledAt = fresh ? sample?.time : nil
                self.level = self.envelope.update(rms: fresh ? sample!.rms : 0, deltaTime: now - last)
                last = now
            }
        }
    }
    func stop() {
        capture = nil
        input.begin(nil)
        stopClock()
    }

    private func stopClock() {
        clock?.cancel(); clock = nil
        envelope = .init()
        level = 0; sampledAt = nil
    }
}
