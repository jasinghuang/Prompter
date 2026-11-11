import AVFoundation
import XCTest
@testable import Prompter

final class SpeechPerformanceTests: XCTestCase {
    func testNative16kBuffersKeepTheirOwnAudioAfterLaterAppends() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                               channels: 1, interleaved: false))
        let converter = try AppleSpeechPCMConverter(output: format)
        let samples: [Float] = [0.1, -0.2, 0.3, -0.4]
        let first = try XCTUnwrap(converter.convert(samples))
        let second = try XCTUnwrap(converter.convert([0.9]))
        XCTAssertFalse(first === second)
        XCTAssertEqual(first.format, format)
        XCTAssertEqual(first.frameLength, 4)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: first.floatChannelData![0], count: 4)), samples)
        XCTAssertEqual(second.frameLength, 1)
        XCTAssertNil(try converter.convert([]))
    }

    func testReusableResamplerHandlesSmallerPacketsAndRateChangesWithoutOldTailAudio() throws {
        let resampler = SpeechAudioResampler()
        _ = try resampler.convert(Array(repeating: 0.5, count: 4096), sampleRate: 48_000)
        var silent: [Float] = []
        for _ in 0..<100 { silent += try resampler.convert(Array(repeating: 0, count: 96), sampleRate: 48_000) }
        XCTAssertEqual(silent.count, 3200, accuracy: 64)
        XCTAssertTrue(silent.suffix(1000).allSatisfy { abs($0) < 0.00001 })
        let changed = try resampler.convert(Array(repeating: 0, count: 4410), sampleRate: 44_100)
        let fresh = try SpeechAudioResampler().convert(Array(repeating: 0, count: 4410), sampleRate: 44_100)
        // AVAudioConverter retains an initial filter delay. A format change
        // must match a fresh converter, without a previous format's tail.
        XCTAssertEqual(changed, fresh)
        XCTAssertTrue(changed.allSatisfy { abs($0) < 0.00001 })
    }

}
