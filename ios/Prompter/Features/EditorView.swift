import SwiftUI
import SwiftData

/// 编辑页（M2 完整版）：标题/正文 + 分组行 + 工具区（拆分/暂停）+ 正文编辑
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

    // 拆分/暂停模式：本地 state（picker 动画流畅的关键——不直接绑定到
    // settings 对象，避免每次切换触发整个视图树重渲染打断滑块动画）
    @State private var splitMode: SplitMode = .paragraph
    @State private var pauseMode: EditorView.PauseMode = .off

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            folderRow
            toolArea
            textEditor
        }
        .background(Color.canvas)
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

    // MARK: 标题行

    private var titleRow: some View {
        HStack(spacing: 8) {
            Button {
                saveAndClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 34, height: 34)
                    .background(Color.surface.opacity(0.7), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            TextField("稿件标题", text: $title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: 分组行

    /// 已有文件夹 + 当前选中（还没保存到任何稿件的新文件夹也立即显示）
    private var folders: [String] {
        var set = Set(allScripts.compactMap(\.folder))
        if let f = folder { set.insert(f) }
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var folderRow: some View {
        HStack(spacing: 10) {
            Label("分组", systemImage: "folder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    folderChip(label: "未分组", active: folder == nil) { folder = nil }
                    ForEach(folders, id: \.self) { name in
                        folderChip(label: name, active: folder == name) { folder = name }
                    }
                    if newFolderOpen {
                        TextField("新分组名", text: $newFolderName)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(width: 110, height: 32)
                            .background(Color.accentGold.opacity(0.1), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.accentGold.opacity(0.4)))
                            .focused($newFolderFocused)
                            .submitLabel(.done)
                            .onSubmit { commitNewFolder() }
                            .onChange(of: newFolderFocused) { _, focused in
                                if !focused { commitNewFolder() }
                            }
                    } else {
                        Button {
                            newFolderName = ""
                            newFolderOpen = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                newFolderFocused = true
                            }
                        } label: {
                            Label("新建", systemImage: "plus")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 16)
            }
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { hairline }
    }

    private func folderChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? .white : .white.opacity(0.45))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(active ? Color.white.opacity(0.15) : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func commitNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderOpen = false
        guard !name.isEmpty else { return }
        folder = name // 新分组随本稿件落地，folders 计算属性会立即包含它
    }

    // MARK: 工具区（拆分行 + 暂停行，各自独立行，参照 Web 版布局）

    private var toolArea: some View {
        VStack(spacing: 0) {
            // ── 拆分行 ──
            HStack(spacing: 10) {
                Label("拆分", systemImage: "scissors")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.leading, 16)
                SegmentedPill(
                    options: SplitMode.allCases.map { ($0, $0.label) },
                    selection: $splitMode
                )
                .frame(width: splitMode == .keyword ? 100 : 110, height: 32)
                if splitMode == .keyword {
                    keywordField("关键词", text: $settings.data.splitKeyword)
                        .frame(maxWidth: 110)
                }
                Spacer(minLength: 8)
                Button(action: performSplit) {
                    Text("智能拆分")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.canvas)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(splitDisabled ? Color.accentGold.opacity(0.3) : Color.accentGold, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(splitDisabled)
                .padding(.trailing, 16)
            }
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) { hairline }

            // ── 暂停行 ──
            HStack(spacing: 10) {
                Label("暂停", systemImage: "pause.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.leading, 16)
                SegmentedPill(
                    options: PauseMode.allCases.map { ($0, $0.label) },
                    selection: $pauseMode
                )
                .frame(width: pauseMode == .keyword ? 140 : 160, height: 32)
                if pauseMode == .keyword {
                    keywordField("关键词", text: $settings.data.pauseKeyword)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) { hairline }
        }
    }

    private func keywordField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.05)))
            .autocorrectionDisabled()
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

    // MARK: 暂停模式

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

    // MARK: 正文

    private var textEditor: some View {
        TextEditor(text: $content)
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private var hairline: some View {
        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1).padding(.horizontal, 16)
    }

    // MARK: 保存

    private func saveAndClose() {
        // 退出前同步拆分/暂停模式到设置
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