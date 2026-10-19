import SwiftUI

// MARK: - Zoom namespaces

private struct SessionZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private struct TodayBookZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The namespace the full-screen session zooms out of. `MainTabs` owns it; Today's hero button
    /// and the session accessory register as sources ("hero" / "accessory", see `router.sessionSource`).
    var sessionZoomNamespace: Namespace.ID? {
        get { self[SessionZoomNamespaceKey.self] }
        set { self[SessionZoomNamespaceKey.self] = newValue }
    }

    /// The namespace Today's covers zoom into book detail from (Today's navigation stack only).
    var todayBookZoomNamespace: Namespace.ID? {
        get { self[TodayBookZoomNamespaceKey.self] }
        set { self[TodayBookZoomNamespaceKey.self] = newValue }
    }
}

/// Registers a view as a zoom source when the namespace has been provided, and does nothing otherwise
/// (previews, or a view shown outside `MainTabs`). Capsule controls clip the zoom to a capsule.
private struct ZoomSourceModifier: ViewModifier {
    let id: String
    let clipsToCapsule: Bool
    @Environment private var namespace: Namespace.ID?

    init(id: String, clipsToCapsule: Bool, namespace keyPath: KeyPath<EnvironmentValues, Namespace.ID?>) {
        self.id = id
        self.clipsToCapsule = clipsToCapsule
        _namespace = Environment(keyPath)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace = namespace {
            if clipsToCapsule {
                content.matchedTransitionSource(id: id, in: namespace) { source in
                    source.clipShape(RoundedRectangle(cornerRadius: 26, style: .circular))
                }
            } else {
                content.matchedTransitionSource(id: id, in: namespace)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Marks the control the session zooms out of: `ReadingSessionLauncher.heroSource` or `.accessorySource`.
    /// Both are capsules, so the zoom is clipped to one.
    func sessionZoomSource(_ id: String) -> some View {
        modifier(ZoomSourceModifier(id: id, clipsToCapsule: true, namespace: \.sessionZoomNamespace))
    }

    /// Marks a cover on Today as the zoom source for that book's detail (`id` is the book id).
    func todayBookZoomSource(_ id: String) -> some View {
        modifier(ZoomSourceModifier(id: id, clipsToCapsule: false, namespace: \.todayBookZoomNamespace))
    }
}

// MARK: - Starting a session

/// One way to begin reading, shared by Today, the accessory and the reminder action.
@MainActor
enum ReadingSessionLauncher {
    static let heroSource = "hero"
    static let accessorySource = "accessory"

    /// Starts a session for `bookID` (or the book the reader is most likely to pick up) and opens the
    /// full-screen timer, zooming from `source`. If a session is already running, it just opens it.
    /// A book that has never been started and has no position yet asks "Where are you?" first, then
    /// starts from the answer. `teaID` and `goalSeconds` carry a tea ritual's cup into the session.
    /// Returns false when there's nothing to read.
    @discardableResult
    static func start(
        bookID: String? = nil,
        store: LibraryStore,
        router: AppRouter,
        from source: String,
        teaID: String? = nil,
        goalSeconds: Double? = nil,
        asksPosition: Bool = true
    ) -> Bool {
        if store.activeSession != nil {
            router.presentSession(from: source)
            return true
        }
        let requested = bookID.flatMap { store.item($0) }
        guard let id = requested?.id ?? store.nextBook?.id else { return false }
        if asksPosition, let item = store.item(id), needsPosition(item, store: store) {
            router.askPosition(for: id, then: .startSession(source: source, teaID: teaID, goalSeconds: goalSeconds))
            return true
        }
        guard store.startSession(bookID: id, teaID: teaID, goalSeconds: goalSeconds) != nil else { return false }
        router.presentSession(from: source)
        // `sessionStart` lands as the zoom settles.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            Haptics.shared.play(.sessionStart)
        }
        return true
    }

    /// "Steep and read": opens the session screen at the tea for `bookID` (or the next book). The steep comes before
    /// the session, so no reading time is counted until the cup is poured. Asks "Where are you?" first for a book
    /// that needs it. With a session already running, it just opens it.
    @discardableResult
    static func beginRitual(bookID: String?, teaID: String?, store: LibraryStore, router: AppRouter, from source: String, asksPosition: Bool = true) -> Bool {
        if store.activeSession != nil {
            router.presentSession(from: source)
            return true
        }
        let requested = bookID.flatMap { store.item($0) }
        guard let id = requested?.id ?? store.nextBook?.id else { return false }
        if asksPosition, let item = store.item(id), needsPosition(item, store: store) {
            router.askPosition(for: id, then: .ritual(source: source, teaID: teaID))
            return true
        }
        router.ritual = RitualRequest(bookID: id, teaID: teaID)
        router.presentSession(from: source)
        return true
    }

    /// A book that has never been read here and hasn't been told where the reader is: starting it should ask first.
    static func needsPosition(_ item: LibraryItem, store: LibraryStore) -> Bool {
        !item.positionConfirmed && item.shelf != .finished && store.sessionCount(for: item.id) == 0
    }

    /// "Start reading" on a reminder: clear anything on screen, then start on Today.
    static func startFromReminder(bookID: String?, store: LibraryStore, router: AppRouter) {
        let wasPresenting = router.showSettings || router.showSpeedTest || router.lastOutcome != nil
        router.showSpeedTest = false
        router.showSettings = false
        router.lastOutcome = nil
        router.popToRoot()
        router.tab = .today
        Task { @MainActor in
            // Let a sheet finish leaving before the session cover goes up.
            if wasPresenting { try? await Task.sleep(for: .milliseconds(500)) }
            start(bookID: bookID, store: store, router: router, from: heroSource)
        }
    }

    /// Closes the full-screen session (and any sheet in the way), then shows the wrap-up sheet once the
    /// cover has gone, because SwiftUI can't present a sheet while a cover is still leaving.
    static func present(_ outcome: SessionOutcome, router: AppRouter) {
        let wasPresenting = router.showSession || router.showSettings || router.showSpeedTest
        router.showSession = false
        router.showSettings = false
        router.showSpeedTest = false
        Task { @MainActor in
            if wasPresenting { try? await Task.sleep(for: .milliseconds(700)) }
            router.lastOutcome = outcome
        }
    }

    /// Leaf's guess at the page reached: elapsed time × pace ÷ words per page, from the session's start page.
    static func estimatedPage(for session: ActiveSession, book: Book, wpm: Double, at date: Date = Date()) -> Int {
        let minutes = session.elapsed(at: date) / 60
        let pages = minutes * max(wpm, 1) / max(book.wordsPerPage, 1)
        let start = min(max(0, session.startPage), book.pages)
        guard pages.isFinite else { return start }
        return min(max(start + Int(pages.rounded()), start), book.pages)
    }

    /// The pages a session can end on: its start page through the end of the book.
    static func pageRange(for session: ActiveSession, book: Book) -> ClosedRange<Int> {
        let upper = max(1, book.pages)
        let lower = min(max(0, session.startPage), upper)
        return lower...upper
    }
}

// MARK: - Session clock

/// The numbers a live session shows at one moment: time read, today's goal, and how the timer reads. A tea
/// ritual's session counts down its cup instead of today's goal; today's goal still decides "goal met".
struct SessionClock {
    /// Seconds read in this session.
    let elapsed: Double
    /// Seconds already logged today before this session.
    let readBefore: Double
    /// Today's goal in seconds.
    let goal: Double
    let isReadingDay: Bool
    /// The cup-length read of a tea ritual, in seconds, or nil.
    let cup: Double?

    init(elapsed: Double, readBefore: Double, goal: Double, isReadingDay: Bool, cup: Double? = nil) {
        self.elapsed = max(0, elapsed)
        self.readBefore = max(0, readBefore)
        self.goal = max(0, goal)
        self.isReadingDay = isReadingDay
        self.cup = cup.flatMap { $0 > 0 ? $0 : nil }
    }

    @MainActor
    init(session: ActiveSession, store: LibraryStore, at date: Date) {
        self.init(
            elapsed: session.elapsed(at: date),
            readBefore: store.minutesReadToday * 60,
            goal: Double(store.preferences.dailyMinutes) * 60,
            isReadingDay: store.isReadingDay,
            cup: session.goalSeconds
        )
    }

    var hasGoal: Bool { goal > 0 }

    var hasCup: Bool { cup != nil }

    /// The cup is drunk: the ritual's read is done.
    var cupDone: Bool {
        guard let cup else { return false }
        return elapsed >= cup
    }

    /// Today plus this session.
    var total: Double { readBefore + elapsed }

    /// The goal was still open when the session began, on a reading day: the timer counts down to it.
    var tracksGoal: Bool { isReadingDay && hasGoal && readBefore < goal }

    /// Today's minutes are in.
    var goalMet: Bool { hasGoal && total >= goal }

    /// The goal was reached during this session (the moment for `goalReached`).
    var crossedGoal: Bool { hasGoal && readBefore < goal && total >= goal }

    var countsDown: Bool {
        if hasCup { return !cupDone }
        return tracksGoal && !goalMet
    }

    var remaining: Double {
        if let cup { return max(0, cup - elapsed) }
        return max(0, goal - total)
    }

    /// What the timer face shows: time left in the cup or to the goal, or time read in this session once that's
    /// done (or on a rest day).
    var displaySeconds: Double { countsDown ? remaining.rounded(.up) : elapsed }

    var ringProgress: Double {
        if let cup { return min(1, elapsed / cup) }
        guard hasGoal else { return 0 }
        return min(1, total / goal)
    }
}
