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

    var onActiveIndex: (Int) -> Void = { _ in }
    var onReachEnd: () -> Void = {}
    var onAtBottom: (Bool) -> Void = { _ in }
    var onPointerDown: (Bool) -> Void = { _ in }
    var onTap: () -> Void = {}
    var onPinch: (Int) -> Void = { _ in }
    var onPinchEnd: (Int) -> Void = { _ in }
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
            touch.onDown = { [weak self] in self?.parent.onPointerDown(true) }
            touch.onUp = { [weak self] in self?.parent.onPointerDown(false) }
            tv.addGestureRecognizer(touch)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            tv.addGestureRecognizer(pinch)

        }

        func teardown() {
            displayLink?.invalidate()
            displayLink = nil
        }

        // MARK: 渲染

        func render(_ t: Typography) {
            guard let tv = textView, t != rendered else { return }
            if rendered?.content != t.content {
                charCount = PrompterCore.readableCharCount(t.content)
            }
            let keepIndex = activeIndex
            rendered = t
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
                top: max(76, (size.height * 0.16).rounded()),
                left: max(horizontal, safe.left),
                bottom: max(160, (size.height * 0.18).rounded()),
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

        /// 定位到某个字所在行（行中心对齐视口中线）；index 0 = 顶部
        func scrollToIndex(_ index: Int) {
            guard let tv = textView else { return }
            var target: CGFloat = 0
            if index > 0, let rect = lineRect(forCharIndex: index) {
                target = rect.midY + tv.textContainerInset.top - tv.bounds.height / 2
            }
            position = min(max(0, target), maxOffset)
            tv.setContentOffset(CGPoint(x: 0, y: position), animated: false)
            computeActive()
            updateAtBottom()
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
        private func lineRect(forCharIndex index: Int) -> CGRect? {
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
            return line.map { $0.typographicBounds.offsetBy(dx: origin.x, dy: origin.y) }
        }

        private func computeActive() {
            guard let tv = textView,
                  let index = characterIndexOfLine(atViewportY: tv.bounds.height / 2),
                  index != activeIndex else { return }
            activeIndex = index
            notify { $0.onActiveIndex(index) }
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

        func setPlaying(_ playing: Bool) {
            if playing {
                guard displayLink == nil else { return }
                ended = false
                lastTimestamp = nil
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            } else {
                displayLink?.invalidate()
                displayLink = nil
                lastTimestamp = nil
            }
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let tv = textView else { return }
            let now = link.timestamp
            guard !userInteracting else { lastTimestamp = nil; return }
            defer { lastTimestamp = now }
            guard let last = lastTimestamp else { return }
            let dt = min(now - last, 0.1) // 从后台回来不一跳到底
            let limit = maxOffset
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
            if displayLink != nil {
                notify { $0.onUserDragPause() }
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { userInteracting = false }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            userInteracting = false
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if userInteracting || abs(scrollView.contentOffset.y - position) > 0.5 {
                position = scrollView.contentOffset.y
            }
            computeActive()
            updateAtBottom()
        }

        // MARK: 手势

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard CACurrentMediaTime() >= suppressTapUntil else { return } // 捏合后短暂抑制
            parent.onTap()
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let tv = textView else { return }
            switch gesture.state {
            case .began:
                pinchStartFont = rendered?.fontSize ?? SettingsData.defaults.fontSize
                lastPinchFont = pinchStartFont
                suppressTapUntil = CACurrentMediaTime() + 0.5
                // 取消正在进行的单指滚动：双指期间只调字号不滚动
                tv.panGestureRecognizer.isEnabled = false
                tv.panGestureRecognizer.isEnabled = true
            case .changed:
                guard abs(gesture.scale - 1) >= 0.03 else { return } // 死区：轻点误判防护
                let next = PrompterCore.pinchFontSize(scale: gesture.scale, startFontSize: pinchStartFont)
                guard next != lastPinchFont else { return }
                lastPinchFont = next
                parent.onPinch(next)
            case .ended, .cancelled, .failed:
                suppressTapUntil = CACurrentMediaTime() + 0.5
                parent.onPinchEnd(lastPinchFont)
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
        tracking = false
    }
}
