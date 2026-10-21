import Foundation

// The few facts Leaf's Home Screen and Lock Screen widgets and its Control Center controls draw. The app writes the
// snapshot to the App Group after every change (`Leaf/Services/WidgetFeed.swift`); the extension only reads it. Like
// the rest of this folder it is plain Foundation, so it compiles into the app (which stages the widgets for
// screenshots) and the extension, and can't reach anything in Shared/.

/// What the widgets show, worked out by the app from the library. Small on purpose: a widget extension has little
/// memory and no business with the engines.
struct LeafWidgetSnapshot: Codable, Hashable, Sendable {
    struct Book: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var title: String
        var author: String
        var currentPage: Int
        var pages: Int
        var paletteSeed: Int
        /// The cover's base name in the App Group (`ReadingActivityAssets`), nil when the app couldn't write one.
        var coverFileName: String?
        /// The likely finish day (the forecast's median, else the plan's), nil when there's no telling.
        var finish: Date?
        /// On the Reading shelf, rather than waiting in To read.
        var isReading: Bool

        var progress: Double { pages > 0 ? min(1, max(0, Double(currentPage) / Double(pages))) : 0 }
    }

    struct Day: Codable, Hashable, Sendable {
        var date: Date
        var minutes: Double
        var isReadingDay: Bool
    }

    /// The reading session running now. The timer fields mean the same as `ReadingActivityContent`'s.
    struct Session: Codable, Hashable, Sendable {
        var bookID: String
        /// The real start moved forward by every pause, so `Text(timerInterval:)` shows reading time only.
        var timerStart: Date
        var isPaused: Bool
        /// Reading seconds at the pause, while paused.
        var pausedElapsed: Double
        /// The cup, or what was left of today's goal when it began; nil for an open-ended session.
        var goalSeconds: Double?
        var teaName: String?
    }

    /// A pot steeping before the cup of reading.
    struct Steep: Codable, Hashable, Sendable {
        var teaName: String
        var startedAt: Date
        var steepSeconds: Int

        var readyAt: Date { startedAt.addingTimeInterval(Double(steepSeconds)) }
        /// Half an hour after it's ready the tea has gone cold and the pot is cleared (as `TeaSteepState` does).
        var coldAt: Date { readyAt.addingTimeInterval(30 * 60) }
    }

    /// The day `minutesReadToday` belongs to (its start).
    var day: Date
    var dailyMinutes: Int
    var minutesReadToday: Double
    var isReadingDay: Bool
    var hasOnboarded: Bool
    var streak: Int
    /// The book Today suggests: the session's book while one runs.
    var current: Book?
    /// Today's pages for `current`, when the plan has some.
    var fromPage: Int?
    var toPage: Int?
    /// Up to three books after `current`: the rest of Reading, then To read.
    var upNext: [Book]
    /// Monday to Sunday (or the reader's own week), today among them.
    var week: [Day]
    var session: Session?
    var steep: Steep?

    var minutesLeft: Double { max(0, Double(dailyMinutes) - minutesReadToday) }
    var goalProgress: Double { dailyMinutes > 0 ? min(1, minutesReadToday / Double(dailyMinutes)) : 0 }
    var isGoalMet: Bool { dailyMinutes > 0 && minutesReadToday >= Double(dailyMinutes) }
    var isRestDay: Bool { !isReadingDay && minutesReadToday == 0 }
    var minutesLeftText: String { "\(Int(minutesLeft.rounded(.up)))" }

    /// The snapshot as it reads at `date`: a new day starts from nothing read, and a cold pot is gone.
    func at(_ date: Date, calendar: Calendar = .current) -> LeafWidgetSnapshot {
        var next = self
        if let steep, date >= steep.coldAt { next.steep = nil }
        guard !calendar.isDate(date, inSameDayAs: day) else { return next }
        next.day = calendar.startOfDay(for: date)
        next.minutesReadToday = 0
        next.fromPage = nil
        next.toPage = nil
        let weekday = calendar.component(.weekday, from: date)
        next.isReadingDay = week.first { calendar.component(.weekday, from: $0.date) == weekday }?.isReadingDay ?? isReadingDay
        // Past the end of the week the strip would show last week's days; start the new one empty.
        if !week.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            next.week = week.map { Day(date: calendar.date(byAdding: .day, value: 7, to: $0.date) ?? $0.date, minutes: 0, isReadingDay: $0.isReadingDay) }
        }
        return next
    }

    /// What the widget is about at `date`: a timer when one runs, else today's reading.
    func phase(at date: Date) -> LeafWidgetPhase {
        if let session {
            if session.isPaused { return .paused }
            if let goal = session.goalSeconds, goal > 0, date.timeIntervalSince(session.timerStart) < goal { return .reading }
            return (session.goalSeconds ?? 0) > 0 ? .goalReached : .reading
        }
        if let steep, date < steep.coldAt {
            return date < steep.readyAt ? .steeping : .teaReady
        }
        guard hasOnboarded, current != nil else { return .empty }
        if isGoalMet { return .goalMet }
        if isRestDay || dailyMinutes == 0 { return .rest }
        return .today
    }

    /// "13 min · p. 143", as the watch face writes it, with the goal-met and rest-day variants.
    var line: String {
        let page = current.map { " · p. \($0.currentPage)" } ?? ""
        if isRestDay { return "Rest day" + page }
        if isGoalMet { return "Goal met" + page }
        return "\(minutesLeftText) min" + page
    }

    /// The sentence VoiceOver reads for today's reading.
    var spoken: String {
        var parts: [String] = []
        if isRestDay {
            parts.append("A rest day.")
        } else if isGoalMet {
            parts.append("Today’s reading goal is met.")
        } else {
            let left = Int(minutesLeft.rounded(.up))
            parts.append("\(left) \(left == 1 ? "minute" : "minutes") left today.")
        }
        if let current {
            parts.append("\(current.title), from page \(current.currentPage).")
        }
        return parts.joined(separator: " ")
    }

    /// The moments the widget should change by itself, after `now`: the goal crossed, the tea ready, the pot gone
    /// cold, and midnight. The timeline holds one entry for each, and the system draws the seconds in between.
    func changes(after now: Date, calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        if let session, !session.isPaused, let goal = session.goalSeconds, goal > 0 {
            dates.append(session.timerStart.addingTimeInterval(goal))
        }
        if let steep {
            dates.append(steep.readyAt)
            dates.append(steep.coldAt)
        }
        let today = calendar.startOfDay(for: now)
        if let midnight = calendar.date(byAdding: .day, value: 1, to: today) { dates.append(midnight) }
        return Array(Set(dates.filter { $0 > now })).sorted()
    }

    static let empty = LeafWidgetSnapshot(
        day: .distantPast, dailyMinutes: 0, minutesReadToday: 0, isReadingDay: true, hasOnboarded: false, streak: 0,
        current: nil, fromPage: nil, toPage: nil, upNext: [], week: [], session: nil, steep: nil
    )

    /// A lived-in evening for previews, the placeholder and the widget gallery.
    static func sample(now: Date = Date(), calendar: Calendar = .current) -> LeafWidgetSnapshot {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let minutes: [Double] = [22, 31, 18, 12, 0, 0, 0]
        let week = (0..<7).map { offset -> Day in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? today
            let isPast = date <= today
            return Day(date: date, minutes: isPast ? minutes[offset] : 0, isReadingDay: offset != 5)
        }
        let read = week.first { calendar.isDate($0.date, inSameDayAs: today) }?.minutes ?? 12
        func later(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: today) ?? today }
        return LeafWidgetSnapshot(
            day: today, dailyMinutes: 25, minutesReadToday: read, isReadingDay: true, hasOnboarded: true, streak: 6,
            current: Book(id: "OL27482W", title: "The Hobbit", author: "J.R.R. Tolkien", currentPage: 143, pages: 310, paletteSeed: 2, coverFileName: nil, finish: later(9), isReading: true),
            fromPage: 143, toPage: 154,
            upNext: [
                Book(id: "circe", title: "Circe", author: "Madeline Miller", currentPage: 58, pages: 393, paletteSeed: 6, coverFileName: nil, finish: later(26), isReading: true),
                Book(id: "piranesi", title: "Piranesi", author: "Susanna Clarke", currentPage: 0, pages: 245, paletteSeed: 1, coverFileName: nil, finish: later(41), isReading: false),
                Book(id: "remains", title: "The Remains of the Day", author: "Kazuo Ishiguro", currentPage: 0, pages: 258, paletteSeed: 9, coverFileName: nil, finish: nil, isReading: false),
            ],
            week: week, session: nil, steep: nil
        )
    }
}

/// What a widget is showing at a moment.
enum LeafWidgetPhase: String, Hashable, Sendable {
    /// Today's minutes left and the page to start from.
    case today
    case goalMet
    case rest
    /// Nothing to read yet, or Leaf not set up.
    case empty
    case reading
    case paused
    /// A session past its goal, still counting up.
    case goalReached
    case steeping
    case teaReady

    var isTimer: Bool { [.reading, .paused, .goalReached, .steeping, .teaReady].contains(self) }
}

/// Where the snapshot lives: the App Group's shared defaults, beside the watch's own complication snapshot.
enum LeafWidgetStore {
    static let appGroup = ReadingActivityAssets.appGroup
    /// The Home Screen and Lock Screen widget.
    static let todayKind = "LeafToday"
    static let readControlKind = "com.norvodesigns.leaf.control.read"
    static let steepControlKind = "com.norvodesigns.leaf.control.steep"
    static let logControlKind = "com.norvodesigns.leaf.control.log"
    private static let key = "leaf.widget"

    static func read() -> LeafWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LeafWidgetSnapshot.self, from: data)
    }

    /// Saves the snapshot; true when it differs from what was there, so timelines are reloaded only then.
    @discardableResult
    static func write(_ snapshot: LeafWidgetSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup), let data = try? JSONEncoder().encode(snapshot) else { return false }
        guard defaults.data(forKey: key) != data else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
