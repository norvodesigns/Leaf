import SwiftUI

@main
struct LeafWatchApp: App {
    @State private var store = WatchStore(demo: LaunchScreen.isDemo)

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
                .task {
                    if !LaunchScreen.isDemo { PhoneBridge.shared.activate(store: store) }
                }
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    /// Lets the reader step away from a live session to browse, without ending it.
    @State private var sessionMinimized = false
    @State private var page = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                TodayPage(onOpenSession: { sessionMinimized = false }).tag(0)
                WeekPage().tag(1)
                BooksPage(onStart: { sessionMinimized = false }).tag(2)
            }
            .tabViewStyle(.verticalPage)
        }
        .fullScreenCover(isPresented: sessionPresented) {
            SessionView(onMinimize: { sessionMinimized = true })
                .environment(store)
        }
        .onChange(of: store.activeSession?.id) { _, id in
            if id != nil { sessionMinimized = false }
        }
        .onAppear {
            if LaunchScreen.current == "books" { page = 2 }
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
