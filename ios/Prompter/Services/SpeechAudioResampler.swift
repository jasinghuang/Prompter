import AVFoundation

/// Queue-confined streaming conversion. Keep AVAudioConverter alive across audio
/// buffers so fractional samples and filter state survive callback boundaries.
final class SpeechAudioResampler {
    private var converter: AVAudioConverter?
    private var inputRate: Double = 0

    func convert(_ samples: [Float], sampleRate: Double) throws -> [Float] {
        guard !samples.isEmpty else { return [] }
        if sampleRate == 16_000 { return samples }
        guard sampleRate.isFinite, sampleRate > 0,
              let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                         channels: 1, interleaved: false) else { throw SpeechCaptureError.input }
        if converter == nil || inputRate != sampleRate {
            converter = AVAudioConverter(from: source, to: target)
            inputRate = sampleRate
        }
        guard let converter,
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: target,
                    frameCapacity: AVAudioFrameCount(ceil(Double(samples.count) * 16_000 / sampleRate)) + 64),
              let inputData = input.floatChannelData else { throw SpeechCaptureError.input }
        input.frameLength = input.frameCapacity
        samples.withUnsafeBufferPointer { inputData[0].update(from: $0.baseAddress!, count: samples.count) }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true
            state.pointee = .haveData
            return input
        }
        guard error == nil, status != .error, let data = output.floatChannelData else { throw SpeechCaptureError.input }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
