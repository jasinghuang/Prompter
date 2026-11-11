import Foundation
import SwiftData

/// A versioned value document; never serialize SwiftData objects or its store files.
struct LibraryArchive: Codable, Sendable {
    static let formatIdentifier = "com.jasing.prompter.library"
    static let currentVersion = 1
    let format: String
    let version: Int
    let exportedAt: Date
    let folders: [String]
    let scripts: [Record]

    struct Record: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let title: String
        let content: String
        let folder: String?
        let starred: Bool
        let isFilmed: Bool
        let createdAt: Int64
        let updatedAt: Int64

        init(_ snapshot: ScriptSnapshot) throws {
            guard snapshot.deletedAt == nil else { throw LibraryArchiveError.invalidFile }
            id = snapshot.id; title = snapshot.title; content = snapshot.content
            folder = snapshot.folder; starred = snapshot.starred; isFilmed = snapshot.isFilmed
            createdAt = try Self.milliseconds(snapshot.createdAt)
            updatedAt = try Self.milliseconds(snapshot.updatedAt)
        }

        private static func milliseconds(_ date: Date) throws -> Int64 {
            let seconds = date.timeIntervalSince1970
            guard seconds.isFinite, (-62_135_596_800...253_402_300_799).contains(seconds) else {
                throw LibraryArchiveError.invalidFile
            }
            return Int64((seconds * 1_000).rounded())
        }

        @MainActor func apply(to script: Script) {
            script.title = title; script.content = content; script.folder = folder
            script.starred = starred; script.isFilmed = isFilmed
            script.createdAt = Date(timeIntervalSince1970: Double(createdAt) / 1_000)
            script.updatedAt = Date(timeIntervalSince1970: Double(updatedAt) / 1_000)
            script.deletedAt = nil
        }
    }

    init(scripts: [Record], exportedAt: Date = Date()) {
        format = Self.formatIdentifier; version = Self.currentVersion
        self.exportedAt = exportedAt; self.scripts = scripts
        folders = Array(Set(scripts.compactMap(\.folder))).sorted()
    }
}

enum LibraryArchiveError: LocalizedError {
    case invalidFile, tooLarge, tooManyScripts, unsupportedVersion(Int), libraryChanged
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "这个文件不是有效的稿件库，或文件内容已损坏。"
        case .tooLarge: return "稿件库文件超过 10 MB，请分批导出。"
        case .tooManyScripts: return "单个文件最多包含 10,000 篇稿件，请分批导出。"
        case .unsupportedVersion(let version): return "这个稿件库使用较新的文件格式（版本 \(version)），请更新 App 后再导入。"
        case .libraryChanged: return "本机稿件已有变化，请核对更新后的导入结果再继续。"
        }
    }
}

enum LibraryArchiveService {
    static let maximumBytes = 10 * 1_024 * 1_024
    static let maximumScripts = 10_000

    static func encode(_ archive: LibraryArchive) throws -> Data {
        try validate(archive)
        // Bound the source before encoding; JSON escaping is checked again below.
        let rawBytes = archive.scripts.reduce(0) { $0 + $1.title.utf8.count + $1.content.utf8.count + ($1.folder?.utf8.count ?? 0) }
        guard rawBytes <= maximumBytes else { throw LibraryArchiveError.tooLarge }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maximumBytes else { throw LibraryArchiveError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> LibraryArchive {
        guard data.count <= maximumBytes else { throw LibraryArchiveError.tooLarge }
        // Read the header first so future formats produce an update instruction,
        // even if their record schema differs from this app's version.
        struct Header: Decodable { let format: String; let version: Int }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data),
              header.format == LibraryArchive.formatIdentifier else { throw LibraryArchiveError.invalidFile }
        guard header.version == LibraryArchive.currentVersion else {
            throw LibraryArchiveError.unsupportedVersion(header.version)
        }
        guard let archive = try? decoder.decode(LibraryArchive.self, from: data) else { throw LibraryArchiveError.invalidFile }
        try validate(archive)
        return archive
    }

    static func validate(_ archive: LibraryArchive) throws {
        guard archive.format == LibraryArchive.formatIdentifier else { throw LibraryArchiveError.invalidFile }
        guard archive.version == LibraryArchive.currentVersion else { throw LibraryArchiveError.unsupportedVersion(archive.version) }
        guard archive.scripts.count <= maximumScripts else { throw LibraryArchiveError.tooManyScripts }
        let names = archive.scripts.compactMap(\.folder)
        guard Set(archive.scripts.map(\.id)).count == archive.scripts.count,
              Set(archive.folders).count == archive.folders.count,
              Set(archive.folders) == Set(names),
              names.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              archive.scripts.allSatisfy({
                  (-62_135_596_800_000...253_402_300_799_999).contains($0.createdAt)
                    && (-62_135_596_800_000...253_402_300_799_999).contains($0.updatedAt)
              }) else { throw LibraryArchiveError.invalidFile }
    }

    /// Bounded read while retaining access to document-provider URLs.
    static func read(from url: URL) throws -> LibraryArchive {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var readingError: NSError?
        var result: Result<LibraryArchive, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &readingError) { coordinatedURL in
            result = Result {
                let handle = try FileHandle(forReadingFrom: coordinatedURL)
                defer { try? handle.close() }
                var data = Data()
                while let chunk = try handle.read(upToCount: min(64 * 1_024, maximumBytes + 1 - data.count)), !chunk.isEmpty {
                    data.append(chunk)
                    guard data.count <= maximumBytes else { throw LibraryArchiveError.tooLarge }
                }
                return try decode(data)
            }
        }
        if let readingError { throw readingError }
        guard let result else { throw LibraryArchiveError.invalidFile }
        return try result.get()
    }

    enum ConflictPolicy: String, CaseIterable { case keepLocal, useFile }
    struct Conflict: Identifiable {
        var id: UUID { incoming.id }
        let incoming: LibraryArchive.Record
        let local: ScriptSnapshot
    }
    struct ImportPlan {
        let archive: LibraryArchive
        let baseline: [UUID: ScriptSnapshot]
        let newRecords: [LibraryArchive.Record]
        let conflicts: [Conflict]
        let identicalCount: Int
    }
    struct ImportReport {
        let added: Int
        let updated: Int
        let kept: Int
        let skipped: Int
    }

    @MainActor static func plan(_ archive: LibraryArchive, in context: ModelContext) throws -> ImportPlan {
        try validate(archive)
        let incomingIDs = Set(archive.scripts.map(\.id))
        let baseline = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Script>())
            .filter { incomingIDs.contains($0.id) }.map { ($0.id, ScriptSnapshot($0)) })
        var newRecords: [LibraryArchive.Record] = [], conflicts: [Conflict] = []
        var identical = 0
        for record in archive.scripts {
            guard let local = baseline[record.id] else { newRecords.append(record); continue }
            if local.deletedAt == nil, try LibraryArchive.Record(local) == record { identical += 1 }
            else { conflicts.append(Conflict(incoming: record, local: local)) }
        }
        return ImportPlan(archive: archive, baseline: baseline, newRecords: newRecords,
                          conflicts: conflicts, identicalCount: identical)
    }

    @MainActor static func apply(_ plan: ImportPlan, policy: ConflictPolicy, in context: ModelContext,
                                persist: (ModelContext) throws -> Void = { try $0.save() }) throws -> ImportReport {
        // Recheck before writing; an undo, edit, or another import may have run
        // after the confirmation sheet was opened.
        let currentPlan = try self.plan(plan.archive, in: context)
        guard currentPlan.baseline == plan.baseline else { throw LibraryArchiveError.libraryChanged }
        let current = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Script>()).map { ($0.id, $0) })
        var inserted: [Script] = [], restored: [(Script, ScriptSnapshot)] = []
        do {
            for record in plan.newRecords {
                let script = Script(id: record.id)
                record.apply(to: script); context.insert(script); inserted.append(script)
            }
            if policy == .useFile {
                for conflict in plan.conflicts {
                    guard let script = current[conflict.id] else { throw LibraryArchiveError.libraryChanged }
                    restored.append((script, ScriptSnapshot(script)))
                    conflict.incoming.apply(to: script)
                }
            }
            if !inserted.isEmpty || !restored.isEmpty { try persist(context) }
        } catch {
            inserted.forEach(context.delete)
            for (script, snapshot) in restored { snapshot.apply(to: script) }
            throw error
        }
        return ImportReport(added: inserted.count, updated: restored.count,
                            kept: policy == .keepLocal ? plan.conflicts.count : 0, skipped: plan.identicalCount)
    }
}
