import SwiftUI

/// 双胶囊控件体系（播放页顶栏），对应 Web 版 CapsuleButton.tsx：
/// 胶囊壳 44pt 触控行（T1 层级）、内格 34pt、图标 18pt、分隔 1×16pt。
/// 底色与卡片同族（surface 72% + 1pt 白 7% 描边），不用毛玻璃。
struct CapsuleBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, 5)
        .frame(height: CTL.t1)
        .background(Color.surface.opacity(0.72), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
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

/// 胶囊内格按钮：幽灵样式；active（如已拍摄）= 绿 16% 衬底 + 绿色图标
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
                .padding(.horizontal, 11)
                .frame(minWidth: 34)
                .frame(height: 34)
                .background(active ? Color.successGreen.opacity(0.16) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}
