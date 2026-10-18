import Foundation

enum TeaFamily: String, Codable, CaseIterable, Sendable {
    case black, green, white, oolong, herbal, rooibos, chai, matcha

    var title: String {
        switch self {
        case .black: return "Black"
        case .green: return "Green"
        case .white: return "White"
        case .oolong: return "Oolong"
        case .herbal: return "Herbal"
        case .rooibos: return "Rooibos"
        case .chai: return "Chai"
        case .matcha: return "Matcha"
        }
    }
}

/// How much caffeine a cup carries, in the four steps a reader actually thinks in.
enum TeaCaffeine: String, Codable, CaseIterable, Comparable, Sendable {
    case none, low, medium, high

    var rank: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    static func < (lhs: TeaCaffeine, rhs: TeaCaffeine) -> Bool { lhs.rank < rhs.rank }

    var title: String {
        switch self {
        case .none: return "Caffeine free"
        case .low: return "A little caffeine"
        case .medium: return "Some caffeine"
        case .high: return "Plenty of caffeine"
        }
    }
}

/// What a tea is good for. The suggester matches these against the weather.
enum TeaMood: String, Codable, CaseIterable, Sendable {
    case calm, cozy, focus, uplifting, warming, refreshing, rainyDay, windDown, wakeUp

    var title: String {
        switch self {
        case .calm: return "Calm"
        case .cozy: return "Cozy"
        case .focus: return "Focus"
        case .uplifting: return "Uplifting"
        case .warming: return "Warming"
        case .refreshing: return "Refreshing"
        case .rainyDay: return "Rainy day"
        case .windDown: return "Wind down"
        case .wakeUp: return "Wake up"
        }
    }
}

/// How strong the reader likes it. This only moves the steep time; the leaves stay the same.
enum TeaStrength: String, Codable, CaseIterable, Sendable {
    case light, regular, strong

    var title: String {
        switch self {
        case .light: return "Light"
        case .regular: return "Regular"
        case .strong: return "Strong"
        }
    }

    /// Light is a shorter steep, strong a longer one. Never so far that the cup turns bitter.
    var multiplier: Double {
        switch self {
        case .light: return 0.75
        case .regular: return 1
        case .strong: return 1.25
        }
    }
}

/// One tea, as plain data. There is no colour or drawing here: `paletteToken` is a word from `CozyPalette` that the
/// UI maps to a colour later.
struct Tea: Codable, Hashable, Identifiable, Sendable {
    /// Stable and kebab-case. Saved on sessions as `teaID`, so it must never be renamed.
    var id: String
    var name: String
    var family: TeaFamily
    /// Steep time for a regular cup. Matcha is whisked rather than steeped, so its number is the whisking time.
    var steepSeconds: Int
    var celsius: Int
    var fahrenheit: Int
    var caffeine: TeaCaffeine
    /// A few tasting words, the way the back of a tin would say it.
    var notes: [String]
    /// One line in the app's warm voice.
    var blurb: String
    var seasons: [Season]
    var dayparts: [Daypart]
    var moods: [TeaMood]
    /// A word from `CozyPalette`.
    var paletteToken: String
}
