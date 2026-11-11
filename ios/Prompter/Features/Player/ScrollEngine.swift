import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// 提词正文滚动引擎（M3 核心）
/// UITextView(TextKit 2) 承载正文，CADisplayLink 每帧推进 contentOffset，
/// 与手动拖拽共享同一 contentOffset——对应 Web 版 useAutoScroll 走原生滚动通道、无缝切换的设计。
struct PrompterScrollView: UIViewRepresentable {
    /// 影响排版的全部参数：任一变化即重建富文本，并保持当前阅读行居中
    struct Typography: Equatable {
        var content: String
        var fontSize: Int
        var letterSpacing: Double
        var lineHeight: Double
        var horizontalPadding: Int
        var textAlign: String
    }

    let typography: Typography
    let isPlaying: Bool
    let wordsPerMinute: Int
    let controller: ScrollEngineController
    var voiceMode = false
    var voiceTarget: SpeechFollowTarget? = nil
    var voiceAdvancing = false
    var voiceAdvanceUntil: TimeInterval?
    var voicePauseContinuation: SpeechPauseContinuation?
    var voiceCruiseUntil: TimeInterval?

    var onActiveIndex: (Int) -> Void = { _ in }
    var onReadingProgress: (Double) -> Void = { _ in }
    var onVoiceViewport: (Int, Double) -> Void = { _, _ in }
    var onReachEnd: () -> Void = {}
    var onAtBottom: (Bool) -> Void = { _ in }
    var onPointerDown: (Bool) -> Void = { _ in }
    var onTap: () -> Void = {}
    var onPinch: (Int) -> Void = { _ in }
    var onPinchEnd: (Int) -> Void = { _ in }
    var onVoiceInteractionBegan: () -> Void = {}
    var onVoiceResumeAt: (Int) -> Void = { _ in }
    var onUserDragPause: () -> Void = {} // 播放中用户拖动正文 → 暂停（计时随之停）

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PrompterTextView {
        let tv = PrompterTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = true
        tv.showsVerticalScrollIndicator = false
        tv.showsHorizontalScrollIndicator = false
        tv.alwaysBounceVertical = true
        tv.backgroundColor = .clear
        tv.contentInsetAdjustmentBehavior = .never
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.panGestureRecognizer.maximumNumberOfTouches = 1 // 双指留给捏合调字号
        tv.delaysContentTouches = false
        context.coordinator.attach(tv)
        controller.coordinator = context.coordinator
        return tv
    }

    func updateUIView(_ uiView: PrompterTextView, context: Context) {
        let c = context.coordinator
        c.parent = self
        c.wordsPerMinute = wordsPerMinute
        c.render(typography)
        c.updateVoiceTarget()
        c.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ uiView: PrompterTextView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: PrompterScrollView
        var wordsPerMinute = 160
        private(set) var activeIndex = 0

        weak var textView: PrompterTextView?
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval?
        private var lastVoiceDebugTarget = -1
        private var voiceMotion = SpeechScrollMotion()
        private var voiceSpeed = SpeechScrollSpeed()
        private var speedPauseStartedAt: TimeInterval?
        private var speedPauseBoundary = 0.0
        private var voiceDestination: CGFloat?
        private var voiceConfirmedLineY: CGFloat?
        private var lastViewportReport: CFTimeInterval = 0
        private var voiceLinesPerSecond = 1.0
        private var resolvedVoiceTarget: SpeechFollowTarget?
        private var renderedVoiceMode = false
        private var handoff = SpeechTouchHandoff()
        private var resumeTask: Task<Void, Never>?
        private var pinching = false
        private var position: CGFloat = 0 // 自持滚动位置，避免逐帧取整漂移
        private var ended = false
        private var userInteracting = false
        private var atBottom = false
        private var rendered: Typography?
        private var charCount = 0

        private var pinchStartFont = 0
        private var lastPinchFont = 0
        private var suppressTapUntil: CFTimeInterval = 0

        init(_ parent: PrompterScrollView) {
            self.parent = parent
        }

        func attach(_ tv: PrompterTextView) {
            textView = tv
            tv.delegate = self
            tv.onLayoutChange = { [weak self] in
                DispatchQueue.main.async { self?.handleLayoutChange() }
            }

            // 轻点播放/暂停：系统 UITapGestureRecognizer 自带标准位移容差与手指滚动判定，
            // 拦停惯性滚动的触摸会被 UIScrollView 的 pan 抢占而使 tap 失败——误触天然被排除
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            tv.addGestureRecognizer(tap)

            // 只观察按住/抬起（拖拽浏览时隐藏中央提示），不参与点击判定
            let touch = TouchObserverRecognizer()
            touch.onDown = { [weak self] in self?.pointerDown() }
            touch.onUp = { [weak self] in self?.pointerUp() }
            tv.addGestureRecognizer(touch)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            tv.addGestureRecognizer(pinch)

        }

        func teardown() {
            resumeTask?.cancel()
            handoff.reset()
            displayLink?.invalidate()
            displayLink = nil
        }

        // MARK: 渲染

        func render(_ t: Typography) {
            guard let tv = textView, t != rendered || renderedVoiceMode != parent.voiceMode else { return }
            if rendered?.content != t.content {
                charCount = PrompterCore.readableCharCount(t.content)
            }
            let keepIndex = activeIndex
            rendered = t
            renderedVoiceMode = parent.voiceMode
            tv.attributedText = Self.attributedString(for: t)
            applyInsets()
            relayout()
            scrollToIndex(keepIndex)
        }

        private func handleLayoutChange() {
            guard rendered != nil else { return }
            applyInsets()
            relayout()
            scrollToIndex(activeIndex)
        }

        /// 上下留白 16vh/18vh；左右 = max(百分比内边距, 内容列居中到 896pt, 安全区)
        private func applyInsets() {
            guard let tv = textView, let t = rendered else { return }
            let size = tv.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let safe = tv.safeAreaInsets
            let percent = size.width * CGFloat(t.horizontalPadding) / 100
            let centering = max(0, (size.width - 896) / 2)
            let horizontal = max(percent, centering)
            tv.textContainerInset = UIEdgeInsets(
                top: parent.voiceMode ? max(0, readingAnchor - CGFloat(t.fontSize) * t.lineHeight / 2) : max(76, (size.height * 0.16).rounded()),
                left: max(horizontal, safe.left),
                bottom: parent.voiceMode ? size.height - readingAnchor + voiceLead : max(160, (size.height * 0.18).rounded()),
                right: max(horizontal, safe.right)
            )
        }

        private func relayout() {
            guard let tv = textView else { return }
            if let tlm = tv.textLayoutManager {
                tlm.ensureLayout(for: tlm.documentRange)
            }
            tv.layoutIfNeeded()
        }

        private static func attributedString(for t: Typography) -> NSAttributedString {
            let size = CGFloat(t.fontSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = size * t.lineHeight
            paragraph.maximumLineHeight = size * t.lineHeight
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineBreakStrategy = []
            switch t.textAlign {
            case "center": paragraph.alignment = .center
            case "right": paragraph.alignment = .right
            default: paragraph.alignment = .left
            }
            return NSAttributedString(string: t.content, attributes: [
                .font: UIFont.systemFont(ofSize: size),
                .foregroundColor: UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1),
                .paragraphStyle: paragraph,
                .kern: size * t.letterSpacing,
            ])
        }

        // MARK: 几何

        private var maxOffset: CGFloat {
            guard let tv = textView else { return 0 }
            var height = tv.contentSize.height
            if let tlm = tv.textLayoutManager {
                let usage = tlm.usageBoundsForTextContainer
                height = max(height, usage.maxY + tv.textContainerInset.top + tv.textContainerInset.bottom)
            }
            return max(0, height - tv.bounds.height)
        }

        private var readingAnchor: CGFloat {
            guard let tv = textView else { return 0 }
            return SpeechReadingLayout.anchor(in: tv.bounds.size, voice: parent.voiceMode)
        }

        private var voiceLead: CGFloat {
            guard let tv = textView else { return 0 }
            let lineHeight = CGFloat(rendered?.fontSize ?? 36) * (rendered?.lineHeight ?? 1.5)
            return SpeechReadingLayout.lead(in: tv.bounds.size, lineHeight: lineHeight,
                                           safeTop: tv.safeAreaInsets.top)
        }

        /// 定位到某个字所在行（行中心对齐视口中线）；index 0 = 顶部
        func scrollToIndex(_ index: Int) {
            guard let tv = textView else { return }
            var target: CGFloat = 0
            if (index > 0 || parent.voiceMode), let rect = lineRect(forCharIndex: index) {
                target = rect.midY + tv.textContainerInset.top - readingAnchor
            }
            position = min(max(0, target), maxOffset)
            resetVoiceMotion()
            resolvedVoiceTarget = nil
            updateVoiceTarget(force: true)
            tv.setContentOffset(CGPoint(x: 0, y: position), animated: false)
            computeActive()
            updateAtBottom()
            reportReadingProgress()
        }

        /// 当前阅读行 = 第一个"行中心 ≥ 视口中线"的行，取其首字偏移（UTF-16）
        private func characterIndexOfLine(atViewportY y: CGFloat) -> Int? {
            guard let tv = textView,
                  let tlm = tv.textLayoutManager,
                  let tcm = tlm.textContentManager else { return nil }
            let docStart = tcm.documentRange.location
            guard tcm.offset(from: docStart, to: tcm.documentRange.endLocation) > 0 else { return nil }
            let cy = tv.contentOffset.y + y - tv.textContainerInset.top
            let from = tlm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, cy)))?.rangeInElement.location ?? docStart
            var result: Int?
            tlm.enumerateTextLayoutFragments(from: from, options: [.ensuresLayout]) { fragment in
                let frame = fragment.layoutFragmentFrame
                let fragStart = tcm.offset(from: docStart, to: fragment.rangeInElement.location)
                for line in fragment.textLineFragments where frame.minY + line.typographicBounds.midY >= cy {
                    result = fragStart + line.characterRange.location
                    return false
                }
                return true
            }
            return result ?? lastLineStart(tlm: tlm, tcm: tcm)
        }

        private func lastLineStart(tlm: NSTextLayoutManager, tcm: NSTextContentManager) -> Int? {
            var result: Int?
            tlm.enumerateTextLayoutFragments(from: tcm.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { fragment in
                let fragStart = tcm.offset(from: tcm.documentRange.location, to: fragment.rangeInElement.location)
                result = fragStart + (fragment.textLineFragments.last?.characterRange.location ?? 0)
                return false
            }
            return result
        }

        /// 某个字所在行的排版矩形（文本容器坐标系）
        func lineRect(forCharIndex index: Int) -> CGRect? {
            lineMetrics(forCharIndex: index)?.rect
        }

        private func lineMetrics(forCharIndex index: Int) -> (rect: CGRect, range: NSRange)? {
            guard let tv = textView,
                  let tlm = tv.textLayoutManager,
                  let tcm = tlm.textContentManager else { return nil }
            let docStart = tcm.documentRange.location
            let length = tcm.offset(from: docStart, to: tcm.documentRange.endLocation)
            guard length > 0 else { return nil }
            let clamped = min(max(0, index), length - 1)
            guard let location = tcm.location(docStart, offsetBy: clamped),
                  let fragment = tlm.textLayoutFragment(for: location) else { return nil }
            let fragStart = tcm.offset(from: docStart, to: fragment.rangeInElement.location)
            let local = clamped - fragStart
            let origin = fragment.layoutFragmentFrame.origin
            let line = fragment.textLineFragments.first { NSLocationInRange(local, $0.characterRange) }
                ?? fragment.textLineFragments.last
            return line.map {
                ($0.typographicBounds.offsetBy(dx: origin.x, dy: origin.y),
                 NSRange(location: fragStart + $0.characterRange.location, length: $0.characterRange.length))
            }
        }

        /// Recognition only updates a cached destination. Display frames alone
        /// move the scroll view; every word in one visual line has the same Y.
        func updateVoiceTarget(force: Bool = false) {
            guard force || parent.voiceTarget != resolvedVoiceTarget else { return }
            resolvedVoiceTarget = parent.voiceTarget
            guard let target = parent.voiceTarget, let tv = textView,
                  let metrics = lineMetrics(forCharIndex: max(0, target.utf16End - 1)) else {
                voiceDestination = nil
                voiceConfirmedLineY = nil
                return
            }
            voiceConfirmedLineY = metrics.rect.midY + tv.textContainerInset.top
            voiceLinesPerSecond = target.tokensPerSecond / Double(max(1, metrics.range.length))
            voiceDestination = min(maxOffset, max(0, metrics.rect.midY + tv.textContainerInset.top - readingAnchor + voiceLead))
        }

        private func computeActive() {
            guard let index = characterIndexOfLine(atViewportY: readingAnchor),
                  index != activeIndex else { return }
            activeIndex = index
            notify { $0.onActiveIndex(index) }
            reportReadingProgress()
        }

        private func reportReadingProgress() {
            let length = max(1, textView?.text.utf16.count ?? 0)
            let fraction = position <= 0.5 ? 0 : min(1, max(0, Double(activeIndex) / Double(length)))
            notify { $0.onReadingProgress(fraction) }
        }

        private func updateAtBottom() {
            guard let tv = textView else { return }
            let limit = maxOffset
            let now = limit > 0 && tv.contentOffset.y >= limit - 8 // 8pt 容差兼容橡皮筋回弹
            guard now != atBottom else { return }
            atBottom = now
            notify { $0.onAtBottom(now) }
        }

        /// UIKit 回调可能发生在 SwiftUI 更新周期内，异步回传避免"更新中改状态"
        private func notify(_ body: @escaping (PrompterScrollView) -> Void) {
            let snapshot = parent
            DispatchQueue.main.async { body(snapshot) }
        }

        // MARK: 自动滚动

        private func resetVoiceMotion() {
            voiceMotion.reset(to: Double(position))
            voiceSpeed.reset()
            speedPauseStartedAt = nil
            speedPauseBoundary = 0
        }

        func setPlaying(_ playing: Bool) {
            if playing {
                guard displayLink == nil else { return }
                ended = false
                lastTimestamp = nil
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                let maximum = Float(textView?.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond)
                link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
                resetVoiceMotion()
                link.add(to: .main, forMode: .common)
                displayLink = link
            } else {
                resumeTask?.cancel(); resumeTask = nil
                handoff.reset()
                resetVoiceMotion()
                displayLink?.invalidate()
                displayLink = nil
                lastTimestamp = nil
            }
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let tv = textView else { return }
            let now = link.timestamp
            guard !userInteracting, !handoff.isSuspended, !pinching else {
                resetVoiceMotion()
                lastTimestamp = nil
                return
            }
            defer { lastTimestamp = now }
            guard let last = lastTimestamp else { return }
            let dt = min(now - last, 0.1) // 从后台回来不一跳到底
            let limit = maxOffset
            if parent.voiceMode {
                updateVoiceTarget()
                // A short pause may move a few points past the old target.
                // Wait for new recognized text instead of rewinding that drift.
                let destination = max(position, voiceDestination ?? position)
                #if DEBUG
                if let target = parent.voiceTarget, lastVoiceDebugTarget != target.utf16End {
                    lastVoiceDebugTarget = target.utf16End
                    SpeechCaptureDiagnostics.record("scroll target=\(target.utf16End) destination=\(destination) position=\(position) limit=\(limit) active=\(activeIndex)")
                }
                #endif
                let lineHeight = CGFloat(rendered?.fontSize ?? 36) * (rendered?.lineHeight ?? 1.5)
                let uptime = ProcessInfo.processInfo.systemUptime
                let previousPosition = Double(position)
                let frameStart = uptime - min(dt, 0.05)
                position = CGFloat(voiceMotion.advance(toward: Double(destination), deltaTime: dt,
                                                       lineHeight: Double(lineHeight), linesPerSecond: voiceLinesPerSecond,
                                                       minimumPosition: voiceConfirmedLineY.map { Double($0 - readingAnchor) },
                                                       settlementRemaining: parent.voiceAdvanceUntil.map { max(0, $0 - uptime) },
                                                       allowed: parent.voiceAdvancing && voiceDestination != nil &&
                                                        (parent.voiceAdvanceUntil.map { uptime < $0 } ?? true)))
                if parent.voiceAdvancing, let confirmedDestination = voiceDestination {
                    var floorDistance = 0.0
                    var floorSpeed = 0.0
                    if let deadline = parent.voiceCruiseUntil, uptime < deadline {
                        floorSpeed = SpeechPauseContinuation.cruisingSpeed(lineHeight: Double(lineHeight))
                        floorDistance = floorSpeed * (uptime - frameStart)
                    } else if let window = parent.voicePauseContinuation {
                        floorSpeed = window.speed(at: uptime, lineHeight: Double(lineHeight))
                        floorDistance = window.distance(from: frameStart, to: uptime, lineHeight: Double(lineHeight))
                    }
                    position = CGFloat(voiceMotion.applyMinimumMotion(from: previousPosition, distance: floorDistance, speed: floorSpeed,
                                                                     maximumPosition: Double(min(limit, confirmedDestination + lineHeight * SpeechPauseContinuation.maximumLineFraction))))
                }
                let pursuing = parent.voiceAdvanceUntil.map { uptime < $0 } ?? true
                let cruising = parent.voiceCruiseUntil.map { uptime < $0 } ?? false
                let pause = parent.voicePauseContinuation
                let continuing = pause.map { uptime < $0.until } ?? false
                let allowed = parent.voiceAdvancing && voiceDestination != nil && (pursuing || cruising || continuing)
                // Longer braking needs room beyond the ordinary cruising lead.
                // The microphone and time window still bound this lookahead.
                if let pause, speedPauseStartedAt != pause.startedAt {
                    speedPauseStartedAt = pause.startedAt
                    speedPauseBoundary = SpeechScrollSpeed.pauseBoundary(position: previousPosition,
                                                                         confirmedDestination: Double(voiceDestination ?? position),
                                                                         velocity: voiceSpeed.velocity, lineHeight: Double(lineHeight))
                } else if pause == nil { speedPauseStartedAt = nil }
                let ordinaryBoundary = Double(voiceDestination ?? position) + (cruising || continuing ? Double(lineHeight) * 1.6 : 0)
                let boundary = min(Double(limit), continuing ? max(ordinaryBoundary, speedPauseBoundary) : ordinaryBoundary)
                let distance = voiceSpeed.advance(requested: max(0, (Double(position) - previousPosition) / max(0.001, dt)),
                                                  floor: SpeechPauseContinuation.cruisingSpeed(lineHeight: Double(lineHeight)),
                                                  at: uptime, deltaTime: dt, lineHeight: Double(lineHeight),
                                                  initialSpeed: Double(lineHeight) * voiceLinesPerSecond, pause: pause,
                                                  remainingDistance: max(0, boundary - previousPosition), allowed: allowed)
                position = CGFloat(previousPosition + distance)
                voiceMotion.rebasePosition(to: Double(position))
                tv.contentOffset = CGPoint(x: 0, y: position)
                if now - lastViewportReport >= 0.2, let target = parent.voiceTarget, let lineY = voiceConfirmedLineY {
                    lastViewportReport = now
                    parent.onVoiceViewport(target.utf16End, Double(lineY - position - readingAnchor))
                }
                return
            }
            let speed = PrompterCore.pointsPerSecond(maxOffset: limit, charCount: charCount, wordsPerMinute: wordsPerMinute)
            guard speed > 0 else { return }
            let next = min(position, limit) + CGFloat(speed * dt)
            if next >= limit {
                position = limit
                tv.contentOffset = CGPoint(x: 0, y: limit)
                if !ended {
                    ended = true
                    notify { $0.onReachEnd() }
                }
                return
            }
            position = next
            tv.contentOffset = CGPoint(x: 0, y: next)
        }

        // MARK: UIScrollViewDelegate（手动拖拽期间暂停推进，松手从新位置继续）

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            userInteracting = true
            lastTimestamp = nil
            // 播放中拖动 = 阅读回看 → 自动暂停（此前引擎悬停但计时照走，观感"播完了时间还在跑"）
            if parent.voiceMode && parent.isPlaying {
                if !handoff.isSuspended { pointerDown() }
                handoff.scrollingBegan()
            } else if displayLink != nil {
                notify { $0.onUserDragPause() }
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                userInteracting = false
                handoff.scrollingEnded()
                scheduleVoiceResume()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            userInteracting = false
            handoff.scrollingEnded()
            scheduleVoiceResume()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if userInteracting || abs(scrollView.contentOffset.y - position) > 0.5 {
                position = scrollView.contentOffset.y
                resetVoiceMotion()
            }
            computeActive()
            updateAtBottom()
        }

        // MARK: 手势

        func pointerDown() {
            parent.onPointerDown(true)
            guard parent.voiceMode, parent.isPlaying else { return }
            resumeTask?.cancel(); resumeTask = nil
            handoff.touchBegan()
            resetVoiceMotion()
            lastTimestamp = nil
            parent.onVoiceInteractionBegan()
        }

        func pointerUp() {
            parent.onPointerDown(false)
            guard parent.voiceMode, parent.isPlaying, handoff.isSuspended else { return }
            handoff.touchEnded(at: CACurrentMediaTime())
            scheduleVoiceResume()
        }

        private func scheduleVoiceResume() {
            resumeTask?.cancel(); resumeTask = nil
            guard parent.voiceMode, parent.isPlaying, !pinching,
                  let delay = handoff.delayUntilResume(at: CACurrentMediaTime()) else { return }
            resumeTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.parent.voiceMode, self.parent.isPlaying, !self.pinching,
                      let remaining = self.handoff.delayUntilResume(at: CACurrentMediaTime()), remaining <= 0 else { return }
                // Rebase at the visible reading line, never the old ASR cursor.
                self.computeActive()
                self.resetVoiceMotion()
                self.voiceDestination = nil
                self.resolvedVoiceTarget = nil
                self.handoff.reset()
                self.parent.onVoiceResumeAt(self.activeIndex)
            }
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard CACurrentMediaTime() >= suppressTapUntil else { return } // 捏合后短暂抑制
            guard !(parent.voiceMode && parent.isPlaying) else { return }
            parent.onTap()
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let tv = textView else { return }
            switch gesture.state {
            case .began:
                pinching = true
                pinchStartFont = rendered?.fontSize ?? SettingsData.defaults.fontSize
                lastPinchFont = pinchStartFont
                suppressTapUntil = CACurrentMediaTime() + 0.5
                // 取消正在进行的单指滚动：双指期间只调字号不滚动
                tv.panGestureRecognizer.isEnabled = false
                tv.panGestureRecognizer.isEnabled = true
                userInteracting = false
                handoff.scrollingEnded()
            case .changed:
                guard abs(gesture.scale - 1) >= 0.03 else { return } // 死区：轻点误判防护
                let next = PrompterCore.pinchFontSize(scale: gesture.scale, startFontSize: pinchStartFont)
                guard next != lastPinchFont else { return }
                lastPinchFont = next
                parent.onPinch(next)
            case .ended, .cancelled, .failed:
                suppressTapUntil = CACurrentMediaTime() + 0.5
                pinching = false
                parent.onPinchEnd(lastPinchFont)
                scheduleVoiceResume()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

/// SwiftUI 侧向引擎发命令的句柄（回到顶部 / 重读）
final class ScrollEngineController {
    fileprivate weak var coordinator: PrompterScrollView.Coordinator?

    func scrollToIndex(_ index: Int) {
        coordinator?.scrollToIndex(index)
    }

    /// 是否停在顶部（重新开拍一条时用于计时归零）
    var isAtTop: Bool {
        (coordinator?.textView?.contentOffset.y ?? 0) <= 1
    }
}

/// 尺寸/安全区变化时通知引擎重算留白并保持阅读行居中
final class PrompterTextView: UITextView {
    var onLayoutChange: (() -> Void)?
    private var lastLayoutSize = CGSize.zero
    private var lastSafeArea = UIEdgeInsets.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize || safeAreaInsets != lastSafeArea else { return }
        lastLayoutSize = bounds.size
        lastSafeArea = safeAreaInsets
        onLayoutChange?()
    }
}

/// 只观察不独占的触摸识别器：仅报告按下/抬起（用于拖拽浏览时隐藏中央提示）
private final class TouchObserverRecognizer: UIGestureRecognizer {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?

    private var tracking = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    convenience init() { self.init(target: nil, action: nil) }

    // Stay alive alongside the scroll view's pan/pinch recognizers so a drag
    // cannot report finger-up early when another recognizer wins.
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    private func activeTouchCount(_ event: UIEvent) -> Int {
        event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard !tracking else { return }
        tracking = true
        onDown?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard tracking, activeTouchCount(event) == 0 else { return }
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard tracking, activeTouchCount(event) == 0 else { return }
        finish()
    }

    private func finish() {
        tracking = false
        onUp?()
        state = .failed
    }

    override func reset() {
        super.reset()
        if tracking { tracking = false; onUp?() }
    }
}
