import AVFoundation
import Foundation
import Speech

/// Cross-thread results are generation-scoped; a drag/seek cannot publish old
/// native callbacks into the replacement session.
final class SpeechResultMailbox {
    private let lock = NSLock()
    private var generation = UUID()
    private var results: [SpeechRecognitionResult] = []
    private var failure: Error?

    func reset() -> UUID {
        lock.lock(); defer { lock.unlock() }
        generation = UUID(); results = []; failure = nil
        return generation
    }
    func append(_ result: SpeechRecognitionResult, generation: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard self.generation == generation else { return }
        if let last = results.last, last.segment == result.segment && !last.isFinal { results[results.count - 1] = result }
        else if results.count < 32 { results.append(result) }
        else { failure = SpeechCaptureError.overloaded }
    }
    func fail(_ error: Error, generation: UUID) {
        lock.lock(); defer { lock.unlock() }
        if self.generation == generation { failure = error }
    }
    func take() throws -> SpeechRecognitionResult? {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        return results.isEmpty ? nil : results.removeFirst()
    }
}

enum AppleSpeechPreparation {
    static func prepare(progress: @escaping @Sendable (Double?) -> Void) async throws -> () throws -> any LocalSpeechRecognizer {
        if #available(iOS 26.0, *), SpeechTranscriber.isAvailable,
           let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN")) {
            let transcriber = AppleAnalyzerRecognizer.makeTranscriber(locale)
            _ = try await AssetInventory.reserve(locale: locale)
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                let observation = installation.progress.observe(\.fractionCompleted, options: [.initial, .new]) { value, _ in
                    progress(value.fractionCompleted)
                }
                defer { observation.invalidate() }
                try await installation.downloadAndInstall()
            }
            try Task.checkCancellation()
            guard await AssetInventory.status(forModules: [transcriber]) == .installed,
                  let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw SpeechEngineError.languageUnavailable
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            progress(nil)
            try await analyzer.prepareToAnalyze(in: format)
            return { try AppleAnalyzerRecognizer(locale: locale, format: format, analyzer: analyzer, transcriber: transcriber) }
        }
        // Older devices use the legacy API only when it explicitly supports
        // on-device recognition. No server recognition fallback is permitted.
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized else { throw SpeechEngineError.permission }
        return { try AppleLegacyRecognizer() }
    }
}

@available(iOS 26.0, *)
private final class AppleAnalyzerRecognizer: LocalSpeechRecognizer {
    private let locale: Locale
    private let format: AVAudioFormat
    private let mailbox = SpeechResultMailbox()
    private var session: Session?
    private var segment = 0

    static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults],
                          attributeOptions: [.audioTimeRange])
    }

    init(locale: Locale, format: AVAudioFormat, analyzer: SpeechAnalyzer, transcriber: SpeechTranscriber) throws {
        self.locale = locale
        self.format = format
        session = try Session(analyzer: analyzer, transcriber: transcriber, format: format, mailbox: mailbox,
                              generation: mailbox.reset(), segment: segment, prepared: true)
    }
    deinit { session?.stop() }

    func resetForReposition() throws {
        session?.stop()
        let version = mailbox.reset()
        segment += 1
        let transcriber = Self.makeTranscriber(locale)
        session = try Session(analyzer: SpeechAnalyzer(modules: [transcriber]), transcriber: transcriber,
                              format: format, mailbox: mailbox, generation: version, segment: segment, prepared: false)
    }
    func accept(_ samples: [Float]) throws -> SpeechRecognitionResult? {
        let result = try mailbox.take()
        try session?.append(samples)
        return result
    }

    private final class Session {
        private let analyzer: SpeechAnalyzer
        private let input: AsyncStream<AnalyzerInput>.Continuation
        private let converter: AppleSpeechPCMConverter
        private let format: AVAudioFormat
        private var frame: Int64 = 0
        private var analysisTask: Task<Void, Never>?
        private var resultTask: Task<Void, Never>?

        init(analyzer: SpeechAnalyzer, transcriber: SpeechTranscriber, format: AVAudioFormat,
             mailbox: SpeechResultMailbox, generation: UUID, segment: Int, prepared: Bool) throws {
            self.analyzer = analyzer
            self.format = format
            converter = try AppleSpeechPCMConverter(output: format)
            let stream = AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .bufferingOldest(64))
            input = stream.continuation
            resultTask = Task {
                var transcript = SpeechTranscriptAssembler()
                do {
                    for try await result in transcriber.results {
                        guard !Task.isCancelled else { return }
                        let text = result.text
                        let fragments = text.runs.map { run -> SpeechTimedText in
                            let range = run.audioTimeRange ?? result.range
                            return .init(start: CMTimeGetSeconds(range.start), end: CMTimeGetSeconds(CMTimeRangeGetEnd(range)),
                                         text: String(text[run.range].characters))
                        }
                        if let hypothesis = transcript.update(rangeStart: CMTimeGetSeconds(result.range.start),
                            rangeEnd: CMTimeGetSeconds(CMTimeRangeGetEnd(result.range)), fragments: fragments,
                            finalizedThrough: CMTimeGetSeconds(result.resultsFinalizationTime), segment: segment) {
                            mailbox.append(hypothesis, generation: generation)
                        }
                    }
                } catch { if !Task.isCancelled { mailbox.fail(error, generation: generation) } }
            }
            analysisTask = Task {
                do {
                    if !prepared { try await analyzer.prepareToAnalyze(in: format) }
                    try Task.checkCancellation()
                    try await analyzer.start(inputSequence: stream.stream)
                } catch { if !Task.isCancelled { mailbox.fail(error, generation: generation) } }
            }
        }
        func append(_ samples: [Float]) throws {
            guard let buffer = try converter.convert(samples) else { return }
            let item = AnalyzerInput(buffer: buffer, bufferStartTime: CMTime(value: frame, timescale: Int32(format.sampleRate)))
            frame += Int64(buffer.frameLength)
            switch input.yield(item) {
            case .enqueued: break
            case .dropped: throw SpeechCaptureError.overloaded
            case .terminated: throw SpeechEngineError.offlineUnavailable
            @unknown default: throw SpeechEngineError.offlineUnavailable
            }
        }
        func stop() {
            input.finish()
            analysisTask?.cancel(); resultTask?.cancel()
            let analyzer = analyzer
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}

/// Queue-confined PCM conversion for the native analyzer's chosen format.
private final class AppleSpeechPCMConverter {
    private let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let output: AVAudioFormat
    private let converter: AVAudioConverter
    init(output: AVAudioFormat) throws {
        self.output = output
        guard let converter = AVAudioConverter(from: source, to: output) else { throw SpeechCaptureError.input }
        self.converter = converter
    }
    func convert(_ samples: [Float]) throws -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = input.floatChannelData?[0] else { throw SpeechCaptureError.input }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: $0.count) }
        let capacity = AVAudioFrameCount(ceil(Double(samples.count) * output.sampleRate / 16_000) + 1024)
        guard let result = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { throw SpeechCaptureError.input }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: result, error: &error) { _, flag in
            if supplied { flag.pointee = .noDataNow; return nil }
            supplied = true; flag.pointee = .haveData; return input
        }
        if let error { throw error }
        guard status != .error else { throw SpeechCaptureError.input }
        return result.frameLength > 0 ? result : nil
    }
}

/// Compatibility path for devices that cannot use SpeechTranscriber.
private final class AppleLegacyRecognizer: LocalSpeechRecognizer {
    private let recognizer: SFSpeechRecognizer
    private let mailbox = SpeechResultMailbox()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var segment = 0
    private var restart = false
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    init() throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.supportsOnDeviceRecognition else {
            throw SpeechEngineError.offlineUnavailable
        }
        self.recognizer = recognizer
        try resetForReposition()
    }
    deinit { request?.endAudio(); task?.cancel() }
    func resetForReposition() throws {
        let generation = mailbox.reset()
        request?.endAudio(); task?.cancel()
        segment += 1
        restart = false
        let part = segment
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request
        let mailbox = mailbox
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result { mailbox.append(.init(text: result.bestTranscription.formattedString, segment: part, isFinal: result.isFinal), generation: generation) }
            if let error { mailbox.fail(error, generation: generation) }
        }
    }
    func accept(_ samples: [Float]) throws -> SpeechRecognitionResult? {
        if restart { try resetForReposition() }
        if !samples.isEmpty {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let data = buffer.floatChannelData?[0] else { throw SpeechCaptureError.input }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: $0.count) }
            request?.append(buffer)
        }
        let result = try mailbox.take()
        if result?.isFinal == true { restart = true }
        return result
    }
}
