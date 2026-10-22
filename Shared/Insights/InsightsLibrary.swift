import Foundation

// MARK: - Genre and length mix

extension InsightsEngine {
    /// One slice of the genre pie.
    struct GenreShare: Hashable, Identifiable, Sendable {
        /// The catalog tag ("fantasy", "science-fiction"), or "other" for books with no genre.
        var tag: String
        /// Friendly name for sentences ("science fiction").
        var name: String
        /// Finished books that carry this tag.
        var books: Int
        /// Share of finished books, 0 to 1. A book with several genres splits its weight between them, so the shares
        /// of all slices add up to 1.
        var share: Double

        var id: String { tag }
    }

    /// One slice of the length pie.
    struct LengthShare: Hashable, Identifiable, Sendable {
        var band: LengthBand
        var books: Int
        var share: Double

        var id: Int { band.rawValue }

        /// "short reads", "medium reads", "long reads".
        var label: String {
            switch band {
            case .short: return "short reads"
            case .medium: return "medium reads"
            case .long: return "long reads"
            }
        }

        /// What the band means at the reader's pace: "under 6 hours", "6 to 14 hours", "over 14 hours".
        var detail: String {
            switch band {
            case .short: return "under 6 hours"
            case .medium: return "6 to 14 hours"
            case .long: return "over 14 hours"
            }
        }
    }

    /// What the reader finishes, by genre, biggest slice first. Pass a `year` to look at one year. Empty when nothing
    /// has been finished.
    func genreMix(year: Int? = nil) -> [GenreShare] {
        let finished = finishedItems(year: year)
        guard !finished.isEmpty else { return [] }
        var weights: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for item in finished {
            var seen = Set<String>()
            let tags = item.book.genres.filter { !$0.isEmpty && seen.insert($0).inserted }
            let effective = tags.isEmpty ? ["other"] : tags
            for tag in effective {
                weights[tag, default: 0] += 1 / Double(effective.count)
                counts[tag, default: 0] += 1
            }
        }
        let total = Double(finished.count)
        return weights
            .map { tag, weight in
                GenreShare(tag: tag, name: Genre.name(tag), books: counts[tag] ?? 0, share: weight / total)
            }
            .sorted { lhs, rhs in
                abs(lhs.share - rhs.share) > 1e-9 ? lhs.share > rhs.share : lhs.tag < rhs.tag
            }
    }

    /// What the reader finishes, by length at their own pace. All three bands, in order, when anything has been
    /// finished; empty otherwise.
    func lengthMix(year: Int? = nil) -> [LengthShare] {
        let finished = finishedItems(year: year)
        guard !finished.isEmpty else { return [] }
        let wpm = max(data.preferences.wpm, 40)
        var counts: [LengthBand: Int] = [:]
        for item in finished {
            counts[LengthBand.of(hours: item.book.minutes(atWPM: wpm) / 60), default: 0] += 1
        }
        return LengthBand.allCases.map { band in
            LengthShare(band: band, books: counts[band] ?? 0, share: Double(counts[band] ?? 0) / Double(finished.count))
        }
    }
}

// MARK: - TBR depth

/// How long the To read pile would last at the reader's pace.
struct TBRDepth: Hashable, Sendable {
    enum Basis: String, Sendable {
        /// The daily minutes and reading days chosen in settings.
        case goal
        /// What the reader actually did over the last four weeks.
        case recent
    }

    var queueBooks: Int
    /// Minutes to read everything on To read at the reader's words per minute.
    var queueMinutes: Double
    /// Books on Reading or Paused, which count as in progress.
    var inProgressBooks: Int
    var inProgressMinutes: Double
    /// Minutes of reading per calendar day (rest days averaged in) that the estimate assumes.
    var minutesPerDay: Double
    var basis: Basis
    /// Months to read the whole To read queue, or nil when the reader has no daily time at all.
    var months: Double?
    /// "Your TBR is 14 months deep at this pace."
    var sentence: String

    /// "under a month", "about a month", "14 months", "2 years", "2.5 years".
    static func phrase(months: Double) -> String {
        if months < 0.75 { return "under a month" }
        if months < 1.5 { return "about a month" }
        if months < 24 { return "\(Int(months.rounded())) months" }
        let years = (months / 12 * 2).rounded() / 2
        if years == years.rounded() { return "\(Int(years)) years" }
        return String(format: "%.1f years", years)
    }
}

extension InsightsEngine {
    /// Months of reading waiting in the To read queue. Uses the reader's real recent pace once they have a few weeks of
    /// history, and the goal they set before that.
    func tbrDepth() -> TBRDepth {
        let wpm = max(data.preferences.wpm, 40)
        let queue = data.items.filter { $0.shelf == .toRead }
        let open = data.items.filter { $0.shelf == .reading || $0.shelf == .paused }
        let queueMinutes = queue.reduce(0) { $0 + $1.minutesLeft(atWPM: wpm) }
        let openMinutes = open.reduce(0) { $0 + $1.minutesLeft(atWPM: wpm) }

        let goalPerDay = Double(max(0, data.preferences.dailyMinutes)) * Double(schedule.count) / 7
        var perDay = goalPerDay
        var basis = TBRDepth.Basis.goal
        if let recent = recentDailyAverage() {
            perDay = recent
            basis = .recent
        }

        let months: Double? = perDay > 0.01 ? queueMinutes / perDay / 30.4375 : nil
        let sentence: String
        if queue.isEmpty {
            sentence = "Your Up next pile is empty."
        } else if let months {
            sentence = "Your TBR is \(TBRDepth.phrase(months: months)) deep at this pace."
        } else {
            sentence = "Set a daily reading time to see how deep your TBR is."
        }
        return TBRDepth(
            queueBooks: queue.count,
            queueMinutes: queueMinutes,
            inProgressBooks: open.count,
            inProgressMinutes: openMinutes,
            minutesPerDay: perDay,
            basis: basis,
            months: months,
            sentence: sentence
        )
    }

    /// Minutes per calendar day over the last four weeks, or nil until there are two weeks of history and five read
    /// days in the window.
    private func recentDailyAverage() -> Double? {
        guard let firstDay = sittings.first?.day else { return nil }
        let observed = min(28, max(1, daysBetween(firstDay, today) + 1))
        let start = addDays(-(observed - 1), to: today)
        let inWindow = readDays.filter { $0 >= start && $0 <= today }
        guard observed >= 14, inWindow.count >= 5 else { return nil }
        let minutes = sittings(from: start, through: today).reduce(0) { $0 + $1.minutes }
        return minutes / Double(observed)
    }
}

// MARK: - Year goal pacing

/// Books finished this year against a straight line from zero to the goal.
struct YearGoalPacing: Hashable, Sendable {
    enum Status: String, Sendable {
        case noGoal, ahead, onTrack, behind, reached
    }

    var year: Int
    /// The yearly goal, or nil when the reader has not set one.
    var goal: Int?
    var finished: Int
    /// Where a steady reader would be today: the goal times the share of the year gone (today counted).
    var expectedByToday: Double
    /// `finished - expectedByToday`; positive is ahead.
    var difference: Double
    /// `difference` rounded to whole books: +2 is two books ahead, -3 is three behind.
    var booksAheadOrBehind: Int
    var status: Status
    var remaining: Int
    /// Days left in the year after today.
    var daysLeft: Int
    /// Books a month from here to reach the goal, counting today (0 once reached).
    var booksPerMonthNeeded: Double
    /// Books a month so far this year (never judged over less than a month).
    var booksPerMonthSoFar: Double
    /// Where the year would end if the pace so far simply continued (never extrapolated from less than a month).
    var straightLineProjection: Double
}

extension InsightsEngine {
    /// Where the reader stands against their yearly goal. The chance of making it lives in the forecast engine; this is
    /// the plain arithmetic.
    func yearGoalPacing() -> YearGoalPacing {
        let year = currentYear
        let finished = finishedItems(year: year).count
        // Counted with whole local days, not `ordinality`, which Foundation on Linux works out in UTC.
        let yearStart = startOfYear(year)
        let dayOfYear = max(1, yearStart.map { daysBetween($0, today) + 1 } ?? 1)
        let daysInYear = max(dayOfYear, yearStart.flatMap { start in startOfYear(year + 1).map { daysBetween(start, $0) } } ?? 365)
        let fraction = Double(dayOfYear) / Double(daysInYear)
        let daysLeft = daysInYear - dayOfYear

        let goal = data.preferences.yearlyGoal.flatMap { $0 > 0 ? $0 : nil }
        let expected = Double(goal ?? 0) * fraction
        let difference = goal == nil ? 0 : Double(finished) - expected
        let signed = Int(difference.rounded())
        let remaining = max(0, (goal ?? 0) - finished)
        let monthsLeft = Double(daysLeft + 1) / Double(daysInYear) * 12

        let status: YearGoalPacing.Status
        if goal == nil {
            status = .noGoal
        } else if remaining == 0 {
            status = .reached
        } else if signed >= 1 {
            status = .ahead
        } else if signed <= -1 {
            status = .behind
        } else {
            status = .onTrack
        }

        return YearGoalPacing(
            year: year,
            goal: goal,
            finished: finished,
            expectedByToday: expected,
            difference: difference,
            booksAheadOrBehind: signed,
            status: status,
            remaining: remaining,
            daysLeft: daysLeft,
            booksPerMonthNeeded: remaining == 0 ? 0 : Double(remaining) / max(monthsLeft, 1.0 / 31),
            booksPerMonthSoFar: Double(finished) / max(1, fraction * 12),
            straightLineProjection: Double(finished) / max(fraction, 1.0 / 12)
        )
    }
}
