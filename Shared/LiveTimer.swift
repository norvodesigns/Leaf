import Foundation

// MARK: - A live timer

/// A timer running right now that the watch face and the Smart Stack should show: a reading session (counting down
/// to its goal, then up) or a pot steeping (counting down to ready). Everything a card needs to draw itself with
/// `Text(timerInterval:)` and no further updates: the start, the pause, the goal, and when it stops mattering.
struct LiveTimer: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case reading
        case steep
    }

    /// The device the reader started it on.
    enum Origin: String, Codable, Sendable {
        case phone
        case watch
    }

    enum State: String, Codable, Sendable {
        case running
        case paused
        /// The goal is met, or the tea is ready.
        case reached
    }

    /// One stretch of the timer's life, from `from` until the next phase: what it shows and how much the Smart
    /// Stack should want it.
    struct Phase: Codable, Hashable, Sendable {
        var from: Date
        var state: State
        /// 0 to 1, for `TimelineEntryRelevance`.
        var relevance: Double
    }

    var kind: Kind
    var origin: Origin
    /// The session it belongs to (reading), so a card can tell whether a mirrored Live Activity already shows it.
    var sessionID: UUID?
    /// Reading: the session's start moved forward by every pause so far, so `Text(timerInterval:)` counts reading
    /// time only. Steep: when the water went on.
    var start: Date
    /// Reading seconds at the moment of the pause, while paused; nil while running.
    var pausedElapsed: Double?
    /// Reading: the session's goal (a cup, or what is left of today). Steep: how long it steeps.
    var goalSeconds: Double?
    var title: String?
    var teaName: String?

    /// A pot left steeping goes cold half an hour after it is ready; a reading timer nobody stopped stops mattering
    /// after this long.
    static let teaGoesCold: TimeInterval = 30 * 60
    static let forgottenReading: TimeInterval = 8 * 3600

    var isPaused: Bool { pausedElapsed != nil }

    private var goal: TimeInterval? {
        guard let goalSeconds, goalSeconds.isFinite, goalSeconds > 0 else { return nil }
        return goalSeconds
    }

    /// When the countdown reaches zero (the goal is met, the tea is ready) if nothing changes; nil while paused or
    /// with no goal.
    var goalDate: Date? {
        guard !isPaused, let goal else { return nil }
        return start.addingTimeInterval(goal)
    }

    /// After this the timer is gone from the face: a steep once the tea has gone cold, a reading session once it
    /// has clearly been forgotten. A paused session counts its pause against the same limit.
    var expiresAt: Date {
        switch kind {
        case .steep:
            return start.addingTimeInterval((goal ?? 0) + LiveTimer.teaGoesCold)
        case .reading:
            return start.addingTimeInterval(LiveTimer.forgottenReading)
        }
    }

    func isExpired(at date: Date) -> Bool { date >= expiresAt }

    /// What the timer shows at `date`.
    func state(at date: Date) -> State {
        if isPaused { return .paused }
        if let goalDate, date >= goalDate { return .reached }
        return .running
    }

    /// Seconds of reading (or steeping) so far at `date`.
    func elapsed(at date: Date) -> TimeInterval {
        if let pausedElapsed { return max(0, pausedElapsed) }
        return max(0, date.timeIntervalSince(start))
    }

    /// The timer's stretches from `now` with no further updates: running, then reached at the goal, until it
    /// expires. Empty once expired. Running is the most relevant; a paused session less; a ready pot stays high for a
    /// few minutes (it's waiting for the reader), a met goal falls back once its moment has passed.
    func phases(from now: Date) -> [Phase] {
        guard !isExpired(at: now) else { return [] }
        var phases: [Phase] = []
        let current = state(at: now)
        phases.append(Phase(from: now, state: current, relevance: LiveTimer.relevance(current, kind: kind)))
        if current == .running, let goalDate, goalDate < expiresAt {
            phases.append(Phase(from: goalDate, state: .reached, relevance: LiveTimer.relevance(.reached, kind: kind)))
            let settle = goalDate.addingTimeInterval(5 * 60)
            if settle < expiresAt {
                phases.append(Phase(from: settle, state: .reached, relevance: kind == .steep ? 0.8 : 0.5))
            }
        }
        return phases
    }

    static func relevance(_ state: State, kind: Kind) -> Double {
        switch state {
        case .running: return 1
        case .paused: return 0.6
        case .reached: return kind == .steep ? 1 : 0.8
        }
    }
}

// MARK: - Which card shows it

/// One timer, one card. A Live Activity started on the iPhone is mirrored to the watch's Smart Stack by the system, so
/// whenever the phone has one for this session, that is the card, and the watch's own Timer widget stays out of the
/// way. Otherwise (Live Activities are off on the phone, or the watch started the session while the phone couldn't
/// start one) the watch's Timer widget is the card.
enum LiveTimerRules {
    /// Whether the watch's Timer widget should show `timer`, given the Live Activity the phone says it is running
    /// (`phoneActivitySessionID`, nil for none).
    static func watchShowsCard(for timer: LiveTimer, phoneActivitySessionID: UUID?) -> Bool {
        switch timer.kind {
        case .steep:
            // A steep on the watch is the watch's own; one on the phone is in the phone's Live Activity.
            return timer.origin == .watch
        case .reading:
            guard let phoneActivitySessionID, let sessionID = timer.sessionID else { return true }
            return phoneActivitySessionID != sessionID
        }
    }
}
