import Foundation

enum BundledSpeechModels {
    // Signed bundle resources cannot change during this process. Cache both
    // successful lookups and missing assets; Swift initializes each once.
    static let senseVoice: URL? = {
        guard let root = Bundle.main.url(forResource: "SenseVoiceModel", withExtension: nil),
              (try? String(contentsOf: root.appendingPathComponent("verified"), encoding: .utf8)) == "2024-07-17",
              ["model.int8.onnx", "tokens.txt"].allSatisfy({ FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }) else { return nil }
        return root
    }()

    static let zipformer: URL? = {
        guard let root = Bundle.main.url(forResource: "ZipformerModel", withExtension: nil),
              (try? String(contentsOf: root.appendingPathComponent("verified"), encoding: .utf8)) == "2025-06-30",
              ["encoder.int8.onnx", "decoder.onnx", "joiner.int8.onnx", "tokens.txt"].allSatisfy({ FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }) else { return nil }
        return root
    }()
}
