import SwiftUI

struct AirPodsNodSettings: View {
    @ObservedObject var controller: AirPodsNodController
    @EnvironmentObject private var settings: AppSettings
    @State private var showCalibration = false
    @State private var showDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { settings.data.airPodsNodEnabled }, set: { enabled in
                if enabled && settings.data.headGestureCalibration?.valid != true { showCalibration = true }
                else { settings.data.airPodsNodEnabled = enabled }
            })) {
                Label("AirPods 点头控制", systemImage: "airpodspro")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
            }
            .tint(.accentGold).accessibilityIdentifier("settings.airPodsNod")
            Text(settings.data.airPodsNodEnabled
                 ? "点头一下并回正，开始或暂停提词。请保持身体稳定。"
                 : "戴上支持头部运动的 AirPods，点头即可开始或暂停。首次开启需要校准。")
                .font(.caption).foregroundStyle(.textSecondary).fixedSize(horizontal: false, vertical: true)
            if settings.data.airPodsNodEnabled {
                Text(controller.status).font(.caption).foregroundStyle(.textSecondary)
                if let hint = controller.lastAttemptHint {
                    Text("上次动作：\(hint)").font(.subheadline).foregroundStyle(Color.accentGold)
                        .accessibilityIdentifier("settings.nodLastAttempt")
                }
            }
            HStack {
                Button(settings.data.headGestureCalibration == nil ? "了解并校准" : "重新校准") { showCalibration = true }
                    .accessibilityIdentifier("settings.calibrateNod")
                Spacer()
                if settings.data.airPodsNodEnabled {
                    Button("检查连接") { controller.refreshConnection() }
                }
            }.font(.subheadline).foregroundStyle(Color.accentGold).frame(minHeight: 44)
            if settings.data.airPodsNodEnabled {
                Text("换耳机后沿用当前校准；如识别不顺手，可自行重新校准。")
                    .font(.caption).foregroundStyle(.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if settings.data.airPodsNodEnabled || controller.diagnostics.canMark {
                Button { showDiagnostics = true } label: {
                    HStack {
                        Label("点头诊断", systemImage: "waveform.path.ecg")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.font(.subheadline).foregroundStyle(Color.accentGold).frame(minHeight: 44)
                }.accessibilityIdentifier("settings.nodDiagnostics")
            }
        }
        .sheet(isPresented: $showCalibration) {
            AirPodsCalibrationView(controller: controller) { profile in
                settings.data.headGestureCalibration = profile
                settings.data.airPodsNodEnabled = true
                settings.flush()
                showCalibration = false
            }
        }
        .sheet(isPresented: $showDiagnostics) { NodDiagnosticsView(controller: controller) }
    }
}

struct AirPodsCalibrationView: View {
    @ObservedObject var controller: AirPodsNodController
    var onComplete: (HeadGestureCalibration) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var readyFeedbackSent = false

    private var stage: HeadCalibrationStage { controller.calibrationProgress.stage }
    private var action: HeadCalibrationAction { controller.calibrationAction ?? .down }
    private var displayAction: HeadCalibrationAction { action }
    private var hasCandidate: Bool { controller.candidate != nil && controller.calibrationAction == nil }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let compact = geometry.size.width > geometry.size.height && geometry.size.width > 650
                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? 16 : 24) {
                        intro(compact: compact)
                        if compact {
                            HStack(alignment: .center, spacing: 20) {
                                focusCard(compact: true).frame(maxWidth: .infinity)
                                controls(compact: true).frame(maxWidth: .infinity)
                            }
                        } else {
                            focusCard(compact: false)
                            controls(compact: false)
                        }
                        if !compact { comfortNote }
                    }
                    .padding(compact ? 18 : 24)
                    .frame(maxWidth: compact ? 1000 : 620)
                    .frame(maxWidth: .infinity)
                }.accessibilityIdentifier("nod.calibrationScroll")
            }
            .background(Color.canvas).foregroundStyle(.white)
            .navigationTitle("点头控制校准").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(Color.accentGold)
                        .accessibilityIdentifier("nod.cancelCalibration")
                }
            }
            .toolbarBackground(Color.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .interactiveDismissDisabled(controller.capturing)
        .onAppear { controller.beginCalibration() }
        .onDisappear { controller.endCalibration() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { controller.interruptCalibration() } }
        .onChange(of: stage) { _, stage in
            // Verification is ready at .verifying; its .performing phase is already the user's nod.
            let ready = hasCandidate ? stage == .verifying : stage == .performing
            if ready && !readyFeedbackSent {
                readyFeedbackSent = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            if stage == .completed { UISelectionFeedbackGenerator().selectionChanged() }
            UIAccessibility.post(notification: .announcement,
                                 argument: stage == .performing && !hasCandidate ? action.title : stage.title)
        }
        .onChange(of: controller.verified) { _, verified in
            // A full success belongs to the independently verified result, not each recorded step.
            if verified { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }

    private func intro(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Text(controller.verified ? "校准完成" : controller.calibrationError != nil ? "调整当前动作" : hasCandidate ? (controller.learningHabit ? "最后，适配你的点头" : "再试一次，就完成了") : "认识你的佩戴方式")
                .font(compact ? .headline : .title2.weight(.semibold))
            if !compact {
                Text(hasCandidate ? (controller.learningHabit ? "按平时控制提词的习惯，自然地点头，不必刻意加大动作。" : "用一次新的自然点头，检查当前设置能否正常识别。") : "坐稳、看向正面。等准备完成后，再跟随卡片里的提示做动作。")
                    .font(.subheadline).foregroundStyle(.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 7) {
                ForEach(HeadCalibrationAction.allCases, id: \.rawValue) { item in
                    let done = controller.completedCalibrationActions.contains(item)
                    let current = controller.calibrationAction == item
                    Button { controller.selectCalibrationAction(item) } label: {
                        Capsule().fill(done ? Color.accentGold : current ? Color.accentGold.opacity(0.45) : Color.white.opacity(0.1))
                            .frame(height: 4).frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).allowsHitTesting(!controller.capturing && item.rawValue < controller.captures.count)
                    .accessibilityLabel("\(item.shortTitle)，\(done ? "已记录，点按重做" : current ? "当前动作" : "待完成")")
                    .accessibilityIdentifier("nod.step.\(item.rawValue)")
                }
            }
        }
    }

    private var stepNumber: Int { hasCandidate || controller.verified ? 6 : displayAction.rawValue + 1 }
    private var actionTitle: String {
        if controller.verified { return "点头识别成功" }
        return hasCandidate ? (controller.learningHabit ? "自然点头" : "试一次点头") : displayAction.title
    }
    private var stageTitle: String {
        if controller.capturing { return stage.title }
        if controller.verified { return "可以开启点头控制了" }
        if hasCandidate {
            if controller.learningHabit { return controller.habitSamples.isEmpty ? "准备好后开始" : "上次已记录，继续下一次" }
            return controller.candidate?.habit == nil ? "使用默认设置，等待验证" : "个人适配已记录"
        }
        if controller.calibrationError != nil { return "只需重做当前动作" }
        return "准备好后开始"
    }
    private var stageColor: Color {
        controller.verified ? .successGreen : .accentGold
    }

    private func focusCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: controller.verified ? "checkmark" : displayAction.icon)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(stageColor).frame(width: 52, height: 52)
                    .background(stageColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                Text(actionTitle)
                    .font(.title.weight(.semibold)).foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : AppMotion.detail, value: actionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier(hasCandidate ? "nod.verification" : "nod.action")
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if hasCandidate && !controller.learningHabit {
                        Text("验证").font(.headline).foregroundStyle(Color.accentGold)
                    } else {
                    Text("\(controller.learningHabit ? controller.habitSamples.count + 1 : stepNumber)").font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : AppMotion.detail,
                                   value: controller.learningHabit ? controller.habitSamples.count + 1 : stepNumber)
                    Text(controller.learningHabit ? "/3" : "/6").font(.title3.weight(.medium)).foregroundStyle(.textSecondary)
                    }
                }
                .monospacedDigit().fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(hasCandidate ? (controller.learningHabit ? "自然点头 \(controller.habitSamples.count + 1)，共 3 次" : "最终验证") : "动作 \(stepNumber)，共 6 个")
                .accessibilityIdentifier("nod.stepNumber")
            }
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                Label(stageTitle, systemImage: controller.verified ? "checkmark.circle" : stage == .preparing ? "pause.circle" : "waveform.path")
                    .font(.headline).foregroundStyle(stageColor)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : AppMotion.detail, value: stageTitle)
                    .accessibilityIdentifier("nod.stage")
                if controller.calibrationError == nil {
                    Text(controller.verified ? "点击下方按钮保存，之后点头即可开始或暂停提词。" : controller.capturing ? controller.calibrationProgress.hint : hasCandidate ? "先保持静止，再自然地点头一下并回正。" : displayAction.instruction)
                        .font(.body).foregroundStyle(Color.white.opacity(0.88)).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("nod.instruction")
                }
                if controller.capturing && (stage == .preparing || stage == .performing || stage == .returning) {
                    CalibrationProgressTrack(progress: controller.calibrationProgress)
                        .accessibilityLabel(stage == .preparing ? "准备进度" : stage == .performing ? "动作幅度进度" : "回正进度")
                }
            }
            errorCard
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(controller.capturing ? Color.accentGold.opacity(0.25) : Color.white.opacity(0.04)))
    }

    @ViewBuilder private var errorCard: some View {
        if let error = controller.calibrationError {
            VStack(alignment: .leading, spacing: 12) {
                Label("这一步需要调整", systemImage: "exclamationmark.circle.fill")
                    .font(.headline).foregroundStyle(Color.accentGold)
                Text(error).font(.body).foregroundStyle(.white).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nod.calibrationError")
                if let problem = controller.calibrationProblem, problem.related.count > 1 {
                    HStack {
                        ForEach(problem.related, id: \.rawValue) { item in
                            Button("重做\(item.shortTitle)") { controller.selectCalibrationAction(item) }
                                .font(.subheadline).foregroundStyle(Color.accentGold).frame(minHeight: 44)
                        }
                    }
                }
                if controller.calibrationProblem?.requiresRestart == true {
                    Button("重新佩戴后，从头校准") { controller.restartCalibration() }
                        .foregroundStyle(Color.accentGold).frame(minHeight: 44)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentGold.opacity(0.18)))
        }
    }

    private var comfortNote: some View {
        Text("做到舒适幅度即可，不必用力。短暂晃动会自动重新准备，已完成的动作会保留。")
            .font(.caption).foregroundStyle(.textSecondary).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func controls(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 10) {
            if compact {
                Text(controller.verified ? "完成校准" : controller.capturing ? "跟随左侧提示" : "准备与连接")
                    .font(.headline).foregroundStyle(.white)
            }
            if !controller.capturing && !controller.verified && controller.calibrationError == nil {
                Label(controller.status, systemImage: "airpodspro").font(.subheadline).foregroundStyle(.textSecondary)
                    .accessibilityIdentifier("nod.connectionStatus")
            }
            Button {
                if controller.verified, let candidate = controller.candidate { onComplete(candidate) }
                else { readyFeedbackSent = false; controller.retryCalibration() }
            } label: {
                HStack(spacing: 8) {
                    if controller.capturing { ProgressView().tint(.black) }
                    Text(buttonTitle).font(.body.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(.black).background(Color.accentGold, in: Capsule())
            }
            .buttonStyle(PressableStyle(disabledOpacity: 0.75)).disabled(controller.capturing)
            .accessibilityIdentifier("nod.startCalibration")
            if hasCandidate && controller.learningHabit {
                Button("使用默认并验证") { readyFeedbackSent = false; controller.skipHabitLearning() }
                    .foregroundStyle(Color.accentGold).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("nod.skipHabit")
            }
            if controller.capturing {
                Button(hasCandidate ? "重新试一次点头" : "重新准备这个动作") { readyFeedbackSent = false; controller.retryCalibration() }
                    .foregroundStyle(Color.accentGold).font(.subheadline).frame(minHeight: 44)
                    .accessibilityIdentifier("nod.retryCurrent")
            }
            if controller.permissionDenied {
                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }.font(.subheadline).foregroundStyle(Color.accentGold).frame(minHeight: 44)
            }
            if compact { comfortNote }
        }
        .padding(compact ? 20 : 0)
        .background(compact ? Color.surface.opacity(0.65) : .clear, in: RoundedRectangle(cornerRadius: 22))
    }
    private var buttonTitle: String {
        if controller.capturing { return stage == .preparing ? "正在准备…" : stage == .returning ? "等待回正…" : "正在识别…" }
        if controller.verified { return "完成并开启" }
        if hasCandidate { return controller.learningHabit ? "\(controller.habitSamples.isEmpty ? "开始" : "继续")：自然点头 \(controller.habitSamples.count + 1)/3" : "试一次点头" }
        if controller.calibrationError != nil { return "只重试\(action.shortTitle)" }
        return stage == .completed ? "继续：\(action.shortTitle)" : "开始：\(action.shortTitle)"
    }
}

/// Smooth real progress only within one phase. A reset or phase change must remain immediate.
private struct CalibrationProgressTrack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var progress: HeadCalibrationProgress
    @State private var fraction: Double

    init(progress: HeadCalibrationProgress) {
        self.progress = progress
        _fraction = State(initialValue: progress.fraction)
    }

    var body: some View {
        ProgressView(value: fraction)
            .tint(Color.accentGold)
            .onChange(of: progress) { old, new in
                let smooth = !reduceMotion && old.stage == new.stage && new.fraction > old.fraction
                withAnimation(smooth ? AppMotion.sensorTracking : nil) { fraction = new.fraction }
            }
    }
}

