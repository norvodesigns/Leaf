import Foundation
import UserNotifications

/// What Leaf remembers outside the library file that still says something about the library: generated greeting
/// lines (they can name a book), which lines were shown, quiet books kept off the plan, a skipped day, a snoozed
/// reminder. "Erase all data" clears these with the library, so nothing of it stays on the phone.
enum LibraryTraces {
    /// Every UserDefaults key of Leaf's own starts with this.
    static let prefix = "leaf."
    /// Kept: the Focus filter's state belongs to the system's Focus, and the cozy settings have their own reset.
    static let kept: [String] = ["leaf.focus.", "leaf.cozy."]

    static func erase(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            guard !kept.contains(where: { key.hasPrefix($0) }) else { continue }
            defaults.removeObject(forKey: key)
        }
        // The daily, goal and weekly reminders are rescheduled from the empty library; a snooze would still name the book.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [ReminderID.snooze])
    }
}
