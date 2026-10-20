import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Fixtures

private var swCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}

private func swDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 21) -> Date {
    swCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private let swNow = swDate(2026, 10, 20, 12)

private func swBook(_ id: String, pages: Int = 300, genres: [String] = ["fantasy"]) -> Book {
    Book(id: id, title: "Book \(id)", author: "Author \(id)", year: 2000, pages: pages, words: pages * 270, genres: genres)
}

private func swSession(_ book: String, _ date: Date, minutes: Double = 30, from: Int = 0, to: Int = 10, tea: String? = nil) -> ReadingSession {
    let hash = SeededGenerator.hash("\(book)|\(date.timeIntervalSince1970)|\(from)|\(to)")
    let tail = String(format: "%012llx", hash & 0xFFFF_FFFF_FFFF)
    return ReadingSession(id: UUID(uuidString: "00000000-0000-0000-0000-\(tail)")!, bookID: book, startedAt: date, seconds: minutes * 60, fromPage: from, toPage: to, kind: .timed, teaID: tea)
}

private func swFinished(_ book: Book, started: Date?, finished: Date?, rating: Int? = nil, added: Date? = nil, reads: [ReadThrough] = []) -> LibraryItem {
    LibraryItem(
        book: book, shelf: .finished, currentPage: book.pages, order: 0, addedAt: added ?? started ?? finished ?? swNow,
        startedAt: started, finishedAt: finished, rating: rating, updatedAt: finished ?? swNow, reads: reads
    )
}

private func swSpine(_ id: String, width: Double) -> ShelfSpine {
    ShelfSpine(book: swBook(id), year: 2026, finishedAt: nil, rating: nil, finishes: 1, teaID: nil, width: width, height: 0.9)
}

/// Six books across three years: rereads, an undated finish, a book being read again, one still to read.
private func swShelfData() -> LeafData {
    var data = LeafData()
    let a = swBook("a", pages: 150)
    let b = swBook("b", pages: 600)
    let c = swBook("c")
    let d = swBook("d")
    let e = swBook("e")
    let f = swBook("f")
    data.items = [
        swFinished(a, started: swDate(2026, 2, 15), finished: swDate(2026, 3, 1), rating: 5, reads: [
            ReadThrough(bookID: "a", startedAt: swDate(2024, 4, 1), finishedAt: swDate(2024, 5, 1), rating: 3),
        ]),
        swFinished(b, started: swDate(2026, 1, 1), finished: swDate(2026, 1, 10), rating: 9),
        swFinished(c, started: nil, finished: nil, rating: 4, added: swDate(2025, 7, 1)),
        LibraryItem(book: d, shelf: .reading, currentPage: 40, order: 0, addedAt: swDate(2024, 12, 1), startedAt: swDate(2026, 8, 20), reads: [
            ReadThrough(bookID: "d", startedAt: swDate(2025, 1, 2), finishedAt: swDate(2025, 2, 1)),
        ]),
        LibraryItem(book: e, shelf: .toRead, order: 0, addedAt: swDate(2026, 5, 1)),
        swFinished(f, started: swDate(2026, 7, 1), finished: swDate(2026, 8, 1), rating: 5, reads: [
            ReadThrough(bookID: "f", startedAt: swDate(2026, 1, 20), finishedAt: swDate(2026, 2, 1), rating: 4),
        ]),
    ]
    data.sessions = [
        // a, first read: no tea.
        swSession("a", swDate(2024, 4, 20)),
        // a, second read: more earl grey than sencha.
        swSession("a", swDate(2026, 2, 20), minutes: 30, tea: "sencha"),
        swSession("a", swDate(2026, 2, 25), minutes: 20, tea: "earl-grey"),
        swSession("a", swDate(2026, 2, 26), minutes: 20, tea: "earl-grey"),
        // d, read again now with matcha: not the 2025 read's tea.
        swSession("d", swDate(2026, 9, 1), tea: "matcha"),
    ]
    return data
}

// MARK: - Shelf wall

struct ShelfWallTests {
    @Test func longerBooksStandThickerWithinBounds() {
        #expect(ShelfWall.spineWidth(pages: 0) == ShelfWall.minimumWidth)
        #expect(ShelfWall.spineWidth(pages: 150) == 10 + 150.0 / 16)
        #expect(ShelfWall.spineWidth(pages: 5_000) == ShelfWall.maximumWidth)
        var last = 0.0
        for pages in stride(from: 0, through: 1_200, by: 50) {
            let width = ShelfWall.spineWidth(pages: pages)
            #expect(width >= last)
            last = width
        }
    }

    @Test func heightsAreUnevenButTheSameEveryTime() {
        let heights = (0..<200).map { ShelfWall.spineHeight(bookID: "book-\($0)") }
        #expect(heights.allSatisfy { $0 >= 0.8 && $0 <= 1 })
        #expect(Set(heights).count > 100)
        #expect(ShelfWall.spineHeight(bookID: "OL27482W") == ShelfWall.spineHeight(bookID: "OL27482W"))
    }

    @Test func aShelfForEveryYearNewestFirstInTheOrderTheyWereFinished() {
        let wall = ShelfWall.build(data: swShelfData(), calendar: swCalendar)
        #expect(wall.years.map { $0.year } == [2026, 2025, 2024])
        #expect(wall.years[0].spines.map { $0.book.id } == ["b", "a", "f"])
        // The book being read again stands in the year of its earlier finish; the undated finish comes last.
        #expect(wall.years[1].spines.map { $0.book.id } == ["d", "c"])
        #expect(wall.years[2].spines.map { $0.book.id } == ["a"])
        #expect(wall.spineCount == 6)
        let all = wall.years.flatMap { $0.spines }
        #expect(!all.contains { $0.book.id == "e" })
    }

    @Test func aBookFinishedTwiceInAYearStandsOnceAndCountsBoth() throws {
        let wall = ShelfWall.build(data: swShelfData(), calendar: swCalendar)
        let f = try #require(wall.years[0].spines.first { $0.book.id == "f" })
        #expect(f.finishes == 2)
        #expect(f.finishedAt == swDate(2026, 8, 1))
        #expect(f.rating == 5)
        #expect(f.isFavorite)
        #expect(wall.years[0].finishes == 4)
        #expect(wall.years[0].pages == 600 + 150 + 300 * 2)
    }

    @Test func ratingsAndFavouritesComeFromEachFinish() throws {
        let wall = ShelfWall.build(data: swShelfData(), calendar: swCalendar)
        let a2026 = try #require(wall.years[0].spines.first { $0.book.id == "a" })
        let a2024 = try #require(wall.years[2].spines.first { $0.book.id == "a" })
        #expect(a2026.rating == 5 && a2026.isFavorite)
        #expect(a2024.rating == 3 && !a2024.isFavorite)
        // A rating outside one to five isn't a rating.
        let b = try #require(wall.years[0].spines.first { $0.book.id == "b" })
        #expect(b.rating == nil)
        let c = try #require(wall.years[1].spines.first { $0.book.id == "c" })
        #expect(c.finishedAt == nil && c.rating == 4)
    }

    @Test func theTeaRingGoesToTheReadThroughItWasDrunkWith() throws {
        let wall = ShelfWall.build(data: swShelfData(), calendar: swCalendar)
        let a2026 = try #require(wall.years[0].spines.first { $0.book.id == "a" })
        let a2024 = try #require(wall.years[2].spines.first { $0.book.id == "a" })
        #expect(a2026.teaID == "earl-grey")
        #expect(a2026.hasTea)
        #expect(a2024.teaID == nil)
        // Tea with the book being read now belongs to no finished read-through yet.
        let d = try #require(wall.years[1].spines.first { $0.book.id == "d" })
        #expect(d.teaID == nil)
    }

    @Test func spinesPackIntoRowsInOrder() {
        let spines = [swSpine("1", width: 20), swSpine("2", width: 30), swSpine("3", width: 25), swSpine("4", width: 40), swSpine("5", width: 50)]
        let rows = ShelfWall.rows(spines, width: 100, spacing: 2)
        let ids: [[String]] = rows.map { row in row.map { $0.book.id } }
        #expect(ids == [["1", "2", "3"], ["4", "5"]])
        // A spine wider than the row stands alone.
        let wide = ShelfWall.rows([swSpine("1", width: 20), swSpine("2", width: 150), swSpine("3", width: 20)], width: 100, spacing: 2)
        #expect(wide.map { $0.count } == [1, 1, 1])
        #expect(ShelfWall.rows(spines, width: 0, spacing: 2).count == 1)
        #expect(ShelfWall.rows([], width: 100, spacing: 2).isEmpty)
    }

    @Test func fiveHundredBooksAndMoreBuildAndPackWithoutLosingOne() {
        var data = LeafData()
        for index in 0..<640 {
            let book = swBook("bulk-\(index)", pages: 80 + (index * 37) % 900)
            let finished = swDate(2016 + index % 11, 1 + index % 12, 1 + index % 27)
            data.items.append(swFinished(book, started: finished.addingTimeInterval(-86_400 * 9), finished: finished, rating: 1 + index % 5))
            data.sessions.append(swSession(book.id, finished.addingTimeInterval(-3_600), tea: index % 3 == 0 ? "sencha" : nil))
        }
        let wall = ShelfWall.build(data: data, calendar: swCalendar)
        #expect(wall.spineCount == 640)
        #expect(wall.years.count == 11)
        for year in wall.years {
            let rows = ShelfWall.rows(year.spines, width: 358, spacing: 2)
            let packed: [String] = rows.flatMap { $0 }.map { $0.id }
            #expect(packed == year.spines.map { $0.id })
            for row in rows {
                var used = Double(row.count - 1) * 2
                for spine in row { used += spine.width }
                #expect(used <= 358)
            }
        }
        let withTea = wall.years.flatMap { $0.spines }.filter { $0.hasTea }
        #expect(withTea.count == 214)
    }
}

// MARK: - Reading Wrapped

/// A year with two books: a slow one read at nine with Earl Grey (and once at seven), and a quick one read ten
/// evenings running, three of them with sencha. Three quotes, two of them from the quick one.
private func swYearData() -> LeafData {
    var data = LeafData()
    let slow = swBook("slow", pages: 280, genres: ["fantasy"])
    let quick = swBook("quick", pages: 200, genres: ["mystery"])
    data.items = [
        swFinished(slow, started: swDate(2026, 1, 5), finished: swDate(2026, 2, 20), rating: 5),
        swFinished(quick, started: swDate(2026, 3, 1), finished: swDate(2026, 3, 10), rating: 4),
    ]
    var page = 0
    for week in 0..<7 {
        let day = swCalendar.date(byAdding: .day, value: week * 7, to: swDate(2026, 1, 5))!
        data.sessions.append(swSession("slow", day, minutes: 40, from: page, to: page + 40, tea: "earl-grey"))
        page += 40
    }
    data.sessions.append(swSession("slow", swDate(2026, 1, 6, 7), minutes: 20, from: 120, to: 130))
    page = 0
    for offset in 0..<10 {
        let day = swCalendar.date(byAdding: .day, value: offset, to: swDate(2026, 3, 1))!
        data.sessions.append(swSession("quick", day, minutes: 25, from: page, to: page + 20, tea: offset < 3 ? "sencha" : "earl-grey"))
        page += 20
    }
    data.journal = [
        JournalEntry(bookID: "slow", bookTitle: "Book slow", bookAuthor: "Author slow", kind: .quote, text: "A slow line.", page: 12, createdAt: swDate(2026, 1, 20)),
        JournalEntry(bookID: "quick", bookTitle: "Book quick", bookAuthor: "Author quick", kind: .quote, text: "The one I loved.", page: 30, isFavorite: true, createdAt: swDate(2026, 3, 2)),
        JournalEntry(bookID: "quick", bookTitle: "Book quick", bookAuthor: "Author quick", kind: .quote, text: "A later line.", page: 90, createdAt: swDate(2026, 3, 6)),
        JournalEntry(bookID: "quick", bookTitle: "Book quick", bookAuthor: "Author quick", kind: .thought, text: "Not a quote.", page: 91, createdAt: swDate(2026, 3, 7)),
    ]
    return data
}

struct WrappedStoryTests {
    private func story(_ data: LeafData, year: Int = 2026) -> WrappedStory {
        InsightsEngine(data: data, now: swNow, calendar: swCalendar).wrappedStory(year: year)
    }

    @Test func aFullYearTellsEightCardsInOrder() {
        let wrapped = story(swYearData())
        #expect(wrapped.cards == [.books, .tea, .hour, .streak, .slowBurn, .quoted, .personality, .shelf])
        #expect(wrapped.summary.booksFinished == 2)
        #expect(!wrapped.isEmpty)
    }

    @Test func theTeaOfTheYearIsTheOneOfMostSittings() throws {
        let tea = try #require(story(swYearData()).tea)
        #expect(tea.teaID == "earl-grey")
        #expect(tea.name == "Earl Grey")
        #expect(tea.family == .black)
        #expect(tea.sittings == 14)
        #expect(tea.teaSittings == 17)
        #expect(tea.allSittings == 18)
        #expect(abs(tea.minutes - (7 * 40 + 7 * 25)) < 1e-6)
    }

    @Test func theBestHourCarriesItsShareOfTheYear() throws {
        let hour = try #require(story(swYearData()).hour)
        #expect(hour.hour == 21)
        let total = 7 * 40.0 + 20 + 10 * 25
        #expect(abs(hour.share - (total - 20) / total) < 1e-9)
    }

    @Test func theSlowBurnIsTheBookOfTheMostDays() throws {
        let wrapped = story(swYearData())
        let slow = try #require(wrapped.slowBurn)
        #expect(slow.bookID == "slow")
        #expect(slow.days == 47)
        #expect(wrapped.summary.longestStreak >= 10)
    }

    @Test func theMostQuotedBookShowsItsFavouriteQuote() throws {
        let quoted = try #require(story(swYearData()).quoted)
        #expect(quoted.bookID == "quick")
        #expect(quoted.quotes == 2)
        #expect(quoted.text == "The one I loved.")
        #expect(quoted.page == 30)
    }

    @Test func aQuietYearFillsInWithWhatItHasAndNeverPassesEight() {
        var data = LeafData()
        data.items = [swFinished(swBook("only", genres: ["mystery"]), started: nil, finished: swDate(2026, 5, 1), rating: 4)]
        let wrapped = story(data)
        #expect(wrapped.cards == [.books, .genre, .personality, .shelf])
        #expect(wrapped.tea == nil && wrapped.hour == nil && wrapped.quoted == nil && wrapped.slowBurn == nil)

        // Fillers only top up to six.
        let summary = story(swYearData()).summary
        let topped = WrappedStory.cards(summary: summary, tea: nil, hour: nil, slowBurn: nil, quoted: nil)
        #expect(topped.count == WrappedStory.fewestCards)
        #expect(topped.first == .books)
        #expect(Array(topped.suffix(2)) == [WrappedStory.Card.personality, .shelf])
        #expect(topped.contains(.genre))
    }

    @Test func aYearWithNothingInItIsEmpty() {
        let wrapped = story(swYearData(), year: 2019)
        #expect(wrapped.isEmpty)
        #expect(wrapped.cards.count <= WrappedStory.maximumCards)
        #expect(!WrappedOffer.hasStory(data: swYearData(), year: 2019, calendar: swCalendar))
        #expect(WrappedOffer.hasStory(data: swYearData(), year: 2026, calendar: swCalendar))
    }

    @Test func itIsOfferedInDecemberAndTheFirstWeekOfJanuary() {
        #expect(WrappedOffer.offeredYear(now: swDate(2026, 12, 1, 9), calendar: swCalendar) == 2026)
        #expect(WrappedOffer.offeredYear(now: swDate(2026, 12, 31, 23), calendar: swCalendar) == 2026)
        #expect(WrappedOffer.offeredYear(now: swDate(2027, 1, 3), calendar: swCalendar) == 2026)
        #expect(WrappedOffer.offeredYear(now: swDate(2027, 1, 8), calendar: swCalendar) == nil)
        #expect(WrappedOffer.offeredYear(now: swNow, calendar: swCalendar) == nil)
    }
}

// MARK: - Tilt for parallax

struct TiltFilterTests {
    /// A tiny, repeatable tremor, well inside the dead zone.
    private func tremor(_ index: Int) -> Double {
        Double(SeededGenerator.hash("tremor|\(index)") % 2_001) / 1_000_000 - 0.001
    }

    @Test func aPhoneHeldStillOrLyingFlatNeverJitters() {
        for pose in [RibbonVector(x: 0, y: 1), RibbonVector(x: 0.31, y: 0.9), RibbonVector(x: 0, y: 0)] {
            var filter = TiltFilter()
            var updates = 0
            for index in 0..<900 {
                let sample = RibbonVector(x: pose.x + tremor(index), y: pose.y + tremor(index + 7))
                if filter.feed(sample) != nil { updates += 1 }
            }
            #expect(updates == 0)
            #expect(filter.output == .zero)
        }
    }

    @Test func aTiltEasesInStaysWithinTheLimitAndSettlesBack() {
        var filter = TiltFilter()
        for _ in 0..<60 { _ = filter.feed(RibbonVector(x: 0, y: 1)) }
        var outputs: [Double] = []
        for index in 0..<300 {
            let sample = RibbonVector(x: 0.6 + tremor(index), y: 0.8)
            _ = filter.feed(sample)
            outputs.append(filter.output.x)
        }
        let first: Double = outputs[0]
        let peak: Double = outputs.max() ?? 0
        let last: Double = outputs[outputs.count - 1]
        // Eases in rather than jumping, reaches a clear tilt, never passes the limit.
        #expect(first < 0.1)
        #expect(peak > 0.2)
        #expect(peak <= filter.limit)
        // Held at the new angle for ten seconds, it settles back to no tilt.
        #expect(last == 0)
    }

    @Test func updatesAreRateLimitedToVisibleChanges() {
        var filter = TiltFilter()
        var updates = 0
        var previous = RibbonVector.zero
        for index in 0..<600 {
            let angle = Double(index) / 30 * 2
            let sample = RibbonVector(x: 0.25 * sin(angle), y: 1)
            if let next = filter.feed(sample) {
                updates += 1
                let change: Double = max(abs(next.x - previous.x), abs(next.y - previous.y))
                #expect(change >= filter.step || next == .zero)
                previous = next
            }
        }
        #expect(updates > 0)
        #expect(updates < 600)
    }

    @Test func nonsenseSamplesAreIgnored() {
        var filter = TiltFilter()
        #expect(filter.feed(RibbonVector(x: .nan, y: 1)) == nil)
        #expect(filter.feed(RibbonVector(x: 1, y: .infinity)) == nil)
        #expect(filter.output == .zero)
    }
}
