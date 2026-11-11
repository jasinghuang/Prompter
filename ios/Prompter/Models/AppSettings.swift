import Foundation
import SwiftUI

enum PlaybackMode: String, Codable, CaseIterable {
    case constant, voice
    var label: String { self == .constant ? "匀速" : "语音跟随" }
}

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
    var playbackMode: PlaybackMode = .constant
    var speechEngine: SpeechEngineKind = .paraformer
    var showSpeechDiagnostics = false
    var islandIndicatorEnabled = true
    var mirror = false
    var horizontalPadding: Int = 8
    var textAlign: String = "left"
    var pauseKeyword: String = ""
    var pauseOnParagraph = false
    var completeAction: String = "none"
    var splitMode: String = "paragraph"
    var splitKeyword: String = ""
    var pauseMode: AutoPauseMode? = nil
    var airPodsNodEnabled = false
    var headGestureCalibration: HeadGestureCalibration? = nil

    init() {}

    private enum CodingKeys: String, CodingKey {
        case fontSize, letterSpacing, lineHeight, scrollSpeed, mirror, horizontalPadding, textAlign
        case pauseKeyword, pauseOnParagraph, completeAction, splitMode, splitKeyword, pauseMode
        case airPodsNodEnabled, headGestureCalibration, playbackMode, speechEngine, showSpeechDiagnostics
        case islandIndicatorEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try c.decodeIfPresent(Int.self, forKey: .fontSize) ?? 64
        letterSpacing = try c.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? 0.05
        lineHeight = try c.decodeIfPresent(Double.self, forKey: .lineHeight) ?? 1.6
        scrollSpeed = try c.decodeIfPresent(Int.self, forKey: .scrollSpeed) ?? 160
        playbackMode = (try? c.decodeIfPresent(PlaybackMode.self, forKey: .playbackMode)) ?? .constant
        speechEngine = (try? c.decodeIfPresent(SpeechEngineKind.self, forKey: .speechEngine)) ?? .paraformer
        showSpeechDiagnostics = (try? c.decodeIfPresent(Bool.self, forKey: .showSpeechDiagnostics)) ?? false
        islandIndicatorEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .islandIndicatorEnabled)) ?? true
        mirror = try c.decodeIfPresent(Bool.self, forKey: .mirror) ?? false
        horizontalPadding = try c.decodeIfPresent(Int.self, forKey: .horizontalPadding) ?? 8
        textAlign = try c.decodeIfPresent(String.self, forKey: .textAlign) ?? "left"
        pauseKeyword = try c.decodeIfPresent(String.self, forKey: .pauseKeyword) ?? ""
        pauseOnParagraph = try c.decodeIfPresent(Bool.self, forKey: .pauseOnParagraph) ?? false
        completeAction = try c.decodeIfPresent(String.self, forKey: .completeAction) ?? "none"
        splitMode = try c.decodeIfPresent(String.self, forKey: .splitMode) ?? "paragraph"
        splitKeyword = try c.decodeIfPresent(String.self, forKey: .splitKeyword) ?? ""
        pauseMode = try c.decodeIfPresent(AutoPauseMode.self, forKey: .pauseMode)
        airPodsNodEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .airPodsNodEnabled)) ?? false
        // A damaged/future calibration must not erase unrelated reader preferences.
        headGestureCalibration = try? c.decodeIfPresent(HeadGestureCalibration.self, forKey: .headGestureCalibration)
    }

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
        if headGestureCalibration?.valid != true {
            copy.headGestureCalibration = nil
            copy.airPodsNodEnabled = false
        }
        return copy
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private static let storageKey = "prompter_settings"
    private let defaults: UserDefaults
    private static var islandCalibrationKey: String { "prompter_island_calibration_\(IslandIndicatorGeometry.currentModel)" }
    @Published var islandCalibration: IslandIndicatorCalibration {
        didSet {
            if let encoded = try? JSONEncoder().encode(islandCalibration.normalized) {
                defaults.set(encoded, forKey: Self.islandCalibrationKey)
            }
        }
    }
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
        islandCalibration = defaults.data(forKey: Self.islandCalibrationKey)
            .flatMap { try? JSONDecoder().decode(IslandIndicatorCalibration.self, from: $0) }?.normalized ?? .init()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetSettings") {
            islandCalibration = .init()
            data = .defaults
            flush()
            return
        }
        #endif
        if let raw = defaults.data(forKey: Self.storageKey), let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            data = decoded.normalized
        } else { data = .defaults }
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-speechEngine=") }),
           let engine = SpeechEngineKind(rawValue: String(argument.dropFirst("-speechEngine=".count))) {
            data.speechEngine = engine
            data.playbackMode = .voice
        }
        if ProcessInfo.processInfo.arguments.contains("-speechDiagnostics") { data.showSpeechDiagnostics = true }
        #endif
    }

    func flush() {
        pendingSave?.cancel(); pendingSave = nil
        // normalized replaces nonfinite values before JSON encoding.
        if let encoded = try? JSONEncoder().encode(data.normalized) { defaults.set(encoded, forKey: Self.storageKey) }
    }
}
