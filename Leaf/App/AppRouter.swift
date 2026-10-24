import Foundation
import SwiftUI
import Observation

/// The four tabs (docs/design/REDESIGN.md §1). `search` is not a tab any more: asking for it opens Search as a sheet
/// over Library, so older call sites keep working.
enum AppTab: Hashable {
    case today, plan, library, you, search
}

/// The deeper pages: the forecast lives on Plan, the others on You.
enum PlanSection: String, CaseIterable, Identifiable, Hashable {
    case forecast, insights, challenges, circles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forecast: "Forecast"
        case .insights: "Insights"
        case .challenges: "Challenges"
        case .circles: "Circles"
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

/// The What's new sheet, for these releases (newest first).
struct WhatsNewRequest: Identifiable, Hashable {
    let releaseIDs: [String]
    var id: String { releaseIDs.joined(separator: ",") }
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

/// How the reader wants to add a book, from the Library's `plus`: search for it, scan it, or type it in.
enum AddBookIntent: Hashable {
    case search, scan, manual
}

/// App-wide navigation state.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .today {
        didSet {
            // Search opens as a sheet over Library.
            if tab == .search {
                tab = .library
                showSearch = true
                FirstUseTips.shared.finish(.libraryAdd)
            }
        }
    }
    var todayPath: [BookRoute] = []
    var libraryPath: [BookRoute] = []
    var planPath: [BookRoute] = []
    var youPath: [BookRoute] = []
    /// Search (and Discover), as a sheet over Library.
    var showSearch = false
    /// Search pushes books, whole rows ("See all"), "More like this" and "Your taste", so its path is untyped.
    var searchPath = NavigationPath()

    var showSettings = false
    /// Each time the app is opened: 0 for the launch, then one more for every return from the background. Today greets
    /// every open with a fresh line.
    private(set) var opens = 0
    @ObservationIgnored private var isAway = false
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
    var showReadingTimes = false {
        didSet { if showReadingTimes { FirstUseTips.shared.finish(.planTimes) } }
    }
    /// A reading time to open straight into when the editor appears (screenshots).
    var readingSlotToEdit: UUID?
    /// A reading time's own small sheet from Plan: change its time, or swap its book.
    var slotEdit: SlotEdit? {
        didSet { if slotEdit != nil { FirstUseTips.shared.finish(.planTimes) } }
    }
    /// The swipe deck as a full sheet (from Search and Today).
    var showDeck = false
    /// "Ask the Librarian" as a full sheet (from Search).
    var showLibrarian = false
    /// Screenshots: "answer" walks the librarian's questions so the picks are on screen.
    var librarianStage: String?
    /// "Steep and read": the session screen opens at the tea instead of the timer.
    var ritual: RitualRequest?
    /// Which deeper page is showing. The forecast is Plan's; insights, challenges and circles are You's, so asking
    /// for one of those moves to You.
    var planSection: PlanSection = .forecast {
        didSet {
            if planSection != .forecast, tab == .plan { tab = .you }
        }
    }
    var planSheet: PlanSheet?
    /// A what-if or scroll position to stage on the Plan tab (screenshots): "whatif", "care", "mix", "stamps"…
    var planStage: String?
    /// A sheet to open on the Circles page: "new" (from Today's suggestion too), and for screenshots "member",
    /// "schedule" or "name".
    var circleStage: String?
    /// The circle the Circles page should show, when something (Today's circle card) asked for one.
    var circleFocus: UUID?
    /// Opens the Search tab ready to add a book (the Library's `plus`); Search consumes it.
    var addBookIntent: AddBookIntent?
    /// Search staging once its rows exist (screenshots): "series", "author", "time", "seasonal", "seeall", "undo",
    /// and for adding: "quickadd", "added", "scan", "manual".
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
    /// What's new, after an update or from Settings.
    var whatsNew: WhatsNewRequest?

    /// The app went to the background.
    func noteAway() { isAway = true }

    /// The app is in front again: after time in the background, that is a new open.
    func noteActive() {
        guard isAway else { return }
        isAway = false
        opens += 1
    }

    /// Opens the full-screen session, zooming from `source`.
    func presentSession(from source: String) {
        sessionSource = source
        showSession = true
        FirstUseTips.shared.finish(.todayStart)
    }

    /// The Circles page under You, scrolled to it, on one circle or opening a sheet ("new").
    func openCircles(focus circleID: UUID? = nil, stage: String? = nil) {
        circleFocus = circleID
        circleStage = stage
        tab = .you
        planSection = .circles
        planStage = "circles"
    }

    /// Goes to Search ready to add a book.
    func beginAddingBook(_ intent: AddBookIntent = .search) {
        tab = .search
        addBookIntent = intent
    }

    /// Asks "Where are you?" for a book.
    func askPosition(for bookID: String, then: PositionRequest.Then = .save) {
        positionRequest = PositionRequest(bookID: bookID, then: then)
        if then == .save { FirstUseTips.shared.finish(.bookPage) }
    }

    func open(_ book: Book) {
        let route = BookRoute(book: book)
        if showSearch {
            searchPath.append(route)
            return
        }
        switch tab {
        case .today: todayPath.append(route)
        case .library: libraryPath.append(route)
        case .plan: planPath.append(route)
        case .you: youPath.append(route)
        case .search: searchPath.append(route)
        }
    }

    func popToRoot() {
        todayPath.removeAll()
        libraryPath.removeAll()
        planPath.removeAll()
        youPath.removeAll()
        searchPath = NavigationPath()
    }

    /// The Sunday letter, from its notification.
    func openWeeklyLetter() {
        tab = .you
        planSection = .insights
        planSheet = .weeklyLetter
    }
}
