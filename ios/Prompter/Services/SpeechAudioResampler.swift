import AVFoundation

/// Queue-confined streaming conversion. Keep AVAudioConverter alive across audio
/// buffers so fractional samples and filter state survive callback boundaries.
final class SpeechAudioResampler {
    private var converter: AVAudioConverter?
    private var inputRate: Double = 0
    private var sourceFormat: AVAudioFormat?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                             channels: 1, interleaved: false)!
    private var inputBuffer: AVAudioPCMBuffer?
    private var outputBuffer: AVAudioPCMBuffer?

    func convert(_ samples: [Float], sampleRate: Double) throws -> [Float] {
        guard !samples.isEmpty else { return [] }
        if sampleRate == 16_000 { return samples }
        guard sampleRate.isFinite, sampleRate > 0 else { throw SpeechCaptureError.input }
        if converter == nil || inputRate != sampleRate {
            guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                             channels: 1, interleaved: false) else { throw SpeechCaptureError.input }
            sourceFormat = source
            converter = AVAudioConverter(from: source, to: targetFormat)
            inputRate = sampleRate
            inputBuffer = nil; outputBuffer = nil
        }
        let capacity = AVAudioFrameCount(samples.count)
        let outputCapacity = AVAudioFrameCount(ceil(Double(samples.count) * 16_000 / sampleRate)) + 64
        if inputBuffer == nil || inputBuffer!.frameCapacity < capacity, let sourceFormat {
            inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: capacity)
        }
        if outputBuffer == nil || outputBuffer!.frameCapacity < outputCapacity {
            outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity)
        }
        guard let converter, let input = inputBuffer, let output = outputBuffer,
              let inputData = input.floatChannelData else { throw SpeechCaptureError.input }
        input.frameLength = capacity
        output.frameLength = 0
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
        // Return an owned copy: only the synchronous conversion buffers are
        // reused; the recognizer never observes overwritten audio storage.
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
