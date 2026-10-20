import SwiftUI

@main
struct LeafWatchApp: App {
    @State private var store: WatchStore

    init() {
        let store = WatchStore(demo: LaunchScreen.isDemo)
        _store = State(initialValue: store)
        // Before launch finishes: a reminder's Start that launched the app is delivered to this delegate.
        if !LaunchScreen.isDemo {
            WatchNotifications.shared.configure(store: store)
            PhoneBridge.shared.activate(store: store)
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// Lets the reader step away from a live session to browse, without ending it.
    @State private var sessionMinimized = false
    @State private var page = WatchPage.today
    @State private var path: [WatchRoute] = []

    /// The pages, top to bottom. The crown pages between them; screens that need the crown are pushed instead.
    enum WatchPage: Hashable { case today, log, forecast, week, shelf, add }

    var body: some View {
        #if DEBUG
        if LaunchScreen.current == "complications" {
            ComplicationGallery()
        } else {
            root
        }
        #else
        root
        #endif
    }

    private var root: some View {
        NavigationStack(path: $path) {
            TabView(selection: $page) {
                TodayPage(onOpenSession: { sessionMinimized = false }).tag(WatchPage.today)
                LogPage().tag(WatchPage.log)
                ForecastPage().tag(WatchPage.forecast)
                WeekPage().tag(WatchPage.week)
                ShelfPage(onStart: { sessionMinimized = false }).tag(WatchPage.shelf)
                AddPage().tag(WatchPage.add)
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .quickLog(let bookID):
                    if let book = store.snapshot.book(bookID) { QuickLogView(book: book) }
                case .whereWasI(let bookID):
                    if let book = store.snapshot.book(bookID) { WhereWasIView(book: book) }
                case .shelfBook(let bookID):
                    if let book = store.snapshot.book(bookID) {
                        ShelfBookActions(book: book, isReading: store.reading.contains { $0.id == bookID }) {
                            sessionMinimized = false
                            path.removeAll()
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: sessionPresented) {
            SessionView(onMinimize: {
                sessionMinimized = true
                store.lastLogged = nil
            })
                .environment(store)
                .stagedAlwaysOn(LaunchScreen.current == "aod")
        }
        .onChange(of: store.activeSession?.id) { _, id in
            if id != nil { sessionMinimized = false }
        }
        .onAppear(perform: stage)
        .onChange(of: scenePhase) { _, phase in
            // Back on the wrist after midnight: a fresh day until the phone sends its numbers.
            guard phase == .active, !LaunchScreen.isDemo else { return }
            store.rollDayIfNeeded()
            PhoneBridge.shared.refreshIfReachable()
        }
    }

    /// Screenshot staging (`-LeafScreen`, DEBUG only).
    private func stage() {
        guard let screen = LaunchScreen.current else { return }
        let bookID = store.suggestedBook?.id ?? ""
        switch screen {
        case "log": page = .log
        case "quicklog": page = .log; path = [.quickLog(bookID: bookID)]
        case "where": page = .log; path = [.whereWasI(bookID: bookID)]
        case "forecast": page = .forecast
        case "week": page = .week
        case "books", "shelf": page = .shelf
        case "shelf.actions": page = .shelf; path = [.shelfBook(bookID: store.snapshot.queue.first?.id ?? bookID)]
        case "add", "add.sent": page = .add
        default: break
        }
    }

    private var sessionPresented: Binding<Bool> {
        Binding(
            get: { (store.activeSession != nil && !sessionMinimized) || store.lastLogged != nil },
            set: { presented in
                if !presented {
                    if store.activeSession != nil { sessionMinimized = true }
                    store.lastLogged = nil
                }
            }
        )
    }
}

private extension View {
    /// Shows the Always-On look in a screenshot. Never overrides the real value otherwise.
    @ViewBuilder func stagedAlwaysOn(_ isOn: Bool) -> some View {
        if isOn { environment(\.isLuminanceReduced, true) } else { self }
    }
}
