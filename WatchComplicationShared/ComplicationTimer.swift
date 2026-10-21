import Foundation

/// A timer running on the wrist, as the Timer widget draws it: reading (to its goal, then up) or a pot steeping (to
/// ready). The watch app works it out from the session with `LiveTimer` (Shared/LiveTimer.swift), which decides
/// whether the watch shows a card at all (never beside the phone's mirrored Live Activity) and when it stops
/// mattering, and leaves only plain data here: the widget extension draws, it doesn't decide.
struct ComplicationTimer: Codable, Hashable, Sendable {
    /// One stretch of the timer's life: from when, showing what, and how much the Smart Stack should want it.
    struct Phase: Codable, Hashable, Sendable {
        var from: Date
        /// "running", "paused" or "reached".
        var state: String
        var relevance: Double
    }

    var isSteep: Bool
    /// Reading: the start moved forward by every pause. Steep: when the water went on.
    var start: Date
    /// Seconds elapsed at the pause, while paused.
    var pausedElapsed: Double?
    var goalSeconds: Double?
    var title: String?
    var teaName: String?
    var phases: [Phase]
    /// After this it is gone from the face (cold tea, a forgotten session).
    var expiresAt: Date

    /// The longest a timer view is asked to cover, so `Text(timerInterval:)` never reserves a huge width.
    static let longest: TimeInterval = 12 * 3600

    var hasGoal: Bool { (goalSeconds ?? 0) > 0 }

    /// The interval for `Text(timerInterval:)`: down to the goal while `countsDown`, otherwise up from the start.
    func range(countsDown: Bool) -> ClosedRange<Date> {
        if countsDown, let goalSeconds, goalSeconds > 0 { return start...start.addingTimeInterval(min(goalSeconds, Self.longest)) }
        return start...start.addingTimeInterval(Self.longest)
    }

    /// Where to freeze the digits while paused, inside `range(countsDown:)`.
    func pauseDate(countsDown: Bool) -> Date? {
        guard let pausedElapsed else { return nil }
        let span = range(countsDown: countsDown)
        let offset = min(max(pausedElapsed, 0), span.upperBound.timeIntervalSince(span.lowerBound))
        return span.lowerBound.addingTimeInterval(offset)
    }
}
