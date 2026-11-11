import Foundation

struct SpeechRecognitionResult {
    var text: String
    var segment: Int
    var isFinal: Bool
}

protocol LocalSpeechRecognizer: AnyObject {
    func accept(_ samples: [Float]) throws -> SpeechRecognitionResult?
    func resetForReposition() throws
}

enum SpeechEngineKind: String, Codable, CaseIterable {
    case apple, zipformer, senseVoice, paraformer
    var label: String {
        switch self {
        case .apple: return "Apple 本地"
        case .zipformer: return "Zipformer 流式"
        case .paraformer: return "Paraformer 流式"
        case .senseVoice: return "SenseVoice 分段"
        }
    }
    var detail: String {
        switch self {
        case .apple: return "系统管理中文语言资源；首次可能需要下载，之后在本机识别"
        case .zipformer: return "中文流式模型 · 2025-06-30 INT8"
        case .paraformer: return "原中英双语流式模型 · 对照方案"
        case .senseVoice: return "非流式模型 · 分段快照识别，可能有更长等待"
        }
    }
}

enum SpeechEngineError: LocalizedError {
    case offlineUnavailable, languageUnavailable, permission, modelMissing
    var errorDescription: String? {
        switch self {
        case .offlineUnavailable: return "此设备暂不支持所选 Apple 本地识别，音频不会切换到云端。请选择其他本地引擎。"
        case .languageUnavailable: return "Apple 中文离线资源暂不可用，请联网准备语言资源后重试。"
        case .permission: return "语音识别权限未开启，请在系统设置中允许提词器使用语音识别。"
        case .modelMissing: return "所选本地模型尚未准备完成，请选择已就绪的引擎。"
        }
    }
}

protocol SpeechGatedRecognizer: LocalSpeechRecognizer {
    func accept(_ samples: [Float], speech: Bool) throws -> SpeechRecognitionResult?
}
