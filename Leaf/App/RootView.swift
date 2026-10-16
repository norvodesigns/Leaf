import SwiftUI

/// Onboarding until the reader has a plan, then the tabs.
struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var onboardingStart: OnboardingStep = .welcome
    /// Screenshot runs can show onboarding on top of a demo library.
    @State private var forceOnboarding = false
    @State private var didApplyLaunchRoute = false

    var body: some View {
        ZStack {
            if store.hasOnboarded && !forceOnboarding {
                MainTabs()
                    .transition(.opacity)
            } else {
                OnboardingFlow(startAt: onboardingStart) {
                    withAnimation(.smooth(duration: 0.6)) {
                        forceOnboarding = false
                        store.updatePreferences { $0.hasOnboarded = true }
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear(perform: applyLaunchRoute)
    }

    /// Debug-only staging for screenshots (`-LeafScreen <key>`).
    private func applyLaunchRoute() {
        guard !didApplyLaunchRoute, let key = LaunchOptions.current.screen else { return }
        didApplyLaunchRoute = true
        if key.hasPrefix("onboarding.") {
            onboardingStart = OnboardingStep(rawValue: String(key.dropFirst("onboarding.".count))) ?? .welcome
            forceOnboarding = true
            return
        }
        switch key {
        case "today":
            router.tab = .today
        case "library":
            router.tab = .library
        case "library.finished":
            router.tab = .library
            router.libraryShelf = .finished
        case "plan":
            router.tab = .plan
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
