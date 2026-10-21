import SwiftUI

/// Onboarding until the reader has a plan, then the tabs.
struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    /// Debug launch routes (`-LeafScreen onboarding.quiz`) have to be known when the flow is first created.
    @State private var onboardingStart: OnboardingStep
    /// Screenshot runs can show onboarding on top of a demo library.
    @State private var forceOnboarding: Bool
    @State private var didApplyLaunchRoute = false
    /// Screenshot runs can show the Live Activity on a stand-in Lock Screen (`-LeafScreen liveactivity.goal`).
    private let liveActivityStage: LiveActivityStage.Kind?
    /// Screenshot runs can show the widgets on a stand-in Home Screen or Lock Screen (`-LeafScreen widgets.home`).
    private let widgetStage: WidgetStage.Kind?
    /// Screenshot runs can open the design-system pages (`-LeafScreen gallery`, `gallery.ribbon`). Debug builds only.
    private let galleryKey: String?

    init() {
        let key = LaunchOptions.current.screen ?? ""
        let step = key.hasPrefix("onboarding.") ? OnboardingStep(rawValue: String(key.dropFirst("onboarding.".count))) : nil
        _onboardingStart = State(initialValue: step ?? .welcome)
        _forceOnboarding = State(initialValue: step != nil)
        liveActivityStage = key.hasPrefix("liveactivity.") ? LiveActivityStage.Kind(rawValue: String(key.dropFirst("liveactivity.".count))) : nil
        widgetStage = key.hasPrefix("widgets.") ? WidgetStage.Kind(rawValue: String(key.dropFirst("widgets.".count))) : nil
        galleryKey = key == "gallery" || key.hasPrefix("gallery.") ? key : nil
    }

    var body: some View {
        ZStack {
            if let liveActivityStage {
                LiveActivityStage(kind: liveActivityStage)
            } else if let widgetStage {
                WidgetStage(kind: widgetStage)
            } else if let galleryKey {
                gallery(galleryKey)
            } else if store.hasOnboarded && !forceOnboarding {
                MainTabs()
                    .transition(.opacity)
            } else {
                OnboardingFlow(startAt: onboardingStart) {
                    withAnimation(.smooth(duration: 0.6)) {
                        forceOnboarding = false
                        store.updatePreferences {
                            $0.hasOnboarded = true
                            if $0.onboardedAt == nil { $0.onboardedAt = Date() }
                        }
                    }
                    // A new reader gets a quick look around each part of the app the first time they visit it.
                    if !LaunchOptions.current.isScripted { CoachTour.shared.start() }
                }
                .transition(.opacity)
            }
        }
        .onAppear(perform: applyLaunchRoute)
        .task { await offerWhatsNew() }
    }

    /// Once after an update: What's new, a moment after launch, when nothing else is on screen. A fresh install
    /// remembers every release as seen, so a new reader meets onboarding, not news. Screenshot runs skip it.
    private func offerWhatsNew() async {
        guard !LaunchOptions.current.isScripted else { return }
        let build = WhatsNew.currentBuild
        let state = WhatsNew.loadState()
        let onboarded = store.hasOnboarded
        let ids = WhatsNewGate.releasesToShow(current: build, state: state, hasOnboarded: onboarded, releaseIDs: WhatsNew.releaseIDs)
        guard !ids.isEmpty else {
            WhatsNew.saveState(WhatsNewGate.remember(current: build, state: state, shown: [], hasOnboarded: onboarded, releaseIDs: WhatsNew.releaseIDs))
            return
        }
        try? await Task.sleep(for: .seconds(1.2))
        // Not over a session, a sheet or anything else the reader came to the app for; it waits for the next launch.
        guard router.whatsNew == nil, !router.showSession, router.planSheet == nil, !router.showSettings,
              router.positionRequest == nil, router.teaPage == nil, router.lastOutcome == nil, router.wrapped == nil else { return }
        WhatsNew.saveState(WhatsNewGate.remember(current: build, state: state, shown: ids, hasOnboarded: onboarded, releaseIDs: WhatsNew.releaseIDs))
        router.whatsNew = WhatsNewRequest(releaseIDs: ids)
    }

    @ViewBuilder
    private func gallery(_ key: String) -> some View {
#if DEBUG
        if key == "gallery.posters" {
            SharePosterStage()
        } else if let section = MotionGallery.Section(rawValue: String(key.dropFirst("gallery.".count))) {
            NavigationStack { MotionGallery(section: section) }
        } else {
            DesignSystemGallery()
        }
#else
        EmptyView()
#endif
    }

    /// Debug-only staging for screenshots (`-LeafScreen <key>`).
    private func applyLaunchRoute() {
        guard !didApplyLaunchRoute, let key = LaunchOptions.current.screen else { return }
        didApplyLaunchRoute = true
        if key.hasPrefix("onboarding.") { return }
        switch key {
        case "today", "today.steep":
            router.tab = .today
        case "position", "position.page", "position.percent", "position.read":
            router.tab = .today
            let opensOn: PositionChoice?
            switch key {
            case "position.page": opensOn = .page
            case "position.percent": opensOn = .percent
            case "position.read": opensOn = .alreadyRead
            default: opensOn = nil
            }
            let book = store.reading.first { !$0.positionConfirmed } ?? store.reading.first
            if let book {
                router.positionRequest = PositionRequest(
                    bookID: book.id,
                    then: .startSession(source: ReadingSessionLauncher.heroSource, teaID: nil, goalSeconds: nil),
                    opensOn: opensOn
                )
            }
        case "readingtimes":
            router.tab = .today
            router.showReadingTimes = true
        case "readingtimes.edit":
            router.tab = .today
            router.readingSlotToEdit = store.preferences.effectiveReadingSlots.first?.id
            router.showReadingTimes = true
        case "deck":
            router.tab = .search
            router.showDeck = true
        case "librarian", "librarian.answer":
            router.tab = .search
            if key == "librarian.answer" { router.librarianStage = "answer" }
            router.showLibrarian = true
        case "library":
            router.tab = .library
        case "library.finished":
            router.tab = .library
            router.libraryShelf = .finished
        case "library.paused":
            router.tab = .library
            router.libraryShelf = .paused
        case "library.toread":
            router.tab = .library
            router.libraryShelf = .toRead
        case "plan":
            router.tab = .plan
        case "plan.whatif", "plan.care", "plan.order", "plan.reading":
            router.tab = .plan
            router.planStage = String(key.dropFirst("plan.".count))
        case "plan.finishline":
            router.tab = .plan
            router.planSheet = .finishLine(bookID: nil)
        case "plan.suggest":
            router.tab = .plan
            router.planSheet = .smartOrder
        case "plan.insights", "plan.insights.time", "plan.insights.mix", "plan.insights.personality", "plan.insights.more":
            router.tab = .plan
            router.planSection = .insights
            if key != "plan.insights" { router.planStage = String(key.dropFirst("plan.insights.".count)) }
        case "plan.year":
            router.tab = .plan
            router.planSection = .insights
            router.planSheet = .yearInBooks
        case "plan.letter":
            router.openWeeklyLetter()
        case "plan.circles", "plan.circles.new", "plan.circles.member", "plan.circles.schedule", "plan.circles.prompts":
            router.tab = .plan
            router.planSection = .circles
            switch key {
            case "plan.circles.prompts": router.planStage = "prompts"
            case "plan.circles": break
            default: router.circleStage = String(key.dropFirst("plan.circles.".count))
            }
        case "plan.challenges", "plan.stamps":
            router.tab = .plan
            router.planSection = .challenges
            if key == "plan.stamps" { router.planStage = "stamps" }
        case "search":
            router.tab = .search
        case "search.query":
            router.tab = .search
            router.searchQuery = "dune"
        case "search.isbn":
            router.tab = .search
            router.searchQuery = "9780441172719"
        case "search.series", "search.author", "search.time", "search.seasonal", "search.seeall", "search.undo",
             "search.quickadd", "search.added", "search.scan", "search.manual":
            router.tab = .search
            router.searchStage = String(key.dropFirst("search.".count))
        case "search.similar":
            router.tab = .search
            router.searchPath.append(SimilarRoute(book: DemoData.hobbit))
        case "search.taste":
            router.tab = .search
            router.searchPath.append(TasteRoute())
        case "settings":
            router.showSettings = true
        case "tea.cabinet", "tea.add", "tea.catalog", "tea.edit":
            router.tab = .today
            if key != "tea.cabinet" { router.teaStage = String(key.dropFirst("tea.".count)) }
            router.teaPage = .cabinet
        case "tea.history":
            router.tab = .today
            router.teaPage = .history
        case "book.pairing":
            router.bookStage = "pairing"
            router.tab = .library
            router.libraryPath = [BookRoute(book: store.item(DemoData.hobbit.id)?.book ?? DemoData.hobbit)]
        case "log", "log.finished", "log.search":
            router.tab = .plan
            router.planSection = .insights
            if key != "log" { router.historyStage = String(key.dropFirst("log.".count)) }
            router.planSheet = .readingLog
        case "numbers", "numbers.range", "numbers.alltime":
            router.tab = .plan
            router.planSection = .insights
            if key != "numbers" { router.historyStage = String(key.dropFirst("numbers.".count)) }
            router.planSheet = .numbers
        case "quote", "quote.style":
            router.tab = .plan
            router.planSection = .insights
            if key == "quote.style" { router.historyStage = "style" }
            router.planSheet = .quoteCard(entryID: nil)
        case "whatsnew":
            router.tab = .today
            router.whatsNew = WhatsNewRequest(releaseIDs: [WhatsNew.releaseIDs.first ?? ""])
        case "tour.today", "tour.today.steep", "tour.library", "tour.plan", "tour.search", "tour.settings":
            let first: [String: String] = [
                "tour.today": "today.nook", "tour.today.steep": "today.steep", "tour.library": "library.shelves",
                "tour.plan": "plan.forecast", "tour.search": "search.rows", "tour.settings": "settings.times",
            ]
            CoachTour.shared.stage(from: first[key] ?? "today.nook")
            switch key {
            case "tour.library": router.tab = .library
            case "tour.plan": router.tab = .plan
            case "tour.search": router.tab = .search
            case "tour.settings": router.showSettings = true
            default: router.tab = .today
            }
        case "shelf", "shelf.slip", "shelf.poster":
            router.tab = .library
            router.libraryShelf = .finished
            router.libraryStage = key == "shelf" ? "shelf" : String(key.dropFirst("shelf.".count))
        case "wrapped", "wrapped.1", "wrapped.2", "wrapped.3", "wrapped.4", "wrapped.5", "wrapped.6", "wrapped.7":
            router.tab = .plan
            router.planSection = .insights
            let card = Int(key.dropFirst("wrapped.".count)) ?? 0
            router.wrapped = WrappedRequest(year: store.calendar.component(.year, from: store.now), startCard: card)
        case "wrapped.offer":
            router.tab = .today
            router.wrappedStage = "offer"
        case "plan.insights.wrapped":
            router.tab = .plan
            router.planSection = .insights
            router.wrappedStage = "offer"
        case "book.timeline":
            router.bookStage = "timeline"
            router.tab = .library
            router.libraryPath = [BookRoute(book: store.item(DemoData.hobbit.id)?.book ?? DemoData.hobbit)]
        case "settings.plan", "settings.tea", "settings.cloud", "settings.data", "settings.soundlab":
            router.settingsStage = String(key.dropFirst("settings.".count))
            router.showSettings = true
        case "book.journal", "book.more", "book.edition":
            router.bookStage = String(key.dropFirst("book.".count))
            router.tab = .library
            router.libraryPath = [BookRoute(book: store.item(DemoData.hobbit.id)?.book ?? DemoData.hobbit)]
        case "session":
            store.startSession(bookID: DemoData.hobbit.id, startedAt: Date().addingTimeInterval(-(9 * 60 + 41)))
            router.showSession = true
        case "session.cup", "session.cupdone", "session.paused", "session.note", "session.ambience", "session.nook":
            let minutes = key == "session.cupdone" ? 26.5 : 9 + 41.0 / 60
            let teaID: String? = key.hasPrefix("session.cup") || key == "session.note" ? TeaCatalog.earlGrey.id : nil
            store.startSession(
                bookID: DemoData.hobbit.id,
                startedAt: Date().addingTimeInterval(-minutes * 60),
                teaID: teaID,
                goalSeconds: teaID == nil ? nil : 25 * 60
            )
            if key == "session.paused" { store.pauseSession() }
            router.showSession = true
        case "session.ritual", "session.steeping", "session.ready":
            router.ritual = RitualRequest(bookID: DemoData.hobbit.id, teaID: TeaCatalog.earlGrey.id)
            router.showSession = true
        case "session.outcome", "session.tasting":
            let teaID: String? = key == "session.tasting" ? TeaCatalog.earlGrey.id : nil
            let session = ReadingSession(bookID: DemoData.hobbit.id, startedAt: Date().addingTimeInterval(-26 * 60), seconds: 26 * 60, fromPage: 142, toPage: 165, teaID: teaID)
            if let teaID {
                // The card as it looks once the reader has tapped "Just right" and added a little more.
                store.saveTasting(sessionID: session.id, teaID: teaID, bookID: DemoData.hobbit.id, strength: .justRight, aromas: ["citrus", "floral"], rating: 4)
            }
            router.lastOutcome = SessionOutcome(session: session, bookID: DemoData.hobbit.id, finishedBook: false, reachedGoalNow: true, minutesToday: 38, oldWPM: 258, newWPM: 262)
        default:
            if key.hasPrefix("book:"), let item = store.item(String(key.dropFirst("book:".count))) {
                router.tab = .library
                router.libraryPath = [BookRoute(book: item.book)]
            }
        }
    }
}
