import Foundation
import UserNotifications
import WatchKit

/// Keeps a reading session alive on the wrist when the wrist goes down, so the timer keeps time and can tap at the
/// goal. A `WKExtendedRuntimeSession` of the mindfulness type (declared in `WKBackgroundModes`): the closest Apple
/// offers to "sit quietly with a book"; a session lasts up to an hour and is restarted on resume. Only sessions the
/// watch itself is timing start one; a session mirrored from the phone does not.
@MainActor
final class ReadingRuntime: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = ReadingRuntime()

    private var session: WKExtendedRuntimeSession?
    private var goalTask: Task<Void, Never>?
    /// Called when the system ends the runtime before we did (expired, denied, suppressed), so the store can fall back
    /// to a scheduled notification for the goal.
    var onLost: (() -> Void)?

    /// True while a runtime is keeping the session alive; the goal tap is then the runtime's.
    var isRunning: Bool { session != nil }

    /// Starts (or keeps) the runtime and taps the wrist when `secondsToGoal` have passed.
    func begin(secondsToGoal: Double?) {
        if session == nil || session?.state == .invalid {
            let next = WKExtendedRuntimeSession()
            next.delegate = self
            next.start()
            session = next
        }
        goalTask?.cancel()
        guard let secondsToGoal, secondsToGoal > 1 else { return }
        goalTask = Task {
            try? await Task.sleep(for: .seconds(secondsToGoal))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.success)
        }
    }

    /// Lets the watch sleep again: on pause, finish or cancel.
    func end() {
        goalTask?.cancel()
        goalTask = nil
        session?.invalidate()
        session = nil
    }

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        // About to run out (an hour): a gentle tap so a long read isn't lost silently.
        Task { @MainActor in WKInterfaceDevice.current().play(.notification) }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor in
            // Ours to end goes through end(), which clears `session` first; anything else was the system.
            guard self.session === extendedRuntimeSession else { return }
            self.session = nil
            self.goalTask?.cancel()
            self.goalTask = nil
            self.onLost?()
        }
    }
}

/// The reading reminder's actions on the wrist: Start, Snooze 30 min, Skip today. The phone schedules the reminders
/// and handles them when it is in hand; registering the same category here lets the watch act on them too when the
/// notification shows on the wrist. The identifiers match `ReminderID` in the iPhone app.
@MainActor
final class WatchNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotifications()

    static let category = "leaf.reading"
    static let startAction = "leaf.start"
    static let snoozeAction = "leaf.snooze"
    static let skipAction = "leaf.skip"
    static let bookKey = "bookID"
    static let snoozeMinutes = 30

    private weak var store: WatchStore?

    func configure(store: WatchStore) {
        self.store = store
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startAction, title: "Start reading", options: [.foreground])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "In \(Self.snoozeMinutes) minutes", options: [])
        let skip = UNNotificationAction(identifier: Self.skipAction, title: "Skip today", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [start, snooze, skip], intentIdentifiers: [], options: [])
        ])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The tea and goal taps are already on screen (and tapped) while the app is open; reminders still show.
        let own = ["leaf.watch.steep", "leaf.watch.goal"]
        return own.contains(notification.request.identifier) ? [] : [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let bookID = content.userInfo[Self.bookKey] as? String
        switch response.actionIdentifier {
        case Self.startAction:
            await MainActor.run {
                guard let store = self.store, store.activeSession == nil else { return }
                if let id = bookID ?? store.suggestedBook?.id { store.start(bookID: id) }
            }
        case Self.snoozeAction:
            let again = UNMutableNotificationContent()
            again.title = content.title
            again.body = content.body
            again.sound = .default
            again.categoryIdentifier = Self.category
            again.userInfo = content.userInfo
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(Self.snoozeMinutes * 60), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "leaf.watch.snooze", content: again, trigger: trigger))
        default:
            // Skip today, or a plain tap: nothing more to do on the wrist.
            break
        }
    }
}
