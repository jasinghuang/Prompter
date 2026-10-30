import Foundation

/// 纯函数核心：与 Web 版逻辑一一对应（字数/时长/格式化/分层排序）
enum PrompterCore {
    static let speedMin = 100
    static let speedMax = 700

    /// 非空白字符数（Unicode 标量级，与 Web 版 countReadableChars 一致）
    static func readableCharCount(_ content: String) -> Int {
        content.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }

    /// 预计口播时长（秒）= 字数 / 每分钟字数 × 60
    static func estimateDurationSeconds(charCount: Int, wordsPerMinute: Int) -> Int {
        guard wordsPerMinute > 0, charCount > 0 else { return 0 }
        return Int((Double(charCount) / Double(wordsPerMinute)) * 60.0)
    }

    /// 秒 → mm:ss（向下取整）
    static func formatTime(_ totalSeconds: Int) -> String {
        let s = max(0, totalSeconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// 列表分层（数值越小越靠上）：
    /// 0 未拍星标 → 1 未拍 → 2 已拍星标 → 3 已拍（沉底）
    static func tier(starred: Bool, filmed: Bool) -> Int {
        switch (starred, filmed) {
        case (true, false): return 0
        case (false, false): return 1
        case (true, true): return 2
        case (false, true): return 3
        }
    }
}

enum SortKey: String, CaseIterable {
    case date
    case title
    case chars

    var label: String {
        switch self {
        case .date: return "日期"
        case .title: return "标题"
        case .chars: return "字数"
        }
    }
}
