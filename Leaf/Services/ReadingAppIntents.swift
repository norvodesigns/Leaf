import AppIntents
import Foundation

// Siri, Shortcuts, the Action button and Focus (NEXT.md section 16). The Live Activity's own buttons (pause, resume,
// log pages) live in `LiveActivityShared/ReadingIntents.swift` because the extension has to see them; they all land
// here, in the app, through `ReadingIntentBridge`.

/// The app's side of the reading intents: the session the store holds is the one they act on.
@MainActor
final class AppReadingIntents: ReadingIntentHandling {
    static let shared = AppReadingIntents()

    private weak var store: LibraryStore?
    private weak var router: AppRouter?

    private init() {}

    func connect(store: LibraryStore, router: AppRouter) {
        self.store = store
        self.router = router
        ReadingIntentBridge.handler = self
    }

    func startReading() -> Bool {
        guard let store, let router else { return false }
        guard store.activeSession != nil || store.nextBook != nil else { return false }
        // The same path as a reminder's "Start reading": clear anything on screen, then begin on Today.
        ReadingSessionLauncher.startFromReminder(bookID: nil, store: store, router: router)
        return true
    }

    func pauseReading() -> Bool {
        guard let store, let session = store.activeSession, !session.isPaused else { return false }
        store.pauseSession()
        return true
    }

    func resumeReading() -> Bool {
        guard let store, let session = store.activeSession, session.isPaused else { return false }
        store.resumeSession()
        return true
    }

    func logPages(_ pages: Int) -> Bool {
        guard let store, let session = store.activeSession, let item = store.item(session.bookID) else { return false }
        let from = max(item.currentPage, session.startPage)
        store.setPage(item.id, page: min(item.book.pages, from + max(1, pages)))
        LiveActivityController.shared.sync()
        return true
    }
}

/// "Start reading in Leaf": opens the app on Today and begins (or returns to) the session, tea and all.
struct StartReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start reading"
    static var description: IntentDescription? = IntentDescription("Opens Leaf and starts today’s reading.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = ReadingIntentBridge.handler?.startReading()
        return .result()
    }
}

/// Natural phrases for Siri and Spotlight. Every phrase names the app, as App Shortcuts require.
struct LeafShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartReadingIntent(),
            phrases: [
                "Start reading in \(.applicationName)",
                "Read with \(.applicationName)",
                "Open my book in \(.applicationName)",
                "Time to read in \(.applicationName)",
            ],
            shortTitle: "Start reading",
            systemImageName: "book"
        )
        AppShortcut(
            intent: PauseReadingIntent(),
            phrases: [
                "Pause reading in \(.applicationName)",
                "Pause my book in \(.applicationName)",
            ],
            shortTitle: "Pause reading",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeReadingIntent(),
            phrases: [
                "Resume reading in \(.applicationName)",
                "Carry on reading in \(.applicationName)",
            ],
            shortTitle: "Resume reading",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: LogPagesIntent(),
            phrases: [
                "Log pages in \(.applicationName)",
                "Move my bookmark in \(.applicationName)",
            ],
            shortTitle: "Log pages",
            systemImageName: "bookmark"
        )
    }
}

// MARK: - Focus

/// Whether a Reading Focus has asked Leaf to keep its reminders to itself.
enum ReadingFocus {
    private static let key = "leaf.focus.holdsReminders"

    static var holdsReminders: Bool { UserDefaults.standard.bool(forKey: key) }

    static func set(holdsReminders: Bool) {
        UserDefaults.standard.set(holdsReminders, forKey: key)
    }
}

/// A Focus filter for a "Reading" Focus (Settings > Focus > Add Filter > Leaf): while it's on, Leaf holds its own
/// reminders, so nothing taps you to read while you already are. When the Focus ends, the system sends the filter
/// back with its parameter unset, which turns the hold off.
struct ReadingFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Reading"
    static var description: IntentDescription? = IntentDescription("Hold Leaf’s reminders while this Focus is on.")

    @Parameter(title: "Hold Leaf’s reminders")
    var holdsReminders: Bool?

    init() {}

    var displayRepresentation: DisplayRepresentation {
        let state = (holdsReminders ?? false) ? "Leaf’s reminders are held" : "Reminders as usual"
        return DisplayRepresentation(title: "Reading", subtitle: "\(state)")
    }

    func perform() async throws -> some IntentResult {
        ReadingFocus.set(holdsReminders: holdsReminders ?? false)
        // Drop or restore today's pending reminders to match.
        await MainActor.run { Reminders.shared.scheduleRefresh() }
        return .result()
    }
}
