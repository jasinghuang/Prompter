import SwiftUI
import AVFoundation

/// 前置化妆镜（复刻 Web CameraMirror）：打开才取流，关闭立即停会话释放设备（指示灯灭）；
/// 纯本地预览不录制不上传，水平镜像；加载/错误态文案与 Web 一致。
struct CameraMirrorView: View {
    @Binding var open: Bool
    @State private var status: Status = .loading

    private enum Status: Equatable {
        case loading, ready, failed(String)
    }

    private let session = AVCaptureSession()
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

    // MARK: 镜面卡片（Web: rounded-[22px] 白10% 描边 surface 底）

    private var mirrorCard: some View {
        ZStack {
            MirrorPreview(session: session)
                .opacity(status == .ready ? 1 : 0)
            if status != .ready { statusOverlay }
            closeButton
        }
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
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

/// 前置预览层（水平镜像，铺满裁剪——对应 Web -scale-x-100 object-cover）
private struct MirrorPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async {
            if let connection = view.videoPreviewLayer.connection, connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
