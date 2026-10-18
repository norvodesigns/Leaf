import Foundation

/// Finding, grouping, summarising and exporting the reader's journal, with no AI involved: counts, dates and the
/// reader's own words.
///
/// Titles come from the entries themselves (they are stored with each entry, so a quote still reads properly after the
/// book leaves the library); the library only fills in for older entries that have none.
struct JournalTools: Sendable {
    let entries: [JournalEntry]
    let calendar: Calendar
    private let libraryTitles: [String: (title: String, author: String)]

    init(entries: [JournalEntry], library: [LibraryItem] = [], calendar: Calendar) {
        self.entries = entries
        self.calendar = calendar
        var titles: [String: (title: String, author: String)] = [:]
        for item in library where titles[item.id] == nil { titles[item.id] = (item.book.title, item.book.author) }
        libraryTitles = titles
    }

    init(data: LeafData, calendar: Calendar) {
        self.init(entries: data.journal, library: data.items, calendar: calendar)
    }

    // MARK: Search and filter

    /// What to keep. Every field that is set must match; `text` words must all appear (in the entry, the book title or
    /// the author), ignoring case and accents.
    struct Filter: Hashable, Sendable {
        var bookID: String?
        var kind: JournalEntry.Kind?
        var favouritesOnly = false
        var text = ""

        init(bookID: String? = nil, kind: JournalEntry.Kind? = nil, favouritesOnly: Bool = false, text: String = "") {
            self.bookID = bookID
            self.kind = kind
            self.favouritesOnly = favouritesOnly
            self.text = text
        }
    }

    /// Matching entries, newest first.
    func search(_ filter: Filter = Filter()) -> [JournalEntry] {
        let words = JournalTools.searchWords(filter.text)
        return entries
            .filter { entry in
                if let bookID = filter.bookID, entry.bookID != bookID { return false }
                if let kind = filter.kind, entry.kind != kind { return false }
                if filter.favouritesOnly, !entry.isFavorite { return false }
                guard !words.isEmpty else { return true }
                let haystack = JournalTools.fold(entry.text + " " + title(of: entry) + " " + author(of: entry))
                return words.allSatisfy { haystack.contains($0) }
            }
            .sorted(by: JournalTools.newestFirst)
    }

    // MARK: Grouping

    /// All of one book's entries.
    struct BookGroup: Hashable, Identifiable, Sendable {
        var bookID: String
        var title: String
        var author: String
        /// In reading order: by page (entries without a page last), then by when they were written.
        var entries: [JournalEntry]

        var id: String { bookID }
    }

    /// Entries grouped by book, the book written in most recently first.
    func groupedByBook(_ filter: Filter = Filter()) -> [BookGroup] {
        let matching = search(filter)
        let grouped = Dictionary(grouping: matching, by: \.bookID)
        let groups = grouped.map { bookID, items -> BookGroup in
            let first = items[0]
            return BookGroup(
                bookID: bookID,
                title: title(of: first, among: items),
                author: author(of: first, among: items),
                entries: items.sorted(by: JournalTools.readingOrder)
            )
        }
        return groups.sorted { lhs, rhs in
            let l = lhs.entries.map(\.createdAt).max() ?? .distantPast
            let r = rhs.entries.map(\.createdAt).max() ?? .distantPast
            if l != r { return l > r }
            return lhs.bookID < rhs.bookID
        }
    }

    // MARK: Quote of the day

    /// A quote for `now`, the same one all day and a different one tomorrow. Quotes are dealt out in a seeded shuffle,
    /// so none comes back until every other has been shown. Nil when there are no quotes.
    ///
    /// - Parameters:
    ///   - favouritesOnly: draw only from starred quotes.
    ///   - seed: mixes into the shuffle, so a widget and the app can agree or differ on purpose.
    func quoteOfTheDay(now: Date, favouritesOnly: Bool = false, seed: UInt64 = 0) -> JournalEntry? {
        let pool = entries
            .filter { $0.kind == .quote && (!favouritesOnly || $0.isFavorite) }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        guard !pool.isEmpty else { return nil }

        let day = JournalTools.dayNumber(now, calendar: calendar)
        let count = pool.count
        let cycle = Int(floorDiv(day, count))
        let position = Int(day - Int64(cycle) * Int64(count))
        var order = Array(0..<count)
        var rng = SeededGenerator(seed: SeededGenerator.hash("quote-cycle-\(cycle)") ^ seed)
        // Fisher-Yates with the seeded generator: the same cycle always deals the same order.
        if count > 1 {
            for index in stride(from: count - 1, to: 0, by: -1) {
                let swap = Int(rng.next() % UInt64(index + 1))
                order.swapAt(index, swap)
            }
        }
        return pool[order[position]]
    }

    private func floorDiv(_ a: Int64, _ b: Int) -> Int64 {
        let divisor = Int64(b)
        let q = a / divisor
        return (a % divisor != 0 && (a < 0) != (divisor < 0)) ? q - 1 : q
    }

    // MARK: Per-book summary

    /// Counts and dates for one book's notes, built without AI.
    struct BookSummary: Hashable, Identifiable, Sendable {
        var bookID: String
        var title: String
        var author: String
        var entryCount: Int
        var thoughts: Int
        var quotes: Int
        var favourites: Int
        var firstEntry: Date?
        var lastEntry: Date?
        /// Lowest and highest page with an entry, or nil when no entry has a page.
        var firstPage: Int?
        var lastPage: Int?
        /// The newest starred quote, or nil when none is starred.
        var favouriteQuote: JournalEntry?
        /// The favourite quote, or the newest quote when none is starred. Nil without quotes.
        var featuredQuote: JournalEntry?

        var id: String { bookID }
    }

    func summary(forBook bookID: String) -> BookSummary {
        let mine = entries.filter { $0.bookID == bookID }.sorted(by: JournalTools.newestFirst)
        let quotes = mine.filter { $0.kind == .quote }
        let favouriteQuote = quotes.first { $0.isFavorite }
        let pages = mine.compactMap(\.page)
        return BookSummary(
            bookID: bookID,
            title: title(of: mine.first, bookID: bookID, among: mine),
            author: author(of: mine.first, bookID: bookID, among: mine),
            entryCount: mine.count,
            thoughts: mine.filter { $0.kind == .thought }.count,
            quotes: quotes.count,
            favourites: mine.filter(\.isFavorite).count,
            firstEntry: mine.map(\.createdAt).min(),
            lastEntry: mine.map(\.createdAt).max(),
            firstPage: pages.min(),
            lastPage: pages.max(),
            favouriteQuote: favouriteQuote,
            featuredQuote: favouriteQuote ?? quotes.first
        )
    }

    /// A summary for every book with entries, most recently written in first.
    func summaries() -> [BookSummary] {
        groupedByBook().map { summary(forBook: $0.bookID) }
    }

    // MARK: Markdown export

    /// One book's journal as Markdown. Entries run in reading order with their page numbers; dates are ISO so the text
    /// is the same in every locale. Empty when the book has no entries.
    func markdown(forBook bookID: String) -> String {
        let group = groupedByBook(Filter(bookID: bookID)).first
        guard let group else { return "" }
        return "# " + JournalTools.escapeInline(group.title) + "\n\n" + bookBody(group, includeTitle: false)
    }

    /// The whole journal (or the part that matches `filter`) as Markdown, books in title order.
    func markdown(filter: Filter = Filter()) -> String {
        let groups = groupedByBook(filter).sorted { lhs, rhs in
            let l = lhs.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            let r = rhs.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return l != r ? l < r : lhs.bookID < rhs.bookID
        }
        guard !groups.isEmpty else { return "# Reading journal\n\nNothing saved yet.\n" }
        let total = groups.reduce(0) { $0 + $1.entries.count }
        var out = "# Reading journal\n\n"
        out += "\(total) \(total == 1 ? "entry" : "entries") from \(groups.count) \(groups.count == 1 ? "book" : "books").\n"
        for group in groups {
            out += "\n" + bookBody(group, includeTitle: true)
        }
        return out
    }

    private func bookBody(_ group: BookGroup, includeTitle: Bool) -> String {
        var out = ""
        if includeTitle { out += "## " + JournalTools.escapeInline(group.title) + "\n\n" }
        let quotes = group.entries.filter { $0.kind == .quote }.count
        let thoughts = group.entries.count - quotes
        var facts: [String] = []
        if !group.author.isEmpty { facts.append("*" + JournalTools.escapeInline(group.author) + "*") }
        if quotes > 0 { facts.append("\(quotes) \(quotes == 1 ? "quote" : "quotes")") }
        if thoughts > 0 { facts.append("\(thoughts) \(thoughts == 1 ? "thought" : "thoughts")") }
        out += facts.joined(separator: " · ") + "\n"

        for entry in group.entries {
            out += "\n"
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var stamp = [String]()
            if let page = entry.page { stamp.append("p. \(page)") }
            stamp.append(isoDate(entry.createdAt))
            let line = stamp.joined(separator: ", ") + (entry.isFavorite ? " ★" : "")
            switch entry.kind {
            case .quote:
                for textLine in text.components(separatedBy: .newlines) {
                    out += textLine.isEmpty ? ">\n" : "> " + textLine + "\n"
                }
                out += ">\n> — " + line + "\n"
            case .thought:
                out += text.components(separatedBy: .newlines).map(JournalTools.escapeBlockStart).joined(separator: "\n") + "\n"
                out += "\n*" + line + "*\n"
            }
        }
        return out
    }

    // MARK: Helpers

    private func title(of entry: JournalEntry) -> String {
        entry.bookTitle.isEmpty ? (libraryTitles[entry.bookID]?.title ?? "") : entry.bookTitle
    }

    private func author(of entry: JournalEntry) -> String {
        entry.bookAuthor.isEmpty ? (libraryTitles[entry.bookID]?.author ?? "") : entry.bookAuthor
    }

    private func title(of entry: JournalEntry, among items: [JournalEntry]) -> String {
        title(of: entry, bookID: entry.bookID, among: items)
    }

    private func author(of entry: JournalEntry, among items: [JournalEntry]) -> String {
        author(of: entry, bookID: entry.bookID, among: items)
    }

    /// The newest non-empty title stored on an entry, else the library's, else empty.
    private func title(of entry: JournalEntry?, bookID: String, among items: [JournalEntry]) -> String {
        if let stored = items.sorted(by: JournalTools.newestFirst).first(where: { !$0.bookTitle.isEmpty })?.bookTitle { return stored }
        if let entry, !entry.bookTitle.isEmpty { return entry.bookTitle }
        return libraryTitles[bookID]?.title ?? ""
    }

    private func author(of entry: JournalEntry?, bookID: String, among items: [JournalEntry]) -> String {
        if let stored = items.sorted(by: JournalTools.newestFirst).first(where: { !$0.bookAuthor.isEmpty })?.bookAuthor { return stored }
        if let entry, !entry.bookAuthor.isEmpty { return entry.bookAuthor }
        return libraryTitles[bookID]?.author ?? ""
    }

    private func isoDate(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func newestFirst(_ lhs: JournalEntry, _ rhs: JournalEntry) -> Bool {
        lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id.uuidString < rhs.id.uuidString
    }

    /// By page (pages first, entries without one last), then oldest first.
    static func readingOrder(_ lhs: JournalEntry, _ rhs: JournalEntry) -> Bool {
        switch (lhs.page, rhs.page) {
        case let (l?, r?) where l != r: return l < r
        case (.some, nil): return true
        case (nil, .some): return false
        default:
            return lhs.createdAt != rhs.createdAt ? lhs.createdAt < rhs.createdAt : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func searchWords(_ text: String) -> [String] {
        fold(text).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// A day count that goes up by one each calendar day in `calendar`, whatever the calendar: whole local days since
    /// the start of 1 January 1970 (UTC) as seen in that calendar's time zone.
    static func dayNumber(_ date: Date, calendar: Calendar) -> Int64 {
        let reference = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        let days = calendar.dateComponents([.day], from: reference, to: calendar.startOfDay(for: date)).day
        return Int64(days ?? Int((date.timeIntervalSince1970 / 86_400).rounded(.down)))
    }

    /// Escapes characters that would turn a title or author into formatting.
    static func escapeInline(_ text: String) -> String {
        var out = ""
        for character in text.replacingOccurrences(of: "\n", with: " ") {
            if "\\`*_[]<>".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Keeps a line of a thought from being read as a heading, list or quote.
    static func escapeBlockStart(_ line: String) -> String {
        let trimmed = line.drop(while: { $0 == " " })
        guard let first = trimmed.first else { return line }
        if "#>-+*".contains(first) { return "\\" + line }
        if first.isNumber, let dot = trimmed.firstIndex(where: { !$0.isNumber }), trimmed[dot] == "." || trimmed[dot] == ")" {
            return "\\" + line
        }
        return line
    }
}
