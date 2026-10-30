import SwiftUI
import SwiftData

/// 编辑页（M2）：标题 / 分组 / 拆分 / 暂停 / 正文——全套系统控件 + 系统底色
struct EditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @Query private var allScripts: [Script]

    let script: Script? // nil = 新建

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var folder: String?
    @State private var loaded = false

    // 分组行内联新建
    @State private var newFolderOpen = false
    @State private var newFolderName = ""
    @FocusState private var newFolderFocused: Bool

    // 拆分/暂停：本地 state，退出时同步到设置
    @State private var splitMode: SplitMode = .paragraph
    @State private var pauseMode: PauseMode = .off

    var body: some View {
        VStack(spacing: 0) {
            // ── 标题行 ──
            HStack(spacing: 10) {
                Button {
                    saveAndClose()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 17, weight: .medium))
                }
                .buttonStyle(.borderless)
                TextField("稿件标题", text: $title)
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // ── 设置区（系统 Form 外观，但保持紧凑高度） ──
            VStack(spacing: 0) {
                // 拆分行
                HStack(spacing: 12) {
                    Text("拆分")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Picker("", selection: $splitMode) {
                        ForEach(SplitMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                    // 关键词输入框常驻：未选关键词时灰色不可输入，位置大小不变
                    TextField("关键词", text: $settings.data.splitKeyword)
                        .font(.subheadline)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .disabled(splitMode != .keyword)
                    Spacer(minLength: 8)
                    Button("智能拆分") {
                        performSplit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(splitDisabled)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // 暂停行
                HStack(spacing: 12) {
                    Text("暂停")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Picker("", selection: $pauseMode) {
                        ForEach(PauseMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    TextField("关键词", text: $settings.data.pauseKeyword)
                        .font(.subheadline)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .disabled(pauseMode != .keyword)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // 分组行
                HStack(spacing: 12) {
                    Text("分组")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Menu {
                                Button("未分组") { folder = nil }
                                ForEach(folders, id: \.self) { name in
                                    Button(name) { folder = name }
                                }
                                Divider()
                                Button("新建分组…") {
                                    newFolderOpen = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                    Text(folder ?? "未分组")
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                }
                            }
                            .buttonStyle(.bordered)
                            if newFolderOpen {
                                TextField("新分组名", text: $newFolderName)
                                    .font(.subheadline)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 110)
                                    .focused($newFolderFocused)
                                    .onSubmit { commitNewFolder() }
                                Button("确定") {
                                    commitNewFolder()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)

            // ── 正文编辑区 ──
            TextEditor(text: $content)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            title = script?.title ?? ""
            content = script?.content ?? ""
            folder = script?.folder
            splitMode = SplitMode(rawValue: settings.data.splitMode) ?? .paragraph
            pauseMode = Self.derivePauseMode(settings.data)
        }
    }

    // MARK: 分组

    private var folders: [String] {
        var set = Set(allScripts.compactMap(\.folder))
        if let f = folder { set.insert(f) }
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func commitNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderOpen = false
        newFolderName = ""
        guard !name.isEmpty else { return }
        folder = name
    }

    // MARK: 拆分

    private var splitDisabled: Bool {
        if splitMode == .keyword {
            return settings.data.splitKeyword.isEmpty || !content.contains(settings.data.splitKeyword)
        }
        return !content.contains("\n\n")
    }

    private func performSplit() {
        let segments = splitMode == .keyword
            ? Splitter.byKeyword(content, keyword: settings.data.splitKeyword)
            : Splitter.byParagraphs(content)
        guard segments.count >= 2 else { return }
        for segment in segments {
            let segTitle = Splitter.titleOfSegment(segment)
            context.insert(Script(title: segTitle.isEmpty ? "未命名稿件" : segTitle, content: segment, folder: folder))
        }
        if let script { context.delete(script) }
        dismiss()
    }

    // MARK: 暂停

    enum PauseMode: String, CaseIterable {
        case off, paragraph, keyword
        var label: String {
            switch self {
            case .off: return "关闭"
            case .paragraph: return "空行"
            case .keyword: return "关键词"
            }
        }
    }

    static func derivePauseMode(_ data: SettingsData) -> PauseMode {
        if !data.pauseKeyword.isEmpty { return .keyword }
        return data.pauseOnParagraph ? .paragraph : .off
    }

    // MARK: 保存

    private func saveAndClose() {
        settings.data.splitMode = splitMode.rawValue
        settings.data.pauseOnParagraph = pauseMode == .paragraph
        if pauseMode != .keyword { settings.data.pauseKeyword = "" }

        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let script {
            script.title = finalTitle.isEmpty ? "未命名稿件" : finalTitle
            script.content = content
            script.folder = folder
            script.updatedAt = Date()
        } else {
            context.insert(Script(
                title: finalTitle.isEmpty ? "未命名稿件" : finalTitle,
                content: content,
                folder: folder
            ))
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let c = try! ModelContainer(for: Script.self, configurations: config)
        let context = ModelContext(c)
        context.insert(Script(title: "已有稿件", content: "内容", folder: "口播"))
        try? context.save()
        return c
    }()
    return EditorView(script: nil)
        .modelContainer(container)
        .environmentObject(AppSettings())
}
#endif