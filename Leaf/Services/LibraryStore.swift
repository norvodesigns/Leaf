import Foundation
import Observation

/// What happened when a reading session was logged, for the end-of-session moment.
struct SessionOutcome: Hashable {
    var session: ReadingSession
    var bookID: String
    var finishedBook: Bool
    var reachedGoalNow: Bool
    var minutesToday: Double
    var oldWPM: Double
    var newWPM: Double
}

/// The single source of truth for the library, sessions, preferences and the plan.
@MainActor
@Observable
final class LibraryStore {
    private(set) var data: LeafData
    private(set) var plan: ReadingPlan = .empty
    /// The moment "today" is computed from. Refreshed when the app becomes active and at midnight.
    private(set) var now: Date

    /// Called after every change (reminders and the watch listen here).
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let persistence: Persistence
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored var calendar: Calendar = .current

    init(persistence: Persistence = .shared, now: Date = Date()) {
        self.persistence = persistence
        self.now = now
        self.data = persistence.load() ?? LeafData()
        recomputePlan()
    }

    // MARK: - Reading the state

    var preferences: ReadingPreferences { data.preferences }
    var wpm: Double { data.preferences.wpm }
    var hasOnboarded: Bool { data.preferences.hasOnboarded }

    var reading: [LibraryItem] { data.items(on: .reading) }
    var toRead: [LibraryItem] { data.items(on: .toRead) }
    var finished: [LibraryItem] { data.items(on: .finished) }

    func item(_ id: String) -> LibraryItem? { data.items.first { $0.id == id } }
    func shelf(of id: String) -> Shelf? { item(id)?.shelf }

    var minutesReadToday: Double { ReadingStats.minutesRead(on: now, sessions: data.sessions, calendar: calendar) }

    var goalProgress: Double {
        let goal = Double(data.preferences.dailyMinutes)
        return goal > 0 ? min(1, minutesReadToday / goal) : 0
    }

    var goalMetToday: Bool { data.preferences.dailyMinutes > 0 && minutesReadToday >= Double(data.preferences.dailyMinutes) }

    var isReadingDay: Bool { data.preferences.readingDays.contains(calendar.component(.weekday, from: now)) }

    var streak: Int { ReadingStats.streak(sessions: data.sessions, readingDays: data.preferences.readingDays, today: now, calendar: calendar) }

    var week: [DayStat] { ReadingStats.week(containing: now, sessions: data.sessions, readingDays: data.preferences.readingDays, calendar: calendar) }

    var booksFinishedThisYear: Int { ReadingStats.booksFinished(in: calendar.component(.year, from: now), items: data.items, calendar: calendar) }

    /// Today's reading, paired with the books it's for.
    var todayAssignments: [(item: LibraryItem, assignment: Assignment)] {
        (plan.today?.assignments ?? []).compactMap { assignment in
            item(assignment.bookID).map { ($0, assignment) }
        }
    }

    /// The book the reader is most likely to pick up next.
    var nextBook: LibraryItem? { todayAssignments.first?.item ?? reading.first ?? toRead.first }

    var activeSession: ActiveSession? { data.activeSession }

    func sessions(for bookID: String) -> [ReadingSession] {
        data.sessions.filter { $0.bookID == bookID }.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Shelves

    func add(_ book: Book, to shelf: Shelf) {
        if let index = data.items.firstIndex(where: { $0.id == book.id }) {
            data.items[index].book = book
            commit()
            move(book.id, to: shelf)
            return
        }
        var item = LibraryItem(book: book, shelf: shelf, order: nextOrder(on: shelf), addedAt: now)
        if shelf == .reading { item.startedAt = now }
        if shelf == .finished {
            item.finishedAt = now
            item.currentPage = book.pages
        }
        data.items.append(item)
        commit()
    }

    func move(_ id: String, to shelf: Shelf) {
        guard let index = data.items.firstIndex(where: { $0.id == id }), data.items[index].shelf != shelf else { return }
        data.items[index].shelf = shelf
        data.items[index].order = nextOrder(on: shelf)
        switch shelf {
        case .reading:
            if data.items[index].startedAt == nil { data.items[index].startedAt = now }
            data.items[index].finishedAt = nil
            if data.items[index].currentPage >= data.items[index].book.pages { data.items[index].currentPage = 0 }
        case .toRead:
            data.items[index].finishedAt = nil
        case .finished:
            data.items[index].finishedAt = now
            data.items[index].currentPage = data.items[index].book.pages
        }
        commit()
    }

    func startReading(_ id: String) { move(id, to: .reading) }

    func markFinished(_ id: String, rating: Int? = nil) {
        move(id, to: .finished)
        if let rating { setRating(id, rating: rating) }
    }

    func setRating(_ id: String, rating: Int?) {
        guard let index = data.items.firstIndex(where: { $0.id == id }) else { return }
        data.items[index].rating = rating
        commit()
    }

    func remove(_ id: String) {
        data.items.removeAll { $0.id == id }
        if data.activeSession?.bookID == id { data.activeSession = nil }
        commit()
    }

    func setPage(_ id: String, page: Int) {
        guard let index = data.items.firstIndex(where: { $0.id == id }) else { return }
        data.items[index].currentPage = min(max(0, page), data.items[index].book.pages)
        commit()
    }

    /// Reorders a shelf after a drag (List.onMove semantics).
    func reorder(_ shelf: Shelf, fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = data.items(on: shelf).map(\.id)
        let moving = source.sorted().map { ids[$0] }
        for offset in source.sorted(by: >) { ids.remove(at: offset) }
        let insertAt = destination - source.filter { $0 < destination }.count
        ids.insert(contentsOf: moving, at: max(0, min(insertAt, ids.count)))
        applyOrder(ids)
    }

    /// Puts a book at the front of its shelf ("Read next").
    func moveToFront(_ id: String) {
        guard let shelf = shelf(of: id) else { return }
        let ids = [id] + data.items(on: shelf).map(\.id).filter { $0 != id }
        applyOrder(ids)
    }

    func updateBook(_ id: String, title: String? = nil, author: String? = nil, pages: Int? = nil) {
        guard let index = data.items.firstIndex(where: { $0.id == id }) else { return }
        var book = data.items[index].book
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { book.title = title }
        if let author, !author.trimmingCharacters(in: .whitespaces).isEmpty { book.author = author }
        if let pages, pages > 0, pages != book.pages {
            let wordsPerPage = book.wordsPerPage
            book.pages = pages
            book.words = max(1, Int((Double(pages) * wordsPerPage).rounded()))
        }
        data.items[index].book = book
        data.items[index].currentPage = min(data.items[index].currentPage, book.pages)
        commit()
    }

    // MARK: - Preferences

    func updatePreferences(_ change: (inout ReadingPreferences) -> Void) {
        change(&data.preferences)
        data.preferences.dailyMinutes = min(240, max(0, data.preferences.dailyMinutes))
        data.preferences.wpm = ReadingSpeed.clamp(data.preferences.wpm)
        commit()
    }

    func recordSpeedTest(_ result: SpeedTestResult) {
        data.speedTests.append(result)
        data.preferences.wpm = result.effectiveWPM
        commit()
    }

    var latestSpeedTest: SpeedTestResult? { data.speedTests.last }

    // MARK: - Sessions

    @discardableResult
    func startSession(bookID: String, origin: SessionDevice = .phone) -> ActiveSession? {
        if let active = data.activeSession { return active }
        guard let item = item(bookID) else { return nil }
        if item.shelf != .reading { move(bookID, to: .reading) }
        let session = ActiveSession(bookID: bookID, startedAt: Date(), startPage: self.item(bookID)?.currentPage ?? 0, origin: origin)
        data.activeSession = session
        commit()
        return session
    }

    func pauseSession() {
        guard data.activeSession != nil else { return }
        data.activeSession?.pause()
        commit()
    }

    func resumeSession() {
        guard data.activeSession != nil else { return }
        data.activeSession?.resume()
        commit()
    }

    func cancelSession() {
        guard data.activeSession != nil else { return }
        data.activeSession = nil
        commit()
    }

    /// Ends the live session at `toPage`, logs it, recalibrates speed, and finishes the book if it's done.
    @discardableResult
    func finishSession(toPage: Int, at end: Date = Date()) -> SessionOutcome? {
        guard let active = data.activeSession else { return nil }
        let session = ReadingSession(
            id: active.id,
            bookID: active.bookID,
            startedAt: active.startedAt,
            seconds: active.elapsed(at: end),
            fromPage: active.startPage,
            toPage: toPage
        )
        data.activeSession = nil
        let outcome = log(session)
        if outcome == nil { commit() }
        return outcome
    }

    /// Logs a finished session (from this phone, the watch, or a manual entry).
    @discardableResult
    func log(_ session: ReadingSession) -> SessionOutcome? {
        guard !data.sessions.contains(where: { $0.id == session.id }) else { return nil }
        guard let index = data.items.firstIndex(where: { $0.id == session.bookID }) else { return nil }
        let wasMet = goalMetToday
        let oldWPM = data.preferences.wpm
        let book = data.items[index].book
        let toPage = min(max(session.toPage, 0), book.pages)
        var logged = session
        logged.toPage = toPage
        data.sessions.append(logged)
        data.items[index].currentPage = max(data.items[index].currentPage, toPage)
        if data.items[index].shelf == .toRead {
            data.items[index].shelf = .reading
            data.items[index].order = nextOrder(on: .reading)
        }
        if data.items[index].startedAt == nil { data.items[index].startedAt = session.startedAt }
        if let observed = ReadingSpeed.observedWPM(pagesRead: logged.pagesRead, wordsPerPage: book.wordsPerPage, seconds: logged.seconds) {
            data.preferences.wpm = ReadingSpeed.calibrated(current: oldWPM, observed: observed)
        }
        let finishedBook = toPage >= book.pages
        if finishedBook {
            data.items[index].shelf = .finished
            data.items[index].finishedAt = session.startedAt.addingTimeInterval(session.seconds)
        }
        commit()
        return SessionOutcome(
            session: logged,
            bookID: session.bookID,
            finishedBook: finishedBook,
            reachedGoalNow: !wasMet && goalMetToday,
            minutesToday: minutesReadToday,
            oldWPM: oldWPM,
            newWPM: data.preferences.wpm
        )
    }

    /// Applies an event that arrived from the watch.
    @discardableResult
    func apply(_ event: SyncEvent) -> SessionOutcome? {
        switch event {
        case .sessionChanged(let remote):
            if let current = data.activeSession, current.id == remote.id, current.revision >= remote.revision { return nil }
            if let current = data.activeSession, current.id != remote.id, current.startedAt > remote.startedAt { return nil }
            if data.sessions.contains(where: { $0.id == remote.id }) { return nil }
            if item(remote.bookID)?.shelf == .toRead { move(remote.bookID, to: .reading) }
            data.activeSession = remote
            commit()
        case .sessionCancelled(let id):
            if data.activeSession?.id == id {
                data.activeSession = nil
                commit()
            }
        case .sessionLogged(let session, let activeID):
            if let activeID, data.activeSession?.id == activeID { data.activeSession = nil }
            if let outcome = log(session) { return outcome }
            commit()
        case .requestSnapshot:
            onChange?()
        }
        return nil
    }

    // MARK: - Day changes, reset

    func refreshDay(_ date: Date = Date()) {
        now = date
        recomputePlan()
        onChange?()
    }

    func resetEverything() {
        data = LeafData()
        commit()
    }

    /// Replaces all data (demo seeding and screenshot runs).
    func replaceAll(with newData: LeafData) {
        data = newData
        commit()
    }

    /// Writes immediately (when the app moves to the background).
    func flush() {
        saveTask?.cancel()
        try? persistence.save(data)
    }

    // MARK: - Internals

    private func nextOrder(on shelf: Shelf) -> Double {
        (data.items.filter { $0.shelf == shelf }.map(\.order).max() ?? 0) + 1
    }

    private func applyOrder(_ ids: [String]) {
        for (position, id) in ids.enumerated() {
            if let index = data.items.firstIndex(where: { $0.id == id }) {
                data.items[index].order = Double(position)
            }
        }
        commit()
    }

    private func recomputePlan() {
        let input = PlanInput(
            reading: data.items(on: .reading),
            queue: data.items(on: .toRead),
            wpm: data.preferences.wpm,
            dailyMinutes: data.preferences.dailyMinutes,
            readingDays: data.preferences.readingDays,
            mode: data.preferences.planMode,
            today: now,
            minutesReadToday: minutesReadToday,
            calendar: calendar
        )
        plan = Planner.makePlan(input, recordDays: 60)
    }

    private func commit() {
        recomputePlan()
        scheduleSave()
        onChange?()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = data
        let persistence = persistence
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            try? persistence.save(snapshot)
        }
    }
}
