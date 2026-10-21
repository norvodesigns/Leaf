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
        guard let store else { return false }
        if let session = store.activeSession, let item = store.item(session.bookID) {
            let from = max(item.currentPage, session.startPage)
            store.setPage(item.id, page: min(item.book.pages, from + max(1, pages)))
            LiveActivityController.shared.sync()
            return true
        }
        // No session (the Control Center control): the book Today suggests, as if the reader moved its bookmark.
        guard let item = store.nextBook, item.shelf == .reading, item.currentPage < item.book.pages else { return false }
        store.setPage(item.id, page: min(item.book.pages, item.currentPage + max(1, pages)))
        return true
    }

    func startSteep() -> Bool {
        guard let store, let router else { return false }
        if store.activeSession != nil { return startReading() }
        guard let item = store.nextBook else { return false }
        let pot = TeaSteepState.load()
        // A pot already on the stove for this book is the one to come back to; otherwise pour the book's tea now,
        // unless Leaf first has to ask where the reader is (the ritual then opens with "Pour and steep").
        if pot?.bookID != item.id, !ReadingSessionLauncher.needsPosition(item, store: store) {
            let tea = Self.tea(for: item, store: store)
            let strength = CozySettings.teaStrength
            let ritual = TeaRitual.plan(tea: tea, strength: strength, cupMinutes: store.preferences.cupMinutes)
            let isOwn = store.data.cabinet.contains { $0.teaID == tea.id }
            TeaSteepState.save(TeaSteepState(teaID: tea.id, steepSeconds: ritual.steepSeconds, startedAt: Date(), bookID: item.id, strength: strength, ownTea: isOwn ? tea : nil))
            CozySounds.shared.teaBrewStarted()
        }
        router.showSettings = false
        router.lastOutcome = nil
        router.teaPage = nil
        router.popToRoot()
        router.tab = .today
        return ReadingSessionLauncher.beginRitual(bookID: item.id, teaID: nil, store: store, router: router, from: ReadingSessionLauncher.heroSource)
    }

    /// The tea the ritual would open on for this book: its pairing among the teas on offer for the hour.
    private static func tea(for item: LibraryItem, store: LibraryStore) -> Tea {
        let offer = store.teaChoices(limit: 8, for: item.id)
        return TeaShelf.preferred(for: item.book, pinnedTeaID: item.pairedTeaID, choices: offer.teas) ?? offer.teas.first ?? TeaCatalog.earlGrey
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
