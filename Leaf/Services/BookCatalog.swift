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

    var book: Book {
        Book(id: id, title: t, author: a, year: y, pages: p, words: w, coverID: c, genres: g ?? [], popularity: pop ?? 0)
    }
}

/// A themed row on the Search tab.
struct BookCollection: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var books: [Book]
}

/// The offline catalog: thousands of popular and classic books, searchable without a connection.
@MainActor
@Observable
final class BookCatalog {
    static let shared = BookCatalog()

    private(set) var books: [Book] = []
    private(set) var isLoaded = false

    @ObservationIgnored private var index: [(book: Book, title: String, author: String, words: [String])] = []
    @ObservationIgnored private var byID: [String: Book] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Loads `books.json` off the main thread. Safe to call repeatedly.
    func load() async {
        if isLoaded { return }
        if let loadTask { return await loadTask.value }
        let task = Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> [Book] in
                guard let url = Bundle.main.url(forResource: "books", withExtension: "json"),
                      let data = try? Data(contentsOf: url),
                      let records = try? JSONDecoder().decode([CatalogRecord].self, from: data) else { return [] }
                return records.map(\.book)
            }.value
            self.books = loaded
            self.byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.index = loaded.map { book in
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

    /// Curated rows for browsing, tuned to the reader's speed.
    func collections(wpm: Double, excluding ids: Set<String> = []) -> [BookCollection] {
        let pool = books.filter { !ids.contains($0.id) }
        func genre(_ tags: Set<String>) -> [Book] { pool.filter { !tags.isDisjoint(with: $0.genres) } }
        func top(_ list: [Book], _ count: Int = 24) -> [Book] { Array(list.prefix(count)) }

        var rows: [BookCollection] = [
            BookCollection(id: "loved", title: "Loved by readers", subtitle: "The most-shelved books in the catalog", books: top(pool)),
            BookCollection(id: "short", title: "Short reads", subtitle: "Under four hours at your pace", books: top(pool.filter { $0.minutes(atWPM: wpm) < 240 && $0.pages >= 80 })),
            BookCollection(id: "classics", title: "Classics", subtitle: "Still worth the hype", books: top(genre(["classics"]))),
            BookCollection(id: "fantasy", title: "Other worlds", subtitle: "Fantasy and science fiction", books: top(genre(["fantasy", "science-fiction"]))),
            BookCollection(id: "mystery", title: "Page-turners", subtitle: "Mysteries and thrillers", books: top(genre(["mystery", "thriller"]))),
            BookCollection(id: "true", title: "True stories", subtitle: "Biography, memoir and history", books: top(genre(["biography", "memoir", "history"]))),
            BookCollection(id: "ideas", title: "Big ideas", subtitle: "Science, philosophy and psychology", books: top(genre(["science", "philosophy", "psychology"]))),
            BookCollection(id: "long", title: "Long haul", subtitle: "Big books for slow evenings", books: top(pool.filter { $0.minutes(atWPM: wpm) > 900 })),
        ]
        rows.removeAll { $0.books.count < 4 }
        return rows
    }

    nonisolated static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
