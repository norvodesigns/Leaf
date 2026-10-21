import AppIntents
import Foundation

// The intents the Live Activity's buttons run. This folder is compiled into the app and the widget extension: the
// extension needs to see the types to draw `Button(intent:)`, and the system runs a `LiveActivityIntent` in the app's
// process, where the app has registered a handler. Nothing here can reach the library itself (the extension doesn't
// compile `Shared/` or `Leaf/`), so each intent hands its job to `ReadingIntentBridge`.

/// What the reading intents ask the app to do. `LeafApp` registers one at launch.
@MainActor
protocol ReadingIntentHandling: AnyObject {
    /// Opens Leaf and starts (or returns to) a reading session. False when there's nothing to read.
    func startReading() -> Bool
    /// Opens Leaf at the tea for the next book with a pot already steeping (or the one on the stove). False when
    /// there's nothing to read.
    func startSteep() -> Bool
    func pauseReading() -> Bool
    func resumeReading() -> Bool
    /// Moves the bookmark on by `pages`: the session's book, or with none running the book Today suggests. False with
    /// nothing to move.
    func logPages(_ pages: Int) -> Bool
}

/// The app's handler for the reading intents. Empty in the extension's own process, where the intents never run.
@MainActor
enum ReadingIntentBridge {
    static weak var handler: ReadingIntentHandling?
}

/// "Start reading in Leaf": opens the app on Today and begins (or returns to) the session, tea and all. Here rather
/// than in the app so the Home Screen widgets and the Control Center control can run it too; the system opens Leaf
/// and performs it there.
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

/// "Steep a pot": opens Leaf at the tea for the next book, with the kettle already poured, so the reader can find
/// their page while it steeps. Nothing plays unless the reader turned Leaf's sounds on.
struct StartSteepIntent: AppIntent {
    static var title: LocalizedStringResource = "Steep a pot"
    static var description: IntentDescription? = IntentDescription("Opens Leaf with a pot of tea steeping for your next book.")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = ReadingIntentBridge.handler?.startSteep()
        return .result()
    }
}

/// Pauses the reading timer (the Live Activity's pause button, Shortcuts, Siri).
struct PauseReadingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause reading"
    static var description: IntentDescription? = IntentDescription("Pauses the reading timer. Your place is kept.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = ReadingIntentBridge.handler?.pauseReading()
        return .result()
    }
}

/// Carries on after a pause.
struct ResumeReadingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume reading"
    static var description: IntentDescription? = IntentDescription("Starts the reading timer again after a pause.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = ReadingIntentBridge.handler?.resumeReading()
        return .result()
    }
}

/// Moves the bookmark on while reading, without ending the session; with no session, moves the next book's bookmark
/// (the Control Center control). Runs in the app's process without opening it.
struct LogPagesIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log pages"
    static var description: IntentDescription? = IntentDescription("Moves your bookmark on by a few pages while you read.")

    @Parameter(title: "Pages", default: 1)
    var pages: Int

    init() {}

    init(pages: Int) {
        self.pages = pages
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = ReadingIntentBridge.handler?.logPages(max(1, min(pages, 200)))
        return .result()
    }
}
