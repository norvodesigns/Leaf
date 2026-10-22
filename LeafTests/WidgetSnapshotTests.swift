#if !canImport(LeafCore)
import Foundation
import Testing
@testable import Leaf

/// The widgets' snapshot: what it shows when, the moments its timeline changes, and how the app builds it.
@MainActor
struct WidgetSnapshotTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        return calendar
    }()

    /// 20:30 on a Wednesday.
    var evening: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 20, minute: 30)) ?? Date()
    }

    func sample() -> LeafWidgetSnapshot {
        LeafWidgetSnapshot.sample(now: evening, calendar: calendar)
    }

    @Test func todayShowsMinutesLeftAndThePage() {
        var snapshot = sample()
        snapshot.minutesReadToday = 12
        let phase = snapshot.phase(at: evening)
        let line = snapshot.line
        #expect(phase == .today)
        #expect(line == "13 min · p. 143")
    }

    @Test func goalMetAndRestDay() {
        var met = sample()
        met.minutesReadToday = 30
        let metPhase = met.phase(at: evening)
        #expect(metPhase == .goalMet)
        var rest = sample()
        rest.isReadingDay = false
        rest.minutesReadToday = 0
        let restPhase = rest.phase(at: evening)
        #expect(restPhase == .rest)
    }

    @Test func nothingToReadIsEmpty() {
        var snapshot = sample()
        snapshot.current = nil
        let phase = snapshot.phase(at: evening)
        #expect(phase == .empty)
        let neverSetUp = LeafWidgetSnapshot.empty.phase(at: evening)
        #expect(neverSetUp == .empty)
    }

    @Test func sessionCountsDownThenPastTheGoal() {
        var snapshot = sample()
        snapshot.session = LeafWidgetSnapshot.Session(bookID: "OL27482W", timerStart: evening, isPaused: false, pausedElapsed: 0, goalSeconds: 600, teaName: nil)
        let during = snapshot.phase(at: evening.addingTimeInterval(300))
        let after = snapshot.phase(at: evening.addingTimeInterval(601))
        #expect(during == .reading)
        #expect(after == .goalReached)
        let changes = snapshot.changes(after: evening, calendar: calendar)
        #expect(changes.first == evening.addingTimeInterval(600))
    }

    @Test func pausedSessionStaysPausedAndHasNoGoalChange() {
        var snapshot = sample()
        snapshot.session = LeafWidgetSnapshot.Session(bookID: "OL27482W", timerStart: evening, isPaused: true, pausedElapsed: 120, goalSeconds: 600, teaName: nil)
        let phase = snapshot.phase(at: evening.addingTimeInterval(3600))
        #expect(phase == .paused)
        let changes = snapshot.changes(after: evening, calendar: calendar)
        #expect(!changes.contains(evening.addingTimeInterval(600)))
    }

    @Test func steepGoesReadyThenCold() {
        var snapshot = sample()
        snapshot.steep = LeafWidgetSnapshot.Steep(teaName: "Earl Grey", startedAt: evening, steepSeconds: 240)
        let steeping = snapshot.phase(at: evening.addingTimeInterval(60))
        let ready = snapshot.phase(at: evening.addingTimeInterval(300))
        let later = snapshot.at(evening.addingTimeInterval(240 + 31 * 60), calendar: calendar)
        let cold = later.phase(at: evening.addingTimeInterval(240 + 31 * 60))
        #expect(steeping == .steeping)
        #expect(ready == .teaReady)
        #expect(later.steep == nil)
        #expect(cold == .today)
        let changes = snapshot.changes(after: evening, calendar: calendar)
        #expect(changes.contains(evening.addingTimeInterval(240)))
        #expect(changes.contains(evening.addingTimeInterval(240 + 30 * 60)))
    }

    @Test func midnightStartsTheDayFromNothing() throws {
        let snapshot = sample()
        let midnight = try #require(snapshot.changes(after: evening, calendar: calendar).last)
        let tomorrow = snapshot.at(midnight, calendar: calendar)
        let sameDay = calendar.isDate(tomorrow.day, inSameDayAs: midnight)
        #expect(sameDay)
        #expect(tomorrow.minutesReadToday == 0)
        #expect(tomorrow.fromPage == nil)
    }

    @Test func nextReadingTimeMovesOnAQuarterHourAfterItStarts() {
        let snapshot = sample()
        let atSeven = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: evening) ?? evening
        let morning = snapshot.nextSlot(at: atSeven, calendar: calendar)?.id
        let tonight = snapshot.nextSlot(at: evening, calendar: calendar)?.id
        let late = calendar.date(bySettingHour: 21, minute: 46, second: 0, of: evening) ?? evening
        let none = snapshot.nextSlot(at: late, calendar: calendar)
        #expect(morning == "morning")
        #expect(tonight == "evening")
        #expect(none == nil)
        let changes = snapshot.changes(after: evening, calendar: calendar)
        let quarterPast = calendar.date(bySettingHour: 21, minute: 45, second: 0, of: evening) ?? evening
        #expect(changes.contains(quarterPast))
    }

    @Test func aSnapshotWithoutReadingTimesStillDecodes() throws {
        var snapshot = sample()
        snapshot.slots = nil
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(LeafWidgetSnapshot.self, from: data)
        #expect(decoded.slots == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        var snapshot = sample()
        snapshot.steep = LeafWidgetSnapshot.Steep(teaName: "Sencha", startedAt: evening, steepSeconds: 90)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(LeafWidgetSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test func timerArgumentsAreAlwaysValidRanges() {
        var snapshot = sample()
        snapshot.session = LeafWidgetSnapshot.Session(bookID: "OL27482W", timerStart: evening, isPaused: true, pausedElapsed: 9_999, goalSeconds: 600, teaName: "Earl Grey")
        let timer = LeafWidgetTimer(snapshot: snapshot, phase: .paused)
        let range = timer?.range
        let pause = timer?.pauseDate
        #expect(range?.upperBound == evening.addingTimeInterval(600))
        #expect(pause == range?.upperBound)
        let eyebrow = timer?.eyebrow
        #expect(eyebrow == "Paused")
        let none = LeafWidgetTimer(snapshot: sample(), phase: .today)
        #expect(none == nil)
    }

    @Test func storeBuildsTheSnapshotFromTheLibrary() {
        let store = LibraryStore(persistence: .ephemeral())
        store.replaceAll(with: DemoData.make())
        let snapshot = store.widgetSnapshot(coverName: { _ in nil })
        let currentID = snapshot.current?.id
        let upNextIDs = snapshot.upNext.map(\.id)
        #expect(currentID == store.nextBook?.id)
        #expect(!upNextIDs.contains(currentID ?? ""))
        #expect(upNextIDs.count <= 3)
        #expect(snapshot.week.count == 7)
        #expect(snapshot.dailyMinutes == store.preferences.dailyMinutes)
        // Built twice with nothing changed, it's the same, so the widgets aren't reloaded for nothing.
        let again = store.widgetSnapshot(coverName: { _ in nil })
        #expect(again == snapshot)
    }
}
#endif
