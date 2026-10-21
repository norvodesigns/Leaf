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
    @ObservationIgnored private let writer: LibraryWriter
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Bumped for every write, so a slow save of an older snapshot can never land after a newer one.
    @ObservationIgnored private var saveGeneration = 0
    /// True while the saved library couldn't be read yet (Leaf was woken before the first unlock after a restart).
    /// Nothing is written until `loadIfDeferred()` has read it, so the empty stand-in can never replace it.
    @ObservationIgnored private(set) var isLoadDeferred = false
    @ObservationIgnored var calendar: Calendar = .current
    /// iCloud sync, when the build has it. Every local change is reported to it as a diff against `syncShadow`.
    @ObservationIgnored var sync: CloudSync?
    @ObservationIgnored private var syncShadow: LeafData
    /// Wall-clock time for change stamps (iCloud merging compares these), kept apart from `now` so tests can control it.
    @ObservationIgnored var clock: () -> Date = { Date() }
    private var stamp: Date { clock() }

    init(persistence: Persistence = .shared, now: Date = Date()) {
        self.persistence = persistence
        self.writer = LibraryWriter(persistence: persistence)
        self.now = now
        // Earlier read-throughs that older versions didn't keep are recovered from sessions. Every device recovers the
        // same ones, so they aren't sent anywhere until the book next changes.
        let loaded: LeafData
        switch persistence.loadLibrary() {
        case .library(let value): loaded = value.withRecoveredReads()
        case .nothing: loaded = LeafData()
        case .unavailable:
            loaded = LeafData()
            isLoadDeferred = true
        }
        self.data = loaded
        self.syncShadow = loaded
        recomputePlan()
    }

    /// Reads the library if the launch couldn't (see `isLoadDeferred`). Call it when protected data becomes
    /// available and when the app comes to the front. True when the library was read just now.
    @discardableResult
    func loadIfDeferred() -> Bool {
        guard isLoadDeferred else { return false }
        let loaded: LeafData
        switch persistence.loadLibrary() {
        case .unavailable: return false
        case .library(let value): loaded = value.withRecoveredReads()
        case .nothing: loaded = LeafData()
        }
        isLoadDeferred = false
        // Anything changed in the meantime was made against an empty stand-in, so the saved library replaces it.
        saveTask?.cancel()
        data = loaded
        syncShadow = loaded
        recomputePlan()
        onChange?()
        return true
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
        // Leaving Finished (to read it again, or to put it back on a shelf) keeps the finish as a read-through.
        data.items[index] = data.items[index].keepingCurrentRead(now: stamp)
        data.items[index].shelf = shelf
        data.items[index].order = nextOrder(on: shelf)
        data.items[index].updatedAt = stamp
        data.items[index].pausedAt = shelf == .paused ? now : nil
        switch shelf {
        case .reading:
            if data.items[index].startedAt == nil { data.items[index].startedAt = now }
            data.items[index].finishedAt = nil
            if data.items[index].currentPage >= data.items[index].book.pages {
                // Reading it again: a fresh start, so the merge doesn't pull the page back to the last read-through.
                data.items[index].currentPage = 0
                data.items[index].startPage = 0
                data.items[index].startedAt = now
            }
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

    /// Puts To read in a suggested order the reader accepted. Books the order doesn't name keep their places after it.
    func applyQueueOrder(_ ids: [String]) {
        let shelf = data.items(on: .toRead).map(\.id)
        let named = ids.filter { shelf.contains($0) }
        applyOrder(named + shelf.filter { !named.contains($0) })
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

    /// Another printing of the same book: the words stay the same and only the page count changes. The count it
    /// had stays on offer, and a reader who tracks percent keeps their place by share rather than by page number.
    func switchEdition(_ id: String, pages: Int) {
        guard pages > 0, let index = data.items.firstIndex(where: { $0.id == id }) else { return }
        var item = data.items[index]
        let old = item.book.pages
        guard pages != old else { return }
        var counts = item.book.pageCounts ?? []
        if old > 0, !counts.contains(old) { counts.append(old) }
        item.book.pageCounts = counts
        item.book.pages = pages
        if item.progressMode == .percent, old > 0 {
            let scale = Double(pages) / Double(old)
            item.currentPage = min(pages, Int((Double(item.currentPage) * scale).rounded()))
            item.startPage = min(pages, Int((Double(item.startPage) * scale).rounded()))
        } else {
            item.currentPage = min(item.currentPage, pages)
        }
        item.updatedAt = stamp
        data.items[index] = item
        commit()
    }

    // MARK: - Preferences

    func updatePreferences(_ change: (inout ReadingPreferences) -> Void) {
        let before = data.preferences
        change(&data.preferences)
        data.preferences.dailyMinutes = min(240, max(0, data.preferences.dailyMinutes))
        data.preferences.wpm = ReadingSpeed.clamp(data.preferences.wpm)
        // Device-only settings (haptics, appearance, the sync switch) shouldn't win a merge against a real change elsewhere.
        if !before.hasSameSyncedFields(as: data.preferences) { data.preferences.updatedAt = stamp }
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
        // A number JSON can't hold (from a damaged watch message, say) would make every later save of the library fail.
        guard session.seconds.isFinite, session.startedAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
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
        guard let item = item(bookID), minutes > 0, minutes.isFinite else { return nil }
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

    // MARK: - Backups

    /// Merges a backup in, by iCloud's rules: what's missing is added, anything newer here stays, and the live session
    /// and this device's own settings are kept. The changes then sync like any other.
    func importBackup(_ backup: LeafData) {
        data = LeafBackup.merge(backup.withRecoveredReads(), into: data, now: stamp)
        commit()
    }

    // MARK: - Read-throughs

    /// Rates one read-through. The current one (a book on Finished) is the book's own rating.
    func setReadRating(_ bookID: String, readID: UUID, rating: Int?) {
        guard let index = data.items.firstIndex(where: { $0.id == bookID }) else { return }
        if let readIndex = data.items[index].reads.firstIndex(where: { $0.id == readID }) {
            data.items[index].reads[readIndex].rating = rating.map { min(5, max(1, $0)) }
            data.items[index].reads[readIndex].updatedAt = stamp
            data.items[index].updatedAt = stamp
            commit()
        } else if data.items[index].readThroughs.last?.id == readID, data.items[index].shelf == .finished {
            setRating(bookID, rating: rating)
        }
    }

    /// Adds a read-through from before Leaf ("I read this in 2019"). Ignored when one already ends that day.
    func addEarlierRead(_ bookID: String, startedAt: Date?, finishedAt: Date, rating: Int? = nil) {
        guard let index = data.items.firstIndex(where: { $0.id == bookID }) else { return }
        let day = calendar.startOfDay(for: finishedAt)
        guard !data.items[index].readThroughs.contains(where: { calendar.startOfDay(for: $0.finishedAt) == day }) else { return }
        let read = ReadThrough(bookID: bookID, startedAt: startedAt, finishedAt: finishedAt, rating: rating, updatedAt: stamp)
        data.items[index].reads.append(read)
        data.items[index].reads.sort(by: ReadThrough.isEarlier)
        data.items[index].updatedAt = stamp
        clearTombstone(.read, read.id.uuidString)
        commit()
    }

    /// Takes an earlier read-through off a book. The current one goes by moving the book off Finished.
    func removeRead(_ bookID: String, readID: UUID) {
        guard let index = data.items.firstIndex(where: { $0.id == bookID }),
              data.items[index].reads.contains(where: { $0.id == readID }) else { return }
        data.items[index].reads.removeAll { $0.id == readID }
        data.items[index].updatedAt = stamp
        addTombstone(.read, readID.uuidString)
        commit()
    }

    // MARK: - Tea

    /// A tea by the id a session saved: one of the reader's own (or their tin of a catalog tea), else the catalog's.
    func tea(id: String?) -> Tea? {
        TeaShelf.tea(id: id, cabinet: data.cabinet)
    }

    /// Pins a tea as the book's pairing; nil unpins it.
    func setPairedTea(_ bookID: String, teaID: String?) {
        guard let index = data.items.firstIndex(where: { $0.id == bookID }), data.items[index].pairedTeaID != teaID else { return }
        data.items[index].pairedTeaID = teaID
        data.items[index].updatedAt = stamp
        commit()
    }

    /// Adds a tea to the cabinet. A catalog tea is kept once: adding it again puts the tin back in stock.
    @discardableResult
    func addCabinetTea(_ tea: CabinetTea) -> CabinetTea {
        if let catalogID = tea.catalogID, let kept = data.cabinet.first(where: { $0.catalogID == catalogID && !$0.isOutOf }) {
            return kept
        }
        if let catalogID = tea.catalogID, let index = data.cabinet.firstIndex(where: { $0.catalogID == catalogID }) {
            // Every tin of it has run out: this one is back in stock.
            data.cabinet[index].isOutOf = false
            data.cabinet[index].updatedAt = stamp
            commit()
            return data.cabinet[index]
        }
        var added = tea
        added.name = tea.name.trimmingCharacters(in: .whitespacesAndNewlines)
        added.addedAt = stamp
        added.updatedAt = added.addedAt
        data.cabinet.append(added)
        clearTombstone(.cabinetTea, added.id.uuidString)
        commit()
        return added
    }

    /// Saves edits to a tea in the cabinet (name, brand, notes, steep time, rating, stock).
    func updateCabinetTea(_ tea: CabinetTea) {
        guard let index = data.cabinet.firstIndex(where: { $0.id == tea.id }) else { return }
        var updated = tea
        updated.name = tea.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.addedAt = data.cabinet[index].addedAt
        updated.updatedAt = data.cabinet[index].updatedAt
        guard updated != data.cabinet[index] else { return }
        updated.updatedAt = stamp
        data.cabinet[index] = updated
        commit()
    }

    func setOutOf(_ id: UUID, _ isOutOf: Bool) {
        guard let index = data.cabinet.firstIndex(where: { $0.id == id }), data.cabinet[index].isOutOf != isOutOf else { return }
        data.cabinet[index].isOutOf = isOutOf
        data.cabinet[index].updatedAt = stamp
        commit()
    }

    /// Takes a tea out of the cabinet. Sessions and tasting notes keep its name.
    func removeCabinetTea(_ id: UUID) {
        guard data.cabinet.contains(where: { $0.id == id }) else { return }
        data.cabinet.removeAll { $0.id == id }
        addTombstone(.cabinetTea, id.uuidString)
        commit()
    }

    /// The tasting note written after a session, if there is one.
    func tasting(forSession id: UUID) -> TastingNote? {
        data.tastings.first { $0.sessionID == id }
    }

    /// Writes (or rewrites) the tasting note for a session's cup.
    @discardableResult
    func saveTasting(
        sessionID: UUID?,
        teaID: String,
        bookID: String?,
        strength: TastingStrength?,
        aromas: [String],
        rating: Int?,
        text: String = ""
    ) -> TastingNote {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sessionID, let index = data.tastings.firstIndex(where: { $0.sessionID == sessionID }) {
            var note = data.tastings[index]
            note.strength = strength
            note.aromas = aromas
            note.rating = rating.map { min(5, max(1, $0)) }
            note.text = trimmed
            guard note != data.tastings[index] else { return note }
            note.updatedAt = stamp
            data.tastings[index] = note
            commit()
            return note
        }
        let tea = self.tea(id: teaID)
        let note = TastingNote(
            teaID: teaID, teaName: tea?.name ?? "", family: tea?.family, bookID: bookID, sessionID: sessionID,
            strength: strength, aromas: aromas, rating: rating, text: trimmed, createdAt: stamp
        )
        data.tastings.append(note)
        clearTombstone(.tasting, note.id.uuidString)
        commit()
        return note
    }

    func deleteTasting(_ id: UUID) {
        guard data.tastings.contains(where: { $0.id == id }) else { return }
        data.tastings.removeAll { $0.id == id }
        addTombstone(.tasting, id.uuidString)
        commit()
    }

    // MARK: - Challenges

    func joinChallenge(_ id: String, year: Int? = nil) {
        guard !data.challenges.contains(where: { $0.id == id && $0.year == year }) else { return }
        data.challenges.append(ChallengeEnrollment(id: id, joinedAt: stamp, year: year))
        clearTombstone(.challenge, SyncKey.challengeTombstoneKey(id: id, year: year))
        commit()
    }

    func leaveChallenge(_ id: String, year: Int? = nil) {
        guard data.challenges.contains(where: { $0.id == id && $0.year == year }) else { return }
        data.challenges.removeAll { $0.id == id && $0.year == year }
        addTombstone(.challenge, SyncKey.challengeTombstoneKey(id: id, year: year))
        commit()
    }

    // MARK: - Day changes, reset

    func refreshDay(_ date: Date = Date()) {
        now = date
        recomputePlan()
        onChange?()
    }

    func resetEverything() {
        // Nothing of the erased library stays on this phone: not the file, its rolling backup (which the next save
        // would otherwise refresh from the old file), or a damaged copy set aside.
        saveTask?.cancel()
        saveGeneration += 1
        writer.erase(generation: saveGeneration)
        isLoadDeferred = false
        data = LeafData()
        syncShadow = data
        recomputePlan()
        scheduleSave()
        onChange?()
        // Not reported as a diff (that would read as deleting everything); the cloud copy is cleared separately.
        if let sync {
            Task { @MainActor [weak self] in
                // If iCloud couldn't clear its copy, syncing again now would bring the library straight back; the
                // error stays in Settings instead. (A retry that survives relaunch belongs in CloudSync.)
                guard await sync.deleteCloudData() else { return }
                if let data = self?.data { sync.start(initial: data) }
            }
        }
    }

    /// Takes data merged from iCloud. Written to disk before returning, so the sync engine never remembers a
    /// fetch position that is ahead of what is saved.
    func applyRemote(merged: LeafData) {
        data = merged
        syncShadow = merged
        recomputePlan()
        flush()
        onChange?()
    }

    /// Replaces all data (demo seeding and screenshot runs).
    func replaceAll(with newData: LeafData) {
        data = newData
        commit()
    }

    /// Writes immediately (when the app moves to the background).
    func flush() {
        guard !isLoadDeferred else { return }
        saveTask?.cancel()
        saveGeneration += 1
        writer.save(data, generation: saveGeneration)
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
        let previous = syncShadow
        syncShadow = data
        sync?.localDataChanged(old: previous, new: data)
    }

    private func scheduleSave() {
        guard !isLoadDeferred else { return }
        saveTask?.cancel()
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = data
        let writer = writer
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            writer.save(snapshot, generation: generation)
        }
    }
}

extension SessionOutcome: Identifiable {
    var id: UUID { session.id }
}
