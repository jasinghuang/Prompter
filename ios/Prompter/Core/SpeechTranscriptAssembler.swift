import Foundation

/// Native transcription can finalize one word at a time. Merge timed ranges
/// into a rolling hypothesis instead of asking the matcher to align isolated
/// one/two-character fragments. Overlapping volatile text is replaced.
struct SpeechTimedText {
    var start: Double
    var end: Double
    var text: String
}

struct SpeechTranscriptAssembler {
    private struct Part {
        var start: Double
        var end: Double
        var text: String
        var final: Bool
    }
    private var parts: [Part] = []

    mutating func update(rangeStart: Double, rangeEnd: Double, fragments: [SpeechTimedText],
                         finalizedThrough: Double, segment: Int) -> SpeechRecognitionResult? {
        guard rangeStart.isFinite, rangeEnd.isFinite, rangeEnd >= rangeStart else { return nil }
        parts.removeAll { $0.start < rangeEnd && $0.end > rangeStart || ($0.start == rangeStart && $0.end == rangeEnd) }
        for fragment in fragments where fragment.start.isFinite && fragment.end.isFinite && !fragment.text.isEmpty {
            if let last = parts.last, last.start == fragment.start && last.end == fragment.end {
                parts[parts.count - 1].text += fragment.text
            } else {
                parts.append(.init(start: fragment.start, end: fragment.end, text: fragment.text, final: false))
            }
        }
        parts.sort { $0.start < $1.start }
        for i in parts.indices where parts[i].end <= finalizedThrough { parts[i].final = true }
        if parts.count > 128 { parts.removeFirst(parts.count - 128) }
        let text = String(parts.map(\.text).joined().suffix(160))
        guard !text.isEmpty else { return nil }
        return .init(text: text, segment: segment, isFinal: parts.allSatisfy(\.final))
    }
}
