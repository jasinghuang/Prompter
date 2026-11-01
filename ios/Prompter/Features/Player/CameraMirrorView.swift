import SwiftUI
import AVFoundation
import QuartzCore

/// 前置化妆镜（复刻 Web CameraMirror）：打开才取流，关闭立即停会话释放设备（指示灯灭）；
/// 纯本地预览不录制不上传，水平镜像；加载/错误态文案与 Web 一致。
///
/// 架构（教科书原生）：整个摄像头生命周期（会话/输入/预览层/启停）收在
/// MirrorCameraUIView 一个 UIView 里自持——SwiftUI 只嵌入与收状态回调，
/// 不再有跨对象的 @State 会话与异步配置时序（黑屏/多会话两类 bug 的根源）。
struct CameraMirrorView: View {
    @Binding var open: Bool
    @State private var status: Status = .loading
    @State private var retryID = UUID()
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
                    .onTapGesture { open = false }
                // 显式宽高（Web: 横屏 16:10·高 75%·最宽 80%；竖屏正方·高 72%）——
                // aspectRatio 对贪婪子视图的求值不可靠，曾致卡片横向失控
                let cardHeight = geo.size.height * (landscape ? 0.75 : 0.72)
                let cardWidth = min(geo.size.width * (landscape ? 0.80 : 0.92),
                                    cardHeight * (landscape ? 1.6 : 1.0))
                mirrorCard
                    .frame(width: cardWidth, height: cardHeight)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.98).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 镜面卡片（Web: rounded-[22px] surface 底 + 高光渐变描边）

    private var mirrorCard: some View {
        ZStack {
            MirrorCameraView(onStatus: { message in
                if let message {
                    status = .failed(message)
                } else {
                    status = .ready
                }
            })
            .id(retryID)
            .opacity(status == .ready ? 1 : 0)
            if status != .ready { statusOverlay }
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
                    Button("重试") { status = .loading; retryID = UUID() }
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
                    open = false
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
}

// MARK: - 自持摄像头的原生视图（会话/输入/预览层生命周期全在此，无跨对象时序）

/// nil = 就绪；非 nil = 错误文案
private struct MirrorCameraView: UIViewRepresentable {
    let onStatus: (String?) -> Void

    func makeUIView(context: Context) -> MirrorCameraUIView {
        let view = MirrorCameraUIView()
        view.onStatus = onStatus
        return view
    }

    func updateUIView(_ uiView: MirrorCameraUIView, context: Context) {
        uiView.onStatus = onStatus
    }

    static func dismantleUIView(_ uiView: MirrorCameraUIView, coordinator: ()) {
        uiView.stop() // 移除即释放设备（指示灯灭）
    }
}

final class MirrorCameraUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    var onStatus: ((String?) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "prompter.camera")
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var generation = 0
    private var requested = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        // 关键：预览层必须挂上会话才有画面（单视图重构时漏了这两行=黑屏根因）
        videoPreviewLayer.session = session
        videoPreviewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func start() {
        guard window != nil, !requested else { return }
        requested = true; generation += 1
        let expectedGeneration = generation
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            onStatus?("摄像头权限被拒绝，可在系统设置中允许后重试")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.window != nil, self.generation == expectedGeneration else { return }
                    granted ? self.configure(generation: expectedGeneration) : self.onStatus?("摄像头权限被拒绝，可在系统设置中允许后重试")
                }
            }
        default:
            configure(generation: expectedGeneration)
        }
    }

    private func configure(generation expectedGeneration: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                DispatchQueue.main.async {
                    guard self.window != nil, self.generation == expectedGeneration else { return }
                    self.onStatus?("未检测到可用的摄像头")
                }
                return
            }
            guard let input = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async {
                    guard self.window != nil, self.generation == expectedGeneration else { return }
                    self.onStatus?("摄像头暂时不可用（可能被其他应用占用）")
                }
                return
            }
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.sessionPreset = .hd1280x720
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                DispatchQueue.main.async {
                    guard self.window != nil, self.generation == expectedGeneration else { return }
                    self.onStatus?("摄像头暂时不可用，请稍后重试")
                }
                return
            }
            session.addInput(input)
            session.commitConfiguration()
            session.startRunning()
            DispatchQueue.main.async {
                guard self.window != nil, self.generation == expectedGeneration else { return }
                self.setupRotationCoordinator(device: device)
                self.onStatus?(nil) // 就绪
            }
        }
    }

    func stop() {
        requested = false; generation += 1
        rotationObservation?.invalidate()
        rotationObservation = nil
        rotationCoordinator = nil
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
            session.inputs.forEach(session.removeInput) // 立即释放设备
        }
    }

    // 真正挂上窗口才取流、离开窗口即释放（原生视图生命周期的标准触发点）
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            start()
        } else {
            stop()
        }
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
