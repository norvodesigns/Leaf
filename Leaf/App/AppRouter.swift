import Foundation
import Observation

enum AppTab: Hashable {
    case today, library, plan, search
}

/// A pushed book detail. Carries the whole book so search results not yet in the library can open too.
struct BookRoute: Hashable {
    let book: Book
}

/// App-wide navigation state.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .today
    var todayPath: [BookRoute] = []
    var libraryPath: [BookRoute] = []
    var planPath: [BookRoute] = []
    var searchPath: [BookRoute] = []

    var showSettings = false
    /// The full-screen reading session.
    var showSession = false
    /// Retaking the speed test from Settings.
    var showSpeedTest = false
    /// Set after a session ends, to show the wrap-up moment.
    var lastOutcome: SessionOutcome?

    func open(_ book: Book) {
        let route = BookRoute(book: book)
        switch tab {
        case .today: todayPath.append(route)
        case .library: libraryPath.append(route)
        case .plan: planPath.append(route)
        case .search: searchPath.append(route)
        }
    }

    func popToRoot() {
        todayPath.removeAll()
        libraryPath.removeAll()
        planPath.removeAll()
        searchPath.removeAll()
    }
}
