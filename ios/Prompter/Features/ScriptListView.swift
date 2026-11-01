import SwiftUI
import SwiftData

private enum LibrarySheet: Identifiable {
    case editor(Script?), folders([Script])
    var id: String {
        switch self {
        case .editor(let script): return "editor.\(script?.id.uuidString ?? "new")"
        case .folders(let scripts): return "folders." + scripts.map { $0.id.uuidString }.sorted().joined()
        }
    }
    var detents: Set<PresentationDetent> {
        switch self { case .editor: return [.fraction(0.85), .large]; default: return [.medium, .large] }
    }
}

struct ScriptListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var settings: AppSettings
    @Query(filter: #Predicate<Script> { $0.deletedAt == nil }, sort: \Script.createdAt, order: .reverse) private var scripts: [Script]
    @StateObject private var library = ScriptLibraryState()
    @StateObject private var operations = ScriptOperations()
    @State private var sheet: LibrarySheet?
    @State private var playingScript: Script?
    @State private var lastOpenedID: UUID?
    @State private var confirmDelete = false
    @State private var deleteTargets: [Script] = []
    @FocusState private var searchFocused: Bool

    private var visible: [Script] { library.visible(in: scripts) }
    private var selectedScripts: [Script] { scripts.filter { library.selected.contains($0.id) } }
    private var allVisibleSelected: Bool { !visible.isEmpty && Set(visible.map(\.id)).isSubset(of: library.selected) }

    var body: some View {
        let visible = library.visible(in: scripts)
        let rows = library.rows(for: visible)
        NavigationStack {
            VStack(spacing: 0) {
                header
                if !scripts.isEmpty { filters }
                List {
                    if visible.isEmpty {
                        emptyState.listRowBackground(Color.canvas).listRowSeparator(.hidden)
                    } else {
                        ForEach(rows) { row in
                            switch row {
                            case .heading(let tier, let count):
                                sectionHeading(tier: tier, count: count)
                            case .script(let script):
                                card(script)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                // A row move must not inherit the swipe action's closing animation.
                // Match by global script ID; keep scrolling and UIKit swipe gestures native.
                .transaction(value: rows.map(\.id)) { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .environment(\.defaultMinListRowHeight, 0)
                .accessibilityIdentifier("script.list")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !operations.undoItems.isEmpty || library.selecting {
                        VStack(spacing: 8) {
                            if !operations.undoItems.isEmpty { undoBar }
                            if library.selecting { selectionBar }
                        }.padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }
            }
            .background(Color.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $sheet) { destination in
            sheetContent(destination)
                .presentationDetents(destination.detents)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.canvas)
        }
        .fullScreenCover(item: $playingScript) { PlayerView(script: $0) }
        .confirmationDialog("删除这 \(deleteTargets.count) 篇稿件？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除 \(deleteTargets.count) 篇", role: .destructive) {
                if operations.delete(deleteTargets, in: context) { library.exitSelection() }
                deleteTargets = []
            }
            Button("取消", role: .cancel) { deleteTargets = [] }
        } message: { Text("删除后可在 8 秒内撤销。") }
        .alert("操作未完成", isPresented: Binding(get: { operations.errorMessage != nil }, set: { if !$0 { operations.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { operations.errorMessage = nil }
        } message: { Text(operations.errorMessage ?? "") }
        .onChange(of: scripts.map(ScriptLibraryState.Revision.init), initial: true) { _, _ in library.refresh(scripts) }
        .task {
            operations.purgeExpired(in: context)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openPlayer"), playingScript == nil {
                playingScript = scripts.max { $0.content.count < $1.content.count }
            }
            #endif
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image("Logo").resizable().frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
                Text(library.selecting ? "已选 \(library.selected.count) 篇" : "我的稿件")
                    .font(.title2.bold()).foregroundStyle(.textPrimary)
                Spacer(minLength: 4)
                if library.selecting {
                    Button("完成") { library.exitSelection() }.frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("select.exit")
                } else {
                    Button(role: .destructive) { requestDelete(scripts) } label: {
                        Image(systemName: "trash").font(.system(size: 18)).frame(width: 44, height: 44)
                    }.buttonStyle(PressableStyle()).disabled(scripts.isEmpty)
                        .accessibilityLabel("清空全部稿件").accessibilityIdentifier("library.clear")
                    Button { searchFocused = false; sheet = .editor(nil) } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.canvas).frame(width: 44, height: 44)
                            .background(Color.accentGold, in: Circle())
                    }
                    .buttonStyle(PressableStyle()).accessibilityLabel("新建稿件")
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.textMuted)
                TextField("搜索标题或正文", text: $library.query)
                    .font(.body).foregroundStyle(.textPrimary).focused($searchFocused)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .submitLabel(.search).onSubmit { searchFocused = false }
                    .accessibilityIdentifier("script.search")
                if !library.query.isEmpty {
                    Button { library.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.textMuted).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("清除搜索")
                }
            }
            .padding(.leading, 12).padding(.trailing, library.query.isEmpty ? 12 : 0)
            .frame(minHeight: 44).background(Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
    }

    private var filters: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    filterChip("全部 \(scripts.count)", value: .all)
                    filterChip("星标", icon: "star", value: .starred)
                    ForEach(library.folders, id: \.self) { name in
                        filterChip(name, icon: "folder", value: .folder(name))
                            .accessibilityIdentifier("chip.\(name)")
                    }
                }.padding(.leading, 16)
            }
            Menu {
                Picker("排序方式", selection: $library.sortKey) {
                    ForEach(SortKey.allCases, id: \.self) { key in
                        Text(key == .date ? "最近修改" : key.label).tag(key)
                    }
                }
                Button { library.sortAscending.toggle() } label: {
                    Label(library.sortAscending ? "改为降序" : "改为升序", systemImage: "arrow.up.arrow.down")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").foregroundStyle(.textSecondary).frame(width: 44, height: 44)
            }.accessibilityLabel("排序方式").padding(.trailing, 8)
        }.padding(.bottom, 2)
    }

    private func filterChip(_ title: String, icon: String? = nil, value: ScriptFilter) -> some View {
        let active = library.filter == value
        return Button { library.filter = value } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.caption) }
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(active ? Color.accentGold : .textSecondary)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(active ? Color.accentGold.opacity(0.06) : Color.canvas, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? Color.accentGold.opacity(0.5) : Color.white.opacity(0.16)))
        }.buttonStyle(PressableStyle()).accessibilityAddTraits(active ? .isSelected : [])
    }

    private func card(_ script: Script) -> some View {
        ScriptCardView(script: script, wordsPerMinute: settings.data.scrollSpeed, summary: library.summaries[script.id],
                       selectMode: library.selecting, isSelected: library.selected.contains(script.id),
                       highlighted: script.id == lastOpenedID && !library.selecting) { handle($0, script) }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.canvas).listRowSeparator(.hidden)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if !library.selecting {
                    Button { handle(.toggleFilmed, script) } label: {
                        Label(script.isFilmed ? "取消已拍" : "已拍摄", systemImage: script.isFilmed ? "arrow.uturn.backward" : "checkmark")
                    }.tint(script.isFilmed ? .gray : .green)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !library.selecting {
                    Button(role: .destructive) { handle(.delete, script) } label: {
                        Label("删除", systemImage: "trash").foregroundStyle(Color.canvas)
                    }.tint(.accentGold)
                }
            }
    }

    private func sectionHeading(tier: Int, count: Int) -> some View {
        // Ordinary, opaque rows cannot leave a second pinned header over a moving card.
        HStack {
            Text(sectionTitle(tier))
            Spacer()
            Text("\(count) 篇")
        }
        .font(.caption).foregroundStyle(.textSecondary)
        .frame(minHeight: 34)
        .background(Color.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("script.section.\(tier)")
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.canvas).listRowSeparator(.hidden)
    }

    private var selectionBar: some View {
        HStack(spacing: 8) {
            Button(allVisibleSelected ? "取消全选" : "全选") {
                let ids = Set(visible.map(\.id))
                if ids.isSubset(of: library.selected) { library.selected.subtract(ids) }
                else { library.selected.formUnion(ids) }
            }.accessibilityIdentifier("select.all").frame(minWidth: 44, minHeight: 44)
            Spacer()
            Button { sheet = .folders(selectedScripts) } label: { Label("移动", systemImage: "folder") }
                .accessibilityIdentifier("batch.move").disabled(library.selected.isEmpty).frame(minHeight: 44)
            Button(role: .destructive) { requestDelete(selectedScripts) } label: { Label("删除", systemImage: "trash") }
                .accessibilityIdentifier("batch.delete").disabled(library.selected.isEmpty).frame(minHeight: 44)
        }.buttonStyle(PressableStyle()).font(.subheadline).padding(.horizontal, 14).padding(.vertical, 5)
            .background(Color.surface, in: Capsule())
    }

    private var undoBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已删除 \(operations.undoItems.count) 篇").font(.subheadline)
                Text("8 秒内可撤销").font(.caption).foregroundStyle(.textSecondary)
            }
            Spacer(minLength: 4)
            Button { operations.undo(in: context) } label: { Label("撤销", systemImage: "arrow.uturn.backward").font(.subheadline.weight(.semibold)) }
                .frame(minHeight: 44).buttonStyle(PressableStyle()).accessibilityIdentifier("undo.pill")
        }
        .foregroundStyle(.textPrimary).padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 7)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.12)))
        .accessibilityElement(children: .contain)
        .onAppear { UIAccessibility.post(notification: .announcement, argument: "已删除，8 秒内可撤销") }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: scripts.isEmpty ? "doc.text" : "magnifyingglass").font(.largeTitle).foregroundStyle(.textMuted)
            Text(scripts.isEmpty ? "还没有稿件" : "没有匹配的稿件").font(.headline).foregroundStyle(.textPrimary)
            if scripts.isEmpty {
                Button("新建稿件") { sheet = .editor(nil) }.frame(minHeight: 44)
            } else {
                Button("查看全部") { library.query = ""; library.filter = .all }.frame(minHeight: 44)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    @ViewBuilder private func sheetContent(_ destination: LibrarySheet) -> some View {
        switch destination {
        case .editor(let script): EditorView(script: script)
        case .folders(let targets):
            FolderPickerSheet(targets: targets, folders: library.folders, counts: library.folderCounts, errorMessage: operations.errorMessage) { folder in
                if operations.move(targets, to: folder, in: context) { sheet = nil; library.exitSelection() }
            }
        }
    }

    private func handle(_ action: ScriptCardView.Action, _ script: Script) {
        switch action {
        case .open: searchFocused = false; lastOpenedID = script.id; playingScript = script
        case .edit: searchFocused = false; sheet = .editor(script)
        case .delete: operations.delete([script], in: context)
        case .toggleStar:
            operations.update([script], in: context) { $0.starred.toggle(); $0.updatedAt = Date() }
        case .toggleFilmed:
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                _ = operations.update([script], in: context) { $0.isFilmed.toggle(); $0.updatedAt = Date() }
            }
        case .showFolderPicker: sheet = .folders([script])
        case .longPress:
            library.selecting = true; library.selected.insert(script.id)
            UISelectionFeedbackGenerator().selectionChanged()
        case .toggleSelect:
            if library.selected.contains(script.id) { library.selected.remove(script.id) }
            else { library.selected.insert(script.id) }
        }
    }
    private func requestDelete(_ targets: [Script]) { deleteTargets = targets; confirmDelete = !targets.isEmpty }
    private func sectionTitle(_ tier: Int) -> String { ["星标置顶", "待拍摄", "已拍摄 · 星标", "已拍摄"][tier] }
}
