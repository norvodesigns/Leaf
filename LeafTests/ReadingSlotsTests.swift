import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct ReadingSlotsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    /// 2026-10-19 is a Monday (weekday 2).
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)) ?? Date() }

    private func day(_ assignments: [Assignment]) -> PlanDay {
        PlanDay(date: monday, isReadingDay: true, assignments: assignments)
    }

    private func a(_ id: String, minutes: Double, from: Int, to: Int, finishes: Bool = false) -> Assignment {
        Assignment(bookID: id, minutes: minutes, fromPage: from, toPage: to, finishesBook: finishes)
    }

    private func slot(_ hour: Int, _ minute: Int = 0, book: String? = nil, weekdays: Set<Int>? = nil, enabled: Bool = true) -> ReadingSlot {
        ReadingSlot(hour: hour, minute: minute, weekdays: weekdays, bookID: book, isEnabled: enabled)
    }

    @Test func oneSlotGetsTheWholeDay() {
        let plans = SlotPlanner.plan(day: day([a("hobbit", minutes: 30, from: 143, to: 160)]), slots: [slot(21)], calendar: calendar)
        #expect(plans.count == 1)
        #expect(plans[0].parts == [SlotPart(bookID: "hobbit", minutes: 30, fromPage: 143, toPage: 160, finishesBook: false)])
    }

    @Test func oneBookSplitsAcrossTwoTimes() {
        let plans = SlotPlanner.plan(day: day([a("hobbit", minutes: 30, from: 101, to: 120)]), slots: [slot(21), slot(8)], calendar: calendar)
        #expect(plans.map { $0.slot.hour } == [8, 21], "earlier times come first")
        let parts = plans.flatMap(\.parts)
        #expect(parts.map(\.fromPage) == [101, 111])
        #expect(parts.map(\.toPage) == [110, 120])
        #expect(abs(parts.map(\.minutes).reduce(0, +) - 30) < 1e-9)
    }

    @Test func eachBookGetsItsOwnTime() {
        let plans = SlotPlanner.plan(
            day: day([a("hobbit", minutes: 15, from: 10, to: 20), a("circe", minutes: 15, from: 5, to: 15)]),
            slots: [slot(8), slot(21)], calendar: calendar
        )
        #expect(plans.map { $0.parts.map(\.bookID) } == [["hobbit"], ["circe"]])
    }

    @Test func aSlotTiedToABookReadsThatBook() {
        let plans = SlotPlanner.plan(
            day: day([a("hobbit", minutes: 15, from: 10, to: 20), a("circe", minutes: 15, from: 5, to: 15)]),
            slots: [slot(8, book: "circe"), slot(21)], calendar: calendar
        )
        #expect(plans[0].parts.map(\.bookID) == ["circe"])
        #expect(plans[1].parts.map(\.bookID) == ["hobbit"])
    }

    @Test func aSlotTiedToABookNotInTodaysPlanReadsWhatIsNext() {
        let plans = SlotPlanner.plan(day: day([a("hobbit", minutes: 20, from: 10, to: 20)]), slots: [slot(8, book: "circe")], calendar: calendar)
        #expect(plans.count == 1)
        #expect(plans[0].parts.map(\.bookID) == ["hobbit"])
    }

    @Test func theBiggerBookGetsTheExtraTime() {
        let plans = SlotPlanner.plan(
            day: day([a("small", minutes: 10, from: 1, to: 6), a("big", minutes: 40, from: 1, to: 40)]),
            slots: [slot(8), slot(13), slot(21)], calendar: calendar
        )
        let counts = Dictionary(grouping: plans.flatMap(\.parts), by: \.bookID).mapValues(\.count)
        #expect(counts["big"] == 2)
        #expect(counts["small"] == 1)
    }

    @Test func moreBooksThanTimesShareTimes() {
        let books = [a("a", minutes: 10, from: 1, to: 5), a("b", minutes: 10, from: 1, to: 5), a("c", minutes: 10, from: 1, to: 5)]
        let plans = SlotPlanner.plan(day: day(books), slots: [slot(8), slot(21)], calendar: calendar)
        #expect(plans.count == 2)
        #expect(Set(plans.flatMap(\.parts).map(\.bookID)) == ["a", "b", "c"])
    }

    @Test func slotsWhenEveryTimeBelongsToAnotherBookStillCoverEverything() {
        let plans = SlotPlanner.plan(
            day: day([a("hobbit", minutes: 15, from: 10, to: 20), a("circe", minutes: 15, from: 5, to: 15)]),
            slots: [slot(8, book: "hobbit")], calendar: calendar
        )
        #expect(plans.count == 1)
        #expect(Set(plans[0].parts.map(\.bookID)) == ["hobbit", "circe"], "the leftover book reads after the last time")
    }

    @Test func disabledAndOtherWeekdaySlotsAreIgnored() {
        let slots = [slot(8, enabled: false), slot(12, weekdays: [1, 7]), slot(21, weekdays: [2])]
        let plans = SlotPlanner.plan(day: day([a("hobbit", minutes: 20, from: 1, to: 10)]), slots: slots, calendar: calendar)
        #expect(plans.map { $0.slot.hour } == [21])
    }

    @Test func noSlotsOrNoReadingMeansNoPlans() {
        #expect(SlotPlanner.plan(day: day([a("hobbit", minutes: 20, from: 1, to: 10)]), slots: [], calendar: calendar).isEmpty)
        #expect(SlotPlanner.plan(day: day([]), slots: [slot(21)], calendar: calendar).isEmpty)
    }

    @Test func aBookTooShortToSplitUsesOneTime() {
        let plans = SlotPlanner.plan(day: day([a("poem", minutes: 5, from: 40, to: 40, finishes: true)]), slots: [slot(8), slot(21)], calendar: calendar)
        #expect(plans.count == 1)
        #expect(plans[0].parts[0].finishesBook)
    }

    @Test func finishingFlagLandsOnlyOnTheLastPart() {
        let plans = SlotPlanner.plan(day: day([a("hobbit", minutes: 30, from: 1, to: 30, finishes: true)]), slots: [slot(8), slot(21)], calendar: calendar)
        #expect(plans.flatMap(\.parts).map(\.finishesBook) == [false, true])
    }

    @Test func everyMinuteAndPageLandsInExactlyOneSlot() {
        var rng = SeededGenerator(seed: 42)
        for trial in 0..<300 {
            let bookCount = 1 + Int(rng.next() % 4)
            var cursor = 1
            var assignments: [Assignment] = []
            for index in 0..<bookCount {
                let pages = 1 + Int(rng.next() % 40)
                assignments.append(a("b\(index)", minutes: Double(5 + Int(rng.next() % 40)), from: cursor, to: cursor + pages - 1, finishes: rng.next() % 5 == 0))
                cursor += pages
            }
            let slotCount = 1 + Int(rng.next() % 4)
            var slots: [ReadingSlot] = []
            for i in 0..<slotCount {
                let hour: Int = 6 + i * 4
                let minute: Int = Int(rng.next() % 4) * 15
                var pinnedBook: String?
                if rng.next() % 3 == 0 { pinnedBook = "b" + String(Int(rng.next() % UInt64(bookCount + 1))) }
                slots.append(slot(hour, minute, book: pinnedBook))
            }
            let plans = SlotPlanner.plan(day: day(assignments), slots: slots, calendar: calendar)
            let parts: [SlotPart] = plans.flatMap(\.parts)
            let plannedMinutes: Double = assignments.map(\.minutes).reduce(0, +)
            let slottedMinutes: Double = parts.map(\.minutes).reduce(0, +)
            #expect(abs(slottedMinutes - plannedMinutes) < 1e-6, "minutes preserved (trial \(trial))")
            for assignment in assignments {
                let mine = parts.filter { $0.bookID == assignment.bookID }.sorted { $0.fromPage < $1.fromPage }
                #expect(mine.first?.fromPage == assignment.fromPage, "trial \(trial)")
                #expect(mine.last?.toPage == assignment.toPage, "trial \(trial)")
                for (left, right) in zip(mine, mine.dropFirst()) {
                    let expectedStart: Int = left.toPage + 1
                    #expect(right.fromPage == expectedStart, "pages contiguous (trial \(trial))")
                }
                let finishing: Int = mine.filter(\.finishesBook).count
                let expectedFinishing: Int = assignment.finishesBook ? 1 : 0
                #expect(finishing == expectedFinishing, "trial \(trial)")
            }
            let times: [Int] = plans.map(\.slot.minuteOfDay)
            #expect(times == times.sorted(), "chronological")
        }
    }

    @Test func nextSlotSkipsTimesThatHavePassed() {
        let plans = SlotPlanner.plan(day: day([a("hobbit", minutes: 30, from: 1, to: 30)]), slots: [slot(8), slot(21)], calendar: calendar)
        let noon = calendar.date(byAdding: .hour, value: 12, to: monday) ?? monday
        #expect(SlotPlanner.next(in: plans, day: monday, now: noon, calendar: calendar)?.slot.hour == 21)
        let night = calendar.date(byAdding: .hour, value: 23, to: monday) ?? monday
        #expect(SlotPlanner.next(in: plans, day: monday, now: night, calendar: calendar) == nil)
    }

    @Test func olderPreferencesKeepTheirSingleReminderTime() throws {
        var prefs = ReadingPreferences()
        #expect(prefs.effectiveReadingSlots.isEmpty, "reminders off, no slots")
        prefs.reminderEnabled = true
        prefs.reminderHour = 20
        prefs.reminderMinute = 45
        #expect(prefs.effectiveReadingSlots.map(\.minuteOfDay) == [20 * 60 + 45])
        prefs.readingSlots = [ReadingSlot(hour: 8), ReadingSlot(hour: 21, minute: 30)]
        #expect(prefs.effectiveReadingSlots.count == 2)
        let decoded = try JSONDecoder().decode(ReadingPreferences.self, from: try JSONEncoder().encode(prefs))
        #expect(decoded.readingSlots == prefs.readingSlots)
        #expect(try JSONDecoder().decode(ReadingPreferences.self, from: Data("{}".utf8)).readingSlots.isEmpty)
    }

    @Test func slotTimesAreClamped() {
        let s = ReadingSlot(hour: 99, minute: -4)
        #expect(s.hour == 23 && s.minute == 0)
    }
}
