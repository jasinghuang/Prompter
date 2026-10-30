import SwiftUI
import SwiftData

/// 编辑页（M2 完整版）：标题/正文 + 分组行 + 智能拆分 + 自动暂停设置
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

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            folderRow
            splitRow
            pauseRow
            editor
        }
        .background(Color.canvas)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            title = script?.title ?? ""
            content = script?.content ?? ""
            folder = script?.folder
        }
    }

    // MARK: 标题行（返回胶囊 + 标题，与播放页同位）

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

    // MARK: 分组行：未分组 / 现有文件夹 / 内联新建（写入即时生效）

    private var folders: [String] {
        Array(Set(allScripts.compactMap(\.folder))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
                                if !focused { commitNewFolder() } // 点别处 = 提交非空名称
                            }
                    } else {
                        Button {
                            newFolderName = ""
                            newFolderOpen = true
                            newFolderFocused = true
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
        .frame(height: 52)
        .overlay(alignment: .bottom) { hairline }
    }

    private func folderChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? .white : .white.opacity(0.45))
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(active ? Color.white.opacity(0.15) : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func commitNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderOpen = false
        guard !name.isEmpty else { return }
        folder = name // 新分组随本稿件落地
    }

    // MARK: 智能拆分行

    private var splitRow: some View {
        HStack(spacing: 10) {
            Label("拆分", systemImage: "scissors")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 16)
            Picker("拆分方式", selection: Binding(
                get: { SplitMode(rawValue: settings.data.splitMode) ?? .paragraph },
                set: { settings.data.splitMode = $0.rawValue }
            )) {
                ForEach(SplitMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            if settings.data.splitMode == SplitMode.keyword.rawValue {
                TextField("拆分关键词", text: $settings.data.splitKeyword)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.05)))
                    .autocorrectionDisabled()
            }
            Spacer(minLength: 8)
            Button(action: performSplit) {
                Label("智能拆分", systemImage: "scissors")
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
        .frame(height: 52)
        .overlay(alignment: .bottom) { hairline }
    }

    private var splitDisabled: Bool {
        if settings.data.splitMode == SplitMode.keyword.rawValue {
            return settings.data.splitKeyword.isEmpty || !content.contains(settings.data.splitKeyword)
        }
        return !content.contains("\n\n")
    }

    /// 拆分：产物继承分组，删除原稿，回列表（与 Web 版行为一致）
    private func performSplit() {
        let mode = SplitMode(rawValue: settings.data.splitMode) ?? .paragraph
        let segments = mode == .keyword
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

    // MARK: 自动暂停设置行（行为在 M3 播放页生效）

    private enum PauseMode: String, CaseIterable {
        case off, paragraph, keyword
        var label: String {
            switch self {
            case .off: return "关闭"
            case .paragraph: return "空行"
            case .keyword: return "关键词"
            }
        }
    }

    private var pauseMode: PauseMode {
        if !settings.data.pauseKeyword.isEmpty { return .keyword }
        return settings.data.pauseOnParagraph ? .paragraph : .off
    }

    private func setPauseMode(_ mode: PauseMode) {
        settings.data.pauseOnParagraph = mode == .paragraph
        if mode != .keyword { settings.data.pauseKeyword = "" }
    }

    private var pauseRow: some View {
        HStack(spacing: 10) {
            Label("自动暂停", systemImage: "pause.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 16)
            Picker("自动暂停", selection: Binding(get: { pauseMode }, set: { setPauseMode($0) })) {
                ForEach(PauseMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            if pauseMode == .keyword {
                TextField("暂停关键词", text: $settings.data.pauseKeyword)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.05)))
                    .autocorrectionDisabled()
            }
            Spacer(minLength: 0)
        }
        .frame(height: 52)
        .overlay(alignment: .bottom) { hairline }
    }

    // MARK: 正文

    private var editor: some View {
        TextEditor(text: $content)
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
    }

    private var hairline: some View {
        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1).padding(.horizontal, 16)
    }

    // MARK: 保存

    private func saveAndClose() {
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