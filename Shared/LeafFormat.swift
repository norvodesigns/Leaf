import Foundation

/// Human-friendly strings for durations, dates, and pages.
enum LeafFormat {
    /// "under a minute", "12 min", "1 h 5 min", "6 h 12 min", "112 h"
    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if minutes < 0.5 { return "under a minute" }
        if total < 60 { return "\(max(1, total)) min" }
        let hours = total / 60
        let rest = total % 60
        if hours >= 100 || rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    /// Compact form for tight spaces: "22m", "1h 5m", "6h".
    static func compactDuration(minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        if total < 60 { return "\(total)m" }
        let hours = total / 60
        let rest = total % 60
        return rest == 0 || hours >= 100 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Timer face: "4:07", "12:04", "1:02:03".
    static func clock(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// "Today", "Tomorrow", "Thursday" (within a week), "Nov 2", "Nov 2, 2027".
    static func relativeDay(_ date: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: today)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2..<7: return format(date, template: "EEEE", calendar: calendar)
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: today)
            return format(date, template: sameYear ? "MMMd" : "MMMdyyyy", calendar: calendar)
        }
    }

    /// "Nov 2" or "Nov 2, 2027" when not this year.
    static func shortDate(_ date: Date, today: Date = Date(), calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: today)
        return format(date, template: sameYear ? "MMMd" : "MMMdyyyy", calendar: calendar)
    }

    static func format(_ date: Date, template: String, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// "pp. 143–158", or "p. 143" for a single page.
    static func pages(from: Int, to: Int) -> String {
        from >= to ? "p. \(to)" : "pp. \(from)–\(to)"
    }

    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func time(hour: Int, minute: Int, calendar: Calendar = .current) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = calendar.date(from: components) ?? Date()
        return format(date, template: "jmm", calendar: calendar)
    }
}
