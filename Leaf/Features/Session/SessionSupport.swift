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
/// (previews, or a view shown outside `MainTabs`).
private struct ZoomSourceModifier: ViewModifier {
    let id: String
    @Environment private var namespace: Namespace.ID?

    init(id: String, namespace keyPath: KeyPath<EnvironmentValues, Namespace.ID?>) {
        self.id = id
        _namespace = Environment(keyPath)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace = namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

extension View {
    /// Marks the control the session zooms out of: `ReadingSessionLauncher.heroSource` or `.accessorySource`.
    func sessionZoomSource(_ id: String) -> some View {
        modifier(ZoomSourceModifier(id: id, namespace: \.sessionZoomNamespace))
    }

    /// Marks a cover on Today as the zoom source for that book's detail (`id` is the book id).
    func todayBookZoomSource(_ id: String) -> some View {
        modifier(ZoomSourceModifier(id: id, namespace: \.todayBookZoomNamespace))
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
    /// Returns false when there's nothing to read.
    @discardableResult
    static func start(bookID: String? = nil, store: LibraryStore, router: AppRouter, from source: String) -> Bool {
        if store.activeSession != nil {
            router.presentSession(from: source)
            return true
        }
        let requested = bookID.flatMap { store.item($0) }
        guard let id = requested?.id ?? store.nextBook?.id,
              store.startSession(bookID: id) != nil else { return false }
        router.presentSession(from: source)
        // `sessionStart` lands as the zoom settles.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            Haptics.shared.play(.sessionStart)
        }
        return true
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

/// The numbers a live session shows at one moment: time read, today's goal, and how the timer reads.
struct SessionClock {
    /// Seconds read in this session.
    let elapsed: Double
    /// Seconds already logged today before this session.
    let readBefore: Double
    /// Today's goal in seconds.
    let goal: Double
    let isReadingDay: Bool

    @MainActor
    init(session: ActiveSession, store: LibraryStore, at date: Date) {
        elapsed = session.elapsed(at: date)
        readBefore = store.minutesReadToday * 60
        goal = Double(store.preferences.dailyMinutes) * 60
        isReadingDay = store.isReadingDay
    }

    /// Today plus this session.
    var total: Double { readBefore + elapsed }

    /// The goal was still open when the session began, so the timer counts down to it.
    var tracksGoal: Bool { isReadingDay && goal > 0 && readBefore < goal }

    /// Today's minutes are in (on a reading day).
    var goalSatisfied: Bool { isReadingDay && goal > 0 && total >= goal }

    /// The goal was reached during this session.
    var crossedGoal: Bool { tracksGoal && goalSatisfied }

    var countsDown: Bool { tracksGoal && !goalSatisfied }

    var remaining: Double { max(0, goal - total) }

    /// What the timer face shows: time left to the goal, or time read once it's met (or on a rest day).
    var displaySeconds: Double { countsDown ? remaining.rounded(.up) : elapsed }

    var ringProgress: Double {
        guard goal > 0 else { return 0 }
        return min(1, total / goal)
    }
}
