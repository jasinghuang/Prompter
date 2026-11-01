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

    struct Revision: Equatable {
        let snapshot: ScriptSnapshot
        init(_ script: Script) { snapshot = ScriptSnapshot(script) }
    }
    struct Summary {
        let content: String
        let characterCount: Int
        let excerpt: String
    }
    enum RowID: Hashable {
        case heading(Int)
        case script(UUID)
    }
    enum Row: Identifiable {
        case heading(tier: Int, count: Int)
        case script(Script)

        var id: RowID {
            switch self {
            case .heading(let tier, _): return .heading(tier)
            case .script(let script): return .script(script.id)
            }
        }
    }

    /// One identity scope: a script keeps its row when its filmed/starred tier changes.
    func rows(for visibleScripts: [Script]) -> [Row] {
        var result: [Row] = []
        for tier in 0..<4 {
            let items = visibleScripts.filter { PrompterCore.tier(starred: $0.starred, filmed: $0.isFilmed) == tier }
            guard !items.isEmpty else { continue }
            result.append(.heading(tier: tier, count: items.count))
            result.append(contentsOf: items.map(Row.script))
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
        summaries = next; folderCounts = counts; searchable = search
        selected.formIntersection(scripts.map(\.id))
        if case .folder(let name) = filter, counts[name] == nil { filter = .all }
    }

    func visible(in scripts: [Script]) -> [Script] {
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
