import SwiftUI

struct NodDiagnosticsView: View {
    @ObservedObject var controller: AirPodsNodController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("记录本次测试", isOn: Binding(get: { controller.diagnostics.recording },
                                                           set: { controller.setDiagnosticsRecording($0) }))
                            .tint(.accentGold).accessibilityIdentifier("nod.diagnosticsRecording")
                        Text("开启后回到正文测试。记录只保留在本次播放页面内，离开前可导出；不包含稿件正文或原始运动数据。")
                            .font(.subheadline).foregroundStyle(.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本次记录").font(.headline)
                        statistic("识别通过", count: controller.diagnostics.counts.detected, id: "detected")
                        statistic("实际播放切换", count: controller.diagnostics.counts.applied, id: "applied")
                        statistic("自动拒绝", count: controller.diagnostics.counts.rejected, id: "rejected")
                        statistic("数据与服务异常", count: controller.diagnostics.counts.serviceIssues, id: "service")
                        if controller.diagnostics.counts.sensorChanges > 0 {
                            statistic("耳机来源切换", count: controller.diagnostics.counts.sensorChanges, id: "sensorChanges")
                        }
                        if controller.diagnostics.counts.notApplied > 0 {
                            statistic("页面未接收", count: controller.diagnostics.counts.notApplied, id: "notApplied")
                        }
                        Divider().overlay(Color.white.opacity(0.06)).padding(.vertical, 6)
                        statistic("手动未响应", count: controller.diagnostics.counts.manualMisses, id: "misses")
                        statistic("手动误触", count: controller.diagnostics.counts.manualFalsePositives, id: "falsePositives")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Button("标记未响应") { controller.markUnresponsiveNod() }
                                .disabled(!controller.diagnostics.canMark)
                                .accessibilityIdentifier("nod.markMiss")
                            Button("上次是误触") { controller.markLastNodFalsePositive() }
                                .disabled(!controller.diagnostics.canMarkFalsePositive)
                                .accessibilityIdentifier("nod.markFalsePositive")
                        }.buttonStyle(.bordered).tint(.accentGold).font(.subheadline).frame(minHeight: 44)
                        Text("没响应时点一次“标记未响应”；误触会关联上次实际切换。手动标记不改变播放状态，也不会被当作自动判定原因。")
                            .font(.caption).foregroundStyle(.textSecondary).fixedSize(horizontal: false, vertical: true)
                        if controller.diagnostics.canUndoMark {
                            Button("撤销上次标记") { controller.undoDiagnosticMark() }
                                .foregroundStyle(Color.accentGold).font(.subheadline).frame(minHeight: 44)
                                .accessibilityIdentifier("nod.undoMark")
                        }
                    }
                    if controller.diagnostics.canMark {
                        observationSummary
                        recentEvents
                        HStack {
                            if let text = controller.diagnosticsExport {
                                ShareLink(item: text) { Label("导出记录", systemImage: "square.and.arrow.up") }
                                    .accessibilityIdentifier("nod.exportDiagnostics")
                            }
                            Spacer()
                            Button("清空记录") { controller.clearDiagnostics() }
                                .accessibilityIdentifier("nod.clearDiagnostics")
                        }.foregroundStyle(Color.accentGold).font(.subheadline).frame(minHeight: 44)
                    }
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("nod.diagnosticsScroll")
            .background(Color.canvas).foregroundStyle(.white)
            .navigationTitle("点头诊断").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.foregroundStyle(Color.accentGold)
                        .accessibilityIdentifier("nod.closeDiagnostics")
                }
            }
            .toolbarBackground(Color.canvas, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private func statistic(_ title: String, count: Int, id: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.textSecondary)
            Spacer()
            Text("\(count)").font(.body.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier("nod.count.\(id)")
        }.frame(minHeight: 28)
    }

    private var observationSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近观察").font(.headline)
            if let observed = controller.diagnostics.lastPlaybackObservation {
                Text(observed.condition.label).font(.subheadline).foregroundStyle(Color.accentGold)
                Text("保留进入设置前的最近状态，仅作参考，不能据此确认某次漏判原因。")
                    .font(.caption).foregroundStyle(.textSecondary)
            }
            let durations = controller.diagnosticObservedSeconds
            ForEach([NodDiagnostics.Condition.ready, .settling, .cooldown, .manualSuppression, .interrupted], id: \.self) { state in
                if let seconds = durations[state], seconds > 0 {
                    HStack {
                        Text(state.label)
                        Spacer()
                        Text(String(format: "%.1f 秒", seconds)).monospacedDigit()
                    }.font(.subheadline).foregroundStyle(.textSecondary)
                }
            }
            Text("状态时长是观察估计。自动记录无法判断所有点头意图，因此这里不计算成功率。")
                .font(.caption).foregroundStyle(.textSecondary)
        }
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近事件").font(.headline)
            ForEach(Array(controller.diagnostics.entries.suffix(8).reversed())) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.label).font(.subheadline).foregroundStyle(.white)
                    HStack {
                        Text(PrompterCore.formatTime(Int(max(0, entry.time - (controller.diagnostics.beganAt ?? entry.time)))))
                        if entry.kind == .manualMiss, let condition = entry.condition { Text("参考：\(condition.label)") }
                    }.font(.caption).foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("nod.event.\(entry.kind.rawValue).\(entry.id)")
            }
        }
    }
}
