import Foundation

/// Why a greeting was chosen, in the engine's priority order: the first one that applies wins, except that the last
/// few (weather and friends) take a turn only some of the time so the ordinary time-of-day lines still show up.
enum GreetingTag: String, CaseIterable, Sendable {
    case firstEver, nearFinish, finishedToday, welcomeBack, goalMet, restDay, streak, stalled
    case holiday, goalProgress, weather, moon, book, weekday, season, daypart
    /// Written by the on-device model rather than picked from the pool.
    case generated
}

/// A bucket of lines for one kind of moment. Every bucket has at least three lines in the pool.
enum GreetingMoment: String, CaseIterable, Sendable {
    case firstEver
    case nearFinish, finishedToday
    case welcomeBack, welcomeBackLong
    case goalMet, goalPartial
    case restDay
    case streakWeek, streakFortnight, streakMonth, streakCentury, streakOther, streakGoing
    case stalled
    case newYearsEve, newYear, valentines, easter, halloween, spookySeason, thanksgiving
    case christmasSeason, christmasEve, christmas
    case rain, snow, cold, hot, wind, fog, clear
    case fullMoon, newMoon
    case justStarted, midway
    case monday, friday, saturday, sunday
    case spring, summer, autumn, winter
    case dawn, morning, lunch, afternoon, teaTime, dusk, evening, late, smallHours

    var tag: GreetingTag {
        switch self {
        case .firstEver: return .firstEver
        case .nearFinish: return .nearFinish
        case .finishedToday: return .finishedToday
        case .welcomeBack, .welcomeBackLong: return .welcomeBack
        case .goalMet: return .goalMet
        case .goalPartial: return .goalProgress
        case .restDay: return .restDay
        case .streakWeek, .streakFortnight, .streakMonth, .streakCentury, .streakOther, .streakGoing: return .streak
        case .stalled: return .stalled
        case .newYearsEve, .newYear, .valentines, .easter, .halloween, .spookySeason, .thanksgiving,
             .christmasSeason, .christmasEve, .christmas: return .holiday
        case .rain, .snow, .cold, .hot, .wind, .fog, .clear: return .weather
        case .fullMoon, .newMoon: return .moon
        case .justStarted, .midway: return .book
        case .monday, .friday, .saturday, .sunday: return .weekday
        case .spring, .summer, .autumn, .winter: return .season
        case .dawn, .morning, .lunch, .afternoon, .teaTime, .dusk, .evening, .late, .smallHours: return .daypart
        }
    }

    /// The placeholders the engine always has when it picks this bucket. A bucket needs at least three lines that use
    /// nothing beyond these, so it can never run dry when the optional facts (a title, a tea) are missing.
    var guaranteedPlaceholders: Set<VoicePlaceholder> {
        switch self {
        case .nearFinish: return [.pages, .day]
        case .goalPartial: return [.minutes, .day]
        case .streakWeek, .streakFortnight, .streakMonth, .streakCentury, .streakOther, .streakGoing: return [.streak, .day]
        default: return [.day]
        }
    }

    static func daypart(_ daypart: Daypart) -> GreetingMoment {
        switch daypart {
        case .smallHours: return .smallHours
        case .dawn: return .dawn
        case .morning: return .morning
        case .lunch: return .lunch
        case .afternoon: return .afternoon
        case .teaTime: return .teaTime
        case .dusk: return .dusk
        case .evening: return .evening
        case .late: return .late
        }
    }

    static func holiday(_ holiday: GreetingHoliday) -> GreetingMoment {
        switch holiday {
        case .newYearsEve: return .newYearsEve
        case .newYear: return .newYear
        case .valentines: return .valentines
        case .easter: return .easter
        case .halloween: return .halloween
        case .spookySeason: return .spookySeason
        case .thanksgiving: return .thanksgiving
        case .christmasSeason: return .christmasSeason
        case .christmasEve: return .christmasEve
        case .christmas: return .christmas
        }
    }

    static func weather(_ weather: GreetingWeather) -> GreetingMoment? {
        switch weather {
        case .rain: return .rain
        case .snow: return .snow
        case .cold: return .cold
        case .hot: return .hot
        case .wind: return .wind
        case .fog: return .fog
        case .clear: return .clear
        case .unknown: return nil
        }
    }

    static func season(_ season: Season) -> GreetingMoment {
        switch season {
        case .spring: return .spring
        case .summer: return .summer
        case .autumn: return .autumn
        case .winter: return .winter
        }
    }
}

/// What the engine hands back: the words, why they were chosen, and an id the app keeps so tomorrow's greeting is
/// never the same line.
struct Greeting: Equatable, Sendable {
    var headline: String
    var subline: String?
    var tag: GreetingTag
    /// The bucket it came from, or nil for a generated line.
    var moment: GreetingMoment?
    /// Stable per line. Store the last one shown and pass it back as `previousLineID` (see `GreetingMemory`).
    var lineID: String

    /// Headline and subline as one string: "Still up? One more page, then bed."
    var text: String {
        guard let subline, !subline.isEmpty else { return headline }
        return headline + " " + subline
    }
}

/// One line in the pool, as plain data. The headline and subline may hold `{placeholders}`.
struct GreetingLine: Equatable, Sendable, Identifiable {
    let id: String
    let moment: GreetingMoment
    let headline: String
    let subline: String?
    /// Nil means any time of day. Used for lines that only make sense at certain hours ("Seven evenings in a row").
    let dayparts: Set<Daypart>?
    /// Relative odds within a bucket. The late-night signature line is heavier than the rest.
    let weight: Double
    let placeholders: Set<VoicePlaceholder>

    /// `row` is "Headline" or "Headline | Subline".
    init(moment: GreetingMoment, row: String, dayparts: Set<Daypart>? = nil, weight: Double = 1) {
        let pieces = row.components(separatedBy: " | ")
        headline = pieces[0].trimmingCharacters(in: .whitespaces)
        let rest = pieces.dropFirst().joined(separator: " | ").trimmingCharacters(in: .whitespaces)
        subline = rest.isEmpty ? nil : rest
        self.moment = moment
        self.dayparts = dayparts
        self.weight = weight
        placeholders = VoiceTemplate.placeholders(in: headline).union(VoiceTemplate.placeholders(in: rest))
        id = VoiceText.stableID(moment.rawValue, headline + "|" + rest)
    }

    /// The template as one string, with the placeholders still in it.
    var template: String { subline.map { headline + " " + $0 } ?? headline }
}
