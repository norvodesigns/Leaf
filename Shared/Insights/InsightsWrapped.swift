import Foundation

// MARK: - Reading Wrapped

/// The year as a story of six to eight cards, built on the Year in Books: the books and pages, the tea drunk most, the
/// best hour, the longest streak, the book taken longest over, the most-quoted book and the reading personality, then
/// the year's shelf. A card without anything to say is left out; when that leaves fewer than six, the genre, the
/// busiest month and the fastest book fill in.
struct WrappedStory: Hashable, Sendable {
    enum Card: String, Hashable, Identifiable, Sendable {
        case books, tea, hour, streak, slowBurn = "slowburn", quoted, genre, month, fastest, personality, shelf

        var id: String { rawValue }
    }

    struct TeaOfTheYear: Hashable, Sendable {
        var teaID: String
        var name: String
        var family: TeaFamily?
        /// Sittings with this tea.
        var sittings: Int
        var minutes: Double
        /// Sittings with any tea at all.
        var teaSittings: Int
        /// Every sitting of the year.
        var allSittings: Int
    }

    struct BestHour: Hashable, Sendable {
        /// 0 to 23.
        var hour: Int
        var minutes: Double
        /// Share of the year's timed reading that began in this hour, 0 to 1.
        var share: Double
    }

    struct MostQuoted: Hashable, Sendable {
        var bookID: String
        var title: String
        var author: String
        /// Quotes kept from it this year.
        var quotes: Int
        /// The favourite of them, or else the newest.
        var text: String
        var page: Int?
    }

    var year: Int
    var summary: YearInBooks
    var tea: TeaOfTheYear?
    var hour: BestHour?
    /// The finished book with the most days between its start and its finish.
    var slowBurn: YearInBooks.BookHighlight?
    var quoted: MostQuoted?
    var personality: ReadingPersonality
    var cards: [Card]

    static let maximumCards = 8
    static let fewestCards = 6

    /// Nothing read and nothing finished: no story to tell.
    var isEmpty: Bool { summary.isEmpty }

    /// The cards in order. The opening and the personality always come; the rest when they have something to show.
    static func cards(
        summary: YearInBooks, tea: TeaOfTheYear?, hour: BestHour?, slowBurn: YearInBooks.BookHighlight?, quoted: MostQuoted?
    ) -> [Card] {
        var middle: [Card] = []
        if tea != nil { middle.append(.tea) }
        if hour != nil { middle.append(.hour) }
        if summary.longestStreak >= 2 { middle.append(.streak) }
        if slowBurn != nil { middle.append(.slowBurn) }
        if quoted != nil { middle.append(.quoted) }
        let closing: [Card] = summary.booksFinished > 0 ? [.personality, .shelf] : [.personality]

        var fillers: [Card] = []
        if summary.topGenre != nil { fillers.append(.genre) }
        if summary.busiestMonth != nil { fillers.append(.month) }
        if let fastest = summary.fastestBook, fastest.id != slowBurn?.id, summary.booksFinished > 1 { fillers.append(.fastest) }
        for filler in fillers where 1 + middle.count + closing.count < fewestCards {
            middle.append(filler)
        }
        return Array(([Card.books] + middle + closing).prefix(maximumCards))
    }
}

extension InsightsEngine {
    /// The story of `year`.
    func wrappedStory(year: Int) -> WrappedStory {
        let summary = yearInBooks(year: year)
        let tea = teaOfTheYear(year)
        let hour = bestHour(year, favourite: summary.favouriteHour)
        let slowBurn = summary.finishedBooks
            .filter { ($0.days ?? 0) >= 2 }
            .max { (a: YearInBooks.BookHighlight, b: YearInBooks.BookHighlight) -> Bool in
                let x = a.days ?? 0
                let y = b.days ?? 0
                if x != y { return x < y }
                if a.pages != b.pages { return a.pages < b.pages }
                return a.finishedAt > b.finishedAt
            }
        let quoted = mostQuoted(year)
        return WrappedStory(
            year: year,
            summary: summary,
            tea: tea,
            hour: hour,
            slowBurn: slowBurn,
            quoted: quoted,
            personality: personality(),
            cards: WrappedStory.cards(summary: summary, tea: tea, hour: hour, slowBurn: slowBurn, quoted: quoted)
        )
    }

    /// The tea of the most sittings this year (then the most minutes, then the id).
    private func teaOfTheYear(_ year: Int) -> WrappedStory.TeaOfTheYear? {
        var counts: [String: Int] = [:]
        var minutes: [String: Double] = [:]
        var teaSittings = 0
        var all = 0
        for session in data.sessions where session.seconds >= 60 && self.year(of: session.startedAt) == year {
            all += 1
            guard let teaID = session.teaID, !teaID.isEmpty else { continue }
            teaSittings += 1
            counts[teaID, default: 0] += 1
            minutes[teaID, default: 0] += session.seconds / 60
        }
        var best: String?
        for id in counts.keys {
            guard let current = best else {
                best = id
                continue
            }
            let a = counts[id] ?? 0
            let b = counts[current] ?? 0
            let m = minutes[id] ?? 0
            let n = minutes[current] ?? 0
            if a > b || (a == b && m > n + 1e-9) || (a == b && abs(m - n) <= 1e-9 && id < current) { best = id }
        }
        guard let best else { return nil }
        let tea = TeaShelf.tea(id: best, cabinet: data.cabinet)
        let tasted = data.tastings.last { $0.teaID == best && !$0.teaName.isEmpty }
        return WrappedStory.TeaOfTheYear(
            teaID: best,
            name: tea?.name ?? tasted?.teaName ?? "A tea of your own",
            family: tea?.family ?? tasted?.family,
            sittings: counts[best] ?? 0,
            minutes: minutes[best] ?? 0,
            teaSittings: teaSittings,
            allSittings: all
        )
    }

    /// The Year in Books' favourite hour, with its share of the year's timed reading.
    private func bestHour(_ year: Int, favourite: Int?) -> WrappedStory.BestHour? {
        guard let favourite else { return nil }
        var total = 0.0
        var inHour = 0.0
        for sitting in sittings where sitting.isTimed && sitting.countsAsReading && self.year(of: sitting.day) == year {
            total += sitting.minutes
            if sitting.hour == favourite { inHour += sitting.minutes }
        }
        guard total > 0, inHour > 0 else { return nil }
        return WrappedStory.BestHour(hour: favourite, minutes: inHour, share: inHour / total)
    }

    /// The book with the most quotes kept this year (then the newest quote, then the title).
    private func mostQuoted(_ year: Int) -> WrappedStory.MostQuoted? {
        var byBook: [String: [JournalEntry]] = [:]
        for entry in data.journal where entry.kind == .quote && self.year(of: entry.createdAt) == year {
            guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            byBook[entry.bookID, default: []].append(entry)
        }
        func newest(_ entries: [JournalEntry]) -> Date { entries.map(\.createdAt).max() ?? .distantPast }
        let ranked = byBook.sorted { (a: (key: String, value: [JournalEntry]), b: (key: String, value: [JournalEntry])) -> Bool in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            let x = newest(a.value)
            let y = newest(b.value)
            if x != y { return x > y }
            return a.key < b.key
        }
        guard let top = ranked.first else { return nil }
        let bookID = top.key
        let entries = top.value
        let pick = entries.max { (a: JournalEntry, b: JournalEntry) -> Bool in
            if a.isFavorite != b.isFavorite { return b.isFavorite }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
        guard let pick else { return nil }
        let item = itemsByID[bookID]
        return WrappedStory.MostQuoted(
            bookID: bookID,
            title: item?.book.title ?? pick.bookTitle,
            author: item?.book.author ?? pick.bookAuthor,
            quotes: entries.count,
            text: pick.text,
            page: pick.page
        )
    }
}

// MARK: - When to offer it

enum WrappedOffer {
    /// The year Leaf offers a story for unasked: this year all through December, and last year in the first week of
    /// January, for anyone who reads on New Year's Eve. Any other day it waits to be asked for.
    static func offeredYear(now: Date, calendar: Calendar) -> Int? {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month else { return nil }
        if month == 12 { return year }
        if month == 1, (parts.day ?? 99) <= 7 { return year - 1 }
        return nil
    }

    /// A year with a story in it: a sitting of a minute or more, or a finish.
    static func hasStory(data: LeafData, year: Int, calendar: Calendar) -> Bool {
        if data.sessions.contains(where: { $0.seconds >= 60 && calendar.component(.year, from: $0.startedAt) == year }) { return true }
        return data.items.contains { item in
            item.readThroughs.contains { calendar.component(.year, from: $0.finishedAt) == year }
        }
    }
}
