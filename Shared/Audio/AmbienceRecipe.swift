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

    /// The generations of the recipes. `.original` is the first TestFlight's fireplace, kettle, cafe and library,
    /// kept only so the Sound lab and the audio previews can play them beside `.current`. Rain is the same in both.
    enum Version: String, CaseIterable, Sendable {
        case original
        case current
    }

    /// The recipe for a stored ambience id. Nil for silence ("none"), for nil, and for anything unrecognised.
    init?(id: String?) {
        guard let id, let recipe = AmbienceRecipe(rawValue: id) else { return nil }
        self = recipe
    }

    /// How loud the current recipe is at full volume, in LUFS as `AudioMeasure.loudness` reads it (K-weighted and
    /// ungated, over a long stretch). Every sound sits at the same loudness, so switching between them at one volume
    /// keeps the room the same; the library is a hush by design, eight below. The kettle is measured once it has
    /// come up to the simmer.
    var targetLoudness: Double {
        switch self {
        case .rain, .fireplace, .kettle, .cafe: return AmbienceRecipe.sharedLoudness
        case .library: return AmbienceRecipe.sharedLoudness - 8
        }
    }

    static let sharedLoudness = -17.0

    /// Gain that takes a voice's raw mix to its target loudness (measured over several seeds at 44.1 kHz; the tests
    /// hold it to within 1.5 LU).
    func rawToTarget(_ version: Version = .current) -> Float {
        switch (self, version) {
        case (.rain, .original): return 0.1957
        case (.rain, .current): return 0.1294
        case (.fireplace, .original): return 0.1143
        case (.fireplace, .current): return 0.741
        case (.kettle, .original): return 0.1642
        case (.kettle, .current): return 0.537
        case (.cafe, .original): return 0.1987
        case (.cafe, .current): return 9.0
        case (.library, .original): return 0.0271
        case (.library, .current): return 1.047
        }
    }

    func makeVoice(sampleRate: Double, seed: UInt64, version: Version = .current) -> any AmbienceVoice {
        switch (self, version) {
        case (.rain, _): return AmbienceRainVoice(sampleRate: sampleRate, seed: seed)
        case (.fireplace, .original): return AmbienceFireVoiceOriginal(sampleRate: sampleRate, seed: seed)
        case (.fireplace, .current): return AmbienceFireVoice(sampleRate: sampleRate, seed: seed)
        case (.kettle, .original): return AmbienceKettleVoiceOriginal(sampleRate: sampleRate, seed: seed)
        case (.kettle, .current): return AmbienceKettleVoice(sampleRate: sampleRate, seed: seed)
        case (.cafe, .original): return AmbienceCafeVoiceOriginal(sampleRate: sampleRate, seed: seed)
        case (.cafe, .current): return AmbienceCafeVoice(sampleRate: sampleRate, seed: seed)
        case (.library, .original): return AmbienceLibraryVoiceOriginal(sampleRate: sampleRate, seed: seed)
        case (.library, .current): return AmbienceLibraryVoice(sampleRate: sampleRate, seed: seed)
        }
    }
}
