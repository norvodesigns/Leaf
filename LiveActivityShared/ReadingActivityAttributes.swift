import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// This folder is compiled into the Leaf app and the LeafWidgets extension, and into nothing else, so it can only use
// Foundation and the system frameworks both targets can see. It cannot reach anything in Shared/.

/// What the reading Live Activity is showing right now. The view picks its wording and emphasis from this.
enum ReadingActivityState: String, Codable, Hashable, Sendable {
    case reading
    case paused
    /// The goal length has passed. The timer keeps counting up instead of sitting at zero.
    case goalReached
    /// The reader is wrapping up the book or the session. The activity is about to end.
    case finishing
}

/// The part of a reading Live Activity that changes. ActivityKit caps attributes plus state at about 4 KB, so this stays
/// small: numbers and a date, never text or images.
///
/// The timer fields work together. `timerStart` is the real start moved forward by every pause so far, which means
/// `Text(timerInterval:)` shows reading time only and keeps counting by itself between updates. While paused,
/// `pausedElapsedSeconds` is how much of that time had passed, so the view can freeze the digits with `pauseDate`.
struct ReadingActivityContent: Codable, Hashable, Sendable {
    /// Session start plus all time spent paused so far.
    var timerStart: Date
    var isPaused: Bool
    /// Reading seconds elapsed at the moment of the last pause. Only meaningful while `isPaused`.
    var pausedElapsedSeconds: Int
    /// Length of this session in seconds, or nil for an open-ended one.
    var goalSeconds: Int?
    var currentPage: Int
    var state: ReadingActivityState

    init(
        timerStart: Date,
        isPaused: Bool = false,
        pausedElapsedSeconds: Int = 0,
        goalSeconds: Int? = nil,
        currentPage: Int,
        state: ReadingActivityState = .reading
    ) {
        self.timerStart = timerStart
        self.isPaused = isPaused
        self.pausedElapsedSeconds = pausedElapsedSeconds
        self.goalSeconds = goalSeconds
        self.currentPage = currentPage
        self.state = state
    }
}

extension ReadingActivityContent {
    /// The longest span a timer view is asked to cover: a Live Activity runs for at most 8 hours and can linger on the
    /// Lock Screen for another 4. A bounded range also keeps `Text(timerInterval:)` from reserving a huge width.
    static let longestTimerSeconds: TimeInterval = 12 * 3600

    /// The goal as a positive length, or nil when the session is open-ended (or the goal makes no sense).
    private var goalLength: TimeInterval? {
        guard let goalSeconds, goalSeconds > 0 else { return nil }
        return min(TimeInterval(goalSeconds), Self.longestTimerSeconds)
    }

    /// True while the digits should count down to the goal. Once the goal is reached they count up instead.
    var countsDown: Bool {
        guard goalLength != nil else { return false }
        return state == .reading || state == .paused
    }

    /// The interval to hand to `Text(timerInterval:pauseTime:countsDown:showsHours:)`. Always a valid range, because
    /// SwiftUI traps on one that ends before it starts.
    var timerRange: ClosedRange<Date> {
        let length = countsDown ? (goalLength ?? Self.longestTimerSeconds) : Self.longestTimerSeconds
        return timerStart...timerStart.addingTimeInterval(length)
    }

    /// The date to freeze the timer at, or nil while it runs. Always inside `timerRange`.
    var pauseDate: Date? {
        guard isPaused else { return nil }
        let range = timerRange
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        let offset = min(max(TimeInterval(pausedElapsedSeconds), 0), span)
        return range.lowerBound.addingTimeInterval(offset)
    }
}

#if canImport(ActivityKit)
/// The fixed facts about one reading Live Activity. They are set when the activity starts and never change, so a new
/// book means a new activity.
struct ReadingActivityAttributes: ActivityAttributes {
    typealias ContentState = ReadingActivityContent

    var bookID: String
    var title: String
    var author: String
    var totalPages: Int
    /// Name of the pre-rendered cover file in the App Group container, or nil when the book has no cover. The image
    /// stays out of the attributes because of the size limit.
    var coverFileName: String?
}
#endif
