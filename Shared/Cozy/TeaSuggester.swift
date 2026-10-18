import Foundation

/// Picks a tea for the moment. Pure and deterministic: the same inputs and seed give the same tea, so Today doesn’t
/// flicker on re-render. Pass `SeededGenerator.daySeed(...)` to get a fresh pick each day that holds steady within it.
///
/// Three things matter, in this order:
/// 1. Caffeine by the clock. This is a hard rule: nothing with caffeine late at night, nothing strong in the evening.
/// 2. Fit: the hour, the season, and the weather if it is known.
/// 3. Manners: never the tea you just had, and a gentle lean toward the one you love.
enum TeaSuggester {
    /// The most caffeine a tea may carry at this hour. A favourite tea has to obey it too.
    static func caffeineCap(for daypart: Daypart) -> TeaCaffeine {
        switch daypart {
        case .smallHours, .late: return .none
        case .evening: return .low
        case .dusk, .teaTime: return .medium
        case .dawn, .morning, .lunch, .afternoon: return .high
        }
    }

    /// Every tea allowed at this hour, before fit and manners are weighed.
    static func allowed(at daypart: Daypart) -> [Tea] {
        let cap = caffeineCap(for: daypart)
        return TeaCatalog.all.filter { $0.caffeine <= cap }
    }

    /// The best tea for now.
    static func suggest(
        daypart: Daypart,
        season: Season,
        weather: CozyWeather? = nil,
        lastTeaID: String? = nil,
        favoriteTeaID: String? = nil,
        seed: UInt64 = 0
    ) -> Tea {
        ranked(daypart: daypart, season: season, weather: weather, lastTeaID: lastTeaID, favoriteTeaID: favoriteTeaID, seed: seed, limit: 1).first
            ?? TeaCatalog.earlGrey
    }

    /// The allowed teas, best first, for a "something else?" tap.
    static func ranked(
        daypart: Daypart,
        season: Season,
        weather: CozyWeather? = nil,
        lastTeaID: String? = nil,
        favoriteTeaID: String? = nil,
        seed: UInt64 = 0,
        limit: Int = 5
    ) -> [Tea] {
        let scored = allowed(at: daypart).map { tea -> (tea: Tea, score: Double) in
            var score = fit(tea, daypart: daypart, season: season, weather: weather)
            if tea.id == favoriteTeaID { score += favoriteNudge }
            if tea.id == lastTeaID { score -= repeatPenalty }
            score += CozyRanking.wobble(seed: seed, key: tea.id) * wobbleSize
            return (tea, score)
        }
        let ordered = scored.sorted { $0.score > $1.score || ($0.score == $1.score && $0.tea.id < $1.tea.id) }
        return Array(ordered.prefix(max(0, limit)).map(\.tea))
    }

    // MARK: Weights

    /// Big enough to lean toward the favourite on a close call, small enough that it never beats a much better fit.
    static let favoriteNudge = 1.5
    /// Larger than any other term, so the last tea only comes back if it is the only choice.
    static let repeatPenalty = 100.0
    /// How far the daily seed can shuffle near-equal teas.
    static let wobbleSize = 1.5

    private static func fit(_ tea: Tea, daypart: Daypart, season: Season, weather: CozyWeather?) -> Double {
        var score = 0.0
        if tea.dayparts.contains(daypart) { score += 3 }
        if tea.seasons.contains(season) { score += 2 }
        score += caffeineFit(tea.caffeine, daypart: daypart)
        if let weather { score += weatherFit(tea, weather: weather) }
        return score
    }

    /// Morning wants a lift, the afternoon a little one, and the evening wants none.
    private static func caffeineFit(_ caffeine: TeaCaffeine, daypart: Daypart) -> Double {
        switch daypart {
        case .dawn, .morning:
            switch caffeine {
            case .high: return 1.5
            case .medium: return 0.8
            case .low: return 0
            case .none: return -0.8
            }
        case .lunch, .afternoon:
            switch caffeine {
            case .medium: return 0.8
            case .high: return 0.4
            case .low: return 0.3
            case .none: return 0
            }
        case .teaTime:
            switch caffeine {
            case .medium: return 0.6
            case .low: return 0.4
            case .none, .high: return 0
            }
        case .dusk:
            switch caffeine {
            case .low: return 0.5
            case .none: return 0.3
            case .medium, .high: return 0
            }
        case .evening:
            switch caffeine {
            case .none: return 0.6
            case .low: return 0.4
            case .medium, .high: return 0
            }
        case .late, .smallHours:
            return 0
        }
    }

    private static func weatherFit(_ tea: Tea, weather: CozyWeather) -> Double {
        let moods = Set(tea.moods)
        func has(_ mood: TeaMood, _ value: Double) -> Double { moods.contains(mood) ? value : 0 }
        switch weather {
        case .rain, .fog:
            return has(.rainyDay, 2) + has(.warming, 0.6) + has(.cozy, 0.4)
        case .snow, .cold:
            return has(.warming, 2) + has(.cozy, 0.6) - has(.refreshing, 1.5)
        case .hot:
            return has(.refreshing, 2) - has(.warming, 1.5)
        case .cloudy:
            return has(.cozy, 0.4)
        case .clear:
            return has(.uplifting, 0.4)
        }
    }

    // MARK: Steeping

    /// Seconds to steep a tea at the reader’s strength, to the nearest five. Light is a shorter steep and strong a
    /// longer one, kept within a sensible range so a strong cup never turns into a bitter one.
    static func steepSeconds(for tea: Tea, strength: TeaStrength = .regular) -> Int {
        let raw = Double(tea.steepSeconds) * strength.multiplier
        let rounded = Int((raw / 5).rounded()) * 5
        return min(maximumSteepSeconds, max(minimumSteepSeconds, rounded))
    }

    static let minimumSteepSeconds = 15
    /// Ten minutes: past this, even herbal tea is only getting stronger in a bad way.
    static let maximumSteepSeconds = 600
}
