import SwiftUI

struct IslandIndicatorSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var calibrating = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("横屏镜头指示环", isOn: $settings.data.islandIndicatorEnabled)
                .accessibilityIdentifier("settings.islandIndicator")
            Text("金色为底轨，绿色表示当前阅读进度。横屏显示，竖屏隐藏。")
                .font(.caption).foregroundStyle(Color.textSecondary)
            if settings.data.islandIndicatorEnabled {
                Button("调整与灵动岛的贴合") { calibrating = true }
                    .accessibilityIdentifier("settings.islandCalibration")
                    .foregroundStyle(Color.accentGold).frame(minHeight: 44)
            }
        }
        .fullScreenCover(isPresented: $calibrating) { IslandCalibrationView() }
    }
}

private struct IslandCalibrationView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var draft = IslandIndicatorCalibration()
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if geometry.size.width > geometry.size.height {
                    PromptIslandOverlay(readingProgress: 0.65, visible: true, calibration: draft)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea().allowsHitTesting(false)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("贴合灵动岛").font(.title2.bold())
                        Text(geometry.size.width > geometry.size.height
                             ? "观察镜头旁的环，调整到轮廓外侧。这里只改变指示环，不改变正文位置。"
                             : "请横放手机，观察灵动岛旁的指示环。")
                            .font(.caption).foregroundStyle(Color.textSecondary)
                        control("离边缘距离", value: $draft.edgeOffset, range: -16...16)
                        control("上下位置", value: $draft.verticalOffset, range: -24...24)
                        control("长度", value: $draft.lengthAdjustment, range: -24...24)
                        control("宽度", value: $draft.thicknessAdjustment, range: -12...12)
                        HStack {
                            Button("恢复基准") { draft = .init() }
                            Spacer()
                            Button("取消") { dismiss() }
                            Button("保存") { settings.islandCalibration = draft.normalized; settings.flush(); dismiss() }
                                .buttonStyle(.borderedProminent)
                        }.frame(minHeight: 44)
                    }.padding(20)
                }
                .frame(maxWidth: 540, maxHeight: geometry.size.height - 20)
                .background(Color.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 76).padding(.vertical, 10)
            }
        }
        .onAppear { draft = settings.islandCalibration }
        .preferredColorScheme(.dark).tint(.accentGold)
    }
    private func control(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).font(.subheadline).frame(width: 88, alignment: .leading)
            Slider(value: value, in: range, step: 0.5).accessibilityLabel(label)
            Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                .font(.caption.monospacedDigit()).frame(width: 36)
        }.frame(minHeight: 36)
    }
}
