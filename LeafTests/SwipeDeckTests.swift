import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct SwipeDeckTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    private func pool() -> [Book] {
        var books: [Book] = []
        let spec: [(String, [String], [String])] = [
            ("fantasy", ["fantasy"], ["magic", "dragons"]),
            ("horror", ["horror"], ["ghosts", "monsters"]),
            ("romance", ["romance"], ["love stories"]),
            ("mystery", ["mystery"], ["detectives", "murder"]),
            ("scifi", ["science-fiction"], ["space & aliens"]),
            ("history", ["history"], ["war"]),
        ]
        for (index, entry) in spec.enumerated() {
            for n in 0..<40 {
                books.append(Book(
                    id: "\(entry.0)-\(n)", title: "\(entry.0.capitalized) Tale \(n)", author: "\(entry.0) author \(n % 12)",
                    year: 1980 + n, pages: 250 + n * 3, genres: entry.1, popularity: 5_000 - n * 40 - index, themes: entry.2
                ))
            }
        }
        return books
    }

    private func deck(seed: UInt64 = 1, library: [LibraryItem] = []) -> SwipeDeck {
        let books = pool()
        let context = RecommendationContext(library: library, sessions: [], dismissed: [], wpm: 250, dailyMinutes: 30, now: now, calendar: calendar())
        return SwipeDeck(pool: books, stats: CatalogStats(books: books), context: context, seed: seed)
    }

    @Test func aColdDeckProbesWidely() {
        var d = deck()
        let first = d.peek(8)
        #expect(first.count == 8)
        let genres = Set(first.compactMap { $0.book.genres.first })
        #expect(genres.count >= 4, "the first cards should sample several tastes")
        #expect(Set(first.map(\.id)).count == first.count)
    }

    @Test func cardsNeverRepeat() {
        var d = deck()
        var seen = Set<String>()
        for _ in 0..<120 {
            guard let card = d.swipe(.keep) else { break }
            #expect(seen.insert(card.id).inserted, "\(card.id) came up twice")
        }
        #expect(seen.count > 60)
    }

    @Test func theDeckFollowsWhatTheReaderSays() {
        var cold = deck()
        let before = cold.peek(10).filter { $0.book.genres.contains("fantasy") }.count

        var d = deck()
        // Keep fantasy and pass everything else, for the first dozen cards that show up.
        var swiped = 0
        while swiped < 14, let top = d.top {
            _ = d.swipe(top.book.genres.contains("fantasy") ? .keep : .pass)
            swiped += 1
        }
        let next = d.peek(10)
        let fantasy = next.filter { $0.book.genres.contains("fantasy") }.count
        let horror = next.filter { $0.book.genres.contains("horror") }.count
        #expect(fantasy > before, "fantasy should rise from \(before) once the reader keeps it, got \(fantasy)")
        #expect(fantasy >= 4, "got \(fantasy) fantasy of 10")
        #expect(horror <= 1, "passed genres fade, got \(horror) horror of 10")
    }

    @Test func undoPutsTheCardBackAndForgetsTheSwipe() {
        var d = deck()
        let first = d.top
        _ = d.swipe(.pass)
        #expect(d.passes.count == 1)
        let restored = d.undo()
        #expect(restored?.id == first?.id)
        #expect(d.top?.id == first?.id)
        #expect(d.passes.isEmpty && d.swipes.isEmpty)
        #expect(d.undo() == nil)
    }

    @Test func sortsSwipesIntoTheThreeBuckets() {
        var d = deck()
        _ = d.swipe(.keep); _ = d.swipe(.startNow); _ = d.swipe(.pass); _ = d.swipe(.keep)
        #expect(d.keeps.count == 2)
        #expect(d.starts.count == 1)
        #expect(d.passes.count == 1)
    }

    @Test func booksAlreadyInTheLibraryAreNeverDealt() {
        let owned = pool().filter { $0.id.hasPrefix("fantasy") }.map { LibraryItem(book: $0, shelf: .toRead, order: 0, addedAt: now) }
        var d = deck(library: owned)
        for card in d.peek(16) { #expect(!card.id.hasPrefix("fantasy")) }
    }

    @Test func sameSeedSameDeckAndAnEmptyPoolIsHandled() {
        var a = deck(seed: 5), b = deck(seed: 5), c = deck(seed: 6)
        #expect(a.peek(10).map(\.id) == b.peek(10).map(\.id))
        #expect(a.peek(10).map(\.id) != c.peek(10).map(\.id))
        var empty = SwipeDeck(pool: [], stats: CatalogStats(books: []), context: RecommendationContext(now: now, calendar: calendar()), seed: 1)
        #expect(empty.top == nil)
        #expect(empty.swipe(.keep) == nil)
        #expect(empty.peek(5).isEmpty)
    }

    @Test func exhaustingThePoolEndsGracefully() {
        let small = Array(pool().prefix(30))
        var d = SwipeDeck(pool: small, stats: CatalogStats(books: small), context: RecommendationContext(now: now, calendar: calendar()), seed: 3)
        var count = 0
        while d.swipe(.pass) != nil { count += 1; if count > 100 { break } }
        #expect(count <= 30)
        #expect(d.top == nil)
    }
}
