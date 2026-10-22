import Foundation

/// Debug-only launch arguments used to stage screens for screenshots and previews, e.g.
/// `-LeafDemo YES -LeafScreen plan`. Release builds always launch normally.
///
/// - `-LeafScenario goalmet` picks a variant of the demo library (`DemoData.Scenario`).
/// - `-LeafTime 07:40` makes "now" that time today, so Today can be staged at any hour.
/// - `-LeafScroll week` scrolls Today to one of its cards after it appears.
/// - `-LeafPublicDomain YES` swaps the demo books for public-domain ones (App Store screenshots).
struct LaunchOptions {
    var demo: Bool
    var screen: String?
    var appearance: String?
    var scenario: String?
    var time: String?
    var scroll: String?
    var publicDomain = false

    static let current: LaunchOptions = {
        #if DEBUG
        let defaults = UserDefaults.standard
        return LaunchOptions(
            demo: defaults.bool(forKey: "LeafDemo"),
            screen: defaults.string(forKey: "LeafScreen"),
            appearance: defaults.string(forKey: "LeafAppearance"),
            scenario: defaults.string(forKey: "LeafScenario"),
            time: defaults.string(forKey: "LeafTime"),
            scroll: defaults.string(forKey: "LeafScroll"),
            publicDomain: defaults.bool(forKey: "LeafPublicDomain")
        )
        #else
        return LaunchOptions(demo: false, screen: nil, appearance: nil, scenario: nil, time: nil, scroll: nil)
        #endif
    }()

    /// Scripted runs use throwaway storage so they never touch real data.
    var isScripted: Bool { demo || screen != nil }

    /// The moment the app treats as now: the real time, or today at `-LeafTime HH:MM` for staged screenshots.
    func now(calendar: Calendar = .current) -> Date {
        let real = Date()
        guard let time else { return real }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return real }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: real) ?? real
    }
}
