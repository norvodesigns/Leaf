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
    /// Screenshot runs can open the design-system pages (`-LeafScreen gallery`, `gallery.ribbon`). Debug builds only.
    private let galleryKey: String?

    init() {
        let key = LaunchOptions.current.screen ?? ""
        let step = key.hasPrefix("onboarding.") ? OnboardingStep(rawValue: String(key.dropFirst("onboarding.".count))) : nil
        _onboardingStart = State(initialValue: step ?? .welcome)
        _forceOnboarding = State(initialValue: step != nil)
        liveActivityStage = key.hasPrefix("liveactivity.") ? LiveActivityStage.Kind(rawValue: String(key.dropFirst("liveactivity.".count))) : nil
        galleryKey = key == "gallery" || key.hasPrefix("gallery.") ? key : nil
    }

    var body: some View {
        ZStack {
            if let liveActivityStage {
                LiveActivityStage(kind: liveActivityStage)
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
                }
                .transition(.opacity)
            }
        }
        .onAppear(perform: applyLaunchRoute)
    }

    @ViewBuilder
    private func gallery(_ key: String) -> some View {
#if DEBUG
        if let section = MotionGallery.Section(rawValue: String(key.dropFirst("gallery.".count))) {
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
        case "library":
            router.tab = .library
        case "library.finished":
            router.tab = .library
            router.libraryShelf = .finished
        case "plan":
            router.tab = .plan
        case "plan.whatif", "plan.care", "plan.order":
            router.tab = .plan
            router.planStage = String(key.dropFirst("plan.".count))
        case "plan.finishline":
            router.tab = .plan
            router.planSheet = .finishLine(bookID: nil)
        case "plan.suggest":
            router.tab = .plan
            router.planSheet = .smartOrder
        case "plan.insights", "plan.insights.time", "plan.insights.mix", "plan.insights.personality":
            router.tab = .plan
            router.planSection = .insights
            if key != "plan.insights" { router.planStage = String(key.dropFirst("plan.insights.".count)) }
        case "plan.year":
            router.tab = .plan
            router.planSection = .insights
            router.planSheet = .yearInBooks
        case "plan.letter":
            router.openWeeklyLetter()
        case "plan.challenges", "plan.stamps":
            router.tab = .plan
            router.planSection = .challenges
            if key == "plan.stamps" { router.planStage = "stamps" }
        case "search":
            router.tab = .search
        case "search.query":
            router.tab = .search
            router.searchQuery = "dune"
        case "settings":
            router.showSettings = true
        case "session":
            store.startSession(bookID: DemoData.hobbit.id, startedAt: Date().addingTimeInterval(-(9 * 60 + 41)))
            router.showSession = true
        case "session.cup", "session.cupdone", "session.paused", "session.note", "session.ambience":
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
        case "session.outcome":
            let session = ReadingSession(bookID: DemoData.hobbit.id, startedAt: Date().addingTimeInterval(-26 * 60), seconds: 26 * 60, fromPage: 142, toPage: 165)
            router.lastOutcome = SessionOutcome(session: session, bookID: DemoData.hobbit.id, finishedBook: false, reachedGoalNow: true, minutesToday: 38, oldWPM: 258, newWPM: 262)
        default:
            if key.hasPrefix("book:"), let item = store.item(String(key.dropFirst("book:".count))) {
                router.tab = .library
                router.libraryPath = [BookRoute(book: item.book)]
            }
        }
    }
}
