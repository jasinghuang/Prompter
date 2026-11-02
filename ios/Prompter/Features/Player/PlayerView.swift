import SwiftUI
import SwiftData

/// Black/gold controls appear while paused; tapping the text toggles playback.
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var operations = ScriptOperations()
    @StateObject private var nodController = AirPodsNodController()
    @EnvironmentObject private var settings: AppSettings
    let script: Script

    private static let onboardKey = "prompter_onboarded"

    @State private var engine = ScrollEngineController()
    @State private var isPlaying = false
    @State private var activeIndex = 0
    @State private var showReturnHint = false
    @State private var elapsed = 0
    @State private var paragraphStarts: Set<Int> = []
    @State private var keywordTracker = KeywordPauseTracker()
    @State private var paragraphTracker = ParagraphPauseTracker()

    @State private var showSettings = false
    @State private var showMirror = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: PlayerView.onboardKey)
    @State private var completed = false
    @State private var toast: Toast?
    @State private var toastTask: Task<Void, Never>?
    @State private var returnTask: Task<Void, Never>?

    struct Toast: Equatable {
        var text: String
        var color: Color
    }

    private var typography: PrompterScrollView.Typography {
        .init(
            content: script.content,
            fontSize: settings.data.fontSize,
            letterSpacing: settings.data.letterSpacing,
            lineHeight: settings.data.lineHeight,
            horizontalPadding: settings.data.horizontalPadding,
            textAlign: settings.data.textAlign
        )
    }

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()
            reader
            guideLines
            topBar
            if !isPlaying { bottomControls }
            toastView
            onboarding
            PlayerSettingsDrawer(open: $showSettings, nodController: nodController) {
                showSettings = false; showOnboarding = true
            }
            // 前置化妆镜（最顶层；打开才取流，关闭即释放）
            if showMirror {
                CameraMirrorView(open: $showMirror)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showMirror)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true // 拍摄中屏幕常亮
            paragraphStarts = PrompterCore.paragraphStarts(script.content)
            #if DEBUG
            // 自动化截图验证用：-skipOnboard 跳过引导 / -autoPlay 直接播放 / -openSettings 打开设置抽屉
            // -pauseParagraph=段落暂停+高速；-fastEnd=仅高速（验证读完提示和点击时间回顶）
            let args = ProcessInfo.processInfo.arguments
            let testRun = args.contains("-pauseParagraph") || args.contains("-fastEnd")
            if args.contains("-skipOnboard") || testRun { showOnboarding = false }
            if args.contains("-autoPlay") || testRun { isPlaying = true }
            if args.contains("-openSettings") { showSettings = true }
            if testRun {
                UserDefaults.standard.set(true, forKey: "debug_player_test_ran")
                settings.data.scrollSpeed = 700
                if args.contains("-pauseParagraph") { settings.data.automaticPause = .paragraph }
            } else if UserDefaults.standard.bool(forKey: "debug_player_test_ran") {
                // 上次是验证运行，还原设置
                settings.data.automaticPause = .off
                settings.data.scrollSpeed = SettingsData.defaults.scrollSpeed
                UserDefaults.standard.set(false, forKey: "debug_player_test_ran")
            }
            #endif
        }
        .onDisappear {
            nodController.shutdown()
            UIApplication.shared.isIdleTimerDisabled = false
            toastTask?.cancel(); returnTask?.cancel(); settings.flush()
        }
        .onChange(of: script.content) { _, content in
            paragraphStarts = PrompterCore.paragraphStarts(content)
            keywordTracker.reset(); paragraphTracker.reset(); cancelCompletionReturn()
        }
        .onChange(of: activeIndex) { _, _ in checkAutoPause() }
        .onChange(of: isPlaying) { _, playing in
            if playing { checkAutoPause() }
        }
        .onChange(of: settings.data.pauseKeyword) { _, _ in keywordTracker.reset() }
        .onChange(of: settings.data.automaticPause) { _, _ in keywordTracker.reset(); paragraphTracker.reset() }
        .onChange(of: showSettings) { _, open in if open { isPlaying = false; cancelCompletionReturn() } }
        .onChange(of: showMirror) { _, open in if open { isPlaying = false; cancelCompletionReturn() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { nodController.interruptCalibration() }
            if phase != .active { isPlaying = false; settings.flush() }
            if phase == .background { showMirror = false }
            UIApplication.shared.isIdleTimerDisabled = phase == .active
        }
        .task(id: isPlaying) { await runTimer() }
        .task(id: nodConfiguration) {
            nodController.configure(profile: nodConfiguration.profile, suspended: nodConfiguration.suspended)
        }
        .onReceive(nodController.nods) { trigger in
            guard settings.data.airPodsNodEnabled, !nodConfiguration.suspended else { nodController.discardNod(trigger); return }
            applyPlaybackToggle()
            nodController.confirmNodApplied(trigger, playing: isPlaying)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onReceive(nodController.notices) { message in
            guard settings.data.airPodsNodEnabled, !nodConfiguration.suspended else { return }
            showToast(message)
        }
        .alert("操作未完成", isPresented: Binding(get: { operations.errorMessage != nil }, set: { if !$0 { operations.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { operations.errorMessage = nil }
        } message: { Text(operations.errorMessage ?? "") }
    }

    // MARK: 正文

    private struct NodConfiguration: Equatable {
        var profile: HeadGestureCalibration?
        var suspended: Bool
    }
    private var nodConfiguration: NodConfiguration {
        .init(profile: settings.data.airPodsNodEnabled ? settings.data.headGestureCalibration : nil,
              suspended: scenePhase != .active || showSettings || showMirror || showOnboarding)
    }

    private var reader: some View {
        PrompterScrollView(
            typography: typography,
            isPlaying: isPlaying,
            wordsPerMinute: settings.data.scrollSpeed,
            mirror: settings.data.mirror,
            controller: engine,
            onActiveIndex: { activeIndex = $0 },
            onReachEnd: handleReachEnd,
            onAtBottom: { if !$0 { showReturnHint = false } },
            onTap: togglePlayback,
            onPinch: { size in
                settings.data.fontSize = size
                showToast("字号 \(size) pt", duration: nil)
            },
            onPinchEnd: { size in showToast("字号 \(size) pt", duration: 0.6) },
            onEdgeBack: { dismiss() }, // 左缘右滑返回列表，对齐系统返回手势
            onUserDragPause: {
                nodController.rearm()
                if isPlaying { isPlaying = false } // 播放中拖动正文=回看，自动暂停并停表
            }
        )
        .scaleEffect(x: settings.data.mirror ? -1 : 1, y: 1)
        .ignoresSafeArea()
        .accessibilityAction(named: isPlaying ? "暂停提词" : "开始提词", togglePlayback)

    }

    // MARK: 顶栏——双胶囊（左：导航/状态，右：操作，播放中自动隐藏）

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CapsuleBar {
                    CapsuleButton(icon: "chevron.left", label: "返回") { dismiss() }
                    CapsuleDivider()
                    Button(action: returnToTop) {
                        HStack(spacing: 7) {
                            Image(systemName: isPlaying ? "play.fill" : "pause.fill")
                                .font(.system(size: 10)).foregroundStyle(isPlaying ? Color.accentGold : .textSecondary)
                            Text(PrompterCore.formatTime(elapsed))
                                .font(.system(.caption, design: .monospaced)).monospacedDigit()
                                .foregroundStyle(.textSecondary).fixedSize()
                                .accessibilityIdentifier("player.elapsed")
                        }.padding(.horizontal, 8).frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(PressableStyle())
                        .accessibilityIdentifier("player.returnToTop")
                        .accessibilityLabel("回到顶部")
                        .accessibilityValue("\(isPlaying ? "提词中" : "已暂停")，\(PrompterCore.formatTime(elapsed))")
                        .accessibilityHint("回到正文开头，暂停并将计时归零")
                    CapsuleDivider()
                    CapsuleButton(icon: "camera", label: "前置镜子") { isPlaying = false; showMirror = true }
                        .accessibilityIdentifier("player.mirror")
                }
                Spacer(minLength: 0)
                CapsuleBar {
                    CapsuleButton(icon: script.isFilmed ? "checkmark.circle.fill" : "checkmark.circle",
                                  label: script.isFilmed ? "取消已拍摄标记" : "标记为已拍摄",
                                  active: script.isFilmed, action: toggleFilmed)
                        .accessibilityIdentifier("player.filmed")
                        .accessibilityValue(script.isFilmed ? "已拍摄" : "待拍摄")
                    CapsuleDivider()
                    CapsuleButton(icon: "slider.horizontal.3", label: "设置") { isPlaying = false; showSettings = true }
                        .accessibilityIdentifier("player.settings")
                }
                .opacity(isPlaying ? 0 : 1).allowsHitTesting(!isPlaying)
                .accessibilityHidden(isPlaying)
            }
            if showReturnHint && !isPlaying {
                Text("已读完，点击时间回到顶部")
                    .font(.caption).foregroundStyle(.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.07)))
                    .accessibilityIdentifier("player.returnHint")
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            if settings.data.airPodsNodEnabled && !nodConfiguration.suspended && !isPlaying {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "airpodspro").foregroundStyle(Color.accentGold)
                    Text(nodController.status).foregroundStyle(.textSecondary)
                        .accessibilityIdentifier("player.nodStatus")
                }
                .font(.caption).padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: 280, alignment: .leading)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isPlaying)
        .padding(.horizontal, 16).padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: 阅读引导线（金色辉光竖条，左右各一）

    private var guideLines: some View {
        HStack {
            guideBar
            Spacer()
            guideBar
        }
        .padding(.horizontal, 12)
        .opacity(isPlaying ? 1 : 0) // 暂停时让位正文，播放时才亮起
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isPlaying)
        .allowsHitTesting(false)
    }

    private var guideBar: some View {
        Capsule()
            .fill(Color.accentGold)
            .frame(width: 4, height: 112)
            .shadow(color: Color.accentGold.opacity(0.55), radius: 6)
    }

    // MARK: 底部控件（字号 / 速度，播放中自动隐藏）

    private var bottomControls: some View {
        GeometryReader { geometry in
            // Outer margins and inner padding total 60pt; each label/value pair uses 84pt.
            // After both pairs and the 16pt gap, split the remaining track width 1:2.
            let available = max(0, geometry.size.width - 60)
            let horizontal = available >= 394
            let speedTrack = horizontal ? (available - 184) * 2 / 3 : max(70, available - 84)
            let fontTrack = horizontal ? speedTrack / 2 : speedTrack
            Group {
                if horizontal {
                    HStack(spacing: 16) { parameters(fontTrack: fontTrack, speedTrack: speedTrack) }
                } else {
                    VStack(alignment: .leading, spacing: 0) { parameters(fontTrack: fontTrack, speedTrack: speedTrack) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.1)))
            .padding(.horizontal, 16).padding(.bottom, 16)
            .background(Color.canvas.ignoresSafeArea(edges: .bottom))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder private func parameters(fontTrack: CGFloat, speedTrack: CGFloat) -> some View {
        ParamGroup(label: "字号", value: settings.data.fontSize,
            range: PrompterCore.fontSizeMin...PrompterCore.fontSizeMax, step: 2, trackWidth: fontTrack) { settings.data.fontSize = $0 }
        ParamGroup(label: "速度", value: settings.data.scrollSpeed,
            range: PrompterCore.speedMin...PrompterCore.speedMax, step: 1, trackWidth: speedTrack) { settings.data.scrollSpeed = $0 }
    }

    private func togglePlayback() {
        nodController.rearm()
        applyPlaybackToggle()
    }

    private func applyPlaybackToggle() {
        cancelCompletionReturn()
        if !isPlaying && engine.isAtTop { elapsed = 0 }
        isPlaying.toggle()
    }

    private func returnToTop() {
        nodController.rearm()
        isPlaying = false
        elapsed = 0
        cancelCompletionReturn()
        keywordTracker.reset(); paragraphTracker.reset()
        toastTask?.cancel(); toast = nil
        showReturnHint = false
        engine.scrollToIndex(0)
    }

    // MARK: 提示胶囊（暂停原因 / 捏合字号 / 读完）

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast.text)
                .font(.subheadline)
                .foregroundStyle(toast.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .padding(.bottom, 148)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityIdentifier("player.toast")
        }
    }

    // MARK: 首次操作提示：明确确认后关闭，可从设置再次查看

    @ViewBuilder
    private var onboarding: some View {
        if showOnboarding {
            ZStack {
                Color.canvas.opacity(0.8).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("提词器")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    VStack(spacing: 10) {
                        onboardLine("轻点屏幕", "开始 / 暂停")
                        onboardLine("拖动文本", "回看上文")
                        onboardLine("双指捏合", "调整字号")
                    }
                    Text("轻点正文开始，再点一下暂停")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 8)
                }
            }
            .overlay(alignment: .bottom) {
                Button("知道了") { dismissOnboarding() }
                    .buttonStyle(.borderedProminent).tint(.accentGold).foregroundStyle(.canvas)
                    .frame(minHeight: 44).padding(.bottom, 96)
            }
            .transition(.opacity)
        }
    }

    private func onboardLine(_ action: String, _ effect: String) -> some View {
        HStack(spacing: 4) {
            Text(action).foregroundStyle(Color.textSecondary)
            Text(effect).fontWeight(.medium).foregroundStyle(Color.textPrimary)
        }
        .font(.system(size: 14))
    }

    // MARK: 行为

    private func handleReachEnd() {
        guard !completed else { return }
        isPlaying = false
        switch settings.data.completion {
        case .restart:
            // 重读：自动暂停重新生效，回到开头并暂停，计时归零（新一条）
            returnToTop()
        case .list:
            if !script.isFilmed && !operations.update([script], in: context, change: { $0.isFilmed = true; $0.updatedAt = Date() }) { return }
            completed = true
            showToast("✓ 已读完·已标记拍摄", color: .successGreen, duration: 1.2)
            returnTask?.cancel()
            returnTask = Task {
                do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
                dismiss()
            }
        case .none:
            showReturnHint = true
        }
    }

    private func cancelCompletionReturn() {
        returnTask?.cancel(); returnTask = nil; completed = false
    }

    private func checkAutoPause() {
        guard isPlaying else { return }
        let keyword = settings.data.pauseKeyword
        if settings.data.automaticPause == .keyword, !keyword.isEmpty,
           keywordTracker.shouldPause(content: script.content, keyword: keyword, activeIndex: activeIndex) {
            isPlaying = false
            showToast("已暂停：命中关键词「\(keyword)」")
            return
        }
        if settings.data.automaticPause == .paragraph,
           paragraphTracker.shouldPause(paragraphStarts: paragraphStarts, activeIndex: activeIndex) {
            isPlaying = false
            showToast("已暂停：段落分隔")
        }
    }

    private func toggleFilmed() {
        operations.update([script], in: context) { $0.isFilmed.toggle(); $0.updatedAt = Date() }
        // 不再弹提示：按钮自身的绿色高亮即状态反馈
    }

    /// duration 为 nil 时常驻（捏合过程中），由后续调用接管关闭
    private func showToast(_ text: String, color: Color = .accentGold, duration: Double? = 3) {
        toastTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { toast = Toast(text: text, color: color) }
        guard let duration else { return }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { toast = nil }
        }
    }

    /// 墙钟计时：播放时每秒 +1，暂停停表不清零（与 Web 版 useTimer 一致）
    private func runTimer() async {
        guard isPlaying else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            elapsed += 1
        }
    }

    private func dismissOnboarding() {
        guard showOnboarding else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showOnboarding = false }
        UserDefaults.standard.set(true, forKey: Self.onboardKey)
    }
}

// MARK: - 底部参数组：暗淡标签 + 数值胶囊 + 滑杆

private struct ParamGroup: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let trackWidth: CGFloat
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 24, alignment: .leading)
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 48)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            Slider(
                value: Binding(get: { Double(value) }, set: { onChange(Int($0.rounded())) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .tint(.accentGold)
            .frame(width: trackWidth, height: CTL.t1)
            .accessibilityLabel(label)
            .accessibilityIdentifier("player.slider.\(label)")
        }
    }
}

#if DEBUG
#Preview {
    let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: Script.self, configurations: config)
    }()
    let script = Script(
        title: "预览稿件",
        content: "广发证券新客开户福利来了！从现在起，新客来开户，可立享专属 VIP 优惠佣金、沪深 Level-2 十档行情、超 30 款智能投资工具等多重新客福利。\n\n总有人问我，为什么我的交易更频繁了，但手续费却更省了？答案就是开户时选对了渠道。\n\n新客开户即享价值约 1688 元的新客福利包，名额有限，先到先得。"
    )
    container.mainContext.insert(script)
    return PlayerView(script: script)
        .modelContainer(container)
        .environmentObject(AppSettings())
}
#endif
