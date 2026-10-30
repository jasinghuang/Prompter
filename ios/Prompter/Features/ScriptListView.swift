import SwiftUI
import SwiftData

/// 稿件列表页（M1）：筛选 chips / 排序 / 卡片网格 / 删除撤销 / 剪贴板导入导出
struct ScriptListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Script.createdAt, order: .reverse) private var scripts: [Script]
    @EnvironmentObject private var settings: AppSettings

    @State private var query = ""
    @State private var filter: String = "all" // all / starred / 文件夹名
    @State private var sortKey: SortKey = .date
    @State private var sortAsc = false

    @State private var editingScript: Script?
    @State private var creatingNew = false
    @State private var playingScript: Script?

    @State private var confirmClearAll = false
    // 删除撤销（单篇；批量在 M4 泛化）
    @State private var undoItems: [UndoSnapshot] = []
    @State private var showUndo = false

    // 剪贴板导入
    @State private var pendingPayload: ExportPayload?
    @State private var showImportPrompt = false
    @State private var importCount = 0
    @State private var pasteboardChecked = false

    struct UndoSnapshot {
        let script: Script
        let starred: Bool
        let isFilmed: Bool
    }

    // MARK: 派生数据

    private var folders: [String] {
        Array(Set(scripts.compactMap(\.folder))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var visible: [Script] {
        var list = scripts
        if filter == "starred" { list = list.filter(\.starred) }
        else if filter != "all" { list = list.filter { $0.folder == filter } }
        let q = query.lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q) || $0.content.lowercased().contains(q)
            }
        }
        let dir = sortAsc ? 1 : -1
        list.sort { a, b in
            switch sortKey {
            case .title: return dir * a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .chars:
                let ac = PrompterCore.readableCharCount(a.content)
                let bc = PrompterCore.readableCharCount(b.content)
                return dir * (ac - bc) < 0
            case .date: return dir * a.createdAt.compare(b.createdAt) == .orderedAscending
            }
        }
        // 分层稳定分区：星标未拍 → 未拍 → 星标已拍 → 已拍（沉底）
        return list.sorted {
            PrompterCore.tier(starred: $0.starred, filmed: $0.isFilmed)
                < PrompterCore.tier(starred: $1.starred, filmed: $1.isFilmed)
        }
    }

    // MARK: 视图

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    if !scripts.isEmpty {
                        filterChips
                        toolbar
                    }
                    if visible.isEmpty {
                        emptyState
                    } else {
                        cardsGrid
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(Color.canvas)
            .navigationBarHidden(true)
            .overlay(alignment: .top) { undoPill }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editingScript) { script in
            EditorView(script: script)
        }
        .sheet(isPresented: $creatingNew) {
            EditorView(script: nil)
        }
        .fullScreenCover(item: $playingScript) { script in
            PlayerView(script: script)
        }
        .confirmationDialog("确认清空全部稿件？", isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("删除全部 \(scripts.count) 篇", role: .destructive) { deleteAll() }
            Button("取消", role: .cancel) {}
        }
        .alert("检测到提词器数据", isPresented: $showImportPrompt) {
            Button("导入") { importPending() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("剪贴板中有 \(pendingPayload?.scripts?.count ?? 0) 篇稿件数据，要导入吗？")
        }
        .task { checkPasteboardOnce() }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "quote.bubble.fill")
                .foregroundStyle(.accentGold)
                .font(.system(size: 22))
            Text("提词器").font(.system(size: 16, weight: .bold))
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.4)).font(.system(size: 13))
                TextField("搜索稿件…", text: $query)
                    .foregroundStyle(.white)
                    .font(.system(size: 14))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12)
            .frame(height: CTL.t2)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
            .frame(width: query.isEmpty ? 150 : 220)
            Menu {
                Button {
                    if let payload = MigrationService.pasteboardString().flatMap(MigrationService.decode(_:)) {
                        pendingPayload = payload
                        showImportPrompt = true
                    }
                } label: { Label("从剪贴板导入", systemImage: "doc.on.clipboard") }
                Button {
                    MigrationService.copyToPasteboard(
                        MigrationService.exportJSON(scripts: scripts, settings: settings.data)
                    )
                } label: { Label("拷贝导出数据", systemImage: "doc.on.doc") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: CTL.t2, height: CTL.t2)
            }
            Button {
                creatingNew = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                    Text("新建稿件").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Color.canvas)
                .padding(.horizontal, 14)
                .frame(height: CTL.t2)
                .background(Color.accentGold, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: 筛选 chips（T2 40px）

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(active: filter == "all", height: CTL.t2, fontSize: 14) {
                    setFilter("all")
                } label: {
                    Text("全部")
                    CountBadge(text: "\(scripts.count)")
                }
                FilterChip(active: filter == "starred", height: CTL.t2, fontSize: 14) {
                    setFilter("starred")
                } label: {
                    Image(systemName: "star.fill").font(.system(size: 11))
                    Text("星标")
                }
                ForEach(folders, id: \.self) { folder in
                    FilterChip(active: filter == folder, height: CTL.t2, fontSize: 14) {
                        setFilter(folder)
                    } label: {
                        Image(systemName: "folder.fill").font(.system(size: 11))
                        Text(folder)
                        CountBadge(text: "\(scripts.filter { $0.folder == folder }.count)")
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func setFilter(_ value: String) {
        withAnimation(.easeInOut(duration: 0.2)) { filter = value }
    }

    // MARK: 工具行（T3 32px）：排序 + 导出 + 清空

    private var toolbar: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.25))
            ForEach(SortKey.allCases, id: \.self) { key in
                let active = sortKey == key
                Button {
                    if sortKey == key { sortAsc.toggle() } else { sortKey = key; sortAsc = false }
                } label: {
                    HStack(spacing: 2) {
                        Text(key.label)
                        if active { Text(sortAsc ? "↑" : "↓") }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(active ? .white : .white.opacity(0.4))
                    .padding(.horizontal, 12)
                    .frame(height: CTL.t3)
                    .background(active ? Color.white.opacity(0.15) : Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Button {
                MigrationService.copyToPasteboard(
                    MigrationService.exportJSON(scripts: scripts, settings: settings.data)
                )
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .frame(height: CTL.t3)
            }
            .buttonStyle(.plain)
            Button {
                confirmClearAll = true
            } label: {
                Label("清空全部", systemImage: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentGold.opacity(0.8))
                    .padding(.horizontal, 10)
                    .frame(height: CTL.t3)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 14)
    }

    // MARK: 卡片网格

    private var cardsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
            ForEach(visible) { script in
                ScriptCardView(
                    script: script,
                    wordsPerMinute: settings.data.scrollSpeed
                ) { action in
                    handleCardAction(action, script)
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func handleCardAction(_ action: ScriptCardView.Action, _ script: Script) {
        switch action {
        case .open: playingScript = script
        case .edit: editingScript = script
        case .toggleStar:
            withAnimation(.easeInOut(duration: 0.2)) { script.starred.toggle() }
        case .delete: deleteScripts([script])
        }
    }

    // MARK: 空态

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: scripts.isEmpty ? "doc.text" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.1))
            Text(scripts.isEmpty ? "暂无稿件" : "没有匹配的稿件")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
            if !scripts.isEmpty && filter != "all" {
                Button("查看全部") { setFilter("all") }
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 96)
    }

    // MARK: 删除与撤销

    private func deleteScripts(_ targets: [Script]) {
        guard !targets.isEmpty else { return }
        undoItems = targets.map { UndoSnapshot(script: $0, starred: $0.starred, isFilmed: $0.isFilmed) }
        withAnimation(.easeOut(duration: 0.22)) {
            targets.forEach(context.delete)
        }
        showUndo = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if showUndo { // 2 秒窗口结束，真正落下
                withAnimation(.easeOut(duration: 0.18)) { showUndo = false }
                undoItems = []
            }
        }
    }

    private func undoDelete() {
        for snapshot in undoItems {
            context.insert(snapshot.script)
            snapshot.script.starred = snapshot.starred
            snapshot.script.isFilmed = snapshot.isFilmed
        }
        withAnimation(.easeOut(duration: 0.18)) {
            showUndo = false
            undoItems = []
        }
    }

    @ViewBuilder
    private var undoPill: some View {
        if showUndo {
            Button {
                undoDelete()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .bold))
                    Text("撤销删除").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(Color.accentGold)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.surface.opacity(0.9), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.accentGold.opacity(0.3)))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.top, 76)
        }
    }

    private func deleteAll() {
        deleteScripts(scripts)
    }

    // MARK: 剪贴板导入

    private func checkPasteboardOnce() {
        guard !pasteboardChecked else { return }
        pasteboardChecked = true
        if let payload = MigrationService.pasteboardString().flatMap(MigrationService.decode(_:)),
           (payload.scripts?.count ?? 0) > 0 {
            pendingPayload = payload
            showImportPrompt = true
        }
    }

    private func importPending() {
        guard let payload = pendingPayload else { return }
        let count = MigrationService.importPayload(payload, into: context)
        var data = settings.data
        MigrationService.mergeSettings(payload.settings, into: &data)
        settings.data = data
        importCount = count
        pendingPayload = nil
    }
}

// MARK: - 子组件

/// T2 筛选胶囊（选中 = 白 15% 底）
struct FilterChip<Label: View>: View {
    let active: Bool
    let height: CGFloat
    let fontSize: CGFloat
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                label()
            }
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(active ? .white : .white.opacity(0.45))
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(active ? Color.white.opacity(0.15) : Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CountBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.12), in: Capsule())
    }
}
