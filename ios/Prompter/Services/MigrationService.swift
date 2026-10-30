import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

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

    static func decode(_ json: String) -> ExportPayload? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ExportPayload.self, from: data),
              payload.type == payloadType || payload.scripts != nil else { return nil }
        return payload
    }

    /// 导入到数据上下文，返回导入的稿件数
    @discardableResult
    static func importPayload(_ payload: ExportPayload, into context: ModelContext) -> Int {
        let filmed = Set(payload.filmedIds ?? [])
        var count = 0
        for item in payload.scripts ?? [] {
            let script = Script(
                title: (item.title?.isEmpty == false) ? item.title! : "未命名稿件",
                content: item.content ?? "",
                folder: item.folder,
                starred: item.starred ?? false,
                isFilmed: filmed.contains(item.id ?? "")
            )
            if let created = item.createdAt {
                script.createdAt = Date(timeIntervalSince1970: created / 1000)
            }
            if let updated = item.updatedAt {
                script.updatedAt = Date(timeIntervalSince1970: updated / 1000)
            }
            context.insert(script)
            count += 1
        }
        return count
    }

    /// 把当前数据导出成与 PWA 同形状的 JSON（用于备份/反向迁移）
    static func exportJSON(scripts: [Script], settings: SettingsData) -> String {
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
            scripts: scripts.map {
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
            filmedIds: scripts.filter(\.isFilmed).map(\.id.uuidString),
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
                splitKeyword: settings.splitKeyword
            )
        )
        return (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: 剪贴板（仅 iOS）

    static func pasteboardString() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #else
        return nil
        #endif
    }

    static func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
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
    }
}
