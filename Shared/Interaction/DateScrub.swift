import Foundation

/// One stop on the finish-by timeline: a date, how far along the timeline it is, and what it would take to finish a
/// book by then.
struct DateScrubResult: Sendable, Equatable {
    /// Days after the timeline's start (today).
    var dayOffset: Int
    /// Start of that day, in the scrub's calendar.
    var date: Date
    /// 0 at the earliest date, 1 at the latest. Where to draw the handle.
    var fraction: Double
    /// Minutes of reading per day needed to finish by `date`, from the caller's closure. Nil when the closure has no
    /// answer (or an unusable one), so the view can say "can't tell" instead of a made-up number.
    var minutesPerDay: Double?
    var isEarliest: Bool
    var isLatest: Bool
}

/// Maps a drag across a timeline to a "finish by" date and the minutes a day that date would take. The planner owns
/// the arithmetic of how many minutes a book needs; this owns the gesture, and asks the caller's closure for the
/// minutes. Dates are whole calendar days counted from `start`, so daylight saving never makes a day 23 or 25 steps.
///
/// Everything is a pure function of its inputs: pass today in, never ask the clock.
struct DateScrub: Sendable {
    /// The most reading a day can hold; anything above is treated as no answer.
    static let minutesInDay = 1440.0

    /// Today (any moment in it); offsets count from the start of this day.
    let start: Date
    let calendar: Calendar
    /// The first and last offsets the timeline reaches, in days after `start`.
    let earliestOffset: Int
    let latestOffset: Int
    /// Minutes per day needed to finish by the date, given the date and the number of days from `start` to it. Return
    /// nil when it can't be worked out.
    let minutesPerDay: @Sendable (Date, Int) -> Double?

    /// - Parameters:
    ///   - earliestDay: the first finish-by day offered, in days after `start` (1 is tomorrow).
    ///   - latestDay: the last one (365 is about a year out).
    init(
        start: Date,
        calendar: Calendar,
        earliestDay: Int = 1,
        latestDay: Int = 365,
        minutesPerDay: @escaping @Sendable (Date, Int) -> Double?
    ) {
        self.start = start
        self.calendar = calendar
        let first = min(max(earliestDay, 0), 36_500)
        self.earliestOffset = first
        self.latestOffset = min(max(latestDay, first), 36_500)
        self.minutesPerDay = minutesPerDay
    }

    // MARK: Days and dates

    /// How many days the timeline spans.
    var spanDays: Int { latestOffset - earliestOffset }

    /// The start of the day `offset` days after `start`.
    func date(forOffset offset: Int) -> Date {
        let origin = calendar.startOfDay(for: start)
        return calendar.date(byAdding: .day, value: offset, to: origin) ?? origin
    }

    /// The offset of the day `date` falls on, limited to the timeline.
    func offset(of date: Date) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
        return min(max(days, earliestOffset), latestOffset)
    }

    // MARK: Results

    /// The stop for a day offset, limited to the timeline.
    func result(forOffset offset: Int) -> DateScrubResult {
        let clamped = min(max(offset, earliestOffset), latestOffset)
        let day = date(forOffset: clamped)
        let fraction = spanDays > 0 ? Double(clamped - earliestOffset) / Double(spanDays) : 0
        return DateScrubResult(
            dayOffset: clamped,
            date: day,
            fraction: fraction,
            minutesPerDay: usableMinutes(for: day, offset: clamped),
            isEarliest: clamped == earliestOffset,
            isLatest: clamped == latestOffset
        )
    }

    /// The stop `fraction` of the way along the timeline (0 earliest, 1 latest), rounded to a whole day.
    func result(forFraction fraction: Double) -> DateScrubResult {
        let f = InteractionMath.clamp(fraction, 0, 1)
        return result(forOffset: earliestOffset + Int((f * Double(spanDays)).rounded()))
    }

    /// The stop for a drag that began at `startOffset` and has moved `translation` points, at `pointsPerDay` points to
    /// the day. Positive translation moves later.
    func result(forTranslation translation: Double, from startOffset: Int, pointsPerDay: Double) -> DateScrubResult {
        guard translation.isFinite, pointsPerDay.isFinite, pointsPerDay > 0 else { return result(forOffset: startOffset) }
        let days = InteractionMath.clamp((translation / pointsPerDay).rounded(), -100_000, 100_000)
        return result(forOffset: startOffset + Int(days))
    }

    /// The stop for a finger at `x` points along a timeline `width` points wide.
    func result(forX x: Double, inWidth width: Double) -> DateScrubResult {
        guard width.isFinite, width > 0 else { return result(forOffset: earliestOffset) }
        return result(forFraction: x / width)
    }

    /// The stop for a `ScrubModel` value (a day offset).
    func result(forValue value: Double) -> DateScrubResult {
        result(forOffset: Int(InteractionMath.clamp(InteractionMath.finite(value).rounded(), Double(earliestOffset), Double(latestOffset))))
    }

    // MARK: Driving a ScrubModel

    /// A `ScrubConfiguration` for scrubbing the timeline with a `ScrubModel`: whole days, a tick on every day, a heavier
    /// tick every week, magnets at the offsets that matter (the date the current pace finishes, the date a goal hits),
    /// and a format that prints the date.
    func scrubConfiguration(magnetOffsets: [Int] = [], magnetRadius: Double = 0.45, pointsPerDay: Double = 6) -> ScrubConfiguration {
        var configuration = ScrubConfiguration(range: Double(earliestOffset)...Double(latestOffset), step: 1)
        configuration.pointsPerStep = pointsPerDay
        configuration.detentEvery = 1
        configuration.majorEvery = 7
        configuration.magnets = magnetOffsets.map { ScrubMagnet(value: Double($0), radius: magnetRadius) }
        let today = start
        let calendar = calendar
        let first = earliestOffset
        let last = latestOffset
        configuration.format = ScrubValueFormat { value in
            let offset = min(max(Int(InteractionMath.clamp(InteractionMath.finite(value).rounded(), Double(first), Double(last))), first), last)
            let origin = calendar.startOfDay(for: today)
            let day = calendar.date(byAdding: .day, value: offset, to: origin) ?? origin
            return LeafFormat.shortDate(day, today: today, calendar: calendar)
        }
        return configuration
    }

    // MARK: Helpers

    private func usableMinutes(for date: Date, offset: Int) -> Double? {
        guard let minutes = minutesPerDay(date, offset), minutes.isFinite, minutes >= 0, minutes <= DateScrub.minutesInDay else {
            return nil
        }
        return minutes
    }
}
