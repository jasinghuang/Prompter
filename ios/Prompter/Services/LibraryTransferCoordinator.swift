import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let prompterLibrary = UTType(exportedAs: LibraryArchive.formatIdentifier, conformingTo: .json)
}

struct LibraryArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.prompterLibrary] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw LibraryArchiveError.invalidFile }
        _ = try LibraryArchiveService.decode(data)
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct LibraryShareFile: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .prompterLibrary) { file in
            SentTransferredFile(file.url)
        }
    }
}

struct PreparedLibraryExport: Sendable {
    let data: Data
    let file: LibraryShareFile
    let name: String
}

enum LibraryExportFiles {
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("PrompterLibraryExports", isDirectory: true) }

    static func prepare(_ archive: LibraryArchive) throws -> PreparedLibraryExport {
        let data = try LibraryArchiveService.encode(archive)
        removeExpired()
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "稿件库-\(formatter.string(from: archive.exportedAt))"
        // Each share gets its own location. Do not remove a file on view dismissal:
        // AirDrop or another share extension can still be reading it asynchronously.
        let location = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: location, withIntermediateDirectories: true)
        let url = location.appendingPathComponent(name).appendingPathExtension("prompter")
        try data.write(to: url, options: .atomic)
        return PreparedLibraryExport(data: data, file: LibraryShareFile(url: url), name: name)
    }

    static func removeExpired(now: Date = Date()) {
        let manager = FileManager.default
        for directory in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            guard let created = try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  now.timeIntervalSince(created) > 86_400 else { continue }
            try? manager.removeItem(at: directory)
        }
    }
}

@MainActor
final class LibraryTransferCoordinator: ObservableObject {
    struct Incoming: Identifiable {
        let id = UUID()
        let archive: LibraryArchive
        let name: String
    }
    @Published private(set) var pending: [Incoming] = []
    @Published private(set) var isReading = false
    @Published var errorMessage: String?
    private var readingCount = 0

    func receive(_ url: URL) {
        guard url.isFileURL else { errorMessage = LibraryArchiveError.invalidFile.localizedDescription; return }
        guard pending.count + readingCount < 4 else {
            errorMessage = "请先处理已经收到的稿件库，再打开新的文件。"; return
        }
        readingCount += 1; isReading = true
        Task {
            defer { readingCount -= 1; isReading = readingCount > 0 }
            do {
                let archive = try await Task.detached(priority: .userInitiated) {
                    try LibraryArchiveService.read(from: url)
                }.value
                pending.append(Incoming(archive: archive, name: url.lastPathComponent))
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func takeNext() -> Incoming? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }
}

struct LibraryExportRequest: Identifiable {
    let id = UUID()
    let records: [LibraryArchive.Record]
    let currentIDs: Set<UUID>
    let currentTitle: String
    let onlySelected: Bool
    let prefersCurrent: Bool
}
