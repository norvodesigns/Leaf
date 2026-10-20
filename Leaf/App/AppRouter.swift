import Foundation
import SwiftUI
import Observation

enum AppTab: Hashable {
    case today, library, plan, search
}

/// The three pages of the Plan tab.
enum PlanSection: String, CaseIterable, Identifiable, Hashable {
    case forecast, insights, challenges

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forecast: "Forecast"
        case .insights: "Insights"
        case .challenges: "Challenges"
        }
    }
}

/// A sheet over the Plan tab.
enum PlanSheet: Identifiable, Hashable {
    /// "Finish by a date": for one book, or the first in the plan.
    case finishLine(bookID: String?)
    case smartOrder
    case yearInBooks
    case weeklyLetter
    case readingLog
    /// The deeper numbers.
    case numbers
    /// Quote cards, opening on one quote or the newest.
    case quoteCard(entryID: UUID?)

    var id: String {
        switch self {
        case .finishLine(let bookID): "finish-\(bookID ?? "")"
        case .smartOrder: "order"
        case .yearInBooks: "year"
        case .weeklyLetter: "letter"
        case .readingLog: "log"
        case .numbers: "numbers"
        case .quoteCard(let entryID): "quote-\(entryID?.uuidString ?? "")"
        }
    }
}

/// A pushed book detail. Carries the whole book so search results not yet in the library can open too.
struct BookRoute: Hashable {
    let book: Book
}

/// "Where are you?" for one book, and what happens once it's answered.
struct PositionRequest: Identifiable, Hashable {
    enum Then: Hashable {
        /// Just record the answer.
        case save
        /// Begin reading from the answer, zooming from `source`, with the tea and cup-length goal if there is one.
        case startSession(source: String, teaID: String?, goalSeconds: Double?)
        /// Open the tea ritual for the book once it's answered.
        case ritual(source: String, teaID: String?)
    }

    let bookID: String
    var then: Then = .save
    /// The answer the sheet opens on (screenshots); nil lets the sheet choose from the book's state.
    var opensOn: PositionChoice?

    var id: String { bookID }
}

/// A tea ritual waiting in the session screen: the book, and the tea it opens with. No reading time is counted
/// until the reader starts the cup.
struct RitualRequest: Hashable {
    let bookID: String
    var teaID: String?
}

/// App-wide navigation state.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .today
    var todayPath: [BookRoute] = []
    var libraryPath: [BookRoute] = []
    var planPath: [BookRoute] = []
    /// Search pushes books, whole rows ("See all"), "More like this" and "Your taste", so its path is untyped.
    var searchPath = NavigationPath()

    var showSettings = false
    /// The full-screen reading session.
    var showSession = false
    /// Retaking the speed test from Settings.
    var showSpeedTest = false
    /// Set after a session ends, to show the wrap-up moment.
    var lastOutcome: SessionOutcome?
    /// Which shelf the Library tab shows.
    var libraryShelf: Shelf = .reading
    /// A query to pre-fill on the Search tab (used by "Find a book" buttons and screenshots).
    var searchQuery: String?
    /// Which control the session zooms out of ("hero" on Today, or "accessory").
    var sessionSource = "hero"
    /// The "Where are you?" sheet, for whichever book asked.
    var positionRequest: PositionRequest?
    /// The reading-times editor as a sheet (from Today).
    var showReadingTimes = false
    /// A reading time to open straight into when the editor appears (screenshots).
    var readingSlotToEdit: UUID?
    /// The swipe deck as a full sheet (from Search and Today).
    var showDeck = false
    /// "Steep and read": the session screen opens at the tea instead of the timer.
    var ritual: RitualRequest?
    /// Which page the Plan tab shows.
    var planSection: PlanSection = .forecast
    var planSheet: PlanSheet?
    /// A what-if or scroll position to stage on the Plan tab (screenshots): "whatif", "care", "mix", "stamps"…
    var planStage: String?
    /// Search staging once its rows exist (screenshots): "series", "author", "time", "seasonal", "seeall", "undo".
    var searchStage: String?
    /// Book detail staging (screenshots): "journal", "more", "edition".
    var bookStage: String?
    /// Settings staging (screenshots): the section to scroll to, "plan", "tea", "cloud".
    var settingsStage: String?
    /// The tea cabinet or the tea history, as a sheet over the tabs.
    var teaPage: TeaPage?
    /// Tea page staging (screenshots): "add", "catalog", "edit".
    var teaStage: String?
    /// Reading log, numbers and quote card staging (screenshots): "finished", "search", "range", "style".
    var historyStage: String?
    /// The Finished shelf as a wall of spines (screenshots): "shelf", a spine held out ("slip"), the poster ("poster").
    var libraryStage: String?
    /// Reading Wrapped, playing over the tabs.
    var wrapped: WrappedRequest?
    /// Wrapped staging (screenshots): "offer" shows the December offer whatever the date.
    var wrappedStage: String?

    /// Opens the full-screen session, zooming from `source`.
    func presentSession(from source: String) {
        sessionSource = source
        showSession = true
    }

    /// Asks "Where are you?" for a book.
    func askPosition(for bookID: String, then: PositionRequest.Then = .save) {
        positionRequest = PositionRequest(bookID: bookID, then: then)
    }

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
        searchPath = NavigationPath()
    }

    /// The Sunday letter, from its notification.
    func openWeeklyLetter() {
        tab = .plan
        planSection = .insights
        planSheet = .weeklyLetter
    }
}
