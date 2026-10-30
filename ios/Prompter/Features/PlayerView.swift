import SwiftUI

/// 播放页（M3 占位：仅保证列表往返导航；滚动引擎在 M3 实现）
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let script: Script

    @State private var isPlaying = false

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()
            ScrollView {
                Text(script.content)
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 48)
                    .padding(.vertical, 160)
            }
            // 顶栏占位（M3 换双胶囊）
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 34, height: 34)
                            .background(Color.surface.opacity(0.7), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("M3 滚动引擎施工中")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer()
            }
            // 中央播放提示（穿透不拦截）
            if !isPlaying {
                VStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 72, height: 72)
                        .background(Color.black.opacity(0.35), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
                    Text("点击屏幕任意位置播放")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isPlaying.toggle() }
        .statusBarHidden()
    }
}

#if DEBUG
#Preview {
    PlayerView(script: Script(title: "预览稿件", content: "广发证券新客开户福利来了！从现在起，新客来开户，可立享专属 VIP 优惠佣金、沪深 Level-2 十档行情、超 30 款智能投资工具等多重新客福利。"))
}
#endif
