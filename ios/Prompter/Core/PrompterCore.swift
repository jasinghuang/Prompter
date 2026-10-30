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

    // MARK: 播放页（与 Web 版 types.ts / Teleprompter.tsx 对齐）

    static let fontSizeMin = 24
    static let fontSizeMax = 120
    static let letterSpacingMin = 0.0
    static let letterSpacingMax = 0.3
    static let lineHeightMin = 1.0
    static let lineHeightMax = 2.5
    static let paddingMin = 4
    static let paddingMax = 20

    /// 自动滚动速度（pt/s）= 可滚动总距离 / 字数 × (字/分 ÷ 60)
    /// 即把整篇可滚动距离均摊到每个字上，字/分换算为每秒位移
    static func pointsPerSecond(maxOffset: Double, charCount: Int, wordsPerMinute: Int) -> Double {
        guard charCount > 0, maxOffset > 0, wordsPerMinute > 0 else { return 0 }
        return (maxOffset / Double(charCount)) * (Double(wordsPerMinute) / 60.0)
    }

    /// 双指捏合换算字号：起始字号按手指间距比例缩放，步进 2 取偶，夹在 [fontSizeMin, fontSizeMax]
    static func pinchFontSize(scale: Double, startFontSize: Int) -> Int {
        guard scale > 0, scale.isFinite else { return startFontSize }
        let raw = Double(startFontSize) * scale
        let stepped = Int((raw / 2).rounded()) * 2
        return min(fontSizeMax, max(fontSizeMin, stepped))
    }

    /// 段落起点集合（UTF-16 偏移）：连续 2+ 换行之后的首个非换行字符位置
    static func paragraphStarts(_ content: String) -> Set<Int> {
        let units = Array(content.utf16)
        let newline = UInt16(10)
        var starts = Set<Int>()
        guard units.count > 1 else { return starts }
        for i in 1..<units.count where units[i] == newline && units[i - 1] == newline {
            var j = i + 1
            while j < units.count && units[j] == newline { j += 1 }
            if j < units.count { starts.insert(j) }
        }
        return starts
    }
}

// MARK: - 自动暂停（与 Web 版 usePauseOnKeyword / usePauseOnParagraph 一致）

/// 关键词自动暂停：在当前行起点前后窗口内查找关键词，同一命中位置只触发一次
struct KeywordPauseTracker {
    private(set) var pausedAt = -1

    mutating func reset() { pausedAt = -1 }

    /// 返回 true 表示此刻应暂停（并记录命中位置）；偏移均为 UTF-16
    mutating func shouldPause(content: String, keyword: String, activeIndex: Int) -> Bool {
        guard !keyword.isEmpty else { return false }
        let text = content as NSString
        let keywordLength = (keyword as NSString).length
        let ctxStart = max(0, activeIndex - max(keywordLength, 30))
        let ctxEnd = min(text.length, activeIndex + keywordLength)
        guard ctxEnd > ctxStart else { return false }
        let ctx = text.substring(with: NSRange(location: ctxStart, length: ctxEnd - ctxStart)) as NSString
        let skip = pausedAt >= ctxStart ? pausedAt - ctxStart + 1 : 0
        guard skip < ctx.length else { return false }
        let found = ctx.range(of: keyword, options: [], range: NSRange(location: skip, length: ctx.length - skip))
        guard found.location != NSNotFound else { return false }
        pausedAt = ctxStart + found.location
        return true
    }
}

/// 段落自动暂停：滚到段落起点行时暂停，同一起点只触发一次
struct ParagraphPauseTracker {
    private(set) var pausedAt = -1

    mutating func reset() { pausedAt = -1 }

    mutating func shouldPause(paragraphStarts: Set<Int>, activeIndex: Int) -> Bool {
        guard paragraphStarts.contains(activeIndex), pausedAt != activeIndex else { return false }
        pausedAt = activeIndex
        return true
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
