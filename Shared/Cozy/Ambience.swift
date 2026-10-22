import Foundation

/// A background sound, as metadata only. The audio engine is built elsewhere and keys off `id`; this file says what
/// each sound is called, how loud to start it, and when it suits.
struct Ambience: Codable, Hashable, Identifiable, Sendable {
    /// Stable, and saved on sessions and in preferences as `ambienceID`.
    var id: String
    var name: String
    var blurb: String
    /// An SF Symbol name for the picker.
    var symbol: String
    /// Where the volume starts, 0 to 1. The sounds are made to one loudness (the library a little under), so they
    /// all start in the same place.
    var defaultVolume: Double
    /// Whether the sound can run for as long as the reader likes without a seam. They all can: the procedural sounds
    /// never repeat, and each recorded bed is crossfaded into itself when it loads (`AmbienceRecording`).
    var loopSafe: Bool
    var seasons: [Season]
    var dayparts: [Daypart]
    /// The weather this sound goes with.
    var weathers: [CozyWeather]

    var isSilence: Bool { id == AmbienceCatalog.silenceID }
}

enum AmbienceCatalog {
    static let silenceID = "none"

    /// Silence is part of the catalog so a picker can list it, but the suggester never offers it.
    static let none = Ambience(
        id: silenceID, name: "Silence", blurb: "Just the page turning.",
        symbol: "speaker.slash", defaultVolume: 0, loopSafe: true, seasons: [], dayparts: [], weathers: []
    )

    static let rain = Ambience(
        id: "rain", name: "Rain on the window", blurb: "A soft, steady rain, the kind that makes a chair feel better.",
        symbol: "cloud.rain", defaultVolume: 0.5, loopSafe: true,
        seasons: [.spring, .autumn], dayparts: Daypart.allCases, weathers: [.rain, .fog, .cloudy]
    )

    static let fireplace = Ambience(
        id: "fireplace", name: "Fireplace", blurb: "Embers settling and the odd crackle, close enough to warm your feet.",
        symbol: "flame", defaultVolume: 0.5, loopSafe: true,
        seasons: [.autumn, .winter], dayparts: [.teaTime, .dusk, .evening, .late, .smallHours], weathers: [.cold, .snow, .rain, .fog]
    )

    static let kettle = Ambience(
        id: "kettle", name: "Kettle on", blurb: "A kettle coming up to a simmer in the next room.",
        symbol: "cup.and.saucer", defaultVolume: 0.5, loopSafe: true,
        seasons: [.autumn, .winter, .spring], dayparts: [.dawn, .morning, .afternoon, .teaTime, .dusk], weathers: [.cold, .cloudy, .clear]
    )

    static let cafe = Ambience(
        id: "cafe", name: "Café murmur", blurb: "Low voices, cups on saucers and nobody who needs anything from you.",
        symbol: "person.2", defaultVolume: 0.5, loopSafe: true,
        seasons: [.spring, .summer, .autumn], dayparts: [.morning, .lunch, .afternoon, .teaTime], weathers: [.clear, .cloudy, .hot]
    )

    static let library = Ambience(
        id: "library", name: "Library hush", blurb: "Pages turning across the room, someone passing, the hush of a big quiet space.",
        symbol: "books.vertical", defaultVolume: 0.5, loopSafe: true,
        seasons: Season.allCases, dayparts: [.dawn, .morning, .lunch, .afternoon, .dusk, .evening, .late, .smallHours], weathers: [.clear, .cloudy, .hot, .fog]
    )

    /// In picker order: silence last.
    static let all: [Ambience] = [rain, fireplace, kettle, cafe, library, none]

    /// Everything except silence: what the suggester chooses from.
    static let sounds: [Ambience] = all.filter { !$0.isSilence }

    static let ids: [String] = all.map(\.id)

    /// The ambience with this id. A nil id means silence, which is what `preferences.ambienceID == nil` already says.
    static func ambience(id: String?) -> Ambience? {
        guard let id else { return none }
        return all.first { $0.id == id }
    }

    /// The sounds that suit this daypart at all.
    static func tagged(daypart: Daypart? = nil, season: Season? = nil) -> [Ambience] {
        sounds.filter { sound in
            (daypart.map { sound.dayparts.contains($0) } ?? true) && (season.map { sound.seasons.contains($0) } ?? true)
        }
    }
}

/// Picks a background sound for the moment, the same way the tea suggester picks a tea: deterministic by seed,
/// never the sound you just had, and a gentle lean toward your favourite.
enum AmbienceSuggester {
    static func suggest(
        daypart: Daypart,
        season: Season,
        weather: CozyWeather? = nil,
        lastAmbienceID: String? = nil,
        favoriteAmbienceID: String? = nil,
        seed: UInt64 = 0
    ) -> Ambience {
        ranked(daypart: daypart, season: season, weather: weather, lastAmbienceID: lastAmbienceID, favoriteAmbienceID: favoriteAmbienceID, seed: seed, limit: 1).first
            ?? AmbienceCatalog.library
    }

    static func ranked(
        daypart: Daypart,
        season: Season,
        weather: CozyWeather? = nil,
        lastAmbienceID: String? = nil,
        favoriteAmbienceID: String? = nil,
        seed: UInt64 = 0,
        limit: Int = 5
    ) -> [Ambience] {
        // The hour is a hard rule: no café murmur at 1am. Every hour has at least two sounds, so this never runs dry.
        let suited = AmbienceCatalog.tagged(daypart: daypart)
        let pool = suited.isEmpty ? AmbienceCatalog.sounds : suited
        let scored = pool.map { sound -> (sound: Ambience, score: Double) in
            var score = 0.0
            if sound.seasons.contains(season) { score += 2 }
            if let weather, sound.weathers.contains(weather) { score += 3 }
            if sound.id == favoriteAmbienceID { score += favoriteNudge }
            if sound.id == lastAmbienceID { score -= repeatPenalty }
            score += CozyRanking.wobble(seed: seed, key: sound.id) * wobbleSize
            return (sound, score)
        }
        let ordered = scored.sorted { $0.score > $1.score || ($0.score == $1.score && $0.sound.id < $1.sound.id) }
        return Array(ordered.prefix(max(0, limit)).map(\.sound))
    }

    static let favoriteNudge = 1.5
    static let repeatPenalty = 100.0
    static let wobbleSize = 1.5
}
