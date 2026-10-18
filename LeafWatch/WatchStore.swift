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
    /// A pot steeping right now (the tea timer that hands off to reading), if any.
    private(set) var steep: SteepTimer?

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

    func start(bookID: String, teaID: String? = nil, goalSeconds: Double? = nil) {
        guard snapshot.activeSession == nil, let book = snapshot.book(bookID) else { return }
        let session = ActiveSession(bookID: bookID, startedAt: Date(), startPage: book.currentPage, origin: .watch, teaID: teaID, goalSeconds: goalSeconds)
        snapshot.activeSession = session
        steep = nil
        cancelSteepNotification()
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
        let logged = ReadingSession(
            id: active.id, bookID: active.bookID, startedAt: active.startedAt, seconds: active.elapsed(at: end),
            fromPage: active.startPage, toPage: page, teaID: active.teaID, ambienceID: active.ambienceID, device: .watch
        )
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

    // MARK: Quick actions (no timer needed)

    /// "Read without the timer": crown to the page, tap to save.
    func quickLog(bookID: String, toPage: Int, minutes: Double, now: Date = Date()) {
        guard minutes > 0, let book = snapshot.book(bookID) else { return }
        let page = min(max(0, toPage), book.pages)
        let logged = ReadingSession(
            bookID: bookID, startedAt: now.addingTimeInterval(-minutes * 60), seconds: minutes * 60,
            fromPage: book.currentPage, toPage: page, kind: .manual, device: .watch
        )
        snapshot.minutesReadToday += minutes
        setLocalPage(bookID, page)
        lastLogged = logged
        save()
        send?(.sessionLogged(logged, activeID: nil))
    }

    /// "Where was I?" corrected from the wrist.
    func setPage(bookID: String, page: Int) {
        guard let book = snapshot.book(bookID) else { return }
        let clamped = min(max(0, page), book.pages)
        setLocalPage(bookID, clamped)
        save()
        send?(.pageSet(bookID: bookID, page: clamped))
    }

    /// Dictated thought or quote, attached to a book. Stored on the phone.
    func addJournal(bookID: String, kind: JournalEntry.Kind, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let book = snapshot.book(bookID) else { return }
        send?(.journalAdded(bookID: bookID, kind: kind, text: trimmed, page: book.currentPage))
    }

    /// Mark finished, set aside, or start a queued book from the wrist.
    func moveBook(_ bookID: String, to shelf: Shelf, rating: Int? = nil) {
        guard snapshot.book(bookID) != nil else { return }
        switch shelf {
        case .finished, .paused, .toRead:
            snapshot.reading.removeAll { $0.id == bookID }
            snapshot.today.removeAll { $0.bookID == bookID }
        case .reading:
            if let queued = snapshot.queue.first(where: { $0.id == bookID }), !snapshot.reading.contains(where: { $0.id == bookID }) {
                snapshot.reading.append(queued)
                snapshot.queue.removeAll { $0.id == bookID }
            }
        }
        save()
        send?(.shelfChanged(bookID: bookID, shelf: shelf, rating: rating))
    }

    /// A title dictated on the wrist; the phone finds it in the catalog and queues it.
    func addBook(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send?(.addBook(query: trimmed))
    }

    private func setLocalPage(_ bookID: String, _ page: Int) {
        if let index = snapshot.reading.firstIndex(where: { $0.id == bookID }) {
            snapshot.reading[index].currentPage = max(0, page)
        } else if let index = snapshot.queue.firstIndex(where: { $0.id == bookID }) {
            snapshot.queue[index].currentPage = max(0, page)
        }
    }

    // MARK: Tea timer (steep, then read)

    /// Starts steeping. A local notification taps the wrist when the tea is ready, even with the app in the background.
    func startSteep(_ tea: WatchTea, now: Date = Date()) {
        steep = SteepTimer(tea: tea, startedAt: now)
        scheduleSteepNotification(tea: tea, seconds: Double(tea.steepSeconds))
    }

    func cancelSteep() {
        steep = nil
        cancelSteepNotification()
    }

    private func scheduleSteepNotification(tea: WatchTea, seconds: Double) {
        guard seconds > 1 else { return }
        let center = UNUserNotificationCenter.current()
        Task {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(tea.name) is ready"
            content.body = "Time to read."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "leaf.watch.steep", content: content, trigger: trigger))
        }
    }

    private func cancelSteepNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["leaf.watch.steep"])
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

/// A pot of tea steeping on the wrist.
struct SteepTimer: Hashable, Sendable {
    var tea: WatchTea
    var startedAt: Date

    var endsAt: Date { startedAt.addingTimeInterval(Double(tea.steepSeconds)) }

    func remaining(at now: Date) -> Double { max(0, endsAt.timeIntervalSince(now)) }

    func isReady(at now: Date) -> Bool { now >= endsAt }
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
        snapshot.greeting = WatchGreeting(headline: "Tea o’clock.", subline: "Thirteen minutes to today’s goal.")
        snapshot.tea = WatchTea(id: "earl-grey", name: "Earl Grey", steepSeconds: 240)
        snapshot.queue = [
            WatchBook(id: "OL20893680W", title: "Piranesi", author: "Susanna Clarke", currentPage: 0, pages: 272, wordsPerPage: 270, paletteSeed: 8, finish: calendar.date(byAdding: .day, value: 40, to: now)),
            WatchBook(id: "OL21745884W", title: "Project Hail Mary", author: "Andy Weir", currentPage: 0, pages: 496, wordsPerPage: 270, paletteSeed: 1, finish: calendar.date(byAdding: .day, value: 58, to: now)),
        ]
        snapshot.forecasts = [
            WatchForecast(bookID: hobbit.id, sentence: "Probably done next Saturday.", median: hobbit.finish),
            WatchForecast(bookID: circe.id, sentence: "Likely early next month.", median: circe.finish),
        ]
        snapshot.yearGoal = WatchYearGoal(year: calendar.component(.year, from: now), finished: 9, goal: 24, sentence: "On track for 22 books.")
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
