import Foundation
import SwiftUI

enum ScriptFilter: Hashable {
    case all, starred, folder(String)
}

/// One derived pass per data revision; long text is counted only when it changes.
@MainActor
final class ScriptLibraryState: ObservableObject {
    @Published var query = ""
    @Published var filter: ScriptFilter = .all
    @Published var sortKey: SortKey = .date
    @Published var sortAscending = false
    @Published var selecting = false
    @Published var selected: Set<UUID> = []
    @Published private(set) var summaries: [UUID: Summary] = [:]
    @Published private(set) var folderCounts: [String: Int] = [:]
    private var searchable: [UUID: String] = [:]

    /// A single bounded cache. UI-only state (selection, sheets, return highlight)
    /// does not change ordering or the immutable rows used by the native table.
    final class Projection {
        let visibleIDs: [UUID]
        let rows: [Row]
        init(visibleIDs: [UUID], rows: [Row]) { self.visibleIDs = visibleIDs; self.rows = rows }
    }
    private struct ProjectionKey: Equatable {
        let scripts: [ScriptSnapshot]
        let query: String
        let filter: ScriptFilter
        let sortKey: SortKey
        let ascending: Bool
        let summaries: [UUID: Summary]
    }
    private var cachedProjection: (key: ProjectionKey, value: Projection)?

    func projection(in scripts: [Script]) -> Projection {
        // Read current model fields even on cache hits to retain SwiftData observation
        // and detect edits that do not change updatedAt (including undo/rollback).
        let key = ProjectionKey(scripts: scripts.map(ScriptSnapshot.init), query: query,
                                filter: filter, sortKey: sortKey, ascending: sortAscending, summaries: summaries)
        if let cachedProjection, cachedProjection.key == key { return cachedProjection.value }
        let visible = computeVisible(in: scripts)
        let value = Projection(visibleIDs: visible.map(\.id), rows: rows(for: visible))
        cachedProjection = (key, value)
        return value
    }

    struct Revision: Equatable {
        let snapshot: ScriptSnapshot
        init(_ script: Script) { snapshot = ScriptSnapshot(script) }
    }
    struct Summary: Equatable {
        let content: String
        let characterCount: Int
        let excerpt: String
    }
    enum Group: Int, CaseIterable, Hashable {
        case pending, filmed
        var title: String { self == .pending ? "待拍摄" : "已拍摄" }
    }
    enum RowID: Hashable {
        case heading(Group)
        case script(UUID)
    }
    enum Row: Identifiable, Equatable {
        case heading(group: Group, count: Int)
        case script(ScriptSnapshot)

        var id: RowID {
            switch self {
            case .heading(let group, _): return .heading(group)
            case .script(let script): return .script(script.id)
            }
        }
    }

    /// Only filming status creates headings; starred ordering stays within each group.
    /// A script keeps its global row identity when its filmed/starred state changes.
    func rows(for visibleScripts: [Script]) -> [Row] {
        var result: [Row] = []
        for group in Group.allCases {
            let items = visibleScripts.filter { $0.isFilmed == (group == .filmed) }
            guard !items.isEmpty else { continue }
            result.append(.heading(group: group, count: items.count))
            result.append(contentsOf: items.map { .script(ScriptSnapshot($0)) })
        }
        return result
    }
    var folders: [String] { folderCounts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    func refresh(_ scripts: [Script]) {
        var next: [UUID: Summary] = [:]
        var counts: [String: Int] = [:]
        var search: [UUID: String] = [:]
        for script in scripts {
            next[script.id] = summaries[script.id].flatMap { $0.content == script.content ? $0 : nil }
                ?? Summary(content: script.content, characterCount: PrompterCore.readableCharCount(script.content),
                           excerpt: String(script.content.prefix(240)).replacingOccurrences(of: "\n", with: " "))
            if let folder = script.folder { counts[folder, default: 0] += 1 }
            search[script.id] = script.title + "\n" + script.content
        }
        let searchChanged = searchable != search
        searchable = search
        if summaries != next || searchChanged { summaries = next }
        if folderCounts != counts { folderCounts = counts }
        let remaining = selected.intersection(scripts.map(\.id))
        if remaining != selected { selected = remaining }
        if case .folder(let name) = filter, counts[name] == nil { filter = .all }
    }

    func visible(in scripts: [Script]) -> [Script] {
        let ids = projection(in: scripts).visibleIDs
        // Resolve current objects rather than caching live models across contexts.
        let current = Dictionary(uniqueKeysWithValues: scripts.map { ($0.id, $0) })
        return ids.compactMap { current[$0] }
    }

    private func computeVisible(in scripts: [Script]) -> [Script] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return scripts.filter { script in
            guard script.deletedAt == nil else { return false }
            let matches: Bool
            switch filter {
            case .all: matches = true
            case .starred: matches = script.starred
            case .folder(let name): matches = script.folder == name
            }
            return matches && (text.isEmpty || (searchable[script.id] ?? script.title + script.content).localizedStandardContains(text))
        }.sorted { a, b in
            let at = PrompterCore.tier(starred: a.starred, filmed: a.isFilmed)
            let bt = PrompterCore.tier(starred: b.starred, filmed: b.isFilmed)
            if at != bt { return at < bt }
            let comparison: ComparisonResult
            switch sortKey {
            case .title: comparison = a.title.localizedStandardCompare(b.title)
            case .date: comparison = a.updatedAt.compare(b.updatedAt)
            case .chars:
                let ac = summaries[a.id]?.characterCount ?? 0, bc = summaries[b.id]?.characterCount ?? 0
                comparison = ac == bc ? .orderedSame : ac < bc ? .orderedAscending : .orderedDescending
            }
            if comparison == .orderedSame { return a.id.uuidString < b.id.uuidString }
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    func exitSelection() { selecting = false; selected = [] }
}
