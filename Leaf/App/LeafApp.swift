import SwiftUI

@main
struct LeafApp: App {
    @State private var store: LibraryStore
    @State private var router: AppRouter
    @State private var catalog = BookCatalog.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let options = LaunchOptions.current
        let now = options.now()
        let store = LibraryStore(persistence: options.isScripted ? .ephemeral() : .shared, now: now)
        if options.demo {
            let scenario = options.scenario.flatMap(DemoData.Scenario.init(rawValue:)) ?? .standard
            store.replaceAll(with: DemoData.make(now: now, scenario: scenario))
        }
        _store = State(initialValue: store)
        let router = AppRouter()
        _router = State(initialValue: router)
        if options.isScripted {
            // Screenshot runs start with no pot on the stove, except the one that shows it steeping.
            let steeped: TimeInterval? = switch options.screen ?? "" {
            case "today.steep", "session.steeping": 75
            case "session.ready": 250
            default: nil
            }
            TeaSteepState.save(steeped.map {
                TeaSteepState(teaID: TeaCatalog.earlGrey.id, steepSeconds: 240, startedAt: Date().addingTimeInterval(-$0), bookID: DemoData.hobbit.id)
            })
        }

        if !options.isScripted, CloudSync.isAvailable {
            let sync = CloudSync()
            sync.onRemoteData = { [weak store] merged in store?.applyRemote(merged: merged) }
            store.sync = sync
            sync.start(initial: store.data)
        }

        Reminders.shared.configure(store: store)
        Reminders.shared.onOpenWeeklyLetter = { [weak router] in router?.openWeeklyLetter() }
        WatchBridge.shared.activate(store: store)
        AppReadingIntents.shared.connect(store: store, router: router)
        LiveActivityController.shared.configure(store: store)
        store.onChange = { [weak store] in
            Reminders.shared.scheduleRefresh()
            WatchBridge.shared.schedulePush()
            LiveActivityController.shared.sync()
            if let level = store?.preferences.hapticsLevel { Haptics.shared.level = level }
        }
        Haptics.shared.level = store.preferences.hapticsLevel
        Haptics.shared.prepare()
        CozySettings.apply()
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
                .tint(Color.accent)
                .task { await catalog.load() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        store.refreshDay(LaunchOptions.current.now())
                        Haptics.shared.prepare()
                        LiveActivityController.shared.sync()
                    case .background:
                        store.flush()
                    default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    store.refreshDay(LaunchOptions.current.now())
                }
        }
    }
}
