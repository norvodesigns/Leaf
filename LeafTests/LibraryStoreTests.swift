#if !canImport(LeafCore)
import Foundation
import Testing
@testable import Leaf

@MainActor
struct LibraryStoreTests {
    func makeStore() -> LibraryStore {
        let store = LibraryStore(persistence: .ephemeral())
        store.updatePreferences { $0.wpm = 270; $0.dailyMinutes = 30 }
        return store
    }

    func book(_ id: String, pages: Int = 300) -> Book {
        Book(id: id, title: id.uppercased(), author: "Author", pages: pages, words: pages * 270)
    }

    @Test func addingAndMovingBooks() {
        let store = makeStore()
        store.add(book("a"), to: .toRead)
        store.add(book("b"), to: .toRead)
        #expect(store.toRead.map(\.id) == ["a", "b"])
        store.startReading("b")
        #expect(store.reading.map(\.id) == ["b"])
        #expect(store.item("b")?.startedAt != nil)
        store.markFinished("b", rating: 5)
        #expect(store.finished.first?.id == "b")
        #expect(store.item("b")?.currentPage == 300)
        #expect(store.item("b")?.rating == 5)
    }

    @Test func reorderingTheQueueReflowsThePlan() {
        let store = makeStore()
        ["a", "b", "c"].forEach { store.add(book($0), to: .toRead) }
        store.reorder(.toRead, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.toRead.map(\.id) == ["c", "a", "b"])
        #expect(store.plan.books.first?.id == "c")
        store.moveToFront("b")
        #expect(store.toRead.map(\.id) == ["b", "c", "a"])
    }

    @Test func sessionLogsProgressAndCalibrates() {
        let store = makeStore()
        store.add(book("a"), to: .reading)
        let start = Date().addingTimeInterval(-600)
        store.startSession(bookID: "a", startedAt: start)
        #expect(store.activeSession != nil)
        // 10 minutes, 13 pages at 270 words a page = 351 wpm observed, nudging 270 upward.
        let outcome = store.finishSession(toPage: 13)
        #expect(store.activeSession == nil)
        #expect(store.item("a")?.currentPage == 13)
        #expect(outcome?.finishedBook == false)
        #expect((outcome?.newWPM ?? 0) > 270)
        #expect(store.minutesReadToday > 9.9)
    }

    @Test func reachingTheLastPageFinishesTheBook() {
        let store = makeStore()
        store.add(book("a", pages: 20), to: .reading)
        store.startSession(bookID: "a", startedAt: Date().addingTimeInterval(-1200))
        let outcome = store.finishSession(toPage: 20)
        #expect(outcome?.finishedBook == true)
        #expect(store.item("a")?.shelf == .finished)
    }

    @Test func watchEventsMergeByRevision() {
        let store = makeStore()
        store.add(book("a"), to: .reading)
        var remote = ActiveSession(bookID: "a", startedAt: Date().addingTimeInterval(-300), startPage: 0, origin: .watch)
        store.apply(.sessionChanged(remote))
        #expect(store.activeSession?.id == remote.id)
        remote.pause()
        store.apply(.sessionChanged(remote))
        #expect(store.activeSession?.isPaused == true)
        // An older revision doesn't win.
        var stale = remote
        stale.revision = 0
        stale.pausedAt = nil
        store.apply(.sessionChanged(stale))
        #expect(store.activeSession?.isPaused == true)
        let logged = ReadingSession(id: remote.id, bookID: "a", startedAt: remote.startedAt, seconds: 300, fromPage: 0, toPage: 6)
        store.apply(.sessionLogged(logged, activeID: remote.id))
        #expect(store.activeSession == nil)
        #expect(store.item("a")?.currentPage == 6)
        // Logging the same session twice is ignored.
        store.apply(.sessionLogged(logged, activeID: remote.id))
        #expect(store.data.sessions.count == 1)
    }

    @Test func persistsAcrossLaunches() async throws {
        let persistence = Persistence.ephemeral()
        let store = LibraryStore(persistence: persistence)
        store.add(book("a"), to: .toRead)
        store.flush()
        let reopened = LibraryStore(persistence: persistence)
        #expect(reopened.toRead.map(\.id) == ["a"])
        persistence.delete()
    }

    @Test func demoDataProducesAPlan() {
        let store = makeStore()
        store.replaceAll(with: DemoData.make())
        #expect(store.reading.count == 2)
        #expect(!store.todayAssignments.isEmpty)
        #expect(store.streak >= 1)
        #expect(store.plan.books.allSatisfy { $0.finish != nil })
    }

    @Test func watchSnapshotCarriesToday() {
        let store = makeStore()
        store.replaceAll(with: DemoData.make())
        let snapshot = store.watchSnapshot()
        #expect(snapshot.reading.first?.id == DemoData.hobbit.id)
        #expect(snapshot.week.count == 7)
        #expect(snapshot.dailyMinutes == 25)
    }

    // MARK: Foundation (paused shelf, position, tombstones, journal)

    @Test func settingABookAsideKeepsItsPageAndLeavesThePlan() {
        let store = makeStore()
        store.add(book("a"), to: .reading)
        store.setPage("a", page: 120)
        store.add(book("b"), to: .toRead)
        store.pause("a")
        #expect(store.item("a")?.shelf == .paused)
        #expect(store.item("a")?.currentPage == 120)
        #expect(store.item("a")?.pausedAt != nil)
        #expect(!store.plan.books.contains { $0.id == "a" })
        store.startReading("a")
        #expect(store.item("a")?.shelf == .reading)
        #expect(store.item("a")?.pausedAt == nil)
    }

    @Test func whereAreYouRecordsTheStartingPage() {
        let store = makeStore()
        store.add(book("a"), to: .toRead)
        #expect(store.item("a")?.positionConfirmed == false)
        store.confirmPosition("a", page: 80, mode: .percent)
        #expect(store.item("a")?.currentPage == 80)
        #expect(store.item("a")?.startPage == 80)
        #expect(store.item("a")?.positionConfirmed == true)
        #expect(store.item("a")?.progressMode == .percent)
    }

    @Test func firstSessionIsMeasuredFromWhereTheReaderBegan() {
        let store = makeStore()
        store.add(book("a"), to: .reading)
        store.confirmPosition("a", page: 100)
        store.startSession(bookID: "a", startedAt: Date().addingTimeInterval(-1200))
        let outcome = store.finishSession(toPage: 140)
        #expect(outcome?.session.fromPage == 100)
        #expect(outcome?.session.pagesRead == 40)
        #expect(store.item("a")?.startPage == 100)
    }

    @Test func deletingLeavesATombstoneAndReAddingClearsIt() {
        let store = makeStore()
        store.add(book("a"), to: .toRead)
        store.remove("a")
        #expect(store.data.tombstones.contains { $0.kind == .item && $0.key == "a" })
        store.add(book("a"), to: .toRead)
        #expect(!store.data.tombstones.contains { $0.kind == .item && $0.key == "a" })
    }

    @Test func changesAreStampedForMerging() {
        let store = makeStore()
        var time = Date(timeIntervalSince1970: 1_000_000)
        store.clock = { time }
        store.add(book("a"), to: .toRead)
        #expect(store.item("a")?.updatedAt == time)
        time = time.addingTimeInterval(60)
        store.setRating("a", rating: 4)
        #expect(store.item("a")?.updatedAt == time)
        time = time.addingTimeInterval(60)
        store.updatePreferences { $0.dailyMinutes = 45 }
        #expect(store.preferences.updatedAt == time)
    }

    @Test func manualLogsCountAsReading() {
        let store = makeStore()
        store.add(book("a"), to: .reading)
        let outcome = store.logManual(bookID: "a", minutes: 20, toPage: 30)
        #expect(outcome?.session.kind == .manual)
        #expect(store.item("a")?.currentPage == 30)
        #expect(store.minutesReadToday >= 20 || store.sessions(for: "a").count == 1)
    }

    @Test func journalEntriesKeepTheirBookAfterItLeaves() {
        let store = makeStore()
        store.add(book("a"), to: .reading)
        let entry = store.addJournalEntry(bookID: "a", kind: .quote, text: "  A line worth keeping.  ")
        #expect(entry?.text == "A line worth keeping.")
        #expect(entry?.bookTitle == "A")
        #expect(store.addJournalEntry(bookID: "a", text: "   ") == nil)
        store.remove("a")
        #expect(store.journal(for: "a").count == 1)
        if let id = entry?.id {
            store.deleteJournalEntry(id)
            #expect(store.journal(for: "a").isEmpty)
            #expect(store.data.tombstones.contains { $0.kind == .journal && $0.key == id.uuidString })
        }
    }

    @Test func teaAndGoalTravelWithTheSession() {
        let store = makeStore()
        store.add(book("a"), to: .reading)
        let active = store.startSession(bookID: "a", startedAt: Date().addingTimeInterval(-600), teaID: "earl-grey", goalSeconds: 1500, ambienceID: "rain")
        #expect(active?.teaID == "earl-grey")
        let outcome = store.finishSession(toPage: 20)
        #expect(outcome?.session.teaID == "earl-grey")
        #expect(outcome?.session.ambienceID == "rain")
    }

    @Test func challengesCanBeJoinedAndLeft() {
        let store = makeStore()
        store.joinChallenge("autumn-readathon", year: 2026)
        store.joinChallenge("autumn-readathon", year: 2026)
        #expect(store.data.challenges.count == 1)
        store.leaveChallenge("autumn-readathon", year: 2026)
        #expect(store.data.challenges.isEmpty)
    }
}
#endif
