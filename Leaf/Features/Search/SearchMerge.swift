import Foundation

/// Pure helpers for the Search tab: merging the bundled catalog with Open Library, and keeping stale
/// live results honest while a new query is still on its way.
enum SearchMerge {
    /// Title and author folded the way the catalog folds them, so "Dune / Frank Herbert" matches across sources.
    static func key(for book: Book) -> String {
        BookCatalog.normalize(book.title) + "|" + BookCatalog.normalize(book.author)
    }

    /// Catalog results first, then anything new from Open Library. Duplicates (same id, or the same
    /// title and author) keep the catalog copy, which has the better word count.
    static func merge(local: [Book], remote: [Book]) -> [Book] {
        var ids = Set<String>()
        var keys = Set<String>()
        var merged: [Book] = []
        merged.reserveCapacity(local.count + remote.count)
        for book in local + remote {
            guard ids.insert(book.id).inserted else { continue }
            guard keys.insert(key(for: book)).inserted else { continue }
            merged.append(book)
        }
        return merged
    }

    /// Whether every word of `query` starts a word in the book's title or author (the catalog's own rule).
    static func matches(_ book: Book, query: String) -> Bool {
        let terms = BookCatalog.normalize(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return false }
        let words = BookCatalog.normalize(book.title + " " + book.author).split(separator: " ").map(String.init)
        return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
    }
}
