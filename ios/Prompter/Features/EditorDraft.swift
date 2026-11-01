import Foundation
import SwiftData
import SwiftUI

@MainActor
final class EditorDraft: ObservableObject {
    struct Value: Equatable {
        var title = ""
        var content = ""
        var folder: String?
    }
    @Published var value = Value()
    @Published private(set) var loaded = false
    @Published private(set) var saveError: String?
    private var saved = Value()
    private var record: Script?
    var hasChanges: Bool { value != saved }

    func load(_ script: Script?) {
        guard !loaded else { return }
        record = script
        value = Value(title: script?.title ?? "", content: script?.content ?? "", folder: script?.folder)
        saved = value; loaded = true
    }

    func save(in context: ModelContext) throws {
        guard loaded, hasChanges else { return }
        guard record?.deletedAt == nil else { return }
        let title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if record == nil && title.isEmpty && value.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saved = value; return
        }
        let previous = record.map(ScriptSnapshot.init)
        let isNew = record == nil
        let script = record ?? Script()
        if isNew { context.insert(script) }
        script.title = title.isEmpty ? "未命名稿件" : title
        script.content = value.content; script.folder = value.folder; script.updatedAt = Date()
        do {
            try context.save()
            record = script; saved = value; saveError = nil
        } catch {
            if isNew { context.delete(script) } else { previous?.apply(to: script) }
            saveError = "未能保存，请重试。\n\(error.localizedDescription)"
            throw error
        }
    }

    func paste(_ text: String) {
        guard !text.isEmpty else { return }
        value.content += value.content.isEmpty ? text : "\n\n" + text
    }

    func split(_ segments: [String], in context: ModelContext) throws -> [Script] {
        guard segments.count >= 2 else { return [] }
        try save(in: context)
        guard let record, record.deletedAt == nil else { return [] }
        return try ScriptOperations().split(segments, replacing: record, in: context)
    }
}
