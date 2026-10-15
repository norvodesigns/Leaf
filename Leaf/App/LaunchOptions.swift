import Foundation

/// Debug-only launch arguments used to stage screens for screenshots and previews, e.g.
/// `-LeafDemo YES -LeafScreen plan`. Release builds always launch normally.
struct LaunchOptions {
    var demo: Bool
    var screen: String?
    var appearance: String?

    static let current: LaunchOptions = {
        #if DEBUG
        let defaults = UserDefaults.standard
        return LaunchOptions(
            demo: defaults.bool(forKey: "LeafDemo"),
            screen: defaults.string(forKey: "LeafScreen"),
            appearance: defaults.string(forKey: "LeafAppearance")
        )
        #else
        return LaunchOptions(demo: false, screen: nil, appearance: nil)
        #endif
    }()

    /// Scripted runs use throwaway storage so they never touch real data.
    var isScripted: Bool { demo || screen != nil }
}
