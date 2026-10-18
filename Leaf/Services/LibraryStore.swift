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
    /// Wall-clock time for change stamps (iCloud merging compares these), kept apart from `now` so tests can control it.
    @ObservationIgnored var clock: () -> Date = { Date() }
    private var stamp: Date { clock() }

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

    /// Today's issue number: 1 on the day onboarding finished.
    var issueNumber: Int {
        guard let start = data.preferences.onboardedAt else { return 1 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0
        return max(1, days + 1)
    }

    /// Sessions logged for a book, oldest first.
    func sessionCount(for bookID: String) -> Int { data.sessions.filter { $0.bookID == bookID }.count }

    func sessions(for bookID: String) -> [ReadingSession] {
        data.sessions.filter { $0.bookID == bookID }.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Shelves

    func add(_ book: Book, to shelf: Shelf) {
        if let index = data.items.firstIndex(where: { $0.id == book.id }) {
            data.items[index].book = book
            data.items[index].updatedAt = stamp
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
        item.updatedAt = stamp
        clearTombstone(.item, book.id)
        data.items.append(item)
        commit()
    }

    func move(_ id: String, to shelf: Shelf) {
        guard let index = data.items.firstIndex(where: { $0.id == id }), data.items[index].shelf != shelf else { return }
        data.items[index].shelf = shelf
        data.items[index].order = nextOrder(on: shelf)
        data.items[index].updatedAt = stamp
        data.items[index].pausedAt = shelf == .paused ? now : nil
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
            data.items[index].positionConfirmed = true
        case .paused:
            data.items[index].finishedAt = nil
            if data.activeSession?.bookID == id { data.activeSession = nil }
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
        data.items[index].updatedAt = stamp
        commit()
    }

    func remove(_ id: String) {
        guard data.items.contains(where: { $0.id == id }) else { return }
        data.items.removeAll { $0.id == id }
        if data.activeSession?.bookID == id { data.activeSession = nil }
        addTombstone(.item, id)
        commit()
    }

    /// Sets a book aside without guilt. It keeps its page and drops out of the plan.
    func pause(_ id: String) { move(id, to: .paused) }

    // MARK: - Discovery

    /// "Not for me": the book stops appearing in suggestions and nudges the reader's taste away from it.
    func dismiss(_ id: String) {
        guard !data.dismissed.contains(id) else { return }
        data.dismissed.append(id)
        clearTombstone(.dismissal, id)
        commit()
    }

    func undismiss(_ id: String) {
        guard data.dismissed.contains(id) else { return }
        data.dismissed.removeAll { $0 == id }
        addTombstone(.dismissal, id)
        commit()
    }

    /// Everything the recommender needs to know about this reader.
    func recommendationContext(catalog: BookCatalog) -> RecommendationContext {
        RecommendationContext(
            library: data.items,
            sessions: data.sessions,
            dismissed: data.dismissed.compactMap { catalog.book(id: $0) },
            wpm: wpm,
            dailyMinutes: data.preferences.dailyMinutes,
            now: now,
            calendar: calendar
        )
    }

    func setPage(_ id: String, page: Int) {
        guard let index = data.items.firstIndex(where: { $0.id == id }) else { return }
        data.items[index].currentPage = min(max(0, page), data.items[index].book.pages)
        data.items[index].positionConfirmed = true
        data.items[index].updatedAt = stamp
        commit()
    }

    /// "Where are you?": records where the reader is, and where they began if no reading has been logged yet,
    /// so the first session's speed is measured from the right page.
    func confirmPosition(_ id: String, page: Int, mode: ProgressMode? = nil) {
        guard let index = data.items.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(0, page), data.items[index].book.pages)
        data.items[index].currentPage = clamped
        if sessionCount(for: id) == 0 { data.items[index].startPage = clamped }
        data.items[index].positionConfirmed = true
        if let mode { data.items[index].progressMode = mode }
        data.items[index].updatedAt = stamp
        commit()
    }

    /// Applies the answer to "Where are you?" for a book (the book may be on any shelf).
    func apply(_ position: StartingPosition, to id: String) {
        guard let item = item(id) else { return }
        if case .alreadyRead(let date) = position {
            markFinished(id)
            if let date, let index = data.items.firstIndex(where: { $0.id == id }) {
                data.items[index].finishedAt = date
                data.items[index].updatedAt = stamp
                commit()
            }
            return
        }
        guard let page = position.page(inBookOf: item.book.pages) else { return }
        confirmPosition(id, page: page, mode: position.progressMode)
    }

    func setProgressMode(_ id: String, _ mode: ProgressMode) {
        guard let index = data.items.firstIndex(where: { $0.id == id }), data.items[index].progressMode != mode else { return }
        data.items[index].progressMode = mode
        data.items[index].updatedAt = stamp
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
        data.items[index].updatedAt = stamp
        commit()
    }

    // MARK: - Preferences

    func updatePreferences(_ change: (inout ReadingPreferences) -> Void) {
        change(&data.preferences)
        data.preferences.dailyMinutes = min(240, max(0, data.preferences.dailyMinutes))
        data.preferences.wpm = ReadingSpeed.clamp(data.preferences.wpm)
        data.preferences.updatedAt = stamp
        commit()
    }

    func recordSpeedTest(_ result: SpeedTestResult) {
        data.speedTests.append(result)
        data.preferences.wpm = result.effectiveWPM
        data.preferences.updatedAt = stamp
        commit()
    }

    var latestSpeedTest: SpeedTestResult? { data.speedTests.last }

    // MARK: - Sessions

    @discardableResult
    func startSession(
        bookID: String,
        origin: SessionDevice = .phone,
        startedAt: Date = Date(),
        teaID: String? = nil,
        goalSeconds: Double? = nil,
        ambienceID: String? = nil
    ) -> ActiveSession? {
        if let active = data.activeSession { return active }
        guard let item = item(bookID) else { return nil }
        if item.shelf != .reading { move(bookID, to: .reading) }
        let session = ActiveSession(
            bookID: bookID,
            startedAt: startedAt,
            startPage: self.item(bookID)?.currentPage ?? 0,
            origin: origin,
            teaID: teaID,
            goalSeconds: goalSeconds,
            ambienceID: ambienceID
        )
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
            toPage: toPage,
            teaID: active.teaID,
            ambienceID: active.ambienceID,
            device: active.origin
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
        if sessionCount(for: session.bookID) == 0, data.items[index].startPage == 0 { data.items[index].startPage = logged.fromPage }
        data.sessions.append(logged)
        data.items[index].currentPage = max(data.items[index].currentPage, toPage)
        data.items[index].positionConfirmed = true
        data.items[index].updatedAt = stamp
        if data.items[index].shelf == .toRead || data.items[index].shelf == .paused {
            data.items[index].shelf = .reading
            data.items[index].pausedAt = nil
            data.items[index].order = nextOrder(on: .reading)
        }
        if data.items[index].startedAt == nil { data.items[index].startedAt = session.startedAt }
        if data.preferences.learnFromSessions,
           let observed = ReadingSpeed.observedWPM(pagesRead: logged.pagesRead, wordsPerPage: book.wordsPerPage, seconds: logged.seconds) {
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
        case .journalAdded(let bookID, let kind, let text, let page):
            addJournalEntry(bookID: bookID, kind: kind, text: text, page: page)
        case .pageSet(let bookID, let page):
            setPage(bookID, page: page)
        case .shelfChanged(let bookID, let shelf, let rating):
            if shelf == .finished {
                markFinished(bookID, rating: rating)
            } else {
                move(bookID, to: shelf)
            }
        case .addBook:
            // Needs the catalog, so the watch bridge resolves it and calls add(_:to:).
            break
        }
        return nil
    }

    /// "Read without the timer": logs minutes and the page reached.
    @discardableResult
    func logManual(bookID: String, minutes: Double, toPage: Int, at date: Date? = nil) -> SessionOutcome? {
        guard let item = item(bookID), minutes > 0 else { return nil }
        let seconds = minutes * 60
        let start = date ?? stamp.addingTimeInterval(-seconds)
        let session = ReadingSession(
            bookID: bookID, startedAt: start, seconds: seconds,
            fromPage: item.currentPage, toPage: toPage, kind: .manual, device: .phone
        )
        return log(session)
    }

    // MARK: - Reading times

    /// What each of the reader's reading times is for on `day` (today by default): which book, how long, which pages.
    func slotPlans(on day: PlanDay? = nil) -> [SlotPlan] {
        guard let day = day ?? plan.today else { return [] }
        return SlotPlanner.plan(day: day, slots: preferences.effectiveReadingSlots, calendar: calendar)
    }

    /// The next reading time today that hasn't started yet.
    var nextSlotToday: SlotPlan? {
        SlotPlanner.next(in: slotPlans(), day: plan.today?.date ?? now, now: now, calendar: calendar)
    }

    @discardableResult
    func addReadingSlot(hour: Int, minute: Int = 0, bookID: String? = nil, weekdays: Set<Int>? = nil, label: String? = nil) -> ReadingSlot {
        let slot = ReadingSlot(hour: hour, minute: minute, weekdays: weekdays, bookID: bookID, label: label)
        updatePreferences { prefs in
            // The first slot added carries over the single reminder time the reader already had.
            if prefs.readingSlots.isEmpty, prefs.reminderEnabled {
                prefs.readingSlots = [ReadingSlot(hour: prefs.reminderHour, minute: prefs.reminderMinute)]
            }
            prefs.readingSlots.append(slot)
            prefs.reminderEnabled = true
        }
        return slot
    }

    func updateReadingSlot(_ slot: ReadingSlot) {
        updatePreferences { prefs in
            var slots = prefs.effectiveReadingSlots
            if let index = slots.firstIndex(where: { $0.id == slot.id }) {
                slots[index] = slot
            } else {
                slots.append(slot)
            }
            prefs.readingSlots = slots
        }
    }

    func removeReadingSlot(_ id: UUID) {
        updatePreferences { prefs in
            var slots = prefs.effectiveReadingSlots
            slots.removeAll { $0.id == id }
            prefs.readingSlots = slots
            // No times left means no reminders, rather than quietly falling back to the old single time.
            if slots.isEmpty { prefs.reminderEnabled = false }
        }
    }

    // MARK: - Journal

    func journal(for bookID: String) -> [JournalEntry] {
        data.journal.filter { $0.bookID == bookID }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func addJournalEntry(bookID: String, kind: JournalEntry.Kind = .thought, text: String, page: Int? = nil, sessionID: UUID? = nil) -> JournalEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let book = item(bookID)?.book
        let entry = JournalEntry(
            bookID: bookID, bookTitle: book?.title ?? "", bookAuthor: book?.author ?? "",
            kind: kind, text: trimmed, page: page ?? item(bookID)?.currentPage, sessionID: sessionID, createdAt: stamp
        )
        data.journal.append(entry)
        commit()
        return entry
    }

    func updateJournalEntry(_ id: UUID, text: String? = nil, isFavorite: Bool? = nil) {
        guard let index = data.journal.firstIndex(where: { $0.id == id }) else { return }
        if let text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { data.journal[index].text = trimmed }
        }
        if let isFavorite { data.journal[index].isFavorite = isFavorite }
        data.journal[index].updatedAt = stamp
        commit()
    }

    func deleteJournalEntry(_ id: UUID) {
        guard data.journal.contains(where: { $0.id == id }) else { return }
        data.journal.removeAll { $0.id == id }
        addTombstone(.journal, id.uuidString)
        commit()
    }

    // MARK: - Challenges

    func joinChallenge(_ id: String, year: Int? = nil) {
        guard !data.challenges.contains(where: { $0.id == id && $0.year == year }) else { return }
        data.challenges.append(ChallengeEnrollment(id: id, joinedAt: stamp, year: year))
        clearTombstone(.challenge, id)
        commit()
    }

    func leaveChallenge(_ id: String, year: Int? = nil) {
        guard data.challenges.contains(where: { $0.id == id && $0.year == year }) else { return }
        data.challenges.removeAll { $0.id == id && $0.year == year }
        addTombstone(.challenge, id)
        commit()
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

    private func addTombstone(_ kind: Tombstone.Kind, _ key: String) {
        data.tombstones.removeAll { $0.kind == kind && $0.key == key }
        data.tombstones.append(Tombstone(kind: kind, key: key, deletedAt: stamp))
    }

    private func clearTombstone(_ kind: Tombstone.Kind, _ key: String) {
        data.tombstones.removeAll { $0.kind == kind && $0.key == key }
    }

    private func nextOrder(on shelf: Shelf) -> Double {
        (data.items.filter { $0.shelf == shelf }.map(\.order).max() ?? 0) + 1
    }

    private func applyOrder(_ ids: [String]) {
        for (position, id) in ids.enumerated() {
            if let index = data.items.firstIndex(where: { $0.id == id }), data.items[index].order != Double(position) {
                data.items[index].order = Double(position)
                data.items[index].updatedAt = stamp
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

extension SessionOutcome: Identifiable {
    var id: UUID { session.id }
}
