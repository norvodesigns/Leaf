import Foundation
import Observation

/// One row of the bundled `books.json` (short keys keep the file small).
struct CatalogRecord: Decodable, Sendable {
    let id: String
    let t: String
    let a: String
    let y: Int?
    let p: Int
    let w: Int?
    let c: Int?
    let g: [String]?
    let pop: Int?
    let th: [String]?

    var book: Book {
        Book(id: id, title: t, author: a, year: y, pages: p, words: w, coverID: c, genres: g ?? [], popularity: pop ?? 0, themes: th)
    }
}

/// The offline catalog: thousands of popular and classic books, searchable without a connection.
@MainActor
@Observable
final class BookCatalog {
    static let shared = BookCatalog()

    private(set) var books: [Book] = []
    private(set) var isLoaded = false
    /// Corpus-wide counts the recommender weighs features by; built once, right after the books load.
    @ObservationIgnored private(set) var stats = CatalogStats(books: [])

    @ObservationIgnored private var index: [(book: Book, title: String, author: String, words: [String])] = []
    @ObservationIgnored private var byID: [String: Book] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Loads `books.json` off the main thread. Safe to call repeatedly.
    func load() async {
        if isLoaded { return }
        if let loadTask { return await loadTask.value }
        let task = Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> (books: [Book], stats: CatalogStats) in
                guard let url = Bundle.main.url(forResource: "books", withExtension: "json"),
                      let data = try? Data(contentsOf: url),
                      let records = try? JSONDecoder().decode([CatalogRecord].self, from: data) else { return ([], CatalogStats(books: [])) }
                let books = records.map(\.book)
                return (books, CatalogStats(books: books))
            }.value
            self.books = loaded.books
            self.stats = loaded.stats
            self.byID = Dictionary(loaded.books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.index = loaded.books.map { book in
                let title = BookCatalog.normalize(book.title)
                let author = BookCatalog.normalize(book.author)
                return (book, title, author, (title + " " + author).split(separator: " ").map(String.init))
            }
            self.isLoaded = true
        }
        loadTask = task
        await task.value
    }

    func book(id: String) -> Book? { byID[id] }

    /// Ranked local search over titles and authors. Every query word must prefix-match a word.
    func search(_ query: String, limit: Int = 40) -> [Book] {
        let normalized = BookCatalog.normalize(query)
        let terms = normalized.split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        var scored: [(Book, Double)] = []
        for entry in index {
            guard terms.allSatisfy({ term in entry.words.contains { $0.hasPrefix(term) } }) else { continue }
            var score = log(Double(entry.book.popularity) + 10)
            if entry.title == normalized { score += 40 }
            else if entry.title.hasPrefix(normalized) { score += 20 }
            else if entry.title.contains(normalized) { score += 8 }
            if entry.author.contains(normalized) { score += 10 }
            scored.append((entry.book, score))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// Rows for browsing: moods, genres, themes, series, authors, decades, time budgets and, once the reader has
    /// history, rows picked from their taste. Built off the main thread, since a big catalog makes this real work.
    func collections(context: RecommendationContext) async -> [BookCollection] {
        let books = books, stats = stats
        return await Task.detached(priority: .userInitiated) {
            CollectionBuilder(
                books: books, stats: stats, wpm: context.wpm, dailyMinutes: context.dailyMinutes,
                now: context.now, calendar: context.calendar, context: context
            ).build()
        }.value
    }

    /// A short, varied table of popular books for someone who has not read anything yet.
    func starterBooks(wpm: Double, excluding ids: Set<String>, count: Int = 12) -> [Book] {
        CollectionBuilder(books: books, stats: stats, wpm: wpm, dailyMinutes: 20, now: Date(), excluding: ids).starterBooks(count: count)
    }

    nonisolated static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
