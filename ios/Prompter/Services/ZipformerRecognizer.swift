import Foundation
import SherpaOnnxC

/// Same streaming interface and capture/VAD/alignment as Paraformer; only the
/// acoustic recognizer changes during a comparison session.
final class ZipformerRecognizer: LocalSpeechRecognizer {
    private let recognizer: OpaquePointer
    private var stream: OpaquePointer
    private var previous = ""
    private var segment = 0

    init(directory: URL) throws {
        let names = ["encoder.int8.onnx", "decoder.onnx", "joiner.int8.onnx", "tokens.txt"]
        let paths = names.map { directory.appendingPathComponent($0).path }
        guard paths.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else { throw SpeechEngineError.modelMissing }
        let pointer = paths[0].withCString { encoder in
            paths[1].withCString { decoder in
                paths[2].withCString { joiner in
                    paths[3].withCString { tokens in
                        "cpu".withCString { provider in
                            "zipformer2".withCString { type in
                                "greedy_search".withCString { method in
                                    var config = SherpaOnnxOnlineRecognizerConfig()
                                    config.feat_config.sample_rate = 16_000
                                    config.feat_config.feature_dim = 80
                                    config.model_config.transducer.encoder = encoder
                                    config.model_config.transducer.decoder = decoder
                                    config.model_config.transducer.joiner = joiner
                                    config.model_config.tokens = tokens
                                    config.model_config.num_threads = 2
                                    config.model_config.provider = provider
                                    config.model_config.model_type = type
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

    func resetForReposition() throws {
        guard let fresh = SherpaOnnxCreateOnlineStream(recognizer) else { throw SpeechCaptureError.model }
        SherpaOnnxDestroyOnlineStream(stream)
        stream = fresh
        previous = ""
        segment += 1
    }

    func accept(_ samples: [Float]) throws -> SpeechRecognitionResult? {
        samples.withUnsafeBufferPointer { SherpaOnnxOnlineStreamAcceptWaveform(stream, 16_000, $0.baseAddress, Int32($0.count)) }
        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0 { SherpaOnnxDecodeOnlineStream(recognizer, stream) }
        guard let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else { throw SpeechCaptureError.model }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(result) }
        let text = result.pointee.text.map { String(cString: $0) } ?? ""
        let final = SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) != 0
        let changed = text != previous
        let current = segment
        previous = text
        if final {
            SherpaOnnxOnlineStreamReset(recognizer, stream)
            previous = ""
            segment += 1
        }
        return changed || final ? .init(text: text, segment: current, isFinal: final) : nil
    }
}
