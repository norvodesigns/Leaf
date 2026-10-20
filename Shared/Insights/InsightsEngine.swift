import Foundation

/// The numbers behind the Plan page, the heatmap, Year in Books and the weekly letter.
///
/// Everything here is derived from `LeafData` alone (library, sessions, journal, preferences) plus the three inputs that
/// make a result repeatable: `now`, a `Calendar` and, where chance is involved (`JournalTools`), a seed. Nothing reads
/// the clock or the current calendar, so the same data always gives the same answer, in any time zone.
///
/// How the data is read:
/// - A **reading day** is a day with at least one session of a minute or more (the same rule `ReadingStats.streak`
///   uses). Rest days never break a streak.
/// - **Pace** (words per minute) comes from timed sessions of books still in the library, with the same filter the app
///   uses to learn the reader's speed. Typed-in sessions and books marked finished without sessions add to books and
///   pages but never to pace.
/// - **Time totals** include every session, even those of books the reader has since removed.
/// - **Paused** books count as in progress, not as finished or abandoned.
///
/// The engine does its calendar work once, in `init`, so each question afterwards is a pass over plain numbers.
struct InsightsEngine: Sendable {
    let data: LeafData
    let now: Date
    let calendar: Calendar

    /// Start of the day that contains `now`.
    let today: Date
    /// Weekdays the reader reads on (1 = Sunday ... 7 = Saturday). Never empty.
    let schedule: Set<Int>
    /// Every session with its calendar facts worked out, oldest first.
    let sittings: [Sitting]
    /// Days with at least a minute of reading, oldest first and without repeats.
    let readDays: [Date]
    let minutesByDay: [Date: Double]
    let itemsByID: [String: LibraryItem]
    let sessionCountByBook: [String: Int]

    /// One session with the calendar facts everything below needs.
    struct Sitting: Sendable {
        var id: UUID
        var bookID: String
        var start: Date
        var day: Date
        var weekday: Int
        var hour: Int
        var daypart: Daypart
        var seconds: Double
        var pages: Int
        var isTimed: Bool
        /// Words read, when the book is still in the library and the session is long enough to learn from.
        var words: Double
        /// Words per minute for this sitting, or nil when it is too short, too small or implausible to trust.
        var wpm: Double?

        var minutes: Double { seconds / 60 }
        var countsAsReading: Bool { seconds >= 60 }
    }

    init(data: LeafData, now: Date, calendar: Calendar) {
        self.data = data
        self.now = now
        self.calendar = calendar
        today = calendar.startOfDay(for: now)

        let days = data.preferences.readingDays.filter { (1...7).contains($0) }
        schedule = days.isEmpty ? Set(1...7) : days

        var byID: [String: LibraryItem] = [:]
        for item in data.items where byID[item.id] == nil { byID[item.id] = item }
        itemsByID = byID

        var built: [Sitting] = []
        built.reserveCapacity(data.sessions.count)
        var counts: [String: Int] = [:]
        var minutes: [Date: Double] = [:]
        var reading = Set<Date>()
        for session in data.sessions {
            let parts = calendar.dateComponents([.hour, .weekday], from: session.startedAt)
            let day = calendar.startOfDay(for: session.startedAt)
            let seconds = max(0, session.seconds)
            var words = 0.0
            var wpm: Double?
            if session.kind == .timed, let item = byID[session.bookID],
               let observed = ReadingSpeed.observedWPM(pagesRead: session.pagesRead, wordsPerPage: item.book.wordsPerPage, seconds: seconds) {
                words = Double(session.pagesRead) * item.book.wordsPerPage
                wpm = observed
            }
            let sitting = Sitting(
                id: session.id,
                bookID: session.bookID,
                start: session.startedAt,
                day: day,
                weekday: parts.weekday ?? 1,
                hour: min(23, max(0, parts.hour ?? 0)),
                daypart: Daypart.of(session.startedAt, calendar: calendar),
                seconds: seconds,
                pages: session.pagesRead,
                isTimed: session.kind == .timed,
                words: words,
                wpm: wpm
            )
            built.append(sitting)
            counts[session.bookID, default: 0] += 1
            minutes[day, default: 0] += sitting.minutes
            if sitting.countsAsReading { reading.insert(day) }
        }
        built.sort { lhs, rhs in
            lhs.start != rhs.start ? lhs.start < rhs.start : lhs.id.uuidString < rhs.id.uuidString
        }
        sittings = built
        sessionCountByBook = counts
        minutesByDay = minutes
        readDays = reading.sorted()
    }

    // MARK: - Calendar helpers

    func addDays(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date) ?? date
    }

    /// Whole calendar days from `start` to `end` (both snapped to the start of their day).
    func daysBetween(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    func year(of date: Date) -> Int { calendar.component(.year, from: date) }

    /// The year that contains `now`.
    var currentYear: Int { year(of: now) }

    /// First day of `year`, or nil for a year the calendar cannot build.
    func startOfYear(_ year: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: 1, day: 1)).map { calendar.startOfDay(for: $0) }
    }

    /// Minutes read on the day that contains `date`.
    func minutes(on date: Date) -> Double { minutesByDay[calendar.startOfDay(for: date)] ?? 0 }

    /// Sittings that began on a day in `first...last` (days, inclusive).
    func sittings(from first: Date, through last: Date) -> [Sitting] {
        sittings.filter { $0.day >= first && $0.day <= last }
    }

    /// Finishes in `year` (all years when nil), oldest first: one finished copy of the book per read-through, with
    /// that read-through's dates and rating, so a book read twice appears twice.
    func finishedItems(year: Int? = nil) -> [LibraryItem] {
        var out: [LibraryItem] = []
        for item in data.items {
            for read in item.readThroughs {
                if let year, self.year(of: read.finishedAt) != year { continue }
                out.append(item.asOf(read))
            }
        }
        return out.sorted { lhs, rhs in
            let l = lhs.finishedAt ?? .distantPast
            let r = rhs.finishedAt ?? .distantPast
            return l != r ? l < r : lhs.id < rhs.id
        }
    }

    // MARK: - Streaks

    /// Whether no day between `earlier` and `later` (exclusive of both) is one the reader plans to read on, so the gap
    /// is only rest days. A gap of a week or more always contains a planned day.
    func isRestOnly(between earlier: Date, and later: Date) -> Bool {
        var day = earlier
        for _ in 0..<7 {
            day = addDays(1, to: day)
            if day >= later { return true }
            if schedule.contains(calendar.component(.weekday, from: day)) { return false }
        }
        return false
    }

    /// Reading days in a row counting back from `day` (default: today), with rest days bridging gaps. The day itself
    /// only counts once you have read, but not having read yet never breaks the streak. Matches `ReadingStats.streak`.
    func currentStreak(asOf day: Date? = nil) -> Int {
        let anchorDay = calendar.startOfDay(for: day ?? now)
        guard let lastIndex = lastReadIndex(onOrBefore: anchorDay) else { return 0 }
        if readDays[lastIndex] != anchorDay, !isRestOnly(between: readDays[lastIndex], and: anchorDay) { return 0 }
        var count = 1
        var index = lastIndex
        while index > 0, isRestOnly(between: readDays[index - 1], and: readDays[index]) {
            count += 1
            index -= 1
        }
        return count
    }

    /// The longest run of reading days, in one `year` or across all history (up to today) when nil.
    func longestStreak(year: Int? = nil) -> Int {
        var first = Date.distantPast
        var last = today
        if let year {
            guard let start = startOfYear(year), let next = startOfYear(year + 1) else { return 0 }
            first = start
            last = min(today, addDays(-1, to: next))
        }
        return longestStreak(from: first, through: last)
    }

    /// The longest run of reading days that lies entirely within `first...last`.
    func longestStreak(from first: Date, through last: Date) -> Int {
        var best = 0
        var run = 0
        var previous: Date?
        for day in readDays where day >= first && day <= last {
            if let previous, isRestOnly(between: previous, and: day) { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = day
        }
        return best
    }

    private func lastReadIndex(onOrBefore day: Date) -> Int? {
        var low = 0
        var high = readDays.count
        while low < high {
            let mid = (low + high) / 2
            if readDays[mid] <= day { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? low - 1 : nil
    }
}

// MARK: - Small statistics

/// The handful of statistics the insights share. Plain arrays in, plain numbers out.
enum InsightsMath {
    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Where `x` sits between `low` (0) and `high` (1), clamped.
    static func ramp(_ x: Double, _ low: Double, _ high: Double) -> Double {
        guard high > low else { return x >= high ? 1 : 0 }
        return min(1, max(0, (x - low) / (high - low)))
    }

    /// A least-squares line through the points, with how many standard errors the slope is from zero.
    struct Fit: Sendable {
        var slope: Double
        var intercept: Double
        var tStatistic: Double
    }

    static func linearFit(x: [Double], y: [Double]) -> Fit? {
        let n = x.count
        guard n >= 3, n == y.count else { return nil }
        let meanX = mean(x)
        let meanY = mean(y)
        var sxx = 0.0
        var sxy = 0.0
        for index in 0..<n {
            sxx += (x[index] - meanX) * (x[index] - meanX)
            sxy += (x[index] - meanX) * (y[index] - meanY)
        }
        guard sxx > 1e-12 else { return nil }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        var sse = 0.0
        for index in 0..<n {
            let residual = y[index] - (intercept + slope * x[index])
            sse += residual * residual
        }
        let standardError = (sse / Double(n - 2) / sxx).squareRoot()
        let t: Double
        if standardError > 1e-12 {
            t = slope / standardError
        } else {
            t = abs(slope) < 1e-12 ? 0 : (slope > 0 ? .infinity : -.infinity)
        }
        return Fit(slope: slope, intercept: intercept, tStatistic: t)
    }
}
