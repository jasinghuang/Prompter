import Foundation
import SwiftUI

/// 提词设置（与 Web 版 TeleprompterSettings 对齐，UserDefaults 持久化）
struct SettingsData: Codable, Equatable {
    var fontSize: Int = 64
    var letterSpacing: Double = 0.05
    var lineHeight: Double = 1.6
    var scrollSpeed: Int = 160
    var mirror = false
    var horizontalPadding: Int = 8
    var textAlign: String = "left"
    var pauseKeyword: String = ""
    var pauseOnParagraph = false
    var completeAction: String = "none"
    var splitMode: String = "paragraph"
    var splitKeyword: String = ""

    static let defaults = SettingsData()
}

@MainActor
final class AppSettings: ObservableObject {
    private static let storageKey = "prompter_settings"
    @Published var data: SettingsData {
        didSet { persist() }
    }

    init() {
        if let raw = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            data = decoded
        } else {
            data = .defaults
        }
    }

    private func persist() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: Self.storageKey)
        }
    }
}
