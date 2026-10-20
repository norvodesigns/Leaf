import Foundation

// MARK: - The deeper numbers

/// The stats pages behind Insights: pace by genre and by time of day, streak history, best weeks, a year by year
/// comparison, how many started books were set aside, and authors and decades. Everything but the year comparison
/// looks at one date range.
struct InsightsDepth: Hashable, Sendable {
    /// Pages an hour for a group of sittings.
    struct Pace: Hashable, Identifiable, Sendable {
        var key: String
        var name: String
        var pagesPerHour: Double
        var minutes: Double
        var sittings: Int

        var id: String { key }
    }

    struct Streak: Hashable, Identifiable, Sendable {
        var first: Date
        var last: Date
        var days: Int
        /// Whether it is still going today.
        var isCurrent: Bool

        var id: Date { first }
    }

    struct Week: Hashable, Identifiable, Sendable {
        var start: Date
        var minutes: Double
        var pages: Int
        var sittings: Int
        var daysRead: Int

        var id: Date { start }
    }

    struct YearRow: Hashable, Identifiable, Sendable {
        var year: Int
        var booksFinished: Int
        var pages: Int
        var minutes: Double
        var daysRead: Int
        var averageRating: Double?
        /// Pages an hour over the year's timed sittings, when there are enough to say.
        var pagesPerHour: Double?

        var id: Int { year }
    }

    /// Books begun in the range and where they stand now.
    struct SetAside: Hashable, Sendable {
        var started: Int
        var finished: Int
        var setAside: Int
        var stillReading: Int
        /// Set aside out of those that came to an end either way (finished or set aside), 0 to 1; nil before any did.
        var rate: Double?
        /// Titles set aside, most recent first.
        var titles: [String]
    }

    struct Group: Hashable, Identifiable, Sendable {
        var key: String
        var name: String
        var books: Int
        var pages: Int

        var id: String { key }
    }

    var range: DateInterval
    var minutes: Double
    var pages: Int
    var sittings: Int
    var booksFinished: Int
    var byGenre: [Pace]
    var byTimeOfDay: [Pace]
    /// Longest first.
    var streaks: [Streak]
    /// Most minutes first.
    var bestWeeks: [Week]
    /// Newest year first, every year with any reading.
    var years: [YearRow]
    var setAside: SetAside
    /// Most books first.
    var authors: [Group]
    /// Oldest decade first.
    var decades: [Group]

    var isEmpty: Bool { sittings == 0 && booksFinished == 0 }

    /// Fewer timed minutes than this, and a pace isn't shown.
    static let minimumPaceMinutes = 30.0
}

extension InsightsEngine {
    /// The deeper numbers for `range` (whole days, inclusive). The year comparison always covers all years.
    func depth(in range: DateInterval, limit: Int = 5) -> InsightsDepth {
        let first = calendar.startOfDay(for: range.start)
        let last = calendar.startOfDay(for: min(range.end, now))
        let inRange = sittings(from: first, through: last)
        let finishes = finishedItems().filter { item in
            guard let at = item.finishedAt else { return false }
            let day = calendar.startOfDay(for: at)
            return day >= first && day <= last
        }
        return InsightsDepth(
            range: range,
            minutes: inRange.reduce(0) { $0 + $1.minutes },
            pages: inRange.reduce(0) { $0 + $1.pages },
            sittings: inRange.count,
            booksFinished: finishes.count,
            byGenre: paceByGenre(inRange),
            byTimeOfDay: paceByTimeOfDay(inRange),
            streaks: streakHistory(from: first, through: last, limit: limit),
            bestWeeks: bestWeeks(inRange, limit: limit),
            years: yearRows(),
            setAside: setAsideRate(from: first, through: last),
            authors: Array(groupedByAuthor(finishes).prefix(8)),
            decades: groupedByDecade(finishes)
        )
    }

    // MARK: Pace

    private func pace(_ group: [Sitting]) -> (pagesPerHour: Double, minutes: Double)? {
        let timed = group.filter { $0.isTimed && $0.countsAsReading && $0.pages > 0 }
        let minutes = timed.reduce(0) { $0 + $1.minutes }
        guard minutes >= InsightsDepth.minimumPaceMinutes else { return nil }
        let pages = timed.reduce(0) { $0 + $1.pages }
        return (Double(pages) / (minutes / 60), minutes)
    }

    /// A book with several genres counts in each of them.
    func paceByGenre(_ group: [Sitting]) -> [InsightsDepth.Pace] {
        var byTag: [String: [Sitting]] = [:]
        for sitting in group {
            guard let item = itemsByID[sitting.bookID] else { continue }
            var seen = Set<String>()
            let tags = item.book.genres.filter { !$0.isEmpty && seen.insert($0).inserted }
            for tag in tags.isEmpty ? ["other"] : tags { byTag[tag, default: []].append(sitting) }
        }
        return byTag.compactMap { tag, sittings -> InsightsDepth.Pace? in
            guard let found = pace(sittings) else { return nil }
            return InsightsDepth.Pace(key: tag, name: Genre.name(tag), pagesPerHour: found.pagesPerHour, minutes: found.minutes, sittings: sittings.count)
        }
        .sorted { (a: InsightsDepth.Pace, b: InsightsDepth.Pace) -> Bool in
            if abs(a.pagesPerHour - b.pagesPerHour) > 1e-9 { return a.pagesPerHour > b.pagesPerHour }
            return a.key < b.key
        }
    }

    /// In the order of the day, from the small hours to late.
    func paceByTimeOfDay(_ group: [Sitting]) -> [InsightsDepth.Pace] {
        Daypart.allCases.compactMap { part -> InsightsDepth.Pace? in
            let sittings = group.filter { $0.daypart == part }
            guard let found = pace(sittings) else { return nil }
            return InsightsDepth.Pace(
                key: part.rawValue, name: part.depthTitle, pagesPerHour: found.pagesPerHour,
                minutes: found.minutes, sittings: sittings.count
            )
        }
    }

    // MARK: Streaks and weeks

    /// Runs of reading days within the range (rest days bridge them, as everywhere), longest first, then latest.
    func streakHistory(from first: Date, through last: Date, limit: Int = 5) -> [InsightsDepth.Streak] {
        var runs: [InsightsDepth.Streak] = []
        var start: Date?
        var previous: Date?
        var count = 0
        for day in readDays where day >= first && day <= last {
            if let previous, isRestOnly(between: previous, and: day) {
                count += 1
            } else {
                if let start, let previous, count >= 2 {
                    runs.append(InsightsDepth.Streak(first: start, last: previous, days: count, isCurrent: false))
                }
                start = day
                count = 1
            }
            previous = day
        }
        if let start, let previous, count >= 2 {
            let current = currentStreak() == count && (previous == today || isRestOnly(between: previous, and: today))
            runs.append(InsightsDepth.Streak(first: start, last: previous, days: count, isCurrent: current))
        }
        let sorted = runs.sorted { (a: InsightsDepth.Streak, b: InsightsDepth.Streak) -> Bool in
            if a.days != b.days { return a.days > b.days }
            return a.first > b.first
        }
        return Array(sorted.prefix(limit))
    }

    /// Calendar weeks (the calendar's own first weekday) with the most minutes.
    func bestWeeks(_ group: [Sitting], limit: Int = 5) -> [InsightsDepth.Week] {
        var weeks: [Date: (minutes: Double, pages: Int, sittings: Int, days: Set<Date>)] = [:]
        for sitting in group {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: sitting.day)?.start else { continue }
            var week = weeks[start] ?? (0, 0, 0, [])
            week.minutes += sitting.minutes
            week.pages += sitting.pages
            week.sittings += 1
            if sitting.countsAsReading { week.days.insert(sitting.day) }
            weeks[start] = week
        }
        let rows = weeks.map { start, week in
            InsightsDepth.Week(start: start, minutes: week.minutes, pages: week.pages, sittings: week.sittings, daysRead: week.days.count)
        }
        let sorted = rows.filter { $0.minutes > 0 }.sorted { (a: InsightsDepth.Week, b: InsightsDepth.Week) -> Bool in
            if abs(a.minutes - b.minutes) > 1e-9 { return a.minutes > b.minutes }
            return a.start > b.start
        }
        return Array(sorted.prefix(limit))
    }

    // MARK: Years

    /// Every year with a sitting or a finish, newest first.
    func yearRows() -> [InsightsDepth.YearRow] {
        var years = Set(sittings.map { year(of: $0.day) })
        let finished = finishedItems()
        for item in finished {
            if let at = item.finishedAt { years.insert(year(of: at)) }
        }
        return years.sorted(by: >).map { year in
            let inYear = sittings.filter { self.year(of: $0.day) == year }
            let books = finished.filter { item in item.finishedAt.map { self.year(of: $0) == year } ?? false }
            let markedPages = books.filter { (sessionCountByBook[$0.id] ?? 0) == 0 }.reduce(0) { $0 + $1.book.pages }
            let ratings = books.compactMap(\.rating).filter { (1...5).contains($0) }
            let average: Double? = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
            return InsightsDepth.YearRow(
                year: year,
                booksFinished: books.count,
                pages: inYear.reduce(0) { $0 + $1.pages } + markedPages,
                minutes: inYear.reduce(0) { $0 + $1.minutes },
                daysRead: Set(inYear.filter(\.countsAsReading).map(\.day)).count,
                averageRating: average,
                pagesPerHour: pace(inYear)?.pagesPerHour
            )
        }
    }

    // MARK: Set aside

    /// Books begun in the range (their current read-through), and how many of those were set aside.
    func setAsideRate(from first: Date, through last: Date) -> InsightsDepth.SetAside {
        var started = 0
        var finished = 0
        var aside: [(title: String, at: Date)] = []
        var reading = 0
        for item in data.items {
            // Earlier read-throughs that began in the range all ended in a finish.
            for read in item.reads {
                guard let begun = read.startedAt.map({ calendar.startOfDay(for: $0) }), begun >= first, begun <= last else { continue }
                started += 1
                finished += 1
            }
            guard let begun = item.startedAt.map({ calendar.startOfDay(for: $0) }), begun >= first, begun <= last else { continue }
            switch item.shelf {
            case .finished:
                started += 1
                finished += 1
            case .paused:
                started += 1
                aside.append((item.book.title, item.pausedAt ?? item.updatedAt))
            case .reading:
                started += 1
                reading += 1
            case .toRead:
                continue
            }
        }
        let ended = finished + aside.count
        return InsightsDepth.SetAside(
            started: started,
            finished: finished,
            setAside: aside.count,
            stillReading: reading,
            rate: ended > 0 ? Double(aside.count) / Double(ended) : nil,
            titles: aside.sorted { $0.at > $1.at }.map(\.title)
        )
    }

    // MARK: Authors and decades

    /// Finishes by author (spellings of one author together), most books first, then most pages.
    func groupedByAuthor(_ finishes: [LibraryItem]) -> [InsightsDepth.Group] {
        var groups: [String: (books: Int, pages: Int, spellings: [String: Int])] = [:]
        for item in finishes {
            let key = TasteProfile.normalizeAuthor(item.book.author)
            guard !key.isEmpty else { continue }
            var group = groups[key] ?? (0, 0, [:])
            group.books += 1
            group.pages += item.book.pages
            group.spellings[item.book.author, default: 0] += 1
            groups[key] = group
        }
        let rows = groups.map { key, group -> InsightsDepth.Group in
            let name = group.spellings.sorted { (a: (key: String, value: Int), b: (key: String, value: Int)) -> Bool in
                if a.value != b.value { return a.value > b.value }
                return a.key < b.key
            }.first?.key ?? key
            return InsightsDepth.Group(key: key, name: name, books: group.books, pages: group.pages)
        }
        return rows.sorted { (a: InsightsDepth.Group, b: InsightsDepth.Group) -> Bool in
            if a.books != b.books { return a.books > b.books }
            if a.pages != b.pages { return a.pages > b.pages }
            return a.key < b.key
        }
    }

    /// Finishes by the decade the book came out ("1930s"), oldest first; books without a year are left out.
    func groupedByDecade(_ finishes: [LibraryItem]) -> [InsightsDepth.Group] {
        var groups: [Int: (books: Int, pages: Int)] = [:]
        for item in finishes {
            guard let year = item.book.year, year > 0 else { continue }
            let decade = year / 10 * 10
            var group = groups[decade] ?? (0, 0)
            group.books += 1
            group.pages += item.book.pages
            groups[decade] = group
        }
        return groups.keys.sorted().map { decade in
            InsightsDepth.Group(key: String(decade), name: "\(decade)s", books: groups[decade]?.books ?? 0, pages: groups[decade]?.pages ?? 0)
        }
    }
}

extension Daypart {
    /// "Small hours", "Tea time": a row label for the stats pages.
    var depthTitle: String {
        switch self {
        case .smallHours: return "Small hours"
        case .dawn: return "Dawn"
        case .morning: return "Morning"
        case .lunch: return "Lunchtime"
        case .afternoon: return "Afternoon"
        case .teaTime: return "Tea time"
        case .dusk: return "Dusk"
        case .evening: return "Evening"
        case .late: return "Late"
        }
    }
}

// MARK: - Ranges

/// The date ranges the stats pages offer.
enum InsightsRange: String, CaseIterable, Hashable, Sendable {
    case thisYear, lastYear, last12Months, allTime

    var title: String {
        switch self {
        case .thisYear: return "This year"
        case .lastYear: return "Last year"
        case .last12Months: return "Last 12 months"
        case .allTime: return "All time"
        }
    }

    /// The range as whole days, ending today (or on the last day of last year). All time begins with the first sitting
    /// or finish, or today when there is none.
    func interval(data: LeafData, now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: now)
        func startOf(_ y: Int) -> Date { calendar.date(from: DateComponents(year: y, month: 1, day: 1)) ?? today }
        switch self {
        case .thisYear:
            return DateInterval(start: startOf(year), end: max(startOf(year), today))
        case .lastYear:
            let end = calendar.date(byAdding: .day, value: -1, to: startOf(year)) ?? today
            return DateInterval(start: startOf(year - 1), end: end)
        case .last12Months:
            let start = calendar.date(byAdding: .year, value: -1, to: today).flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? today
            return DateInterval(start: start, end: today)
        case .allTime:
            var earliest = today
            for session in data.sessions { earliest = min(earliest, calendar.startOfDay(for: session.startedAt)) }
            for item in data.items {
                for read in item.readThroughs { earliest = min(earliest, calendar.startOfDay(for: read.finishedAt)) }
            }
            return DateInterval(start: earliest, end: today)
        }
    }
}
