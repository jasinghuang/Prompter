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
    @State private var lastOpenedId: UUID? // 最近打开：返回列表时其卡片金边高亮（会话级，Web 同款）
    @State private var showBlur = false
    @State private var folderPickerScript: Script?
    @State private var newFolderAlert = false
    @State private var newFolderName = "" // 独立跟踪弹窗可见性，消失即刻关模糊
    @State private var newFolderTarget: Script? // 新建文件夹的目标稿件（弹窗前先记下，弹窗期间选择器已关）

    @State private var confirmClearAll = false
    // 长按多选 + 批量操作
    @State private var selectMode = false
    @State private var selected: Set<UUID> = []
    @State private var confirmBatchDelete = false
    @State private var batchMoveOpen = false
    @State private var batchMovePending = false // 批量移动的新建文件夹正在命名
    // 删除撤销（单篇；批量在 M4 泛化）
    @State private var undoItems: [UndoSnapshot] = []
    @State private var showUndo = false
    @State private var undoCountdown = 1.0

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
        let dir = sortAsc
        list.sort { a, b in
            switch sortKey {
            case .title:
                let r = a.title.localizedStandardCompare(b.title)
                return dir ? r == .orderedAscending : r == .orderedDescending
            case .chars:
                let ac = PrompterCore.readableCharCount(a.content)
                let bc = PrompterCore.readableCharCount(b.content)
                return dir ? ac < bc : ac > bc
            case .date:
                let r = a.createdAt.compare(b.createdAt)
                return dir ? r == .orderedAscending : r == .orderedDescending
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
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        if !scripts.isEmpty {
                            if selectMode {
                                selectBar
                            } else {
                                filterChips
                                toolbar
                            }
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
                .ignoresSafeArea(.keyboard) // 键盘不推列表：防止全网格 spring 重排（真机卡顿数秒根因）
                .blur(radius: showBlur ? 8 : 0)
                // 出现=淡入；消失=瞬时（收起动画后不再拖 0.25s 淡出尾巴）
                .animation(showBlur ? .easeOut(duration: 0.25) : nil, value: showBlur)

                // 弹窗打开时：透明遮罩拦截所有背景交互，点击即刻关弹窗+模糊
                if showBlur {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if editingScript != nil { editingScript = nil }
                            if creatingNew { creatingNew = false }
                            if folderPickerScript != nil { folderPickerScript = nil }
                            if batchMoveOpen { batchMoveOpen = false }
                            showBlur = false
                        }
                        .ignoresSafeArea()
                }
            }
            .onChange(of: editingScript?.id) { _, _ in
                if editingScript == nil { showBlur = false }
            }
            .onChange(of: creatingNew) { _, _ in
                if !creatingNew { showBlur = false }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .top) { undoPill }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editingScript) { script in
            EditorView(script: script)
                .presentationDetents([.fraction(0.80), .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color.canvas)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.80)))
                .onAppear { showBlur = true }
                .onDisappear { showBlur = false }
        }
        .sheet(isPresented: $creatingNew) {
            EditorView(script: nil)
                .presentationDetents([.fraction(0.80), .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color.canvas)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.80)))
                .onAppear { showBlur = true }
                .onDisappear { showBlur = false }
        }
        .fullScreenCover(item: $playingScript) { script in
            PlayerView(script: script)
        }
        .sheet(item: $folderPickerScript) { script in
            FolderPickerSheet(
                targets: [script],
                folders: folders,
                allScripts: scripts,
                onSelect: { folder in
                    script.folder = folder
                    script.updatedAt = Date()
                    folderPickerScript = nil
                },
                onNewFolder: {
                    newFolderTarget = script // 先记目标，再关选择器弹 alert（此前读已置 nil 的选择器导致创建丢失）
                    folderPickerScript = nil
                    newFolderName = ""
                    newFolderAlert = true
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            .presentationBackground(Color.canvas)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .onAppear { showBlur = true }
            .onDisappear { showBlur = false }
        }
        .sheet(isPresented: $batchMoveOpen) {
            FolderPickerSheet(
                targets: selectedScripts,
                folders: folders,
                allScripts: scripts,
                onSelect: { folder in
                    for script in selectedScripts {
                        script.folder = folder
                        script.updatedAt = Date()
                    }
                    batchMoveOpen = false
                    exitSelectMode()
                },
                onNewFolder: {
                    // 批量新建：记目标为批量模式，关选择器弹 alert
                    newFolderTarget = nil // 标记批量（nil + batchMovePending）
                    batchMovePending = true
                    batchMoveOpen = false
                    newFolderName = ""
                    newFolderAlert = true
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            .presentationBackground(Color.canvas)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .onAppear { showBlur = true }
            .onDisappear { showBlur = false }
        }
        .onChange(of: folderPickerScript?.id) { _, _ in
            if folderPickerScript == nil { showBlur = false }
        }
        .onChange(of: batchMoveOpen) { _, open in
            if !open { showBlur = false }
        }
        .alert("新建文件夹", isPresented: $newFolderAlert) {
            TextField("文件夹名称", text: $newFolderName)
            Button("创建") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    if batchMovePending {
                        // 批量：选中项全部移入新文件夹，然后退出多选
                        for script in selectedScripts {
                            script.folder = name
                            script.updatedAt = Date()
                        }
                        selected = []
                        selectMode = false
                    } else if let script = newFolderTarget {
                        script.folder = name
                        script.updatedAt = Date()
                    }
                }
                batchMovePending = false
                newFolderTarget = nil
                newFolderName = ""
            }
            Button("取消", role: .cancel) {
                batchMovePending = false
                newFolderTarget = nil
                newFolderName = ""
            }
        }
        .confirmationDialog("确认清空全部稿件？", isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("删除全部 \(scripts.count) 篇", role: .destructive) { deleteAll() }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("确认删除选中的 \(selected.count) 篇稿件？", isPresented: $confirmBatchDelete, titleVisibility: .visible) {
            Button("删除 \(selected.count) 篇", role: .destructive) {
                let targets = selectedScripts
                exitSelectMode()
                deleteScripts(targets) // 批量撤销胶囊显示「已删除 N 篇」
            }
            Button("取消", role: .cancel) {}
        }
        .alert("检测到提词器数据", isPresented: $showImportPrompt) {
            Button("导入") { importPending() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("剪贴板中有 \(pendingPayload?.scripts?.count ?? 0) 篇稿件数据，要导入吗？")
        }
        .task {
            checkPasteboardOnce()
            #if DEBUG
            // 自动化截图验证用：-openPlayer 进入内容最长的稿件（不受排序/已拍状态被其他用例污染影响）
            if ProcessInfo.processInfo.arguments.contains("-openPlayer"), playingScript == nil,
               let longest = visible.max(by: {
                   PrompterCore.readableCharCount($0.content) < PrompterCore.readableCharCount($1.content)
               }) {
                playingScript = longest
            }
            #endif
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text("提词器").font(.system(size: 16, weight: .bold))
            Spacer(minLength: 8)
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
            .frame(maxWidth: 220)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
            .layoutPriority(0) // 空间不足时优先收缩搜索框
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
            .layoutPriority(1)
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    // MARK: 筛选 chips（T2 40px）

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(active: filter == "all", height: CTL.t2, fontSize: 14) {
                    setFilter("all")
                } label: {
                    Text("全部")
                    CountBadge(text: "\(scripts.count)", active: filter == "all")
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
                        // Web 版 FilterChip 用轮廓 Folder（size 13），不随选中变实心
                        Image(systemName: "folder").font(.system(size: 11))
                        Text(folder)
                        CountBadge(
                            text: "\(scripts.filter { $0.folder == folder }.count)",
                            active: filter == folder
                        )
                    }
                    // 显式 identifier：按钮内文字会被 a11y 合并吞掉，UI 测试靠它定位
                    .accessibilityIdentifier("chip.\(folder)")
                }
            }
            .padding(.bottom, 16) // Web: filter chips mb-4 = 16pt
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
        .padding(.bottom, 20) // 排序行与卡片之间留足呼吸空间
    }

    // MARK: 卡片网格

    private var cardsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 10)], spacing: 10) {
            ForEach(visible) { script in
                ScriptCardView(
                    script: script,
                    wordsPerMinute: settings.data.scrollSpeed,
                    folders: folders,
                    selectMode: selectMode,
                    isSelected: selected.contains(script.id),
                    highlighted: script.id == lastOpenedId && !selectMode
                ) { action in
                    handleCardAction(action, script)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97)),
                    removal: .cardExit
                ))
            }
        }
        // id 集合变化（删除/新建/筛选）时驱动补位动画——对应 Web 的 FLIP；spring 手感更顺
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: visible.map(\.id))
        .padding(.bottom, 24)
    }

    // MARK: 多选栏（长按卡片进入；占据筛选 chips + 排序行的同一位置，Web mb-5=20pt）

    private var selectedScripts: [Script] {
        scripts.filter { selected.contains($0.id) }
    }

    private var allVisibleSelected: Bool {
        !visible.isEmpty && Set(visible.map(\.id)).isSubset(of: selected)
    }

    private var selectBar: some View {
        HStack(spacing: 8) {
            Button {
                exitSelectMode()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: CTL.t3, height: CTL.t3)
                    .background(Color.surface.opacity(0.8), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("select.exit")

            Text("已选 \(selected.count) 篇")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .fixedSize()

            Button {
                let visibleIds = Set(visible.map(\.id))
                if visibleIds.isSubset(of: selected) {
                    selected.subtract(visibleIds) // 已全选 → 取消全选
                } else {
                    selected.formUnion(visibleIds)
                }
            } label: {
                Text(allVisibleSelected ? "取消全选" : "全选")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .frame(height: CTL.t3)
                    .background(Color.surface.opacity(0.8), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("select.all")

            Spacer(minLength: 8)

            Button {
                batchMoveOpen = true
            } label: {
                // 竖屏窄宽度时降级为「移动」，保证单行（系统 ViewThatFits）
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder").font(.system(size: 13))
                        Text("移动到文件夹").font(.system(size: 13, weight: .medium))
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "folder").font(.system(size: 13))
                        Text("移动").font(.system(size: 13, weight: .medium))
                    }
                }
                .lineLimit(1)
                .foregroundStyle(Color.accentGold.opacity(0.8))
                .padding(.horizontal, 12)
                .frame(height: CTL.t3)
            }
            .buttonStyle(PressableStyle())
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.3 : 1)
            .accessibilityIdentifier("batch.move")

            Button {
                confirmBatchDelete = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 13))
                    Text("删除").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.dangerRed.opacity(0.9))
                .padding(.horizontal, 12)
                .frame(height: CTL.t3)
            }
            .buttonStyle(PressableStyle())
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.3 : 1)
            .accessibilityIdentifier("batch.delete")
        }
        .padding(.bottom, 20)
    }

    private func exitSelectMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selected = []
            selectMode = false
        }
    }

    private func handleCardAction(_ action: ScriptCardView.Action, _ script: Script) {
        switch action {
        case .open:
            lastOpenedId = script.id
            playingScript = script
        case .edit: editingScript = script
        case .toggleStar:
            withAnimation(.easeInOut(duration: 0.2)) { script.starred.toggle() }
        case .toggleFilmed:
            // 右滑提交：标记/取消已拍 → 分层排序自动沉底/归位
            // 不加 withAnimation：多元素交叉淡变（勾图标/描边/底色/标题划线/沉底位移动画叠在一起）
            // 在不同图层上各自渐变 → 视觉重影；直接切换=干净利落
            script.isFilmed.toggle()
            script.updatedAt = Date()
        case .delete: deleteScripts([script])
        case .showFolderPicker:
            folderPickerScript = script
        case .longPress:
            // 长按进入多选并选中本卡（Web: LONG_PRESS_MS 500 + 本卡预选）
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectMode = true
                selected = [script.id]
            }
        case .toggleSelect:
            withAnimation(.easeInOut(duration: 0.15)) {
                if selected.contains(script.id) {
                    selected.remove(script.id)
                } else {
                    selected.insert(script.id)
                }
            }
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
        targets.forEach(context.delete) // 卡片退场+补位动画由 cardsGrid 的 animation(value:) 驱动
        undoCountdown = 1
        withAnimation(.easeOut(duration: 0.18)) { showUndo = true }
        withAnimation(.linear(duration: 4)) { undoCountdown = 0 } // 与 4 秒撤销窗口同步收尽
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if showUndo { // 4 秒窗口结束，真正落下
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
                HStack(spacing: 0) {
                    // 状态区 | 撤销区 —— 与顶栏胶囊同构（T1 壳 44pt / 内格 34pt / 分颊 1×16）
                    Text("已删除 \(undoItems.count) 篇")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                    CapsuleDivider()
                    Text("撤销")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.accentGold)
                        .padding(.horizontal, 15)
                        .frame(height: 34)
                }
                .padding(.horizontal, 5)
                .frame(height: CTL.t1)
                .background(Color.surface.opacity(0.72), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                .overlay(alignment: .bottom) { undoCountdownLine }
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8) // 悬浮于卡片之上的一层，不再像临时贴片
            }
            .buttonStyle(PressableStyle())
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.top, 72)
            .accessibilityIdentifier("undo.pill")
        }
    }

    /// 撤销窗口倒计时：胶囊底边金色细线 4 秒内收尽，直观表达时机限时
    private var undoCountdownLine: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.accentGold.opacity(0.55))
                .frame(width: geo.size.width * undoCountdown, height: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .allowsHitTesting(false)
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

/// T2 筛选胶囊：选中 = 黑底 + 金色描边 + 白字；未选中 = 白 8% 底
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
            .foregroundStyle(active ? Color.accentGold : Color.white.opacity(0.45))
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(Color.canvas, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    active ? Color.accentGold.opacity(0.5) : Color.white.opacity(0.45),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}

struct CountBadge: View {
    let text: String
    var active: Bool = false
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(active ? Color.accentGold.opacity(0.7) : Color.white.opacity(0.35))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(
                active ? Color.accentGold.opacity(0.12) : Color.white.opacity(0.06),
                in: Capsule()
            )
    }
}

// MARK: - Canvas 预览（内存库 + 演示数据，不碰真机数据）

#if DEBUG
private func makePreviewContainer(seed: Bool) -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Script.self, configurations: config)
    if seed {
        let context = ModelContext(container)
        let demo: [(String, String, String?, Bool, Bool)] = [
            ("脚本1-广发新客开户", "朋友们，广发证券新客开户福利来了！从现在起，新客来开户，可立享专属 VIP 优惠佣金。", "口播", true, false),
            ("脚本2-佣金优惠", "总有人问我，为什么我的交易更频繁了，但手续费却更省了？", "口播", false, false),
            ("脚本3-新客福利包", "新客开户即享价值约 1688 元的新客福利包。", nil, false, false),
            ("脚本4-已拍示例", "这一条已经拍完了，应当沉底显示。", "口播", false, true),
        ]
        for (title, content, folder, starred, filmed) in demo {
            context.insert(Script(title: title, content: content, folder: folder, starred: starred, isFilmed: filmed))
        }
        try? context.save()
    }
    return container
}

#Preview("有数据") {
    ScriptListView()
        .modelContainer(makePreviewContainer(seed: true))
        .environmentObject(AppSettings())
}

#Preview("空态") {
    ScriptListView()
        .modelContainer(makePreviewContainer(seed: false))
        .environmentObject(AppSettings())
}
#endif
