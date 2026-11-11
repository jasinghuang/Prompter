import SwiftUI

struct SpeechFollowSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var models: SpeechModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("提词模式", systemImage: "waveform")
                .foregroundStyle(Color.textSecondary)
            Picker("提词模式", selection: $settings.data.playbackMode) {
                ForEach(PlaybackMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings.playbackMode")
            if settings.data.playbackMode == .voice {
                Text("轻点正文开始。竖屏在中上方阅读，横屏以灵动岛的中心高度为阅读基准。说话时保持缓慢前进，语速变化时立即开始柔和调整，用约 2 秒平滑过渡；短暂停顿后逐渐减速，约 6 秒后停住。触摸或拖动立即暂停跟随，松手 1.5 秒后按当前阅读区重新跟随；右上角暂停键可持续暂停。")
                    .font(.caption).foregroundStyle(Color.textSecondary)
                Picker("识别引擎", selection: $settings.data.speechEngine) {
                    ForEach(SpeechEngineKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityIdentifier("speech.enginePicker")
                Text(settings.data.speechEngine.detail).font(.caption).foregroundStyle(Color.textSecondary)
                Toggle("显示识别与跟随状态", isOn: $settings.data.showSpeechDiagnostics)
                    .accessibilityIdentifier("speech.showDiagnostics")
                if settings.data.speechEngine == .apple {
                    Label("音频仅在本机识别 · 系统语言资源首次可能需下载", systemImage: "iphone")
                        .font(.caption).foregroundStyle(Color.textSecondary)
                } else if settings.data.speechEngine == .zipformer {
                    Label(BundledSpeechModels.zipformer != nil ? "离线模型已随 App 安装 · 无需下载" : "所选模型暂未就绪", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(Color.accentGold)
                        .accessibilityIdentifier("speech.modelReady")
                } else if settings.data.speechEngine == .senseVoice {
                    Label(BundledSpeechModels.senseVoice != nil ? "离线模型已随 App 安装 · 无需下载" : "所选模型暂未就绪", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(Color.accentGold)
                        .accessibilityIdentifier("speech.modelReady")
                } else {
                if models.ready {
                    Label(models.isBundled ? "离线模型已随 App 安装 · 无需下载" : "离线模型已就绪 · 音频仅在本机处理", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(Color.accentGold)
                        .accessibilityIdentifier("speech.modelReady")
                } else if let progress = models.progress {
                    if models.downloadPhase == .connecting {
                        ProgressView().tint(.accentGold)
                    } else {
                        ProgressView(value: progress).tint(.accentGold)
                    }
                    Text(models.downloadPhase.label)
                        .font(.caption).foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("speech.downloadPhase")
                    HStack {
                        Text(String(format: "%.1f / %.1f MB", Double(models.downloadedBytes) / 1_000_000,
                                    Double(ParaformerModel.totalBytes) / 1_000_000))
                            .font(.caption).monospacedDigit()
                            .accessibilityIdentifier("speech.downloadBytes")
                        Spacer()
                        Button("取消下载", action: models.cancel).frame(minHeight: 44)
                            .accessibilityIdentifier("speech.cancelDownload")
                    }
                } else {
                    Text("首次需下载约 237 MB 的模型，完成后可断网使用。")
                        .font(.caption).foregroundStyle(Color.textSecondary)
                    Button(action: models.downloadModel) {
                        Label(models.message == nil ? "下载离线模型" : "重试下载", systemImage: "arrow.down.circle")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("speech.downloadModel")
                }
                if let message = models.message {
                    Text(message).font(.caption).foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("speech.downloadError")
                }
                }
            }
        }
    }
}
