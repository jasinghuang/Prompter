import SwiftUI
import SwiftData

/// 播放页（M3）：TextKit 2 滚动引擎 + 双胶囊顶栏 + 中央播放提示 + 引导线 + 底部字号/速度 + 设置抽屉
/// 交互与 Web 版 Teleprompter.tsx 一一对应：轻点开始/暂停、拖动回看、双指捏合调字号、播放中非必要控件自动隐藏
struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    let script: Script

    private static let onboardKey = "prompter_onboarded"

    @State private var engine = ScrollEngineController()
    @State private var isPlaying = false
    @State private var activeIndex = 0
    @State private var atBottom = false
    @State private var pointerDown = false // 手指按住屏幕（拖拽浏览）时隐藏中央提示
    @State private var elapsed = 0
    @State private var paragraphStarts: Set<Int> = []
    @State private var keywordTracker = KeywordPauseTracker()
    @State private var paragraphTracker = ParagraphPauseTracker()

    @State private var showSettings = false
    @State private var showMirror = false
    @State private var editing = false
    @State private var showBlur = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: PlayerView.onboardKey)
    @State private var completed = false
    @State private var toast: Toast?
    @State private var toastTask: Task<Void, Never>?
    @State private var hintPulse = false

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
            centerHint
            topBar
            bottomControls
            backToTop
            toastView
            onboarding
            // 弹窗打开时：透明遮罩拦截背景交互，点击空白即刻关弹窗+模糊（三层触发的第一层）
            if showBlur {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if editing { editing = false }
                        showBlur = false
                    }
                    .ignoresSafeArea()
            }
            PlayerSettingsDrawer(open: $showSettings)
            // 前置化妆镜（最顶层；打开才取流，关闭即释放）
            if showMirror {
                CameraMirrorView(open: $showMirror)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .blur(radius: showBlur ? 8 : 0)
        .animation(.easeOut(duration: 0.25), value: showBlur)
        .animation(.easeOut(duration: 0.22), value: showMirror)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true // 拍摄中屏幕常亮
            paragraphStarts = PrompterCore.paragraphStarts(script.content)
            #if DEBUG
            // 自动化截图验证用：-skipOnboard 跳过引导 / -autoPlay 直接播放 / -openSettings 打开设置抽屉
            // -pauseParagraph=段落暂停+高速（验证自动暂停）；-fastEnd=仅高速（快速滚到底验证回顶按钮）
            let args = ProcessInfo.processInfo.arguments
            let testRun = args.contains("-pauseParagraph") || args.contains("-fastEnd")
            if args.contains("-skipOnboard") || testRun { showOnboarding = false }
            if args.contains("-autoPlay") || testRun { isPlaying = true }
            if args.contains("-openSettings") { showSettings = true }
            if testRun {
                UserDefaults.standard.set(true, forKey: "debug_player_test_ran")
                settings.data.scrollSpeed = 700
                if args.contains("-pauseParagraph") { settings.data.pauseOnParagraph = true }
            } else if UserDefaults.standard.bool(forKey: "debug_player_test_ran") {
                // 上次是验证运行，还原设置
                settings.data.pauseOnParagraph = false
                settings.data.scrollSpeed = SettingsData.defaults.scrollSpeed
                UserDefaults.standard.set(false, forKey: "debug_player_test_ran")
            }
            #endif
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            toastTask?.cancel()
        }
        .onChange(of: script.content) { _, content in
            paragraphStarts = PrompterCore.paragraphStarts(content)
        }
        .onChange(of: activeIndex) { _, _ in checkAutoPause() }
        .onChange(of: isPlaying) { _, playing in
            if playing { checkAutoPause() }
        }
        .onChange(of: settings.data.pauseKeyword) { _, _ in keywordTracker.reset() }
        .onChange(of: editing) { _, value in
            if !value { showBlur = false }
        }
        .task(id: isPlaying) { await runTimer() }
        .sheet(isPresented: $editing) {
            EditorView(script: script)
                .presentationDetents([.fraction(0.80), .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color.canvas)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.80))) // 让空白点击直达遮罩层
                .onAppear { showBlur = true }
                .onDisappear {
                    showBlur = false
                    if script.isDeleted { dismiss() } // 编辑页做了智能拆分，原稿已不存在
                }
        }
    }

    // MARK: 正文

    private var reader: some View {
        PrompterScrollView(
            typography: typography,
            isPlaying: isPlaying,
            wordsPerMinute: settings.data.scrollSpeed,
            mirror: settings.data.mirror,
            controller: engine,
            onActiveIndex: { activeIndex = $0 },
            onReachEnd: handleReachEnd,
            onAtBottom: { atBottom = $0 },
            onPointerDown: { pointerDown = $0 },
            onTap: {
                if !isPlaying && engine.isAtTop {
                    elapsed = 0 // 从头开拍一条新计时；暂停续播不清零（与 Web 一致）
                }
                isPlaying.toggle()
            },
            onPinch: { size in
                settings.data.fontSize = size
                showToast("字号 \(size)px", duration: nil)
            },
            onPinchEnd: { size in showToast("字号 \(size)px", duration: 0.6) },
            onEdgeBack: { dismiss() } // 左缘右滑返回列表，对齐系统返回手势
        )
        .scaleEffect(x: settings.data.mirror ? -1 : 1, y: 1)
        .ignoresSafeArea()
        // 设置抽屉打开时正文做模糊处理，避免抽屉文字与脚本文案叠在一起看不清
        .blur(radius: showSettings ? 8 : 0)
        .animation(.easeOut(duration: 0.25), value: showSettings)
    }

    // MARK: 顶栏——双胶囊（左：导航/状态，右：操作，播放中自动隐藏）

    private var topBar: some View {
        HStack(spacing: 10) {
            CapsuleBar {
                CapsuleButton(icon: "chevron.left", label: "返回") { dismiss() }
                CapsuleDivider()
                HStack(spacing: 7) {
                    // 播放/暂停状态位：两态同占 12pt 盒，切换时数字不横移
                    ZStack {
                        if isPlaying {
                            Circle()
                                .fill(Color.dangerRed)
                                .overlay(
                                    Circle().strokeBorder(
                                        LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center),
                                        lineWidth: 1
                                    )
                                )
                                .shadow(color: Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255).opacity(0.5), radius: 3)
                        } else {
                            Image(systemName: "pause.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .frame(width: 12, height: 12)
                    Text(PrompterCore.formatTime(elapsed))
                        .font(.system(size: 13, design: .monospaced))
                        .monospacedDigit()
                        .tracking(0.5)
                        .fixedSize() // 防止被挤成两行
                        .foregroundStyle(.white.opacity(0.6))
                        .accessibilityIdentifier("player.elapsed")
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .accessibilityLabel(isPlaying ? "播放中" : "已暂停")
                CapsuleDivider()
                CapsuleButton(icon: "camera", label: "前置镜子") { showMirror = true }
            }

            Spacer(minLength: 0)

            CapsuleBar {
                CapsuleButton(
                    icon: "checkmark.circle",
                    label: script.isFilmed ? "取消已拍摄标记" : "标记为已拍摄",
                    active: script.isFilmed
                ) { toggleFilmed() }
                CapsuleDivider()
                CapsuleButton(icon: "pencil.line", label: "编辑") {
                    isPlaying = false
                    editing = true
                }
                CapsuleDivider()
                CapsuleButton(icon: "slider.horizontal.3", label: "设置") { showSettings = true }
            }
            .opacity(isPlaying ? 0 : 1)
            .offset(y: isPlaying ? -8 : 0)
            .allowsHitTesting(!isPlaying)
        }
        .animation(.easeInOut(duration: 0.3), value: isPlaying)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: 中央播放提示（暂停时；穿透不拦截，瞄准图标点也能播放）

    @ViewBuilder
    private var centerHint: some View {
        if !isPlaying && !pointerDown && !showOnboarding && !showSettings {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 88, height: 88)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 88, height: 88)
                    Image(systemName: "play.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.accentGold)
                        .offset(x: 2)
                }
                .shadow(color: .black.opacity(0.45), radius: 22, y: 8) // 托底，把提示从正文上“抬”出来
                .shadow(color: Color.accentGold.opacity(0.35), radius: 16) // 金色微光，与引导线同族
                Text("点击屏幕任意位置播放")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.45), in: Capsule()) // 垫底，避免被大字正文穿透
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
            .opacity(hintPulse ? 1 : 0.72)
            .scaleEffect(hintPulse ? 1.03 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    hintPulse = true
                }
            }
            .onDisappear { hintPulse = false }
            .allowsHitTesting(false)
        }
    }

    // MARK: 阅读引导线（金色辉光竖条，左右各一）

    private var guideLines: some View {
        HStack {
            guideBar
            Spacer()
            guideBar
        }
        .padding(.horizontal, 12)
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
        HStack(spacing: 12) {
            ParamGroup(label: "字号", value: settings.data.fontSize,
                       range: PrompterCore.fontSizeMin...PrompterCore.fontSizeMax, step: 2) {
                settings.data.fontSize = $0
            }
            ParamGroup(label: "速度", value: settings.data.scrollSpeed,
                       range: PrompterCore.speedMin...PrompterCore.speedMax, step: 10) {
                settings.data.scrollSpeed = $0
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.canvas.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .opacity(isPlaying ? 0 : 1)
        .offset(y: isPlaying ? 8 : 0)
        .allowsHitTesting(!isPlaying)
        .animation(.easeInOut(duration: 0.3), value: isPlaying)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: 回到顶部（停在最底部且暂停时出现）——胶囊体系，与底部控制条对齐呼吸

    @ViewBuilder
    private var backToTop: some View {
        if atBottom && !isPlaying {
            Button {
                isPlaying = false
                elapsed = 0
                engine.scrollToIndex(0)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("回到顶部")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.65))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color.surface.opacity(0.72), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            }
            .buttonStyle(PressableStyle())
            .padding(.bottom, 100) // 底部控制条（约 84pt）上方留 16pt 呼吸空间
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }

    // MARK: 提示胶囊（暂停原因 / 捏合字号 / 读完）

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast.text)
                .font(.system(size: 12))
                .foregroundStyle(toast.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.surface.opacity(0.94), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .padding(.top, 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityIdentifier("player.toast")
        }
    }

    // MARK: 新手引导（首次进入，5 秒或点击消失）

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
                    Text("点击任意位置开始")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { dismissOnboarding() }
            .task {
                try? await Task.sleep(for: .seconds(5))
                dismissOnboarding()
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
        switch settings.data.completeAction {
        case "restart":
            // 重读：自动暂停重新生效，回到开头并暂停，计时归零（新一条）
            keywordTracker.reset()
            paragraphTracker.reset()
            elapsed = 0
            engine.scrollToIndex(0)
        case "list":
            completed = true
            if !script.isFilmed {
                script.isFilmed = true
                script.updatedAt = Date()
            }
            showToast("✓ 已读完·已标记拍摄", color: .successGreen, duration: 1.2)
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            }
        default:
            break // none：读完即停
        }
    }

    private func checkAutoPause() {
        guard isPlaying else { return }
        let keyword = settings.data.pauseKeyword
        if !keyword.isEmpty,
           keywordTracker.shouldPause(content: script.content, keyword: keyword, activeIndex: activeIndex) {
            isPlaying = false
            showToast("已暂停：命中关键词「\(keyword)」")
            return
        }
        if settings.data.pauseOnParagraph,
           paragraphTracker.shouldPause(paragraphStarts: paragraphStarts, activeIndex: activeIndex) {
            isPlaying = false
            showToast("已暂停：段落分隔")
        }
    }

    private func toggleFilmed() {
        script.isFilmed.toggle()
        script.updatedAt = Date()
        // 不再弹提示：按钮自身的绿色高亮即状态反馈
    }

    /// duration 为 nil 时常驻（捏合过程中），由后续调用接管关闭
    private func showToast(_ text: String, color: Color = .accentGold, duration: Double? = 3) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { toast = Toast(text: text, color: color) }
        guard let duration else { return }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
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
        withAnimation(.easeOut(duration: 0.2)) { showOnboarding = false }
        UserDefaults.standard.set(true, forKey: Self.onboardKey)
    }
}

// MARK: - 底部参数组：暗淡标签 + 数值胶囊 + 滑杆

private struct ParamGroup: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            Slider(
                value: Binding(get: { Double(value) }, set: { onChange(Int($0.rounded())) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .tint(.accentGold)
            .frame(height: CTL.t1)
        }
        .frame(maxWidth: .infinity)
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
