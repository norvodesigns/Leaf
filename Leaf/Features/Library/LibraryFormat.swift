import Foundation

/// Date phrases shared by the shelves and book detail.
enum LibraryDates {
    /// Whole days from `now` to `date` (0 = the same day, negative = in the past).
    static func days(from now: Date, to date: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// "3 Dec", or "3 Dec 2027" when it isn't this year.
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return LeafFormat.format(date, template: sameYear ? "dMMM" : "dMMMyyyy", calendar: calendar)
    }

    /// "15 Oct 2026": always with the year.
    static func dayWithYear(_ date: Date, calendar: Calendar) -> String {
        LeafFormat.format(date, template: "dMMMyyyy", calendar: calendar)
    }

    /// "done by 26 Oct", "done by tomorrow" or "finishes today".
    static func donePhrase(_ finish: Date, now: Date, calendar: Calendar) -> String {
        switch days(from: now, to: finish, calendar: calendar) {
        case ...0: return "finishes today"
        case 1: return "done by tomorrow"
        default: return "done by \(day(finish, now: now, calendar: calendar))"
        }
    }
}
