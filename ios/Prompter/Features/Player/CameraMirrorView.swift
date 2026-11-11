import SwiftUI
import AVFoundation
import QuartzCore

/// 前置化妆镜：打开才取流，关闭取消采集请求并按序停止会话、释放设备；
/// 纯本地预览不录制不上传，水平镜像；加载/错误态文案与 Web 一致。
///
/// The native view observes preview readiness and system failures; blocking
/// hardware work belongs to the serial capture owner.
struct CameraMirrorView: View {
    @Binding var open: Bool
    @State private var status: Status = .loading
    @State private var retryID = UUID()
    @State private var cameraControl = MirrorCameraControl()
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Status: Equatable {
        case loading, ready, failed(String)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                // 显式宽高（Web: 横屏 16:10·高 75%·最宽 80%；竖屏正方·高 72%）——
                // aspectRatio 对贪婪子视图的求值不可靠，曾致卡片横向失控
                let cardHeight = geo.size.height * (landscape ? 0.75 : 0.72)
                let cardWidth = min(geo.size.width * (landscape ? 0.80 : 0.92),
                                    cardHeight * (landscape ? 1.6 : 1.0))
                mirrorCard
                    .frame(width: cardWidth, height: cardHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 镜面卡片（Web: rounded-[22px] surface 底 + 高光渐变描边）

    private var mirrorCard: some View {
        ZStack {
            MirrorCameraView(control: cameraControl, onStatus: { message in
                if let message {
                    status = .failed(message)
                } else {
                    status = .ready
                }
            })
            .id(retryID)
            ZStack {
                if status != .ready { statusOverlay.transition(.opacity) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : AppMotion.detail, value: status == .ready)
            closeButton
        }
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        VStack(spacing: 12) {
            if status == .loading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.accentGold)
                Text("正在开启前置摄像头…")
            } else if case .failed(let message) = status {
                Image(systemName: "video.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.3))
                Text(message)
                if message.contains("权限") {
                    Button("前往系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }.frame(minHeight: 44).foregroundStyle(.accentGold)
                } else {
                    Button("重试") { cameraControl.stop(); status = .loading; retryID = UUID() }
                        .frame(minHeight: 44).foregroundStyle(.accentGold)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.textSecondary)
        .multilineTextAlignment(.center)
        .padding(24)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.45), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("关闭前置镜子")
                .accessibilityIdentifier("mirror.close")
            }
            Spacer()
        }
        .padding(10)
    }

    private func close() {
        // Stop before SwiftUI's fade-out or a replacement view can begin.
        cameraControl.stop()
        open = false
    }
}

// MARK: - 原生预览视图（将界面生命周期绑定到可取消的采集请求）

/// Weak cancellation handle for close/retry actions before SwiftUI teardown.
@MainActor
private final class MirrorCameraControl {
    weak var view: MirrorCameraUIView?
    func stop() { view?.stop() }
}

/// nil = 就绪；非 nil = 错误文案
private struct MirrorCameraView: UIViewRepresentable {
    let control: MirrorCameraControl
    let onStatus: (String?) -> Void
    func makeCoordinator() -> MirrorCameraControl { control }

    func makeUIView(context: Context) -> MirrorCameraUIView {
        let view = MirrorCameraUIView()
        view.onStatus = onStatus
        control.view = view
        return view
    }

    func updateUIView(_ uiView: MirrorCameraUIView, context: Context) {
        uiView.onStatus = onStatus
    }

    static func dismantleUIView(_ uiView: MirrorCameraUIView, coordinator: MirrorCameraControl) {
        uiView.stop() // 移除即取消回调，硬件按后台队列顺序释放
        if coordinator.view === uiView { coordinator.view = nil }
    }
}

final class MirrorCameraUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    var onStatus: ((String?) -> Void)?

    private var capture: MirrorCameraCapture?
    private var request: CaptureRequest?
    private var startTask: Task<Void, Never>?
    private var previewTimeout: Task<Void, Never>?
    private var previewObservation: NSKeyValueObservation?
    private var sessionObserver: MirrorCameraSessionObserver?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        videoPreviewLayer.videoGravity = .resizeAspectFill
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        request?.cancel()
        startTask?.cancel(); previewTimeout?.cancel()
        previewObservation?.invalidate(); rotationObservation?.invalidate()
        capture?.stop()
    }

    func start() {
        guard window != nil, request == nil else { return }
        let request = CaptureRequest()
        self.request = request
        let capture = MirrorCameraCapture()
        self.capture = capture
        sessionObserver = MirrorCameraSessionObserver(session: capture.session) { [weak self] failure in
            self?.fail(failure.localizedDescription, request: request)
        }
        startTask = Task { @MainActor [weak self] in
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard let self, self.isCurrent(request) else { return }
            guard allowed else {
                self.fail("摄像头权限被拒绝，可在系统设置中允许后重试", request: request)
                return
            }
            self.watchPreviewTimeout(request)
            // The mirror action stops speech before mounting this view. Wait
            // for both graph teardown and app-wide audio-session deactivation.
            await SpeechAudioSessionCoordinator.shared.waitForIdle()
            guard self.isCurrent(request), !Task.isCancelled else { return }
            self.videoPreviewLayer.session = capture.session
            self.previewObservation = self.videoPreviewLayer.observe(\.isPreviewing, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.previewChanged(request) }
            }
            do {
                let device = try await capture.start()
                guard self.isCurrent(request), !Task.isCancelled else { capture.stop(); return }
                self.setupRotationCoordinator(device: device)
                self.previewChanged(request)
            } catch {
                guard self.isCurrent(request), !(error is CancellationError) else { return }
                let message = (error as? MirrorCameraFailure)?.localizedDescription ?? MirrorCameraFailure.unavailable.localizedDescription
                self.fail(message, request: request)
            }
        }
    }

    private func isCurrent(_ request: CaptureRequest) -> Bool {
        self.request === request && request.isActive && window != nil
    }

    private func previewChanged(_ request: CaptureRequest) {
        guard isCurrent(request) else { return }
        guard videoPreviewLayer.isPreviewing else { watchPreviewTimeout(request); return }
        previewTimeout?.cancel(); previewTimeout = nil
        onStatus?(nil)
    }

    private func watchPreviewTimeout(_ request: CaptureRequest) {
        previewTimeout?.cancel()
        previewTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            guard let self, self.isCurrent(request) else { return }
            self.fail(MirrorCameraFailure.previewTimeout.localizedDescription, request: request)
        }
    }

    private func fail(_ message: String, request: CaptureRequest) {
        guard isCurrent(request) else { return }
        stop()
        onStatus?(message)
    }

    func stop() {
        request?.cancel(); request = nil
        startTask?.cancel(); startTask = nil
        previewTimeout?.cancel(); previewTimeout = nil
        previewObservation?.invalidate(); previewObservation = nil
        rotationObservation?.invalidate(); rotationObservation = nil
        rotationCoordinator = nil
        sessionObserver?.stop(); sessionObserver = nil
        let previous = capture
        capture = nil
        previous?.stop()
        let preview = videoPreviewLayer
        Task { @MainActor in
            await previous?.waitUntilStopped()
            if let previous, preview.session === previous.session { preview.session = nil }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { start() } else { stop() }
    }

    // MARK: 自动旋转（RotationCoordinator：监听设备姿态始终给地平线水平角；含镜像）

    private func setupRotationCoordinator(device: AVCaptureDevice) {
        rotationObservation?.invalidate()
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)
        rotationCoordinator = coordinator
        applyRotation()
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyRotation() }
        }
    }

    private func applyRotation() {
        guard let coordinator = rotationCoordinator,
              let connection = videoPreviewLayer.connection else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false // 先关自动再手动设镜像（否则抛异常）
            connection.isVideoMirrored = true
        }
        let angle = coordinator.videoRotationAngleForHorizonLevelPreview
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    // 旋转/布局变化时预览层 frame 可能滞留旧值（曾致画面铺满全屏），这里强制跟随
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true) // 禁隐式动画，避免旋转时画面"飞"一下
        videoPreviewLayer.frame = bounds
        CATransaction.commit()
    }
}
