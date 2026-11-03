import SwiftUI

/// Portrait uses a system sheet; landscape keeps the original dark side panel.
/// Only the dedicated handle owns the dismissal drag, leaving sliders and scrolling alone.
struct PlayerSettingsDrawer: View {
    @Binding var open: Bool
    @ObservedObject var nodController: AirPodsNodController
    @EnvironmentObject private var settings: AppSettings
    var onShowHelp: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @GestureState private var dragging = false
    @State private var pendingHelp = false
    @FocusState private var keywordFocused: Bool

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                let width = min(340, geo.size.width * 0.85)
                ZStack(alignment: .trailing) {
                    if open {
                        Color.black.opacity(0.35 * (1 - min(1, dragOffset / width))).ignoresSafeArea()
                            .onTapGesture { open = false }.transition(.opacity)
                        panel(width: width, showsHandle: true)
                            .overlay(alignment: .leading) {
                                Color.clear.contentShape(Rectangle()).frame(width: 28)
                                    .gesture(dismissDrag(panelWidth: width))
                                    .accessibilityHidden(true)
                            }
                            .offset(x: max(0, dragOffset))
                            .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : AppMotion.drawer, value: open)
                .allowsHitTesting(open)
            } else {
                Color.clear.sheet(isPresented: $open, onDismiss: showPendingHelp) {
                    panel(width: nil, showsHandle: false)
                        .presentationDetents([.fraction(0.75), .large])
                        .presentationDragIndicator(.visible).presentationBackground(Color.surface)
                }
            }
        }
        .coordinateSpace(name: "settings.drawerInteraction")
        .onChange(of: open, initial: true) { _, open in
            if open {
                pendingHelp = false
                resetDragImmediately()
            } else { keywordFocused = false }
        }
        .onChange(of: dragging) { _, dragging in
            // Also handles a system-cancelled drag, which does not deliver onEnded.
            if !dragging && open { returnDrag() }
        }
        .onChange(of: settings.data.automaticPause) { _, mode in
            if mode != .keyword { keywordFocused = false }
        }
        .onDisappear {
            pendingHelp = false
            resetDragImmediately()
        }
    }

    /// 从左往右拨：横向为主的拖动才接管（竖向留给滚动）；
    /// Gesture state detects cancellation; the offset itself follows the finger without animation.
    private func dismissDrag(panelWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("settings.drawerInteraction"))
            .updating($dragging) { _, state, transaction in
                transaction.animation = nil
                state = true
            }
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { dragOffset = max(0, value.translation.width) }
            }
            .onEnded { value in
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                let final = horizontal ? max(0, value.translation.width) : 0
                let dismiss = horizontal && (final > panelWidth * 0.3
                    || value.predictedEndTranslation.width > panelWidth * 0.6)
                if dismiss {
                    open = false
                } else {
                    returnDrag()
                }
            }
    }

    private func returnDrag() {
        withAnimation(reduceMotion ? nil : AppMotion.drawerReturn) { dragOffset = 0 }
    }

    private func resetDragImmediately() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { dragOffset = 0 }
    }

    private func requestHelp(sidePanel: Bool) {
        pendingHelp = true
        if sidePanel {
            withAnimation(reduceMotion ? nil : AppMotion.drawer, completionCriteria: .removed) {
                open = false
            } completion: {
                showPendingHelp()
            }
        } else {
            // Native sheet dismissal owns its completion, rather than a guessed sleep duration.
            open = false
        }
    }

    private func showPendingHelp() {
        guard pendingHelp && !open else { return }
        pendingHelp = false
        onShowHelp()
    }

    // MARK: 面板

    private func panel(width: CGFloat?, showsHandle: Bool) -> some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    SettingSlider(icon: "textformat.size", label: "字号",
                                  value: Double(settings.data.fontSize),
                                  range: Double(PrompterCore.fontSizeMin)...Double(PrompterCore.fontSizeMax),
                                  step: 2, suffix: " pt") { settings.data.fontSize = Int($0) }
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
                    AirPodsNodSettings(controller: nodController)
                    alignmentRow
                    mirrorRow
                    autoPauseRow
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel(icon: "checkmark.circle", "读完以后")
                        Picker("读完以后", selection: $settings.data.completion) {
                            Text("停在末尾").tag(CompletionAction.none)
                            Text("回到开头").tag(CompletionAction.restart)
                            Text("标记并返回").tag(CompletionAction.list)
                        }.pickerStyle(.segmented).frame(minHeight: 44)
                            .accessibilityIdentifier("settings.completion")
                        if settings.data.completion == .list {
                            Text("读完后标记为已拍摄，并返回稿件列表。")
                                .font(.caption).foregroundStyle(.textSecondary)
                        }
                    }
                    Button { requestHelp(sidePanel: showsHandle) } label: { Label("查看操作提示", systemImage: "questionmark.circle").frame(minHeight: 44) }
                        .accessibilityIdentifier("settings.help")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }.accessibilityIdentifier("settings.scroll")
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Color.surface.ignoresSafeArea()) // 实底保证控制面板可读，正文保留实时排版预览
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1).ignoresSafeArea()
        }
        // 左缘竖向指示条（规范同编辑/文件夹弹窗：5pt 粗、60pt 长、距边缘 10pt）
        .overlay(alignment: .leading) {
            if showsHandle {
                Capsule().fill(Color.textSecondary).frame(width: 5, height: 60)
                    .padding(.leading, 10).accessibilityHidden(true)
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.textSecondary)
                Text("设置")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                open = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.textSecondary)
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
                .foregroundStyle(active ? Color.accentGold : Color.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(
                    active ? Color.accentGold.opacity(0.15) : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label).accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: 镜像

    private var mirrorRow: some View {
        Toggle(isOn: $settings.data.mirror) {
            sectionLabel(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", "镜像翻转")
        }
        .tint(.accentGold)
        .padding(.top, 20)
        .overlay(alignment: .top) { hairline }
    }

    // MARK: 自动暂停

    private var autoPauseRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(icon: "pause.circle", "自动暂停")
            Picker("", selection: $settings.data.automaticPause) {
                ForEach(AutoPauseMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(height: 32)
            if settings.data.automaticPause == .keyword {
                TextField("输入关键词", text: $settings.data.pauseKeyword)
                    .font(.body).foregroundStyle(.textPrimary).padding(12)
                    .background(Color.canvas, in: RoundedRectangle(cornerRadius: 10))
                    .autocorrectionDisabled()
                    .focused($keywordFocused)
                    .accessibilityIdentifier("settings.pauseKeyword")
                    .modifier(LocalReveal())
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { hairline }
    }

    // MARK: 零件

    private func sectionLabel(icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
            Text(text)
                .font(.subheadline.weight(.semibold))
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
                        .foregroundStyle(Color.textSecondary)
                    Text(label)
                        .font(.subheadline.weight(.semibold))
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
                Slider(value: sliderValue, in: range, step: step)
                    .tint(.accentGold)
                    .accessibilityIdentifier("slider.\(label)").accessibilityLabel(label)
                stepButton("plus", label: "增大\(label)") { commit(value + step) }
            }
        }
    }

    private var formatted: String {
        String(format: "%.\(fractionDigits)f", value)
    }

    private var sliderValue: Binding<Double> {
        Binding(get: { value }, set: { commit($0) })
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
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}
