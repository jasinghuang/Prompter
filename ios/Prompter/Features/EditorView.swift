import SwiftUI
import SwiftData

/// 编辑页（M2）：标题 / 分组 / 拆分 / 暂停 / 正文——自定义深色视觉 + 常驻关键词框
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

    // 拆分/暂停：本地 state
    @State private var splitMode: SplitMode = .paragraph
    @State private var pauseMode: PauseMode = .off

    var body: some View {
        VStack(spacing: 0) {
            // 自定义拖拽指示条
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 4)
            titleRow
            folderRow
            splitRow
            pauseRow
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
            TextField("稿件标题", text: $title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 分组行

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
                    folderChip("未分组", active: folder == nil) { folder = nil }
                    ForEach(folders, id: \.self) { name in
                        folderChip(name, active: folder == name) { folder = name }
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

    private func folderChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
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
        folder = name
    }

    // MARK: 拆分行

    private var splitRow: some View {
        HStack(spacing: 10) {
            Label("拆分", systemImage: "scissors")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 16)
            Picker("", selection: $splitMode) {
                ForEach(SplitMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 100, height: 32)
            // 关键词框常驻：未选关键词时灰色，位置大小不变
            keyField("关键词", text: $settings.data.splitKeyword, enabled: splitMode == .keyword)
                .frame(maxWidth: 110)
            Spacer(minLength: 8)
                Button(action: performSplit) {
                    Text("智能拆分")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.canvas)
                        .lineLimit(1)
                        .fixedSize()
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
    }

    // MARK: 暂停行

    private var pauseRow: some View {
        HStack(spacing: 10) {
            Label("暂停", systemImage: "pause.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 16)
            Picker("", selection: $pauseMode) {
                ForEach(PauseMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 140, height: 32)
            // 关键词框常驻：未选关键词时灰色
            keyField("关键词", text: $settings.data.pauseKeyword, enabled: pauseMode == .keyword)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { hairline }
    }

    /// 常驻关键词输入框：enabled 时可输入（白色边框），disabled 时灰色（不可输入但占位不变）
    private func keyField(_ placeholder: String, text: Binding<String>, enabled: Bool) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 13))
            .foregroundStyle(enabled ? .white : .white.opacity(0.3))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                Color.white.opacity(enabled ? 0.05 : 0.03),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(enabled ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )
            .autocorrectionDisabled()
            .disabled(!enabled)
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