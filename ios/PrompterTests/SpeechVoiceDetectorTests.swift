import AVFoundation
import XCTest
@testable import Prompter

final class SpeechVoiceDetectorTests: XCTestCase {
    func testQuietRealSpeechIsDetectedAndSilenceClosesWithoutASREndpoint() throws {
        let model = try XCTUnwrap(SpeechVoiceDetector.bundledModel)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/speech-fixture/test.wav")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Prepare the speech fixture") }
        let audio = try AVAudioFile(forReading: fixture)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
        try audio.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let detector = try SpeechVoiceDetector(model: model)
        var voiceFrames = 0
        var quietVoiceFrames = 0
        for i in stride(from: 0, to: samples.count, by: 512) {
            let frame = samples[i..<min(i + 512, samples.count)].map { $0 * 0.08 }
            if detector.accept(frame) {
                voiceFrames += 1
                if detector.rms < 0.004 { quietVoiceFrames += 1 }
            }
        }
        XCTAssertGreaterThan(voiceFrames, 20)
        XCTAssertGreaterThan(quietVoiceFrames, 10, "Quiet speech rejected by the old RMS floor must still authorize following")
        for _ in 0..<16 { _ = detector.accept(Array(repeating: 0, count: 512)) }
        XCTAssertFalse(detector.accept(Array(repeating: 0, count: 512)), "Silence must close long before ASR's 1.2s endpoint")
        detector.reset()
        XCTAssertFalse(detector.accept(Array(repeating: 0, count: 512)))
    }
}
