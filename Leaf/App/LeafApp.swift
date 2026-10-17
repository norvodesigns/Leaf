import SwiftUI

@main
struct LeafApp: App {
    @State private var store: LibraryStore
    @State private var router = AppRouter()
    @State private var catalog = BookCatalog.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let options = LaunchOptions.current
        let store = LibraryStore(persistence: options.isScripted ? .ephemeral() : .shared)
        if options.demo { store.replaceAll(with: DemoData.make()) }
        _store = State(initialValue: store)

        Reminders.shared.configure(store: store)
        WatchBridge.shared.activate(store: store)
        store.onChange = { [weak store] in
            Reminders.shared.scheduleRefresh()
            WatchBridge.shared.schedulePush()
            if let level = store?.preferences.hapticsLevel { Haptics.shared.level = level }
        }
        Haptics.shared.level = store.preferences.hapticsLevel
        Haptics.shared.prepare()
        LeafAppearance.configure()
    }

    private var colorScheme: ColorScheme? {
        switch store.preferences.appearance {
        case .system: nil
        case .day: .light
        case .night: .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(catalog)
                .preferredColorScheme(colorScheme)
                .tint(Color.accentColor)
                .task { await catalog.load() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        store.refreshDay()
                        Haptics.shared.prepare()
                    case .background:
                        store.flush()
                    default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    store.refreshDay()
                }
        }
    }
}
