import Foundation

// MARK: - A spine

/// One finished book standing on the shelf wall, in the year it was finished. A book finished in two years stands in
/// both; a book finished twice in one year stands once, counting both.
struct ShelfSpine: Hashable, Identifiable, Sendable {
    var book: Book
    var year: Int
    /// The year's last finish, or nil for a book marked finished without a date.
    var finishedAt: Date?
    /// That finish's rating, 1 to 5, or nil when it wasn't rated.
    var rating: Int?
    /// How many times the book was finished that year.
    var finishes: Int
    /// The tea read with it most (by minutes) in that year's read-throughs, or nil when it was read without tea.
    var teaID: String?
    /// Points across: thicker for longer books.
    var width: Double
    /// Share of the shelf's height, 0.8 to 1, the same for a book every time.
    var height: Double

    var id: String { "\(book.id)@\(year)" }
    /// Five stars: it gets a ribbon.
    var isFavorite: Bool { rating == 5 }
    var hasTea: Bool { teaID != nil }
}

// MARK: - The wall

/// The Finished shelf as a wall of spines, a shelf per year, newest year on top and each year's books in the order
/// they were finished. Pure and cheap: one pass over the books and one over the sessions with tea.
struct ShelfWall: Hashable, Sendable {
    struct Year: Hashable, Identifiable, Sendable {
        var year: Int
        /// Oldest finish first; undated books at the end.
        var spines: [ShelfSpine]

        var id: Int { year }
        var pages: Int { spines.reduce(0) { $0 + $1.book.pages * $1.finishes } }
        var finishes: Int { spines.reduce(0) { $0 + $1.finishes } }
    }

    /// Newest first.
    var years: [Year]

    var isEmpty: Bool { years.isEmpty }
    var spineCount: Int { years.reduce(0) { $0 + $1.spines.count } }

    static let minimumWidth = 14.0
    static let maximumWidth = 42.0

    /// About a point for every 16 pages over a 10-point binding: 150 pages is 19 points, 300 is 29, 512 and more 42.
    static func spineWidth(pages: Int) -> Double {
        min(maximumWidth, max(minimumWidth, 10 + Double(max(0, pages)) / 16))
    }

    /// A height from the book's id, so the wall is uneven the way real shelves are, and the same on every launch.
    static func spineHeight(bookID: String) -> Double {
        0.8 + 0.2 * Double(SeededGenerator.hash("spine|" + bookID) % 1_001) / 1_000
    }

    static func build(data: LeafData, calendar: Calendar) -> ShelfWall {
        var teaSessions: [String: [ReadingSession]] = [:]
        for session in data.sessions {
            guard let teaID = session.teaID, !teaID.isEmpty, session.seconds > 0 else { continue }
            teaSessions[session.bookID, default: []].append(session)
        }

        var byYear: [Int: [ShelfSpine]] = [:]
        for item in data.items {
            for spine in spines(for: item, teaSessions: teaSessions[item.id] ?? [], calendar: calendar) {
                byYear[spine.year, default: []].append(spine)
            }
        }
        let years = byYear.keys.sorted(by: >).map { year in
            Year(year: year, spines: (byYear[year] ?? []).sorted(by: comesBefore))
        }
        return ShelfWall(years: years)
    }

    /// A book's spines, one for each year it was finished in.
    static func spines(for item: LibraryItem, teaSessions: [ReadingSession], calendar: Calendar) -> [ShelfSpine] {
        let width = spineWidth(pages: item.book.pages)
        let height = spineHeight(bookID: item.id)
        let reads = item.readThroughs
        if reads.isEmpty {
            // Marked finished without a date: it stands in the year it was added, with all its tea.
            guard item.shelf == .finished, item.finishedAt == nil else { return [] }
            return [ShelfSpine(
                book: item.book, year: calendar.component(.year, from: item.addedAt), finishedAt: nil,
                rating: validRating(item.rating), finishes: 1, teaID: favouriteTea(teaSessions), width: width, height: height
            )]
        }

        // Sessions after one finish and up to the next belong to the next read-through.
        var spinesByYear: [Int: ShelfSpine] = [:]
        var teaByYear: [Int: [ReadingSession]] = [:]
        var previous: Date?
        for read in reads {
            let year = calendar.component(.year, from: read.finishedAt)
            let during = teaSessions.filter { session in
                session.startedAt <= read.finishedAt && (previous.map { session.startedAt > $0 } ?? true)
            }
            teaByYear[year, default: []].append(contentsOf: during)
            previous = read.finishedAt
            if var spine = spinesByYear[year] {
                spine.finishes += 1
                // Reads come oldest first, so this one is the year's latest.
                spine.finishedAt = read.finishedAt
                spine.rating = validRating(read.rating) ?? spine.rating
                spinesByYear[year] = spine
            } else {
                spinesByYear[year] = ShelfSpine(
                    book: item.book, year: year, finishedAt: read.finishedAt, rating: validRating(read.rating),
                    finishes: 1, teaID: nil, width: width, height: height
                )
            }
        }
        return spinesByYear.keys.sorted().compactMap { year in
            guard var spine = spinesByYear[year] else { return nil }
            spine.teaID = favouriteTea(teaByYear[year] ?? [])
            return spine
        }
    }

    /// Spines in rows that fit `width`, left to right and in order, with `spacing` between neighbours. A spine wider
    /// than the row stands alone.
    static func rows(_ spines: [ShelfSpine], width: Double, spacing: Double) -> [[ShelfSpine]] {
        guard width > 0 else { return spines.isEmpty ? [] : [spines] }
        var rows: [[ShelfSpine]] = []
        var row: [ShelfSpine] = []
        var used = 0.0
        for spine in spines {
            let needed = row.isEmpty ? spine.width : used + spacing + spine.width
            if !row.isEmpty && needed > width {
                rows.append(row)
                row = [spine]
                used = spine.width
            } else {
                row.append(spine)
                used = needed
            }
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    private static func validRating(_ rating: Int?) -> Int? {
        guard let rating, (1...5).contains(rating) else { return nil }
        return rating
    }

    /// The tea with the most minutes; on a tie, the one with the smaller id.
    private static func favouriteTea(_ sessions: [ReadingSession]) -> String? {
        var minutes: [String: Double] = [:]
        for session in sessions {
            guard let teaID = session.teaID else { continue }
            minutes[teaID, default: 0] += session.seconds / 60
        }
        var best: (id: String, minutes: Double)?
        for (id, total) in minutes {
            guard let current = best else {
                best = (id, total)
                continue
            }
            if total > current.minutes + 1e-9 || (abs(total - current.minutes) <= 1e-9 && id < current.id) {
                best = (id, total)
            }
        }
        return best?.id
    }

    /// Oldest finish first, undated last, then by title and id.
    private static func comesBefore(_ a: ShelfSpine, _ b: ShelfSpine) -> Bool {
        switch (a.finishedAt, b.finishedAt) {
        case let (x?, y?) where x != y: return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        if a.book.title != b.book.title { return a.book.title < b.book.title }
        return a.book.id < b.book.id
    }
}
