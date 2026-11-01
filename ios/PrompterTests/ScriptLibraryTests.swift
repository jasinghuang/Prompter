import XCTest
import SwiftData
@testable import Prompter

@MainActor
final class ScriptLibraryTests: XCTestCase {
    private func store() throws -> ModelContainer {
        try ModelContainer(for: Script.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testDeletionPersistsAndUndoRestoresAllFieldsAfterSave() throws {
        let container = try store(), context = container.mainContext
        let original = Script(title: "原稿", content: "完整正文\n第二行", folder: "口播", starred: true, isFilmed: true,
                              createdAt: Date(timeIntervalSince1970: 123), updatedAt: Date(timeIntervalSince1970: 456))
        context.insert(original); try context.save()
        let snapshot = ScriptSnapshot(original), operations = ScriptOperations()
        XCTAssertTrue(operations.delete([original], in: context))
        let otherContext = ModelContext(container)
        let persisted = try XCTUnwrap(otherContext.fetch(FetchDescriptor<Script>()).first)
        XCTAssertNotNil(persisted.deletedAt)
        XCTAssertTrue(operations.undo(in: context))
        XCTAssertEqual(ScriptSnapshot(original), snapshot)
        XCTAssertTrue(operations.undoItems.isEmpty)
    }

    func testEarlierDeletionTimerCannotExpireLaterUndo() async throws {
        let container = try store(), context = container.mainContext
        let a = Script(title: "A"), b = Script(title: "B")
        context.insert(a); context.insert(b); try context.save()
        let operations = ScriptOperations()
        XCTAssertTrue(operations.delete([a], in: context, undoDuration: .milliseconds(150)))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(operations.delete([b], in: context, undoDuration: .seconds(2)))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(operations.undoItems.map(\.id), [b.id])
        XCTAssertTrue(operations.undo(in: context))
        XCTAssertNotNil(a.deletedAt)
        XCTAssertNil(b.deletedAt)
    }

    func testUndoThenNewDeletionHasItsOwnWindow() async throws {
        let container = try store(), context = container.mainContext
        let a = Script(title: "A"), b = Script(title: "B")
        context.insert(a); context.insert(b); try context.save()
        let operations = ScriptOperations()
        operations.delete([a], in: context, undoDuration: .milliseconds(150))
        XCTAssertTrue(operations.undo(in: context))
        operations.delete([b], in: context, undoDuration: .seconds(2))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(operations.undoItems.map(\.id), [b.id])
        operations.dismissUndo()
    }

    func testExpiredCleanupDoesNotDeleteActiveOrRecentScripts() throws {
        let container = try store(), context = container.mainContext
        let now = Date(), active = Script(title: "active"), recent = Script(title: "recent"), expired = Script(title: "expired")
        recent.deletedAt = now.addingTimeInterval(-2 * 86_400)
        expired.deletedAt = now.addingTimeInterval(-31 * 86_400)
        [active, recent, expired].forEach(context.insert); try context.save()
        ScriptOperations().purgeExpired(in: context, now: now)
        let titles = Set(try context.fetch(FetchDescriptor<Script>()).map(\.title))
        XCTAssertEqual(titles, ["active", "recent"])
    }

    func testBatchUndoRestoresAllItemsAndClearsUndoState() throws {
        let container = try store(), context = container.mainContext
        let items = [Script(title: "A"), Script(title: "B")]
        items.forEach(context.insert); try context.save()
        let operations = ScriptOperations()
        XCTAssertTrue(operations.delete(items, in: context))
        XCTAssertTrue(operations.undo(in: context))
        XCTAssertTrue(items.allSatisfy { $0.deletedAt == nil })
        XCTAssertTrue(operations.undoItems.isEmpty)
    }

    func testSplitReplacesActiveSourceAndKeepsRecoverableMetadata() throws {
        let container = try store(), context = container.mainContext
        let original = Script(title: "原稿", content: "甲\n\n乙", folder: "口播", starred: true)
        context.insert(original); try context.save()
        let before = ScriptSnapshot(original)
        let created = try ScriptOperations().split(Splitter.byParagraphs(original.content), replacing: original, in: context)
        XCTAssertEqual(created.map(\.content), ["甲", "乙"])
        XCTAssertTrue(created.allSatisfy { $0.folder == "口播" })
        XCTAssertNotNil(original.deletedAt)
        XCTAssertTrue(created.allSatisfy { $0.starred })
        XCTAssertEqual(ScriptLibraryState().visible(in: try context.fetch(FetchDescriptor<Script>())).count, 2)
        let deletedAt = original.deletedAt
        original.deletedAt = nil
        XCTAssertEqual(ScriptSnapshot(original), before)
        original.deletedAt = deletedAt
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Script>()), 3)
    }

    func testDraftSplitSavesLatestContentAndDoesNotRecreateSourceOnDismissal() throws {
        let container = try store(), context = container.mainContext
        let original = Script(title: "Before", content: "Old text", folder: "Old folder")
        context.insert(original); try context.save()
        let draft = EditorDraft(); draft.load(original)
        draft.value.content = "New A\n\nNew B"; draft.value.folder = "New folder"
        let parts = try draft.split(Splitter.byParagraphs(draft.value.content), in: context)
        XCTAssertEqual(parts.map(\.content), ["New A", "New B"])
        XCTAssertTrue(parts.allSatisfy { $0.folder == "New folder" })
        XCTAssertEqual(original.content, "New A\n\nNew B")
        XCTAssertNotNil(original.deletedAt)
        draft.value.content = "Late editor update"
        try draft.save(in: context)
        XCTAssertEqual(original.content, "New A\n\nNew B")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Script>()), 3)
    }

    func testUnsavedNewDraftSplitsIntoOnlyActiveSegments() throws {
        let container = try store(), context = container.mainContext
        let draft = EditorDraft(); draft.load(nil)
        draft.value.title = "Draft"; draft.value.content = "A#B"
        let parts = try draft.split(Splitter.byKeyword(draft.value.content, keyword: "#"), in: context)
        XCTAssertEqual(parts.map(\.content), ["A", "#B"])
        let all = try context.fetch(FetchDescriptor<Script>())
        XCTAssertEqual(all.filter { $0.deletedAt == nil }.count, 2)
        XCTAssertEqual(all.filter { $0.deletedAt != nil }.map(\.title), ["Draft"])
        try draft.save(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Script>()), 3)
    }

    func testInvalidOrDeletedSourceIsNotReplacedAgain() throws {
        let container = try store(), context = container.mainContext
        let original = Script(title: "Original", content: "A\n\nB")
        context.insert(original); try context.save()
        let operations = ScriptOperations()
        XCTAssertTrue(try operations.split(["A"], replacing: original, in: context).isEmpty)
        XCTAssertNil(original.deletedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Script>()), 1)
        _ = try operations.split(["A", "B"], replacing: original, in: context)
        XCTAssertTrue(try operations.split(["A", "B"], replacing: original, in: context).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Script>()), 3)
    }

    func testEditorDoesNotChangeModificationDateWhenUntouched() throws {
        let container = try store(), context = container.mainContext
        let original = Script(title: "未改动", content: "正文", updatedAt: Date(timeIntervalSince1970: 100))
        context.insert(original); try context.save()
        let draft = EditorDraft(); draft.load(original)
        try draft.save(in: context)
        XCTAssertEqual(original.updatedAt, Date(timeIntervalSince1970: 100))
        XCTAssertFalse(draft.hasChanges)
    }

    func testNewDraftAutosavesIntoOneRecordAndKeepsIdentity() throws {
        let container = try store(), context = container.mainContext
        let draft = EditorDraft(); draft.load(nil)
        try draft.save(in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Script>()), 0)
        draft.value.content = "第一版"; try draft.save(in: context)
        let id = try XCTUnwrap(context.fetch(FetchDescriptor<Script>()).first?.id)
        draft.value.content = "第二版"; draft.value.folder = "口播"; try draft.save(in: context)
        let records = try context.fetch(FetchDescriptor<Script>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, id)
        XCTAssertEqual(records.first?.content, "第二版")
        XCTAssertEqual(records.first?.folder, "口播")
    }

    func testFolderNamesCannotCollideWithBuiltInFilters() {
        let a = Script(title: "文件夹 all", folder: "all"), b = Script(title: "文件夹 starred", folder: "starred")
        let c = Script(title: "真正星标", starred: true)
        let library = ScriptLibraryState(); library.refresh([a, b, c])
        library.filter = .folder("all"); XCTAssertEqual(library.visible(in: [a, b, c]).map(\.id), [a.id])
        library.filter = .folder("starred"); XCTAssertEqual(library.visible(in: [a, b, c]).map(\.id), [b.id])
        library.filter = .starred; XCTAssertEqual(library.visible(in: [a, b, c]).map(\.id), [c.id])
    }

    func testRowsKeepGlobalIdentityWhenFilmedTierAppearsAndDisappears() {
        let starred = Script(title: "星标", starred: true)
        let pending = Script(title: "待拍")
        let filmed = Script(title: "已拍", isFilmed: true)
        let scripts = [starred, pending, filmed], library = ScriptLibraryState()
        library.refresh(scripts)
        let before = library.rows(for: library.visible(in: scripts))
        XCTAssertEqual(before.filter { $0.id == .script(starred.id) }.count, 1)
        starred.isFilmed = true
        let after = library.rows(for: library.visible(in: scripts))
        XCTAssertEqual(after.filter { $0.id == .script(starred.id) }.count, 1)
        XCTAssertFalse(after.contains { $0.id == .heading(0) })
        XCTAssertTrue(after.contains { $0.id == .heading(2) })
        XCTAssertEqual(Set(before.compactMap { row -> UUID? in if case .script(let script) = row { return script.id }; return nil }),
                       Set(after.compactMap { row -> UUID? in if case .script(let script) = row { return script.id }; return nil }))
        XCTAssertEqual(Set(after.map(\.id)).count, after.count)
        starred.isFilmed = false
        XCTAssertEqual(library.rows(for: library.visible(in: scripts)).map(\.id), before.map(\.id))
    }

    func testHeaderIdentityDoesNotDependOnItsChangingCount() {
        let a = Script(title: "甲"), b = Script(title: "乙"), c = Script(title: "丙", isFilmed: true)
        let library = ScriptLibraryState(), scripts = [a, b, c]
        library.refresh(scripts)
        let before = library.rows(for: library.visible(in: scripts))
        a.isFilmed = true
        let after = library.rows(for: library.visible(in: scripts))
        func headings(_ rows: [ScriptLibraryState.Row]) -> [Int: Int] {
            Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                if case .heading(let tier, let count) = row { return (tier, count) }; return nil
            })
        }
        XCTAssertEqual(headings(before), [1: 2, 3: 1])
        XCTAssertEqual(headings(after), [1: 1, 3: 2])
        XCTAssertEqual(before.filter { if case .heading = $0 { return true }; return false }.map(\.id),
                       after.filter { if case .heading = $0 { return true }; return false }.map(\.id))
    }

    func testSearchSortingAndStatsReflectContentChanges() {
        let a = Script(title: "甲", content: "一句", folder: "口播"), b = Script(title: "乙", content: "长长的稿件", starred: true)
        let library = ScriptLibraryState(); library.refresh([a, b]); library.sortKey = .chars
        XCTAssertEqual(library.visible(in: [a, b]).first?.id, b.id, "星标分层优先于字数")
        library.query = "稿件"; XCTAssertEqual(library.visible(in: [a, b]).map(\.id), [b.id])
        a.content = "现在也有稿件"; library.refresh([a, b])
        XCTAssertEqual(library.summaries[a.id]?.characterCount, 6)
        XCTAssertEqual(library.visible(in: [a, b]).count, 2)
        XCTAssertEqual(library.folderCounts["口播"], 1)
    }

    func testImportDeduplicatesAndExportExcludesRecentlyDeleted() throws {
        let container = try store(), context = container.mainContext
        let id = UUID()
        let json = """
        {"type":"prompter-export","v":1,"scripts":[{"id":"\(id.uuidString)","title":"稿件","content":"正文","starred":true}],"filmedIds":["\(id.uuidString)"]}
        """
        let payload = try XCTUnwrap(MigrationService.decode(json))
        XCTAssertEqual(try MigrationService.importPayload(payload, into: context), 1)
        XCTAssertEqual(try MigrationService.importPayload(payload, into: context), 0)
        let script = try XCTUnwrap(context.fetch(FetchDescriptor<Script>()).first)
        XCTAssertEqual(script.id, id); XCTAssertTrue(script.isFilmed); XCTAssertTrue(script.starred)
        let roundTrip = try XCTUnwrap(MigrationService.decode(try MigrationService.exportJSON(scripts: [script], settings: .defaults)))
        XCTAssertEqual(roundTrip.scripts?.first?.id, id.uuidString)
        script.deletedAt = Date(); try context.save()
        let exported = try MigrationService.exportJSON(scripts: [script], settings: .defaults)
        let data = try XCTUnwrap(exported.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["scripts"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((object["filmedIds"] as? [String])?.count, 0)
    }

    func testInvalidOrFutureImportFormatIsRejected() {
        XCTAssertNil(MigrationService.decode("{\"type\":\"unrelated\",\"scripts\":[{}]}"))
        XCTAssertNil(MigrationService.decode("{\"type\":\"prompter-export\",\"v\":999,\"scripts\":[{}]}"))
        XCTAssertNil(MigrationService.decode("{\"scripts\":[]}"))
    }

    func testEmptyKeywordModeSurvivesPersistenceAndAllSettingsClamp() throws {
        var data = SettingsData.defaults
        data.automaticPause = .keyword
        XCTAssertEqual(data.automaticPause, .keyword)
        let decoded = try JSONDecoder().decode(SettingsData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.automaticPause, .keyword)
        data.fontSize = -10; data.lineHeight = .infinity; data.letterSpacing = -1
        data.horizontalPadding = 200; data.textAlign = "invalid"; data.completeAction = "invalid"
        let clean = data.normalized
        XCTAssertEqual(clean.fontSize, PrompterCore.fontSizeMin)
        XCTAssertEqual(clean.lineHeight, SettingsData.defaults.lineHeight)
        XCTAssertEqual(clean.letterSpacing, PrompterCore.letterSpacingMin)
        XCTAssertEqual(clean.horizontalPadding, PrompterCore.paddingMax)
        XCTAssertEqual(clean.textAlign, "left"); XCTAssertEqual(clean.completion, .none)
    }

    func testLegacySettingsDecodeAndFlushPersistsLatestValue() throws {
        let suite = "PrompterTests.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var data = SettingsData.defaults; data.pauseKeyword = "暂停"
        let legacy = try JSONEncoder().encode(data)
        defaults.set(legacy, forKey: "prompter_settings")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.data.automaticPause, .keyword)
        settings.data.scrollSpeed = 200; settings.data.scrollSpeed = 260; settings.flush()
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.data.scrollSpeed, 260)
    }
}

// Same entity and property names as the shipped pre-deletedAt model.
private enum LegacyScriptSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Script.self] }
    @Model final class Script {
        @Attribute(.unique) var id: UUID
        var title: String
        var content: String
        var createdAt: Date
        var updatedAt: Date
        var starred: Bool
        var folder: String?
        var isFilmed: Bool
        init(id: UUID) {
            self.id = id; title = "旧版稿件"; content = "完整旧内容"; folder = "口播"
            createdAt = Date(timeIntervalSince1970: 123); updatedAt = Date(timeIntervalSince1970: 456)
            starred = true; isFilmed = true
        }
    }
}

extension ScriptLibraryTests {
    func testPreviousStoreMigratesWithoutLosingScripts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store"), id = UUID()
        do {
            let old = try ModelContainer(for: LegacyScriptSchema.Script.self, configurations: ModelConfiguration(url: url))
            old.mainContext.insert(LegacyScriptSchema.Script(id: id)); try old.mainContext.save()
        }
        let migrated = try ModelContainer(for: Script.self, configurations: ModelConfiguration(url: url))
        let script = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<Script>()).first)
        XCTAssertEqual(script.id, id)
        XCTAssertEqual(script.title, "旧版稿件"); XCTAssertEqual(script.content, "完整旧内容")
        XCTAssertEqual(script.folder, "口播"); XCTAssertTrue(script.starred); XCTAssertTrue(script.isFilmed)
        XCTAssertEqual(script.createdAt, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(script.updatedAt, Date(timeIntervalSince1970: 456)); XCTAssertNil(script.deletedAt)
    }
}
