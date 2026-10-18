import Foundation
import UserNotifications

/// Identifiers shared with notification delegate callbacks (kept outside the main actor).
enum ReminderID {
    static let dailyPrefix = "leaf.daily."
    static let goal = "leaf.session.goal"
    static let category = "leaf.reading"
    static let startAction = "leaf.start"
    static let snoozeAction = "leaf.snooze"
    static let skipAction = "leaf.skip"
    static let snooze = "leaf.snooze.pending"
    static let weeklyPrefix = "leaf.weekly."
    static let bookKey = "bookID"
    static let weeklyKey = "weeklyLetter"
    /// UserDefaults key holding the day ("yyyy-MM-dd") the reader chose to skip.
    static let skippedDayKey = "leaf.reminders.skippedDay"
    static let snoozeMinutes = 30
}

/// Daily reading reminders, personalised with each day's assignment, plus the "goal reached" nudge during a session.
@MainActor
final class Reminders: NSObject {
    static let shared = Reminders()

    private let center = UNUserNotificationCenter.current()
    private weak var store: LibraryStore?
    private var refreshTask: Task<Void, Never>?

    /// Called when someone taps "Start reading" on a reminder.
    var onStartReading: ((String?) -> Void)?
    /// Called when someone opens the Sunday note about their week.
    var onOpenWeeklyLetter: (() -> Void)?

    func configure(store: LibraryStore) {
        self.store = store
        center.delegate = self
        let start = UNNotificationAction(identifier: ReminderID.startAction, title: "Start reading", options: [.foreground])
        let snooze = UNNotificationAction(identifier: ReminderID.snoozeAction, title: "In \(ReminderID.snoozeMinutes) minutes", options: [])
        let skip = UNNotificationAction(identifier: ReminderID.skipAction, title: "Skip today", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ReminderID.category, actions: [start, snooze, skip], intentIdentifiers: [], options: [])
        ])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Coalesces bursts of changes into one reschedule.
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    func reschedule() async {
        guard let store else { return }
        let existing = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.hasPrefix(ReminderID.dailyPrefix) || $0 == ReminderID.goal })

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        scheduleGoalNudge(store: store)
        await scheduleWeeklyLetters(store: store, calendar: Calendar.current, now: Date())

        let prefs = store.preferences
        guard prefs.reminderEnabled else { return }
        let calendar = Calendar.current
        let now = Date()
        var scheduled = 0
        for (offset, day) in store.plan.days.enumerated() where scheduled < 60 {
            guard day.isReadingDay else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day.date)
            components.hour = prefs.reminderHour
            components.minute = prefs.reminderMinute
            guard let fireDate = calendar.date(from: components), fireDate > now else { continue }
            if offset == 0 && (store.goalMetToday || store.activeSession != nil) { continue }
            if UserDefaults.standard.string(forKey: ReminderID.skippedDayKey) == Self.dayKey(day.date, calendar: calendar) { continue }

            let content = UNMutableNotificationContent()
            let copy = Self.copy(for: day, offset: offset, store: store)
            content.title = copy.title
            content.body = copy.body
            content.sound = .default
            content.categoryIdentifier = ReminderID.category
            content.threadIdentifier = "leaf.daily"
            if let bookID = day.assignments.first?.bookID { content.userInfo = [ReminderID.bookKey: bookID] }

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = ReminderID.dailyPrefix + Self.dayKey(day.date, calendar: calendar)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            scheduled += 1
        }
    }

    /// A short Sunday-evening note about the week, for the next few Sundays. The wording is generic on purpose: the
    /// letter itself is written from fresh numbers when the reader opens it.
    private func scheduleWeeklyLetters(store: LibraryStore, calendar: Calendar, now: Date) async {
        let existing = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.hasPrefix(ReminderID.weeklyPrefix) })
        guard store.preferences.weeklyLetter else { return }
        let sunday = DateComponents(hour: 19, minute: 0, weekday: 1)
        var found = 0
        var cursor = now
        while found < 4, let next = calendar.nextDate(after: cursor, matching: sunday, matchingPolicy: .nextTime) {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)
            let content = UNMutableNotificationContent()
            content.title = "Your week in the nook"
            content.body = "A short note on this week’s reading is ready."
            content.sound = .default
            content.threadIdentifier = "leaf.weekly"
            content.userInfo = [ReminderID.weeklyKey: true]
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: ReminderID.weeklyPrefix + Self.dayKey(next, calendar: calendar), content: content, trigger: trigger))
            cursor = next
            found += 1
        }
    }

    /// While a session runs, a quiet tap when today's goal is reached (useful with the phone face down).
    private func scheduleGoalNudge(store: LibraryStore) {
        guard let active = store.activeSession, !active.isPaused, !store.goalMetToday else { return }
        let remaining = (Double(store.preferences.dailyMinutes) - store.minutesReadToday) * 60 - active.elapsed()
        guard remaining > 5 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Goal met"
        content.body = "That's today's \(store.preferences.dailyMinutes) minutes. Anything more is a gift."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        center.add(UNNotificationRequest(identifier: ReminderID.goal, content: content, trigger: trigger))
    }

    /// Notification copy (DESIGN.md §11): minutes and pages first, the book by name, never guilt.
    static func copy(for day: PlanDay, offset: Int, store: LibraryStore) -> (title: String, body: String) {
        let title = "Leaf"
        let parts = day.assignments.compactMap { assignment -> (item: LibraryItem, assignment: Assignment)? in
            store.item(assignment.bookID).map { ($0, assignment) }
        }
        guard let first = parts.first else {
            return (title, store.data.items.isEmpty
                ? "Add a book and Leaf will plan the pages."
                : "Your list is clear. Pick your next book whenever you're ready.")
        }
        let minutes = Int(day.minutes.rounded())
        let pages = "\(first.assignment.fromPage)–\(first.assignment.toPage)"
        if parts.count > 1 {
            return (title, "\(minutes) minutes today, starting with \(first.item.book.title), pp. \(pages).")
        }
        if first.assignment.finishesBook {
            let left = max(1, first.item.book.pages - first.item.currentPage)
            return (title, "\(left) pages left in \(first.item.book.title). You could finish today.")
        }
        let when = store.preferences.reminderHour >= 17 ? "tonight" : "today"
        return (title, "\(minutes) minutes of \(first.item.book.title) \(when) — about pp. \(pages).")
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension Reminders: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // In the app, the session screen celebrates the goal itself.
        notification.request.identifier == ReminderID.goal ? [] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let bookID = content.userInfo[ReminderID.bookKey] as? String
        switch response.actionIdentifier {
        case ReminderID.startAction:
            await MainActor.run { Reminders.shared.onStartReading?(bookID) }
        case ReminderID.snoozeAction:
            // Same words, thirty minutes later.
            let again = UNMutableNotificationContent()
            again.title = content.title
            again.body = content.body
            again.sound = .default
            again.categoryIdentifier = ReminderID.category
            again.userInfo = content.userInfo
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(ReminderID.snoozeMinutes * 60), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: ReminderID.snooze, content: again, trigger: trigger))
        case ReminderID.skipAction:
            // Quiet for the rest of today: drop a pending snooze and remember not to schedule one again.
            center.removePendingNotificationRequests(withIdentifiers: [ReminderID.snooze])
            await MainActor.run {
                UserDefaults.standard.set(Reminders.dayKey(Date(), calendar: .current), forKey: ReminderID.skippedDayKey)
            }
        default:
            if content.userInfo[ReminderID.weeklyKey] != nil {
                await MainActor.run { Reminders.shared.onOpenWeeklyLetter?() }
            }
        }
    }
}
