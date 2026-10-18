import Foundation

/// A book that matched a catalog search, with the full-text engine's relevance score (SQLite's `bm25`: lower, which
/// means more negative, is a better match).
struct CatalogCandidate: Sendable {
    var book: Book
    var bm25: Double
}

/// Turning what the reader typed into a safe SQLite FTS5 expression, and ordering what comes back.
///
/// Pure and Foundation-only so it is tested on Linux. `scripts/catalog/query.py` is the same function in Python (the
/// build checks time the real search SQL with it); both are tested against the same table of cases.
///
/// How search works: the database stores books in popularity order and FTS5 returns matches in that order, so the
/// first 300 matches are the 300 best-known ones without ranking everything that matches a short prefix. `rank`
/// then orders those 300 by how well they match what was typed, the way the old in-memory search did (exact title,
/// then title prefix, then title contains, popularity as the tie-break), plus a small nudge from `bm25`.
enum CatalogQuery {
    static let maxTerms = 6
    static let maxTermLength = 32
    /// How many popularity-ordered matches to fetch before ranking them.
    static let candidateLimit = 300

    // MARK: Text

    /// Lower-cased, accents removed, every run of anything that is not a letter or digit turned into one space.
    /// Plain ASCII, the common case on every keystroke and for every candidate title, skips Foundation entirely.
    static func normalize(_ text: String) -> String {
        if let ascii = normalizeASCII(text) { return ascii }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    private static func normalizeASCII(_ text: String) -> String? {
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count)
        var pendingSpace = false
        for byte in text.utf8 {
            if byte >= 0x80 { return nil }
            var b = byte
            if b >= 0x41 && b <= 0x5A { b += 0x20 }
            let isWordByte = (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39)
            if isWordByte {
                if pendingSpace && !out.isEmpty { out.append(0x20) }
                pendingSpace = false
                out.append(b)
            } else {
                pendingSpace = true
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// The searchable words of `text`: at most `maxTerms`, each cut to `maxTermLength` characters.
    static func terms(_ text: String) -> [String] {
        normalize(text).split(separator: " ").prefix(maxTerms).map { String($0.prefix(maxTermLength)) }
    }

    /// An FTS5 `MATCH` expression such as `"harry"* "pot"*`, or nil when nothing searchable was typed.
    ///
    /// Every word is a quoted string, so FTS5 operators typed by the reader (`OR`, `NEAR`, `title:`, `-`, `*`,
    /// parentheses) become plain words and can neither change the query nor make it a syntax error. A word of two or
    /// more characters is a prefix, so results appear as the reader types. A one character word is an exact word:
    /// a one letter prefix has to merge every index term starting with it, which costs ten times a normal query
    /// and matches nearly everything anyway.
    static func ftsExpression(for text: String) -> String? {
        let words = terms(text)
        guard !words.isEmpty else { return nil }
        return words.map { $0.count >= 2 ? "\"\($0)\"*" : "\"\($0)\"" }.joined(separator: " ")
    }

    // MARK: Stored lists

    /// `"3 17 204"` to `[3, 17, 204]`; anything that is not a number is skipped.
    static func decodeIDs(_ text: String?) -> [Int] {
        (text ?? "").split(separator: " ").compactMap { Int($0) }
    }

    /// `"310,330,366"` to `[310, 330, 366]`.
    static func decodeCounts(_ text: String?) -> [Int] {
        (text ?? "").split(separator: ",").compactMap { Int($0) }
    }

    // MARK: Ranking

    /// How good a match `candidate` is for the normalized query `query`; higher is better.
    static func score(_ candidate: CatalogCandidate, normalizedQuery query: String) -> Double {
        var score = log(Double(max(candidate.book.popularity, 0)) + 10)
        let title = normalize(candidate.book.title)
        if title == query { score += 40 }
        else if title.hasPrefix(query) { score += 20 }
        else if title.contains(query) { score += 8 }
        if normalize(candidate.book.author).contains(query) { score += 10 }
        // bm25 is negative, and about -15 for a very specific match. Worth at most a few points: enough to order
        // near-ties, never enough to beat an exact title.
        score += 0.3 * min(max(-candidate.bm25, 0), 15)
        return score
    }

    /// The best `limit` books among `candidates` for what was typed. Deterministic: ties fall to popularity, then id.
    static func rank(_ candidates: [CatalogCandidate], query: String, limit: Int) -> [Book] {
        let normalized = normalize(query)
        guard !normalized.isEmpty, limit > 0 else { return [] }
        let scored = candidates.map { (candidate: $0, score: score($0, normalizedQuery: normalized)) }
        let ordered = scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.candidate.book.popularity != b.candidate.book.popularity { return a.candidate.book.popularity > b.candidate.book.popularity }
            return a.candidate.book.id < b.candidate.book.id
        }
        return ordered.prefix(limit).map(\.candidate.book)
    }
}
