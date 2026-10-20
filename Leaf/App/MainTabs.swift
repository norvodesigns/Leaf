import SwiftUI

/// The shell: Today, Library, Plan and a Search role tab, each in its own navigation stack, with the
/// session accessory docked above the tab bar. Owns the session zoom, the sheets, and the hooks from
/// reminders and the watch.
struct MainTabs: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router

    /// The session zooms out of the hero button or the accessory (`router.sessionSource`).
    @Namespace private var sessionZoom
    /// Today's covers zoom into book detail.
    @Namespace private var todayBookZoom

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "sun.horizon", value: AppTab.today) {
                NavigationStack(path: $router.todayPath) {
                    TodayView()
                        .focusPull(isFocused: router.todayPath.isEmpty)
                        .navigationDestination(for: BookRoute.self) { route in
                            BookDetailView(book: route.book)
                                .navigationTransition(.zoom(sourceID: route.book.id, in: todayBookZoom))
                        }
                }
                .environment(\.todayBookZoomNamespace, todayBookZoom)
            }

            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack(path: $router.libraryPath) {
                    LibraryView()
                        .navigationDestination(for: BookRoute.self) { route in
                            BookDetailView(book: route.book)
                        }
                }
            }

            Tab("Plan", systemImage: "calendar.day.timeline.leading", value: AppTab.plan) {
                NavigationStack(path: $router.planPath) {
                    PlanView()
                        .navigationDestination(for: BookRoute.self) { route in
                            BookDetailView(book: route.book)
                        }
                }
            }

            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $router.searchPath) {
                    SearchView()
                        .navigationDestination(for: BookRoute.self) { route in
                            BookDetailView(book: route.book)
                        }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            SessionAccessory()
        }
        .environment(\.sessionZoomNamespace, sessionZoom)
        .onChange(of: store.activeSession == nil) { _, ended in
            // A session ended elsewhere (the watch, the Live Activity) while minimized: its ambience ends with it.
            // Not during a tea ritual, which plays before the session starts.
            if ended && router.ritual == nil { AmbiencePlayer.shared.stop() }
        }
        .fullScreenCover(isPresented: $router.showSession) {
            SessionView()
                .navigationTransition(.zoom(sourceID: router.sessionSource, in: sessionZoom))
        }
        .sheet(item: $router.lastOutcome) { outcome in
            SessionOutcomeView(outcome: outcome)
        }
        .sheet(item: $router.positionRequest) { request in
            if let item = store.item(request.bookID) {
                WhereAreYouSheet(request: request, item: item, now: store.now)
            }
        }
        .sheet(isPresented: $router.showReadingTimes) {
            ReadingTimesSheet()
        }
        .sheet(isPresented: $router.showDeck) {
            SwipeDeckScreen()
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
                .fullScreenCover(isPresented: speedTestOverSettings) {
                    speedTestCover
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: speedTestOverTabs) {
            speedTestCover
        }
        .onChange(of: router.tab) { _, _ in
            Haptics.shared.selection()
        }
        .onAppear(perform: wireHooks)
    }

    // MARK: Speed test

    /// The retake from Settings. While the Settings sheet is up the cover hangs off the sheet, so it
    /// presents on top of it; otherwise it hangs off the tabs.
    private var speedTestOverSettings: Binding<Bool> {
        Binding(
            get: { router.showSpeedTest && router.showSettings },
            set: { router.showSpeedTest = $0 }
        )
    }

    private var speedTestOverTabs: Binding<Bool> {
        Binding(
            get: { router.showSpeedTest && !router.showSettings },
            set: { router.showSpeedTest = $0 }
        )
    }

    private var speedTestCover: some View {
        SpeedTestView(
            onComplete: { result in
                store.recordSpeedTest(result)
                router.showSpeedTest = false
            },
            onCancel: {
                router.showSpeedTest = false
            }
        )
    }

    // MARK: Hooks

    /// A tap on "Start reading" in a reminder starts a session; a session logged on the watch shows
    /// its wrap-up here.
    private func wireHooks() {
        let store = store
        let router = router
        Reminders.shared.onStartReading = { bookID in
            ReadingSessionLauncher.startFromReminder(bookID: bookID, store: store, router: router)
        }
        WatchBridge.shared.onRemoteOutcome = { outcome in
            ReadingSessionLauncher.present(outcome, router: router)
        }
    }
}

#Preview("Tabs") {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return MainTabs()
        .environment(store)
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
