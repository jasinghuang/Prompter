import AVFoundation
import XCTest
@testable import Prompter

final class SpeechEngineTests: XCTestCase {
    func testAsyncPartialsReplaceButFinalsAndNewSegmentsRemainOrdered() throws {
        let box = SpeechResultMailbox()
        let generation = box.reset()
        box.append(.init(text: "今天", segment: 0, isFinal: false), generation: generation)
        box.append(.init(text: "今天开始", segment: 0, isFinal: false), generation: generation)
        box.append(.init(text: "今天开始介绍", segment: 0, isFinal: true), generation: generation)
        box.append(.init(text: "下一句", segment: 1, isFinal: false), generation: generation)
        XCTAssertEqual(try box.take()?.text, "今天开始介绍")
        XCTAssertEqual(try box.take()?.text, "下一句")
        XCTAssertNil(try box.take())
    }

    func testSeekDiscardsStaleNativeResultsAndErrors() throws {
        let box = SpeechResultMailbox()
        let old = box.reset()
        box.append(.init(text: "上一个位置", segment: 0, isFinal: false), generation: old)
        let current = box.reset()
        box.append(.init(text: "过期回调", segment: 0, isFinal: true), generation: old)
        box.fail(SpeechCaptureError.overloaded, generation: old)
        box.append(.init(text: "当前的位置", segment: 1, isFinal: false), generation: current)
        XCTAssertEqual(try box.take()?.text, "当前的位置")
        XCTAssertNil(try box.take())
    }

    func testNativeWordFinalsAccumulateAndVolatileCorrectionsReplaceOnlyTheirRange() throws {
        var transcript = SpeechTranscriptAssembler()
        _ = transcript.update(rangeStart: 0, rangeEnd: 1, fragments: [.init(start: 0, end: 1, text: "今天")], finalizedThrough: 1, segment: 0)
        _ = transcript.update(rangeStart: 1, rangeEnd: 2, fragments: [.init(start: 1, end: 2, text: "我们")], finalizedThrough: 2, segment: 0)
        let provisional = try XCTUnwrap(transcript.update(rangeStart: 2, rangeEnd: 3,
            fragments: [.init(start: 2, end: 3, text: "介少")], finalizedThrough: 2, segment: 0))
        XCTAssertEqual(provisional.text, "今天我们介少")
        XCTAssertFalse(provisional.isFinal)
        let corrected = try XCTUnwrap(transcript.update(rangeStart: 2, rangeEnd: 3,
            fragments: [.init(start: 2, end: 3, text: "介绍")], finalizedThrough: 3, segment: 0))
        XCTAssertEqual(corrected.text, "今天我们介绍")
        XCTAssertTrue(corrected.isFinal)
        var matcher = SpeechScriptMatcher(content: "今天我们介绍本地跟随")
        XCTAssertEqual(try XCTUnwrap(matcher.match(corrected.text)).tokenEnd, 6)
    }

    func testEarlierNativeFinalCannotFinalizeAnUnconfirmedTail() throws {
        var transcript = SpeechTranscriptAssembler()
        _ = transcript.update(rangeStart: 0, rangeEnd: 2, fragments: [
            .init(start: 0, end: 1, text: "今天"), .init(start: 1, end: 2, text: "开始")], finalizedThrough: 0, segment: 0)
        let result = try XCTUnwrap(transcript.update(rangeStart: 0, rangeEnd: 1,
            fragments: [.init(start: 0, end: 1, text: "今天")], finalizedThrough: 1, segment: 0))
        XCTAssertEqual(result.text, "今天开始")
        XCTAssertFalse(result.isFinal)
    }

    func testNativeBacklogIsBoundedInsteadOfSilentlyDroppingAudioContext() {
        let box = SpeechResultMailbox()
        let generation = box.reset()
        for i in 0..<33 { box.append(.init(text: "测试", segment: i, isFinal: true), generation: generation) }
        XCTAssertThrowsError(try box.take())
    }

    func testEnginePreferencesPreserveLegacyDefaultsAndRoundTrip() throws {
        XCTAssertEqual(try JSONDecoder().decode(SettingsData.self, from: Data("{}".utf8)).speechEngine, .paraformer)
        XCTAssertEqual(try JSONDecoder().decode(SettingsData.self, from: Data(#"{"speechEngine":"future"}"#.utf8)).speechEngine, .paraformer)
        var settings = SettingsData()
        settings.speechEngine = .apple
        settings.showSpeechDiagnostics = true
        let decoded = try JSONDecoder().decode(SettingsData.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.speechEngine, .apple)
        XCTAssertTrue(decoded.showSpeechDiagnostics)
    }

    func testSenseVoiceProducesSegmentSnapshotsAndFreshOutputAfterSeek() throws {
        let directory = try XCTUnwrap(BundledSpeechModels.senseVoice)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/speech-fixture/test.wav")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Prepare the speech fixture") }
        let audio = try AVAudioFile(forReading: fixture)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
        try audio.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let recognizer = try SenseVoiceRecognizer(directory: directory)
        func decode() throws -> [SpeechRecognitionResult] {
            var results: [SpeechRecognitionResult] = []
            for i in stride(from: 0, to: samples.count, by: 1600) {
                if let result = try recognizer.accept(Array(samples[i..<min(i + 1600, samples.count)]), speech: true) { results.append(result) }
            }
            if let result = try recognizer.accept(Array(repeating: 0, count: 3200), speech: false) { results.append(result) }
            return results
        }
        let baseline = try decode()
        XCTAssertTrue(baseline.contains(where: { !$0.isFinal && !$0.text.isEmpty }))
        XCTAssertTrue(baseline.contains(where: { $0.isFinal }))
        XCTAssertTrue(baseline.contains(where: { $0.text.contains("昨天") }))
        recognizer.resetForReposition()
        XCTAssertEqual(try decode().map(\.text), baseline.map(\.text))
    }

    func testRealZipformerEmitsIncrementalChineseAndStartsCleanAfterSeek() throws {
        let directory = try XCTUnwrap(BundledSpeechModels.zipformer)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/speech-fixture/test.wav")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Prepare the speech fixture") }
        let audio = try AVAudioFile(forReading: fixture)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
        try audio.read(into: buffer)
        var samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        samples += Array(repeating: 0, count: 32_000)
        let recognizer = try ZipformerRecognizer(directory: directory)
        func decode() throws -> [String] {
            var partials: [String] = []
            for i in stride(from: 0, to: samples.count, by: 1600) {
                if let result = try recognizer.accept(Array(samples[i..<min(i + 1600, samples.count)])), !result.text.isEmpty {
                    partials.append(result.text)
                }
            }
            return partials
        }
        let baseline = try decode()
        XCTAssertGreaterThan(baseline.count, 3)
        XCTAssertTrue(baseline.contains(where: { $0.contains("昨天") }))
        _ = try recognizer.accept(Array(samples.prefix(32_000)))
        try recognizer.resetForReposition()
        XCTAssertEqual(try decode(), baseline)
    }
}
