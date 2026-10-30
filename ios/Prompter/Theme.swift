import SwiftUI

// 设计 Token —— 与 Web 版 index.css 一一对应
// （挂在 ShapeStyle where Self == Color 上，foregroundStyle(.accentGold) 等快捷写法才可用）
extension ShapeStyle where Self == Color {
    static var canvas: Color { Color(red: 10 / 255, green: 10 / 255, blue: 11 / 255) } // #0A0A0B
    static var surface: Color { Color(red: 19 / 255, green: 19 / 255, blue: 22 / 255) } // #131316
    static var accentGold: Color { Color(red: 212 / 255, green: 164 / 255, blue: 50 / 255) } // #D4A432
    static var dangerRed: Color { Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255) } // #DC2626
    static var successGreen: Color { Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255) } // #22C55E
    static var textPrimary: Color { Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255) } // #F5F5F5
    static var textSecondary: Color { Color(red: 161 / 255, green: 161 / 255, blue: 170 / 255) } // #A1A1AA
    static var textMuted: Color { Color(red: 113 / 255, green: 113 / 255, blue: 122 / 255) } // #71717A
}

/// 控件层级阶梯（T1 主操作 44 / T2 导航 40 / T3 工具 32 / T4 元信息 12pt 文字）
enum CTL {
    static let t1: CGFloat = 44
    static let t2: CGFloat = 40
    static let t3: CGFloat = 32
}

/// 卡片按压缩放反馈（对应 Web 的 active:scale-[0.98]）
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// 通用按压缩放反馈（对应 Web 的 active:scale-95，小控件用）
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// 卡片删除退场（复刻 Web 版 card-exit：左移 32pt + 缩至 0.96 + 淡出「浮走」，
/// 其余卡片的补位由容器动画承担，对应 Web 的 FLIP）
private struct CardExitModifier: ViewModifier {
    let exiting: Bool
    func body(content: Content) -> some View {
        content
            .opacity(exiting ? 0 : 1)
            .scaleEffect(exiting ? 0.96 : 1)
            .offset(x: exiting ? -32 : 0)
    }
}

extension AnyTransition {
    static var cardExit: AnyTransition {
        .modifier(
            active: CardExitModifier(exiting: true),
            identity: CardExitModifier(exiting: false)
        )
    }
}
