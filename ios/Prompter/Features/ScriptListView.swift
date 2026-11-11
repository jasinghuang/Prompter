import SwiftUI
import SwiftData

private enum LibrarySheet: Identifiable {
    case editor(Script?), folders([Script]), export(LibraryExportRequest), archive(LibraryTransferCoordinator.Incoming)
    var id: String {
        switch self {
        case .editor(let script): return "editor.\(script?.id.uuidString ?? "new")"
        case .folders(let scripts): return "folders." + scripts.map { $0.id.uuidString }.sorted().joined()
        case .export(let request): return "export." + request.id.uuidString
        case .archive(let incoming): return "archive." + incoming.id.uuidString
        }
    }
    var detents: Set<PresentationDetent> {
        switch self {
        case .editor: return [.fraction(0.85), .large]
        case .folders: return [.medium, .large]
        case .export, .archive: return [.large]
        }
    }
}

struct ScriptListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var transfers: LibraryTransferCoordinator
    @Query(filter: #Predicate<Script> { $0.deletedAt == nil }, sort: \Script.createdAt, order: .reverse) private var scripts: [Script]
    @StateObject private var library = ScriptLibraryState()
    @StateObject private var operations = ScriptOperations()
    @State private var sheet: LibrarySheet?
    @State private var playingScript: Script?
    @State private var lastOpenedID: UUID?
    @State private var confirmDelete = false
    @State private var deleteTargets: [Script] = []
    @State private var lastUndoCount = 0
    @State private var lastShelfMode = ActionShelfMode()
    @State private var libraryVisible = false
    #if DEBUG
    @State private var didAutoOpenPlayer = false
    #endif

    private var selectedScripts: [Script] { scripts.filter { library.selected.contains($0.id) } }

    private struct ActionShelfMode: Equatable {
        var undo = false
        var selection = false
        var visible: Bool { undo || selection }
    }

    var body: some View {
        let projection = library.projection(in: scripts)
        let rows = projection.rows
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScriptLibraryControls(library: library, totalCount: scripts.count,
                                      visibleCount: projection.visibleIDs.count,
                                      isPresentingContent: sheet != nil || playingScript != nil,
                                      onExport: { requestExport(onlySelected: library.selecting) })
                Group {
                    if rows.isEmpty {
                        ScrollView { emptyState }
                    } else {
                        NativeScriptList(state: .init(rows: rows, summaries: library.summaries,
                            wordsPerMinute: settings.data.scrollSpeed, selecting: library.selecting,
                            selected: library.selected, highlighted: lastOpenedID)) { action, id in
                                guard let script = scripts.first(where: { $0.id == id }) else { return }
                                handle(action, script)
                            }
                            .ignoresSafeArea(.container, edges:
                                operations.undoItems.isEmpty && !library.selecting ? .bottom : [])
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actionShelf(visibleIDs: projection.visibleIDs)
                }
            }
            .background(Color.canvas)
            .onAppear { libraryVisible = true; presentPendingArchive() }
            .onDisappear { libraryVisible = false }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $playingScript) { script in
                PlayerView(script: script)
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $sheet, onDismiss: presentPendingArchive) { destination in
            sheetContent(destination)
                .presentationDetents(destination.detents)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.canvas)
        }
        .onChange(of: transfers.pending.first?.id) { _, _ in presentPendingArchive() }
        .onChange(of: confirmDelete) { _, showing in if !showing { presentPendingArchive() } }
        .onChange(of: operations.errorMessage) { _, message in if message == nil { presentPendingArchive() } }
        .onChange(of: transfers.errorMessage) { _, message in if message == nil { presentPendingArchive() } }
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
        .onChange(of: operations.undoItems.count, initial: true) { _, count in
            if count > 0 { lastUndoCount = count }
        }
        .task {
            operations.purgeExpired(in: context)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openPlayer"), playingScript == nil, !didAutoOpenPlayer {
                didAutoOpenPlayer = true
                playingScript = scripts.max { $0.content.count < $1.content.count }
            }
            #endif
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image("Logo").resizable().frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
                Text(library.selecting ? "已选 \(library.selected.count) 篇" : "我的稿件")
                    .font(.title2.bold()).foregroundStyle(.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if library.selecting {
                    Button("完成") { library.exitSelection() }.frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("select.exit")
                } else {
                    Button(role: .destructive) { requestDelete(scripts) } label: {
                        Image(systemName: "trash").font(.system(size: 18)).frame(width: 44, height: 44)
                    }.buttonStyle(PressableStyle()).disabled(scripts.isEmpty)
                        .accessibilityLabel("清空全部稿件").accessibilityIdentifier("library.clear")
                    Button { sheet = .editor(nil) } label: {
                        Text("新建稿件").font(.body.weight(.semibold))
                            .foregroundStyle(Color.canvas)
                            .fixedSize().padding(.horizontal, 16).frame(minHeight: 44)
                            .background(Color.accentGold, in: Capsule())
                    }
                    .buttonStyle(PressableStyle()).accessibilityLabel("新建稿件")
                }
            }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
    }

    private func actionShelf(visibleIDs: [UUID]) -> some View {
        let mode = ActionShelfMode(undo: !operations.undoItems.isEmpty, selection: library.selecting)
        let displayed = mode.visible ? mode : lastShelfMode
        return ActionBarPresence(visible: mode.visible) {
            // One presence lifetime prevents batch-delete from temporarily reserving two shelves
            // while the old selection bar leaves and the new undo bar enters.
            VStack(spacing: 8) {
                if displayed.undo { undoBar }
                if displayed.selection { selectionBar(visibleIDs: visibleIDs) }
            }.padding(.horizontal, 16).padding(.vertical, 8)
        }
        .onChange(of: mode, initial: true) { _, new in
            if new.visible { lastShelfMode = new }
        }
    }

    private func selectionBar(visibleIDs: [UUID]) -> some View {
        let ids = Set(visibleIDs)
        let allVisibleSelected = !ids.isEmpty && ids.isSubset(of: library.selected)
        return HStack(spacing: 8) {
            Button(allVisibleSelected ? "取消全选" : "全选") {
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
                Text("已删除 \(operations.undoItems.isEmpty ? lastUndoCount : operations.undoItems.count) 篇").font(.subheadline)
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
        case .export(let request): LibraryExportView(request: request)
        case .archive(let incoming):
            LibraryImportView(incoming: incoming) {
                operations.dismissUndo()
                library.exitSelection()
            }
        }
    }

    private func presentPendingArchive() {
        guard libraryVisible, sheet == nil, playingScript == nil, !confirmDelete,
              operations.errorMessage == nil, transfers.errorMessage == nil,
              let incoming = transfers.takeNext() else { return }
        sheet = .archive(incoming)
    }

    private func requestExport(onlySelected: Bool) {
        do {
            let records = try (onlySelected ? selectedScripts : scripts).map { try LibraryArchive.Record(ScriptSnapshot($0)) }
            guard !records.isEmpty else { return }
            let ids = Set(library.projection(in: scripts).visibleIDs)
            let title: String
            switch library.filter {
            case .all: title = "当前范围"
            case .starred: title = "星标稿件"
            case .folder(let name): title = name
            }
            sheet = .export(LibraryExportRequest(records: records, currentIDs: ids, currentTitle: title,
                onlySelected: onlySelected, prefersCurrent: library.filter != .all && !ids.isEmpty))
        } catch { operations.errorMessage = error.localizedDescription }
    }

    private func handle(_ action: ScriptCardView.Action, _ script: Script) {
        switch action {
        case .open: lastOpenedID = script.id; playingScript = script
        case .edit: sheet = .editor(script)
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
}
