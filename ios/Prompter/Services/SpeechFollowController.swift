import AVFoundation
import Foundation

enum SpeechCaptureError: LocalizedError, Equatable {
    case permission, model, input, overloaded, interrupted, inputChanged, mediaServices
    var errorDescription: String? {
        switch self {
        case .permission: return "麦克风权限未开启，请在系统设置中允许提词器使用麦克风。"
        case .model: return "离线语音模型未能启动，请重新打开提词页后重试。"
        case .input: return "麦克风暂不可用，请检查音频设备后重试。"
        case .overloaded: return "本机识别未能跟上录音，已暂停。请关闭其他高负载应用后重试。"
        case .interrupted: return "音频会话被系统中断，已暂停。轻点正文重新开始。"
        case .inputChanged: return "录音设备已切换，已暂停。确认麦克风后轻点正文继续。"
        case .mediaServices: return "系统音频服务已重置，已暂停。轻点正文重新开始。"
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
private final class SpeechRecognitionPipeline {
    struct Event {
        var capturedAt: TimeInterval
        var epoch: UInt64
        var voice: Bool
        var rms: Float
        var threshold: Float
        var result: SpeechRecognitionResult?
    }
    private static let inferenceQueue = DispatchQueue(label: "prompter.local-speech", qos: .userInitiated)
    private let queue = SpeechRecognitionPipeline.inferenceQueue
    private let lock = NSLock()
    private var stopped = false
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
                completion(.success(()))
            } catch { completion(.failure(error)) }
        }
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        queue.async { self.recognizer = nil; self.voiceDetector = nil; self.resampler = SpeechAudioResampler() }
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
            self.resampler = SpeechAudioResampler()
            self.voiceDetector?.reset()
            self.lock.lock()
            let stillValid = !self.stopped && self.epoch == version
            if stillValid { self.suspended = false }
            self.lock.unlock()
            completion(stillValid ? .success(version) : .failure(CancellationError()))
        }
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
    let audioMeter = SpeechAudioMeter()
    private var lastAlignedAt: TimeInterval?
    var indicatorFeedback: PromptSpeechFeedback {
        let now = ProcessInfo.processInfo.systemUptime
        return .init(speaking: speechDetected && lastMatchSucceeded && !inputCheckPending && now - lastAudio < 0.25,
                     alignedAt: lastAlignedAt, interactionPaused: isInteractionPaused)
    }
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
    @Published private(set) var lastRecognized = ""
    @Published private(set) var lastMatchSucceeded = false
    @Published private(set) var recognizedLineDelta: Double?
    private var engine: AVAudioEngine?
    private var pipeline: SpeechRecognitionPipeline?
    private var sessionID: UUID?
    private let audioSession: SpeechAudioSessionCoordinator
    private var observers: [NSObjectProtocol] = []
    private var inputCheck: Task<Void, Never>?
    private var inputCheckPending = false
    private var inputState: SpeechAudioInputState?
    private var captureID = UUID()
    private var hasInputTap = false
    private var recoveryBudget = SpeechCaptureRecoveryBudget()
    private var clock: Task<Void, Never>?
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

    init(requestPermission: @escaping () async -> Bool = {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }, audioSession: SpeechAudioSessionCoordinator? = nil) {
        self.requestPermission = requestPermission
        self.audioSession = audioSession ?? .shared
    }

    func start(content: String, startUTF16: Int, modelDirectory: URL, kind: SpeechEngineKind = .paraformer) async {
        stop()
        let id = UUID()
        sessionID = id
        errorMessage = nil
        lastRecognized = ""
        lastMatchSucceeded = false
        reachedEnd = false
        matcher = SpeechScriptMatcher(content: content, startUTF16: startUTF16)
        scriptContent = content
        recognitionEpoch = 0
        timing = SpeechFollowTiming()
        settlement = SpeechFollowSettlement()
        viewportOffset = nil; viewportDelta = nil
        inputHasVoice = false
        speechDetected = false
        target = nil
        recognizedLineDelta = nil
        matched = false
        lastResultAt = 0
        audioPackets = 0
        voicePackets = 0
        recoveryBudget = SpeechCaptureRecoveryBudget()
        captureLog("starting engine=\(kind.rawValue) startOffset=\(startUTF16) scriptTokens=\(matcher.script.tokens.count)")
        status = "正在开启本地识别…"
        let allowed = await requestPermission()
        guard sessionID == id else { return }
        guard !Task.isCancelled else { stop(); return }
        guard allowed else { fail(SpeechCaptureError.permission); return }
        do {
            var appleFactory: (() throws -> any LocalSpeechRecognizer)?
            if kind == .apple {
                status = "正在准备 Apple 中文离线资源…"
                appleFactory = try await AppleSpeechPreparation.prepare { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.sessionID == id else { return }
                        self.status = progress.map { "正在准备 Apple 中文离线资源 \(Int(min(1, max(0, $0)) * 100))%" } ?? "正在启动 Apple 本地识别…"
                    }
                }
                guard sessionID == id, !Task.isCancelled else { return }
            }
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
            try await audioSession.activate(owner: id)
            guard sessionID == id, !Task.isCancelled else {
                audioSession.release(owner: id)
                pipeline.stop()
                return
            }
            try beginCapture(pipeline: pipeline, session: id)
            if isInteractionPaused, let index = pendingResumeUTF16 { await resumeAfterInteraction(atUTF16: index) }
            guard sessionID == id, !Task.isCancelled else { return }
            status = isInteractionPaused ? "手动调整中 · 松手 1.5 秒后恢复" : "等待朗读 · 音频仅在本机处理"
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
        inputCheck?.cancel(); inputCheck = nil
        inputCheckPending = false
        inputState = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        detachEngine()
        pipeline?.stop(); pipeline = nil
        if let owner { audioSession.release(owner: owner) }
        isAdvancing = false
        advanceUntil = nil
        pauseContinuation = nil
        cruiseUntil = nil
        speechDetected = false
        target = nil
        recognizedLineDelta = nil
        status = errorMessage ?? "轻点正文开始语音跟随"
    }

    func pauseForInteraction() {
        guard sessionID != nil else { return }
        lastRecognized = ""
        lastMatchSucceeded = false
        lastAlignedAt = nil
        interactionRevision = UUID()
        interactionResume?.cancel(); interactionResume = nil
        pendingResumeUTF16 = nil
        isInteractionPaused = true
        recognitionEpoch = nil
        pipeline?.suspend()
        target = nil
        recognizedLineDelta = nil
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
        guard let pipeline else { pendingResumeUTF16 = index; return }
        pendingResumeUTF16 = nil
        let revision = interactionRevision
        matcher = SpeechScriptMatcher(content: scriptContent, startUTF16: index)
        timing = SpeechFollowTiming()
        settlement = SpeechFollowSettlement()
        viewportOffset = nil; viewportDelta = nil
        inputHasVoice = false
        speechDetected = false
        matched = false
        target = nil
        recognizedLineDelta = nil
        reachedEnd = false
        lastResultAt = 0
        do {
            let epoch = try await withCheckedThrowingContinuation { continuation in
                pipeline.resume { continuation.resume(with: $0) }
            }
            guard sessionID == id, interactionRevision == revision, !Task.isCancelled else { return }
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

    private func receive(_ event: SpeechRecognitionPipeline.Event) {
        guard !isInteractionPaused, recognitionEpoch == event.epoch else { return }
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
            lastRecognized = result.text
            captureLog("ASR segment=\(result.segment) chars=\(result.text.count) final=\(result.isFinal)")
            lastResultAt = event.capturedAt
            if let match = matcher.match(result.text) {
                if target?.utf16End != match.utf16End { captureLog("matched script offset=\(match.utf16End)") }
                timing.observeMatch(token: match.tokenEnd, at: event.capturedAt)
                target = .init(utf16End: match.utf16End, tokensPerSecond: timing.tokensPerSecond)
                matched = true
                lastMatchSucceeded = true
                lastAlignedAt = ProcessInfo.processInfo.systemUptime
                settlement.matched(offset: match.utf16End, final: result.isFinal,
                                   reachedEnd: match.reachedEnd, at: ProcessInfo.processInfo.systemUptime)
            } else {
                captureLog("no match cursor=\(matcher.cursor)")
                matched = false
                lastMatchSucceeded = false
            }
        }
        updateActivity()
    }

    func updateRecognizedLinePosition(utf16: Int, delta: Double, report: Bool) {
        guard target?.utf16End == utf16, !isInteractionPaused else { return }
        viewportOffset = utf16
        viewportDelta = delta
        if report { recognizedLineDelta = delta }
        #if DEBUG
        let now = ProcessInfo.processInfo.systemUptime
        if report && now - lastViewportLogAt >= 0.5 {
            lastViewportLogAt = now
            captureLog("viewport offset=\(utf16) delta=\(delta)")
        }
        #endif
        if settlement.completionReady(delta: delta, voice: inputHasVoice, at: ProcessInfo.processInfo.systemUptime) { reachedEnd = true }
    }

    private func captureLog(_ message: String) {
        #if DEBUG
        let session = AVAudioSession.sharedInstance()
        let input = session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ",")
        SpeechCaptureDiagnostics.record("\(message) running=\(engine?.isRunning ?? false) rate=\(session.sampleRate) input=\(input)")
        #endif
    }

    private func updateActivity() {
        if isInteractionPaused {
            isAdvancing = false
            advanceUntil = nil
            pauseContinuation = nil
            cruiseUntil = nil
            status = "手动调整中 · 松手 1.5 秒后恢复"
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastAudio > 3 { fail(SpeechCaptureError.input); return }
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
        if advance { text = inputHasVoice ? "语音跟随中" : settling ? "正在对齐已识别文字" : "短暂停顿 · 缓慢续滚" }
        else if timing.lastVoice != nil && !inputHasVoice { text = "停顿中 · 继续朗读即可跟随" }
        else if lastResultAt > 0 && !matched { text = "等待匹配原稿 · 请读当前附近的文字" }
        else { text = "等待朗读 · 音频仅在本机处理" }
        if status != text { status = text }
        let delta = viewportOffset == target?.utf16End ? viewportDelta : nil
        if settlement.completionReady(delta: delta, voice: inputHasVoice, at: now) { reachedEnd = true }
    }

    private func detachEngine() {
        audioMeter.stop()
        lastAlignedAt = nil
        if let engine {
            if hasInputTap { engine.inputNode.removeTap(onBus: 0) }
            engine.stop()
        }
        hasInputTap = false
        engine = nil
    }

    private func beginCapture(pipeline: SpeechRecognitionPipeline, session id: UUID) throws {
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        detachEngine()
        captureID = UUID()
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
            throw SpeechCaptureError.input
        }
        let levelInput = audioMeter.input
        let levelCapture = captureID
        audioMeter.start(capture: levelCapture)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let frames = Int(buffer.frameLength)
            let count = Int(buffer.format.channelCount)
            var samples = [Float](repeating: 0, count: frames)
            for channel in 0..<count {
                for frame in 0..<frames {
                    let value = buffer.format.isInterleaved ? channels[0][frame * count + channel] : channels[channel][frame]
                    samples[frame] += value / Float(count)
                }
            }
            let capturedAt = ProcessInfo.processInfo.systemUptime
            let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(frames))
            levelInput.push(rms: rms, at: capturedAt, capture: levelCapture)
            pipeline.submit(samples: samples, sampleRate: buffer.format.sampleRate, capturedAt: capturedAt)
        }
        hasInputTap = true
        engine.prepare()
        try engine.start()
        inputState = currentInput(engine)
        lastAudio = ProcessInfo.processInfo.systemUptime
        captureLog("engine started")
        observeAudioChanges(engine: engine, session: id, capture: captureID)
    }

    private func currentInput(_ engine: AVAudioEngine) -> SpeechAudioInputState {
        let format = engine.inputNode.outputFormat(forBus: 0)
        return .init(portIDs: AVAudioSession.sharedInstance().currentRoute.inputs.map(\.uid).sorted(),
                     sampleRate: format.sampleRate, channels: Int(format.channelCount), running: engine.isRunning)
    }

    private func observeAudioChanges(engine: AVAudioEngine, session id: UUID, capture generation: UUID) {
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
        observe(.AVAudioEngineConfigurationChange, object: engine) { _ in .configuration }
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
                  let engine = self.engine, let previous = self.inputState else { return }
            let current = self.currentInput(engine)
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
                    try self.beginCapture(pipeline: pipeline, session: id)
                    self.updateActivity()
                } catch { self.fail(error) }
            case .pause(let error): self.fail(error)
            }
        }
    }
}
