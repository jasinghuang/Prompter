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

/// Timings describe UI feedback only. Never apply these to reader motion or list updates.
enum AppMotion {
    static let press = Animation.easeOut(duration: 0.15)
    static let playback = Animation.easeOut(duration: 0.2)
    static let noticeIn = Animation.easeOut(duration: 0.18)
    static let noticeOut = Animation.easeOut(duration: 0.16)
    static let detail = Animation.easeOut(duration: 0.14)
    static let sensorTracking = Animation.linear(duration: 0.1)
    static let drawer = Animation.easeOut(duration: 0.22)
    static let drawerReturn = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let overlay = Animation.easeOut(duration: 0.2)
    static let fieldReveal = Animation.easeOut(duration: 0.16)
}

/// Mount fields immediately for focus/layout. Only their appearance fades after the first frame.
/// Removal stays immediate so a hidden field never keeps accepting input.
struct LocalReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content.animation(reduceMotion ? nil : AppMotion.fieldReveal) { $0.opacity(revealed ? 1 : 0) }
        }
        .task(id: reduceMotion) {
            if !reduceMotion && !revealed {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
            revealed = true
        }
    }
}

struct PressFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressed: Bool
    var enabled = true
    var scale: CGFloat = 0.98
    var disabledOpacity: Double = 0.35

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : AppMotion.press) { label in
            label
                .opacity(!enabled ? disabledOpacity : pressed ? 0.82 : 1)
                .scaleEffect(pressed && !reduceMotion ? scale : 1)
        }
    }
}

/// Keeps an outgoing tool visible until its fade ends, without animating its layout.
/// The task is cancelled on a new request, so a quick re-entry cannot be removed by an old exit.
struct ActionBarPresence<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visible: Bool
    @ViewBuilder var content: () -> Content
    @State private var presented = false
    @State private var revealed = false

    private struct Request: Equatable {
        var visible: Bool
        var reduceMotion: Bool
    }

    var body: some View {
        // A concrete zero-height container owns the task even while content is absent.
        VStack(spacing: 0) {
            if presented {
                content()
                    .animation(reduceMotion ? nil : revealed ? AppMotion.noticeIn : AppMotion.noticeOut) {
                        $0.opacity(revealed ? 1 : 0)
                    }
                    .allowsHitTesting(visible)
                    .accessibilityHidden(!visible)
            }
        }
        .task(id: Request(visible: visible, reduceMotion: reduceMotion)) {
            if reduceMotion {
                presented = visible; revealed = visible
            } else if visible {
                presented = true
                // Mount at zero opacity before revealing; no operation waits for this frame.
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                revealed = true
            } else {
                revealed = false
                do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
                presented = false
            }
        }
    }
}

struct PressableStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var scale: CGFloat = 0.98
    var disabledOpacity: Double = 0.35
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.role == .destructive ? Color.dangerRed : Color.accentGold)
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            .modifier(PressFeedback(pressed: configuration.isPressed, enabled: enabled,
                                    scale: scale, disabledOpacity: disabledOpacity))
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
