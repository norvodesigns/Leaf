import Foundation

// MARK: - Tea history

/// What the reader has read with: minutes per tea, the books each went with, and what their tasting notes say.
/// Built from sessions (which save the tea they began with), the cabinet (for the reader's own teas' names) and
/// tasting notes. Pure.
struct TeaHistory: Hashable, Sendable {
    struct TeaLine: Identifiable, Hashable, Sendable {
        var teaID: String
        var name: String
        var family: TeaFamily?
        var minutes: Double
        var sessions: Int
        /// How many different books it was read with.
        var books: Int
        var lastBrewed: Date?
        var tastings: Int
        /// The average rating of its tasting notes, when any are rated.
        var averageRating: Double?

        var id: String { teaID }
    }

    struct BookLine: Identifiable, Hashable, Sendable {
        struct TeaShare: Hashable, Sendable {
            var teaID: String
            var name: String
            var minutes: Double
        }

        var bookID: String
        var title: String
        var author: String
        /// Teas this book was read with, most minutes first.
        var teas: [TeaShare]
        var lastRead: Date

        var id: String { bookID }
    }

    /// Most minutes first.
    var teas: [TeaLine]
    /// Most recently read first.
    var books: [BookLine]
    /// Newest first.
    var tastings: [TastingNote]
    /// Minutes read with any tea, and in all.
    var minutesWithTea: Double
    var minutesInAll: Double

    /// The tea read with most.
    var mostReadWith: TeaLine? { teas.first }

    var isEmpty: Bool { teas.isEmpty && tastings.isEmpty }

    /// Share of all reading minutes that had a cup alongside, 0 to 1.
    var teaShare: Double { minutesInAll > 0 ? min(1, minutesWithTea / minutesInAll) : 0 }

    static func build(data: LeafData) -> TeaHistory {
        var minutes: [String: Double] = [:]
        var sessions: [String: Int] = [:]
        var booksPerTea: [String: Set<String>] = [:]
        var last: [String: Date] = [:]
        var perBook: [String: [String: Double]] = [:]
        var bookLast: [String: Date] = [:]
        var withTea = 0.0
        var inAll = 0.0
        for session in data.sessions {
            let sessionMinutes = max(0, session.seconds) / 60
            inAll += sessionMinutes
            guard let teaID = session.teaID, !teaID.isEmpty else { continue }
            withTea += sessionMinutes
            minutes[teaID, default: 0] += sessionMinutes
            sessions[teaID, default: 0] += 1
            booksPerTea[teaID, default: []].insert(session.bookID)
            last[teaID] = max(last[teaID] ?? .distantPast, session.startedAt)
            perBook[session.bookID, default: [:]][teaID, default: 0] += sessionMinutes
            bookLast[session.bookID] = max(bookLast[session.bookID] ?? .distantPast, session.startedAt)
        }
        var ratings: [String: [Int]] = [:]
        var tastingCounts: [String: Int] = [:]
        var tastedNames: [String: (name: String, family: TeaFamily?)] = [:]
        for note in data.tastings {
            tastingCounts[note.teaID, default: 0] += 1
            if let rating = note.rating { ratings[note.teaID, default: []].append(rating) }
            tastedNames[note.teaID] = (note.teaName, note.family)
        }

        func describe(_ teaID: String) -> (name: String, family: TeaFamily?) {
            if let tea = TeaShelf.tea(id: teaID, cabinet: data.cabinet) { return (tea.name, tea.family) }
            if let named = tastedNames[teaID], !named.name.isEmpty { return named }
            return ("A tea", nil)
        }

        let ids = Set(minutes.keys).union(tastingCounts.keys)
        let lines = ids.map { id -> TeaLine in
            let described = describe(id)
            let rated = ratings[id] ?? []
            return TeaLine(
                teaID: id, name: described.name, family: described.family,
                minutes: minutes[id] ?? 0, sessions: sessions[id] ?? 0, books: booksPerTea[id]?.count ?? 0,
                lastBrewed: last[id], tastings: tastingCounts[id] ?? 0,
                averageRating: rated.isEmpty ? nil : Double(rated.reduce(0, +)) / Double(rated.count)
            )
        }
        .sorted { $0.minutes > $1.minutes || ($0.minutes == $1.minutes && ($0.tastings > $1.tastings || ($0.tastings == $1.tastings && $0.teaID < $1.teaID))) }

        let items = Dictionary(data.items.map { ($0.id, $0.book) }, uniquingKeysWith: { first, _ in first })
        let titles = Dictionary(data.journal.map { ($0.bookID, ($0.bookTitle, $0.bookAuthor)) }, uniquingKeysWith: { first, _ in first })
        let bookLines = perBook.compactMap { bookID, teas -> BookLine? in
            let book = items[bookID]
            guard let title = book?.title ?? titles[bookID]?.0, !title.isEmpty else { return nil }
            let shares = teas.map { BookLine.TeaShare(teaID: $0.key, name: describe($0.key).name, minutes: $0.value) }
                .sorted { $0.minutes > $1.minutes || ($0.minutes == $1.minutes && $0.teaID < $1.teaID) }
            return BookLine(bookID: bookID, title: title, author: book?.author ?? titles[bookID]?.1 ?? "", teas: shares, lastRead: bookLast[bookID] ?? .distantPast)
        }
        .sorted { $0.lastRead > $1.lastRead || ($0.lastRead == $1.lastRead && $0.bookID < $1.bookID) }

        let notes = data.tastings.sorted { $0.createdAt > $1.createdAt || ($0.createdAt == $1.createdAt && $0.id.uuidString < $1.id.uuidString) }
        return TeaHistory(teas: lines, books: bookLines, tastings: notes, minutesWithTea: withTea, minutesInAll: inAll)
    }
}

// MARK: - Tea and book of the week

/// Today's weekly suggestion: one book and a tea to read it with, chosen from the forecast and the pairing.
struct TeaAndBook: Hashable, Sendable {
    var bookID: String
    var title: String
    var tea: Tea
    /// Why this tea, from the pairing (or "your pairing" when the reader pinned it).
    var reason: String
    /// The headline sentence: "Likely finished by Sunday. A pot of Earl Grey to see it home."
    var line: String
    var isPinned: Bool
}

enum TeaOfTheWeek {
    /// The book to read this week and its tea, or nil when nothing is being read or queued.
    ///
    /// The book: a book being read whose likely finish (the forecast's median) falls in the next seven days, the
    /// soonest first; else the book being read that is furthest along; else the first book on To read. The tea: the
    /// reader's pinned pairing for that book, else the best pairing from the cabinet's teas in stock (the catalog when
    /// the cabinet is empty).
    static func pick(data: LeafData, forecast: ForecastResult?, now: Date, calendar: Calendar) -> TeaAndBook? {
        let reading = data.items(on: .reading)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(7 * 86_400)
        let finishing = reading
            .compactMap { item -> (LibraryItem, Date)? in
                guard let median = forecast?.book(item.id)?.median, median < weekEnd else { return nil }
                return (item, median)
            }
            .sorted { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0.id < $1.0.id) }
            .first
        let furthest = reading.max { a, b in a.progress < b.progress || (a.progress == b.progress && a.id > b.id) }
        guard let item = finishing?.0 ?? furthest ?? data.items(on: .toRead).first else { return nil }

        let stock = TeaShelf.inStock(data.cabinet)
        let pool = stock.isEmpty ? TeaCatalog.all : stock
        let tea: Tea
        let reason: String
        let pinned: Bool
        if let pinnedID = item.pairedTeaID, let pinnedTea = TeaShelf.tea(id: pinnedID, cabinet: data.cabinet) {
            tea = pinnedTea
            reason = TeaPairing.reason(for: pinnedTea, with: item.book)
            pinned = true
        } else if let pick = TeaPairing.best(for: item.book, from: pool) {
            tea = pick.tea
            reason = pick.reason
            pinned = false
        } else {
            return nil
        }

        let line: String
        if let finish = finishing?.1 {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: finish)).day ?? 0
            let when = days <= 0 ? "today" : days == 1 ? "tomorrow" : "by " + LeafFormat.format(finish, template: "EEEE", calendar: calendar)
            line = "Likely finished \(when). A pot of \(tea.name) to see it home."
        } else if item.shelf == .reading {
            line = "Your book for the week, with a pot of \(tea.name) beside it."
        } else {
            line = "Next up, and a pot of \(tea.name) to begin it with."
        }
        return TeaAndBook(bookID: item.id, title: item.book.title, tea: tea, reason: reason, line: line, isPinned: pinned)
    }
}
