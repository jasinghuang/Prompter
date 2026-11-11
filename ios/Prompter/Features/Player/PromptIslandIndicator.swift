import SwiftUI
import UIKit

@MainActor
final class PromptReadingProgress: ObservableObject {
    @Published private(set) var value = 0.0
    @Published private(set) var completed = false
    private var lastReading = 0.0
    func update(_ reading: Double) {
        let next = PromptIndicatorState.bounded(reading)
        if completed && next < lastReading - 0.0001 { completed = false }
        lastReading = next
        let shown = completed ? 1 : next
        if abs(shown - value) > 0.0001 { value = shown }
    }
    func complete() { completed = true; value = 1 }
}

/// This view observes visual-only signals. It never controls recognition,
/// playback, scrolling, or audio-session ownership.
struct PlayerPromptIndicator: View {
    @ObservedObject var meter: SpeechAudioMeter
    @ObservedObject var progress: PromptReadingProgress
    var feedback: () -> PromptSpeechFeedback
    var playing: Bool
    var visible: Bool
    var calibration: IslandIndicatorCalibration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let feedback = feedback()
        GeometryReader { geometry in
            if visible && geometry.size.width > geometry.size.height {
                PromptIslandOverlay(state: .make(progress: progress.value, level: meter.level, sampleAt: meter.sampledAt,
                                                alignedAt: feedback.alignedAt, speaking: feedback.speaking, playing: playing,
                                                interactionPaused: feedback.interactionPaused, completed: progress.completed,
                                                at: ProcessInfo.processInfo.systemUptime),
                                    visible: true, calibration: calibration, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}

struct PromptIslandOverlay: UIViewRepresentable {
    var state: PromptIndicatorState
    var visible: Bool
    var calibration: IslandIndicatorCalibration
    var reduceMotion = false

    func makeUIView(context: Context) -> IndicatorView { IndicatorView() }
    func updateUIView(_ view: IndicatorView, context: Context) {
        view.update(state: state, visible: visible, calibration: calibration, reduceMotion: reduceMotion)
    }
    static func dismantleUIView(_ view: IndicatorView, coordinator: Void) { view.invalidate() }

    final class IndicatorView: UIView {
        private let rail = CAShapeLayer()
        private let progress = CAShapeLayer()
        private let goldGlow = CAShapeLayer()
        private let greenGlow = CAShapeLayer()
        private let gold = UIColor(red: 1, green: 0.82, blue: 0.43, alpha: 1)
        private let green = UIColor(red: 0.12, green: 0.9, blue: 0.49, alpha: 1)
        private var state = PromptIndicatorState()
        private var wantsVisible = false
        private var calibration = IslandIndicatorCalibration()
        private var reduceMotion = false
        private var lastFrame: CGRect?
        private var lastCompleted = false
        private var drewProgress = false
        private var orientationObserver: NSObjectProtocol?
        #if DEBUG
        private var lastLayoutReport = ""
        #endif

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            clipsToBounds = false
            accessibilityIdentifier = "player.islandIndicator"
            accessibilityLabel = "镜头旁提词进度"
            accessibilityTraits = .staticText
            for shape in [goldGlow, greenGlow, rail, progress] {
                shape.fillColor = UIColor.clear.cgColor
                shape.lineCap = .round
                shape.lineJoin = .round
                layer.addSublayer(shape)
            }
            rail.strokeColor = gold.withAlphaComponent(0.6).cgColor; rail.lineWidth = 1.5
            progress.strokeColor = green.cgColor; progress.lineWidth = 2.2
            goldGlow.strokeColor = gold.cgColor; goldGlow.shadowColor = gold.cgColor
            greenGlow.strokeColor = green.cgColor; greenGlow.shadowColor = green.cgColor
            for glow in [goldGlow, greenGlow] {
                glow.lineWidth = 1.6; glow.shadowOpacity = 0.9; glow.opacity = 0
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil && orientationObserver == nil {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                orientationObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                                                             object: nil, queue: .main) { [weak self] _ in
                    // 180-degree rotations can keep identical bounds/insets.
                    // Re-read the scene orientation after the system transition.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.layoutIndicator() }
                }
            } else if window == nil { invalidate() }
            setNeedsLayout()
        }
        func invalidate() {
            if let orientationObserver {
                NotificationCenter.default.removeObserver(orientationObserver)
                self.orientationObserver = nil
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
        }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
        override func layoutSubviews() { super.layoutSubviews(); layoutIndicator() }
        override var accessibilityFrame: CGRect {
            get {
                guard let lastFrame else { return super.accessibilityFrame }
                return UIAccessibility.convertToScreenCoordinates(lastFrame, in: self)
            }
            set { super.accessibilityFrame = newValue }
        }

        func update(state: PromptIndicatorState, visible: Bool, calibration: IslandIndicatorCalibration, reduceMotion: Bool) {
            self.state = state; wantsVisible = visible; self.calibration = calibration; self.reduceMotion = reduceMotion
            layoutIndicator()
        }

        private func layoutIndicator() {
            #if DEBUG
            let report = "visible=\(wantsVisible) bounds=\(bounds) window=\(String(describing: window?.bounds)) safe=\(String(describing: window?.safeAreaInsets))"
            if report != lastLayoutReport {
                lastLayoutReport = report
                SpeechCaptureDiagnostics.record("[PromptIndicator] \(report)")
            }
            #endif
            guard let window, wantsVisible, window.bounds.width > window.bounds.height,
                  window.windowScene?.interfaceOrientation.isLandscape == true,
                  max(window.safeAreaInsets.left, window.safeAreaInsets.right) >= 51 else {
                isHidden = true; isAccessibilityElement = false; lastCompleted = state.completed
                return
            }
            let cameraOnLeft = window.windowScene?.interfaceOrientation == .landscapeRight
            guard let windowFrame = IslandIndicatorGeometry.frame(size: window.bounds.size, cameraOnLeft: cameraOnLeft,
                                                                   model: IslandIndicatorGeometry.currentModel, calibration: calibration) else { return }
            let rect = convert(windowFrame, from: window)
            isHidden = false; isAccessibilityElement = true
            accessibilityValue = "\(Int(state.progress * 100))%"
            let changedGeometry = lastFrame != rect
            let oldProgress = progress.presentation()?.strokeEnd ?? progress.strokeEnd
            let oldOpacity = greenGlow.presentation()?.opacity ?? greenGlow.opacity
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if changedGeometry {
                lastFrame = rect
                let path = IslandIndicatorGeometry.path(in: rect)
                for shape in [rail, progress, goldGlow, greenGlow] { shape.path = path }
            }
            progress.strokeEnd = state.progress
            greenGlow.strokeEnd = state.progress
            let pulse = reduceMotion ? 0 : state.pulse
            goldGlow.opacity = Float(pulse * 0.32)
            greenGlow.opacity = Float(pulse * 0.65)
            goldGlow.shadowRadius = 3 + pulse * 7
            greenGlow.shadowRadius = 4 + pulse * 10
            CATransaction.commit()
            if drewProgress && !changedGeometry && !reduceMotion && abs(oldProgress - state.progress) > 0.0001 {
                for shape in [progress, greenGlow] {
                    let animation = CABasicAnimation(keyPath: "strokeEnd")
                    animation.fromValue = oldProgress; animation.toValue = state.progress
                    animation.duration = 0.18
                    shape.add(animation, forKey: "readingProgress")
                }
            }
            if !reduceMotion && pulse == 0 && oldOpacity > 0.01 {
                for glow in [goldGlow, greenGlow] where glow.animation(forKey: "quietFade") == nil {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = glow.presentation()?.opacity ?? oldOpacity; fade.toValue = 0
                    fade.duration = 0.3
                    glow.add(fade, forKey: "quietFade")
                }
            } else if pulse > 0 {
                goldGlow.removeAnimation(forKey: "quietFade"); greenGlow.removeAnimation(forKey: "quietFade")
            }
            if state.completed && !lastCompleted && !reduceMotion {
                let flash = CAKeyframeAnimation(keyPath: "opacity")
                flash.values = [0, 0.75, 0]; flash.keyTimes = [0, 0.3, 1]; flash.duration = 0.65
                greenGlow.add(flash, forKey: "readingComplete")
            }
            lastCompleted = state.completed; drewProgress = true
        }

    }
}
