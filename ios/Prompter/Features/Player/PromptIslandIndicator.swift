import SwiftUI
import UIKit

@MainActor
final class PromptReadingProgress: ObservableObject {
    @Published private(set) var value = 0.0
    @Published private(set) var completed = false
    private var lastReading = 0.0
    func update(_ reading: Double) {
        let next = reading.isFinite ? min(1, max(0, reading)) : 0
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
    @ObservedObject var progress: PromptReadingProgress
    var visible: Bool
    var calibration: IslandIndicatorCalibration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if visible && geometry.size.width > geometry.size.height {
                PromptIslandOverlay(readingProgress: progress.value, visible: true,
                                    calibration: calibration, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}

struct PromptIslandOverlay: UIViewRepresentable {
    var readingProgress: Double
    var visible: Bool
    var calibration: IslandIndicatorCalibration
    var reduceMotion = false

    func makeUIView(context: Context) -> IndicatorView { IndicatorView() }
    func updateUIView(_ view: IndicatorView, context: Context) {
        view.update(readingProgress: readingProgress, visible: visible, calibration: calibration, reduceMotion: reduceMotion)
    }
    static func dismantleUIView(_ view: IndicatorView, coordinator: Void) { view.invalidate() }

    final class IndicatorView: UIView {
        private let rail = CAShapeLayer()
        private let progress = CAShapeLayer()
        private let gold = UIColor(red: 1, green: 0.82, blue: 0.43, alpha: 1)
        private let green = UIColor(red: 0.12, green: 0.9, blue: 0.49, alpha: 1)
        private var readingProgress = 0.0
        private var wantsVisible = false
        private var calibration = IslandIndicatorCalibration()
        private var reduceMotion = false
        private var lastFrame: CGRect?
        private var drewProgress = false
        private var drawnProgress = 0.0
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
            for shape in [rail, progress] {
                shape.fillColor = UIColor.clear.cgColor
                shape.lineCap = .round
                shape.lineJoin = .round
                layer.addSublayer(shape)
            }
            rail.strokeColor = gold.withAlphaComponent(0.6).cgColor; rail.lineWidth = 1.5
            progress.strokeColor = green.cgColor; progress.lineWidth = 2.2
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

        func update(readingProgress: Double, visible: Bool, calibration: IslandIndicatorCalibration, reduceMotion: Bool) {
            self.readingProgress = readingProgress.isFinite ? min(1, max(0, readingProgress)) : 0
            wantsVisible = visible; self.calibration = calibration; self.reduceMotion = reduceMotion
            layoutIndicator()
        }

        private func layoutIndicator() {
            #if DEBUG
            if SpeechCaptureDiagnostics.enabled {
                let report = "visible=\(wantsVisible) bounds=\(bounds) window=\(String(describing: window?.bounds)) safe=\(String(describing: window?.safeAreaInsets))"
                if report != lastLayoutReport {
                    lastLayoutReport = report
                    SpeechCaptureDiagnostics.record("[PromptIndicator] \(report)")
                }
            }
            #endif
            guard let window, wantsVisible, window.bounds.width > window.bounds.height,
                  window.windowScene?.interfaceOrientation.isLandscape == true,
                  max(window.safeAreaInsets.left, window.safeAreaInsets.right) >= 51 else {
                isHidden = true; isAccessibilityElement = false
                return
            }
            let cameraOnLeft = window.windowScene?.interfaceOrientation == .landscapeRight
            guard let windowFrame = IslandIndicatorGeometry.frame(size: window.bounds.size, cameraOnLeft: cameraOnLeft,
                                                                   model: IslandIndicatorGeometry.currentModel, calibration: calibration) else { return }
            let rect = convert(windowFrame, from: window)
            isHidden = false; isAccessibilityElement = true
            accessibilityValue = "\(Int(readingProgress * 100))%"
            let changedGeometry = lastFrame != rect
            let changedProgress = abs(drawnProgress - readingProgress) > 0.0001
            let oldProgress = progress.presentation()?.strokeEnd ?? progress.strokeEnd
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if changedGeometry {
                lastFrame = rect
                let local = CGRect(origin: .zero, size: rect.size)
                let path = IslandIndicatorGeometry.path(in: local)
                for shape in [rail, progress] {
                    shape.frame = rect
                    shape.contentsScale = window.screen.scale
                    shape.path = path
                }
            }
            progress.strokeEnd = readingProgress
            CATransaction.commit()
            if drewProgress && !changedGeometry && !reduceMotion && changedProgress {
                let animation = CABasicAnimation(keyPath: "strokeEnd")
                animation.fromValue = oldProgress; animation.toValue = readingProgress
                animation.duration = 0.18
                progress.add(animation, forKey: "readingProgress")
            }
            drawnProgress = readingProgress
            drewProgress = true
        }

    }
}
