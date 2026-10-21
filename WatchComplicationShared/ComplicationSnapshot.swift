import Foundation

/// What the watch face shows. The watch app writes it after every change (LeafWatch/ComplicationFeed.swift) and the
/// complications read it (LeafWatchWidgets). Small on purpose: a widget extension has little memory and no business
/// with the engines, so it gets the few numbers it draws and nothing else.
struct ComplicationSnapshot: Codable, Hashable, Sendable {
    /// The day `minutesReadToday` belongs to (its start).
    var day: Date
    var dailyMinutes: Int
    var minutesReadToday: Double
    var isReadingDay: Bool
    /// The book Today suggests and the page to start from.
    var title: String?
    var nextPage: Int?
    /// Today's reading times, as minutes after midnight.
    var slotMinutes: [Int]
    /// When the session running now started, less its pauses, so the face can count up. Nil when none is running.
    var liveSince: Date?

    var minutesLeft: Double { max(0, Double(dailyMinutes) - minutesReadToday) }
    var goalProgress: Double { dailyMinutes > 0 ? min(1, minutesReadToday / Double(dailyMinutes)) : 0 }
    var isGoalMet: Bool { dailyMinutes > 0 && minutesReadToday >= Double(dailyMinutes) }
    var isRestDay: Bool { !isReadingDay && minutesReadToday == 0 }

    /// The snapshot as it reads at `date`: a new day starts from nothing read.
    func at(_ date: Date, calendar: Calendar = .current) -> ComplicationSnapshot {
        guard !calendar.isDate(date, inSameDayAs: day) else { return self }
        var next = self
        next.day = calendar.startOfDay(for: date)
        next.minutesReadToday = 0
        next.liveSince = nil
        return next
    }

    /// "13 min · p. 143", the line the brief asks for, with the goal-met and rest-day variants.
    var line: String {
        let page = nextPage.map { " · p. \($0)" } ?? ""
        if isRestDay { return "Rest day" + page }
        if isGoalMet { return "Goal met" + page }
        return "\(Int(minutesLeft.rounded(.up))) min" + page
    }

    /// The sentence VoiceOver reads for any of the complications.
    var spoken: String {
        var parts: [String] = []
        if liveSince != nil {
            parts.append("Reading now.")
        } else if isRestDay {
            parts.append("A rest day.")
        } else if isGoalMet {
            parts.append("Today’s reading goal is met.")
        } else {
            let left = Int(minutesLeft.rounded(.up))
            parts.append("\(left) \(left == 1 ? "minute" : "minutes") left today.")
        }
        if let title {
            parts.append(nextPage.map { "\(title), from page \($0)." } ?? "\(title).")
        }
        return parts.joined(separator: " ")
    }

    static let empty = ComplicationSnapshot(day: .distantPast, dailyMinutes: 0, minutesReadToday: 0, isReadingDay: true, title: nil, nextPage: nil, slotMinutes: [], liveSince: nil)

    static let sample = ComplicationSnapshot(
        day: Calendar.current.startOfDay(for: Date()), dailyMinutes: 25, minutesReadToday: 12, isReadingDay: true,
        title: "The Hobbit", nextPage: 143, slotMinutes: [7 * 60 + 30, 21 * 60 + 30], liveSince: nil
    )
}

/// The shared container the watch app and its complications both see.
enum ComplicationStore {
    static let appGroup = "group.com.norvodesigns.leaf"
    static let kind = "LeafWatchComplication"
    private static let key = "leaf.complication"

    static func read() -> ComplicationSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ComplicationSnapshot.self, from: data)
    }

    /// Saves the snapshot; true when it differs from what was there, so timelines are reloaded only then.
    @discardableResult
    static func write(_ snapshot: ComplicationSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup), let data = try? JSONEncoder().encode(snapshot) else { return false }
        guard defaults.data(forKey: key) != data else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
