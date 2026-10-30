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

// MARK: - 智能拆分（与 Web 版 lib/split.ts 对齐）

enum SplitMode: String, CaseIterable {
    case paragraph
    case keyword

    var label: String {
        switch self {
        case .paragraph: return "空行"
        case .keyword: return "关键词"
        }
    }
}

enum Splitter {
    /// 按连续空行（2+ 换行）切分，去首尾空白、滤空段
    static func byParagraphs(_ content: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var newlineRun = 0
        for ch in content {
            if ch == "\n" {
                newlineRun += 1
                if newlineRun >= 2 {
                    if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    current = ""
                }
                continue
            }
            if newlineRun == 1 { current += "\n" } // 单个换行保留为段内换行
            newlineRun = 0
            current.append(ch)
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return segments
    }

    /// 在每个关键词出现处之前切分（字面量匹配），新段以关键词开头；空关键词返回空数组
    static func byKeyword(_ content: String, keyword: String) -> [String] {
        guard !keyword.isEmpty else { return [] }
        var parts: [String] = []
        var searchStart = content.startIndex
        var prev = content.startIndex
        while let range = content.range(of: keyword, range: searchStart..<content.endIndex) {
            parts.append(String(content[prev..<range.lowerBound]))
            prev = range.lowerBound
            searchStart = range.upperBound
        }
        parts.append(String(content[prev...]))
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 拆分出的段落标题 = 首行去空白
    static func titleOfSegment(_ segment: String) -> String {
        segment.split(separator: "\n", maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
