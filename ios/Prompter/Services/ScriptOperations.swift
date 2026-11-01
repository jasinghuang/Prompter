import Foundation
import SwiftData
import SwiftUI

/// Value snapshots survive saves and never retain an invalidated SwiftData object.
struct ScriptSnapshot: Equatable {
    let id: UUID
    let title: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let starred: Bool
    let folder: String?
    let isFilmed: Bool
    let deletedAt: Date?

    init(_ script: Script) {
        id = script.id; title = script.title; content = script.content
        createdAt = script.createdAt; updatedAt = script.updatedAt
        starred = script.starred; folder = script.folder
        isFilmed = script.isFilmed; deletedAt = script.deletedAt
    }

    func apply(to script: Script) {
        script.title = title; script.content = content
        script.createdAt = createdAt; script.updatedAt = updatedAt
        script.starred = starred; script.folder = folder
        script.isFilmed = isFilmed; script.deletedAt = deletedAt
    }
}

@MainActor
final class ScriptOperations: ObservableObject {
    // Internal tombstone cleanup for database compatibility; no deleted-items browser is exposed.
    private static let retentionDays = 30
    @Published private(set) var undoItems: [ScriptSnapshot] = []
    @Published var errorMessage: String?
    private var undoTask: Task<Void, Never>?
    private var undoID: UUID?

    @discardableResult
    func update(_ scripts: [Script], in context: ModelContext, change: (Script) -> Void) -> Bool {
        errorMessage = nil
        let snapshots = scripts.map(ScriptSnapshot.init)
        scripts.forEach(change)
        do { try context.save(); return true }
        catch {
            for (script, snapshot) in zip(scripts, snapshots) { snapshot.apply(to: script) }
            errorMessage = "未能保存更改，请重试。\n\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func delete(_ scripts: [Script], in context: ModelContext, undoDuration: Duration = .seconds(8)) -> Bool {
        let targets = scripts.filter { $0.deletedAt == nil }
        guard !targets.isEmpty else { return false }
        let snapshots = targets.map(ScriptSnapshot.init)
        guard update(targets, in: context, change: { $0.deletedAt = Date() }) else { return false }
        undoTask?.cancel()
        let operationID = UUID()
        undoID = operationID
        undoItems = snapshots
        undoTask = Task { [weak self] in
            do { try await Task.sleep(for: undoDuration) } catch { return }
            guard let self, self.undoID == operationID else { return }
            self.dismissUndo()
        }
        return true
    }

    @discardableResult
    func undo(in context: ModelContext) -> Bool {
        let ids = Set(undoItems.map(\.id))
        guard !ids.isEmpty else { return false }
        do {
            let targets = try context.fetch(FetchDescriptor<Script>()).filter { ids.contains($0.id) }
            guard targets.count == ids.count else {
                errorMessage = "部分稿件已无法撤销，请重试。"
                return false
            }
            let snapshots = Dictionary(uniqueKeysWithValues: undoItems.map { ($0.id, $0) })
            guard update(targets, in: context, change: { script in
                snapshots[script.id]?.apply(to: script)
            }) else { return false }
            dismissUndo()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func dismissUndo() {
        undoTask?.cancel(); undoTask = nil; undoID = nil; undoItems = []
    }

    @discardableResult
    func move(_ scripts: [Script], to folder: String?, in context: ModelContext) -> Bool {
        let cleaned = folder?.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = cleaned?.isEmpty == true ? nil : cleaned
        return update(scripts, in: context) { script in
            guard script.folder != destination else { return }
            script.folder = destination; script.updatedAt = Date()
        }
    }

    /// Replace the active source and create its segments in one save. A failed save restores the source.
    func split(_ segments: [String], replacing original: Script, in context: ModelContext) throws -> [Script] {
        guard segments.count >= 2, original.deletedAt == nil else { return [] }
        let previous = ScriptSnapshot(original)
        let inserted = segments.map {
            Script(title: Splitter.titleOfSegment($0), content: $0, folder: original.folder,
                   starred: original.starred, isFilmed: original.isFilmed)
        }
        inserted.forEach(context.insert)
        original.deletedAt = Date()
        do { try context.save(); return inserted }
        catch { inserted.forEach(context.delete); previous.apply(to: original); throw error }
    }

    /// Run before showing editable content. Expired entries never include active scripts.
    func purgeExpired(in context: ModelContext, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        do {
            let expired = try context.fetch(FetchDescriptor<Script>()).filter { ($0.deletedAt ?? .distantFuture) <= cutoff }
            guard !expired.isEmpty else { return }
            expired.forEach(context.delete)
            do { try context.save() } catch { context.rollback(); throw error }
        } catch { errorMessage = "清理已删除数据失败：\(error.localizedDescription)" }
    }
}
