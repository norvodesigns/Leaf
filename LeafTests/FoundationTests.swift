import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

/// The data model that iCloud sync, the Paused shelf, the journal and the cozy features all build on.
struct FoundationTests {
    private let book = Book(id: "b1", title: "The Hobbit", author: "J.R.R. Tolkien", pages: 300, words: 81_000)

    @Test func olderSavedFilesStillLoad() throws {
        // A version-1 library as the first TestFlight build wrote it: none of the newer keys exist.
        let json = """
        {"version":1,"items":[{"book":{"id":"b1","title":"The Hobbit","author":"J.R.R. Tolkien","pages":300,"words":81000,"genres":[],"popularity":0},
        "shelf":"reading","currentPage":120,"order":1,"addedAt":700000000,"startedAt":700000100}],
        "sessions":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bookID":"b1","startedAt":700000200,"seconds":900,"fromPage":100,"toPage":120}],
        "speedTests":[],"preferences":{"wpm":250,"dailyMinutes":30}}
        """
        let data = try JSONDecoder().decode(LeafData.self, from: Data(json.utf8))
        let item = try #require(data.items.first)
        #expect(item.shelf == .reading)
        #expect(item.progressMode == .pages)
        #expect(item.positionConfirmed, "someone already reading has effectively said where they are")
        #expect(item.startPage == 0)
        #expect(item.updatedAt == item.startedAt)
        #expect(data.sessions.first?.kind == .timed)
        #expect(data.sessions.first?.teaID == nil)
        #expect(data.preferences.cupMinutes == 25)
        #expect(data.preferences.catchUp == .forgive)
        #expect(data.preferences.syncEnabled)
        #expect(!data.preferences.aiGreetings)
        #expect(data.journal.isEmpty && data.tombstones.isEmpty && data.challenges.isEmpty)
    }

    @Test func everythingNewSurvivesARoundTrip() throws {
        var data = LeafData()
        var item = LibraryItem(book: book, shelf: .paused, currentPage: 90, order: 2, addedAt: Date(timeIntervalSince1970: 1_000), progressMode: .percent, startPage: 30, positionConfirmed: true, pausedAt: Date(timeIntervalSince1970: 2_000), updatedAt: Date(timeIntervalSince1970: 3_000))
        item.rating = 4
        data.items = [item]
        data.sessions = [ReadingSession(bookID: "b1", startedAt: Date(timeIntervalSince1970: 1_500), seconds: 600, fromPage: 30, toPage: 90, kind: .manual, teaID: "earl-grey", ambienceID: "rain", device: .watch)]
        data.journal = [JournalEntry(bookID: "b1", bookTitle: "The Hobbit", bookAuthor: "Tolkien", kind: .quote, text: "Not all those who wander are lost.", page: 88, isFavorite: true, createdAt: Date(timeIntervalSince1970: 1_600))]
        data.tombstones = [Tombstone(kind: .item, key: "gone", deletedAt: Date(timeIntervalSince1970: 1_700))]
        data.challenges = [ChallengeEnrollment(id: "autumn-readathon", joinedAt: Date(timeIntervalSince1970: 1_800), year: 2026)]
        data.preferences.yearlyGoal = 24
        data.preferences.favoriteTeaID = "earl-grey"
        data.preferences.catchUp = .compress
        data.preferences.updatedAt = Date(timeIntervalSince1970: 3_500)

        let decoded = try JSONDecoder().decode(LeafData.self, from: try JSONEncoder().encode(data))
        #expect(decoded.items == data.items)
        #expect(decoded.sessions == data.sessions)
        #expect(decoded.journal == data.journal)
        #expect(decoded.tombstones == data.tombstones)
        #expect(decoded.challenges == data.challenges)
        #expect(decoded.preferences == data.preferences)
        #expect(decoded.version == 2)
    }

    @Test func pausedIsASeparateShelf() {
        #expect(Shelf.allCases.contains(.paused))
        #expect(!Shelf.main.contains(.paused))
        let data: LeafData = {
            var d = LeafData()
            d.items = [
                LibraryItem(book: book, shelf: .paused, currentPage: 10, order: 1),
                LibraryItem(book: Book(id: "b2", title: "B", author: "A", pages: 100), shelf: .reading, order: 1),
            ]
            return d
        }()
        #expect(data.items(on: .paused).map(\.id) == ["b1"])
        #expect(data.items(on: .reading).map(\.id) == ["b2"])
    }

    @Test func percentAndPageConvert() {
        #expect(LibraryItem.page(forPercent: 50, pages: 300) == 150)
        #expect(LibraryItem.page(forPercent: 0, pages: 300) == 0)
        #expect(LibraryItem.page(forPercent: 100, pages: 300) == 300)
        #expect(LibraryItem.page(forPercent: 140, pages: 300) == 300, "clamped to the last page")
        #expect(LibraryItem.page(forPercent: -5, pages: 300) == 0)
        let item = LibraryItem(book: book, shelf: .reading, currentPage: 75, order: 1)
        #expect(item.percent == 25)
    }

    @Test func newItemsStartUnconfirmedUntilTheyHaveAPosition() {
        #expect(!LibraryItem(book: book, shelf: .toRead, order: 1).positionConfirmed)
        #expect(!LibraryItem(book: book, shelf: .reading, order: 1).positionConfirmed)
        #expect(LibraryItem(book: book, shelf: .reading, currentPage: 40, order: 1).positionConfirmed)
        #expect(LibraryItem(book: book, shelf: .finished, order: 1).positionConfirmed)
    }

    @Test func activeSessionKnowsItsGoal() {
        let start = Date(timeIntervalSince1970: 10_000)
        var session = ActiveSession(bookID: "b1", startedAt: start, startPage: 0, origin: .phone, teaID: "sencha", goalSeconds: 25 * 60)
        #expect(session.remaining(at: start.addingTimeInterval(5 * 60)) == 1200.0)
        session.pause(at: start.addingTimeInterval(10 * 60))
        #expect(session.remaining(at: start.addingTimeInterval(60 * 60)) == 900.0, "paused time doesn't count")
        #expect(ActiveSession(bookID: "b1", startPage: 0, origin: .watch).remaining() == nil)
    }

    @Test func olderActiveSessionsFromTheWatchStillDecode() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bookID":"b1","startedAt":700000000,"pausedSeconds":0,"startPage":10,"origin":"watch","revision":2}"#
        let session = try JSONDecoder().decode(ActiveSession.self, from: Data(json.utf8))
        #expect(session.teaID == nil && session.goalSeconds == nil)
        #expect(session.revision == 2)
    }

    @Test func booksCanCarryLanguageAndAlternateEditions() throws {
        let b = Book(id: "x", title: "Don Quijote", author: "Cervantes", pages: 900, language: "es", pageCounts: [900, 1000])
        let decoded = try JSONDecoder().decode(Book.self, from: try JSONEncoder().encode(b))
        #expect(decoded.language == "es")
        #expect(decoded.pageCounts == [900, 1000])
        let legacy = try JSONDecoder().decode(Book.self, from: Data(#"{"id":"o","title":"T","author":"A","pages":10,"words":2700,"genres":[],"popularity":0}"#.utf8))
        #expect(legacy.language == nil && legacy.pageCounts == nil)
    }
}

struct MomentTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    private func date(_ month: Int, _ day: Int = 15, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }

    @Test func seasonsFollowMeteorologicalMonths() {
        #expect(Season.of(date(1), calendar: calendar) == .winter)
        #expect(Season.of(date(4), calendar: calendar) == .spring)
        #expect(Season.of(date(7), calendar: calendar) == .summer)
        #expect(Season.of(date(10), calendar: calendar) == .autumn)
        #expect(Season.of(date(12), calendar: calendar) == .winter)
        #expect(Season.of(date(10), calendar: calendar, southern: true) == .spring)
    }

    @Test func daypartsCoverTheWholeDay() {
        func part(_ hour: Int, _ minute: Int = 0) -> Daypart { Daypart.of(date(6, hour: hour, minute: minute), calendar: calendar) }
        #expect(part(3) == .smallHours)
        #expect(part(6) == .dawn)
        #expect(part(9) == .morning)
        #expect(part(12) == .lunch)
        #expect(part(15) == .afternoon)
        #expect(part(16, 30) == .teaTime)
        #expect(part(18) == .dusk)
        #expect(part(21) == .evening)
        #expect(part(23, 30) == .late)
        #expect(part(0, 30) == .late)
        #expect(part(1, 59) == .late)
        for hour in 0..<24 { _ = part(hour) }
    }
}

struct CupsTests {
    @Test func cupsAreSittings() {
        #expect(Cups.count(minutes: 50) == 2)
        #expect(Cups.wholeCups(minutes: 49) == 1)
        #expect(Cups.wholeCups(minutes: 60, cupMinutes: 30) == 2)
        #expect(Cups.count(minutes: -5) == 0)
        #expect(Cups.count(minutes: 25, cupMinutes: 0) == 25, "a zero-length cup can't divide by zero")
        #expect(Cups.pots(cups: 9) == 2)
    }

    @Test func phrasesReadNaturally() {
        #expect(Cups.phrase(minutes: 10) == "less than a cup")
        #expect(Cups.phrase(minutes: 25) == "a cup")
        #expect(Cups.phrase(minutes: 75) == "3 cups")
        #expect(Cups.phrase(minutes: 100) == "a pot")
        #expect(Cups.phrase(minutes: 200) == "2 pots")
        #expect(Cups.phrase(minutes: 125) == "5 cups")
    }
}
