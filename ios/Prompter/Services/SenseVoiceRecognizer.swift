import Foundation
import SherpaOnnxC

/// An offline model with repeated bounded utterance snapshots. This is
/// explicitly segmented recognition, not a native streaming decoder.
final class SenseVoiceRecognizer: SpeechGatedRecognizer {
    private let recognizer: OpaquePointer
    private var utterance: [Float] = []
    private var preRoll: [Float] = []
    private var active = false
    private var sinceDecode = 0
    private var segment = 0
    private var previous = ""

    init(directory: URL) throws {
        let model = directory.appendingPathComponent("model.int8.onnx").path
        let tokens = directory.appendingPathComponent("tokens.txt").path
        guard [model, tokens].allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else { throw SpeechEngineError.modelMissing }
        let pointer = model.withCString { model in
            tokens.withCString { tokens in
                "auto".withCString { language in
                    "cpu".withCString { provider in
                        var config = SherpaOnnxOfflineRecognizerConfig()
                        config.feat_config.sample_rate = 16_000
                        config.feat_config.feature_dim = 80
                        config.model_config.sense_voice.model = model
                        config.model_config.sense_voice.language = language
                        config.model_config.sense_voice.use_itn = 1
                        config.model_config.tokens = tokens
                        config.model_config.num_threads = 2
                        config.model_config.provider = provider
                        return SherpaOnnxCreateOfflineRecognizer(&config)
                    }
                }
            }
        }
        guard let pointer else { throw SpeechCaptureError.model }
        recognizer = pointer
    }
    deinit { SherpaOnnxDestroyOfflineRecognizer(recognizer) }

    func resetForReposition() {
        utterance = []; preRoll = []; active = false; sinceDecode = 0; previous = ""; segment += 1
    }
    func accept(_ samples: [Float]) throws -> SpeechRecognitionResult? { try accept(samples, speech: true) }

    func accept(_ samples: [Float], speech: Bool) throws -> SpeechRecognitionResult? {
        if speech {
            if !active { active = true; utterance = preRoll; preRoll = []; sinceDecode = 0 }
            utterance += samples
            sinceDecode += samples.count
            // Start after 0.8s, refresh at most every 0.6s, and bound each
            // snapshot to six seconds so decode cost cannot grow indefinitely.
            if utterance.count >= 96_000 {
                let result = try decode(final: true)
                let overlap = Array(utterance.suffix(4800))
                utterance = overlap; previous = ""; sinceDecode = 0; segment += 1
                return result
            }
            if utterance.count >= 12_800 && sinceDecode >= 9600 {
                sinceDecode = 0
                return try decode(final: false)
            }
        } else {
            if active {
                utterance += samples
                let result = utterance.count >= 3200 ? try decode(final: true) : nil
                utterance = []; previous = ""; sinceDecode = 0; segment += 1; active = false
                preRoll = Array(samples.suffix(4800))
                return result
            }
            preRoll += samples
            if preRoll.count > 4800 { preRoll = Array(preRoll.suffix(4800)) }
        }
        return nil
    }

    private func decode(final: Bool) throws -> SpeechRecognitionResult? {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { throw SpeechCaptureError.model }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        utterance.withUnsafeBufferPointer { SherpaOnnxAcceptWaveformOffline(stream, 16_000, $0.baseAddress, Int32($0.count)) }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { throw SpeechCaptureError.model }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        let text = result.pointee.text.map { String(cString: $0) } ?? ""
        let changed = text != previous
        previous = text
        return final || changed ? .init(text: text, segment: segment, isFinal: final) : nil
    }
}
