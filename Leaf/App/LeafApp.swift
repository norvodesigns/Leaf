import SwiftUI
import UIKit

@main
struct LeafApp: App {
    @State private var store: LibraryStore
    @State private var router: AppRouter
    @State private var catalog = BookCatalog.shared
    @UIApplicationDelegateAdaptor(LeafAppDelegate.self) private var appDelegate
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

        if !options.isScripted {
            CircleStore.importLegacyFile(into: store)
            Self.startSyncIfReady(store)
            CircleSharing.shared.connect(store)
        }

        Reminders.shared.configure(store: store)
        Reminders.shared.onOpenWeeklyLetter = { [weak router] in router?.openWeeklyLetter() }
        WatchBridge.shared.activate(store: store)
        AppReadingIntents.shared.connect(store: store, router: router)
        LiveActivityController.shared.configure(store: store)
        WidgetFeed.shared.configure(store: store)
        store.onChange = { [weak store] in
            Reminders.shared.scheduleRefresh()
            WatchBridge.shared.schedulePush()
            LiveActivityController.shared.sync()
            WidgetFeed.shared.schedule()
            CircleSharing.shared.libraryChanged()
            if let level = store?.preferences.hapticsLevel { Haptics.shared.level = level }
        }
        Haptics.shared.level = store.preferences.hapticsLevel
        Haptics.shared.prepare()
        CozySettings.apply()
        LeafAppearance.configure()
    }

    /// iCloud starts once the library has been read: never against the empty stand-in of a launch before the first
    /// unlock, whose merge would be written over the reader's real library.
    private static func startSyncIfReady(_ store: LibraryStore) {
        guard store.sync == nil, !store.isLoadDeferred, CloudSync.isAvailable else { return }
        let sync = CloudSync()
        sync.onRemoteData = { [weak store] merged in store?.applyRemote(merged: merged) }
        store.sync = sync
        sync.start(initial: store.data)
    }

    /// After a launch before the first unlock, reads the library as soon as it can be read.
    private func loadDeferredLibrary() {
        guard store.loadIfDeferred() else { return }
        WatchBridge.shared.applyHeldEvents()
        if !LaunchOptions.current.isScripted {
            CircleStore.importLegacyFile(into: store)
            Self.startSyncIfReady(store)
        }
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
                        loadDeferredLibrary()
                        if !LaunchOptions.current.isScripted { CircleSharing.shared.connect(store) }
                        store.refreshDay(LaunchOptions.current.now())
                        Haptics.shared.prepare()
                        LiveActivityController.shared.sync()
                        WidgetFeed.shared.schedule()
                    case .background:
                        store.flush()
                        WidgetFeed.shared.publish()
                    default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    store.refreshDay(LaunchOptions.current.now())
                    WidgetFeed.shared.schedule()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                    loadDeferredLibrary()
                }
        }
    }
}
