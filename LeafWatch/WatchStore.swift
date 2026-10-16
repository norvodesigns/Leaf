import Foundation
import Observation
import UserNotifications

/// The watch's view of Leaf: the last snapshot from the phone, plus whatever happened on the wrist since.
@MainActor
@Observable
final class WatchStore {
    private(set) var snapshot: WatchSnapshot
    /// Last reading session logged on the watch, for the wrap-up screen.
    var lastLogged: ReadingSession?

    @ObservationIgnored var send: ((SyncEvent) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persist: Bool
    private static let key = "leaf.watch.snapshot"

    init(defaults: UserDefaults = .standard, demo: Bool = false) {
        self.defaults = defaults
        self.persist = !demo
        if demo {
            snapshot = WatchDemo.snapshot()
        } else if let data = defaults.data(forKey: Self.key), let saved = SyncCodec.decode(WatchSnapshot.self, from: [SyncCodec.snapshotKey: data], key: SyncCodec.snapshotKey) {
            snapshot = saved
        } else {
            snapshot = .empty
        }
    }

    // MARK: Reading

    var activeSession: ActiveSession? { snapshot.activeSession }
    var reading: [WatchBook] { snapshot.reading }

    /// The book to suggest: today's first assignment, else the first book being read.
    var suggestedBook: WatchBook? {
        if let first = snapshot.today.first, let book = snapshot.book(first.bookID) { return book }
        return snapshot.reading.first
    }

    func assignment(for bookID: String) -> WatchAssignment? { snapshot.today.first { $0.bookID == bookID } }

    /// Today's progress including the session running right now.
    func goalProgress(at now: Date) -> Double {
        guard snapshot.dailyMinutes > 0 else { return 0 }
        let live = (activeSession?.elapsed(at: now) ?? 0) / 60
        return min(1, (snapshot.minutesReadToday + live) / Double(snapshot.dailyMinutes))
    }

    func minutesToday(at now: Date) -> Double {
        snapshot.minutesReadToday + (activeSession?.elapsed(at: now) ?? 0) / 60
    }

    /// A smart starting point for the page picker: where your pace says you are.
    func estimatedPage(for session: ActiveSession, at now: Date = Date()) -> Int {
        guard let book = snapshot.book(session.bookID) else { return session.startPage }
        let pages = Double(session.elapsed(at: now) / 60) * snapshot.wpm / max(book.wordsPerPage, 1)
        return min(book.pages, session.startPage + Int(pages.rounded()))
    }

    // MARK: From the phone

    func apply(_ incoming: WatchSnapshot) {
        var next = incoming
        // Keep a newer local copy of the live session if the phone hasn't seen our change yet.
        if let local = snapshot.activeSession, let remote = incoming.activeSession, local.id == remote.id, local.revision > remote.revision {
            next.activeSession = local
        }
        snapshot = next
        save()
    }

    // MARK: Sessions on the wrist

    func start(bookID: String) {
        guard snapshot.activeSession == nil, let book = snapshot.book(bookID) else { return }
        let session = ActiveSession(bookID: bookID, startedAt: Date(), startPage: book.currentPage, origin: .watch)
        snapshot.activeSession = session
        save()
        send?(.sessionChanged(session))
        scheduleGoalNudge()
    }

    func pause() {
        guard snapshot.activeSession != nil else { return }
        snapshot.activeSession?.pause()
        save()
        if let session = snapshot.activeSession { send?(.sessionChanged(session)) }
        cancelGoalNudge()
    }

    func resume() {
        guard snapshot.activeSession != nil else { return }
        snapshot.activeSession?.resume()
        save()
        if let session = snapshot.activeSession { send?(.sessionChanged(session)) }
        scheduleGoalNudge()
    }

    func cancel() {
        guard let session = snapshot.activeSession else { return }
        snapshot.activeSession = nil
        save()
        send?(.sessionCancelled(session.id))
        cancelGoalNudge()
    }

    /// Logs the session at `page`, updates the local copy optimistically, and tells the phone.
    func finish(at page: Int, end: Date = Date()) {
        guard let active = snapshot.activeSession else { return }
        let logged = ReadingSession(id: active.id, bookID: active.bookID, startedAt: active.startedAt, seconds: active.elapsed(at: end), fromPage: active.startPage, toPage: page)
        snapshot.activeSession = nil
        snapshot.minutesReadToday += logged.minutes
        if let index = snapshot.reading.firstIndex(where: { $0.id == active.bookID }) {
            snapshot.reading[index].currentPage = max(snapshot.reading[index].currentPage, page)
        }
        lastLogged = logged
        save()
        send?(.sessionLogged(logged, activeID: active.id))
        cancelGoalNudge()
    }

    // MARK: Goal nudge (a wrist tap when today's minutes are done, even with the app in the background)

    private func scheduleGoalNudge() {
        guard let session = snapshot.activeSession, !session.isPaused else { return }
        let remaining = (Double(snapshot.dailyMinutes) - snapshot.minutesReadToday) * 60 - session.elapsed()
        guard remaining > 5 else { return }
        let center = UNUserNotificationCenter.current()
        let minutes = snapshot.dailyMinutes
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(minutes) minutes read"
            content.body = "That's today's goal. Keep going, or log your page."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "leaf.watch.goal", content: content, trigger: trigger))
        }
    }

    private func cancelGoalNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["leaf.watch.goal"])
    }

    private func save() {
        guard persist, let data = SyncCodec.encode(snapshot, key: SyncCodec.snapshotKey)[SyncCodec.snapshotKey] else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Sample data for screenshots and previews.
enum WatchDemo {
    static func snapshot(now: Date = Date()) -> WatchSnapshot {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let week = (0..<7).map { offset -> WatchDay in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? now
            let isPast = date < calendar.startOfDay(for: now)
            let isToday = calendar.isDate(date, inSameDayAs: now)
            return WatchDay(date: date, minutes: isToday ? 12 : (isPast ? [28, 25, 31, 0, 26, 35, 24][offset] : 0), goal: 25, isReadingDay: true)
        }
        let hobbit = WatchBook(id: "OL27482W", title: "The Hobbit", author: "J. R. R. Tolkien", currentPage: 142, pages: 310, wordsPerPage: 306, paletteSeed: 3, finish: calendar.date(byAdding: .day, value: 9, to: now))
        let circe = WatchBook(id: "OL18012166W", title: "Circe", author: "Madeline Miller", currentPage: 88, pages: 404, wordsPerPage: 270, paletteSeed: 6, finish: calendar.date(byAdding: .day, value: 26, to: now))
        var snapshot = WatchSnapshot(
            generatedAt: now, dailyMinutes: 25, minutesReadToday: 12, isReadingDay: true, streak: 6, wpm: 262,
            today: [WatchAssignment(bookID: hobbit.id, title: hobbit.title, minutes: 13, fromPage: 143, toPage: 154)],
            reading: [hobbit, circe], week: week, activeSession: nil, hasOnboarded: true
        )
        if LaunchScreen.current == "session" || LaunchScreen.current == "pages" {
            snapshot.activeSession = ActiveSession(bookID: hobbit.id, startedAt: now.addingTimeInterval(-9 * 60 - 41), startPage: 142, origin: .watch)
        }
        return snapshot
    }
}

/// Debug launch arguments: `-LeafDemo YES -LeafScreen today|session|pages|books`.
enum LaunchScreen {
    static var isDemo: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "LeafDemo")
        #else
        false
        #endif
    }

    static var current: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "LeafScreen")
        #else
        nil
        #endif
    }
}
