import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Fixtures

private struct Rec: Decodable {
    let id: String, t: String, a: String
    let y: Int?
    let p: Int
    let w: Int?
    let c: Int?
    let g: [String]?
    let pop: Int?
    let th: [String]?
    var book: Book { Book(id: id, title: t, author: a, year: y, pages: p, words: w, coverID: c, genres: g ?? [], popularity: pop ?? 0, themes: th) }
}

/// The real bundled catalog, or nil if the file isn't reachable from where the tests run.
private func realCatalog() -> [Book]? {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Leaf/Resources/books.json")
    guard let data = try? Data(contentsOf: url), let records = try? JSONDecoder().decode([Rec].self, from: data) else { return nil }
    return records.map(\.book)
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}
private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: now)! }

private func book(_ id: String, _ author: String, genres: [String], themes: [String] = [], year: Int = 2005, pages: Int = 320, pop: Int = 100) -> Book {
    Book(id: id, title: "Book \(id)", author: author, year: year, pages: pages, words: pages * 270, genres: genres, popularity: pop, themes: themes)
}

private func finished(_ b: Book, started: Int = 14, finishedAgo: Int = 2, rating: Int? = nil) -> LibraryItem {
    var item = LibraryItem(book: b, shelf: .finished, currentPage: b.pages, order: 0, startedAt: day(started), finishedAt: day(finishedAgo), rating: rating)
    item.currentPage = b.pages
    return item
}

private func context(_ items: [LibraryItem] = [], dismissed: [Book] = [], sessions: [ReadingSession] = []) -> RecommendationContext {
    RecommendationContext(library: items, sessions: sessions, dismissed: dismissed, wpm: 250, dailyMinutes: 30, now: now, calendar: calendar)
}

/// A mixed catalog: lots of fantasy and mystery, some romance and nonfiction, with varied authors and popularity.
private func mixedCatalog(count: Int = 600) -> [Book] {
    var rng = SeededGenerator(seed: 7)
    let genreSets: [[String]] = [["fantasy"], ["fantasy", "young-adult"], ["mystery"], ["mystery", "thriller"], ["romance"], ["science-fiction"], ["history"], ["self-help"], ["classics", "literary"], ["horror"]]
    let themeSets: [String: [String]] = [
        "fantasy": ["magic", "dragons", "quests"], "mystery": ["detectives", "murder", "secrets"], "romance": ["love stories", "second chances"],
        "science-fiction": ["space & aliens", "robots & ai"], "history": ["war", "history & the past"], "self-help": ["habits & mindset"], "classics": ["england"], "horror": ["ghosts", "monsters"],
    ]
    return (0..<count).map { i in
        let genres = genreSets[Int(rng.next() % UInt64(genreSets.count))]
        let pool = themeSets[genres[0]] ?? []
        let themes = pool.filter { _ in rng.unit() < 0.6 }
        return book("c\(i)", "Author \(i % 90)", genres: genres, themes: themes, year: 1950 + Int(rng.next() % 70), pages: 120 + Int(rng.next() % 500), pop: Int(rng.next() % 5000))
    }
}

// MARK: - Engagement and taste

struct EngagementTests {
    @Test func finishingFastBeatsFinishingSlowly() {
        let b = book("a", "A", genres: ["fantasy"], pages: 300)
        let fast = finished(b, started: 5, finishedAgo: 1)
        let slow = finished(b, started: 200, finishedAgo: 1)
        let f = Engagement.score(for: fast, sessions: [], wpm: 250, dailyMinutes: 30, now: now, calendar: calendar)
        let s = Engagement.score(for: slow, sessions: [], wpm: 250, dailyMinutes: 30, now: now, calendar: calendar)
        #expect(f > s)
        #expect(f > 0.6 && s > 0)
    }

    @Test func stalledBooksAreNegative() {
        let b = book("a", "A", genres: ["fantasy"])
        var item = LibraryItem(book: b, shelf: .reading, currentPage: 40, order: 0, startedAt: day(90))
        item.addedAt = day(95)
        let stalled = Engagement.score(for: item, sessions: [], wpm: 250, dailyMinutes: 30, now: now, calendar: calendar)
        #expect(stalled < 0)
        #expect(Engagement.isStalled(item, sessions: [], now: now, calendar: calendar))
        let active = ReadingSession(bookID: "a", startedAt: day(1), seconds: 1500, fromPage: 30, toPage: 40)
        let healthy = Engagement.score(for: item, sessions: [active], wpm: 250, dailyMinutes: 30, now: now, calendar: calendar)
        #expect(healthy > 0)
    }

    @Test func ratingsOverride() {
        let b = book("a", "A", genres: ["fantasy"])
        let loved = Engagement.score(for: finished(b, rating: 5), sessions: [], wpm: 250, dailyMinutes: 30, now: now, calendar: calendar)
        let hated = Engagement.score(for: finished(b, rating: 1), sessions: [], wpm: 250, dailyMinutes: 30, now: now, calendar: calendar)
        #expect(loved > 0.8 && hated < -0.5)
    }

    @Test func profileLearnsGenresAuthorsAndLength() {
        let books = mixedCatalog()
        let stats = CatalogStats(books: books)
        let favourites = books.filter { $0.genres == ["fantasy"] }.prefix(5).map { finished($0) }
        let profile = TasteProfileBuilder(stats: stats, context: context(Array(favourites))).build()
        #expect(profile.topGenres.first == "fantasy")
        #expect(!profile.isCold)
        #expect(profile.logHoursMean != nil)
        #expect(profile.anchors.count == 5)
        #expect(TasteProfileBuilder(stats: stats, context: context()).build().isCold)
    }
}

// MARK: - Recommending

struct RecommenderTests {
    let books = mixedCatalog()

    func fantasyReader() -> (Recommender, [LibraryItem]) {
        let stats = CatalogStats(books: books)
        let items = books.filter { $0.genres.contains("fantasy") }.prefix(6).map { finished($0) }
        return (Recommender(stats: stats, context: context(Array(items))), Array(items))
    }

    @Test func aFantasyReaderGetsMostlyFantasy() {
        let (recommender, items) = fantasyReader()
        let picks = recommender.recommend(from: books, limit: 12, seed: 1)
        #expect(picks.count == 12)
        let fantasy = picks.filter { $0.book.genres.contains("fantasy") }.count
        #expect(fantasy >= 7, "expected mostly fantasy, got \(fantasy) of 12")
        let owned = Set(items.map(\.id))
        #expect(picks.allSatisfy { !owned.contains($0.book.id) })
    }

    @Test func dismissedBooksNeverReturnAndPushTasteAway() {
        let stats = CatalogStats(books: books)
        let horror = books.filter { $0.genres == ["horror"] }.prefix(5)
        let items = books.filter { $0.genres.contains("fantasy") }.prefix(5).map { finished($0) }
        let without = Recommender(stats: stats, context: context(Array(items)))
        let with = Recommender(stats: stats, context: context(Array(items), dismissed: Array(horror)))
        let picks = with.recommend(from: books, limit: 20, seed: 3)
        #expect(picks.allSatisfy { p in !horror.contains { $0.id == p.book.id } })
        let horrorShare = { (r: Recommender) in r.recommend(from: books, limit: 30, seed: 3).filter { $0.book.genres.contains("horror") }.count }
        #expect(horrorShare(with) <= horrorShare(without))
    }

    @Test func authorsAreCappedForVariety() {
        let stats = CatalogStats(books: books)
        let loved = books.filter { $0.author == "Author 3" }.prefix(4).map { finished($0) }
        let picks = Recommender(stats: stats, context: context(Array(loved))).recommend(from: books, limit: 15, seed: 5, maxPerAuthor: 2)
        let counts = Dictionary(grouping: picks, by: { TasteProfile.normalizeAuthor($0.book.author) }).mapValues(\.count)
        #expect(counts.values.max() ?? 0 <= 2)
    }

    @Test func authorNamesMatchAcrossFormatting() {
        let tolkien = ["J. R. R. Tolkien", "J.R.R. Tolkien", "JRR Tolkien", "j r r  tolkien"].map(TasteProfile.normalizeAuthor)
        #expect(Set(tolkien).count == 1)
        #expect(TasteProfile.normalizeAuthor("Ursula K. Le Guin") == "ursula k le guin")
        #expect(TasteProfile.normalizeAuthor("C. S. Lewis") == TasteProfile.normalizeAuthor("CS Lewis"))
        #expect(TasteProfile.normalizeAuthor("Gabriel García Márquez") == "gabriel garcia marquez")
        #expect(TasteProfile.normalizeAuthor("1984") != TasteProfile.normalizeAuthor("1985"))
    }

    @Test func sameSeedSameResultsDifferentDaysDiffer() {
        let (recommender, _) = fantasyReader()
        let a = recommender.recommend(from: books, limit: 15, seed: 11).map(\.book.id)
        let b = recommender.recommend(from: books, limit: 15, seed: 11).map(\.book.id)
        let c = recommender.recommend(from: books, limit: 15, seed: 99).map(\.book.id)
        #expect(a == b)
        #expect(a != c)
        // But the core of the list is stable: most books survive a reshuffle.
        #expect(Set(a).intersection(c).count >= 6)
    }

    @Test func newReadersGetPopularBooksAndHonestReasons() {
        let stats = CatalogStats(books: books)
        let recommender = Recommender(stats: stats, context: context())
        let picks = recommender.recommend(from: books, limit: 10, seed: 1)
        #expect(picks.count == 10)
        let average = picks.map { stats.percentile(ofPopularity: $0.book.popularity) }.reduce(0, +) / 10
        #expect(average > 0.7)
        #expect(picks.allSatisfy { if case .popularInGenre = $0.reason { return true } else { return $0.reason == .popular } })
    }

    @Test func reasonsPointAtSomethingTrue() {
        let stats = CatalogStats(books: books)
        let owned = book("own", "Loved Author", genres: ["fantasy"], themes: ["dragons", "magic"])
        let sameAuthor = book("next", "Loved Author", genres: ["fantasy"], themes: ["dragons"])
        let similar = book("sim", "Someone", genres: ["fantasy"], themes: ["dragons", "magic"])
        let recommender = Recommender(stats: stats, context: context([finished(owned, rating: 5)]))
        let picks = recommender.recommend(from: [sameAuthor, similar] + books, limit: 6, seed: 2, exploration: 0)
        let next = picks.first { $0.book.id == "next" }
        if case .moreBy(let author, let because)? = next?.reason {
            #expect(author == "Loved Author")
            #expect(because == owned.title)
        } else { Issue.record("expected moreBy, got \(String(describing: next?.reason))") }
        #expect(picks.first { $0.book.id == "sim" }.map { $0.reason.text.contains(owned.title) } == true)
    }

    @Test func seriesContinuesAndSimilarFindsNeighbours() {
        let stats = CatalogStats(books: books)
        let one = book("s1", "Writer", genres: ["fantasy"], themes: ["series:green hills", "magic"])
        let two = book("s2", "Writer", genres: ["fantasy"], themes: ["series:green hills", "magic"])
        let other = book("o1", "Other", genres: ["romance"], themes: ["love stories"])
        let recommender = Recommender(stats: stats, context: context([finished(one, rating: 5)]))
        let similar = recommender.similar(to: one, in: [two, other] + books, limit: 5)
        #expect(similar.first?.book.id == "s2")
    }

    @Test func finishLikelihoodFallsForLengthsTheyDrop() {
        let stats = CatalogStats(books: books)
        let longBooks = books.filter { $0.pages > 500 }.prefix(3)
        var items = longBooks.map { b -> LibraryItem in
            var item = LibraryItem(book: b, shelf: .reading, currentPage: 30, order: 0, startedAt: day(120))
            item.addedAt = day(125)
            return item
        }
        items.append(finished(books.first { $0.pages < 250 }!))
        let recommender = Recommender(stats: stats, context: context(items))
        let long = books.first { $0.pages > 520 }!
        let short = books.first { $0.pages < 200 }!
        #expect(recommender.finishLikelihood(for: long, content: 0) < recommender.finishLikelihood(for: short, content: 0))
    }

    @Test func scoringALargePoolIsFast() {
        let big = mixedCatalog(count: 40_000)
        let stats = CatalogStats(books: big)
        let items = big.filter { $0.genres.contains("mystery") }.prefix(8).map { finished($0) }
        let recommender = Recommender(stats: stats, context: context(Array(items)))
        let start = Date()
        let picks = recommender.recommend(from: big, limit: 30, seed: 1)
        #expect(picks.count == 30)
        #expect(Date().timeIntervalSince(start) < 15, "took \(Date().timeIntervalSince(start)) s")
    }
}

// MARK: - The carousels

struct CollectionTests {
    @Test func theRealCatalogMakesAGenuinelyBigShelf() throws {
        guard let books = realCatalog() else { return }
        let stats = CatalogStats(books: books)
        let rows = CollectionBuilder(books: books, stats: stats, wpm: 250, dailyMinutes: 30, now: now, calendar: calendar).build()

        #expect(rows.count >= 90, "only \(rows.count) rows")
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.allSatisfy { $0.books.count >= 8 })
        #expect(rows.allSatisfy { Set($0.books.map(\.id)).count == $0.books.count })
        #expect(rows.contains { $0.kind == .context })
        #expect(rows.first?.id == "loved", "a new reader starts with what's popular")

        let kinds = Set(rows.map { $0.id.split(separator: "-").first.map(String.init) ?? $0.id })
        for expected in ["mood", "genre", "theme", "time", "series", "author", "decade", "gems", "quick"] {
            #expect(kinds.contains(expected), "missing \(expected) rows")
        }
        // The same book shouldn't fill the screen.
        var seen: [String: Int] = [:]
        for row in rows { for b in row.books { seen[b.id, default: 0] += 1 } }
        #expect((seen.values.max() ?? 0) <= 5)
        let distinct = seen.count
        #expect(distinct >= 1500, "rows only reach \(distinct) different books")
    }

    @Test func moodRowsAreBelievable() {
        guard let books = realCatalog() else { return }
        let stats = CatalogStats(books: books)
        let rows = CollectionBuilder(books: books, stats: stats, wpm: 250, dailyMinutes: 30, now: now, calendar: calendar, rowSize: 60).build()
        if let spooky = rows.first(where: { $0.id == "mood-spooky" }) {
            let spookyShare = Double(spooky.books.filter { $0.genres.contains("horror") || ($0.themes ?? []).contains(where: { ["ghosts", "gothic", "vampires", "witches", "monsters"].contains($0) }) }.count) / Double(spooky.books.count)
            #expect(spookyShare > 0.9)
        }
        if let cozy = rows.first(where: { $0.id == "mood-cozy" }) {
            #expect(!cozy.books.contains { $0.genres.contains("horror") })
        }
    }

    @Test func rowsAreStableWithinADayAndChangeBetweenDays() {
        guard let books = realCatalog() else { return }
        let stats = CatalogStats(books: books)
        func ids(_ date: Date) -> [String] { CollectionBuilder(books: books, stats: stats, wpm: 250, dailyMinutes: 30, now: date, calendar: calendar).build().map(\.id) }
        #expect(ids(now) == ids(now.addingTimeInterval(3_600)))
        #expect(ids(now) != ids(now.addingTimeInterval(86_400 * 3)))
    }

    @Test func timeRowsFollowTheReadersPace() {
        guard let books = realCatalog() else { return }
        let stats = CatalogStats(books: books)
        func row(_ minutes: Int, _ id: String) -> BookCollection? {
            CollectionBuilder(books: books, stats: stats, wpm: 250, dailyMinutes: minutes, now: now, calendar: calendar).build().first { $0.id == id }
        }
        let slow = row(15, "time-week"), quick = row(90, "time-week")
        if let slow, let quick {
            let hours = { (r: BookCollection) in r.books.map { $0.minutes(atWPM: 250) / 60 }.reduce(0, +) / Double(r.books.count) }
            #expect(hours(quick) > hours(slow))
        }
    }

    @Test func personalRowsLeadAndExplainThemselves() {
        guard let books = realCatalog() else { return }
        let stats = CatalogStats(books: books)
        let owned = books.filter { $0.genres.contains("fantasy") }.prefix(8)
        let ctx = context(owned.map { finished($0) })
        let rows = CollectionBuilder(books: books, stats: stats, wpm: 250, dailyMinutes: 30, now: now, calendar: calendar, context: ctx).build()
        #expect(rows.first?.id == "for-you")
        #expect(rows.first?.kind == .personal)
        let top = rows[0]
        #expect(top.books.count >= 20)
        #expect(top.books.allSatisfy { top.reasons[$0.id] != nil })
        #expect(top.books.filter { $0.genres.contains("fantasy") }.count >= top.books.count / 2)
        #expect(rows.contains { $0.id.hasPrefix("because-") })
        let ownedIDs = Set(owned.map(\.id))
        #expect(rows.allSatisfy { row in row.books.allSatisfy { !ownedIDs.contains($0.id) } })
    }
}
