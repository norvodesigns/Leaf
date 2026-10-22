import Foundation

/// The small cozy choices that live on this device rather than in the synced reading preferences: whether sound cues
/// play, the tea strength the ritual starts at, how loud an ambience starts, and the session's scene
/// (`NookScene.storageKey`, read through `@AppStorage`). Every one is quiet or neutral until
/// the reader changes it (nothing in Leaf makes a sound by surprise).
@MainActor
enum CozySettings {
    private static let defaults = UserDefaults.standard
    private static let soundCuesKey = "leaf.cozy.soundCues"
    private static let strengthKey = "leaf.cozy.teaStrength"
    private static let volumeKey = "leaf.cozy.ambienceVolume"

    /// Kettle, pour and page cues. Off until turned on.
    static var soundCues: Bool {
        get { defaults.bool(forKey: soundCuesKey) }
        set {
            defaults.set(newValue, forKey: soundCuesKey)
            CozySounds.shared.isEnabled = newValue
        }
    }

    /// The strength a tea ritual starts at.
    static var teaStrength: TeaStrength {
        get { defaults.string(forKey: strengthKey).flatMap(TeaStrength.init(rawValue:)) ?? .regular }
        set { defaults.set(newValue.rawValue, forKey: strengthKey) }
    }

    private static let teaPreferencesKey = "leaf.cozy.teaPreferences"

    /// What the reader likes in a tea (kinds, caffeine, flavours, times of day). Kept on this device; suggestions on
    /// Today and in the ritual follow it.
    static var teaPreferences: TeaPreferences {
        get {
            guard let data = defaults.data(forKey: teaPreferencesKey) else { return TeaPreferences() }
            return (try? JSONDecoder().decode(TeaPreferences.self, from: data)) ?? TeaPreferences()
        }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: teaPreferencesKey)
            } else if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: teaPreferencesKey)
            }
        }
    }

    /// The level an ambience starts at, 0 to 1, or nil to use each sound's own.
    static var ambienceVolume: Double? {
        get { defaults.object(forKey: volumeKey) as? Double }
        set { defaults.set(newValue, forKey: volumeKey) }
    }

    /// Hands the saved choices to the players at launch.
    static func apply() {
        CozySounds.shared.isEnabled = soundCues
    }

    /// Back to the quiet defaults, for "Erase all data": no cues, regular tea, the ambience's own volume.
    static func reset() {
        soundCues = false
        defaults.removeObject(forKey: strengthKey)
        defaults.removeObject(forKey: volumeKey)
        defaults.removeObject(forKey: NookScene.storageKey)
    }
}
