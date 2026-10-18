import Foundation

/// The rules every line of copy has to follow, in one place. The tests check the whole greeting pool and every other
/// surface against these, and the on-device AI writer runs its output through the same checks and throws away
/// anything that breaks one, so a generated line can never be less kind than a hand-written one.
enum VoiceTone {
    static let maxHeadlineWords = 12
    static let maxSublineWords = 14

    enum Violation: Equatable, Sendable {
        case empty
        case exclamation
        case tooLong(words: Int, limit: Int)
        case banned(String)
        case emoji
    }

    /// Single words that carry guilt. Matched as whole words, so "close" is fine and "lost" is not.
    static let bannedWords: Set<String> = [
        "miss", "missed", "misses", "missing",
        "lose", "loses", "losing", "lost",
        "behind", "failing", "fail", "failed", "lazy", "guilty", "overdue",
    ]

    /// Phrases that nag, threaten a streak or scold.
    static let bannedPhrases: [String] = [
        "should have", "shouldn't have", "don't break", "do not break", "lost your streak", "lose your streak",
        "break your streak", "break the streak", "keep your streak", "save your streak", "streak is at risk",
        "last chance", "falling behind", "catch up", "don't forget", "you haven't", "you didn't", "no excuse", "hurry up",
    ]

    /// Tea and cozy words. They are seasoning: about one line in three may use one.
    static let cozyWords: Set<String> = [
        "tea", "teas", "teapot", "kettle", "cup", "cups", "pot", "steep", "steeps", "steeping", "brew", "brewed",
        "lamp", "lamplight", "blanket", "nook", "bookmark", "cozy", "cosy", "hearth", "fireplace", "fireside",
        "candle", "candlelight", "slippers", "mug", "biscuit", "biscuits", "cocoa", "chai", "quilt", "armchair",
        "cardigan", "scone", "scones",
    ]

    // MARK: Checks

    /// Everything wrong with a headline and its optional subline. Empty means the copy is fine.
    /// `ignoring` removes names (a book title, a tea) before the word checks, so a book called "The Lost Boys"
    /// does not fail a line that merely mentions it.
    static func violations(headline: String, subline: String? = nil, ignoring names: [String] = []) -> [Violation] {
        var result = violations(in: headline, maxWords: maxHeadlineWords, ignoring: names)
        if let subline {
            result += violations(in: subline, maxWords: maxSublineWords, ignoring: names)
        }
        return result
    }

    static func violations(in text: String, maxWords: Int, ignoring names: [String] = []) -> [Violation] {
        var result: [Violation] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [.empty] }
        if trimmed.contains("!") || trimmed.contains("¡") { result.append(.exclamation) }
        let count = wordCount(trimmed)
        if count > maxWords { result.append(.tooLong(words: count, limit: maxWords)) }
        if trimmed.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { result.append(.emoji) }

        var checked = normalized(trimmed)
        for name in names where !name.isEmpty {
            checked = checked.replacingOccurrences(of: normalized(name), with: " ")
        }
        let stems = Set(words(in: checked).map(stem))
        for word in bannedWords.sorted() where stems.contains(word) { result.append(.banned(word)) }
        for phrase in bannedPhrases where checked.contains(phrase) { result.append(.banned(phrase)) }
        return result
    }

    static func isAcceptable(headline: String, subline: String? = nil, ignoring names: [String] = []) -> Bool {
        violations(headline: headline, subline: subline, ignoring: names).isEmpty
    }

    /// Whether the text leans on tea or cozy vocabulary.
    static func isCozy(_ text: String) -> Bool {
        let stems = Set(words(in: normalized(text)).map(stem))
        return !stems.isDisjoint(with: cozyWords)
    }

    // MARK: Text helpers

    /// Words as a reader counts them: pieces separated by whitespace that hold a letter or a digit.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).filter { piece in piece.contains(where: { $0.isLetter || $0.isNumber }) }.count
    }

    /// Lowercase, straight apostrophes and quotes, single spaces. Makes phrase matching independent of typography.
    static func normalized(_ text: String) -> String {
        let straight = text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .lowercased()
        return straight.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func words(in normalizedText: String) -> [String] {
        normalizedText.split(whereSeparator: { !($0.isLetter || $0 == "'") }).map(String.init)
    }

    /// "kettle's" is the kettle.
    private static func stem(_ word: String) -> String {
        word.hasSuffix("'s") ? String(word.dropLast(2)) : word
    }
}
