import SwiftUI

/// 播放页设置抽屉（对应 Web 版 SettingsPanel）：右侧滑入 320pt，
/// 遮罩透明不模糊——调参数时正文可实时预览。横屏下系统 sheet 会全屏，故用自绘抽屉。
struct PlayerSettingsDrawer: View {
    @Binding var open: Bool
    @EnvironmentObject private var settings: AppSettings
    @State private var pauseMode: EditorView.PauseMode = .off

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                if open {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { open = false }
                        .transition(.opacity)
                    panel(width: min(320, geo.size.width * 0.85))
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.25), value: open)
        .allowsHitTesting(open)
        .onAppear { pauseMode = EditorView.derivePauseMode(settings.data) }
        .onChange(of: pauseMode) { _, mode in
            settings.data.pauseOnParagraph = mode == .paragraph
            if mode != .keyword { settings.data.pauseKeyword = "" }
        }
    }

    // MARK: 面板

    private func panel(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    SettingSlider(icon: "textformat.size", label: "字号",
                                  value: Double(settings.data.fontSize),
                                  range: Double(PrompterCore.fontSizeMin)...Double(PrompterCore.fontSizeMax),
                                  step: 2, suffix: "px") { settings.data.fontSize = Int($0) }
                    SettingSlider(icon: "arrow.left.and.right", label: "字间距",
                                  value: settings.data.letterSpacing,
                                  range: PrompterCore.letterSpacingMin...PrompterCore.letterSpacingMax,
                                  step: 0.01, suffix: "em", fractionDigits: 2) { settings.data.letterSpacing = $0 }
                    SettingSlider(icon: "text.justify", label: "行距",
                                  value: settings.data.lineHeight,
                                  range: PrompterCore.lineHeightMin...PrompterCore.lineHeightMax,
                                  step: 0.1, fractionDigits: 1) { settings.data.lineHeight = $0 }
                    SettingSlider(icon: "arrow.left.and.right.square", label: "两边间距",
                                  value: Double(settings.data.horizontalPadding),
                                  range: Double(PrompterCore.paddingMin)...Double(PrompterCore.paddingMax),
                                  step: 1, suffix: "%") { settings.data.horizontalPadding = Int($0) }
                    SettingSlider(icon: "speedometer", label: "滚动速度",
                                  value: Double(settings.data.scrollSpeed),
                                  range: Double(PrompterCore.speedMin)...Double(PrompterCore.speedMax),
                                  step: 10, suffix: " 字/分") { settings.data.scrollSpeed = Int($0) }
                    alignmentRow
                    mirrorRow
                    completeActionRow
                    autoPauseRow
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Color.surface.opacity(0.96).ignoresSafeArea()) // 近实底：正文已模糊，不再透字
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1).ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
                Text("设置")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                open = false
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: CTL.t1, height: CTL.t1)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("关闭设置")
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    // MARK: 对齐方式

    private var alignmentRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(icon: "text.alignleft", "对齐方式")
            HStack(spacing: 8) {
                alignButton("left", icon: "text.alignleft", label: "左对齐")
                alignButton("center", icon: "text.aligncenter", label: "居中对齐")
                alignButton("right", icon: "text.alignright", label: "右对齐")
            }
        }
    }

    private func alignButton(_ value: String, icon: String, label: String) -> some View {
        let active = settings.data.textAlign == value
        return Button {
            settings.data.textAlign = value
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(active ? Color.accentGold : Color.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    active ? Color.accentGold.opacity(0.15) : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    // MARK: 镜像

    private var mirrorRow: some View {
        Toggle(isOn: $settings.data.mirror) {
            sectionLabel(icon: "flip.horizontal", "镜像翻转")
        }
        .tint(.accentGold)
        .padding(.top, 20)
        .overlay(alignment: .top) { hairline }
    }

    // MARK: 读完动作

    private var completeActionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(icon: "flag", "读完动作")
            Picker("", selection: $settings.data.completeAction) {
                Text("不开启").tag("none")
                Text("返回列表").tag("list")
                Text("回到开头").tag("restart")
            }
            .pickerStyle(.segmented)
            .frame(height: 32)
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { hairline }
    }

    // MARK: 自动暂停

    private var autoPauseRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(icon: "pause.circle", "自动暂停")
            Picker("", selection: $pauseMode) {
                ForEach(EditorView.PauseMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(height: 32)
            // 关键词框常驻：未选关键词时灰色，位置大小不变（与编辑页一致）
            TextField("输入关键词", text: $settings.data.pauseKeyword)
                .font(.system(size: 14))
                .foregroundStyle(pauseMode == .keyword ? .white : .white.opacity(0.3))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    Color.white.opacity(pauseMode == .keyword ? 0.05 : 0.03),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(pauseMode == .keyword ? 0.08 : 0.03))
                )
                .autocorrectionDisabled()
                .disabled(pauseMode != .keyword)
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { hairline }
    }

    // MARK: 零件

    private func sectionLabel(icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.3))
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var hairline: some View {
        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
    }
}

/// 设置滑杆：标签行（图标 + 名称 | 等宽数值）+ 控件行（− 滑杆 +）
struct SettingSlider: View {
    let icon: String
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    var suffix = ""
    var fractionDigits = 0
    let onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(formatted + suffix)
                    .font(.system(size: 14, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            HStack(spacing: 8) {
                stepButton("minus", label: "减小\(label)") { commit(value - step) }
                Slider(
                    value: Binding(get: { value }, set: { commit($0) }),
                    in: range,
                    step: step
                )
                .tint(.accentGold)
                stepButton("plus", label: "增大\(label)") { commit(value + step) }
            }
        }
    }

    private var formatted: String {
        String(format: "%.\(fractionDigits)f", value)
    }

    /// 按步进取整并夹在范围内（浮点步进如 0.01 需要二次取整去尾差）
    private func commit(_ raw: Double) -> Void {
        let snapped = (raw / step).rounded() * step
        let fixed = (snapped * pow(10, Double(fractionDigits))).rounded() / pow(10, Double(fractionDigits))
        onChange(min(range.upperBound, max(range.lowerBound, fixed)))
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}
