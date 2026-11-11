import AVFoundation
import CryptoKit
import XCTest
import UIKit
@testable import Prompter

final class SpeechFollowTests: XCTestCase {
    func testOffsetsRemainUTF16AfterPunctuationEmojiAndWidthFolding() throws {
        let text = "🎬 开场：ＡＢＣ，今天开始。"
        var matcher = SpeechScriptMatcher(content: text)
        let result = try XCTUnwrap(matcher.match("abc今天"))
        XCTAssertEqual(result.utf16End, (text as NSString).range(of: "今天").upperBound)
        XCTAssertFalse(result.reachedEnd)
    }

    func testFillersOmissionsAndPartialRevisionsDoNotDuplicateProgress() throws {
        var matcher = SpeechScriptMatcher(content: "今天我们介绍这款产品的三个特点")
        let first = try XCTUnwrap(matcher.match("今天我们介绍"))
        XCTAssertEqual(first.tokenEnd, 6)
        XCTAssertEqual(matcher.match("今天我们呃介绍这款产品")?.tokenEnd, 10)
        XCTAssertEqual(matcher.match("今天我们介绍")?.tokenEnd, 10, "ASR revisions cannot move backwards")
        XCTAssertEqual(matcher.match("今天我们介绍这款产品")?.tokenEnd, 10, "Repeated partials do not append")
        XCTAssertTrue(try XCTUnwrap(matcher.match("产品的三个特点")).reachedEnd)
    }

    func testManualResumeUsesNearbyOccurrenceAndContinuesNewSegments() throws {
        let content = "今天开始介绍第一个功能。" + String(repeating: "其他内容", count: 30) + "今天开始介绍第二个功能。接下来测试语音跟随。"
        let start = (content as NSString).range(of: "今天开始", options: .backwards).location
        var matcher = SpeechScriptMatcher(content: content, startUTF16: start)
        let first = try XCTUnwrap(matcher.match("今天开始介绍"))
        XCTAssertGreaterThan(first.utf16End, start)
        XCTAssertTrue(try XCTUnwrap(matcher.match("接下来测试语音跟随")).reachedEnd)
    }

    func testHomophonesDoNotStallNearbyScriptAlignment() throws {
        let content = "宋：你怎么知道我在等你。接下来介绍本地语音跟随。"
        var matcher = SpeechScriptMatcher(content: content)
        let first = try XCTUnwrap(matcher.match("送你怎么知道我在等你"))
        XCTAssertEqual(first.utf16End, (content as NSString).range(of: "等你").upperBound)
        let second = try XCTUnwrap(matcher.match("接下来介绍本地语音根随"))
        XCTAssertTrue(second.reachedEnd)
        XCTAssertEqual(matcher.match("送你怎么知道我在等你")?.tokenEnd, second.tokenEnd)
    }

    func testRecentPhraseCanRecoverFromBadEarlierASRWordsWithoutDistantJump() throws {
        let phrase = "本地离线语音跟随"
        let content = "现在开始介绍" + phrase + "的使用方法。"
        let hypothesis = "这是完全错误无法对齐的开场内容" + phrase
        var nearby = SpeechScriptMatcher(content: content)
        XCTAssertEqual(try XCTUnwrap(nearby.match(hypothesis)).utf16End, (content as NSString).range(of: phrase).upperBound)
        var distant = SpeechScriptMatcher(content: String(repeating: "甲乙丙丁", count: 25) + phrase)
        XCTAssertNil(distant.match(hypothesis), "Tail recovery must not skip distant paragraphs")
    }

    func testUnrelatedSpeechAndShortCommonPhrasesCannotAdvance() {
        var matcher = SpeechScriptMatcher(content: "今天介绍本地语音识别与自动跟随功能")
        XCTAssertNil(matcher.match("今天天气特别适合出去散步"))
        XCTAssertNil(matcher.match("今天"))
        XCTAssertEqual(matcher.cursor, 0)
        var distant = SpeechScriptMatcher(content: String(repeating: "甲乙丙丁", count: 25) + "开始介绍")
        XCTAssertNil(distant.match("开始介绍"))
        XCTAssertEqual(distant.cursor, 0)
    }

    func testEmptyAndShortScripts() {
        var empty = SpeechScriptMatcher(content: " \n🎬")
        XCTAssertNil(empty.match("测试"))
        var short = SpeechScriptMatcher(content: "你好！")
        XCTAssertTrue(short.match("你好")?.reachedEnd == true)
    }

    func testRevisedFinalCannotCompleteFromAnEarlierPartialTail() {
        var matcher = SpeechScriptMatcher(content: "今天介绍本地识别")
        XCTAssertTrue(matcher.match("今天介绍本地识别")?.reachedEnd == true)
        XCTAssertFalse(matcher.match("今天介绍本地")?.reachedEnd == true)
    }

    func testStreamingResamplingPreservesDurationAcrossSmallBuffers() throws {
        let resampler = SpeechAudioResampler()
        let samples = (0..<48_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 48_000)) * 0.1 }
        var output: [Float] = []
        for start in stride(from: 0, to: samples.count, by: 1024) {
            output += try resampler.convert(Array(samples[start..<min(start + 1024, samples.count)]), sampleRate: 48_000)
        }
        XCTAssertEqual(output.count, 16_000, accuracy: 100)
        XCTAssertTrue(output.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(output.map { abs($0) }.max() ?? 0, 0.05)
        XCTAssertEqual(try resampler.convert([0.1, 0.2], sampleRate: 16_000), [0.1, 0.2])
        XCTAssertThrowsError(try resampler.convert([0.1], sampleRate: 0))
    }

    func testPauseResumeAndSpeedChangesUseAudioCaptureTime() {
        var timing = SpeechFollowTiming()
        timing.observeVoice(at: 10)
        XCTAssertFalse(timing.canAdvance(at: 10), "Noise/voice alone cannot authorize movement")
        timing.observeMatch(token: 3, at: 10)
        XCTAssertTrue(timing.canAdvance(at: 10.3))
        XCTAssertFalse(timing.canAdvance(at: 10.7), "Natural pauses stop the follower")
        timing.observeVoice(at: 11)
        timing.observeMatch(token: 9, at: 11)
        let faster = timing.tokensPerSecond
        timing.observeVoice(at: 13)
        timing.observeMatch(token: 11, at: 13)
        XCTAssertLessThan(timing.tokensPerSecond, faster)
        XCTAssertTrue(timing.canAdvance(at: 13.1))
        timing.observeVoice(at: 15)
        XCTAssertFalse(timing.canAdvance(at: 15), "An old hypothesis cannot keep moving indefinitely")
    }


    func testLegacyUnknownAndVoiceSettings() throws {
        XCTAssertEqual(try JSONDecoder().decode(SettingsData.self, from: Data("{}".utf8)).playbackMode, .constant)
        XCTAssertEqual(try JSONDecoder().decode(SettingsData.self, from: Data(#"{"playbackMode":"future"}"#.utf8)).playbackMode, .constant)
        var settings = SettingsData()
        settings.playbackMode = .voice
        settings.scrollSpeed = 213
        let decoded = try JSONDecoder().decode(SettingsData.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.playbackMode, .voice)
        XCTAssertEqual(decoded.scrollSpeed, 213)
    }

    func testAssetValidationRejectsSameSizeCorruption() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("bad".utf8).write(to: url)
        let hash = SHA256.hash(data: Data("yes".utf8)).map { String(format: "%02x", $0) }.joined()
        let asset = SpeechModelAsset(name: "test", bytes: 3, sha256: hash)
        XCTAssertThrowsError(try ParaformerModel.verify(url, asset: asset))
        try Data("yes".utf8).write(to: url)
        XCTAssertNoThrow(try ParaformerModel.verify(url, asset: asset))
    }

    /// Real INT8 inference, fed in microphone-sized chunks with a silence tail.
    /// Run scripts/prepare-speech-fixture.py first; weights stay out of Git.
    func testRealParaformerProducesIncrementalResultsAndEndpoint() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/speech-fixture")
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("verified").path) else {
            throw XCTSkip("Run python3 ios/scripts/prepare-speech-fixture.py to fetch the pinned integration fixture")
        }
        let modelDirectory = Bundle.main.url(forResource: "ParaformerModel", withExtension: nil) ?? directory
        for asset in ParaformerModel.assets { try ParaformerModel.verify(modelDirectory.appendingPathComponent(asset.name), asset: asset) }
        let audio = try AVAudioFile(forReading: directory.appendingPathComponent("test.wav"))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length)))
        try audio.read(into: buffer)
        XCTAssertEqual(audio.processingFormat.sampleRate, 16_000)
        var samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        samples += Array(repeating: 0, count: 32_000)
        let recognizer = try ParaformerRecognizer(directory: modelDirectory)
        var partials: [String] = []
        var finals: [String] = []
        for start in stride(from: 0, to: samples.count, by: 1600) {
            if let result = try recognizer.accept(Array(samples[start..<min(start + 1600, samples.count)])) {
                if result.isFinal { finals.append(result.text) }
                else if !result.text.isEmpty { partials.append(result.text) }
            }
        }
        XCTAssertGreaterThan(partials.count, 2, "Must emit words before utterance end")
        let transcript = finals.joined().lowercased()
        XCTAssertTrue(transcript.contains("昨天") && transcript.contains("monday"), "Unexpected recognition: \(finals)")
        // Seek in the middle of a new utterance, then replay from a clean
        // stream. Incremental output must equal the original fresh run.
        _ = try recognizer.accept(Array(samples.prefix(32_000)))
        try recognizer.resetForReposition()
        var replayPartials: [String] = []
        var replayFinals: [String] = []
        for start in stride(from: 0, to: samples.count, by: 1600) {
            if let result = try recognizer.accept(Array(samples[start..<min(start + 1600, samples.count)])) {
                if result.isFinal { replayFinals.append(result.text) }
                else if !result.text.isEmpty { replayPartials.append(result.text) }
            }
        }
        XCTAssertEqual(replayPartials, partials, "Manual seek must discard feature history and old partials")
        XCTAssertEqual(replayFinals, finals)

    }

    @MainActor
    func testAppContainsReadyOfflineModelWithoutStartingAnyDownload() throws {
        let bundled = try XCTUnwrap(Bundle.main.url(forResource: "ParaformerModel", withExtension: nil))
        let store = SpeechModelStore()
        XCTAssertTrue(store.isBundled)
        XCTAssertTrue(store.ready)
        XCTAssertEqual(store.directory.standardizedFileURL, bundled.standardizedFileURL)
        for asset in ParaformerModel.assets { try ParaformerModel.verify(bundled.appendingPathComponent(asset.name), asset: asset) }
        store.downloadModel()
        XCTAssertNil(store.progress, "Bundled models must never start a network request")
        XCTAssertNil(store.message)
    }

    @MainActor
    func testIncompleteBundledAssetsFallBackWithoutClaimingReady() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let incomplete = root.appendingPathComponent("incomplete")
        try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)
        try ParaformerModel.revision.write(to: incomplete.appendingPathComponent("verified"), atomically: true, encoding: .utf8)
        let store = SpeechModelStore(root: root, bundledDirectory: incomplete)
        XCTAssertFalse(store.isBundled)
        XCTAssertFalse(store.ready)
        XCTAssertNotEqual(store.directory, incomplete)
    }

    @MainActor
    func testTimeoutNSErrorHasChineseGuidance() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                            userInfo: [NSLocalizedDescriptionKey: "The request timed out."])
        let message = SpeechModelStore.downloadErrorMessage(error)
        XCTAssertTrue(message.contains("超时"))
        XCTAssertTrue(message.contains("离线模型"))
        XCTAssertFalse(message.contains("The request timed out"))
    }

    @MainActor
    func testPermissionDenialLeavesReaderStoppedWithActionableError() async {
        let controller = SpeechFollowController(requestPermission: { false })
        await controller.start(content: "今天开始介绍", startUTF16: 0, modelDirectory: FileManager.default.temporaryDirectory)
        XCTAssertFalse(controller.isAdvancing)
        XCTAssertNil(controller.target)
        XCTAssertTrue(controller.errorMessage?.contains("麦克风权限") == true)
        controller.stop()
        XCTAssertEqual(controller.status, controller.errorMessage, "Stopping must not erase permission guidance")
    }

    @MainActor
    func testStoppingDuringPermissionRequestCannotReopenMicrophone() async {
        var permission: CheckedContinuation<Bool, Never>?
        let pending = expectation(description: "permission requested")
        let controller = SpeechFollowController(requestPermission: {
            await withCheckedContinuation { permission = $0; pending.fulfill() }
        })
        let start = Task {
            await controller.start(content: "今天开始介绍", startUTF16: 0, modelDirectory: FileManager.default.temporaryDirectory)
        }
        await fulfillment(of: [pending], timeout: 3)
        controller.stop()
        permission?.resume(returning: true)
        await start.value
        XCTAssertNil(controller.errorMessage, "A stale start must not even attempt model loading")
        XCTAssertNil(controller.target)
        XCTAssertFalse(controller.isAdvancing)
        XCTAssertEqual(controller.status, "轻点正文开始语音跟随")
    }

    @MainActor
    func testVoiceScrollFreezesDuringPauseAndFollowsNewSpokenPositions() async throws {
        let parent = PrompterScrollView(
            typography: .init(content: String(repeating: "本地语音跟随测试，停顿后继续朗读。", count: 40),
                              fontSize: 36, letterSpacing: 0, lineHeight: 1.5, horizontalPadding: 8, textAlign: "left"),
            isPlaying: true, wordsPerMinute: 160, controller: ScrollEngineController(),
            voiceMode: true, voiceTarget: .init(utf16End: 150, tokensPerSecond: 4), voiceAdvancing: false)
        let coordinator = PrompterScrollView.Coordinator(parent)
        let view = PrompterTextView(frame: CGRect(x: 0, y: 0, width: 700, height: 400))
        coordinator.attach(view)
        coordinator.render(parent.typography)
        // TextKit's initial layout callback restores the active line asynchronously.
        // Establish the baseline after layout, before arming playback.
        try await Task.sleep(for: .milliseconds(200))
        coordinator.setPlaying(true)
        defer { coordinator.teardown() }
        let initial = view.contentOffset.y
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(view.contentOffset.y, initial, accuracy: 0.1, "Arming alone must not scroll")
        coordinator.parent.voiceAdvancing = true
        try await Task.sleep(for: .milliseconds(300))
        let following = view.contentOffset.y
        XCTAssertGreaterThan(following, initial + 2, "The new 2s speed observation still allows a gentle initial advance")
        coordinator.parent.voiceAdvancing = false
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(view.contentOffset.y, following, accuracy: 0.1, "Silence must stop immediately without coasting")
        coordinator.parent.voiceTarget = .init(utf16End: 300, tokensPerSecond: 8)
        coordinator.parent.voiceAdvancing = true
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(view.contentOffset.y, following + 2)
        coordinator.setPlaying(false)
    }

    @MainActor
    func testModelDownloadCancellationDoesNotMakePartialFilesReady() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SpeechModelStore(root: root)
        store.downloadModel()
        store.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(store.ready)
        XCTAssertNil(store.progress)
        XCTAssertFalse(SpeechModelStore(root: root).ready)
    }

    @MainActor
    func testPinnedModelDownloadInstallsVerifiedOfflineFiles() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/speech-fixture/verified")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Network integration is enabled by explicitly preparing the speech fixture")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SpeechModelStore(root: root)
        store.downloadModel()
        let deadline = Date().addingTimeInterval(120)
        var observedInFlightProgress = false
        while store.progress != nil && Date() < deadline {
            if let progress = store.progress, progress > 0 && progress < 0.69 && store.downloadedBytes > 0 {
                observedInFlightProgress = true
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        defer { store.cancel() }
        XCTAssertTrue(store.ready, store.message ?? "Download did not finish")
        XCTAssertTrue(observedInFlightProgress, "UI must update before the first 165 MB file completes")
        XCTAssertTrue(SpeechModelStore(root: root).ready, "A new session must work without downloading again")
        try Data().write(to: store.directory.appendingPathComponent("tokens.txt"))
        XCTAssertFalse(SpeechModelStore(root: root).ready, "Missing/truncated assets must not be marked ready")
    }
}
