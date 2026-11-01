import SwiftUI
import SwiftData

struct EditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: AppSettings
    @Query(filter: #Predicate<Script> { $0.deletedAt == nil }) private var allScripts: [Script]
    let script: Script?
    @StateObject private var draft = EditorDraft()
    @State private var choosingFolder = false
    @State private var splitError: String?
    @State private var splitMode: SplitMode = .paragraph
    private enum Field: Hashable { case title, content, splitKeyword, pauseKeyword }
    @FocusState private var focusedField: Field?

    private var folders: [String] {
        var names = Set(allScripts.compactMap(\.folder))
        if let folder = draft.value.folder { names.insert(folder) }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var folderCounts: [String: Int] {
        Dictionary(grouping: allScripts.compactMap(\.folder), by: { $0 }).mapValues(\.count)
    }
    private var segments: [String] {
        splitMode == .keyword ? Splitter.byKeyword(draft.value.content, keyword: settings.data.splitKeyword)
            : Splitter.byParagraphs(draft.value.content)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("稿件标题（选填）", text: $draft.value.title, axis: .vertical)
                            .font(.title2.weight(.semibold)).foregroundStyle(.textPrimary).lineLimit(1...3)
                            .focused($focusedField, equals: .title)
                            .accessibilityLabel("稿件标题").accessibilityIdentifier("editor.title")
                        contentEditor(height: max(180, min(320, geometry.size.height * 0.4)))
                        tools
                        folderRow
                    }.padding(.horizontal, 20).padding(.vertical, 14)
                }.scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("editor.form")
                saveStatus
            }
        }
        .background(Color.canvas)
        .onAppear { draft.load(script); splitMode = SplitMode(rawValue: settings.data.splitMode) ?? .paragraph }
        .task(id: draft.value) {
            guard draft.loaded, draft.hasChanges else { return }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            _ = save()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { _ = save(); settings.flush() } }
        .onDisappear { _ = save(); settings.flush() }
        .interactiveDismissDisabled(draft.hasChanges)
        .sheet(isPresented: $choosingFolder) {
            FolderPickerSheet(targets: [], folders: folders, counts: folderCounts, initialFolder: draft.value.folder) { folder in
                draft.value.folder = folder; choosingFolder = false
            }
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationBackground(Color.canvas)
        }
        .alert("未能拆分", isPresented: Binding(get: { splitError != nil }, set: { if !$0 { splitError = nil } })) {
            Button("知道了", role: .cancel) { splitError = nil }
        } message: { Text(splitError ?? "") }
    }

    private var header: some View {
        HStack {
            Text(script == nil ? "新建稿件" : "编辑稿件").font(.headline).foregroundStyle(.textPrimary)
            Spacer()
            Button("完成") { if save() { settings.flush(); dismiss() } }
                .font(.body.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                .buttonStyle(PressableStyle()).accessibilityIdentifier("editor.done")
        }.padding(.leading, 20).padding(.trailing, 16).padding(.top, 10)
    }

    private func contentEditor(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("正文").font(.subheadline.weight(.medium)).foregroundStyle(.textSecondary)
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    draft.paste(strings.joined(separator: "\n\n"))
                    focusedField = nil
                }
                .labelStyle(.titleAndIcon).buttonBorderShape(.capsule).tint(.accentGold)
                .accessibilityLabel("粘贴正文").accessibilityIdentifier("editor.paste")
            }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            ZStack(alignment: .topLeading) {
                if draft.value.content.isEmpty {
                    Text("粘贴或输入稿件正文…")
                        .font(.body).foregroundStyle(.textMuted).padding(.horizontal, 13).padding(.top, 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                TextEditor(text: $draft.value.content)
                    .font(.body).lineSpacing(5).foregroundStyle(.textPrimary)
                    .scrollContentBackground(.hidden).padding(.horizontal, 8).padding(.bottom, 8)
                    .focused($focusedField, equals: .content).accessibilityIdentifier("editor.content")
            }
        }
        .frame(height: height)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08)))
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("拆分方式").font(.subheadline).foregroundStyle(.textSecondary).fixedSize()
                Picker("拆分方式", selection: $splitMode) {
                    ForEach(SplitMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(minWidth: 104)
                    .accessibilityIdentifier("editor.splitMode")
                splitButton
            }.frame(minHeight: 44)
            if splitMode == .keyword {
                keywordField("拆分关键词", text: $settings.data.splitKeyword, field: .splitKeyword)
            }
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.vertical, 2)
            HStack(spacing: 10) {
                Text("自动暂停").font(.subheadline).foregroundStyle(.textSecondary).fixedSize()
                Picker("自动暂停", selection: $settings.data.automaticPause) {
                    ForEach(AutoPauseMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("editor.autoPause")
            }.frame(minHeight: 44)
            if settings.data.automaticPause == .keyword {
                keywordField("暂停关键词", text: $settings.data.pauseKeyword, field: .pauseKeyword)
            }
        }.foregroundStyle(.textPrimary)
            .onChange(of: splitMode) { _, value in settings.data.splitMode = value.rawValue }
    }

    private var splitButton: some View {
        let enabled = segments.count >= 2
        return Button(action: split) {
            Text("智能拆分")
                .font(.subheadline.weight(.semibold)).fixedSize()
                .foregroundStyle(enabled ? Color.canvas : .textMuted)
                .padding(.horizontal, 12).frame(height: 32)
                .background(enabled ? Color.accentGold : .surface, in: Capsule())
                .overlay(Capsule().strokeBorder(enabled ? Color.clear : Color.white.opacity(0.08)))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled)
            .accessibilityLabel("智能拆分").accessibilityIdentifier("editor.split")
    }

    private func keywordField(_ title: String, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .font(.body).foregroundStyle(.textPrimary)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($focusedField, equals: field)
            .accessibilityIdentifier(field == .splitKeyword ? "editor.splitKeyword" : "editor.pauseKeyword")
    }

    private var folderRow: some View {
        Button { focusedField = nil; choosingFolder = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                Text("分组")
                Spacer()
                Text(draft.value.folder ?? "未分组").lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2)
            }.font(.subheadline).foregroundStyle(.textSecondary).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("选择文件夹")
            .accessibilityValue(draft.value.folder ?? "未分组")
    }

    private var saveStatus: some View {
        HStack(spacing: 8) {
            if let error = draft.saveError {
                Text(error).font(.caption).foregroundStyle(.dangerRed)
                Button("重试") { _ = save() }.font(.subheadline).frame(minWidth: 44, minHeight: 44)
            } else {
                Text(draft.hasChanges ? "正在保存…" : "已自动保存 · 仅存于本机")
                    .font(.caption).foregroundStyle(.textSecondary)
            }
        }.frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 8)
            .accessibilityIdentifier("editor.saveStatus")
    }

    @discardableResult private func save() -> Bool {
        do { try draft.save(in: context); return true } catch { return false }
    }

    private func split() {
        focusedField = nil
        let parts = segments
        guard parts.count >= 2 else { return }
        do {
            let created = try draft.split(parts, in: context)
            guard !created.isEmpty else { splitError = "稿件已无法拆分，请关闭后重试。"; return }
            settings.flush()
            UIAccessibility.post(notification: .announcement, argument: "已拆分为 \(created.count) 篇稿件")
            dismiss()
        } catch { splitError = "未能创建拆分稿件：\(error.localizedDescription)" }
    }
}
