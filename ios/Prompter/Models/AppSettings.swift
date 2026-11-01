import Foundation
import SwiftUI

enum AutoPauseMode: String, Codable, CaseIterable {
    case off, paragraph, keyword
    var label: String {
        switch self { case .off: return "关闭"; case .paragraph: return "空行"; case .keyword: return "关键词" }
    }
}

enum CompletionAction: String, CaseIterable {
    case none, restart, list
    var label: String {
        switch self { case .none: return "停在末尾"; case .restart: return "回到开头"; case .list: return "标记已拍并返回列表" }
    }
}

/// Keep legacy keys readable by the PWA; the explicit mode also preserves an empty keyword draft.
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
    var pauseMode: AutoPauseMode? = nil

    static let defaults = SettingsData()
    var automaticPause: AutoPauseMode {
        get { pauseMode ?? (!pauseKeyword.isEmpty ? .keyword : pauseOnParagraph ? .paragraph : .off) }
        set {
            pauseMode = newValue
            pauseOnParagraph = newValue == .paragraph
            if newValue != .keyword { pauseKeyword = "" }
        }
    }
    var completion: CompletionAction {
        get { CompletionAction(rawValue: completeAction) ?? .none }
        set { completeAction = newValue.rawValue }
    }

    var normalized: SettingsData {
        var copy = self
        copy.fontSize = min(PrompterCore.fontSizeMax, max(PrompterCore.fontSizeMin, fontSize))
        copy.scrollSpeed = min(PrompterCore.speedMax, max(PrompterCore.speedMin, scrollSpeed))
        copy.horizontalPadding = min(PrompterCore.paddingMax, max(PrompterCore.paddingMin, horizontalPadding))
        copy.letterSpacing = letterSpacing.isFinite ? min(PrompterCore.letterSpacingMax, max(PrompterCore.letterSpacingMin, letterSpacing)) : Self.defaults.letterSpacing
        copy.lineHeight = lineHeight.isFinite ? min(PrompterCore.lineHeightMax, max(PrompterCore.lineHeightMin, lineHeight)) : Self.defaults.lineHeight
        if !["left", "center", "right"].contains(textAlign) { copy.textAlign = "left" }
        if SplitMode(rawValue: splitMode) == nil { copy.splitMode = "paragraph" }
        if CompletionAction(rawValue: completeAction) == nil { copy.completeAction = "none" }
        return copy
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private static let storageKey = "prompter_settings"
    private let defaults: UserDefaults
    private var pendingSave: Task<Void, Never>?
    @Published var data: SettingsData {
        didSet {
            guard data != oldValue else { return }
            pendingSave?.cancel()
            pendingSave = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                self?.flush()
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetSettings") {
            data = .defaults
            flush()
            return
        }
        #endif
        if let raw = defaults.data(forKey: Self.storageKey), let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            data = decoded.normalized
        } else { data = .defaults }
    }

    func flush() {
        pendingSave?.cancel(); pendingSave = nil
        // normalized replaces nonfinite values before JSON encoding.
        if let encoded = try? JSONEncoder().encode(data.normalized) { defaults.set(encoded, forKey: Self.storageKey) }
    }
}
