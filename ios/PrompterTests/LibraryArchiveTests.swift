import XCTest
import SwiftData
@testable import Prompter

@MainActor
final class LibraryArchiveTests: XCTestCase {
    private func store() throws -> ModelContainer {
        try ModelContainer(for: Script.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func record(_ script: Script) throws -> LibraryArchive.Record { try LibraryArchive.Record(ScriptSnapshot(script)) }
    private func fixture() -> [Script] {
        [Script(title: "相同标题", content: "中文正文\n第二行 ⭐️", folder: "口播", starred: true, isFilmed: true,
                createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200)),
         Script(title: "相同标题", content: "中文正文\n第二行 ⭐️", folder: "产品", starred: false, isFilmed: false),
         Script(title: "未分组", content: "", folder: nil)]
    }

    func testTwoIndependentLibrariesPreserveAllFieldsAndFolderMembership() throws {
        let source = try store(), destination = try store()
        let scripts = fixture(); scripts.forEach(source.mainContext.insert); try source.mainContext.save()
        let original = try scripts.map(record)
        let bytes = try LibraryArchiveService.encode(LibraryArchive(scripts: original))
        let archive = try LibraryArchiveService.decode(bytes)
        XCTAssertEqual(Set(archive.folders), ["口播", "产品"])
        let plan = try LibraryArchiveService.plan(archive, in: destination.mainContext)
        XCTAssertEqual(plan.newRecords.count, 3)
        let result = try LibraryArchiveService.apply(plan, policy: .keepLocal, in: destination.mainContext)
        XCTAssertEqual(result.added, 3)
        let restored = try destination.mainContext.fetch(FetchDescriptor<Script>())
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: try restored.map { ($0.id, try record($0)) }),
                       Dictionary(uniqueKeysWithValues: original.map { ($0.id, $0) }))
        XCTAssertTrue(restored.allSatisfy { $0.deletedAt == nil })
    }

    func testRepeatingSameImportIsANoopAndDoesNotDeduplicateDifferentIDsByText() throws {
        let container = try store(), scripts = fixture()
        let archive = LibraryArchive(scripts: try scripts.map(record))
        _ = try LibraryArchiveService.apply(LibraryArchiveService.plan(archive, in: container.mainContext), policy: .keepLocal, in: container.mainContext)
        let repeated = try LibraryArchiveService.plan(archive, in: container.mainContext)
        XCTAssertEqual(repeated.identicalCount, 3)
        XCTAssertTrue(repeated.newRecords.isEmpty); XCTAssertTrue(repeated.conflicts.isEmpty)
        let report = try LibraryArchiveService.apply(repeated, policy: .useFile, in: container.mainContext,
                                                    persist: { _ in XCTFail("完全相同的导入不应保存") })
        XCTAssertEqual(report.skipped, 3)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Script>()), 3)
    }

    func testConflictingStatesCanBeKeptOrExplicitlyUpdated() throws {
        let container = try store(), context = container.mainContext
        let local = Script(title: "本机", content: "本机正文", folder: "本机目录", starred: true)
        context.insert(local); try context.save()
        let incoming = Script(id: local.id, title: "接收", content: "接收正文", folder: "收到的目录", isFilmed: true)
        let archive = LibraryArchive(scripts: [try record(incoming)])
        let plan = try LibraryArchiveService.plan(archive, in: context)
        XCTAssertEqual(plan.conflicts.count, 1)
        let kept = try LibraryArchiveService.apply(plan, policy: .keepLocal, in: context)
        XCTAssertEqual(kept.kept, 1); XCTAssertEqual(local.title, "本机"); XCTAssertTrue(local.starred)
        let updated = try LibraryArchiveService.apply(plan, policy: .useFile, in: context)
        XCTAssertEqual(updated.updated, 1)
        XCTAssertEqual(try record(local), try record(incoming))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Script>()), 1)
    }

    func testDeletedRecordIsNotResurrectedWithoutChoosingFileVersion() throws {
        let container = try store(), context = container.mainContext
        let local = Script(title: "删除前"), incoming = try record(local)
        local.deletedAt = Date(); context.insert(local); try context.save()
        let archive = LibraryArchive(scripts: [incoming])
        let plan = try LibraryArchiveService.plan(archive, in: context)
        XCTAssertEqual(plan.conflicts.count, 1)
        _ = try LibraryArchiveService.apply(plan, policy: .keepLocal, in: context)
        XCTAssertNotNil(local.deletedAt)
        _ = try LibraryArchiveService.apply(plan, policy: .useFile, in: context)
        XCTAssertNil(local.deletedAt)
    }

    func testChangedLocalDataInvalidatesConfirmationBeforeAnyInsertion() throws {
        let container = try store(), context = container.mainContext
        let local = Script(title: "A"); context.insert(local); try context.save()
        let archive = LibraryArchive(scripts: [try record(local), try record(Script(title: "新稿"))])
        let plan = try LibraryArchiveService.plan(archive, in: context)
        local.starred.toggle(); try context.save()
        XCTAssertThrowsError(try LibraryArchiveService.apply(plan, policy: .useFile, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Script>()), 1)
        XCTAssertTrue(local.starred)
    }

    func testFailedSaveRestoresExistingContentAndRemovesNewInsertions() throws {
        enum Failure: Error { case disk }
        let container = try store(), context = container.mainContext
        let local = Script(title: "A", content: "保留的正文")
        context.insert(local); try context.save()
        let before = ScriptSnapshot(local)
        let changed = Script(id: local.id, title: "变更", content: "文件正文", starred: true, isFilmed: true)
        let archive = LibraryArchive(scripts: [try record(changed), try record(Script(title: "新稿"))])
        let plan = try LibraryArchiveService.plan(archive, in: context)
        XCTAssertThrowsError(try LibraryArchiveService.apply(plan, policy: .useFile, in: context, persist: { _ in throw Failure.disk }))
        XCTAssertEqual(ScriptSnapshot(local), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Script>()), 1)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Script>()).first?.title, "A")
    }

    func testMalformedAndFutureArchivesAreRejectedBeforeImport() throws {
        XCTAssertThrowsError(try LibraryArchiveService.decode(Data("not a library".utf8)))
        let future = Data("{\"format\":\"com.jasing.prompter.library\",\"version\":999}".utf8)
        XCTAssertThrowsError(try LibraryArchiveService.decode(future)) { error in
            guard case LibraryArchiveError.unsupportedVersion(999) = error else { return XCTFail("应提示更新 App") }
        }
        let one = try record(Script(title: "A"))
        XCTAssertThrowsError(try LibraryArchiveService.encode(LibraryArchive(scripts: [one, one])))
        let valid = try LibraryArchiveService.encode(LibraryArchive(scripts: [one]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["folders"] = ["不存在的目录"]
        XCTAssertThrowsError(try LibraryArchiveService.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try LibraryArchiveService.decode(Data(repeating: 32, count: LibraryArchiveService.maximumBytes + 1)))
    }

    func testSharedFileAndSavedDocumentDecodeToTheSameArchive() throws {
        let archive = LibraryArchive(scripts: try fixture().map(record))
        let prepared = try LibraryExportFiles.prepare(archive)
        defer { try? FileManager.default.removeItem(at: prepared.file.url.deletingLastPathComponent()) }
        XCTAssertEqual(prepared.file.url.pathExtension, "prompter")
        XCTAssertEqual(try LibraryArchiveService.read(from: prepared.file.url).scripts, archive.scripts)
        XCTAssertEqual(try LibraryArchiveService.decode(prepared.data).scripts, archive.scripts)
        let bundle = Bundle.main
        let types = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])
        XCTAssertTrue(types.contains { $0["UTTypeIdentifier"] as? String == LibraryArchive.formatIdentifier })
        let documents = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]])
        XCTAssertTrue(documents.contains { ($0["LSItemContentTypes"] as? [String])?.contains(LibraryArchive.formatIdentifier) == true })
    }

    func testDeletedDataCannotBeAccidentallyExportedAsAnActiveRecord() {
        let deleted = Script(title: "内部删除记录")
        deleted.deletedAt = Date()
        XCTAssertThrowsError(try record(deleted))
    }
}
