import Foundation

struct SpeechAudioInputState: Equatable {
    var portIDs: [String]
    var sampleRate: Double
    var channels: Int
    var running: Bool

    var isAvailable: Bool { !portIDs.isEmpty && sampleRate > 0 && channels > 0 }
}

enum SpeechAudioChange {
    case interruptionBegan, interruptionEnded, route, configuration, mediaServices
}

enum SpeechAudioChangeAction: Equatable {
    case keepRecording, rebuildEngine, pause(SpeechCaptureError)

    static func evaluate(_ change: SpeechAudioChange, previous: SpeechAudioInputState,
                         current: SpeechAudioInputState) -> Self {
        switch change {
        case .interruptionBegan: return .pause(.interrupted)
        case .interruptionEnded: return .keepRecording
        case .mediaServices: return .pause(.mediaServices)
        case .route, .configuration:
            guard current.isAvailable else { return .pause(.input) }
            guard current.portIDs == previous.portIDs else { return .pause(.inputChanged) }
            // Output/category changes and delayed startup notifications do not
            // invalidate a healthy, unchanged microphone stream.
            if current.running && current.sampleRate == previous.sampleRate && current.channels == previous.channels {
                return .keepRecording
            }
            // AVAudioEngine stops itself on hardware format changes. Recreate
            // the tap at its new format instead of treating this as a call.
            return .rebuildEngine
        }
    }
}

struct SpeechCaptureRecoveryBudget {
    private var attempts: [TimeInterval] = []
    mutating func request(at now: TimeInterval) -> Bool {
        attempts.removeAll { now - $0 >= 5 }
        guard attempts.count < 2 else { return false }
        attempts.append(now)
        return true
    }
}
