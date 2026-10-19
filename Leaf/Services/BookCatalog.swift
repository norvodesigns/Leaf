import Foundation
import Observation

/// The offline catalog: hundreds of thousands of books, searchable without a connection.
///
/// The data lives in the bundled read-only SQLite database (`CatalogDatabase`), never in memory as a whole. Two views of it:
///
/// * `books` is the **browse pool**: the best-known books that have genres or themes (about 25,000 in the full build).
///   The carousels, the recommender and the onboarding picks work on this list, so they stay fast and every book in
///   them can be explained.
/// * `search(_:limit:)` and `book(id:)` reach **every** book in the database, pool or not.
@MainActor
@Observable
final class BookCatalog {
    static let shared = BookCatalog()

    /// The browse pool, most popular first. Empty until `load()` finishes. Not the whole catalog: use `search` or
    /// `book(id:)` to reach books outside it.
    private(set) var books: [Book] = []
    private(set) var isLoaded = false
    /// Pool-wide counts the recommender weighs features by; built once, right after the pool loads.
    @ObservationIgnored private(set) var stats = CatalogStats(books: [])

    private let databaseURL: URL?
    @ObservationIgnored private var databaseOpened = false
    @ObservationIgnored private var openedDatabase: CatalogDatabase?
    /// The pool by id, for the common lookup.
    @ObservationIgnored private var byID: [String: Book] = [:]
    /// Books outside the pool that were asked for by id; small, and emptied when it grows past `recentLimit`.
    @ObservationIgnored private var recent: [String: Book] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    private static let recentLimit = 256

    /// `databaseURL` is for tests and previews; the app uses the `catalog.sqlite` in its bundle.
    init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL ?? Bundle.main.url(forResource: "catalog", withExtension: "sqlite")
    }

    /// The database, opened on first use. Opening reads two tiny tables, so it is cheap enough for the main actor.
    private var database: CatalogDatabase? {
        if !databaseOpened {
            databaseOpened = true
            openedDatabase = databaseURL.flatMap { CatalogDatabase(url: $0) }
        }
        return openedDatabase
    }

    /// Loads the browse pool off the main thread. Safe to call repeatedly.
    func load() async {
        if isLoaded { return }
        if let loadTask { return await loadTask.value }
        let database = self.database
        let task = Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> (books: [Book], stats: CatalogStats) in
                let pool = database?.pool() ?? []
                return (pool, CatalogStats(books: pool))
            }.value
            self.books = loaded.books
            self.stats = loaded.stats
            self.byID = Dictionary(loaded.books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.isLoaded = true
        }
        loadTask = task
        await task.value
    }

    /// Any catalog book by Open Library work id, in the pool or not.
    func book(id: String) -> Book? {
        if let known = byID[id] ?? recent[id] { return known }
        guard let found = database?.book(id: id) else { return nil }
        if recent.count >= Self.recentLimit { recent.removeAll(keepingCapacity: true) }
        recent[id] = found
        return found
    }

    /// Ranked search over every title and author. Every word typed must start a word in the title or author; exact
    /// titles come first, then titles that start with the query, then the rest, best-known first. A few milliseconds
    /// at 250,000 books, so it is fine to call on the main actor for each keystroke.
    func search(_ query: String, limit: Int = 40) -> [Book] {
        guard limit > 0, let expression = CatalogQuery.ftsExpression(for: query), let database else { return [] }
        let candidates = database.search(match: expression, limit: CatalogQuery.candidateLimit)
        return CatalogQuery.rank(candidates, query: query, limit: limit)
    }

    /// Rows for browsing: moods, genres, themes, series, authors, decades, time budgets and, once the reader has
    /// history, rows picked from their taste. Built off the main thread over the browse pool, since that is real work.
    func collections(context: RecommendationContext) async -> [BookCollection] {
        let books = books, stats = stats
        return await Task.detached(priority: .userInitiated) {
            CollectionBuilder(
                books: books, stats: stats, wpm: context.wpm, dailyMinutes: context.dailyMinutes,
                now: context.now, calendar: context.calendar, context: context
            ).build()
        }.value
    }

    /// Books like this one, by shared genres, themes and series, for "More like this". Off the main thread.
    func similar(to book: Book, context: RecommendationContext, limit: Int = 24) async -> [Recommendation] {
        let books = books, stats = stats
        return await Task.detached(priority: .userInitiated) {
            Recommender(stats: stats, context: context).similar(to: book, in: books, limit: limit)
        }.value
    }

    /// What the reader's shelves say they like, for the "Your taste" page. Off the main thread.
    func tasteProfile(context: RecommendationContext) async -> TasteProfile {
        let stats = stats
        return await Task.detached(priority: .userInitiated) {
            TasteProfileBuilder(stats: stats, context: context).build()
        }.value
    }

    /// A short, varied table of popular books for someone who has not read anything yet.
    func starterBooks(wpm: Double, excluding ids: Set<String>, count: Int = 12) -> [Book] {
        CollectionBuilder(books: books, stats: stats, wpm: wpm, dailyMinutes: 20, now: Date(), excluding: ids).starterBooks(count: count)
    }

    nonisolated static func normalize(_ text: String) -> String {
        CatalogQuery.normalize(text)
    }
}
