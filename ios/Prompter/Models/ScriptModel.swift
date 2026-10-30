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

    init(
        title: String = "未命名稿件",
        content: String = "",
        folder: String? = nil,
        starred: Bool = false,
        isFilmed: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.starred = starred
        self.folder = folder
        self.isFilmed = isFilmed
    }
}
