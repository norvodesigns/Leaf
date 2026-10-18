import Foundation

/// The four seasons, by meteorological months. The cozy features (greetings, tea, nook scenes, challenges, reading
/// rows) all key off the same definition so they never disagree about what time of year it is.
enum Season: String, Codable, CaseIterable, Sendable {
    case spring, summer, autumn, winter

    /// Northern-hemisphere months unless `southern` is set: spring is March to May, and so on.
    static func of(_ date: Date, calendar: Calendar = .current, southern: Bool = false) -> Season {
        let month = calendar.component(.month, from: date)
        let north: Season
        switch month {
        case 3...5: north = .spring
        case 6...8: north = .summer
        case 9...11: north = .autumn
        default: north = .winter
        }
        guard southern else { return north }
        switch north {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }
}

/// A stretch of the day with its own mood. Boundaries are fixed clock times, not sunrise and sunset, so the
/// result is the same on every device and easy to test.
enum Daypart: String, Codable, CaseIterable, Sendable {
    /// 02:00 to 05:00. The whole house is asleep.
    case smallHours
    /// 05:00 to 08:00.
    case dawn
    /// 08:00 to 11:30.
    case morning
    /// 11:30 to 14:00.
    case lunch
    /// 14:00 to 16:00.
    case afternoon
    /// 16:00 to 17:30. Tea o'clock.
    case teaTime
    /// 17:30 to 19:00.
    case dusk
    /// 19:00 to 23:00.
    case evening
    /// 23:00 to 02:00. "Still up?"
    case late

    static func of(_ date: Date, calendar: Calendar = .current) -> Daypart {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        switch minutes {
        case 120..<300: return .smallHours
        case 300..<480: return .dawn
        case 480..<690: return .morning
        case 690..<840: return .lunch
        case 840..<960: return .afternoon
        case 960..<1050: return .teaTime
        case 1050..<1140: return .dusk
        case 1140..<1380: return .evening
        default: return .late
        }
    }

    /// Whether most people would call this night-time.
    var isNight: Bool { self == .late || self == .smallHours }
}

/// Reading time as a friendly unit: a "cup" is one sitting (25 minutes by default, set in preferences) and a pot is
/// four cups. Real minutes are always shown beside it, so this only ever adds warmth.
enum Cups {
    static let cupsPerPot = 4

    /// Fractional cups for `minutes` of reading.
    static func count(minutes: Double, cupMinutes: Int = 25) -> Double {
        max(0, minutes) / Double(max(1, cupMinutes))
    }

    /// Whole cups, rounded down: only a full sitting counts toward totals like "112 cups this year".
    static func wholeCups(minutes: Double, cupMinutes: Int = 25) -> Int {
        Int(count(minutes: minutes, cupMinutes: cupMinutes).rounded(.down))
    }

    static func pots(cups: Int) -> Int { max(0, cups) / cupsPerPot }

    /// "a cup", "3 cups", "a pot", "2 pots", or "less than a cup".
    static func phrase(minutes: Double, cupMinutes: Int = 25) -> String {
        let cups = wholeCups(minutes: minutes, cupMinutes: cupMinutes)
        if cups == 0 { return "less than a cup" }
        if cups >= cupsPerPot, cups % cupsPerPot == 0 {
            let pots = cups / cupsPerPot
            return pots == 1 ? "a pot" : "\(pots) pots"
        }
        return cups == 1 ? "a cup" : "\(cups) cups"
    }
}
