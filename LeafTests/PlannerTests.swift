import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct PlannerTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// Wednesday, Oct 14 2026, 9:00 local.
    var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9))! }

    func item(_ id: String, pages: Int = 300, words: Int = 81_000, page: Int = 0, shelf: Shelf = .reading, order: Double = 0) -> LibraryItem {
        LibraryItem(book: Book(id: id, title: id, author: "A", pages: pages, words: words), shelf: shelf, currentPage: page, order: order)
    }

    func input(reading: [LibraryItem], queue: [LibraryItem] = [], minutes: Int = 30, days: Set<Int> = Set(1...7), mode: PlanMode = .focus, readToday: Double = 0) -> PlanInput {
        PlanInput(reading: reading, queue: queue, wpm: 270, dailyMinutes: minutes, readingDays: days, mode: mode, today: today, minutesReadToday: readToday, calendar: calendar)
    }

    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))! }

    @Test func singleBookFinishesOnSchedule() {
        // 81,000 words at 270 wpm = 300 minutes = 10 days of 30 minutes.
        let plan = Planner.makePlan(input(reading: [item("a")]))
        #expect(plan.books.count == 1)
        #expect(plan.books[0].finish == day(9))
        #expect(plan.books[0].readingDays == 10)
        #expect(abs(plan.books[0].minutesLeft - 300) < 0.01)
    }

    @Test func todaysAssignmentCoversPages() {
        let plan = Planner.makePlan(input(reading: [item("a")]))
        let today = plan.today!
        #expect(today.assignments.count == 1)
        #expect(today.assignments[0].fromPage == 1)
        #expect(today.assignments[0].toPage == 30)
        #expect(abs(today.minutes - 30) < 0.01)
    }

    @Test func assignmentStartsAfterCurrentPage() {
        let plan = Planner.makePlan(input(reading: [item("a", page: 100)]))
        #expect(plan.today!.assignments[0].fromPage == 101)
        #expect(plan.today!.assignments[0].toPage == 130)
    }

    @Test func minutesAlreadyReadShrinkToday() {
        let plan = Planner.makePlan(input(reading: [item("a")], readToday: 20))
        #expect(abs(plan.today!.minutes - 10) < 0.01)
        let done = Planner.makePlan(input(reading: [item("a")], readToday: 45))
        #expect(done.today!.assignments.isEmpty)
    }

    @Test func queueFollowsAndRollsOverSameDay() {
        // Book a needs 45 minutes: day 0 = 30, day 1 = 15, then b starts with the remaining 15.
        let a = item("a", pages: 45, words: 12_150)
        let b = item("b", shelf: .toRead, order: 1)
        let plan = Planner.makePlan(input(reading: [a], queue: [b]))
        #expect(plan.book("a")?.finish == day(1))
        #expect(plan.book("b")?.start == day(1))
        #expect(plan.days[1].assignments.map(\.bookID) == ["a", "b"])
        #expect(abs(plan.days[1].assignments[1].minutes - 15) < 0.01)
    }

    @Test func doesNotStartNewBookWithCrumbs() {
        // Book a needs 28 minutes, leaving 2 minutes: not enough to start b today.
        let a = item("a", pages: 28, words: 7_560)
        let b = item("b", shelf: .toRead, order: 1)
        let plan = Planner.makePlan(input(reading: [a], queue: [b]))
        #expect(plan.days[0].assignments.map(\.bookID) == ["a"])
        #expect(plan.book("b")?.start == day(1))
    }

    @Test func sideBySideSplitsTime() {
        let plan = Planner.makePlan(input(reading: [item("a"), item("b", order: 1)], mode: .sideBySide))
        let parts = plan.today!.assignments
        #expect(parts.count == 2)
        #expect(abs(parts[0].minutes - 15) < 0.01)
        #expect(abs(parts[1].minutes - 15) < 0.01)
        // Each needs 300 minutes at 15/day = 20 days.
        #expect(plan.book("a")?.finish == day(19))
    }

    @Test func sideBySideRedistributesWhenOneFinishes() {
        let short = item("s", pages: 10, words: 2_700) // 10 minutes
        let long = item("l", order: 1)
        let plan = Planner.makePlan(input(reading: [short, long], mode: .sideBySide))
        let parts = plan.today!.assignments
        #expect(parts.first { $0.bookID == "s" }?.finishesBook == true)
        #expect(abs((parts.first { $0.bookID == "l" }?.minutes ?? 0) - 20) < 0.01)
    }

    @Test func restDaysAreSkipped() {
        // Weekends only (Sunday = 1, Saturday = 7). Today is Wednesday.
        let plan = Planner.makePlan(input(reading: [item("a", pages: 60, words: 16_200)], days: [1, 7]))
        // 60 minutes = 2 weekend days: Sat Oct 17 and Sun Oct 18.
        #expect(plan.today!.assignments.isEmpty)
        #expect(plan.today!.isReadingDay == false)
        #expect(plan.book("a")?.start == day(3))
        #expect(plan.book("a")?.finish == day(4))
    }

    @Test func noTimeMeansNoFinishDates() {
        let plan = Planner.makePlan(input(reading: [item("a")], minutes: 0))
        #expect(plan.book("a")?.finish == nil)
        #expect(plan.days.count == 21)
    }

    @Test func finishedPageCountIsDoneToday() {
        let plan = Planner.makePlan(input(reading: [item("a", page: 300)]))
        #expect(plan.book("a")?.finish == day(0))
        #expect(plan.today!.assignments.isEmpty)
    }

    @Test func booksPerYearEstimate() {
        let value = Planner.booksPerYear(wpm: 250, dailyMinutes: 20, daysPerWeek: 7, averageWords: 80_000)
        #expect(abs(value - 22.8) < 0.2)
    }
}

struct ReadingSpeedTests {
    @Test func wpmMath() {
        #expect(abs(ReadingSpeed.wpm(words: 300, seconds: 60) - 300) < 0.001)
        #expect(abs(ReadingSpeed.wpm(words: 300, seconds: 90) - 200) < 0.001)
    }

    @Test func comprehensionScalesDown() {
        let perfect = ReadingSpeed.effectiveWPM(words: 300, seconds: 60, correct: 3, total: 3)
        let one = ReadingSpeed.effectiveWPM(words: 300, seconds: 60, correct: 1, total: 3)
        #expect(perfect == 300)
        #expect(one < perfect)
    }

    @Test func calibrationIgnoresOutliers() {
        #expect(ReadingSpeed.calibrated(current: 250, observed: 2000) == 250)
        let nudged = ReadingSpeed.calibrated(current: 250, observed: 300)
        #expect(nudged > 250 && nudged < 300)
    }

    @Test func observedNeedsEnoughReading() {
        #expect(ReadingSpeed.observedWPM(pagesRead: 1, wordsPerPage: 270, seconds: 600) == nil)
        #expect(ReadingSpeed.observedWPM(pagesRead: 10, wordsPerPage: 270, seconds: 60) == nil)
        let value = ReadingSpeed.observedWPM(pagesRead: 10, wordsPerPage: 270, seconds: 600)
        #expect(value != nil && abs(value! - 270) < 0.01)
    }

    @Test func percentileIsCentered() {
        #expect(ReadingSpeed.percentile(for: 238) == 50)
        #expect(ReadingSpeed.percentile(for: 400) > 90)
    }
}

struct StatsAndStorageTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    func session(daysAgo: Int, minutes: Double, from today: Date) -> ReadingSession {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        return ReadingSession(bookID: "a", startedAt: start, seconds: minutes * 60, fromPage: 1, toPage: 10)
    }

    @Test func streakSkipsRestDays() {
        // Wednesday Oct 14 2026. Reading days: weekdays only.
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 20))!
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        // Read today (Wed), Tue, Mon, Fri (weekend skipped), Thu.
        let sessions = [0, 1, 2, 5, 6].map { session(daysAgo: $0, minutes: 10, from: today) }
        #expect(ReadingStats.streak(sessions: sessions, readingDays: weekdays, today: today, calendar: calendar) == 5)
        // Not yet read today: streak still counts the days before.
        let notToday = [1, 2].map { session(daysAgo: $0, minutes: 10, from: today) }
        #expect(ReadingStats.streak(sessions: notToday, readingDays: weekdays, today: today, calendar: calendar) == 2)
    }

    @Test func dataDecodesWithMissingKeys() throws {
        let json = #"{"items":[],"preferences":{"dailyMinutes":45}}"#.data(using: .utf8)!
        let data = try JSONDecoder().decode(LeafData.self, from: json)
        #expect(data.preferences.dailyMinutes == 45)
        #expect(data.preferences.readingDays.count == 7)
        #expect(data.activeSession == nil)
    }

    @Test func activeSessionPauseResume() {
        let start = Date(timeIntervalSince1970: 1_000)
        var session = ActiveSession(bookID: "a", startedAt: start, startPage: 10, origin: .phone)
        session.pause(at: start.addingTimeInterval(60))
        #expect(session.elapsed(at: start.addingTimeInterval(500)) == 60)
        session.resume(at: start.addingTimeInterval(120))
        #expect(session.elapsed(at: start.addingTimeInterval(180)) == 120)
        #expect(session.revision == 2)
    }

    @Test func syncRoundTrip() {
        let event = SyncEvent.sessionLogged(ReadingSession(bookID: "a", startedAt: Date(timeIntervalSince1970: 5), seconds: 600, fromPage: 1, toPage: 20), activeID: nil)
        let packed = SyncCodec.encode(event, key: SyncCodec.eventKey)
        let back = SyncCodec.decode(SyncEvent.self, from: packed, key: SyncCodec.eventKey)
        #expect(back == event)
    }

    @Test func formatting() {
        #expect(LeafFormat.duration(minutes: 22) == "22 min")
        #expect(LeafFormat.duration(minutes: 372) == "6 h 12 min")
        #expect(LeafFormat.duration(minutes: 120) == "2 h")
        #expect(LeafFormat.clock(seconds: 247) == "4:07")
        #expect(LeafFormat.clock(seconds: 3723) == "1:02:03")
        #expect(LeafFormat.pages(from: 143, to: 158) == "pp. 143–158")
    }
}
