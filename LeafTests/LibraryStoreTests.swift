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

    @Test func switchingEditionKeepsWordsAndTheOldCount() {
        let store = makeStore()
        var printed = book("a", pages: 300)
        printed.pageCounts = [280]
        store.add(printed, to: .reading)
        store.confirmPosition("a", page: 150, mode: .percent)
        store.switchEdition("a", pages: 400)
        let item = store.item("a")
        #expect(item?.book.pages == 400)
        #expect(item?.book.words == 300 * 270)
        #expect(item?.book.pageCounts?.sorted() == [280, 300])
        #expect(item?.currentPage == 200)
        store.setProgressMode("a", .pages)
        store.switchEdition("a", pages: 280)
        #expect(store.item("a")?.currentPage == 200)
        #expect(store.item("a")?.book.pageCounts?.sorted() == [280, 300, 400])
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

    @Test func applyingASuggestedQueueOrderKeepsEveryBook() {
        let store = makeStore()
        store.replaceAll(with: DemoData.make())
        let queue = store.toRead.map(\.id)
        let suggested = Array(queue.reversed().prefix(2))
        store.applyQueueOrder(suggested + ["not-on-the-shelf"])
        #expect(Array(store.toRead.map(\.id).prefix(2)) == suggested)
        #expect(store.toRead.count == queue.count)
        #expect(Set(store.toRead.map(\.id)) == Set(queue))
    }

    @Test func yearScenarioFillsTheYearSensibly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 20)) ?? Date()
        let data = DemoData.make(now: now, calendar: calendar, scenario: .year)
        let finished = data.items.filter { $0.shelf == .finished }
        #expect(finished.count >= 10)
        #expect(data.sessions.count > 100)
        #expect(data.sessions.allSatisfy { $0.toPage > $0.fromPage && $0.seconds > 0 && $0.startedAt <= now })
        #expect(finished.allSatisfy { ($0.finishedAt ?? .distantFuture) <= now && ($0.startedAt ?? now) <= ($0.finishedAt ?? now) })
        let byBook = Dictionary(grouping: data.sessions, by: \.bookID)
        for item in finished where byBook[item.id] != nil {
            #expect((byBook[item.id]?.map(\.toPage).max() ?? 0) <= item.book.pages)
        }
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

    @Test func whereAreYouAnswersApplyToTheBook() {
        let store = makeStore()
        store.add(book("a"), to: .toRead)
        store.apply(.percent(50), to: "a")
        #expect(store.item("a")?.currentPage == 150)
        #expect(store.item("a")?.progressMode == .percent)
        store.apply(.page(40), to: "a")
        #expect(store.item("a")?.currentPage == 40)
        let long = Date(timeIntervalSince1970: 1_700_000_000)
        store.apply(.alreadyRead(on: long), to: "a")
        #expect(store.item("a")?.shelf == .finished)
        #expect(store.item("a")?.finishedAt == long)
    }

    @Test func aDamagedFileFallsBackToTheBackupAndIsKept() throws {
        let persistence = Persistence.ephemeral()
        var good = LeafData()
        good.items = [LibraryItem(book: book("keep"), shelf: .toRead, order: 1)]
        try persistence.save(good)
        try persistence.save(good) // the second save refreshes the backup from the first
        #expect(FileManager.default.fileExists(atPath: persistence.backupURL.path))

        try Data("{ not json".utf8).write(to: persistence.url)
        let loaded = persistence.load()
        #expect(loaded?.items.map(\.id) == ["keep"], "the backup should have been used")
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: persistence.url.deletingLastPathComponent().path)) ?? []
        #expect(siblings.contains { $0.contains("damaged") && $0.contains(persistence.url.deletingPathExtension().lastPathComponent) }, "the damaged file is kept for recovery")
        persistence.delete()
    }

    @Test func aFirstLaunchHasNothingToLoad() {
        #expect(Persistence.ephemeral().load() == nil)
    }

    @Test func severalReadingTimesSplitTheDay() {
        let store = makeStore()
        store.updatePreferences { $0.planMode = .sideBySide; $0.dailyMinutes = 40 }
        store.add(book("a"), to: .reading)
        store.add(book("b"), to: .reading)
        store.addReadingSlot(hour: 8, bookID: "a", label: "Morning tea")
        store.addReadingSlot(hour: 21, minute: 30, bookID: "b")
        #expect(store.preferences.readingSlots.count == 2)
        #expect(store.preferences.reminderEnabled)
        let plans = store.slotPlans()
        #expect(plans.map { $0.parts.first?.bookID } == ["a", "b"])
        #expect(store.watchSnapshot().slots.count == 2)
    }

    @Test func theFirstReadingTimeKeepsTheOldReminder() {
        let store = makeStore()
        store.updatePreferences { $0.reminderEnabled = true; $0.reminderHour = 20; $0.reminderMinute = 15 }
        store.addReadingSlot(hour: 7)
        #expect(store.preferences.readingSlots.map(\.minuteOfDay) == [20 * 60 + 15, 7 * 60])
        for slot in store.preferences.readingSlots { store.removeReadingSlot(slot.id) }
        #expect(store.preferences.readingSlots.isEmpty)
        #expect(!store.preferences.reminderEnabled)
    }

    // MARK: Tea

    @Test func aCatalogTeaIsKeptOnceAndComesBackInStock() {
        let store = makeStore()
        let earl = TeaCatalog.earlGrey
        let first = store.addCabinetTea(CabinetTea(tin: earl, now: store.now))
        store.setOutOf(first.id, true)
        #expect(store.teaChoices().fromCabinet == false)
        let again = store.addCabinetTea(CabinetTea(tin: earl, now: store.now))
        #expect(again.id == first.id)
        #expect(store.data.cabinet.count == 1)
        #expect(store.data.cabinet.first?.isOutOf == false)
        #expect(store.hasInStock(earl.id))
    }

    @Test func editingAndRemovingATeaStampsAndLeavesATombstone() {
        let store = makeStore()
        let own = store.addCabinetTea(CabinetTea(name: "  Mountain mist ", family: .black, steepSeconds: 200))
        #expect(store.data.cabinet.first?.name == "Mountain mist")
        var edited = own
        edited.name = "Mountain mist"
        store.updateCabinetTea(edited)
        #expect(store.data.cabinet.first?.updatedAt == own.updatedAt)
        edited.rating = 4
        store.updateCabinetTea(edited)
        #expect(store.data.cabinet.first?.rating == 4)
        #expect(store.tea(id: own.teaID)?.name == "Mountain mist")
        store.removeCabinetTea(own.id)
        #expect(store.data.cabinet.isEmpty)
        #expect(store.data.tombstones.contains { $0.kind == .cabinetTea && $0.key == own.id.uuidString })
    }

    @Test func aTastingNoteIsOnePerCupAndKeepsTheTeasName() {
        let store = makeStore()
        let own = store.addCabinetTea(CabinetTea(name: "Autumn spice", family: .chai, steepSeconds: 300))
        let session = UUID()
        let note = store.saveTasting(sessionID: session, teaID: own.teaID, bookID: nil, strength: .light, aromas: [], rating: nil)
        #expect(note.teaName == "Autumn spice")
        #expect(note.family == .chai)
        store.saveTasting(sessionID: session, teaID: own.teaID, bookID: nil, strength: .strong, aromas: ["spicy"], rating: 9)
        #expect(store.data.tastings.count == 1)
        #expect(store.tasting(forSession: session)?.strength == .strong)
        #expect(store.tasting(forSession: session)?.rating == 5)
        store.removeCabinetTea(own.id)
        #expect(TeaHistory.build(data: store.data).teas.first?.name == "Autumn spice")
        store.deleteTasting(note.id)
        #expect(store.data.tastings.isEmpty)
        #expect(store.data.tombstones.contains { $0.kind == .tasting && $0.key == note.id.uuidString })
    }

    @Test func pinningAPairingStampsTheBook() {
        let store = makeStore()
        store.add(book("a"), to: .toRead)
        let before = store.item("a")?.updatedAt
        store.setPairedTea("a", teaID: "sencha")
        #expect(store.item("a")?.pairedTeaID == "sencha")
        #expect(store.item("a")?.updatedAt != before)
        store.setPairedTea("a", teaID: nil)
        #expect(store.item("a")?.pairedTeaID == nil)
    }

    @Test func demoDataHasACabinetAndNotes() {
        let store = makeStore()
        store.replaceAll(with: DemoData.make())
        #expect(store.data.cabinet.count >= 4)
        #expect(store.data.cabinet.contains(where: \.isOutOf))
        #expect(!store.data.tastings.isEmpty)
        #expect(store.item(DemoData.hobbit.id)?.pairedTeaID == "earl-grey")
        #expect(TeaOfTheWeek.pick(data: store.data, forecast: nil, now: store.now, calendar: store.calendar) != nil)
    }
}
#endif
