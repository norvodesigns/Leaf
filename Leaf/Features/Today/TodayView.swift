import SwiftUI

/// Today (NEXT.md section 4): the launchpad for the next ten minutes of reading. The Reading Nook on top (the day's
/// light, the greeting, the book beside a cup that fills as you read, and "Steep and read"), then a stack of cards
/// for anyone who wants more: where you left off, today's reading times, the forecast, the week as tea rings, the
/// year, a pick, challenges, a line from the journal, and gentle nudges.
///
/// Everything comes from `store.todayBrief(catalog:forecast:weather:)`, worked out when the library changes rather
/// than on every render. The greeting is pinned for the day (and mode) so it never flickers.
struct TodayView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(BookCatalog.self) private var catalog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var forecast = ForecastService()
    @State private var brief: TodayBrief?
    @State private var pinned: PinnedGreeting?
    @State private var steep: TeaSteepState? = TeaSteepState.load()
    @State private var steepReady = false
    @State private var chosenTeaID: String?
    @State private var quoteCardEntry: JournalEntry?
    /// Where the scroll view's content begins below the screen's top edge, so the nook's light can reach up to it.
    @State private var topInset: CGFloat = 0
    @State private var cardsUnderClock = false
    /// The year whose Wrapped offer was put off with "Not now".
    @AppStorage("wrapped.putOffYear") private var wrappedPutOff = 0
    /// The deck stays on Today while the reader is swiping, even once a kept book means they're no longer between books.
    @State private var keepsDeckOpen = false
    @State private var didStageScroll = false

    /// Today's cards, in the order a mode wants them. The raw values are the `-LeafScroll` names.
    enum CardKind: String, Hashable, CaseIterable {
        case nudges, deck, leftOff = "leftoff", desk, times, forecast, teaWeek = "teaweek", week, year, pick, challenges, quote, wrapped
    }

    private struct PinnedGreeting {
        var day: String
        var mode: TodayMode
        var greeting: Greeting
    }

    private struct ItemKey: Hashable {
        var id: String
        var shelf: Shelf
        var page: Int
        var confirmed: Bool
        var mode: ProgressMode
    }

    /// What the brief and the forecast are worked out from. When any of it changes they are worked out again.
    private struct DataKey: Hashable {
        var now: Date
        var items: [ItemKey]
        var sessions: Int
        var journal: Int
        var challenges: Int
        var dismissed: Int
        var preferences: ReadingPreferences
    }

    private struct BriefKey: Hashable {
        var data: DataKey
        var live: UUID?
        var catalogReady: Bool
        var forecastReady: Bool
        var forecastWorking: Bool
    }

    private var dataKey: DataKey {
        DataKey(
            now: store.now,
            items: store.data.items.map { ItemKey(id: $0.id, shelf: $0.shelf, page: $0.currentPage, confirmed: $0.positionConfirmed, mode: $0.progressMode) },
            sessions: store.data.sessions.count,
            journal: store.data.journal.count,
            challenges: store.data.challenges.count,
            dismissed: store.data.dismissed.count,
            preferences: store.preferences
        )
    }

    private var briefKey: BriefKey {
        BriefKey(
            data: dataKey,
            live: store.activeSession?.id,
            catalogReady: catalog.isLoaded,
            forecastReady: forecast.result != nil,
            forecastWorking: forecast.isWorking
        )
    }

    // MARK: Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let brief {
                        nook(brief)
                        cards(brief)
                            .leafMargins()
                            .padding(.top, Space.l)
                    } else {
                        Color.clear
                            .frame(height: 480)
                    }
                }
                .padding(.bottom, Space.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .coachMarks(.today)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentInsets.top
            } action: { _, inset in
                topInset = inset
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 160
            } action: { _, scrolled in
                withAnimation(.easeOut(duration: 0.2)) { cardsUnderClock = scrolled }
            }
            // Once the nook has scrolled away, a band of paper under the clock, so cards don't read through it.
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Color.paper.frame(height: max(0, topInset - Space.xl))
                    LinearGradient(colors: [Color.paper, Color.paper.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: Space.xl * 2)
                }
                .ignoresSafeArea(edges: .top)
                .opacity(cardsUnderClock ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.shared.tap()
                        router.showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task(id: briefKey) {
                refreshBrief()
            }
            .task(id: dataKey) {
                forecast.refresh(from: store)
            }
            .task(id: steep?.startedAt) {
                await waitForTea()
            }
            .task(id: brief == nil) {
                await stageScroll(proxy)
            }
            .onAppear {
                steep = TeaSteepState.load()
            }
            .onChange(of: router.showSession) { _, showing in
                // A pot may have been poured, or the cup started, in the session screen.
                if !showing { steep = TeaSteepState.load() }
            }
            .sheet(item: $quoteCardEntry) { entry in
                QuoteCardSheet(initialEntryID: entry.id)
            }
            .onChange(of: brief?.mode) { old, new in
                guard new == .goalMet, old == .reading, router.lastOutcome == nil, !router.showSession else { return }
                Haptics.shared.play(.goalReached)
            }
        }
    }

    // MARK: Nook

    private func nook(_ brief: TodayBrief) -> some View {
        TodayNook(
            brief: brief,
            daypart: Daypart.of(store.now, calendar: store.calendar),
            dateline: LeafFormat.format(store.now, template: "EEEEdMMMM", calendar: store.calendar),
            issueNumber: store.issueNumber,
            issueSpoken: issueSpoken,
            tea: chosenTea(brief),
            steepSeconds: TeaSuggester.steepSeconds(for: chosenTea(brief), strength: CozySettings.teaStrength),
            teaChoices: teaChoices(brief),
            action: nookAction(brief),
            readingBooks: store.reading,
            actions: NookActions(
                steep: { beginSteep() },
                start: { startFromNook() },
                startWithoutTea: { start(bookID: self.brief?.current?.item.id) },
                startBook: { start(bookID: $0) },
                pourOut: { pourOut() },
                chooseTea: { tea in
                    Haptics.shared.selection()
                    chosenTeaID = tea.id
                },
                findBook: { router.tab = .search },
                openBook: { router.open($0) },
                readingTimes: { router.showReadingTimes = true }
            ),
            topInset: topInset
        )
    }

    private var issueSpoken: String {
        let number = store.issueNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        let ordinal = formatter.string(from: NSNumber(value: number)) ?? "\(number)"
        return "Issue \(number), your \(ordinal) day with Leaf"
    }

    private func nookAction(_ brief: TodayBrief) -> NookAction {
        if store.activeSession != nil { return .live }
        if let steep {
            return steepReady || steep.isReady(at: Date()) ? .ready(steep) : .steeping(steep)
        }
        switch brief.mode {
        case .brandNew: return .findBook(firstEver: true)
        case .betweenBooks: return .findBook(firstEver: false)
        case .goalMet: return .readMore
        case .restDay: return .restDay
        case .reading: return .steep
        }
    }

    // MARK: Tea

    /// The reader's pick, else the book's pinned pairing when it suits the hour, else the cabinet's best for the
    /// hour, else today's tea.
    private func chosenTea(_ brief: TodayBrief) -> Tea {
        // A pick made earlier stands only while it can still be made (not run out, not too strong for the hour).
        if let tea = store.offerableTea(chosenTeaID) { return tea }
        if let tea = store.offerableTea(brief.current?.item.pairedTeaID) { return tea }
        let offer = store.teaChoices(limit: 6)
        if offer.fromCabinet, let first = offer.teas.first { return first }
        return brief.tea
    }

    private func teaChoices(_ brief: TodayBrief) -> [Tea] {
        var teas = store.teaChoices(limit: 6, for: brief.current?.item.id).teas
        let chosen = chosenTea(brief)
        if !teas.contains(where: { $0.id == chosen.id }) { teas.insert(chosen, at: 0) }
        return teas
    }

    /// "Steep and read" opens the session screen at the tea: pick, pour, steep, then a cup-length read.
    private func beginSteep() {
        guard let brief, let bookID = brief.current?.item.id else { return }
        ReadingSessionLauncher.beginRitual(
            bookID: bookID, teaID: chosenTea(brief).id, store: store, router: router,
            from: ReadingSessionLauncher.heroSource
        )
    }

    /// The tea is poured: read one cup of the book it was poured for.
    private func startFromNook() {
        guard let steep else {
            start(bookID: brief?.current?.item.id)
            return
        }
        let ritual = TeaRitual.plan(tea: steep.tea, cupMinutes: store.preferences.cupMinutes)
        let bookID = steep.bookID ?? brief?.current?.item.id
        pourOut(animated: false)
        start(bookID: bookID, teaID: ritual.teaID, goalSeconds: ritual.goalSeconds)
    }

    private func pourOut(animated: Bool = true) {
        let change = {
            steep = nil
            steepReady = false
        }
        if animated {
            withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion), change)
        } else {
            change()
        }
        TeaSteepState.save(nil)
    }

    /// Waits out the steep, then says so with `teaReady`. Nothing plays a sound.
    private func waitForTea() async {
        guard let pot = steep else {
            steepReady = false
            return
        }
        let wait = pot.readyAt.timeIntervalSinceNow
        guard wait > 0 else {
            steepReady = true
            return
        }
        steepReady = false
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled, steep == pot else { return }
        withAnimation(Motion.resolved(Motion.board, reduceMotion: reduceMotion)) {
            steepReady = true
        }
        Haptics.shared.play(.teaReady)
    }

    private func start(bookID: String?, teaID: String? = nil, goalSeconds: Double? = nil) {
        ReadingSessionLauncher.start(
            bookID: bookID, store: store, router: router, from: ReadingSessionLauncher.heroSource,
            teaID: teaID, goalSeconds: goalSeconds
        )
    }

    // MARK: Cards

    private func cards(_ brief: TodayBrief) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(Array(cardOrder(brief).enumerated()), id: \.element) { index, kind in
                card(kind, brief: brief)
                    .id(kind)
                    .inkIn(min(index + 4, 6))
            }
        }
    }

    private func cardOrder(_ brief: TodayBrief) -> [CardKind] {
        // Today answers "what now?" (REDESIGN.md §2): today's reading times, where you left off, one nudge, the
        // forecast's sentence. The week, the year, challenges, quotes and picks live one tap away on You.
        var order: [CardKind]
        switch brief.mode {
        case .reading:
            order = [.times, .leftOff, .nudges, .wrapped, .forecast, .desk]
        case .goalMet:
            order = [.times, .leftOff, .wrapped, .forecast, .desk, .nudges]
        case .restDay:
            order = [.wrapped, .times, .leftOff, .nudges]
        case .betweenBooks:
            order = [.deck, .wrapped, .nudges, .times]
        case .brandNew:
            order = [.deck, .times]
        }
        if keepsDeckOpen, !order.contains(.deck) { order.insert(.deck, at: 0) }
        return order.filter { hasContent($0, brief: brief) }
    }

    private func hasContent(_ kind: CardKind, brief: TodayBrief) -> Bool {
        switch kind {
        case .nudges: return !brief.nudges.isEmpty
        case .deck: return catalog.isLoaded
        case .leftOff: return brief.current != nil
        case .desk: return !otherReading(brief).isEmpty
        case .times: return true
        case .forecast: return brief.forecastSentence != nil
        case .teaWeek: return teaOfTheWeek != nil
        case .week: return brief.mode != .brandNew
        case .year: return brief.yearGoal != nil
        case .pick: return !brief.picks.isEmpty && [TodayMode.reading, .goalMet, .restDay].contains(brief.mode)
        case .challenges: return !brief.challenges.isEmpty
        case .quote: return brief.quote != nil
        case .wrapped: return wrappedYear != nil
        }
    }

    /// December and the first week of January: the year's story, until it is put off for the year.
    private var wrappedYear: Int? {
        let year = router.wrappedStage == "offer"
            ? store.calendar.component(.year, from: store.now)
            : WrappedOffer.offeredYear(now: store.now, calendar: store.calendar)
        guard let year, year != wrappedPutOff, WrappedOffer.hasStory(data: store.data, year: year, calendar: store.calendar) else { return nil }
        return year
    }

    /// The week's book and its tea, from the forecast and the pairing.
    private var teaOfTheWeek: TeaAndBook? {
        TeaOfTheWeek.pick(data: store.data, forecast: forecast.result, now: store.now, calendar: store.calendar)
    }

    private func otherReading(_ brief: TodayBrief) -> [LibraryItem] {
        store.reading.filter { $0.id != brief.current?.item.id }
    }

    @ViewBuilder
    private func card(_ kind: CardKind, brief: TodayBrief) -> some View {
        switch kind {
        case .nudges:
            VStack(spacing: Space.s) {
                ForEach(brief.nudges.prefix(1)) { nudge in
                    NudgeCard(nudge: nudge, actions: nudgeActions(nudge))
                }
            }
        case .deck:
            TodayDeckCard(
                isFirstShelf: brief.mode == .brandNew,
                onSwiped: { keepsDeckOpen = true },
                onDone: {
                    withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) { keepsDeckOpen = false }
                }
            )
        case .leftOff:
            if let current = brief.current {
                LeftOffCard(
                    today: current,
                    mode: brief.mode,
                    minutesToGoal: brief.minutesToGoal,
                    minutesReadToday: brief.minutesReadToday,
                    finish: store.plan.book(current.item.id)?.finish,
                    calendar: store.calendar,
                    onPosition: { router.askPosition(for: current.item.id) },
                    onOpen: { router.open(current.item.book) }
                )
            }
        case .desk:
            DeskCard(
                items: otherReading(brief),
                onPosition: { router.askPosition(for: $0.id) },
                onOpen: { router.open($0.book) }
            )
        case .times:
            ReadingTimesCard(
                plans: store.isReadingDay ? brief.slots : [],
                quietSlots: quietSlots(brief),
                hasAnySlots: !store.preferences.effectiveReadingSlots.isEmpty,
                nextSlotID: brief.nextSlot?.id,
                now: store.now,
                calendar: store.calendar,
                title: { store.item($0)?.book.title },
                onEdit: { router.showReadingTimes = true },
                onStart: { start(bookID: $0) }
            )
            .coachMarkAnchor("today.times")
        case .forecast:
            if let sentence = brief.forecastSentence {
                ForecastCard(sentence: sentence) {
                    router.planSection = .forecast
                    router.tab = .plan
                }
            }
        case .teaWeek:
            if let pick = teaOfTheWeek {
                let book = store.item(pick.bookID)?.book
                TeaWeekCard(
                    pick: pick,
                    book: book,
                    onSteep: {
                        // The week's tea when it suits the hour; otherwise the ritual opens on the book's best
                        // pairing among the teas it can offer now (no strong black tea at midnight).
                        let suits = store.offerableTea(pick.tea.id) != nil
                        _ = ReadingSessionLauncher.beginRitual(
                            bookID: pick.bookID, teaID: suits ? pick.tea.id : nil, store: store, router: router,
                            from: ReadingSessionLauncher.heroSource
                        )
                    },
                    onOpen: { if let book { router.open(book) } },
                    onCabinet: { router.teaPage = .cabinet }
                )
            }
        case .week:
            WeekCard(days: brief.week, goalMinutes: brief.goalMinutes, streak: brief.streak, cupMinutes: brief.cupMinutes)
        case .year:
            if let pacing = brief.yearGoal {
                YearGoalCard(pacing: pacing, forecastSentence: yearForecastSentence)
            }
        case .pick:
            if let pick = brief.picks.first {
                PickCard(
                    pick: pick,
                    wpm: store.wpm,
                    onKeep: {
                        Haptics.shared.success()
                        Motion.animate(Motion.paper) { store.add(pick.book, to: .toRead) }
                    },
                    onPass: {
                        Haptics.shared.soft(0.4)
                        Motion.animate(Motion.paper) { store.dismiss(pick.book.id) }
                    },
                    onOpen: { router.open(pick.book) }
                )
            }
        case .challenges:
            VStack(spacing: Space.m) {
                ForEach(brief.challenges, id: \.challengeID) { progress in
                    ChallengeCard(progress: progress)
                }
            }
        case .quote:
            if let quote = brief.quote {
                QuoteCard(entry: quote) { quoteCardEntry = quote }
            }
        case .wrapped:
            if let year = wrappedYear {
                WrappedOfferCard(
                    year: year,
                    play: { router.wrapped = WrappedRequest(year: year) },
                    notNow: {
                        Haptics.shared.tap()
                        Motion.animate(Motion.paper) { wrappedPutOff = year }
                    }
                )
            }
        }
    }

    /// Today's reading times that have nothing planned in them (the plan is done, or nothing is open).
    private func quietSlots(_ brief: TodayBrief) -> [ReadingSlot] {
        guard store.isReadingDay else { return [] }
        let planned = Set(brief.slots.map(\.slot.id))
        let weekday = store.calendar.component(.weekday, from: store.now)
        return store.preferences.effectiveReadingSlots
            .filter { $0.isEnabled && $0.applies(onWeekday: weekday) && !planned.contains($0.id) }
            .sorted { $0.minuteOfDay < $1.minuteOfDay }
    }

    private var yearForecastSentence: String? {
        guard let year = forecast.result?.year else { return nil }
        return ForecastNarrator(now: store.now, calendar: store.calendar).yearSentence(year)
    }

    private func nudgeActions(_ nudge: TodayNudge) -> [NudgeCard.Action] {
        switch nudge.kind {
        case .confirmPosition(let bookID):
            return [NudgeCard.Action(title: "Set my page") { router.askPosition(for: bookID) }]
        case .stalledBook(let bookID, _):
            return [
                NudgeCard.Action(title: "Pick it up") { start(bookID: bookID) },
                NudgeCard.Action(title: "Set it aside", isQuiet: true) {
                    Motion.animate(Motion.paper) { store.pause(bookID) }
                },
            ]
        case .pausedBookWaiting(let bookID, _):
            return [NudgeCard.Action(title: "Pick it back up") {
                Motion.animate(Motion.paper) { store.startReading(bookID) }
            }]
        case .challengeEnding:
            return []
        case .yearGoalBehind:
            return [NudgeCard.Action(title: "Find a short book") { router.tab = .search }]
        }
    }

    // MARK: Brief

    private func refreshBrief() {
        var fresh = store.todayBrief(catalog: catalog, forecast: forecast.result)
        let day = GreetingMemoryStore.dayKey(store.now, calendar: store.calendar)
        if let pinned, pinned.day == day, pinned.mode == fresh.mode {
            fresh.greeting = pinned.greeting
        } else {
            pinned = PinnedGreeting(day: day, mode: fresh.mode, greeting: fresh.greeting)
            store.markGreetingShown(fresh)
        }
        if brief == nil {
            brief = fresh
        } else {
            withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                brief = fresh
            }
        }
    }

    /// Screenshot runs can ask for a card (`-LeafScroll week`).
    private func stageScroll(_ proxy: ScrollViewProxy) async {
        guard brief != nil, !didStageScroll, let target = LaunchOptions.current.scroll, let kind = CardKind(rawValue: target) else { return }
        didStageScroll = true
        try? await Task.sleep(for: .milliseconds(700))
        proxy.scrollTo(kind, anchor: .top)
    }
}

// MARK: - Previews

@MainActor
private func todayPreviewStore(_ scenario: DemoData.Scenario = .standard) -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make(scenario: scenario))
    return store
}

private struct TodayPreviewHost: View {
    var body: some View {
        NavigationStack {
            TodayView()
        }
    }
}

#Preview("Today") {
    TodayPreviewHost()
        .environment(todayPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Today · goal met, dark") {
    TodayPreviewHost()
        .environment(todayPreviewStore(.goalMet))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
        .preferredColorScheme(.dark)
}

#Preview("Today · between books") {
    TodayPreviewHost()
        .environment(todayPreviewStore(.between))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Today · brand new") {
    TodayPreviewHost()
        .environment(todayPreviewStore(.brandNew))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
