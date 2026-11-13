import AVFoundation
import Foundation

enum SpeechCaptureError: LocalizedError, Equatable {
    case permission, model, input, overloaded, interrupted, inputChanged, mediaServices, recognitionUnresponsive, recognitionEnded, startupTimedOut
    var errorDescription: String? {
        switch self {
        case .permission: return "麦克风权限未开启，请在系统设置中允许提词器使用麦克风。"
        case .model: return "离线语音模型未能启动，请重新打开提词页后重试。"
        case .input: return "麦克风暂不可用，请检查音频设备后重试。"
        case .overloaded: return "本机识别未能跟上录音，已暂停。请关闭其他高负载应用后重试。"
        case .interrupted: return "音频会话被系统中断，已暂停。轻点正文重新开始。"
        case .inputChanged: return "录音设备已切换，已暂停。确认麦克风后轻点正文继续。"
        case .mediaServices: return "系统音频服务已重置，已暂停。轻点正文重新开始。"
        case .recognitionUnresponsive: return "听到了说话，但听写长时间没有返回文字，已暂停。轻点正文重新启动听写。"
        case .recognitionEnded: return "听写服务已停止，已暂停。轻点正文重新启动听写。"
        case .startupTimedOut: return "本地听写未能及时启动，已暂停。轻点正文重试，或选择其他本地引擎。"
        }
    }
}

struct SpeechFollowTarget: Equatable {
    var utf16End: Int
    var tokensPerSecond: Double
}

/// Serial inference and conversion, with a bounded input queue. No ONNX work or
/// audio conversion runs on the UI/audio render thread. A slow device fails
/// explicitly instead of accumulating seconds of stale recognition results.
final class SpeechRecognitionPipeline: @unchecked Sendable {
    struct Event {
        var capturedAt: TimeInterval
        var epoch: UInt64
        var voice: Bool
        var rms: Float
        var threshold: Float
        var result: SpeechRecognitionResult?
    }
    // Decoder/shutdown ownership stays on this queue; the lock protects the
    // capture-side flags. Callbacks are installed before preparation begins.
    private static let inferenceQueue = DispatchQueue(label: "prompter.local-speech", qos: .userInitiated)
    private let queue = SpeechRecognitionPipeline.inferenceQueue
    private let lock = NSLock()
    private var stopped = false
    private var cleanupRequested = false
    private var shutdownTask: Task<Void, Never>?
    private var pending = 0
    private var suspended = false
    private var epoch: UInt64 = 0
    private var recognizer: (any LocalSpeechRecognizer)?
    private var resampler = SpeechAudioResampler()
    private var voiceDetector: SpeechVoiceDetector?
    var onEvent: ((Event) -> Void)?
    var onError: ((UInt64, Error) -> Void)?

    func prepare(directory: URL, kind: SpeechEngineKind, appleFactory: (() throws -> any LocalSpeechRecognizer)?, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            self.lock.lock(); let stopped = self.stopped; self.lock.unlock()
            guard !stopped else { completion(.failure(CancellationError())); return }
            do {
                guard let model = SpeechVoiceDetector.bundledModel else { throw SpeechCaptureError.model }
                self.voiceDetector = try SpeechVoiceDetector(model: model)
                switch kind {
                case .paraformer: self.recognizer = try ParaformerRecognizer(directory: directory)
                case .zipformer:
                    guard let directory = BundledSpeechModels.zipformer else { throw SpeechEngineError.modelMissing }
                    self.recognizer = try ZipformerRecognizer(directory: directory)
                case .senseVoice:
                    guard let directory = BundledSpeechModels.senseVoice else { throw SpeechEngineError.modelMissing }
                    self.recognizer = try SenseVoiceRecognizer(directory: directory)
                case .apple:
                    guard let appleFactory else { throw SpeechEngineError.offlineUnavailable }
                    self.recognizer = try appleFactory()
                }
                if let ready = (self.recognizer as? any SpeechRecognizerReadiness)?.readiness {
                    Task {
                        let result = await ready.result
                        self.queue.async {
                            self.lock.lock(); let stopped = self.stopped; self.lock.unlock()
                            completion(stopped ? .failure(CancellationError()) : result)
                        }
                    }
                    return
                }
                completion(.success(()))
            } catch { completion(.failure(error)) }
        }
    }

    func stop() {
        lock.lock()
        guard !cleanupRequested else { lock.unlock(); return }
        stopped = true; cleanupRequested = true
        lock.unlock()
        queue.async {
            let native = self.recognizer as? any SpeechRecognizerShutdown
            self.recognizer = nil; self.voiceDetector = nil; self.resampler = SpeechAudioResampler()
            self.shutdownTask = Task { await native?.shutdown() }
        }
    }

    func waitUntilStopped() async {
        let shutdown: Task<Void, Never>? = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.shutdownTask) }
        }
        await shutdown?.value
    }

    func suspend() {
        lock.lock()
        suspended = true
        epoch &+= 1
        lock.unlock()
    }

    func resume(completion: @escaping (Result<UInt64, Error>) -> Void) {
        lock.lock()
        epoch &+= 1
        let version = epoch
        suspended = true
        lock.unlock()
        queue.async {
            self.lock.lock()
            let valid = !self.stopped && self.epoch == version
            self.lock.unlock()
            guard valid else { completion(.failure(CancellationError())); return }
            do { try self.recognizer?.resetForReposition() }
            catch { completion(.failure(error)); return }
            if let ready = (self.recognizer as? any SpeechRecognizerReadiness)?.readiness {
                Task {
                    let result = await ready.result
                    self.queue.async {
                        switch result {
                        case .success: self.finishResume(version: version, completion: completion)
                        case .failure(let error): completion(.failure(error))
                        }
                    }
                }
            } else {
                self.finishResume(version: version, completion: completion)
            }
        }
    }

    private func finishResume(version: UInt64, completion: (Result<UInt64, Error>) -> Void) {
        lock.lock()
        let valid = !stopped && epoch == version
        if valid {
            resampler = SpeechAudioResampler()
            voiceDetector?.reset()
            suspended = false
        }
        lock.unlock()
        completion(valid ? .success(version) : .failure(CancellationError()))
    }

    func submit(samples: [Float], sampleRate: Double, capturedAt: TimeInterval) {
        lock.lock()
        guard !stopped, !suspended else { lock.unlock(); return }
        let version = epoch
        // About one second at a 1024-frame / 48 kHz tap, bounded independently of
        // recognition speed. Never silently drop audio and damage stream state.
        guard pending < 48 else {
            stopped = true
            lock.unlock()
            onError?(version, SpeechCaptureError.overloaded)
            return
        }
        pending += 1
        lock.unlock()
        queue.async {
            self.lock.lock()
            self.pending -= 1
            let stopped = self.stopped || self.suspended || self.epoch != version
            self.lock.unlock()
            guard !stopped else { return }
            do {
                guard ProcessInfo.processInfo.systemUptime - capturedAt < 1.5 else { throw SpeechCaptureError.overloaded }
                let converted = try self.resampler.convert(samples, sampleRate: sampleRate)
                let voice = self.voiceDetector?.accept(converted) ?? false
                let result: SpeechRecognitionResult?
                if let gated = self.recognizer as? any SpeechGatedRecognizer { result = try gated.accept(converted, speech: voice) }
                else { result = try self.recognizer?.accept(converted) }
                self.onEvent?(.init(capturedAt: capturedAt, epoch: version, voice: voice, rms: self.voiceDetector?.rms ?? 0,
                                    threshold: 0.5, result: result))
            } catch { self.onError?(version, error) }
        }
    }

}

@MainActor
final class SpeechFollowController: ObservableObject {
    @Published private(set) var status = "轻点正文开始语音跟随"
    @Published private(set) var isAdvancing = false
    @Published private(set) var advanceUntil: TimeInterval?
    @Published private(set) var pauseContinuation: SpeechPauseContinuation?
    @Published private(set) var cruiseUntil: TimeInterval?
    @Published private(set) var target: SpeechFollowTarget?
    @Published private(set) var errorMessage: String?
    @Published private(set) var reachedEnd = false
    @Published private(set) var isInteractionPaused = false
    @Published private(set) var speechDetected = false
    @Published private(set) var isListening = false
    @Published private(set) var lastRecognized = ""
    @Published private(set) var lastMatchSucceeded = false
    @Published private(set) var recognizedLineDelta: Double?
    private var capture: SpeechAudioCapture?
    private var pipeline: SpeechRecognitionPipeline?
    private var pipelinePrepared = false
    private var sessionID: UUID?
    private let audioSession: SpeechAudioSessionCoordinator
    private var observers: [NSObjectProtocol] = []
    private var inputCheck: Task<Void, Never>?
    private var inputCheckPending = false
    private var inputState: SpeechAudioInputState?
    private var captureID = UUID()
    private var recoveryBudget = SpeechCaptureRecoveryBudget()
    private var clock: Task<Void, Never>?
    private var startupWatchdog: Task<Void, Never>?
    private var pendingRecognizerStop: Task<Void, Never>?
    private var recognitionHealth = SpeechRecognitionHealth()
    private var recognitionTimeout: TimeInterval = 10
    private var matcher = SpeechScriptMatcher(content: "")
    private var timing = SpeechFollowTiming()
    private var settlement = SpeechFollowSettlement()
    private var viewportOffset: Int?
    private var viewportDelta: Double?
    private var lastViewportLogAt: TimeInterval = 0
    private var lastAudio: TimeInterval = 0
    private var lastResultAt: TimeInterval = 0
    private var inputHasVoice = false
    private var matched = false
    private var audioPackets = 0
    private var voicePackets = 0
    private var scriptContent = ""
    private var recognitionEpoch: UInt64? = 0
    private var interactionRevision = UUID()
    private var pendingResumeUTF16: Int?
    private var interactionResume: Task<Void, Never>?
    private let requestPermission: () async -> Bool
    private let startupTimeout: Duration

    init(requestPermission: @escaping () async -> Bool = {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }, audioSession: SpeechAudioSessionCoordinator? = nil, startupTimeout: Duration = .seconds(20)) {
        self.requestPermission = requestPermission
        self.audioSession = audioSession ?? .shared
        self.startupTimeout = startupTimeout
    }

    func start(content: String, startUTF16: Int, modelDirectory: URL, kind: SpeechEngineKind = .paraformer) async {
        stop()
        let previousShutdown = pendingRecognizerStop
        let id = UUID()
        sessionID = id
        errorMessage = nil
        if !lastRecognized.isEmpty { lastRecognized = "" }
        if lastMatchSucceeded { lastMatchSucceeded = false }
        reachedEnd = false
        matcher = SpeechScriptMatcher(content: content, startUTF16: startUTF16)
        scriptContent = content
        recognitionEpoch = 0
        timing = SpeechFollowTiming()
        settlement = SpeechFollowSettlement()
        viewportOffset = nil; viewportDelta = nil
        inputHasVoice = false
        speechDetected = false
        if target != nil { target = nil }
        if recognizedLineDelta != nil { recognizedLineDelta = nil }
        matched = false
        lastResultAt = 0
        audioPackets = 0
        voicePackets = 0
        recoveryBudget = SpeechCaptureRecoveryBudget()
        recognitionTimeout = kind == .senseVoice ? 15 : 10
        recognitionHealth = .init(timeout: recognitionTimeout)
        captureLog("starting engine=\(kind.rawValue) startOffset=\(startUTF16) scriptTokens=\(matcher.script.tokens.count)")
        status = "正在开启本地识别…"
        let allowed = await requestPermission()
        guard sessionID == id else { return }
        guard !Task.isCancelled else { stop(); return }
        guard allowed else { fail(SpeechCaptureError.permission); return }
        do {
            armStartupWatchdog(session: id)
            if previousShutdown != nil { status = "正在释放上次听写会话…" }
            await previousShutdown?.value
            await audioSession.waitForIdle()
            guard sessionID == id else { return }
            guard !Task.isCancelled else { stop(); return }
            var appleFactory: (() throws -> any LocalSpeechRecognizer)?
            if kind == .apple {
                // System language downloads may take longer than service startup.
                startupWatchdog?.cancel(); startupWatchdog = nil
                status = "正在准备 Apple 中文离线资源…"
                appleFactory = try await AppleSpeechPreparation.prepare { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.sessionID == id, self.pipeline == nil else { return }
                        if progress == nil { self.armStartupWatchdog(session: id) }
                        self.status = progress.map { "正在准备 Apple 中文离线资源 \(Int(min(1, max(0, $0)) * 100))%" } ?? "正在启动 Apple 本地识别…"
                    }
                }
                guard sessionID == id else { return }
                guard !Task.isCancelled else { stop(); return }
            }
            armStartupWatchdog(session: id)
            let pipeline = SpeechRecognitionPipeline()
            self.pipeline = pipeline
            if isInteractionPaused { pipeline.suspend() }
            pipeline.onEvent = { [weak self] event in
                Task { @MainActor in
                    guard let self, self.sessionID == id else { return }
                    self.receive(event)
                }
            }
            pipeline.onError = { [weak self] epoch, error in
                Task { @MainActor in
                    guard let self, self.sessionID == id, self.recognitionEpoch == epoch, !self.isInteractionPaused else { return }
                    self.fail(error)
                }
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pipeline.prepare(directory: modelDirectory, kind: kind, appleFactory: appleFactory) { continuation.resume(with: $0) }
            }
            guard sessionID == id else { pipeline.stop(); return }
            guard !Task.isCancelled else { stop(); return }
            pipelinePrepared = true
            armStartupWatchdog(session: id)
            try await audioSession.activate(owner: id)
            guard sessionID == id, !Task.isCancelled else {
                audioSession.release(owner: id)
                pipeline.stop()
                return
            }
            try await beginCapture(pipeline: pipeline, session: id)
            if isInteractionPaused, let index = pendingResumeUTF16 { await resumeAfterInteraction(atUTF16: index) }
            guard sessionID == id, !Task.isCancelled else { return }
            startupWatchdog?.cancel(); startupWatchdog = nil
            status = isInteractionPaused ? "手动调整中 · 松手 1.5 秒后恢复" : isListening ? "等待朗读 · 音频仅在本机处理" : "正在等待麦克风输入…"
            clock = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                    guard let self, self.sessionID == id else { return }
                    self.updateActivity()
                }
            }
        } catch {
            guard sessionID == id else { return }
            if error is CancellationError || Task.isCancelled { stop(); return }
            fail(error)
        }
    }

    func stop() {
        let owner = sessionID
        sessionID = nil
        interactionRevision = UUID()
        interactionResume?.cancel(); interactionResume = nil
        pendingResumeUTF16 = nil
        isInteractionPaused = false
        recognitionEpoch = nil
        clock?.cancel(); clock = nil
        startupWatchdog?.cancel(); startupWatchdog = nil
        inputCheck?.cancel(); inputCheck = nil
        inputCheckPending = false
        inputState = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        let stoppedCapture = detachEngine()
        let stoppedPipeline = pipeline
        stoppedPipeline?.stop(); pipeline = nil
        pipelinePrepared = false
        if let stoppedPipeline {
            let previous = pendingRecognizerStop
            pendingRecognizerStop = Task {
                await previous?.value
                await stoppedPipeline.waitUntilStopped()
            }
        }
        let shutdown = pendingRecognizerStop
        if let owner {
            audioSession.release(owner: owner, after: {
                await stoppedCapture?.waitUntilStopped()
                await shutdown?.value
            })
        }
        isAdvancing = false
        advanceUntil = nil
        pauseContinuation = nil
        cruiseUntil = nil
        speechDetected = false
        if isListening { isListening = false }
        if target != nil { target = nil }
        if recognizedLineDelta != nil { recognizedLineDelta = nil }
        status = errorMessage ?? "轻点正文开始语音跟随"
    }

    func pauseForInteraction() {
        guard sessionID != nil else { return }
        if !lastRecognized.isEmpty { lastRecognized = "" }
        if lastMatchSucceeded { lastMatchSucceeded = false }
        interactionRevision = UUID()
        interactionResume?.cancel(); interactionResume = nil
        if isListening { startupWatchdog?.cancel(); startupWatchdog = nil }
        pendingResumeUTF16 = nil
        isInteractionPaused = true
        recognitionEpoch = nil
        pipeline?.suspend()
        if target != nil { target = nil }
        if recognizedLineDelta != nil { recognizedLineDelta = nil }
        matched = false
        isAdvancing = false
        advanceUntil = nil
        pauseContinuation = nil
        cruiseUntil = nil
        timing = SpeechFollowTiming()
        settlement = SpeechFollowSettlement()
        viewportOffset = nil; viewportDelta = nil
        inputHasVoice = false
        speechDetected = false
        recognitionHealth = .init(timeout: recognitionTimeout)
        status = "手动调整中 · 松手 1.5 秒后恢复"
    }

    func requestResumeAfterInteraction(atUTF16 index: Int) {
        let revision = interactionRevision
        interactionResume?.cancel()
        interactionResume = Task { @MainActor [weak self] in
            guard let self, self.interactionRevision == revision, !Task.isCancelled else { return }
            await self.resumeAfterInteraction(atUTF16: index)
        }
    }

    private func resumeAfterInteraction(atUTF16 index: Int) async {
        guard let id = sessionID, isInteractionPaused else { return }
        guard let pipeline, pipelinePrepared else { pendingResumeUTF16 = index; return }
        pendingResumeUTF16 = nil
        let revision = interactionRevision
        armStartupWatchdog(session: id)
        matcher = SpeechScriptMatcher(content: scriptContent, startUTF16: index)
        timing = SpeechFollowTiming()
        settlement = SpeechFollowSettlement()
        viewportOffset = nil; viewportDelta = nil
        inputHasVoice = false
        speechDetected = false
        matched = false
        if target != nil { target = nil }
        if recognizedLineDelta != nil { recognizedLineDelta = nil }
        reachedEnd = false
        lastResultAt = 0
        recognitionHealth = .init(timeout: recognitionTimeout)
        do {
            let epoch = try await withCheckedThrowingContinuation { continuation in
                pipeline.resume { continuation.resume(with: $0) }
            }
            guard sessionID == id, interactionRevision == revision, !Task.isCancelled else { return }
            startupWatchdog?.cancel(); startupWatchdog = nil
            recognitionEpoch = epoch
            isInteractionPaused = false
            lastAudio = ProcessInfo.processInfo.systemUptime
            status = "等待朗读 · 已按当前阅读区重新定位"
            captureLog("resumed at UTF16=\(index) epoch=\(epoch)")
        } catch {
            guard sessionID == id, interactionRevision == revision else { return }
            if !(error is CancellationError) { fail(error) }
        }
    }

    private func fail(_ error: Error) {
        captureLog("failure=\(error.localizedDescription)")
        stop()
        errorMessage = error.localizedDescription
        status = error.localizedDescription
    }

    private func armStartupWatchdog(session id: UUID) {
        startupWatchdog?.cancel()
        let timeout = startupTimeout
        startupWatchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.sessionID == id else { return }
            self.fail(SpeechCaptureError.startupTimedOut)
        }
    }

    private func receive(_ event: SpeechRecognitionPipeline.Event) {
        guard !isInteractionPaused, recognitionEpoch == event.epoch else { return }
        if !isListening { isListening = true }
        recognitionHealth.observeAudio(at: event.capturedAt, voice: event.voice)
        audioPackets += 1
        if event.voice { voicePackets += 1 }
        if audioPackets == 1 || audioPackets % 100 == 0 {
            captureLog("audio packets=\(audioPackets) voicePackets=\(voicePackets) rms=\(event.rms) threshold=\(event.threshold)")
        }
        lastAudio = max(lastAudio, event.capturedAt)
        if inputHasVoice && !event.voice { settlement.voiceStopped(at: ProcessInfo.processInfo.systemUptime) }
        inputHasVoice = event.voice
        if speechDetected != event.voice { speechDetected = event.voice }
        if event.voice {
            settlement.voiceResumed()
            timing.observeVoice(at: event.capturedAt)
        }
        if let result = event.result, !result.text.isEmpty {
            recognitionHealth.receivedText()
            // Deduplicate UI notifications only: identical text may carry a
            // new final result, so matching and timing still consume it below.
            if lastRecognized != result.text { lastRecognized = result.text }
            captureLog("ASR segment=\(result.segment) chars=\(result.text.count) final=\(result.isFinal)")
            lastResultAt = event.capturedAt
            if let match = matcher.match(result.text) {
                if target?.utf16End != match.utf16End { captureLog("matched script offset=\(match.utf16End)") }
                timing.observeMatch(token: match.tokenEnd, at: event.capturedAt)
                let nextTarget = SpeechFollowTarget(utf16End: match.utf16End, tokensPerSecond: timing.tokensPerSecond)
                if target != nextTarget { target = nextTarget }
                matched = true
                if !lastMatchSucceeded { lastMatchSucceeded = true }
                settlement.matched(offset: match.utf16End, final: result.isFinal,
                                   reachedEnd: match.reachedEnd, at: ProcessInfo.processInfo.systemUptime)
            } else {
                captureLog("no match cursor=\(matcher.cursor)")
                matched = false
                if lastMatchSucceeded { lastMatchSucceeded = false }
            }
        }
        updateActivity()
    }

    func updateRecognizedLinePosition(utf16: Int, delta: Double, report: Bool) {
        guard target?.utf16End == utf16, !isInteractionPaused else { return }
        viewportOffset = utf16
        viewportDelta = delta
        if report && recognizedLineDelta != delta { recognizedLineDelta = delta }
        #if DEBUG
        let now = ProcessInfo.processInfo.systemUptime
        if report && now - lastViewportLogAt >= 0.5 {
            lastViewportLogAt = now
            captureLog("viewport offset=\(utf16) delta=\(delta)")
        }
        #endif
        if settlement.completionReady(delta: delta, voice: inputHasVoice, at: ProcessInfo.processInfo.systemUptime), !reachedEnd { reachedEnd = true }
    }

    private func captureLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard SpeechCaptureDiagnostics.enabled else { return }
        let session = AVAudioSession.sharedInstance()
        let input = session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ",")
        SpeechCaptureDiagnostics.record("\(message()) running=\(inputState?.running ?? false) rate=\(session.sampleRate) input=\(input)")
        #endif
    }

    private func updateActivity() {
        if isInteractionPaused {
            if isAdvancing { isAdvancing = false }
            if advanceUntil != nil { advanceUntil = nil }
            if pauseContinuation != nil { pauseContinuation = nil }
            if cruiseUntil != nil { cruiseUntil = nil }
            if status != "手动调整中 · 松手 1.5 秒后恢复" { status = "手动调整中 · 松手 1.5 秒后恢复" }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastAudio > 3 { fail(SpeechCaptureError.input); return }
        if recognitionHealth.hasTimedOut(at: now) { fail(SpeechCaptureError.recognitionUnresponsive); return }
        // ASR pursuit and the low-speed floor have separate authorization.
        // Speech can maintain the floor between batches; native frames bound
        // its lookahead and deadline without advancing the recognition cursor.
        let speaking = inputHasVoice && timing.canAdvance(at: now)
        let cruise = !inputCheckPending && target != nil && !settlement.pendingEnd
            ? timing.cruiseDeadline(at: now, hasVoice: inputHasVoice) : nil
        // Refresh the render deadline at most 5Hz while continuously voiced.
        // Clear it immediately for silence, interaction, interruption or EOF.
        if cruise == nil || cruiseUntil == nil || cruise! < cruiseUntil! || cruise! - cruiseUntil! >= 0.2 {
            if cruiseUntil != cruise {
                if (cruiseUntil == nil) != (cruise == nil) { captureLog("listening cruise=\(cruise != nil)") }
                cruiseUntil = cruise
            }
        }
        let settling = settlement.canSettle(at: now, lastVoice: timing.lastVoice)
        let continuation = !inputCheckPending && !inputHasVoice && target != nil
            ? settlement.pauseContinuation(at: now, lastVoice: timing.lastVoice) : nil
        if pauseContinuation != continuation { pauseContinuation = continuation }
        let advance = !inputCheckPending && target != nil && (speaking || settling || continuation != nil || cruise != nil)
        let deadline = advance && !speaking ? settlement.until : nil
        if advanceUntil != deadline { advanceUntil = deadline }
        if isAdvancing != advance {
            isAdvancing = advance
            captureLog("advance=\(advance) target=\(target?.utf16End ?? -1) voice=\(inputHasVoice) settling=\(settling)")
        }
        let text: String
        if !isListening { text = "正在等待麦克风输入…" }
        else if recognitionHealth.isWaitingForText(at: now) { text = "已听到说话，等待听写返回文字…" }
        else if advance { text = inputHasVoice ? "语音跟随中" : settling ? "正在对齐已识别文字" : "短暂停顿 · 缓慢续滚" }
        else if timing.lastVoice != nil && !inputHasVoice { text = "停顿中 · 继续朗读即可跟随" }
        else if lastResultAt > 0 && !matched { text = "等待匹配原稿 · 请读当前附近的文字" }
        else { text = "等待朗读 · 音频仅在本机处理" }
        if status != text { status = text }
        let delta = viewportOffset == target?.utf16End ? viewportDelta : nil
        if settlement.completionReady(delta: delta, voice: inputHasVoice, at: now), !reachedEnd { reachedEnd = true }
    }

    @discardableResult
    private func detachEngine() -> SpeechAudioCapture? {
        let previous = capture
        capture = nil
        previous?.stop()
        return previous
    }

    private func beginCapture(pipeline: SpeechRecognitionPipeline, session id: UUID) async throws {
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        let previous = detachEngine()
        await previous?.waitUntilStopped()
        guard sessionID == id, !Task.isCancelled else { throw CancellationError() }
        let generation = UUID()
        captureID = generation
        recognitionHealth = .init(timeout: recognitionTimeout)
        if isListening { isListening = false }
        let capture = SpeechAudioCapture()
        self.capture = capture
        let started = try await capture.start { samples, rate, capturedAt in
            pipeline.submit(samples: samples, sampleRate: rate, capturedAt: capturedAt)
        }
        guard sessionID == id, captureID == generation, !Task.isCancelled else {
            capture.stop()
            throw CancellationError()
        }
        inputState = started.state
        lastAudio = ProcessInfo.processInfo.systemUptime
        captureLog("engine started")
        observeAudioChanges(configurationObject: started.configurationObject, session: id, capture: generation)
    }

    private func observeAudioChanges(configurationObject: AnyObject?, session id: UUID, capture generation: UUID) {
        func observe(_ name: Notification.Name, object: Any? = nil,
                     change: @escaping @Sendable (Notification) -> SpeechAudioChange?) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] notification in
                guard let event = change(notification) else { return }
                let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.intValue ?? -1
                Task { @MainActor in
                    guard let self, self.sessionID == id, self.captureID == generation else { return }
                    self.captureLog("notification=\(name.rawValue) event=\(event) routeReason=\(reason)")
                    self.handleAudioChange(event, session: id, capture: generation)
                }
            })
        }
        observe(AVAudioSession.interruptionNotification) { notification in
            guard let raw = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
            return type == .began ? .interruptionBegan : .interruptionEnded
        }
        observe(AVAudioSession.routeChangeNotification) { _ in .route }
        observe(AVAudioSession.mediaServicesWereLostNotification) { _ in .mediaServices }
        observe(AVAudioSession.mediaServicesWereResetNotification) { _ in .mediaServices }
        // Ignore another (or a previously torn-down) engine's notifications.
        observe(.AVAudioEngineConfigurationChange, object: configurationObject) { _ in .configuration }
    }

    private func handleAudioChange(_ change: SpeechAudioChange, session id: UUID, capture generation: UUID) {
        switch change {
        case .interruptionBegan: fail(SpeechCaptureError.interrupted); return
        case .interruptionEnded: return
        case .mediaServices: fail(SpeechCaptureError.mediaServices); return
        case .route, .configuration: break
        }
        // Let the system finish settling a route before examining the actual
        // microphone. This checks state; it does not blindly ignore startup errors.
        inputCheck?.cancel()
        inputCheckPending = true
        isAdvancing = false
        advanceUntil = nil
        pauseContinuation = nil
        cruiseUntil = nil
        inputCheck = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, self.sessionID == id, self.captureID == generation,
                  let capture = self.capture, let previous = self.inputState else { return }
            guard let current = try? await capture.snapshot(), self.sessionID == id,
                  self.captureID == generation, !Task.isCancelled else { return }
            let action = SpeechAudioChangeAction.evaluate(change, previous: previous, current: current)
            self.captureLog("input check action=\(action) channels=\(current.channels) unchangedPort=\(previous.portIDs == current.portIDs)")
            self.inputCheckPending = false
            self.inputCheck = nil
            switch action {
            case .keepRecording:
                self.inputState = current
                self.updateActivity()
            case .rebuildEngine:
                guard self.recoveryBudget.request(at: ProcessInfo.processInfo.systemUptime), let pipeline = self.pipeline else {
                    self.fail(SpeechCaptureError.input); return
                }
                do {
                    try await self.beginCapture(pipeline: pipeline, session: id)
                    guard self.sessionID == id, !Task.isCancelled else { return }
                    self.updateActivity()
                } catch {
                    guard self.sessionID == id, !(error is CancellationError), !Task.isCancelled else { return }
                    self.fail(error)
                }
            case .pause(let error): self.fail(error)
            }
        }
    }
}
