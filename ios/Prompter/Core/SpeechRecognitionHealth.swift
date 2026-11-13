import Foundation

/// Service liveness, independent of script alignment and scroll timing. Only
/// unanswered speech counts; silence and unmatching but valid text are healthy.
struct SpeechRecognitionHealth {
    var timeout: TimeInterval = 10
    private var lastAudio: TimeInterval?
    private var unansweredSince: TimeInterval?
    private var voicedDuration = 0.0

    mutating func observeAudio(at time: TimeInterval, voice: Bool) {
        guard time.isFinite, lastAudio.map({ time >= $0 }) ?? true else { return }
        let delta = lastAudio.map { min(0.1, max(0, time - $0)) } ?? 0
        lastAudio = time
        if voice {
            // A brief earlier noise must not consume a later reader's deadline.
            if let since = unansweredSince, voicedDuration < 1, time - since >= timeout {
                unansweredSince = nil; voicedDuration = 0
            }
            if unansweredSince == nil { unansweredSince = time }
            voicedDuration += delta
        }
    }
    mutating func receivedText() { unansweredSince = nil; voicedDuration = 0 }

    func isWaitingForText(at time: TimeInterval) -> Bool {
        guard let unansweredSince else { return false }
        return voicedDuration >= 0.25 && time - unansweredSince >= 2
    }
    func hasTimedOut(at time: TimeInterval) -> Bool {
        guard let unansweredSince else { return false }
        return voicedDuration >= 1 && time - unansweredSince >= timeout
    }
}
