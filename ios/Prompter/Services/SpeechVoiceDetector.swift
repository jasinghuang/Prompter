import Foundation
import SherpaOnnxC

/// Shared speech/non-speech decisions for every recognizer. Loudness alone
/// cannot distinguish quiet speech from silence; the ASR text matcher still
/// independently authorizes every destination change.
final class SpeechVoiceDetector {
    private let detector: OpaquePointer
    private(set) var rms: Float = 0
    private var nearZeroSamples = 0
    private var resetForSilence = false

    init(model: URL) throws {
        guard FileManager.default.fileExists(atPath: model.path) else { throw SpeechCaptureError.model }
        let pointer = model.path.withCString { path in
            "cpu".withCString { provider in
                var config = SherpaOnnxVadModelConfig()
                config.silero_vad.model = path
                config.silero_vad.threshold = 0.5
                config.silero_vad.min_silence_duration = 0.18
                config.silero_vad.min_speech_duration = 0.064
                config.silero_vad.max_speech_duration = 20
                config.silero_vad.window_size = 512
                config.sample_rate = 16_000
                config.num_threads = 1
                config.provider = provider
                return SherpaOnnxCreateVoiceActivityDetector(&config, 30)
            }
        }
        guard let pointer else { throw SpeechCaptureError.model }
        detector = pointer
    }

    deinit { SherpaOnnxDestroyVoiceActivityDetector(detector) }

    func accept(_ samples: [Float]) -> Bool {
        if !samples.isEmpty {
            rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
            nearZeroSamples = rms < 0.0001 ? nearZeroSamples + samples.count : 0
            if nearZeroSamples == 0 { resetForSilence = false }
            samples.withUnsafeBufferPointer {
                SherpaOnnxVoiceActivityDetectorAcceptWaveform(detector, $0.baseAddress, Int32($0.count))
            }
        }
        // The teleprompter needs the current state, not copies of old audio.
        while SherpaOnnxVoiceActivityDetectorEmpty(detector) == 0 {
            SherpaOnnxVoiceActivityDetectorPop(detector)
        }
        // A neural state may linger after an utterance. Near-digital silence
        // has an explicit upper bound; quiet speech is still decided by VAD,
        // without the previous 0.004 RMS floor.
        if nearZeroSamples >= 2880 {
            if !resetForSilence {
                SherpaOnnxVoiceActivityDetectorReset(detector)
                resetForSilence = true
            }
            return false
        }
        return SherpaOnnxVoiceActivityDetectorDetected(detector) != 0
    }

    func reset() {
        SherpaOnnxVoiceActivityDetectorReset(detector)
        rms = 0; nearZeroSamples = 0; resetForSilence = false
    }

    static var bundledModel: URL? {
        Bundle.main.url(forResource: "SpeechSupport", withExtension: nil)?.appendingPathComponent("silero_vad.onnx")
    }
}
