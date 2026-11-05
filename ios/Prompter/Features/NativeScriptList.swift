import SwiftUI
import UIKit

/// UIKit owns swipe completion and self-sizing. SwiftUI only renders immutable row values.
@MainActor
struct NativeScriptList: UIViewRepresentable {
    struct State: Equatable {
        let rows: [ScriptLibraryState.Row]
        let summaries: [UUID: ScriptLibraryState.Summary]
        let wordsPerMinute: Int
        let selecting: Bool
        let selected: Set<UUID>
        let highlighted: UUID?

        /// Headings depend only on their own count; card options belong to that card.
        func reconfiguredRowIDs(from previous: State?) -> [ScriptLibraryState.RowID] {
            guard let previous else { return rows.map(\.id) }
            let oldRows = Dictionary(uniqueKeysWithValues: previous.rows.map { ($0.id, $0) })
            return rows.compactMap { row in
                if oldRows[row.id] != row { return row.id }
                guard case .script(let script) = row else { return nil }
                let id = script.id
                let changed = wordsPerMinute != previous.wordsPerMinute || selecting != previous.selecting
                    || selected.contains(id) != previous.selected.contains(id)
                    || (highlighted == id && !selecting) != (previous.highlighted == id && !previous.selecting)
                    || summaries[id] != previous.summaries[id]
                return changed ? row.id : nil
            }
        }
    }
    let state: State
    let onAction: (ScriptCardView.Action, UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITableView {
        let table = MountedTableView(frame: .zero, style: .plain)
        table.accessibilityIdentifier = "script.list"
        table.backgroundColor = UIColor(Color.canvas)
        table.separatorStyle = .none
        // Let cards scroll underneath the home-indicator area, while keeping the
        // last row reachable above it. SwiftUI reserves the temporary action shelf.
        table.contentInsetAdjustmentBehavior = .automatic
        table.keyboardDismissMode = .interactive
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 190
        table.sectionHeaderTopPadding = 0
        table.selfSizingInvalidation = .enabledIncludingConstraints
        table.allowsSelection = false
        table.register(UITableViewCell.self, forCellReuseIdentifier: "heading")
        table.register(UITableViewCell.self, forCellReuseIdentifier: "script")
        context.coordinator.attach(table)
        return table
    }
    func updateUIView(_ table: UITableView, context: Context) { context.coordinator.update(self) }

    static func dismantleUIView(_ uiView: UITableView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Notify only on mounting/size changes, not for every contentOffset update.
    @MainActor final class MountedTableView: UITableView {
        var onLayoutReady: (() -> Void)?
        private var lastSize = CGSize.zero
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onLayoutReady?() }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size != lastSize {
                lastSize = bounds.size
                if window != nil { onLayoutReady?() }
            }
        }
    }

    @MainActor final class Coordinator: NSObject, UITableViewDelegate {
        private final class DataSource: UITableViewDiffableDataSource<Int, ScriptLibraryState.RowID> {
            var isEditable: (IndexPath) -> Bool = { _ in false }
            override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { isEditable(indexPath) }
        }
        private var owner: NativeScriptList
        private weak var table: UITableView?
        private var dataSource: DataSource!
        private var current: State?
        private var rows: [ScriptLibraryState.RowID: ScriptLibraryState.Row] = [:]
        private var pending: State?
        private var applying = false
        private var attached = false
        private var flushScheduled = false
        private var swiping = false
        private var swipeAction: (ScriptCardView.Action, UUID)?

        init(_ owner: NativeScriptList) { self.owner = owner }

        func attach(_ table: UITableView) {
            self.table = table; attached = true
            (table as? MountedTableView)?.onLayoutReady = { [weak self] in self?.scheduleFlush() }
            table.delegate = self
            dataSource = DataSource(tableView: table) { [weak self] table, indexPath, id in
                guard let self, let row = self.rows[id], let state = self.current else { return nil }
                let reuse: String
                switch row { case .heading: reuse = "heading"; case .script: reuse = "script" }
                let cell = table.dequeueReusableCell(withIdentifier: reuse, for: indexPath)
                cell.selectionStyle = .none
                cell.backgroundConfiguration = .clear()
                cell.contentConfiguration = UIHostingConfiguration { [weak self] in
                    if let self { self.content(row, state: state).id(id).environment(\.colorScheme, .dark) }
                }.margins(.all, 0)
                return cell
            }
            dataSource.isEditable = { [weak self] in self?.canEdit(at: $0) == true }
            update(owner)
        }

        func detach() {
            attached = false
            (table as? MountedTableView)?.onLayoutReady = nil
            table?.delegate = nil
            table?.dataSource = nil
            table = nil; dataSource = nil
            pending = nil; current = nil; rows.removeAll()
            swipeAction = nil; swiping = false; applying = false
        }

        private func scheduleFlush() {
            guard attached, pending != nil, !applying, !flushScheduled else { return }
            flushScheduled = true
            // UIKit may notify from inside a layout pass; do not apply a snapshot reentrantly.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.flushScheduled = false
                self.flush()
            }
        }

        func update(_ owner: NativeScriptList) {
            self.owner = owner
            if owner.state == current && pending == nil { return }
            pending = owner.state
            // A filter/sort/edit may arrive while actions are revealed. Close them so
            // the pending revision cannot remain hidden behind an idle editing session.
            if swiping, table?.window != nil { table?.setEditing(false, animated: true) }
            flush()
        }

        private func flush() {
            // makeUIView/updateUIView can run before the list enters a window. Keep only
            // the latest revision until it has real geometry, traits and safe-area values.
            guard attached, !swiping, !applying, let next = pending, let table,
                  table.window != nil, table.bounds.width > 0, table.bounds.height > 0 else { return }
            pending = nil
            let oldRows = rows, old = current
            let oldIDs = dataSource.snapshot().itemIdentifiers
            let newIDs = next.rows.map(\.id)
            let newRows = Dictionary(uniqueKeysWithValues: next.rows.map { ($0.id, $0) })
            let changedIDs = oldIDs == newIDs ? next.reconfiguredRowIDs(from: old) : []
            if oldIDs == newIDs && changedIDs.isEmpty {
                current = next; rows = newRows
                return
            }
            // Keep an unchanged visible row anchored when an item moves between distant groups.
            let anchor = (table.indexPathsForVisibleRows ?? []).sorted().compactMap { indexPath -> (ScriptLibraryState.RowID, CGFloat)? in
                guard let id = dataSource.itemIdentifier(for: indexPath), newRows[id] == oldRows[id] else { return nil }
                return (id, table.rectForRow(at: indexPath).minY - table.contentOffset.y)
            }.first
            current = next; rows = newRows; applying = true
            var snapshot = NSDiffableDataSourceSnapshot<Int, ScriptLibraryState.RowID>()
            snapshot.appendSections([0]); snapshot.appendItems(newIDs)
            let completion = { [weak self, weak table] in
                guard let self, self.attached, let table, self.table === table else { return }
                defer { self.applying = false; self.flush() }
                // A sheet/navigation transition can detach the view before completion.
                guard table.window != nil else { return }
                table.layoutIfNeeded()
                if oldIDs != newIDs, let (id, distance) = anchor, let index = self.dataSource.indexPath(for: id) {
                    let maximum = max(-table.adjustedContentInset.top,
                                      table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
                    let offset = min(maximum, max(-table.adjustedContentInset.top, table.rectForRow(at: index).minY - distance))
                    table.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                }
            }
            UIView.performWithoutAnimation {
                if oldIDs != newIDs {
                    // A swipe can move AND resize a row. Rebuild native row measurements
                    // atomically after editing ends, rather than combining a move with stale sizing.
                    dataSource.applySnapshotUsingReloadData(snapshot, completion: completion)
                } else {
                    snapshot.reconfigureItems(changedIDs)
                    dataSource.apply(snapshot, animatingDifferences: false, completion: completion)
                }
            }
        }

        @ViewBuilder private func content(_ row: ScriptLibraryState.Row, state: State) -> some View {
            switch row {
            case .heading(let group, let count):
                HStack {
                    Text(group.title)
                    Spacer()
                    Text("\(count) 篇")
                }
                .font(.caption).foregroundStyle(.textSecondary).frame(minHeight: 34)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
                .accessibilityElement(children: .contain).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("script.section.\(group.rawValue)")
            case .script(let script):
                ScriptCardView(script: script, wordsPerMinute: state.wordsPerMinute, summary: state.summaries[script.id],
                               selectMode: state.selecting, isSelected: state.selected.contains(script.id),
                               highlighted: script.id == state.highlighted && !state.selecting) { [weak self] action in
                    self?.owner.onAction(action, script.id)
                }.padding(.horizontal, 16).padding(.bottom, 10)
            }
        }

        func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
            if let id = dataSource.itemIdentifier(for: indexPath), case .heading = rows[id] { return 46 }
            return 190
        }
        private func canEdit(at indexPath: IndexPath) -> Bool {
            guard owner.state.selecting == false, let id = dataSource.itemIdentifier(for: indexPath),
                  case .script = rows[id] else { return false }
            return true
        }
        func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) { swiping = true }
        func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
            swiping = false
            let action = swipeAction; swipeAction = nil
            if let (kind, id) = action { owner.onAction(kind, id) }
            flush()
        }
        func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            swipeConfiguration(at: indexPath, delete: false)
        }
        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            swipeConfiguration(at: indexPath, delete: true)
        }
        private func swipeConfiguration(at indexPath: IndexPath, delete: Bool) -> UISwipeActionsConfiguration? {
            guard !owner.state.selecting, let id = dataSource.itemIdentifier(for: indexPath),
                  case .script(let script) = rows[id] else { return nil }
            let title = delete ? "删除" : script.isFilmed ? "取消已拍" : "已拍摄"
            let action = UIContextualAction(style: .normal, title: title) { [weak self] _, _, completion in
                guard let self, let table = self.table else { completion(false); return }
                self.swipeAction = (delete ? .delete : .toggleFilmed, script.id)
                // End UIKit's swipe before changing the model, order, or intrinsic card size.
                completion(true)
                table.setEditing(false, animated: true)
            }
            action.backgroundColor = delete ? UIColor(Color.accentGold) : script.isFilmed ? .systemGray : .systemGreen
            let symbol = delete ? "trash" : script.isFilmed ? "arrow.uturn.backward" : "checkmark"
            action.image = UIImage(systemName: symbol)?.withTintColor(delete ? UIColor(Color.canvas) : .white, renderingMode: .alwaysOriginal)
            let result = UISwipeActionsConfiguration(actions: [action]); result.performsFirstActionWithFullSwipe = !delete
            return result
        }
    }
}
