import Foundation
import SwiftData

// MARK: - PWA 导出 JSON 的形状

struct ExportedScript: Codable {
    let id: String?
    let title: String?
    let content: String?
    let createdAt: Double? // 毫秒时间戳
    let updatedAt: Double?
    let starred: Bool?
    let folder: String?
}

struct ExportedSettings: Codable {
    var fontSize: Int?
    var letterSpacing: Double?
    var lineHeight: Double?
    var scrollSpeed: Int?
    var mirror: Bool?
    var horizontalPadding: Int?
    var textAlign: String?
    var pauseKeyword: String?
    var pauseOnParagraph: Bool?
    var completeAction: String?
    var splitMode: String?
    var splitKeyword: String?
    var pauseMode: AutoPauseMode? = nil
}

struct ExportPayload: Codable {
    let type: String?
    let v: Int?
    let scripts: [ExportedScript]?
    let filmedIds: [String]?
    let settings: ExportedSettings?
}

// MARK: - 迁移服务

enum MigrationService {
    static let payloadType = "prompter-export"

    static let maximumBytes = 10 * 1024 * 1024
    static func decode(_ json: String) -> ExportPayload? {
        guard json.utf8.count <= maximumBytes, let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ExportPayload.self, from: data),
              payload.type == nil || payload.type == payloadType,
              payload.v == nil || payload.v == 1,
              let scripts = payload.scripts, !scripts.isEmpty, scripts.count <= 10_000 else { return nil }
        return payload
    }

    static func duplicateCount(_ payload: ExportPayload, existing: [Script]) -> Int {
        let ids = Set(existing.map { $0.id.uuidString.lowercased() })
        var contentKeys = Set(existing.map { $0.title + "\u{0}" + $0.content })
        var importedIDs = ids
        var duplicates = 0
        for item in payload.scripts ?? [] {
            let key = normalizedTitle(item.title) + "\u{0}" + (item.content ?? "")
            let id = item.id?.lowercased()
            if id.map({ importedIDs.contains($0) }) == true || contentKeys.contains(key) { duplicates += 1 }
            contentKeys.insert(key)
            if let id { importedIDs.insert(id) }
        }
        return duplicates
    }

    @MainActor
    @discardableResult
    static func importPayload(_ payload: ExportPayload, into context: ModelContext) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<Script>())
        var ids = Set(existing.map { $0.id.uuidString.lowercased() })
        var keys = Set(existing.map { $0.title + "\u{0}" + $0.content })
        let filmed = Set(payload.filmedIds ?? [])
        var inserted: [Script] = []
        for item in payload.scripts ?? [] {
            let title = normalizedTitle(item.title), content = item.content ?? ""
            let key = title + "\u{0}" + content
            let incomingID = item.id?.lowercased()
            if incomingID.map({ ids.contains($0) }) == true || keys.contains(key) { continue }
            let script = Script(id: item.id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                title: title, content: content, folder: item.folder,
                starred: item.starred ?? false, isFilmed: filmed.contains(item.id ?? ""))
            if let created = item.createdAt, created.isFinite { script.createdAt = Date(timeIntervalSince1970: created / 1000) }
            if let updated = item.updatedAt, updated.isFinite { script.updatedAt = Date(timeIntervalSince1970: updated / 1000) }
            context.insert(script); inserted.append(script); keys.insert(key)
            if let incomingID { ids.insert(incomingID) }
        }
        do { try context.save(); return inserted.count }
        catch { inserted.forEach(context.delete); throw error }
    }

    private static func normalizedTitle(_ title: String?) -> String {
        let cleaned = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? "未命名稿件" : cleaned
    }

    /// 把当前数据导出成与 PWA 同形状的 JSON（用于备份/反向迁移）
    static func exportJSON(scripts: [Script], settings: SettingsData) throws -> String {
        struct EncodableExport: Codable {
            let type: String
            let v: Int
            let scripts: [ExportedScript]
            let filmedIds: [String]
            let settings: ExportedSettings
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = EncodableExport(
            type: payloadType,
            v: 1,
            scripts: scripts.filter { $0.deletedAt == nil }.map {
                ExportedScript(
                    id: $0.id.uuidString,
                    title: $0.title,
                    content: $0.content,
                    createdAt: $0.createdAt.timeIntervalSince1970 * 1000,
                    updatedAt: $0.updatedAt.timeIntervalSince1970 * 1000,
                    starred: $0.starred,
                    folder: $0.folder
                )
            },
            filmedIds: scripts.filter { $0.deletedAt == nil && $0.isFilmed }.map { $0.id.uuidString },
            settings: ExportedSettings(
                fontSize: settings.fontSize,
                letterSpacing: settings.letterSpacing,
                lineHeight: settings.lineHeight,
                scrollSpeed: settings.scrollSpeed,
                mirror: settings.mirror,
                horizontalPadding: settings.horizontalPadding,
                textAlign: settings.textAlign,
                pauseKeyword: settings.pauseKeyword,
                pauseOnParagraph: settings.pauseOnParagraph,
                completeAction: settings.completeAction,
                splitMode: settings.splitMode,
                splitKeyword: settings.splitKeyword,
                pauseMode: settings.automaticPause
            )
        )
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }

    /// 从 Web 设置片段合并进当前设置（只覆盖有值字段）
    static func mergeSettings(_ exported: ExportedSettings?, into data: inout SettingsData) {
        guard let s = exported else { return }
        if let v = s.fontSize { data.fontSize = v }
        if let v = s.letterSpacing { data.letterSpacing = v }
        if let v = s.lineHeight { data.lineHeight = v }
        if let v = s.scrollSpeed { data.scrollSpeed = min(max(v, PrompterCore.speedMin), PrompterCore.speedMax) }
        if let v = s.mirror { data.mirror = v }
        if let v = s.horizontalPadding { data.horizontalPadding = v }
        if let v = s.textAlign { data.textAlign = v }
        if let v = s.pauseKeyword { data.pauseKeyword = v }
        if let v = s.pauseOnParagraph { data.pauseOnParagraph = v }
        if let v = s.completeAction { data.completeAction = v }
        if let v = s.splitMode { data.splitMode = v }
        if let v = s.splitKeyword { data.splitKeyword = v }
        if let mode = s.pauseMode { data.automaticPause = mode }
        else if s.pauseKeyword != nil || s.pauseOnParagraph != nil {
            data.pauseMode = !data.pauseKeyword.isEmpty ? .keyword : data.pauseOnParagraph ? .paragraph : .off
        }
        data = data.normalized
    }
}
