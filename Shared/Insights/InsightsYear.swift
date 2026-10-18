import Foundation

// MARK: - Year in books

/// A cozy wrapped for one calendar year: the totals, the favourites, and a ring for every month.
struct YearInBooks: Hashable, Sendable {
    /// A finished book, with how quickly it went.
    struct BookHighlight: Hashable, Identifiable, Sendable {
        var bookID: String
        var title: String
        var author: String
        var pages: Int
        var finishedAt: Date
        var rating: Int?
        /// Calendar days from the first sitting (or the day it was started) to the finish, counting both ends. Nil when
        /// the start is unknown, as for a book marked finished without ever being read here.
        var days: Int?
        var pagesPerDay: Double?

        var id: String { bookID }
    }

    struct GenreHighlight: Hashable, Sendable {
        var tag: String
        var name: String
        var books: Int
        /// Share of the year's finished books (a book with several genres splits its weight).
        var share: Double
    }

    struct AuthorHighlight: Hashable, Sendable {
        var name: String
        var books: Int
        var pages: Int
    }

    /// One month of the tea-ring collage.
    struct MonthRing: Hashable, Identifiable, Sendable {
        /// 1 to 12.
        var month: Int
        var minutes: Double
        var cups: Int
        var booksFinished: Int
        /// 0 for a month with no reading, otherwise 0.1 to 1 with the busiest month at 1. Grows with the square root of
        /// the minutes, so a ring's area follows the time spent.
        var ring: Double

        var id: Int { month }
    }

    var year: Int
    var booksFinished: Int
    /// Pages read in sessions, plus the pages of books marked finished that were never read with a session.
    var pages: Int
    var minutes: Double
    /// Whole cups of reading (the reader's own cup length), counted over the year's minutes.
    var cups: Int
    var pots: Int
    var cupMinutes: Int
    var sessionCount: Int
    /// Days with at least a minute of reading.
    var daysRead: Int
    var longestStreak: Int
    /// The hour (0 to 23) with the most timed reading, or nil without timed sessions.
    var favouriteHour: Int?
    var topGenre: GenreHighlight?
    var topAuthor: AuthorHighlight?
    var longestBook: BookHighlight?
    var shortestBook: BookHighlight?
    /// The book that went fastest in pages per day.
    var fastestBook: BookHighlight?
    var firstFinished: BookHighlight?
    var lastFinished: BookHighlight?
    /// Mean of the 1 to 5 star ratings given to the year's finished books, or nil when none were rated.
    var averageRating: Double?
    var ratedBooks: Int
    /// 1 to 12, or nil when nothing was read.
    var busiestMonth: Int?
    /// Twelve months, January first.
    var months: [MonthRing]
    /// Every book finished in the year, oldest finish first, for the collage of finished-book rings.
    var finishedBooks: [BookHighlight]
    var quotesSaved: Int
    var notesSaved: Int

    /// Nothing to show: no books, no reading, no journal.
    var isEmpty: Bool { booksFinished == 0 && minutes == 0 && pages == 0 && quotesSaved == 0 && notesSaved == 0 }
}

extension InsightsEngine {
    /// The reader's `year` in books. A book belongs to the year it was finished in; time and pages belong to the year
    /// they were read in. Sessions of books since removed still count toward time and pages.
    func yearInBooks(year: Int) -> YearInBooks {
        let first = startOfYear(year)
        let next = startOfYear(year + 1)
        let inYear: [Sitting]
        if let first, let next {
            inYear = sittings.filter { $0.day >= first && $0.day < next }
        } else {
            inYear = []
        }
        let cupMinutes = max(1, data.preferences.cupMinutes)

        let finished = finishedItems(year: year)
        let highlights = bookHighlights(for: finished)

        // Pages come from sessions; books marked finished with no session at all add their whole length.
        let markedFinishedPages = finished
            .filter { (sessionCountByBook[$0.id] ?? 0) == 0 }
            .reduce(0) { $0 + $1.book.pages }
        let pages = inYear.reduce(0) { $0 + $1.pages } + markedFinishedPages
        let minutes = inYear.reduce(0) { $0 + $1.minutes }
        let cups = Cups.wholeCups(minutes: minutes, cupMinutes: cupMinutes)

        // Months.
        var monthMinutes = [Double](repeating: 0, count: 12)
        var monthBooks = [Int](repeating: 0, count: 12)
        for sitting in inYear {
            let month = calendar.component(.month, from: sitting.day)
            if (1...12).contains(month) { monthMinutes[month - 1] += sitting.minutes }
        }
        for item in finished {
            guard let when = item.finishedAt else { continue }
            let month = calendar.component(.month, from: when)
            if (1...12).contains(month) { monthBooks[month - 1] += 1 }
        }
        let busiest = monthMinutes.max() ?? 0
        let months = (0..<12).map { index in
            YearInBooks.MonthRing(
                month: index + 1,
                minutes: monthMinutes[index],
                cups: Cups.wholeCups(minutes: monthMinutes[index], cupMinutes: cupMinutes),
                booksFinished: monthBooks[index],
                ring: monthMinutes[index] > 0 && busiest > 0 ? 0.1 + 0.9 * (monthMinutes[index] / busiest).squareRoot() : 0
            )
        }
        let busiestMonth = busiest > 0 ? monthMinutes.firstIndex(of: busiest).map { $0 + 1 } : nil

        // Favourite hour.
        var hourMinutes = [Double](repeating: 0, count: 24)
        var timedCount = 0
        for sitting in inYear where sitting.isTimed && sitting.countsAsReading {
            hourMinutes[sitting.hour] += sitting.minutes
            timedCount += 1
        }
        let peakHourMinutes = hourMinutes.max() ?? 0
        let favouriteHour = timedCount > 0 && peakHourMinutes > 0 ? hourMinutes.firstIndex(of: peakHourMinutes) : nil

        // Genre and author.
        let topGenre = genreMix(year: year).first.map {
            YearInBooks.GenreHighlight(tag: $0.tag, name: $0.name, books: $0.books, share: $0.share)
        }

        // Ratings.
        let ratings = finished.compactMap(\.rating).filter { (1...5).contains($0) }

        // Journal.
        var quotes = 0
        var notes = 0
        for entry in data.journal where self.year(of: entry.createdAt) == year {
            if entry.kind == .quote { quotes += 1 } else { notes += 1 }
        }

        let longest = highlights.max { lhs, rhs in
            lhs.pages != rhs.pages ? lhs.pages < rhs.pages : lhs.bookID > rhs.bookID
        }
        let shortest = highlights.min { lhs, rhs in
            lhs.pages != rhs.pages ? lhs.pages < rhs.pages : lhs.bookID < rhs.bookID
        }
        let fastest = highlights.filter { $0.pagesPerDay != nil }.max { lhs, rhs in
            let l = lhs.pagesPerDay ?? 0
            let r = rhs.pagesPerDay ?? 0
            if abs(l - r) > 1e-9 { return l < r }
            return lhs.pages != rhs.pages ? lhs.pages < rhs.pages : lhs.bookID > rhs.bookID
        }

        return YearInBooks(
            year: year,
            booksFinished: finished.count,
            pages: pages,
            minutes: minutes,
            cups: cups,
            pots: Cups.pots(cups: cups),
            cupMinutes: cupMinutes,
            sessionCount: inYear.count,
            daysRead: Set(inYear.filter(\.countsAsReading).map(\.day)).count,
            longestStreak: longestStreak(year: year),
            favouriteHour: favouriteHour,
            topGenre: topGenre,
            topAuthor: topAuthor(among: finished),
            longestBook: longest,
            shortestBook: shortest,
            fastestBook: fastest,
            firstFinished: highlights.first,
            lastFinished: highlights.last,
            averageRating: ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count),
            ratedBooks: ratings.count,
            busiestMonth: busiestMonth,
            months: months,
            finishedBooks: highlights,
            quotesSaved: quotes,
            notesSaved: notes
        )
    }

    /// Highlights for finished items that carry a finish date, oldest finish first.
    private func bookHighlights(for items: [LibraryItem]) -> [YearInBooks.BookHighlight] {
        var firstSitting: [String: Date] = [:]
        for sitting in sittings where firstSitting[sitting.bookID] == nil { firstSitting[sitting.bookID] = sitting.day }
        return items.compactMap { item in
            guard let finishedAt = item.finishedAt else { return nil }
            let startDay = firstSitting[item.id] ?? item.startedAt.map { calendar.startOfDay(for: $0) }
            var days: Int?
            var rate: Double?
            if let startDay {
                let span = max(1, daysBetween(startDay, finishedAt) + 1)
                days = span
                rate = Double(item.book.pages) / Double(span)
            }
            return YearInBooks.BookHighlight(
                bookID: item.id, title: item.book.title, author: item.book.author, pages: item.book.pages,
                finishedAt: finishedAt, rating: item.rating, days: days, pagesPerDay: rate
            )
        }
    }

    /// The author with the most finished books (then the most pages, then the name). Spellings of the same author
    /// ("J. R. R. Tolkien", "J.R.R. Tolkien") are treated as one.
    private func topAuthor(among items: [LibraryItem]) -> YearInBooks.AuthorHighlight? {
        var groups: [String: (books: Int, pages: Int, spellings: [String: Int])] = [:]
        for item in items {
            let key = TasteProfile.normalizeAuthor(item.book.author)
            guard !key.isEmpty else { continue }
            var group = groups[key] ?? (books: 0, pages: 0, spellings: [:])
            group.books += 1
            group.pages += item.book.pages
            group.spellings[item.book.author, default: 0] += 1
            groups[key] = group
        }
        let best = groups.sorted { lhs, rhs in
            if lhs.value.books != rhs.value.books { return lhs.value.books > rhs.value.books }
            if lhs.value.pages != rhs.value.pages { return lhs.value.pages > rhs.value.pages }
            return lhs.key < rhs.key
        }.first
        guard let best else { return nil }
        let name = best.value.spellings.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }.first?.key ?? ""
        return YearInBooks.AuthorHighlight(name: name, books: best.value.books, pages: best.value.pages)
    }
}

// MARK: - Weekly letter

/// The plain numbers behind the Sunday-evening letter. The wording is written elsewhere.
struct WeeklyLetterData: Hashable, Sendable {
    /// The totals of one seven-day stretch.
    struct Week: Hashable, Sendable {
        /// First day (start of day).
        var start: Date
        /// Last day (start of day).
        var end: Date
        var minutes: Double
        var cups: Int
        var pages: Int
        var sessions: Int
        /// Days with at least a minute of reading.
        var daysRead: Int
        var booksFinished: Int
    }

    struct BestDay: Hashable, Sendable {
        var date: Date
        var minutes: Double
    }

    struct FinishedBook: Hashable, Identifiable, Sendable {
        var bookID: String
        var title: String
        var author: String
        var pages: Int

        var id: String { bookID }
    }

    struct BookTime: Hashable, Sendable {
        var bookID: String
        var title: String
        var author: String
        var minutes: Double
    }

    enum Trend: String, Sendable {
        /// No reading this week or last.
        case quiet
        /// Reading this week, none the week before.
        case fresh
        case up, steady, down
    }

    var week: Week
    var previous: Week
    /// The day with the most reading this week (earliest on a tie), or nil if the week was quiet.
    var bestDay: BestDay?
    /// Reading-day streak as of the last day of the week.
    var streak: Int
    var finishedBooks: [FinishedBook]
    /// The book that took most of the week, among books still in the library.
    var topBook: BookTime?
    var quotesSaved: Int
    var minutesChange: Double
    /// Change in minutes as a fraction of last week's (0.25 is a quarter more), or nil when last week had none.
    var minutesChangeFraction: Double?
    var pagesChange: Int
    var booksChange: Int
    var trend: Trend

    /// A change smaller than this, as a share of last week, counts as steady.
    static let steadyBand = 0.1
}

extension InsightsEngine {
    /// The seven days that end on the day of `weekEnding`, set beside the seven days before them.
    func weeklyLetter(weekEnding: Date) -> WeeklyLetterData {
        let end = calendar.startOfDay(for: weekEnding)
        let start = addDays(-6, to: end)
        let previousEnd = addDays(-1, to: start)
        let previousStart = addDays(-6, to: previousEnd)

        let this = weekTotals(from: start, through: end)
        let before = weekTotals(from: previousStart, through: previousEnd)
        let inWeek = sittings(from: start, through: end)

        var perDay: [Date: Double] = [:]
        var perBook: [String: Double] = [:]
        for sitting in inWeek {
            perDay[sitting.day, default: 0] += sitting.minutes
            perBook[sitting.bookID, default: 0] += sitting.minutes
        }
        let bestDay = perDay
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                abs(lhs.value - rhs.value) > 1e-9 ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .first
            .map { WeeklyLetterData.BestDay(date: $0.key, minutes: $0.value) }

        let topBook = perBook
            .compactMap { id, minutes -> WeeklyLetterData.BookTime? in
                guard minutes > 0, let item = itemsByID[id] else { return nil }
                return WeeklyLetterData.BookTime(bookID: id, title: item.book.title, author: item.book.author, minutes: minutes)
            }
            .sorted { lhs, rhs in
                abs(lhs.minutes - rhs.minutes) > 1e-9 ? lhs.minutes > rhs.minutes : lhs.bookID < rhs.bookID
            }
            .first

        let finished = finishedItems()
            .filter { item in
                guard let when = item.finishedAt else { return false }
                let day = calendar.startOfDay(for: when)
                return day >= start && day <= end
            }
            .map { WeeklyLetterData.FinishedBook(bookID: $0.id, title: $0.book.title, author: $0.book.author, pages: $0.book.pages) }

        let change = this.minutes - before.minutes
        let fraction: Double? = before.minutes > 0 ? change / before.minutes : nil
        let trend: WeeklyLetterData.Trend
        if before.minutes <= 0 {
            trend = this.minutes > 0 ? .fresh : .quiet
        } else if let fraction, fraction >= WeeklyLetterData.steadyBand {
            trend = .up
        } else if let fraction, fraction <= -WeeklyLetterData.steadyBand {
            trend = .down
        } else {
            trend = .steady
        }

        return WeeklyLetterData(
            week: this,
            previous: before,
            bestDay: bestDay,
            streak: currentStreak(asOf: end),
            finishedBooks: finished,
            topBook: topBook,
            quotesSaved: data.journal.filter { entry in
                let day = calendar.startOfDay(for: entry.createdAt)
                return entry.kind == .quote && day >= start && day <= end
            }.count,
            minutesChange: change,
            minutesChangeFraction: fraction,
            pagesChange: this.pages - before.pages,
            booksChange: this.booksFinished - before.booksFinished,
            trend: trend
        )
    }

    private func weekTotals(from first: Date, through last: Date) -> WeeklyLetterData.Week {
        let inRange = sittings(from: first, through: last)
        let minutes = inRange.reduce(0) { $0 + $1.minutes }
        let finished = finishedItems().filter { item in
            guard let when = item.finishedAt else { return false }
            let day = calendar.startOfDay(for: when)
            return day >= first && day <= last
        }
        // Books marked finished without any session add their length, as in the year review.
        let markedFinishedPages = finished
            .filter { (sessionCountByBook[$0.id] ?? 0) == 0 }
            .reduce(0) { $0 + $1.book.pages }
        return WeeklyLetterData.Week(
            start: first,
            end: last,
            minutes: minutes,
            cups: Cups.wholeCups(minutes: minutes, cupMinutes: max(1, data.preferences.cupMinutes)),
            pages: inRange.reduce(0) { $0 + $1.pages } + markedFinishedPages,
            sessions: inRange.count,
            daysRead: Set(inRange.filter(\.countsAsReading).map(\.day)).count,
            booksFinished: finished.count
        )
    }
}
