import SwiftUI

/// 双胶囊控件体系（播放页顶栏），对应 Web 版 CapsuleButton.tsx：
/// 胶囊壳与每个内格均至少 44pt，图标 18pt，保留原来的分隔线。
/// 底色与卡片同族（surface 实底 + 1pt 白 7% 描边），不用毛玻璃。
struct CapsuleBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 5)
        .frame(height: CTL.t1)
        .background(Color.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(Capsule())
    }
}

struct CapsuleDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 5)
            .accessibilityHidden(true)
    }
}

/// Keep the 44pt hit target; active state is conveyed by the icon without a second background.
struct CapsuleButton: View {
    let icon: String
    let label: String
    var active = false
    let action: () -> Void

    private static let green400 = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255)

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(active ? Self.green400 : Color.white.opacity(0.65))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}
