import SwiftUI

// The existing black/gold identity stays intact; surfaces and text have shared semantic roles.
extension ShapeStyle where Self == Color {
    static var canvas: Color { Color(red: 10 / 255, green: 10 / 255, blue: 11 / 255) }
    static var surface: Color { Color(red: 19 / 255, green: 19 / 255, blue: 22 / 255) }
    static var accentGold: Color { Color(red: 212 / 255, green: 164 / 255, blue: 50 / 255) }
    static var dangerRed: Color { Color(uiColor: .systemRed) }
    static var successGreen: Color { Color(uiColor: .systemGreen) }
    static var textPrimary: Color { Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255) }
    static var textSecondary: Color { Color(red: 177 / 255, green: 177 / 255, blue: 187 / 255) }
    static var textMuted: Color { Color(red: 147 / 255, green: 147 / 255, blue: 158 / 255) }
    static var cardSurface: Color { Color(red: 16 / 255, green: 16 / 255, blue: 19 / 255) }
}

enum CTL {
    static let t1: CGFloat = 44
    static let t2: CGFloat = 44
    static let t3: CGFloat = 44
    static let cardRadius: CGFloat = 16
}

struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.role == .destructive ? Color.dangerRed : Color.accentGold)
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            .opacity(!enabled ? 0.35 : configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SheetHeading: View {
    let title: String
    let close: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(.textPrimary)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.textSecondary)
                    .frame(width: CTL.t1, height: CTL.t1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("关闭\(title)")
        }
        .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 8)
    }
}
