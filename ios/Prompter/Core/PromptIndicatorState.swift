import Foundation

struct PromptSpeechFeedback {
    var speaking: Bool
    var alignedAt: TimeInterval?
    var interactionPaused: Bool
}

/// Pure presentation values. None of these values authorize scrolling.
struct PromptIndicatorState: Equatable {
    var progress: Double = 0
    var pulse: Double = 0
    var completed = false

    static func make(progress: Double, level: Double, sampleAt: TimeInterval?, alignedAt: TimeInterval?,
                     speaking: Bool, playing: Bool, interactionPaused: Bool, completed: Bool,
                     at now: TimeInterval) -> Self {
        let freshAudio = sampleAt.map { now >= $0 && now - $0 < 0.25 } ?? false
        let freshMatch = alignedAt.map { now >= $0 && now - $0 < 1.5 } ?? false
        let canPulse = playing && !interactionPaused && speaking && freshAudio && freshMatch && !completed
        return .init(progress: completed ? 1 : bounded(progress), pulse: canPulse ? bounded(level) : 0, completed: completed)
    }

    static func bounded(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
}

/// Display loudness is intentionally independent of the neural VAD. A quiet
/// valid voice must still be visible, without reintroducing an RMS speech gate.
struct SpeechLevelEnvelope {
    private(set) var level = 0.0
    private var peakDB = -32.0

    mutating func update(rms: Float, deltaTime: TimeInterval) -> Double {
        let dt = min(0.2, max(0, deltaTime))
        let amplitude = rms.isFinite ? max(0, Double(rms)) : 0
        let db = 20 * log10(max(0.00000001, amplitude))
        peakDB = min(0, max(-48, max(db, peakDB - 3 * dt)))
        let normalized = PromptIndicatorState.bounded((db + 84) / (peakDB + 84))
        let target = amplitude > 0.00001 ? pow(normalized, 0.7) : 0
        let response = target > level ? 0.055 : 0.32
        level += (target - level) * (1 - exp(-dt / response))
        if level < 0.0001 { level = 0 }
        return level
    }
}
