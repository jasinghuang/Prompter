import Foundation
import SwiftData

@Model
final class Script {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var starred: Bool
    var folder: String?
    var isFilmed: Bool
    // Optional additive field: existing stores migrate with every script still active.
    var deletedAt: Date? = nil

    init(
        id: UUID = UUID(),
        title: String = "未命名稿件",
        content: String = "",
        folder: String? = nil,
        starred: Bool = false,
        isFilmed: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.starred = starred
        self.folder = folder
        self.isFilmed = isFilmed
    }
}
