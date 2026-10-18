import Foundation

/// The procedural ambience recipes. The raw values are the ids stored in `ReadingPreferences.ambienceID` and
/// `ReadingSession.ambienceID` and listed in `AmbienceCatalog`, so they must never change. (The catalog says what a
/// sound is called and when it suits; this says how it is made.)
enum AmbienceRecipe: String, CaseIterable, Sendable {
    case rain
    case fireplace
    case kettle
    case cafe
    case library

    /// The recipe for a stored ambience id. Nil for silence ("none"), for nil, and for anything unrecognised.
    init?(id: String?) {
        guard let id, let recipe = AmbienceRecipe(rawValue: id) else { return nil }
        self = recipe
    }

    /// How loud the recipe is at full volume, as RMS in dBFS. Beds sit well below the -3 dBFS ceiling so crackles,
    /// pops and clinks have room to stand out; the library is meant to be almost not there.
    var targetLevel: Double {
        switch self {
        case .rain: return -18
        case .fireplace: return -19
        case .kettle: return -21
        case .cafe: return -20
        case .library: return -32
        }
    }

    /// `targetLevel` as a linear RMS.
    var targetRMS: Float { Float(pow(10, targetLevel / 20)) }

    /// Gain that takes the voice's raw mix to `targetRMS` (measured over many seeds at 44.1 kHz; the tests hold it
    /// to within 1.5 dB).
    var rawToTarget: Float {
        switch self {
        case .rain: return 0.1957
        case .fireplace: return 0.1143
        case .kettle: return 0.1642
        case .cafe: return 0.1987
        case .library: return 0.0271
        }
    }

    func makeVoice(sampleRate: Double, seed: UInt64) -> any AmbienceVoice {
        switch self {
        case .rain: return AmbienceRainVoice(sampleRate: sampleRate, seed: seed)
        case .fireplace: return AmbienceFireVoice(sampleRate: sampleRate, seed: seed)
        case .kettle: return AmbienceKettleVoice(sampleRate: sampleRate, seed: seed)
        case .cafe: return AmbienceCafeVoice(sampleRate: sampleRate, seed: seed)
        case .library: return AmbienceLibraryVoice(sampleRate: sampleRate, seed: seed)
        }
    }
}
