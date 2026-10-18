import Foundation

/// One collectible in the reader’s stamp book.
struct StampEntry: Identifiable, Hashable, Sendable {
    enum Source: String, Sendable {
        /// A finished book, with a big tea ring and its date.
        case book
        /// A month of steady reading.
        case month
        /// Earned in a challenge.
        case challenge
    }

    /// Stable across re-evaluation: `book.<book id>`, `month.2026-10`, or `challenge.<design id>@<year>`.
    var id: String
    var source: Source
    var name: String
    /// A short second line: the author, the days read, or the challenge it came from.
    var detail: String
    /// How many tea rings the stamp is pressed with.
    var rings: Int
    var paletteToken: String
    var earnedAt: Date
    var bookID: String?
    var challengeID: String?
    var year: Int?
}

/// The stamp book: everything the reader has earned, worked out from their history alone. Nothing is stored, so the
/// same history always gives the same book with the same ids and dates.
///
/// Three kinds of stamp:
/// - **Finished book.** One per finished book: three tea rings, four for a book of 300 pages or more, five for 600
///   or more, dated the day it was finished.
/// - **Month.** For a month in which the reader read on at least seven days. It is pressed on the first day of the
///   next month, so a month’s stamp never changes while the month is still open. One to four rings by days read.
/// - **Challenge.** Each stamp an enrolled challenge has handed out so far.
enum StampLedger {
    /// A day counts as a reading day with at least this many minutes.
    static let readDayMinutes = 5.0
    /// Reading days a month needs to earn its stamp.
    static let daysForMonthStamp = 7

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// Every stamp, oldest first (ties by id).
    static func entries(data: LeafData, now: Date, calendar: Calendar) -> [StampEntry] {
        var all = bookEntries(data: data)
        all += monthEntries(data: data, now: now, calendar: calendar)
        all += challengeEntries(data: data, now: now, calendar: calendar)

        // Ids are unique by construction; this keeps the oldest if a quirk of the data ever made two.
        var byID: [String: StampEntry] = [:]
        for entry in all where byID[entry.id].map({ entry.earnedAt < $0.earnedAt }) ?? true { byID[entry.id] = entry }
        return byID.values.sorted { $0.earnedAt < $1.earnedAt || ($0.earnedAt == $1.earnedAt && $0.id < $1.id) }
    }

    // MARK: Books

    /// Rings for a finished book: bigger books leave bigger rings.
    static func rings(forPages pages: Int) -> Int {
        pages >= 600 ? 5 : (pages >= 300 ? 4 : 3)
    }

    static func bookEntries(data: LeafData) -> [StampEntry] {
        var earliest: [String: LibraryItem] = [:]
        for item in data.items where item.shelf == .finished {
            guard let finished = item.finishedAt else { continue }
            if let existing = earliest[item.book.id], let seen = existing.finishedAt, seen <= finished { continue }
            earliest[item.book.id] = item
        }
        return earliest.values.compactMap { item -> StampEntry? in
            guard let finished = item.finishedAt else { return nil }
            let tokens = CozyPalette.all
            return StampEntry(
                id: "book.\(item.book.id)", source: .book, name: item.book.title, detail: item.book.author,
                rings: rings(forPages: item.book.pages), paletteToken: tokens[item.book.paletteSeed % tokens.count],
                earnedAt: finished, bookID: item.book.id, challengeID: nil, year: nil
            )
        }
    }

    // MARK: Months

    /// Rings for a month by days read: one for seven or more, two for fourteen, three for twenty-one, four for 28.
    static func rings(forDaysRead days: Int) -> Int {
        min(4, max(1, 1 + (days - daysForMonthStamp) / 7))
    }

    static func monthEntries(data: LeafData, now: Date, calendar: Calendar) -> [StampEntry] {
        // Minutes per day, then the days that count.
        var secondsByDay: [Date: Double] = [:]
        for session in data.sessions {
            secondsByDay[calendar.startOfDay(for: session.startedAt), default: 0] += ChallengeRules.creditedSeconds(session.seconds)
        }
        var daysByMonth: [Int: Int] = [:]
        for (day, seconds) in secondsByDay where seconds >= readDayMinutes * 60 {
            let parts = calendar.dateComponents([.year, .month], from: day)
            guard let year = parts.year, let month = parts.month else { continue }
            daysByMonth[year * 100 + month, default: 0] += 1
        }

        var entries: [StampEntry] = []
        for (key, days) in daysByMonth where days >= daysForMonthStamp {
            let year = key / 100
            let month = key % 100
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start),
                  end <= now, (1...12).contains(month) else { continue }
            entries.append(StampEntry(
                id: "month.\(year)-\(month < 10 ? "0" : "")\(month)", source: .month,
                name: "\(monthNames[month - 1]) \(year)", detail: "\(days) days of reading",
                rings: rings(forDaysRead: days), paletteToken: CozyPalette.token(for: Season.of(start, calendar: calendar)),
                earnedAt: end, bookID: nil, challengeID: nil, year: year
            ))
        }
        return entries
    }

    // MARK: Challenges

    static func challengeEntries(data: LeafData, now: Date, calendar: Calendar) -> [StampEntry] {
        var entries: [StampEntry] = []
        for progress in ChallengeEvaluator.allProgress(data: data, now: now, calendar: calendar) {
            let title = ChallengeCatalog.challenge(id: progress.challengeID)?.title ?? progress.challengeID
            for stamp in progress.stamps {
                entries.append(StampEntry(
                    id: "challenge.\(stamp.id)", source: .challenge, name: stamp.design.name, detail: "\(title) \(stamp.year)",
                    rings: stamp.design.rings, paletteToken: stamp.design.paletteToken, earnedAt: stamp.earnedAt,
                    bookID: nil, challengeID: progress.challengeID, year: stamp.year
                ))
            }
        }
        return entries
    }
}
