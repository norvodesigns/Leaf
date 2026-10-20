import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Fixtures

private var rhCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}

private func rhDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 20) -> Date {
    rhCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private let rhNow = rhDate(2026, 10, 20, 12)

private func rhBook(_ id: String, pages: Int = 300, genres: [String] = ["fantasy"], author: String = "Author", year: Int? = 1990) -> Book {
    Book(id: id, title: "Book \(id)", author: author, year: year, pages: pages, words: pages * 270, genres: genres)
}

private func rhSession(_ book: String, _ date: Date, minutes: Double, from: Int, to: Int, tea: String? = nil, kind: SessionKind = .timed) -> ReadingSession {
    let hash = SeededGenerator.hash("\(book)|\(date.timeIntervalSince1970)|\(from)|\(to)")
    let tail = String(format: "%012llx", hash & 0xFFFF_FFFF_FFFF)
    return ReadingSession(id: UUID(uuidString: "00000000-0000-0000-0000-\(tail)")!, bookID: book, startedAt: date, seconds: minutes * 60, fromPage: from, toPage: to, kind: kind, teaID: tea)
}

private func rhFinished(_ book: Book, started: Date, finished: Date, rating: Int? = nil, reads: [ReadThrough] = []) -> LibraryItem {
    LibraryItem(book: book, shelf: .finished, currentPage: book.pages, order: 0, addedAt: started, startedAt: started, finishedAt: finished, rating: rating, updatedAt: finished, reads: reads)
}

// MARK: - Read-throughs

struct ReadThroughTests {
    @Test func theSameFinishGetsTheSameIDEverywhere() {
        let a = ReadThrough.stableID(bookID: "OL1", finishedAt: rhDate(2025, 3, 1))
        #expect(a == ReadThrough.stableID(bookID: "OL1", finishedAt: rhDate(2025, 3, 1).addingTimeInterval(0.2)))
        #expect(a != ReadThrough.stableID(bookID: "OL2", finishedAt: rhDate(2025, 3, 1)))
        #expect(a != ReadThrough.stableID(bookID: "OL1", finishedAt: rhDate(2025, 3, 2)))
    }

    @Test func aFinishedBookListsEveryReadThroughOldestFirst() {
        let book = rhBook("a")
        let first = ReadThrough(bookID: "a", startedAt: rhDate(2024, 1, 1), finishedAt: rhDate(2024, 2, 1), rating: 3)
        let item = rhFinished(book, started: rhDate(2026, 1, 1), finished: rhDate(2026, 2, 1), rating: 5, reads: [first])
        let reads = item.readThroughs
        #expect(reads.map(\.finishedAt) == [rhDate(2024, 2, 1), rhDate(2026, 2, 1)])
        #expect(reads.map(\.rating) == [3, 5])
        // Being read again: only the earlier one.
        var again = item
        again.shelf = .reading
        again.finishedAt = nil
        #expect(again.readThroughs.count == 1)
        // A stale copy still showing a finish already kept counts it once.
        var stale = rhFinished(book, started: rhDate(2024, 1, 1), finished: rhDate(2024, 2, 1), rating: 3, reads: [first])
        stale.shelf = .finished
        #expect(stale.readThroughs.count == 1)
    }

    @Test func leavingFinishedKeepsTheFinish() {
        let item = rhFinished(rhBook("a"), started: rhDate(2025, 5, 1), finished: rhDate(2025, 6, 1), rating: 4)
        let kept = item.keepingCurrentRead(now: rhNow)
        #expect(kept.reads.count == 1)
        #expect(kept.reads.first?.rating == 4)
        #expect(kept.reads.first?.startedAt == rhDate(2025, 5, 1))
        #expect(kept.reads.first?.updatedAt == rhNow)
        // Twice is still once.
        #expect(kept.keepingCurrentRead(now: rhNow).reads.count == 1)
        var reading = item
        reading.shelf = .reading
        #expect(reading.keepingCurrentRead(now: rhNow).reads.isEmpty)
    }

    @Test func asOfAReadThroughUsesItsDatesAndRating() {
        let read = ReadThrough(bookID: "a", startedAt: rhDate(2024, 1, 1), finishedAt: rhDate(2024, 1, 10), rating: 2)
        var item = LibraryItem(book: rhBook("a"), shelf: .reading, currentPage: 40, order: 0, startedAt: rhDate(2026, 1, 1), rating: 5, reads: [read])
        item.updatedAt = rhNow
        let then = item.asOf(read)
        #expect(then.shelf == .finished && then.finishedAt == rhDate(2024, 1, 10) && then.rating == 2 && then.currentPage == 300)
        #expect(read.days(calendar: rhCalendar) == 10)
    }

    @Test func earlierReadsAreRecoveredFromSessions() {
        // Read to the end in 2025, then started over in 2026 by a version that didn't keep the finish.
        let book = rhBook("a", pages: 100)
        let item = LibraryItem(book: book, shelf: .reading, currentPage: 20, order: 0, startedAt: rhDate(2026, 3, 1))
        let sessions = [
            rhSession("a", rhDate(2025, 1, 5), minutes: 30, from: 0, to: 50),
            rhSession("a", rhDate(2025, 1, 9), minutes: 30, from: 50, to: 100),
            rhSession("a", rhDate(2025, 6, 1), minutes: 10, from: 0, to: 12),
            rhSession("a", rhDate(2026, 3, 2), minutes: 10, from: 0, to: 20),
        ]
        let found = ReadsHistory.recovered(for: item, sessions: sessions)
        #expect(found.count == 1)
        #expect(found.first?.startedAt == rhDate(2025, 1, 5))
        #expect(found.first?.finishedAt == rhDate(2025, 1, 9).addingTimeInterval(30 * 60))
        var data = LeafData()
        data.items = [item]
        data.sessions = sessions
        let migrated = data.withRecoveredReads()
        #expect(migrated.items[0].reads == found)
        #expect(migrated.items[0].updatedAt == item.updatedAt)
        // Recovering again finds nothing new.
        #expect(migrated.withRecoveredReads().items[0].reads == found)
        #expect(ReadsHistory.ordinal(2) == "Second read" && ReadsHistory.ordinal(12) == "Read 12")
    }

    @Test func oldBooksAndReadsDecode() throws {
        let item = rhFinished(rhBook("a"), started: rhDate(2025, 1, 1), finished: rhDate(2025, 2, 1))
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        object.removeValue(forKey: "reads")
        let old = try JSONDecoder().decode(LibraryItem.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.reads.isEmpty)
        let sparse = try JSONDecoder().decode(ReadThrough.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","finishedAt":10,"rating":9}"#.utf8))
        #expect(sparse.rating == 5 && sparse.updatedAt == sparse.finishedAt && sparse.startedAt == nil)
    }
}

// MARK: - Merging read-throughs

struct ReadThroughMergeTests {
    @Test func aRereadOnOneDeviceAndARatingOnAnotherBothSurvive() {
        let book = rhBook("a")
        let original = rhFinished(book, started: rhDate(2025, 1, 1), finished: rhDate(2025, 2, 1), rating: 3)
        // Device A starts it again (keeping the finish), device B later rates the finished copy.
        var reread = original.keepingCurrentRead(now: rhDate(2026, 1, 1))
        reread.shelf = .reading
        reread.finishedAt = nil
        reread.startedAt = rhDate(2026, 1, 1)
        reread.updatedAt = rhDate(2026, 1, 1)
        var rated = original
        rated.rating = 5
        rated.updatedAt = rhDate(2026, 1, 2)
        var a = LeafData()
        a.items = [reread]
        var b = LeafData()
        b.items = [rated]
        for merged in [a.merged(with: b, now: rhNow), b.merged(with: a, now: rhNow)] {
            // The newer copy (B, finished and rated) wins as a whole, and A's kept finish is the same read-through,
            // so it is counted once.
            #expect(merged.items[0].rating == 5)
            #expect(merged.items[0].readThroughs.count == 1)
            #expect(merged.items[0].reads.count == 1)
        }
    }

    @Test func readThroughsMergeOneByOneAndTombstonesWinOnlyWhenLater() {
        let book = rhBook("a")
        let one = ReadThrough(bookID: "a", startedAt: nil, finishedAt: rhDate(2023, 1, 1), rating: 2, updatedAt: rhDate(2023, 1, 1))
        let two = ReadThrough(bookID: "a", startedAt: nil, finishedAt: rhDate(2024, 1, 1), rating: 4, updatedAt: rhDate(2024, 1, 1))
        var newerTwo = two
        newerTwo.rating = 5
        newerTwo.updatedAt = rhDate(2026, 5, 1)
        var a = LeafData()
        a.items = [LibraryItem(book: book, shelf: .reading, order: 0, startedAt: rhDate(2026, 1, 1), updatedAt: rhDate(2026, 6, 1), reads: [one, two])]
        var b = LeafData()
        b.items = [LibraryItem(book: book, shelf: .reading, order: 0, startedAt: rhDate(2026, 1, 1), updatedAt: rhDate(2026, 1, 1), reads: [newerTwo])]
        b.tombstones = [Tombstone(kind: .read, key: one.id.uuidString, deletedAt: rhDate(2026, 9, 1))]
        let ab = a.merged(with: b, now: rhNow)
        let ba = b.merged(with: a, now: rhNow)
        #expect(ab.items == ba.items)
        #expect(ab.items[0].reads.map(\.rating) == [5])
        // A tombstone older than the read-through it names leaves it alone.
        b.tombstones = [Tombstone(kind: .read, key: one.id.uuidString, deletedAt: rhDate(2022, 1, 1))]
        #expect(a.merged(with: b, now: rhDate(2022, 2, 1)).items[0].reads.count == 2)
    }
}

// MARK: - Statistics count every finish

struct ReReadStatsTests {
    private func data() -> LeafData {
        let book = rhBook("a", pages: 200)
        let earlier = ReadThrough(bookID: "a", startedAt: rhDate(2026, 1, 2), finishedAt: rhDate(2026, 1, 20), rating: 4)
        var data = LeafData()
        data.items = [rhFinished(book, started: rhDate(2026, 5, 1), finished: rhDate(2026, 5, 20), rating: 5, reads: [earlier])]
        return data
    }

    @Test func aBookReadTwiceThisYearCountsTwice() {
        let data = data()
        #expect(ReadingStats.booksFinished(in: 2026, items: data.items, calendar: rhCalendar) == 2)
        let engine = InsightsEngine(data: data, now: rhNow, calendar: rhCalendar)
        #expect(engine.finishedItems(year: 2026).count == 2)
        let year = engine.yearInBooks(year: 2026)
        #expect(year.booksFinished == 2)
        #expect(Set(year.finishedBooks.map(\.id)).count == 2)
        #expect(year.finishedBooks.map(\.rating) == [4, 5])
    }
}

// MARK: - Timeline

struct BookTimelineTests {
    @Test func chaptersGoNewestFirstWithBeadsInOrder() {
        let book = rhBook("a", pages: 100)
        let earlier = ReadThrough(bookID: "a", startedAt: rhDate(2025, 1, 1), finishedAt: rhDate(2025, 1, 10), rating: 4)
        let item = LibraryItem(book: book, shelf: .reading, currentPage: 30, order: 0, startedAt: rhDate(2026, 3, 1), reads: [earlier])
        var data = LeafData()
        data.items = [item]
        data.sessions = [
            rhSession("a", rhDate(2025, 1, 3), minutes: 40, from: 0, to: 60, tea: "sencha"),
            rhSession("a", rhDate(2025, 1, 9), minutes: 30, from: 60, to: 100),
            rhSession("a", rhDate(2026, 3, 2), minutes: 20, from: 0, to: 30, tea: "earl-grey"),
        ]
        data.journal = [
            JournalEntry(bookID: "a", bookTitle: book.title, bookAuthor: book.author, kind: .quote, text: "A line", page: 50, createdAt: rhDate(2025, 1, 4)),
            JournalEntry(bookID: "a", bookTitle: book.title, bookAuthor: book.author, kind: .thought, text: "Again", page: 10, createdAt: rhDate(2026, 3, 2, 21)),
        ]
        let timeline = BookTimeline.build(item: item, data: data, calendar: rhCalendar)
        #expect(timeline.chapters.map(\.title) == ["Reading again", "First read"])
        #expect(timeline.timesFinished == 1)
        let current = timeline.chapters[0]
        #expect(current.isCurrent && current.sittings == 1 && current.minutes == 20)
        #expect(current.beads.map(\.id).first == "start.1")
        let first = timeline.chapters[1]
        #expect(first.sittings == 2)
        let kinds = first.beads.map { bead -> String in
            switch bead.kind {
            case .started: return "start"
            case .sitting(_, _, _, let tea, _): return "sitting:\(tea ?? "-")"
            case .quote: return "quote"
            case .note: return "note"
            case .tasting: return "tasting"
            case .finished(let rating, let days): return "finish:\(rating ?? 0):\(days ?? 0)"
            case .setAside: return "aside"
            }
        }
        #expect(kinds == ["start", "sitting:Sencha", "quote", "sitting:-", "finish:4:10"])
    }
}

// MARK: - Reading log and export

struct ReadingLogTests {
    private func data() -> LeafData {
        var data = LeafData()
        let hobbit = Book(id: "h", title: "The Hobbit", author: "J. R. R. Tolkien", pages: 300, words: 81_000)
        let circe = Book(id: "c", title: "Circe", author: "Madeline Miller", pages: 400, words: 108_000)
        data.items = [
            rhFinished(hobbit, started: rhDate(2026, 9, 1), finished: rhDate(2026, 9, 20), rating: 5),
            LibraryItem(book: circe, shelf: .reading, currentPage: 40, order: 0, startedAt: rhDate(2026, 10, 1)),
        ]
        data.sessions = [
            rhSession("h", rhDate(2026, 9, 2), minutes: 30, from: 0, to: 40, tea: "earl-grey"),
            rhSession("c", rhDate(2026, 10, 2), minutes: 25.5, from: 0, to: 40),
            rhSession("c", rhDate(2025, 10, 2), minutes: 5, from: 0, to: 2, kind: .manual),
        ]
        return data
    }

    @Test func filtersSearchAndRanges() {
        let data = data()
        let all = ReadingLog.entries(data: data, calendar: rhCalendar)
        #expect(all.count == 4)
        #expect(all.first?.title == "Circe")
        #expect(ReadingLog.entries(data: data, filter: .init(show: .finishes), calendar: rhCalendar).map(\.title) == ["The Hobbit"])
        #expect(ReadingLog.entries(data: data, filter: .init(show: .sittings), calendar: rhCalendar).count == 3)
        #expect(ReadingLog.entries(data: data, filter: .init(query: "tolkien"), calendar: rhCalendar).count == 2)
        #expect(ReadingLog.entries(data: data, filter: .init(query: "CÍRCE"), calendar: rhCalendar).count == 2)
        let october = DateInterval(start: rhDate(2026, 10, 1, 0), end: rhDate(2026, 10, 2, 0))
        #expect(ReadingLog.entries(data: data, filter: .init(range: october), calendar: rhCalendar).count == 1)
        let totals = ReadingLog.totals(all)
        #expect(totals.sittings == 3 && totals.finishes == 1 && abs(totals.minutes - 60.5) < 1e-9)
    }

    @Test func csvEscapesAndDefusesFields() {
        #expect(ReadingLogExport.field("plain") == "plain")
        #expect(ReadingLogExport.field("Smith, Jane") == "\"Smith, Jane\"")
        #expect(ReadingLogExport.field("A \"quoted\" title") == "\"A \"\"quoted\"\" title\"")
        #expect(ReadingLogExport.field("=SUM(A1)") == "'=SUM(A1)")
        #expect(ReadingLogExport.field("-12") == "-12")
        let csv = ReadingLogExport.csv(ReadingLog.entries(data: data(), calendar: rhCalendar), calendar: rhCalendar)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 5)
        #expect(lines[0] == ReadingLogExport.csvHeader.joined(separator: ","))
        #expect(lines[1] == "Sitting,2026-10-02,20:00,Circe,Madeline Miller,25.5,0,40,40,,,")
        #expect(lines.contains("Finished,2026-09-20,20:00,The Hobbit,J. R. R. Tolkien,,,,,,5,1"))
        #expect(lines.contains { $0.hasPrefix("Sitting (typed in),2025-10-02") })
        #expect(lines.contains { $0.contains("Earl Grey") })
    }

    @Test func markdownGroupsByMonth() {
        let md = ReadingLogExport.markdown(ReadingLog.entries(data: data(), calendar: rhCalendar), title: "Reading log", calendar: rhCalendar)
        #expect(md.hasPrefix("# Reading log\n"))
        #expect(md.contains("## October 2026"))
        #expect(md.contains("## September 2026"))
        #expect(md.contains("- Fri 2 Oct · *Circe* by Madeline Miller · 26 min · pp. 1–40"))
        #expect(md.contains("Finished *The Hobbit* by J. R. R. Tolkien · in 20 days · rated 5 of 5"))
        #expect(ReadingLogExport.markdownEscape("*Bold* _x_ [y]") == "\\*Bold\\* \\_x\\_ \\[y\\]")
        #expect(ReadingLogExport.fileName(extension: "csv", now: rhNow, calendar: rhCalendar) == "Leaf reading log 2026-10-20.csv")
    }
}

// MARK: - Backup

struct LeafBackupTests {
    private func library() -> LeafData {
        var data = LeafData()
        data.items = [rhFinished(rhBook("a"), started: rhDate(2026, 1, 1), finished: rhDate(2026, 2, 1), rating: 4)]
        data.sessions = [rhSession("a", rhDate(2026, 1, 2), minutes: 20, from: 0, to: 30)]
        data.journal = [JournalEntry(bookID: "a", bookTitle: "Book a", bookAuthor: "Author", kind: .quote, text: "A line", createdAt: rhDate(2026, 1, 3))]
        data.cabinet = [CabinetTea(name: "Own", family: .green, steepSeconds: 120, addedAt: rhDate(2026, 1, 4))]
        data.preferences.wpm = 281
        data.preferences.updatedAt = rhDate(2026, 1, 5)
        data.activeSession = ActiveSession(bookID: "a", startedAt: rhNow, startPage: 0, origin: .phone)
        return data
    }

    @Test func aBackupRoundTripsExactlyWithoutTheLiveSession() throws {
        let original = library()
        let bytes = try LeafBackup.encode(original, exportedAt: rhNow)
        let back = try LeafBackup.decode(bytes)
        #expect(back.items == original.items)
        #expect(back.sessions == original.sessions)
        #expect(back.journal == original.journal)
        #expect(back.cabinet == original.cabinet)
        #expect(back.preferences.wpm == 281)
        #expect(back.activeSession == nil)
        #expect(LeafBackup.exportedAt(bytes) == rhNow)
        #expect(LeafBackup.fileName(now: rhNow, calendar: rhCalendar) == "Leaf backup 2026-10-20.json")
    }

    @Test func importingMergesAndNeverWipesNewerChanges() throws {
        let backup = library()
        var local = LeafData()
        var newer = rhFinished(rhBook("a"), started: rhDate(2026, 1, 1), finished: rhDate(2026, 2, 1), rating: 2)
        newer.updatedAt = rhDate(2026, 9, 1)
        local.items = [newer, LibraryItem(book: rhBook("b"), shelf: .toRead, order: 0, updatedAt: rhDate(2026, 9, 1))]
        local.activeSession = ActiveSession(bookID: "b", startedAt: rhNow, startPage: 0, origin: .phone)
        let preview = LeafBackup.preview(of: backup, against: local)
        #expect(preview.books == 0 && preview.sittings == 1 && preview.notes == 1 && preview.teas == 1)
        let merged = LeafBackup.merge(try LeafBackup.decode(LeafBackup.encode(backup, exportedAt: rhNow)), into: local, now: rhNow)
        #expect(merged.items.count == 2)
        #expect(merged.items.first { $0.id == "a" }?.rating == 2)
        #expect(merged.sessions.count == 1 && merged.journal.count == 1 && merged.cabinet.count == 1)
        #expect(merged.activeSession?.bookID == "b")
    }

    @Test func somethingElseIsNotABackup() throws {
        #expect(throws: LeafBackup.Failure.notABackup) { try LeafBackup.decode(Data("not json".utf8)) }
        #expect(throws: LeafBackup.Failure.notABackup) { try LeafBackup.decode(Data(#"{"hello":"world"}"#.utf8)) }
        #expect(throws: LeafBackup.Failure.notABackup) { try LeafBackup.decode(Data(#"{"format":"other","version":1,"exportedAt":0,"data":{}}"#.utf8)) }
        #expect(throws: LeafBackup.Failure.tooNew(version: 9)) { try LeafBackup.decode(Data(#"{"format":"leaf-backup","version":9,"exportedAt":0,"data":{}}"#.utf8)) }
        // A bare library file, with ISO dates, still imports.
        let bare = try LeafBackup.decode(Data(#"{"items":[],"sessions":[{"id":"00000000-0000-0000-0000-000000000009","bookID":"a","startedAt":"2026-01-02T20:00:00Z","seconds":600,"fromPage":0,"toPage":10}]}"#.utf8))
        #expect(bare.sessions.count == 1)
    }
}

// MARK: - The deeper numbers

struct InsightsDepthTests {
    private func data() -> LeafData {
        var data = LeafData()
        data.preferences.readingDays = Set(1...7)
        let fantasy = rhBook("f", pages: 300, genres: ["fantasy"], author: "Ursula K. Le Guin", year: 1968)
        let mystery = rhBook("m", pages: 200, genres: ["mystery"], author: "Agatha Christie", year: 1934)
        let aside = rhBook("s", pages: 500, genres: ["history"], author: "Someone", year: 2001)
        data.items = [
            rhFinished(fantasy, started: rhDate(2026, 9, 1), finished: rhDate(2026, 9, 10), rating: 5),
            rhFinished(mystery, started: rhDate(2025, 3, 1), finished: rhDate(2025, 3, 5), rating: 3),
            LibraryItem(book: aside, shelf: .paused, currentPage: 40, order: 0, startedAt: rhDate(2026, 9, 12), pausedAt: rhDate(2026, 9, 20)),
        ]
        // Fantasy: 60 pages an hour in the evening, five days running; mystery in 2025 in the mornings.
        for day in 1...5 {
            data.sessions.append(rhSession("f", rhDate(2026, 9, day, 21), minutes: 30, from: day * 30 - 30, to: day * 30))
        }
        data.sessions.append(rhSession("f", rhDate(2026, 9, 9, 21), minutes: 30, from: 150, to: 180))
        data.sessions.append(rhSession("m", rhDate(2025, 3, 2, 8), minutes: 60, from: 0, to: 100))
        data.sessions.append(rhSession("m", rhDate(2025, 3, 3, 8), minutes: 60, from: 100, to: 200))
        return data
    }

    @Test func paceStreaksWeeksAndYears() throws {
        let engine = InsightsEngine(data: data(), now: rhNow, calendar: rhCalendar)
        let all = engine.depth(in: InsightsRange.allTime.interval(data: data(), now: rhNow, calendar: rhCalendar))
        let fantasy = try #require(all.byGenre.first { $0.key == "fantasy" })
        #expect(abs(fantasy.pagesPerHour - 60) < 1e-9)
        let mystery = try #require(all.byGenre.first { $0.key == "mystery" })
        #expect(abs(mystery.pagesPerHour - 100) < 1e-9)
        #expect(all.byGenre.first?.key == "mystery")
        #expect(all.byTimeOfDay.map(\.key) == [Daypart.morning.rawValue, Daypart.evening.rawValue])
        #expect(all.streaks.first?.days == 5)
        #expect(all.streaks.first?.first == rhDate(2026, 9, 1, 0))
        // Monday 31 August to Sunday 6 September: five half hours.
        #expect(all.bestWeeks.first.map { $0.minutes } == 150)
        #expect(all.years.map(\.year) == [2026, 2025])
        #expect(all.years.first?.booksFinished == 1 && all.years.last?.averageRating == 3)
        #expect(all.authors.map(\.name).contains("Ursula K. Le Guin"))
        #expect(all.decades.map(\.name) == ["1930s", "1960s"])
        #expect(all.booksFinished == 2)
    }

    @Test func setAsideRateCountsBooksBegunInTheRange() {
        let data = data()
        let engine = InsightsEngine(data: data, now: rhNow, calendar: rhCalendar)
        let thisYear = engine.depth(in: InsightsRange.thisYear.interval(data: data, now: rhNow, calendar: rhCalendar))
        #expect(thisYear.setAside.started == 2)
        #expect(thisYear.setAside.finished == 1 && thisYear.setAside.setAside == 1)
        #expect(thisYear.setAside.rate == 0.5)
        #expect(thisYear.setAside.titles == ["Book s"])
        // Mystery belongs to last year.
        #expect(thisYear.byGenre.contains { $0.key == "mystery" } == false)
        let lastYear = engine.depth(in: InsightsRange.lastYear.interval(data: data, now: rhNow, calendar: rhCalendar))
        #expect(lastYear.booksFinished == 1 && lastYear.setAside.rate == 0)
    }

    @Test func tooLittleTimedReadingShowsNoPace() {
        var data = LeafData()
        data.items = [LibraryItem(book: rhBook("a"), shelf: .reading, order: 0, startedAt: rhDate(2026, 10, 1))]
        data.sessions = [rhSession("a", rhDate(2026, 10, 2), minutes: 20, from: 0, to: 20)]
        let engine = InsightsEngine(data: data, now: rhNow, calendar: rhCalendar)
        let depth = engine.depth(in: InsightsRange.thisYear.interval(data: data, now: rhNow, calendar: rhCalendar))
        #expect(depth.byGenre.isEmpty && depth.byTimeOfDay.isEmpty)
        #expect(depth.sittings == 1 && !depth.isEmpty)
    }

    @Test func rangesAreWholeDays() {
        let data = data()
        let year = InsightsRange.thisYear.interval(data: data, now: rhNow, calendar: rhCalendar)
        #expect(year.start == rhDate(2026, 1, 1, 0) && year.end == rhDate(2026, 10, 20, 0))
        let last = InsightsRange.lastYear.interval(data: data, now: rhNow, calendar: rhCalendar)
        #expect(last.start == rhDate(2025, 1, 1, 0) && last.end == rhDate(2025, 12, 31, 0))
        let twelve = InsightsRange.last12Months.interval(data: data, now: rhNow, calendar: rhCalendar)
        #expect(twelve.start == rhDate(2025, 10, 21, 0))
        #expect(InsightsRange.allTime.interval(data: data, now: rhNow, calendar: rhCalendar).start == rhDate(2025, 3, 2, 0))
    }
}
