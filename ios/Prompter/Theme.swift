import SwiftUI

// 设计 Token —— 与 Web 版 index.css 一一对应
extension Color {
    static let canvas = Color(red: 10 / 255, green: 10 / 255, blue: 11 / 255) // #0A0A0B
    static let surface = Color(red: 19 / 255, green: 19 / 255, blue: 22 / 255) // #131316
    static let accentGold = Color(red: 212 / 255, green: 164 / 255, blue: 50 / 255) // #D4A432
    static let dangerRed = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255) // #DC2626
    static let successGreen = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255) // #22C55E
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
