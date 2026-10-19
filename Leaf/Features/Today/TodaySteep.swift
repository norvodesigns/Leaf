import Foundation

/// A pot steeping on Today: which tea, for which book, and when the kettle was poured. The steep happens before the
/// reading session, never inside it (`TeaRitual`), so the session's seconds stay reading seconds.
///
/// Kept in `UserDefaults` so it survives a trip to another tab or app. Half an hour after it's ready the tea has
/// gone cold and the pot is quietly cleared; nothing nags.
struct TeaSteepState: Codable, Equatable {
    var teaID: String
    var steepSeconds: Int
    var startedAt: Date
    var bookID: String?

    var readyAt: Date { startedAt.addingTimeInterval(Double(steepSeconds)) }

    func isReady(at date: Date) -> Bool { date >= readyAt }

    func isCold(at date: Date) -> Bool { date.timeIntervalSince(readyAt) > 30 * 60 }

    var tea: Tea { TeaCatalog.tea(id: teaID) ?? TeaCatalog.earlGrey }

    private static let key = "leaf.today.steep"

    /// The pot in progress, unless it has gone cold.
    static func load(now: Date = Date()) -> TeaSteepState? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(TeaSteepState.self, from: data),
              !state.isCold(at: now) else { return nil }
        return state
    }

    static func save(_ state: TeaSteepState?) {
        guard let state, let data = try? JSONEncoder().encode(state) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// How a steep time reads on a chip: "4 min", "2½ min", "3:15".
enum SteepText {
    static func duration(seconds: Int) -> String {
        let minutes = seconds / 60
        let rest = seconds % 60
        if rest == 0 { return "\(minutes) min" }
        if rest == 30 { return minutes == 0 ? "½ min" : "\(minutes)½ min" }
        return LeafFormat.clock(seconds: Double(seconds))
    }

    /// "4 minutes", for VoiceOver.
    static func spoken(seconds: Int) -> String {
        let minutes = seconds / 60
        let rest = seconds % 60
        let minuteText = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if rest == 0 { return minuteText }
        if minutes == 0 { return "\(rest) seconds" }
        return "\(minuteText) \(rest) seconds"
    }
}
