import Foundation

/// Blocking hardware calls are ordered here, never on the main actor. Each
/// media kind shares a queue across replacement sessions so teardown wins races.
final class CaptureWorkQueue: @unchecked Sendable {
    static let audio = CaptureWorkQueue(label: "prompter.microphone-hardware")
    static let camera = CaptureWorkQueue(label: "prompter.camera-hardware")
    private let queue: DispatchQueue
    init(label: String) { queue = DispatchQueue(label: label, qos: .userInitiated) }

    func perform<Value>(_ work: @escaping () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: work)) }
        }
    }
    func enqueue(_ work: @escaping () -> Void) { queue.async(execute: work) }
    func drain() async { _ = try? await perform {} }
}

/// Cancellation must be visible while a synchronous start is still blocked.
final class CaptureRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func cancel() { lock.lock(); active = false; lock.unlock() }
}
