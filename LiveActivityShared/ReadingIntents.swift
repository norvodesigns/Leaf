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
    func pauseReading() -> Bool
    func resumeReading() -> Bool
    /// Moves the bookmark of the book being read on by `pages`. False without a session.
    func logPages(_ pages: Int) -> Bool
}

/// The app's handler for the reading intents. Empty in the extension's own process, where the intents never run.
@MainActor
enum ReadingIntentBridge {
    static weak var handler: ReadingIntentHandling?
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

/// Moves the bookmark on while reading, without ending the session.
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
