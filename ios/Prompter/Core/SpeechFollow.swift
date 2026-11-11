import Foundation

/// Recognition tokens retain their original UTF-16 ends, as required by TextKit.
struct SpeechScript {
    let tokens: [String]
    let ends: [Int]

    init(_ text: String) {
        var tokens: [String] = []
        var ends: [Int] = []
        var offset = 0
        for character in text {
            let original = String(character)
            offset += original.utf16.count
            let folded = original.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                                          locale: Locale(identifier: "en_US_POSIX"))
            for scalar in folded.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
                tokens.append(String(scalar))
                ends.append(offset)
            }
        }
        self.tokens = tokens
        self.ends = ends
    }
}

struct SpeechMatch: Equatable {
    var utf16End: Int
    var tokenEnd: Int
    var reachedEnd: Bool
}

/// Bounded semi-global edit distance tolerates omissions, fillers and ASR revisions.
/// Partial results replace the current hypothesis; they are never appended as new words.
struct SpeechScriptMatcher {
    let script: SpeechScript
    private(set) var cursor: Int
    private var phonetics: [String: String] = [:]

    init(content: String, startUTF16: Int = 0) {
        script = SpeechScript(content)
        cursor = script.ends.firstIndex(where: { $0 > startUTF16 }) ?? script.tokens.count
    }

    mutating func match(_ hypothesis: String) -> SpeechMatch? {
        let query = Array(SpeechScript(hypothesis).tokens.suffix(48))
        let minimum = min(3, script.tokens.count)
        guard minimum > 0, query.count >= minimum else { return nil }
        let lower = max(0, cursor - 64)
        let upper = min(script.tokens.count, cursor + 160)
        guard lower < upper else { return nil }
        let window = Array(script.tokens[lower..<upper])
        // Cache transliteration across incremental hypotheses. Only CJK tokens
        // participate; unrelated Latin words never become phonetic aliases.
        for token in Set(query + window) where phonetics[token] == nil {
            let scalar = token.unicodeScalars.first!.value
            let chinese = (0x3400...0x9fff).contains(scalar) || (0x20000...0x3134f).contains(scalar)
            phonetics[token] = chinese ? "han:" + (token.applyingTransform(.mandarinToLatin, reverse: false)?
                .applyingTransform(.stripDiacritics, reverse: false) ?? token) : "literal:" + token
        }

        let windowPhonetics = window.map { phonetics[$0] }
        func candidate(_ words: [String], minimumSimilarity: Double, maximumAdvance: Int?) -> Int? {
            let wordPhonetics = words.map { phonetics[$0] }
            // Free source prefix, penalized query prefix. Partial hypotheses
            // replace earlier output rather than appending duplicate progress.
            var previous = Array(repeating: 0.0, count: window.count + 1)
            for i in words.indices {
                var row = Array(repeating: 0.0, count: window.count + 1)
                row[0] = Double(i + 1)
                for j in window.indices {
                    let cost: Double = words[i] == window[j] ? 0 :
                        (wordPhonetics[i] == windowPhonetics[j] ? 0.28 : 1)
                    row[j + 1] = min(previous[j] + cost, previous[j + 1] + 1, row[j] + 1)
                }
                previous = row
            }
            var best: (end: Int, rank: Double)?
            for j in 1...window.count {
                let end = lower + j
                let errors = previous[j]
                let similarity = 1 - errors / Double(words.count)
                guard similarity >= minimumSimilarity, Double(words.count) - errors >= Double(minimum) - 0.5 else { continue }
                if let maximumAdvance {
                    guard end > cursor, end <= cursor + maximumAdvance else { continue }
                }
                // Short common phrases must not jump across a paragraph.
                guard end <= cursor + 32 || (words.count >= 8 && similarity >= 0.88) else { continue }
                let rank = errors + Double(abs(end - cursor)) * 0.015
                if best == nil || rank < best!.rank { best = (end, rank) }
            }
            return best?.end
        }
        let whole = candidate(query, minimumSimilarity: 0.72, maximumAdvance: nil)
        // A bad prefix in a long ASR segment must not block a clearly matching
        // recent phrase. Recovery is local, forward-only and requires eight
        // nearly exact recent tokens; noise still cannot authorize scrolling.
        let recent = whole == nil && query.count >= 12
            ? candidate(Array(query.suffix(8)), minimumSimilarity: 0.9, maximumAdvance: 24) : nil
        guard let end = whole ?? recent else { return nil }
        cursor = max(cursor, end)
        return .init(utf16End: script.ends[cursor - 1], tokenEnd: cursor,
                     reachedEnd: end == script.tokens.count)
    }
}

/// The microphone remains armed during natural pauses. Manual pause is owned by
/// PlayerView; a permanent pause tears down capture, while touch handoff resets
/// the recognition stream and search window before resuming.
struct SpeechFollowTiming {
    private(set) var lastVoice: TimeInterval?
    private(set) var lastMatch: TimeInterval?
    private(set) var lastToken: Int?
    private(set) var tokensPerSecond: Double = 3

    mutating func observeVoice(at time: TimeInterval) { lastVoice = time }

    mutating func observeMatch(token: Int, at time: TimeInterval) {
        if let lastMatch, let lastToken, time > lastMatch, token > lastToken {
            let observed = min(12, max(0.5, Double(token - lastToken) / (time - lastMatch)))
            tokensPerSecond = tokensPerSecond * 0.4 + observed * 0.6
        }
        if lastToken == nil || token > lastToken! {
            lastMatch = time
            lastToken = token
        }
    }

    func canAdvance(at time: TimeInterval) -> Bool {
        guard let lastVoice, let lastMatch else { return false }
        return time - lastVoice < 0.65 && time - lastMatch < 1.5
    }

    /// Keep the low-speed floor alive between ASR batches. Actual speech and a
    /// recent successful alignment are both required; a silent armed mic is not.
    func cruiseDeadline(at time: TimeInterval, hasVoice: Bool) -> TimeInterval? {
        guard hasVoice, let lastVoice, let lastMatch,
              time >= lastVoice, time >= lastMatch,
              time - lastVoice < 0.65, time - lastMatch < 6 else { return nil }
        return min(lastVoice + 0.65, lastMatch + 6)
    }
}
