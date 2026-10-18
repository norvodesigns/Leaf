import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct TodayBriefTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    /// Monday 19 October 2026, 8 pm.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 20)) ?? Date() }

    private func day(_ offset: Int, hour: Int = 20) -> Date {
        let base = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(byAdding: .hour, value: hour, to: base) ?? base
    }

    private func book(_ id: String, pages: Int = 300) -> Book {
        Book(id: id, title: "Book \(id)", author: "Author \(id)", pages: pages, words: pages * 270, genres: ["fantasy"], themes: ["magic"])
    }

    private func plan(for data: LeafData) -> ReadingPlan {
        Planner.makePlan(PlanInput(
            reading: data.items(on: .reading), queue: data.items(on: .toRead), wpm: data.preferences.wpm, dailyMinutes: data.preferences.dailyMinutes,
            readingDays: data.preferences.readingDays, mode: data.preferences.planMode, today: now,
            minutesReadToday: ReadingStats.minutesRead(on: now, sessions: data.sessions, calendar: calendar), calendar: calendar
        ), recordDays: 14)
    }

    private func brief(_ data: LeafData, candidates: [Book] = [], previous: String? = nil) -> TodayBrief {
        let stats = candidates.isEmpty ? nil : CatalogStats(books: candidates)
        return TodayBriefBuilder.build(TodayBriefInput(data: data, plan: plan(for: data), now: now, calendar: calendar, previousGreetingID: previous, candidates: candidates, stats: stats))
    }

    private func readingData(page: Int = 120, sessionsAgo: [Int] = [1, 2]) -> LeafData {
        var data = LeafData()
        data.preferences.dailyMinutes = 30
        data.preferences.wpm = 250
        let b = book("a")
        data.items = [LibraryItem(book: b, shelf: .reading, currentPage: page, order: 1, addedAt: day(30), startedAt: day(20))]
        data.sessions = sessionsAgo.map { ReadingSession(bookID: "a", startedAt: day($0), seconds: 1200, fromPage: 90, toPage: 100) }
        return data
    }

    @Test func aBrandNewReaderGetsAWelcomeAndSuggestions() {
        let catalog = (0..<40).map { book("c\($0)") }
        let b = brief(LeafData(), candidates: catalog)
        #expect(b.mode == .brandNew)
        #expect(b.current == nil)
        #expect(b.picks.count == 6)
        #expect(!b.greeting.headline.isEmpty)
        #expect(b.slots.isEmpty)
    }

    @Test func aReadingDayShowsTheBookTheTeaAndTheGoal() {
        let b = brief(readingData())
        #expect(b.mode == .reading)
        #expect(b.current?.item.id == "a")
        #expect(b.current?.assignment != nil)
        #expect(b.goalMinutes == 30 && b.minutesToGoal == 30)
        #expect(b.steepSeconds == TeaSuggester.steepSeconds(for: b.tea, strength: .regular))
        #expect(b.week.count == 7)
        #expect(b.streak == 2)
        #expect(b.picks.isEmpty, "no catalog was given")
    }

    @Test func meetingTheGoalChangesTheMode() {
        var data = readingData()
        data.sessions.append(ReadingSession(bookID: "a", startedAt: day(0, hour: 8), seconds: 31 * 60, fromPage: 100, toPage: 120))
        let b = brief(data)
        #expect(b.mode == .goalMet)
        #expect(b.minutesToGoal == 0)
        #expect(b.goalProgress == 1)
        #expect(b.cupsToday >= 1)
    }

    @Test func aRestDayIsARestDay() {
        var data = readingData()
        data.preferences.readingDays = [1, 3, 4, 5, 6, 7] // Monday off
        #expect(brief(data).mode == .restDay)
    }

    @Test func nothingBeingReadMeansBetweenBooks() {
        var data = readingData()
        data.items[0].shelf = .finished
        data.items[0].currentPage = 300
        data.items[0].finishedAt = day(3)
        let catalog = (0..<40).map { book("c\($0)") }
        let b = brief(data, candidates: catalog)
        #expect(b.mode == .betweenBooks)
        #expect(b.picks.count == 6)
        #expect(!b.picks.contains { $0.book.id == "a" })
    }

    @Test func gentleNudgesNeverNag() {
        var data = readingData(sessionsAgo: [20])
        data.items[0].positionConfirmed = false
        var paused = LibraryItem(book: book("p"), shelf: .paused, currentPage: 200, order: 1, addedAt: day(100), startedAt: day(90), pausedAt: day(45))
        paused.positionConfirmed = true
        data.items.append(paused)
        let b = brief(data)
        #expect(b.nudges.count <= TodayBriefBuilder.maxNudges)
        let kinds = b.nudges.map(\.kind)
        #expect(kinds.contains(.confirmPosition(bookID: "a")))
        #expect(kinds.contains(.stalledBook(bookID: "a", days: 20)))
        #expect(kinds.contains(.pausedBookWaiting(bookID: "p", page: 200)))
        for nudge in b.nudges {
            #expect(!nudge.text.contains("!"))
            #expect(!nudge.text.lowercased().contains("behind"))
        }
    }

    @Test func readingTimesAppearWithTheirBooks() {
        var data = readingData()
        data.preferences.readingSlots = [ReadingSlot(hour: 8, label: "Morning tea"), ReadingSlot(hour: 21, minute: 30)]
        let b = brief(data)
        #expect(b.slots.count == 2)
        #expect(b.nextSlot?.slot.hour == 21)
        #expect(b.slots.allSatisfy { $0.parts.first?.bookID == "a" })
    }

    @Test func theGreetingIsStableAndDoesNotRepeatYesterday() {
        let data = readingData()
        let first = brief(data)
        let again = brief(data)
        #expect(first.greeting.lineID == again.greeting.lineID)
        let next = brief(data, previous: first.greeting.lineID)
        #expect(next.greeting.lineID != first.greeting.lineID)
    }

    @Test func aYearGoalAppearsOnlyWhenSet() {
        var data = readingData()
        #expect(brief(data).yearGoal == nil)
        data.preferences.yearlyGoal = 24
        #expect(brief(data).yearGoal?.goal == 24)
    }
}
