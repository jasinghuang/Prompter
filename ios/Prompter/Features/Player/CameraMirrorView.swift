import SwiftUI
import AVFoundation

/// 前置化妆镜（复刻 Web CameraMirror）：打开才取流，关闭立即停会话释放设备（指示灯灭）；
/// 纯本地预览不录制不上传，水平镜像；加载/错误态文案与 Web 一致。
/// session 必须 @State 持有——view struct 每次重渲染会重建，普通 let 会产生多个
/// 并发会话导致二次打开闪退。
struct CameraMirrorView: View {
    @Binding var open: Bool
    @State private var status: Status = .loading
    @State private var session = AVCaptureSession()

    private enum Status: Equatable {
        case loading, ready, failed(String)
    }

    private let queue = DispatchQueue(label: "prompter.camera")

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { open = false }
                mirrorCard
                    .frame(height: geo.size.height * (landscape ? 0.75 : 0.72))
                    .aspectRatio(landscape ? 16.0 / 10.0 : 1, contentMode: .fit)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    // MARK: 镜面卡片（Web: rounded-[22px] 白10% 描边 surface 底 + 高光渐变描边提升质感）

    private var mirrorCard: some View {
        ZStack {
            MirrorPreview(session: session)
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
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.5))
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
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.45), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("mirror.close")
            }
            Spacer()
        }
        .padding(10)
    }

    // MARK: 摄像会话

    private func start() {
        status = .loading
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            status = .failed("摄像头权限被拒绝，可在系统设置中允许后重试")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { configure() } else {
                        status = .failed("摄像头权限被拒绝，可在系统设置中允许后重试")
                    }
                }
            }
        default:
            configure()
        }
    }

    private func configure() {
        queue.async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                DispatchQueue.main.async { status = .failed("未检测到可用的摄像头") }
                return
            }
            guard let input = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async { status = .failed("摄像头暂时不可用（可能被其他应用占用）") }
                return
            }
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.sessionPreset = .hd1280x720
            if session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            session.startRunning()
            DispatchQueue.main.async { status = .ready }
        }
    }

    private func stop() {
        queue.async {
            if session.isRunning { session.stopRunning() }
            session.inputs.forEach(session.removeInput) // 立即释放设备
        }
    }
}

/// 前置预览层（水平镜像，铺满裁剪——对应 Web -scale-x-100 object-cover）。
/// 方向交给 AVCaptureDevice.RotationCoordinator（iOS 17 官方 API）：
/// 它监听设备姿态、始终给出地平线水平的预览角——手动映射界面方向在
/// 「镜像 + 左右横屏」叠加下会差 180°，浏览器(PWA)内部就是做的这件事所以没错。
private struct MirrorPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeCoordinator() -> RotationHolder { RotationHolder() }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        context.coordinator.attachIfNeeded(view: view, session: session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // 会话异步配置完成后 input 才存在——每次重渲染都尝试挂一次协调器
        context.coordinator.attachIfNeeded(view: uiView, session: session)
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: RotationHolder) {
        coordinator.teardown()
    }
}

/// 持有旋转协调器 + KVO：角度变化（含初始）即应用到连接，同时保持手动镜像
@MainActor
private final class RotationHolder {
    var coordinator: AVCaptureDevice.RotationCoordinator?
    var observation: NSKeyValueObservation?
    private var applied = false

    func attachIfNeeded(view: PreviewView, session: AVCaptureSession) {
        guard !applied,
              let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        applied = true
        let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: view.videoPreviewLayer)
        coordinator = rotation
        let apply: (AVCaptureDevice.RotationCoordinator) -> Void = { [weak view] coord in
            guard let view, let connection = view.videoPreviewLayer.connection else { return }
            // 必须先关自动镜像再手动设镜像，否则抛
            // "Cannot be set when automaticallyAdjustsVideoMirroring is YES" 异常（真机卡死根因）
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            let angle = coord.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
        apply(rotation) // 初始角度
        observation = rotation.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { coord, _ in
            DispatchQueue.main.async { apply(coord) }
        }
    }

    func teardown() {
        observation?.invalidate()
        observation = nil
        coordinator = nil
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
