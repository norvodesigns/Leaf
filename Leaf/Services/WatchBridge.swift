import Foundation
import WatchConnectivity

/// Keeps the Apple Watch app in step with the phone: snapshots go out, sessions come back.
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    private weak var store: LibraryStore?
    private var pushTask: Task<Void, Never>?

    /// A session logged on the watch (so the phone can celebrate, too).
    var onRemoteOutcome: ((SessionOutcome) -> Void)?
    /// The latest forecast the phone worked out (Today and Plan both run one), for the wrist's Forecast page.
    var forecast: ForecastResult? {
        didSet { schedulePush() }
    }
    /// The greeting Today last showed and the day it showed it, so the wrist says the same thing.
    private var shownGreeting: (day: String, greeting: WatchGreeting)?
    /// What the watch sent before the library could be read (the iPhone not yet unlocked since it restarted): a
    /// session logged then would find no book to log against. Applied by `applyHeldEvents()` once it can.
    private var heldEvents: [SyncEvent] = []

    func noteGreeting(_ greeting: Greeting, now: Date, calendar: Calendar) {
        let line = WatchGreeting(headline: greeting.headline, subline: greeting.subline)
        let day = GreetingMemoryStore.dayKey(now, calendar: calendar)
        guard shownGreeting?.day != day || shownGreeting?.greeting != line else { return }
        shownGreeting = (day, line)
        schedulePush()
    }

    func greeting(on now: Date, calendar: Calendar) -> WatchGreeting? {
        guard let shownGreeting, shownGreeting.day == GreetingMemoryStore.dayKey(now, calendar: calendar) else { return nil }
        return shownGreeting.greeting
    }

    func activate(store: LibraryStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    func push() {
        // Until the library is read, the store holds an empty stand-in; the watch keeps what it last had instead.
        guard WCSession.isSupported(), let store, !store.isLoadDeferred else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let payload = SyncCodec.encode(store.watchSnapshot(), key: SyncCodec.snapshotKey)
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    /// Applies what the watch sent while the library couldn't be read yet. Call it once the store has loaded.
    func applyHeldEvents() {
        guard let store, !store.isLoadDeferred, !heldEvents.isEmpty else { return }
        let events = heldEvents
        heldEvents = []
        events.forEach(receive)
    }

    private func receive(_ event: SyncEvent) {
        if store?.isLoadDeferred == true {
            heldEvents.append(event)
            return
        }
        if case .addBook(let query) = event {
            addDictatedBook(query)
            return
        }
        if let outcome = store?.apply(event) { onRemoteOutcome?(outcome) }
        push()
    }

    /// A title dictated on the wrist: take the catalog's best match and put it at the end of To read.
    private func addDictatedBook(_ query: String) {
        Task { [weak self] in
            await BookCatalog.shared.load()
            guard let self, let store = self.store, let match = BookCatalog.shared.search(query, limit: 1).first else { return }
            if store.item(match.id) == nil { store.add(match, to: .toRead) }
            self.push()
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let event = SyncCodec.decode(SyncEvent.self, from: message, key: SyncCodec.eventKey) else { return }
        Task { @MainActor in self.receive(event) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let event = SyncCodec.decode(SyncEvent.self, from: message, key: SyncCodec.eventKey)
        replyHandler([:])
        guard let event else { return }
        Task { @MainActor in self.receive(event) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let event = SyncCodec.decode(SyncEvent.self, from: userInfo, key: SyncCodec.eventKey) else { return }
        Task { @MainActor in self.receive(event) }
    }
}

extension LibraryStore {
    /// The compact view of today that the watch shows.
    func watchSnapshot() -> WatchSnapshot {
        let today = todayAssignments.map { pair in
            WatchAssignment(bookID: pair.item.id, title: pair.item.book.title, minutes: pair.assignment.minutes, fromPage: pair.assignment.fromPage, toPage: pair.assignment.toPage)
        }
        var books = Array(reading.prefix(8))
        // A live session's book always goes to the watch, even past the first eight or off the Reading shelf.
        if let active = activeSession, !books.contains(where: { $0.id == active.bookID }), let item = item(active.bookID) {
            books.append(item)
        }
        if books.isEmpty, let next = toRead.first { books = [next] }
        let watchBooks = books.map { item in
            WatchBook(
                id: item.id,
                title: item.book.title,
                author: item.book.author,
                currentPage: item.currentPage,
                pages: item.book.pages,
                wordsPerPage: item.book.wordsPerPage,
                paletteSeed: item.book.paletteSeed,
                finish: plan.book(item.id)?.finish
            )
        }
        let days = week.map { WatchDay(date: $0.date, minutes: $0.minutes, goal: preferences.dailyMinutes, isReadingDay: $0.isReadingDay) }
        // The nook on the wrist: the greeting Today showed (or today's own line), the tea for the hour, each book's
        // forecast sentence and the year's pacing. A light brief: no catalog picks.
        let brief = TodayBriefBuilder.build(TodayBriefInput(data: data, plan: plan, now: now, calendar: calendar))
        // The cabinet's best tea for the hour when the reader keeps one, so the wrist steeps what they have.
        let offer = teaChoices(limit: 1)
        let watchTea = offer.fromCabinet ? (offer.teas.first ?? brief.tea) : brief.tea
        let narrator = ForecastNarrator(now: now, calendar: calendar)
        let forecast = WatchBridge.shared.forecast
        let forecasts = watchBooks.compactMap { book -> WatchForecast? in
            guard let bookForecast = forecast?.book(book.id) else { return nil }
            return WatchForecast(bookID: book.id, sentence: narrator.bookSentence(bookForecast), median: bookForecast.median)
        }
        let yearGoal = brief.yearGoal.flatMap { pacing -> WatchYearGoal? in
            guard let goal = pacing.goal else { return nil }
            let sentence = forecast.map { narrator.yearSentence($0.year) } ?? pacing.sentence
            return WatchYearGoal(year: pacing.year, finished: pacing.finished, goal: goal, sentence: sentence)
        }
        return WatchSnapshot(
            generatedAt: Date(),
            dailyMinutes: preferences.dailyMinutes,
            minutesReadToday: minutesReadToday,
            isReadingDay: isReadingDay,
            streak: streak,
            wpm: wpm,
            today: today,
            reading: Array(watchBooks),
            week: days,
            activeSession: activeSession,
            hasOnboarded: hasOnboarded,
            greeting: WatchBridge.shared.greeting(on: now, calendar: calendar)
                ?? WatchGreeting(headline: brief.greeting.headline, subline: brief.greeting.subline),
            tea: WatchTea(id: watchTea.id, name: watchTea.name, steepSeconds: TeaSuggester.steepSeconds(for: watchTea, strength: CozySettings.teaStrength)),
            cupMinutes: preferences.cupMinutes,
            queue: toRead.prefix(5).map { item in
                WatchBook(id: item.id, title: item.book.title, author: item.book.author, currentPage: item.currentPage, pages: item.book.pages, wordsPerPage: item.book.wordsPerPage, paletteSeed: item.book.paletteSeed, finish: plan.book(item.id)?.finish)
            },
            forecasts: forecasts,
            yearGoal: yearGoal,
            liveActivities: preferences.liveActivities,
            slots: slotPlans().compactMap { slotPlan in
                guard let part = slotPlan.parts.first, let item = item(part.bookID) else { return nil }
                return WatchSlot(id: slotPlan.slot.id, minuteOfDay: slotPlan.slot.minuteOfDay, label: slotPlan.slot.label, bookID: part.bookID, title: item.book.title, minutes: slotPlan.minutes, fromPage: part.fromPage, toPage: slotPlan.parts.last?.toPage ?? part.toPage)
            },
            liveActivitySessionID: LiveActivityController.shared.sessionShown
        )
    }
}

extension YearGoalPacing {
    /// "Two books ahead of a steady pace." The plain-arithmetic line, for when no forecast has run yet.
    var sentence: String {
        let ahead = booksAheadOrBehind
        switch status {
        case .reached:
            return "Goal reached. Everything from here is a gift."
        case .ahead:
            return ahead == 1 ? "A book ahead of a steady pace." : "\(ahead) books ahead of a steady pace."
        case .onTrack:
            return "Right on a steady pace, \(remaining) to go."
        case .behind:
            return "A little behind a steady pace. Shorter books count just the same."
        case .noGoal:
            return "No goal set."
        }
    }
}
