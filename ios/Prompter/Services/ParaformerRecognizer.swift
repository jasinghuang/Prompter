import Foundation
import SherpaOnnxC

/// Queue-confined, fallible C API ownership. Invalid assets/configuration produce
/// an error rather than the force-unwrapped pointers in the sample Swift wrapper.
final class ParaformerRecognizer: LocalSpeechRecognizer {
    private let recognizer: OpaquePointer
    private var stream: OpaquePointer
    private var previous = ""
    private(set) var segment = 0

    init(directory: URL) throws {
        let encoder = directory.appendingPathComponent("encoder.int8.onnx").path
        let decoder = directory.appendingPathComponent("decoder.int8.onnx").path
        let tokens = directory.appendingPathComponent("tokens.txt").path
        let pointer = encoder.withCString { encoder in
            decoder.withCString { decoder in
                tokens.withCString { tokens in
                    "cpu".withCString { provider in
                        "paraformer".withCString { modelType in
                            "greedy_search".withCString { method in
                                var config = SherpaOnnxOnlineRecognizerConfig()
                                config.feat_config.sample_rate = 16_000
                                config.feat_config.feature_dim = 80
                                config.model_config.paraformer.encoder = encoder
                                config.model_config.paraformer.decoder = decoder
                                config.model_config.tokens = tokens
                                config.model_config.num_threads = 2
                                config.model_config.provider = provider
                                config.model_config.model_type = modelType
                                config.decoding_method = method
                                config.max_active_paths = 4
                                config.enable_endpoint = 1
                                config.rule1_min_trailing_silence = 2.4
                                config.rule2_min_trailing_silence = 1.2
                                config.rule3_min_utterance_length = 20
                                return SherpaOnnxCreateOnlineRecognizer(&config)
                            }
                        }
                    }
                }
            }
        }
        guard let pointer else { throw SpeechCaptureError.model }
        guard let stream = SherpaOnnxCreateOnlineStream(pointer) else {
            SherpaOnnxDestroyOnlineRecognizer(pointer)
            throw SpeechCaptureError.model
        }
        recognizer = pointer
        self.stream = stream
    }

    deinit {
        SherpaOnnxDestroyOnlineStream(stream)
        SherpaOnnxDestroyOnlineRecognizer(recognizer)
    }

    typealias Result = SpeechRecognitionResult

    func resetForReposition() throws {
        // Endpoint reset intentionally retains feature/audio history in sherpa.
        // A manual seek needs a fresh stream, while reusing the loaded model.
        guard let fresh = SherpaOnnxCreateOnlineStream(recognizer) else { throw SpeechCaptureError.model }
        SherpaOnnxDestroyOnlineStream(stream)
        stream = fresh
        segment += 1
        previous = ""
    }

    func accept(_ samples: [Float]) throws -> Result? {
        samples.withUnsafeBufferPointer {
            SherpaOnnxOnlineStreamAcceptWaveform(stream, 16_000, $0.baseAddress, Int32($0.count))
        }
        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0 {
            SherpaOnnxDecodeOnlineStream(recognizer, stream)
        }
        guard let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else { throw SpeechCaptureError.model }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(result) }
        let text = result.pointee.text.map { String(cString: $0) } ?? ""
        let final = SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) != 0
        let changed = text != previous
        let current = segment
        previous = text
        if final {
            SherpaOnnxOnlineStreamReset(recognizer, stream)
            segment += 1
            previous = ""
        }
        return changed || final ? .init(text: text, segment: current, isFinal: final) : nil
    }
}
