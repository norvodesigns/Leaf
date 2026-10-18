import Foundation

/// Knobs for the forecast. The defaults are the ones the models were designed around; tests and the backtest turn a few.
struct ForecastOptions: Sendable {
    /// How far ahead a simulated future runs. A book that would finish later has no finish date.
    var horizonDays = 730
    /// A Reading book with no progress for this many days is offered a rest.
    var stallDays = 14
    /// How many weeks of recent days the adherence model looks at.
    var historyWeeks = 8
    /// Genre and book levels are pulled toward their parent as if they had this many sessions of their own.
    var priorSessions = 5.0
    /// The reader's words-per-minute setting is a weaker parent: it comes from a passage test, not from books.
    var globalPriorSessions = 3.0
    /// Sessions shorter than this say little about speed.
    var minimumSessionMinutes = 3.0
    /// A session typed in afterwards counts for this much of a timed one.
    var manualWeight = 0.5
    /// A book needs this many sessions before it gets a correction of its own.
    var bookCorrectionSessions = 3
    /// Limits on the per-book correction (slow books slow down, quick ones speed up, within reason).
    var bookCorrectionRange: ClosedRange<Double> = 0.7...1.4
}

/// Whole-day arithmetic for the forecast. Days are counted from a fixed reference so every conversion is one calendar
/// call, and weekdays then follow by modulo, which holds in every calendar and across daylight-saving changes.
struct ForecastDays: Sendable {
    let calendar: Calendar
    private let reference: Date
    private let referenceWeekday: Int

    init(calendar: Calendar) {
        self.calendar = calendar
        reference = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        referenceWeekday = calendar.component(.weekday, from: reference)
    }

    /// The day number of a date (days since the reference, in the reader's calendar).
    func number(_ date: Date) -> Int {
        calendar.dateComponents([.day], from: reference, to: calendar.startOfDay(for: date)).day ?? 0
    }

    func start(ofDay number: Int) -> Date {
        calendar.date(byAdding: .day, value: number, to: reference) ?? reference
    }

    /// Calendar weekday (1 = Sunday ... 7 = Saturday) of a day number.
    func weekday(ofDay number: Int) -> Int {
        let shifted = (referenceWeekday - 1 + number) % 7
        return (shifted + 7) % 7 + 1
    }

    func minuteOfDay(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// One logged session with everything the models need worked out once: when, how long, how many pages, and the speed
/// it implies (or nil when the session says nothing reliable about speed).
struct ForecastSessionRecord: Sendable {
    var bookID: String
    var genre: String
    var startedAt: Date
    var day: Int
    var weekday: Int
    var minuteOfDay: Int
    var daypart: Daypart
    var minutes: Double
    var seconds: Double
    var fromPage: Int
    var toPage: Int
    var pages: Int
    var wordsPerPage: Double
    var isManual: Bool
    /// Words per minute for this session, or nil when it is too short, has no pages, or is not believable.
    var wpm: Double?
    /// How much to trust the speed: lower for typed-in sessions and for ones with so few pages that rounding dominates.
    var weight: Double
}

enum ForecastRecords {
    /// The page rounding of a session (a page more or less) is the main measurement noise, about 0.29 of a page.
    static let pageRoundingSD = 0.29
    /// Typical session-to-session spread of log speed, used to turn rounding noise into a weight.
    static let referenceSpread = 0.2

    /// Builds the records for every session up to `now`, oldest first. Sessions of books that left the library still
    /// count for how often and how long the reader reads, but not for speed.
    static func make(sessions: [ReadingSession], items: [LibraryItem], days: ForecastDays, now: Date, options: ForecastOptions) -> [ForecastSessionRecord] {
        var itemByID: [String: LibraryItem] = [:]
        for item in items { itemByID[item.id] = item }
        let ordered = sessions
            .filter { $0.startedAt <= now && $0.seconds > 0 }
            .sorted { $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt }

        return ordered.map { session in
            let item = itemByID[session.bookID]
            let wordsPerPage = item?.book.wordsPerPage ?? 270
            // A first session logged from page 0 of a book the reader had half read would look absurdly fast.
            let fromPage = max(session.fromPage, item?.startPage ?? 0)
            let pages = max(0, session.toPage - fromPage)
            let minutes = session.seconds / 60
            let isManual = session.kind == .manual

            var wpm: Double?
            var weight = 0.0
            if item != nil, minutes >= options.minimumSessionMinutes, pages >= 1 {
                let value = Double(pages) * wordsPerPage / minutes
                if ReadingSpeed.plausibleRange.contains(value) {
                    wpm = value
                    let noise = pageRoundingSD / Double(pages)
                    let reference = referenceSpread * referenceSpread
                    weight = reference / (reference + noise * noise) * (isManual ? options.manualWeight : 1)
                }
            }
            return ForecastSessionRecord(
                bookID: session.bookID,
                genre: item.map { primaryGenre(of: $0.book) } ?? "other",
                startedAt: session.startedAt,
                day: days.number(session.startedAt),
                weekday: days.weekday(ofDay: days.number(session.startedAt)),
                minuteOfDay: days.minuteOfDay(session.startedAt),
                daypart: Daypart.of(session.startedAt, calendar: days.calendar),
                minutes: minutes,
                seconds: session.seconds,
                fromPage: fromPage,
                toPage: session.toPage,
                pages: pages,
                wordsPerPage: wordsPerPage,
                isManual: isManual,
                wpm: wpm,
                weight: weight
            )
        }
    }

    /// The genre a book's pace is pooled under: its first listed genre.
    static func primaryGenre(of book: Book) -> String {
        book.genres.first ?? "other"
    }
}
