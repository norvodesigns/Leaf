import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct WatchSyncTests {
    @Test func anOlderSnapshotStillDecodes() throws {
        // What the first TestFlight build's phone sent: none of the watch-overhaul fields.
        let json = """
        {"generatedAt":700000000,"dailyMinutes":25,"minutesReadToday":12,"isReadingDay":true,"streak":3,"wpm":250,
        "today":[],"reading":[{"id":"b1","title":"Circe","author":"Madeline Miller","currentPage":10,"pages":400,"wordsPerPage":270,"paletteSeed":4}],
        "week":[],"hasOnboarded":true}
        """
        let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.greeting == nil && snapshot.tea == nil)
        #expect(snapshot.cupMinutes == 25)
        #expect(snapshot.queue.isEmpty && snapshot.forecasts.isEmpty)
        #expect(snapshot.liveActivities)
        #expect(snapshot.book("b1")?.title == "Circe")
    }

    @Test func theNewFieldsSurviveTheWire() throws {
        var snapshot = WatchSnapshot.empty
        snapshot.greeting = WatchGreeting(headline: "Still up?", subline: "One more page, then bed.")
        snapshot.tea = WatchTea(id: "earl-grey", name: "Earl Grey", steepSeconds: 240)
        snapshot.queue = [WatchBook(id: "q1", title: "Piranesi", author: "Susanna Clarke", currentPage: 0, pages: 272, wordsPerPage: 270, paletteSeed: 2, finish: nil)]
        snapshot.forecasts = [WatchForecast(bookID: "q1", sentence: "Probably done Sunday.", median: Date(timeIntervalSince1970: 1_000))]
        snapshot.yearGoal = WatchYearGoal(year: 2026, finished: 9, goal: 24, sentence: "On track for 24 books.")
        snapshot.minutesReadToday = 50
        snapshot.cupMinutes = 25

        let payload = SyncCodec.encode(snapshot, key: SyncCodec.snapshotKey)
        let decoded = SyncCodec.decode(WatchSnapshot.self, from: payload, key: SyncCodec.snapshotKey)
        #expect(decoded == snapshot)
        #expect(decoded?.cupsToday == 2)
        #expect(decoded?.book("q1")?.title == "Piranesi", "queued books are findable too")
    }

    @Test func newEventsRoundTrip() {
        let events: [SyncEvent] = [
            .journalAdded(bookID: "b1", kind: .quote, text: "All we have to decide is what to do with the time that is given us.", page: 51),
            .pageSet(bookID: "b1", page: 120),
            .shelfChanged(bookID: "b1", shelf: .paused, rating: nil),
            .shelfChanged(bookID: "b1", shelf: .finished, rating: 5),
            .addBook(query: "the left hand of darkness"),
            .sessionLogged(ReadingSession(bookID: "b1", startedAt: Date(timeIntervalSince1970: 5), seconds: 600, fromPage: 1, toPage: 9, kind: .manual, device: .watch), activeID: nil),
        ]
        for event in events {
            let payload = SyncCodec.encode(event, key: SyncCodec.eventKey)
            #expect(SyncCodec.decode(SyncEvent.self, from: payload, key: SyncCodec.eventKey) == event)
        }
    }
}

struct WatchSlotTests {
    @Test func todaysReadingTimesSurviveTheWire() {
        var snapshot = WatchSnapshot.empty
        snapshot.slots = [
            WatchSlot(id: UUID(), minuteOfDay: 8 * 60, label: "Morning tea", bookID: "b1", title: "Circe", minutes: 12, fromPage: 10, toPage: 20),
            WatchSlot(id: UUID(), minuteOfDay: 21 * 60 + 30, label: nil, bookID: "b2", title: "The Hobbit", minutes: 18, fromPage: 143, toPage: 160),
        ]
        let payload = SyncCodec.encode(snapshot, key: SyncCodec.snapshotKey)
        #expect(SyncCodec.decode(WatchSnapshot.self, from: payload, key: SyncCodec.snapshotKey)?.slots == snapshot.slots)
    }
}
