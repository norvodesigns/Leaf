import Foundation

/// Weather as the cozy features understand it. It is optional everywhere: Leaf works with no location or weather
/// permission, so every suggester is good without it and only leans on it when the app happens to know.
enum CozyWeather: String, Codable, CaseIterable, Sendable {
    case clear, cloudy, fog, rain, snow
    /// Dry but chilly.
    case cold
    case hot
}

/// The names of the colours the UI gives teas, ambiences and stamps. The data layer only ever stores these words, so
/// the design pass can change what "chai" looks like without touching a single catalog entry.
enum CozyPalette {
    /// Tea-stained paper.
    static let paper = "paper"
    static let chai = "chai"
    static let matcha = "matcha"
    static let rooibos = "rooibos"
    /// Steam-white.
    static let steam = "steam"
    /// Lamp amber.
    static let amber = "amber"
    /// Hibiscus and rose petals.
    static let rose = "rose"

    static let all: [String] = [paper, chai, matcha, rooibos, steam, amber, rose]

    static func isKnown(_ token: String) -> Bool { all.contains(token) }

    /// A token for a season, used where something has no colour of its own (a month stamp, say).
    static func token(for season: Season) -> String {
        switch season {
        case .spring: return matcha
        case .summer: return amber
        case .autumn: return rooibos
        case .winter: return steam
        }
    }
}

/// Shared by the tea and ambience suggesters.
enum CozyRanking {
    /// A steady number from 0 up to (not including) 1 for one seed and one key. It depends on nothing else, so adding
    /// or reordering catalog entries never reshuffles the wobble of the entries that were already there.
    static func wobble(seed: UInt64, key: String) -> Double {
        var generator = SeededGenerator(seed: SeededGenerator.hash("\(seed)|\(key)"))
        return generator.unit()
    }
}
