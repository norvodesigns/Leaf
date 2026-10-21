import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Fixture

/// Builds small, exact reading histories. Every id is derived from the content, so nothing here is random.
struct InsightsFixture {
    let calendar: Calendar

    init(timeZone: String = "America/New_York") {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        self.calendar = calendar
    }

    /// Sunday, Oct 18 2026, 20:00 local.
    var now: Date { date(2026, 10, 18, 20) }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    /// `offset` days from the day of `base` (default: now), at `hour`.
    func day(_ offset: Int, hour: Int = 20, minute: Int = 0, from base: Date? = nil) -> Date {
        let start = calendar.startOfDay(for: base ?? now)
        let shifted = calendar.date(byAdding: .day, value: offset, to: start) ?? start
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shifted) ?? shifted
    }

    static func uuid(_ seed: String) -> UUID {
        let hash = SeededGenerator.hash(seed)
        let hex = String(hash, radix: 16).leftPadded(to: 12)
        return UUID(uuidString: "00000000-0000-4000-8000-\(hex)") ?? UUID(uuidString: "00000000-0000-4000-8000-000000000000")!
    }

    func book(_ id: String, pages: Int = 300, genres: [String] = ["fantasy"], author: String = "Ann Author") -> Book {
        Book(id: id, title: "Title \(id)", author: author, pages: pages, words: pages * 270, genres: genres)
    }

    func item(
        _ id: String, shelf: Shelf = .reading, pages: Int = 300, genres: [String] = ["fantasy"],
        author: String = "Ann Author", started: Date? = nil, finished: Date? = nil, rating: Int? = nil, page: Int = 0
    ) -> LibraryItem {
        LibraryItem(
            book: book(id, pages: pages, genres: genres, author: author), shelf: shelf,
            currentPage: shelf == .finished ? pages : page, order: 0, addedAt: started ?? finished ?? day(-400),
            startedAt: started, finishedAt: shelf == .finished ? (finished ?? day(-1)) : nil, rating: rating
        )
    }

    /// One minute of reading per page at 270 words a page is 270 words a minute.
    func session(_ bookID: String, at start: Date, minutes: Double, pages: Int, from: Int = 0, kind: SessionKind = .timed) -> ReadingSession {
        ReadingSession(
            id: InsightsFixture.uuid("\(bookID)|\(start.timeIntervalSince1970)|\(minutes)|\(pages)|\(from)"),
            bookID: bookID, startedAt: start, seconds: minutes * 60, fromPage: from, toPage: from + pages, kind: kind
        )
    }

    /// One session on each listed day offset, with the hour and minutes chosen by the position in the list.
    func reader(
        offsets: [Int], book: String = "b", kind: SessionKind = .timed,
        hour: (Int) -> Int, minutes: (Int) -> Double, wpm: (Int) -> Double = { _ in 270 }
    ) -> [ReadingSession] {
        offsets.enumerated().map { index, offset in
            let length = minutes(index)
            let pages = max(2, Int((length * wpm(index) / 270).rounded()))
            return session(book, at: day(offset, hour: hour(index)), minutes: length, pages: pages, kind: kind)
        }
    }

    func data(
        items: [LibraryItem] = [], sessions: [ReadingSession] = [], journal: [JournalEntry] = [],
        _ prefs: (inout ReadingPreferences) -> Void = { _ in }
    ) -> LeafData {
        var data = LeafData()
        data.items = items
        data.sessions = sessions
        data.journal = journal
        prefs(&data.preferences)
        return data
    }

    func engine(_ data: LeafData, now: Date? = nil) -> InsightsEngine {
        InsightsEngine(data: data, now: now ?? self.now, calendar: calendar)
    }

    func entry(
        _ book: String = "b", kind: JournalEntry.Kind = .quote, _ text: String, page: Int? = nil,
        favourite: Bool = false, at created: Date? = nil, title: String? = nil, author: String = "Ann Author"
    ) -> JournalEntry {
        let when = created ?? day(-1)
        return JournalEntry(
            id: InsightsFixture.uuid("\(book)|\(text)|\(when.timeIntervalSince1970)"),
            bookID: book, bookTitle: title ?? "Title \(book)", bookAuthor: author, kind: kind, text: text, page: page,
            isFavorite: favourite, createdAt: when
        )
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? String(suffix(length)) : String(repeating: "0", count: length - count) + self
    }
}

// MARK: - Heatmap

struct InsightsHeatmapTests {
    let fx = InsightsFixture()

    @Test func emptyDataGivesAQuietYear() {
        let cells = fx.engine(fx.data()).heatmap(year: 2026)
        #expect(cells.count == 365)
        #expect(cells.allSatisfy { $0.minutes == 0 && $0.ring == 0 && !$0.didRead })
        #expect(cells.first?.date == fx.date(2026, 1, 1, 0))
        #expect(cells.last?.date == fx.date(2026, 12, 31, 0))
        #expect(cells.filter(\.isToday).count == 1)
        #expect(cells.filter(\.isToday).first?.date == fx.date(2026, 10, 18, 0))
    }

    @Test func futureCellsAreAfterToday() {
        let cells = fx.engine(fx.data()).heatmap(year: 2026)
        #expect(cells.filter(\.isFuture).count == 365 - 291)
        #expect(cells.allSatisfy { $0.isFuture == ($0.date > fx.date(2026, 10, 18, 0)) })
        #expect(fx.engine(fx.data()).heatmap(year: 2027).allSatisfy { $0.isFuture })
        #expect(fx.engine(fx.data()).heatmap(year: 2025).allSatisfy { !$0.isFuture })
    }

    @Test func leapYearsHave366Days() {
        let engine = fx.engine(fx.data())
        let cells = engine.heatmap(year: 2028)
        #expect(cells.count == 366)
        #expect(cells.contains { $0.date == fx.date(2028, 2, 29, 0) })
        #expect(engine.heatmap(year: 2100).count == 365)
        #expect(engine.heatmap(year: 2027).count == 365)
    }

    @Test func daysAreConsecutiveAcrossDaylightSavingChanges() {
        let cells = fx.engine(fx.data()).heatmap(year: 2026)
        #expect(Set(cells.map(\.date)).count == cells.count)
        for (a, b) in zip(cells, cells.dropFirst()) {
            #expect(fx.calendar.dateComponents([.day], from: a.date, to: b.date).day == 1)
            #expect(fx.calendar.startOfDay(for: b.date) == b.date)
        }
    }

    @Test func oneDayOfDataLeavesOneRing() {
        let day = fx.day(-3, hour: 21)
        let sessions = [fx.session("b", at: day, minutes: 30, pages: 30)]
        let cells = fx.engine(fx.data(sessions: sessions)).heatmap(year: 2026)
        let read = cells.filter(\.didRead)
        #expect(read.count == 1)
        #expect(read[0].date == fx.date(2026, 10, 15, 0))
        #expect(abs(read[0].minutes - 30) < 1e-9)
        #expect(read[0].ring > 0 && read[0].ring <= 1)
        #expect(cells.filter { !$0.didRead }.allSatisfy { $0.ring == 0 })
    }

    @Test func yearBoundariesSplitAtLocalMidnight() {
        let sessions = [
            fx.session("b", at: fx.date(2026, 12, 31, 23, 30), minutes: 20, pages: 20),
            fx.session("b", at: fx.date(2027, 1, 1, 0, 30), minutes: 10, pages: 10),
        ]
        let engine = fx.engine(fx.data(sessions: sessions), now: fx.date(2027, 6, 1))
        let last2026 = engine.heatmap(year: 2026).last
        let first2027 = engine.heatmap(year: 2027).first
        #expect(last2026?.minutes == 20)
        #expect(first2027?.minutes == 10)
    }

    @Test func timeZonesDecideWhichDayASessionBelongsTo() {
        // 23:30 in New York is already the next day in UTC and in Tokyo.
        let instant = fx.date(2026, 3, 10, 23, 30)
        let sessions = [fx.session("b", at: instant, minutes: 25, pages: 25)]
        let data = fx.data(sessions: sessions)
        let ny = InsightsEngine(data: data, now: fx.now, calendar: fx.calendar).heatmap(year: 2026)
        let utcFx = InsightsFixture(timeZone: "UTC")
        let utc = InsightsEngine(data: data, now: fx.now, calendar: utcFx.calendar).heatmap(year: 2026)
        #expect(ny.first { $0.didRead }?.date == fx.date(2026, 3, 10, 0))
        #expect(utc.first { $0.didRead }?.date == utcFx.date(2026, 3, 11, 0))
        let nyMinutes: Double = ny.reduce(0) { $0 + $1.minutes }
        let utcMinutes: Double = utc.reduce(0) { $0 + $1.minutes }
        #expect(nyMinutes == utcMinutes)
    }

    @Test func ringGrowsWithMinutesAndStaysInRange() {
        var previous = 0.0
        for minutes in stride(from: 0.0, through: 400, by: 2.5) {
            let ring = HeatCell.ringScale(minutes: minutes, reference: 30)
            #expect(ring >= previous)
            #expect(ring >= 0 && ring <= 1)
            if minutes == 0 { #expect(ring == 0) } else { #expect(ring >= 0.1) }
            previous = ring
        }
        #expect(HeatCell.ringScale(minutes: 60, reference: 30) == 1)
        #expect(HeatCell.ringScale(minutes: 5, reference: 0) > 0)
        #expect(HeatCell.ringScale(minutes: -4, reference: 30) == 0)
    }

    @Test func ringsFollowTheReadersOwnTypicalDay() {
        // A 20-minute goal, but this reader really reads for an hour. The 20-minute day must stay smaller.
        var sessions = (1...30).map { fx.session("b", at: fx.day(-$0), minutes: 60, pages: 60) }
        sessions.append(fx.session("b", at: fx.day(-40), minutes: 20, pages: 20))
        let cells = fx.engine(fx.data(sessions: sessions)).heatmap(year: 2026)
        let long = cells.first { $0.date == fx.date(2026, 10, 17, 0) }
        let short = cells.first { $0.date == fx.date(2026, 9, 8, 0) }
        #expect(long != nil && short != nil)
        #expect((short?.ring ?? 1) < (long?.ring ?? 0))
        #expect((long?.ring ?? 0) <= 1)
    }

    @Test func gridPositionsFollowTheCalendarsFirstWeekday() {
        let cells = fx.engine(fx.data()).heatmap(year: 2026)
        // Jan 1 2026 is a Thursday, so with weeks starting on Sunday it sits in row 4 of column 0.
        #expect(cells[0].row == 4 && cells[0].column == 0)
        #expect(Set(cells.map { "\($0.row)-\($0.column)" }).count == cells.count)
        #expect(cells.allSatisfy { (0..<7).contains($0.row) })
        for (a, b) in zip(cells, cells.dropFirst()) {
            #expect(b.row == (a.row + 1) % 7)
            #expect(b.column == a.column + (b.row == 0 ? 1 : 0))
        }
        var monday = fx.calendar
        monday.firstWeekday = 2
        let shifted = InsightsEngine(data: fx.data(), now: fx.now, calendar: monday).heatmap(year: 2026)
        #expect(shifted[0].row == 3)
    }

    @Test func restDaysAreMarkedFromPreferencesAndStillShowReading() {
        // Weekends are rest days, but a Sunday session still leaves a ring.
        let sunday = fx.day(0, hour: 9)
        let data = fx.data(sessions: [fx.session("b", at: sunday, minutes: 20, pages: 20)]) { $0.readingDays = [2, 3, 4, 5, 6] }
        let cells = fx.engine(data).heatmap(year: 2026)
        let cell = cells.first { $0.isToday }
        #expect(cell?.isReadingDay == false)
        #expect(cell?.isRestDay == true)
        #expect(cell?.didRead == true)
        #expect(cells.filter(\.isReadingDay).allSatisfy { (2...6).contains(fx.calendar.component(.weekday, from: $0.date)) })
    }

    @Test func finishedBooksMarkTheirDay() {
        let finished = fx.item("done", shelf: .finished, finished: fx.date(2026, 5, 4, 22))
        let cells = fx.engine(fx.data(items: [finished])).heatmap(year: 2026)
        #expect(cells.first { $0.date == fx.date(2026, 5, 4, 0) }?.finishedBookIDs == ["done"])
        #expect(cells.filter { !$0.finishedBookIDs.isEmpty }.count == 1)
    }

    @Test func sessionsOfRemovedBooksStillCount() {
        let sessions = [fx.session("gone", at: fx.day(-2), minutes: 45, pages: 40)]
        let cells = fx.engine(fx.data(sessions: sessions)).heatmap(year: 2026)
        #expect(cells.first { $0.date == fx.date(2026, 10, 16, 0) }?.minutes == 45)
    }
}

// MARK: - Streaks

struct InsightsStreakTests {
    let fx = InsightsFixture()

    func readOn(_ offsets: [Int], seconds: Double = 600) -> [ReadingSession] {
        offsets.map { fx.session("b", at: fx.day($0, hour: 19), minutes: seconds / 60, pages: 10) }
    }

    @Test func emptyHistoryHasNoStreak() {
        let engine = fx.engine(fx.data())
        #expect(engine.currentStreak() == 0)
        #expect(engine.longestStreak() == 0)
        #expect(engine.longestStreak(year: 2026) == 0)
    }

    @Test func consecutiveDaysCount() {
        let engine = fx.engine(fx.data(sessions: readOn([-3, -2, -1, 0])))
        #expect(engine.currentStreak() == 4)
        #expect(engine.longestStreak() == 4)
    }

    @Test func notReadingYetTodayDoesNotBreakIt() {
        let engine = fx.engine(fx.data(sessions: readOn([-3, -2, -1])))
        #expect(engine.currentStreak() == 3)
    }

    @Test func aMissedPlannedDayBreaksIt() {
        // Read the 15th and 18th; the 16th and 17th were planned days.
        let engine = fx.engine(fx.data(sessions: readOn([-3, 0])))
        #expect(engine.currentStreak() == 1)
        let stale = fx.engine(fx.data(sessions: readOn([-5, -4, -3])))
        #expect(stale.currentStreak() == 0)
        #expect(stale.longestStreak() == 3)
    }

    @Test func restDaysBridgeAGap() {
        // Planned Monday to Friday. Fri Oct 9, then Mon Oct 12 through Fri Oct 16 and Sunday Oct 18 (today).
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let offsets = [-9, -6, -5, -4, -3, -2, 0]
        let data = fx.data(sessions: readOn(offsets)) { $0.readingDays = weekdays }
        let engine = fx.engine(data)
        // Sat 17th is a rest day, so today's reading joins Friday's run: 6 days back to Mon 12th, then a Fri 9th bridge.
        #expect(engine.currentStreak() == 7)
        #expect(engine.longestStreak() == 7)
        // The same reading with every day planned is broken by the Saturday and the weekend before.
        let strict = fx.engine(fx.data(sessions: readOn(offsets)))
        #expect(strict.currentStreak() == 1)
    }

    @Test func aRestDayAtTheEndKeepsTheStreakAlive() {
        // Planned Monday to Friday and today is Sunday: nothing is owed today, and Saturday was a rest day.
        let data = fx.data(sessions: readOn([-3, -2])) { $0.readingDays = [2, 3, 4, 5, 6] }
        #expect(fx.engine(data).currentStreak() == 2)
        // Skipping Friday (planned) ends it.
        let broken = fx.data(sessions: readOn([-4, -3])) { $0.readingDays = [2, 3, 4, 5, 6] }
        #expect(fx.engine(broken).currentStreak() == 0)
    }

    @Test func emptyReadingDaysMeansEveryDay() {
        let data = fx.data(sessions: readOn([-3, 0])) { $0.readingDays = [] }
        #expect(fx.engine(data).currentStreak() == 1)
    }

    @Test func sessionsUnderAMinuteDoNotCount() {
        let sessions = readOn([-2, -1], seconds: 59) + readOn([0], seconds: 61)
        let engine = fx.engine(fx.data(sessions: sessions))
        #expect(engine.currentStreak() == 1)
        #expect(engine.minutes(on: fx.day(-1)) > 0)
    }

    @Test func longestStreakFindsTheBestRun() {
        let engine = fx.engine(fx.data(sessions: readOn([-30, -29, -28, -20, -19, -18, -17, -16, -5, -4])))
        #expect(engine.longestStreak() == 5)
        #expect(engine.currentStreak() == 0)
    }

    @Test func streaksAreCutAtYearEnds() {
        // Dec 29 2026 to Jan 3 2027 is six days in a row, split three and three by the new year.
        let days = [(2026, 12, 29), (2026, 12, 30), (2026, 12, 31), (2027, 1, 1), (2027, 1, 2), (2027, 1, 3)]
        let sessions = days.map { fx.session("b", at: fx.date($0.0, $0.1, $0.2, 19), minutes: 10, pages: 10) }
        let engine = fx.engine(fx.data(sessions: sessions), now: fx.date(2027, 3, 1))
        #expect(engine.longestStreak() == 6)
        #expect(engine.longestStreak(year: 2026) == 3)
        #expect(engine.longestStreak(year: 2027) == 3)
        #expect(engine.longestStreak(year: 2028) == 0)
    }

    @Test func longestIsNeverShorterThanCurrentOrLongerThanReadDays() {
        var rng = SeededGenerator(seed: 41)
        for _ in 0..<40 {
            let offsets = (0..<45).filter { _ in rng.unit() < 0.6 }.map { -$0 }
            let data = fx.data(sessions: readOn(offsets)) { $0.readingDays = rng.unit() < 0.5 ? [2, 3, 4, 5, 6] : [] }
            let engine = fx.engine(data)
            #expect(engine.longestStreak() >= engine.currentStreak())
            #expect(engine.longestStreak() <= engine.readDays.count)
        }
    }

    @Test func currentStreakAgreesWithTheAppsExistingStreak() {
        // The same rules as ReadingStats.streak, checked on many random schedules and histories.
        var rng = SeededGenerator(seed: 2026)
        for _ in 0..<120 {
            var days = Set<Int>()
            for weekday in 1...7 where rng.unit() < 0.6 { days.insert(weekday) }
            let offsets = (0..<40).filter { _ in rng.unit() < 0.7 }.map { -$0 }
            var sessions = offsets.map { fx.session("b", at: fx.day($0, hour: 8 + Int(rng.unit() * 12)), minutes: 5 + rng.unit() * 50, pages: 5) }
            for _ in 0..<3 { sessions.append(fx.session("b", at: fx.day(-Int(rng.unit() * 40), hour: 7), minutes: 0.5, pages: 1)) }
            let data = fx.data(sessions: sessions) { $0.readingDays = days }
            let expected = ReadingStats.streak(sessions: sessions, readingDays: days, today: fx.now, calendar: fx.calendar)
            #expect(fx.engine(data).currentStreak() == expected)
        }
    }

    @Test func streakAsOfAnEarlierDayIgnoresWhatCameAfter() {
        let engine = fx.engine(fx.data(sessions: readOn([-10, -9, -8, -1, 0])))
        #expect(engine.currentStreak(asOf: fx.day(-8)) == 3)
        #expect(engine.currentStreak() == 2)
    }

    @Test func timeZonesChangeWhichDaysWereRead() {
        // 22:30 in New York is 03:30 the next day in UTC, so the same sessions give a different streak shape.
        let sessions = [-2, -1, 0].map { fx.session("b", at: fx.day($0, hour: 22, minute: 30), minutes: 10, pages: 10) }
        let utc = InsightsFixture(timeZone: "UTC")
        let data = fx.data(sessions: sessions)
        #expect(InsightsEngine(data: data, now: fx.now, calendar: fx.calendar).currentStreak() == 3)
        // At now = Sunday 20:00 New York (Monday 00:00 UTC), UTC's today is Monday with no reading yet: still three.
        #expect(InsightsEngine(data: data, now: fx.now, calendar: utc.calendar).currentStreak() == 3)
        #expect(InsightsEngine(data: data, now: fx.date(2026, 10, 18, 23), calendar: utc.calendar).currentStreak() == 3)
    }
}

// MARK: - Best time of day

struct InsightsBestTimeTests {
    let fx = InsightsFixture()

    /// Daily reading at fixed hours, cycling through `hours`, at the given speeds.
    func history(days: Int = 40, hours: [Int], minutes: Double = 30, wpm: @escaping (Int) -> Double = { _ in 270 }, kind: SessionKind = .timed) -> [ReadingSession] {
        fx.reader(offsets: (1...days).map { -$0 }, kind: kind, hour: { hours[$0 % hours.count] }, minutes: { _ in minutes }, wpm: wpm)
    }

    func engine(_ sessions: [ReadingSession]) -> InsightsEngine {
        fx.engine(fx.data(items: [fx.item("b", pages: 100_000)], sessions: sessions))
    }

    @Test func tooLittleHistoryGivesNothing() {
        #expect(fx.engine(fx.data()).bestTimeOfDay() == nil)
        #expect(engine(history(days: 9, hours: [20])).bestTimeOfDay() == nil)
        // Ten sittings but only four days.
        let crowded = (0..<10).map { fx.session("b", at: fx.day(-($0 % 4) - 1, hour: 8 + $0), minutes: 20, pages: 20) }
        #expect(engine(crowded).bestTimeOfDay() == nil)
        #expect(engine(history(days: 10, hours: [20])).bestTimeOfDay() != nil)
    }

    @Test func manualSessionsSayNothingAboutWhenYouRead() {
        #expect(engine(history(hours: [20], kind: .manual)).bestTimeOfDay() == nil)
    }

    @Test func eveningReaderIsFoundWithAWindow() throws {
        let result = try #require(engine(history(hours: [20, 20, 21])).bestTimeOfDay())
        #expect(result.consistent.daypart == .evening)
        #expect(result.consistent.startHour == 20)
        #expect(result.consistent.endHour == 22)
        #expect(result.consistent.minuteShare == 1)
        #expect(result.sessionCount == 40)
        #expect(result.reason.contains("in the evening"))
        #expect(result.reason.contains("8 to 10 pm"))
        // Only one stretch of the day has any speed data, so there is nothing to compare it with.
        #expect(result.fastest == nil)
        #expect(result.reason.contains("isn’t enough pacing data"))
    }

    @Test func steadySpeedEverywhereIsSaidSo() throws {
        let result = try #require(engine(history(hours: [8, 8, 20])).bestTimeOfDay())
        #expect(result.fastest == nil)
        #expect(result.reason.contains("about the same"))
        #expect(result.consistent.daypart == .morning)
    }

    @Test func fastestAndMostConsistentCanDiffer() throws {
        // Mornings are quick (330 wpm) but rare; evenings are slower (240 wpm) but constant.
        var sessions: [ReadingSession] = []
        sessions += fx.reader(offsets: (1...30).map { -$0 }, hour: { _ in 20 }, minutes: { _ in 30 }, wpm: { _ in 240 })
        sessions += fx.reader(offsets: (31...42).map { -$0 }, hour: { _ in 8 }, minutes: { _ in 30 }, wpm: { _ in 330 })
        let result = try #require(engine(sessions).bestTimeOfDay())
        #expect(result.consistent.daypart == .evening)
        #expect(result.fastest?.daypart == .morning)
        #expect((result.fastest?.wpm ?? 0) > 300)
        #expect((result.consistent.wpm ?? 0) < 260)
        #expect(result.reason.contains("You read fastest in the morning"))
        #expect(result.dayparts.count == Daypart.allCases.count)
        let shareTotal: Double = result.dayparts.map(\.minuteShare).reduce(0, +)
        #expect(abs(shareTotal - 1) < 1e-9)
    }

    @Test func oneStretchCanWinBoth() throws {
        var sessions: [ReadingSession] = []
        sessions += fx.reader(offsets: (1...30).map { -$0 }, hour: { _ in 21 }, minutes: { _ in 30 }, wpm: { _ in 320 })
        sessions += fx.reader(offsets: (31...40).map { -$0 }, hour: { _ in 12 }, minutes: { _ in 30 }, wpm: { _ in 250 })
        let result = try #require(engine(sessions).bestTimeOfDay())
        #expect(result.consistent.daypart == .evening)
        #expect(result.fastest?.daypart == .evening)
        #expect(result.reason.contains("It is also when you read fastest"))
    }

    @Test func fewMeasurableSittingsMeansNoFastestClaim() throws {
        // Sittings of two minutes cannot be timed for speed.
        let sessions = history(days: 20, hours: [20], minutes: 2)
        let result = try #require(engine(sessions).bestTimeOfDay())
        #expect(result.fastest == nil)
        #expect(result.reason.contains("isn’t enough pacing data"))
    }

    @Test func aTinyLeadIsNotCalledFastest() throws {
        var sessions: [ReadingSession] = []
        sessions += fx.reader(offsets: (1...20).map { -$0 }, hour: { _ in 20 }, minutes: { _ in 30 }, wpm: { _ in 270 })
        sessions += fx.reader(offsets: (21...40).map { -$0 }, hour: { _ in 8 }, minutes: { _ in 30 }, wpm: { _ in 274 })
        let result = try #require(engine(sessions).bestTimeOfDay())
        #expect(result.fastest == nil)
    }

    @Test func sameDataSameAnswer() {
        let sessions = history(hours: [7, 12, 20])
        #expect(engine(sessions).bestTimeOfDay() == engine(sessions.reversed()).bestTimeOfDay())
    }

    @Test func theCalendarsTimeZoneDecidesTheDaypart() throws {
        // 20:00 in New York is 09:00 the next day in Tokyo.
        let sessions = history(hours: [20])
        let data = fx.data(items: [fx.item("b", pages: 100_000)], sessions: sessions)
        let tokyo = InsightsFixture(timeZone: "Asia/Tokyo")
        let ny = try #require(InsightsEngine(data: data, now: fx.now, calendar: fx.calendar).bestTimeOfDay())
        let jp = try #require(InsightsEngine(data: data, now: fx.now, calendar: tokyo.calendar).bestTimeOfDay())
        #expect(ny.consistent.daypart == .evening)
        #expect(jp.consistent.daypart == .morning)
    }

    @Test func windowsAndHoursReadWell() {
        #expect(BestTimeOfDay.hourLabel(0) == "midnight")
        #expect(BestTimeOfDay.hourLabel(12) == "noon")
        #expect(BestTimeOfDay.hourLabel(7) == "7 am")
        #expect(BestTimeOfDay.hourLabel(21) == "9 pm")
        #expect(BestTimeOfDay.windowText(startHour: 19, endHour: 21) == "7 to 9 pm")
        #expect(BestTimeOfDay.windowText(startHour: 7, endHour: 9) == "7 to 9 am")
        #expect(BestTimeOfDay.windowText(startHour: 23, endHour: 1) == "11 pm to 1 am")
        #expect(BestTimeOfDay.windowText(startHour: 11, endHour: 13) == "11 am to 1 pm")
        #expect(BestTimeOfDay.windowText(startHour: 12, endHour: 14) == "noon to 2 pm")
    }
}

// MARK: - Speed trend

struct InsightsSpeedTrendTests {
    let fx = InsightsFixture()

    func trend(days: Int = 150, kind: SessionKind = .timed, inLibrary: Bool = true, maxPoints: Int = 90, wpm: @escaping (Int) -> Double) -> SpeedTrend {
        // A small wobble so the line is never perfectly clean.
        let sessions = fx.reader(
            offsets: (1...days).reversed().map { -$0 }, kind: kind,
            hour: { _ in 20 }, minutes: { _ in 30 }, wpm: { wpm($0) + Double(($0 * 37) % 9 - 4) * 2 }
        )
        let items = inLibrary ? [fx.item("b", pages: 100_000)] : []
        return fx.engine(fx.data(items: items, sessions: sessions)).speedTrend(maxPoints: maxPoints)
    }

    @Test func noDataIsNotEnoughData() {
        let result = fx.engine(fx.data()).speedTrend()
        #expect(result.label == .notEnoughData)
        #expect(result.points.isEmpty)
        #expect(result.sampleCount == 0)
        #expect(result.currentWPM == nil)
        #expect(!result.sentence.isEmpty)
    }

    @Test func aReaderGettingFasterIsFaster() {
        let result = trend { 200 + 100 * Double($0) / 150 }
        #expect(result.label == .faster)
        // 100 wpm over five months is about 20 a month.
        #expect(result.slopePerMonth > 14 && result.slopePerMonth < 26)
        #expect(result.sentence.contains("faster"))
        #expect((result.currentWPM ?? 0) > 270)
    }

    @Test func aReaderSlowingDownIsSlowerWithoutGuilt() {
        let result = trend { 300 - 90 * Double($0) / 150 }
        #expect(result.label == .slower)
        #expect(result.slopePerMonth < -10)
        #expect(!result.sentence.contains("!"))
    }

    @Test func aFlatReaderIsSteady() {
        let result = trend { _ in 250 }
        #expect(result.label == .steady)
        #expect(abs(result.slopePerMonth) < 3)
        #expect(result.sentence.contains("steady"))
    }

    @Test func tooFewSittingsOrTooShortASpanIsNotEnough() {
        #expect(trend(days: 7) { _ in 250 }.label == .notEnoughData)
        // Plenty of sittings but all within two weeks.
        let sessions = (0..<20).map { fx.session("b", at: fx.day(-1 - $0 / 3, hour: 8 + $0 % 3), minutes: 30, pages: 30) }
        let result = fx.engine(fx.data(items: [fx.item("b", pages: 100_000)], sessions: sessions)).speedTrend()
        #expect(result.label == .notEnoughData)
    }

    @Test func typedInSessionsAndRemovedBooksAreLeftOut() {
        #expect(trend(kind: .manual) { _ in 250 }.sampleCount == 0)
        #expect(trend(inLibrary: false) { _ in 250 }.sampleCount == 0)
    }

    @Test func pointsAreOrderedBoundedAndThinned() {
        let result = trend(days: 400, maxPoints: 50) { 220 + Double($0 % 60) }
        #expect(result.points.count == 50)
        #expect(zip(result.points, result.points.dropFirst()).allSatisfy { $0.date <= $1.date })
        #expect(result.points.last?.wpm == result.currentWPM)
        let low = result.points.map(\.sessionWPM).min() ?? 0
        let high = result.points.map(\.sessionWPM).max() ?? 0
        #expect(result.points.allSatisfy { $0.wpm >= low - 1 && $0.wpm <= high + 1 })
        #expect(trend(days: 60, maxPoints: 1000) { _ in 250 }.points.count == 58)
        #expect(trend(days: 60, maxPoints: 0) { _ in 250 }.points.isEmpty)
    }

    @Test func onlyTheLastYearDecidesTheLabel() {
        // Slow growth long ago, flat for the last year.
        let old = fx.reader(offsets: (400...700).reversed().map { -$0 }, hour: { _ in 20 }, minutes: { _ in 30 }, wpm: { 180 + Double($0) * 0.2 })
        let recent = fx.reader(offsets: (1...300).reversed().map { -$0 }, hour: { _ in 20 }, minutes: { _ in 30 }, wpm: { _ in 260 })
        let engine = fx.engine(fx.data(items: [fx.item("b", pages: 100_000)], sessions: old + recent))
        #expect(engine.speedTrend().label == .steady)
    }
}

// MARK: - Genre and length mix

struct InsightsMixTests {
    let fx = InsightsFixture()

    @Test func emptyLibraryHasNoMix() {
        let engine = fx.engine(fx.data())
        #expect(engine.genreMix().isEmpty)
        #expect(engine.lengthMix().isEmpty)
    }

    @Test func genreSharesAddUpToOneAndSortBiggestFirst() {
        let items = [
            fx.item("a", shelf: .finished, genres: ["fantasy"]),
            fx.item("b", shelf: .finished, genres: ["fantasy", "young-adult"]),
            fx.item("c", shelf: .finished, genres: ["mystery"]),
            fx.item("d", shelf: .finished, genres: []),
            fx.item("e", shelf: .reading, genres: ["poetry"]),
            fx.item("f", shelf: .paused, genres: ["poetry"]),
            fx.item("g", shelf: .toRead, genres: ["poetry"]),
        ]
        let mix = fx.engine(fx.data(items: items)).genreMix()
        let mixTotal: Double = mix.map(\.share).reduce(0, +)
        #expect(abs(mixTotal - 1) < 1e-9)
        #expect(mix.map(\.tag) == ["fantasy", "mystery", "other", "young-adult"])
        #expect(abs(mix[0].share - 0.375) < 1e-9)
        #expect(mix[0].books == 2)
        #expect(mix.first { $0.tag == "young-adult" }?.name == "young adult")
        #expect(!mix.contains { $0.tag == "poetry" })
    }

    @Test func repeatedGenreTagsCountOnce() {
        let items = [fx.item("a", shelf: .finished, genres: ["fantasy", "fantasy"])]
        let mix = fx.engine(fx.data(items: items)).genreMix()
        #expect(mix.count == 1 && mix[0].share == 1 && mix[0].books == 1)
    }

    @Test func genreMixCanLookAtOneYear() {
        let items = [
            fx.item("a", shelf: .finished, genres: ["fantasy"], finished: fx.date(2025, 6, 1)),
            fx.item("b", shelf: .finished, genres: ["mystery"], finished: fx.date(2026, 6, 1)),
            fx.item("c", shelf: .finished, genres: ["mystery"], finished: fx.date(2026, 7, 1)),
        ]
        let engine = fx.engine(fx.data(items: items))
        #expect(engine.genreMix(year: 2026).map(\.tag) == ["mystery"])
        #expect(engine.genreMix(year: 2025).map(\.tag) == ["fantasy"])
        #expect(engine.genreMix(year: 2024).isEmpty)
        #expect(engine.genreMix().count == 2)
    }

    @Test func tiesBreakByNameSoOrderIsStable() {
        let items = ["zeta", "alpha", "mid"].enumerated().map { fx.item("\($0.offset)", shelf: .finished, genres: [$0.element]) }
        #expect(fx.engine(fx.data(items: items)).genreMix().map(\.tag) == ["alpha", "mid", "zeta"])
        #expect(fx.engine(fx.data(items: items.reversed())).genreMix().map(\.tag) == ["alpha", "mid", "zeta"])
    }

    @Test func lengthBandsFollowTheReadersPace() {
        // At 270 wpm: 6 hours is 97,200 words and 14 hours is 226,800.
        func finished(_ id: String, words: Int) -> LibraryItem {
            LibraryItem(book: Book(id: id, title: id, author: "A", pages: 300, words: words), shelf: .finished, currentPage: 300, order: 0, finishedAt: fx.day(-1))
        }
        let items = [finished("s1", words: 50_000), finished("s2", words: 97_000), finished("m", words: 120_000), finished("l", words: 300_000)]
        let slow = fx.data(items: items) { $0.wpm = 270 }
        let mix = fx.engine(slow).lengthMix()
        #expect(mix.map(\.band) == [.short, .medium, .long])
        #expect(mix.map(\.books) == [2, 1, 1])
        let mixTotal: Double = mix.map(\.share).reduce(0, +)
        #expect(abs(mixTotal - 1) < 1e-9)
        #expect(mix[0].label == "short reads")
        // A faster reader finds the same books shorter.
        let quick = fx.data(items: items) { $0.wpm = 600 }
        #expect(fx.engine(quick).lengthMix().map(\.books) == [3, 1, 0])
    }

    @Test func lengthMixIgnoresBooksThatAreNotFinished() {
        let items = [fx.item("a", shelf: .finished), fx.item("b", shelf: .reading), fx.item("c", shelf: .toRead)]
        let mix = fx.engine(fx.data(items: items)).lengthMix()
        #expect(mix.map(\.books).reduce(0, +) == 1)
    }
}

// MARK: - TBR depth

struct InsightsTBRTests {
    let fx = InsightsFixture()

    /// 81,000 words at 270 wpm is exactly 300 minutes.
    func queue(_ count: Int) -> [LibraryItem] {
        (0..<count).map { index in
            LibraryItem(book: Book(id: "q\(index)", title: "Q\(index)", author: "A", pages: 300, words: 81_000), shelf: .toRead, order: Double(index))
        }
    }

    func data(items: [LibraryItem], sessions: [ReadingSession] = [], minutes: Int = 30, days: Set<Int> = Set(1...7)) -> LeafData {
        fx.data(items: items, sessions: sessions) { prefs in
            prefs.wpm = 270
            prefs.dailyMinutes = minutes
            prefs.readingDays = days
        }
    }

    @Test func emptyQueueIsEmpty() {
        let depth = fx.engine(data(items: [])).tbrDepth()
        #expect(depth.queueBooks == 0)
        #expect(depth.months == 0)
        #expect(depth.sentence == "Your To read pile is empty.")
    }

    @Test func depthComesFromTheGoalBeforeThereIsHistory() throws {
        // Ten books of 300 minutes at 30 minutes a day is 100 days.
        let depth = fx.engine(data(items: queue(10))).tbrDepth()
        #expect(depth.basis == .goal)
        #expect(abs(depth.queueMinutes - 3000) < 1e-6)
        #expect(abs(depth.minutesPerDay - 30) < 1e-9)
        let months = try #require(depth.months)
        #expect(abs(months - 100 / 30.4375) < 1e-6)
        #expect(depth.sentence == "Your TBR is 3 months deep at this pace.")
    }

    @Test func restDaysSlowTheGoalPace() throws {
        let depth = fx.engine(data(items: queue(10), days: [2, 3, 4, 5, 6])).tbrDepth()
        #expect(abs(depth.minutesPerDay - 30 * 5 / 7) < 1e-9)
        let months = try #require(depth.months)
        #expect(months > 100 / 30.4375)
    }

    @Test func noDailyTimeMeansNoEstimate() {
        let depth = fx.engine(data(items: queue(3), minutes: 0)).tbrDepth()
        #expect(depth.months == nil)
        #expect(depth.sentence.contains("Set a daily reading time"))
    }

    @Test func realRecentPaceTakesOverOnceThereIsHistory() throws {
        // Twenty read days in the last 28, an hour each: 1,200 minutes over 28 days.
        let offsets = (1...28).filter { $0 % 7 != 0 && $0 % 7 != 3 }.map { -$0 }
        let sessions = offsets.map { fx.session("x", at: fx.day($0), minutes: 60, pages: 60) }
        let depth = fx.engine(data(items: queue(10), sessions: sessions)).tbrDepth()
        #expect(depth.basis == .recent)
        #expect(abs(depth.minutesPerDay - Double(offsets.count) * 60 / 28) < 1e-9)
        let months = try #require(depth.months)
        #expect(abs(months - 3000 / depth.minutesPerDay / 30.4375) < 1e-9)
    }

    @Test func aFewSessionsAreNotEnoughToOverrideTheGoal() {
        let sessions = [-1, -2, -20].map { fx.session("x", at: fx.day($0), minutes: 90, pages: 60) }
        #expect(fx.engine(data(items: queue(5), sessions: sessions)).tbrDepth().basis == .goal)
    }

    @Test func pausedAndReadingBooksAreInProgressNotInTheQueue() {
        let items = queue(2) + [fx.item("r", shelf: .reading, page: 150), fx.item("p", shelf: .paused, page: 0)]
        let depth = fx.engine(data(items: items)).tbrDepth()
        #expect(depth.queueBooks == 2)
        #expect(depth.inProgressBooks == 2)
        #expect(depth.inProgressMinutes > 0)
        #expect(abs(depth.queueMinutes - 600) < 1e-6)
    }

    @Test func phrasesReadNaturally() {
        #expect(TBRDepth.phrase(months: 0.2) == "under a month")
        #expect(TBRDepth.phrase(months: 1) == "about a month")
        #expect(TBRDepth.phrase(months: 14.2) == "14 months")
        #expect(TBRDepth.phrase(months: 23.4) == "23 months")
        #expect(TBRDepth.phrase(months: 24) == "2 years")
        #expect(TBRDepth.phrase(months: 30) == "2.5 years")
    }

    @Test func hugeQueuesStayFinite() throws {
        let depth = fx.engine(data(items: queue(2000), minutes: 1)).tbrDepth()
        let months = try #require(depth.months)
        #expect(months.isFinite && months > 100)
        #expect(depth.sentence.hasSuffix("at this pace."))
    }
}

// MARK: - Year goal pacing

struct InsightsPacingTests {
    let fx = InsightsFixture()

    func finishedItems(_ count: Int, year: Int = 2026) -> [LibraryItem] {
        (0..<count).map { fx.item("f\($0)", shelf: .finished, finished: fx.date(year, 1 + $0 % 9, 3)) }
    }

    func pacing(goal: Int?, finished: Int, now: Date? = nil) -> YearGoalPacing {
        fx.engine(fx.data(items: finishedItems(finished)) { $0.yearlyGoal = goal }, now: now).yearGoalPacing()
    }

    @Test func noGoalIsSaidPlainly() {
        let result = pacing(goal: nil, finished: 5)
        #expect(result.status == .noGoal && result.goal == nil)
        #expect(result.finished == 5)
        #expect(pacing(goal: 0, finished: 1).status == .noGoal)
    }

    @Test func aheadOfAStraightLine() {
        // Oct 18 is day 291 of 365: a steady reader with a goal of 24 would have 19.1 books.
        let result = pacing(goal: 24, finished: 22)
        #expect(abs(result.expectedByToday - 24 * 291 / 365) < 1e-9)
        #expect(result.status == .ahead)
        #expect(result.booksAheadOrBehind == 3)
        #expect(result.remaining == 2)
        #expect(result.daysLeft == 74)
        #expect(abs(result.booksPerMonthNeeded - 2 / (75.0 / 365 * 12)) < 1e-9)
    }

    @Test func behindAndOnTrack() {
        #expect(pacing(goal: 24, finished: 15).status == .behind)
        #expect(pacing(goal: 24, finished: 15).booksAheadOrBehind == -4)
        #expect(pacing(goal: 24, finished: 19).status == .onTrack)
        #expect(pacing(goal: 24, finished: 19).booksAheadOrBehind == 0)
    }

    @Test func reachingTheGoalEndsTheMath() {
        let done = pacing(goal: 5, finished: 5)
        #expect(done.status == .reached && done.remaining == 0 && done.booksPerMonthNeeded == 0)
        let over = pacing(goal: 3, finished: 5)
        #expect(over.status == .reached && over.remaining == 0)
    }

    @Test func onlyThisYearsFinishesCount() {
        let items = finishedItems(4, year: 2025) + finishedItems(2, year: 2026)
        let result = fx.engine(fx.data(items: items) { $0.yearlyGoal = 12 }).yearGoalPacing()
        #expect(result.finished == 2)
        #expect(result.year == 2026)
    }

    @Test func leapYearsUseTheirOwnLength() {
        let now = fx.date(2028, 12, 31, 12)
        let result = fx.engine(fx.data { $0.yearlyGoal = 12 }, now: now).yearGoalPacing()
        #expect(result.daysLeft == 0)
        #expect(abs(result.expectedByToday - 12) < 1e-9)
        let leapDay = fx.engine(fx.data { $0.yearlyGoal = 366 }, now: fx.date(2028, 2, 29, 9)).yearGoalPacing()
        #expect(abs(leapDay.expectedByToday - 366 * 60 / 366) < 1e-9)
    }

    @Test func theLastAndFirstDaysStayFinite() {
        let lastDay = pacing(goal: 24, finished: 10, now: fx.date(2026, 12, 31, 9))
        #expect(lastDay.booksPerMonthNeeded.isFinite && lastDay.booksPerMonthNeeded > 0)
        #expect(lastDay.status == .behind)
        let firstDay = fx.engine(fx.data { $0.yearlyGoal = 24 }, now: fx.date(2026, 1, 1, 9)).yearGoalPacing()
        #expect(firstDay.status == .onTrack)
        #expect(firstDay.straightLineProjection.isFinite)
        #expect(firstDay.booksPerMonthSoFar == 0)
    }

    @Test func paceSoFarAndProjection() {
        let result = pacing(goal: 24, finished: 12)
        #expect(abs(result.booksPerMonthSoFar - 12 / (291.0 / 365 * 12)) < 1e-9)
        #expect(abs(result.straightLineProjection - 12 / (291.0 / 365)) < 1e-9)
    }
}

// MARK: - Personality

struct InsightsPersonalityTests {
    let fx = InsightsFixture()

    var sixty: [Int] { (1...60).reversed().map { -$0 } }

    /// A modest library that triggers none of the library-based archetypes.
    var quietLibrary: [LibraryItem] {
        [fx.item("b", pages: 100_000), fx.item("f1", shelf: .finished, genres: ["fantasy"]), fx.item("f2", shelf: .finished, genres: ["mystery"])]
    }

    func personality(items: [LibraryItem]? = nil, sessions: [ReadingSession], _ prefs: (inout ReadingPreferences) -> Void = { _ in }) -> ReadingPersonality {
        fx.engine(fx.data(items: items ?? quietLibrary, sessions: sessions, prefs)).personality()
    }

    let spread = [7, 12, 15, 17, 20, 23]

    @Test func emptyAndTinyHistoriesGetAGentleDefault() {
        let empty = fx.engine(fx.data()).personality()
        #expect(empty.archetype == .freshPage && empty.isDefault && empty.score == 0)
        #expect(!empty.blurb.isEmpty && !empty.evidence.isEmpty)
        let few = personality(sessions: fx.reader(offsets: [-5, -4, -3, -2, -1], hour: { _ in 20 }, minutes: { _ in 30 }))
        #expect(few.archetype == .freshPage)
    }

    @Test func eveningSteeper() {
        let result = personality(sessions: fx.reader(offsets: sixty, hour: { _ in 20 }, minutes: { _ in 30 }))
        #expect(result.archetype == .eveningSteeper)
        #expect(result.title == "The Evening Steeper")
        #expect(!result.isDefault && result.score > 0.9)
        #expect(result.evidence.first?.value == 1)
        #expect(result.runnerUp == .steadySipper)
    }

    @Test func earlyBird() {
        #expect(personality(sessions: fx.reader(offsets: sixty, hour: { _ in 6 }, minutes: { _ in 30 })).archetype == .earlyBird)
    }

    @Test func nightOwl() {
        #expect(personality(sessions: fx.reader(offsets: sixty, hour: { _ in 23 }, minutes: { _ in 30 })).archetype == .nightOwl)
    }

    @Test func lunchBreakReader() {
        #expect(personality(sessions: fx.reader(offsets: sixty, hour: { _ in 12 }, minutes: { _ in 20 })).archetype == .lunchBreakReader)
    }

    @Test func teatimeRegular() {
        let sessions = fx.reader(offsets: sixty, hour: { _ in 16 }, minutes: { _ in 20 })
        #expect(personality(sessions: sessions).archetype == .teatimeRegular)
    }

    @Test func weekendBinger() {
        // Ninety minutes on Saturdays and Sundays at changing hours, ten on a couple of weekdays.
        let weekendOffsets = sixty.filter { [1, 7].contains(fx.calendar.component(.weekday, from: fx.day($0))) }
        let weekdayOffsets = sixty.filter { [3, 5].contains(fx.calendar.component(.weekday, from: fx.day($0))) }
        let hours = [9, 13, 19, 22]
        let sessions = fx.reader(offsets: weekendOffsets, hour: { hours[$0 % 4] }, minutes: { _ in 90 })
            + fx.reader(offsets: weekdayOffsets, hour: { hours[$0 % 4] }, minutes: { _ in 10 })
        let result = personality(sessions: sessions) { $0.readingDays = [1, 7] }
        #expect(result.archetype == .weekendBinger)
        #expect(result.evidence.first?.value ?? 0 > 0.8)
    }

    @Test func steadySipper() {
        let sessions = fx.reader(offsets: sixty, hour: { spread[$0 % 6] }, minutes: { _ in 25 })
        let result = personality(sessions: sessions)
        #expect(result.archetype == .steadySipper)
        #expect(result.evidence.contains { $0.key == "adherence" && $0.value > 0.95 })
    }

    @Test func marathoner() {
        let days: Set<Int> = [2, 4, 6]
        let offsets = sixty.filter { days.contains(fx.calendar.component(.weekday, from: fx.day($0))) }
        let hours = [9, 13, 19, 22]
        let result = personality(sessions: fx.reader(offsets: offsets, hour: { hours[$0 % 4] }, minutes: { _ in 90 })) { $0.readingDays = days }
        #expect(result.archetype == .marathoner)
    }

    @Test func nibbler() {
        let sessions = sixty.flatMap { offset in
            (0..<3).map { part in fx.session("b", at: fx.day(offset, hour: [8, 13, 21][part]), minutes: 8, pages: 8) }
        }
        #expect(personality(sessions: sessions).archetype == .nibbler)
    }

    @Test func samplerHasManyBooksOpenAndFewFinished() {
        let items = [fx.item("a", shelf: .finished)]
            + (0..<3).map { fx.item("r\($0)", shelf: .reading, page: 40) }
            + (0..<3).map { fx.item("p\($0)", shelf: .paused, page: 40) }
        let result = personality(items: items, sessions: [])
        #expect(result.archetype == .sampler)
        #expect(result.evidence.contains { $0.key == "open" && $0.value == 6 })
    }

    @Test func completionistFinishesWhatTheyStart() {
        let items = (0..<8).map { fx.item("f\($0)", shelf: .finished, genres: $0 % 2 == 0 ? ["fantasy"] : ["mystery"]) } + [fx.item("r", shelf: .reading)]
        #expect(personality(items: items, sessions: []).archetype == .completionist)
    }

    @Test func wandererReadsEverything() {
        let genres = ["fantasy", "mystery", "history", "romance", "science-fiction", "poetry", "fantasy", "mystery"]
        let items = genres.enumerated().map { fx.item("f\($0.offset)", shelf: .finished, genres: [$0.element]) }
            + [fx.item("r1", shelf: .reading), fx.item("r2", shelf: .reading), fx.item("p1", shelf: .paused)]
        #expect(personality(items: items, sessions: []).archetype == .wanderer)
    }

    @Test func genreLoyalistKeepsReturningToOneShelf() {
        let items = (0..<7).map { fx.item("f\($0)", shelf: .finished, genres: ["fantasy"]) } + [fx.item("m", shelf: .finished, genres: ["mystery"])]
            + [fx.item("r1", shelf: .reading), fx.item("r2", shelf: .reading), fx.item("p1", shelf: .paused)]
        let result = personality(items: items, sessions: [])
        #expect(result.archetype == .genreLoyalist)
        #expect(result.evidence.first?.text.contains("fantasy") == true)
    }

    @Test func plentyOfHistoryButNoPatternIsTheCozyReader() {
        // Every third day, lengths and hours all over the place.
        let offsets = sixty.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        let lengths = [10.0, 25, 45]
        let result = personality(sessions: fx.reader(offsets: offsets, hour: { self.spread[$0 % 6] }, minutes: { lengths[$0 % 3] }))
        #expect(result.archetype == .cozyReader)
        #expect(result.isDefault && result.score == 0)
    }

    @Test func thereAreAtLeastEightRealArchetypesEachWithCopy() {
        let real = ReadingPersonality.Archetype.allCases.filter { $0 != .cozyReader && $0 != .freshPage }
        #expect(real.count >= 8)
        for archetype in ReadingPersonality.Archetype.allCases {
            #expect(archetype.title.hasPrefix("The "))
            #expect(archetype.blurb.hasSuffix("."))
            #expect(!archetype.blurb.contains("!"))
            #expect(archetype.blurb.components(separatedBy: ". ").count == 1)
        }
        #expect(Set(ReadingPersonality.Archetype.allCases.map(\.title)).count == ReadingPersonality.Archetype.allCases.count)
    }

    @Test func theAnswerDoesNotDependOnInputOrder() {
        let sessions = fx.reader(offsets: sixty, hour: { _ in 20 }, minutes: { _ in 30 })
        let one = personality(sessions: sessions)
        let two = personality(items: quietLibrary.reversed(), sessions: sessions.reversed())
        #expect(one == two)
    }

    @Test func scoresStayInRangeForRandomReaders() {
        var rng = SeededGenerator(seed: 99)
        for _ in 0..<25 {
            let offsets = sixty.filter { _ in rng.unit() < 0.5 }
            let sessions = fx.reader(offsets: offsets, hour: { _ in Int(rng.unit() * 24) }, minutes: { _ in 3 + rng.unit() * 120 })
            let result = personality(sessions: sessions)
            #expect(result.score >= 0 && result.score <= 1)
            #expect(!result.evidence.isEmpty)
            #expect(result.isDefault == (result.score == 0))
        }
    }

    @Test func oldHistoryFadesFromTheArchetype() {
        // Two years ago an early bird; for the last year an evening reader.
        let old = fx.reader(offsets: (400...460).reversed().map { -$0 }, hour: { _ in 6 }, minutes: { _ in 30 })
        let recent = fx.reader(offsets: sixty, hour: { _ in 20 }, minutes: { _ in 30 })
        #expect(personality(sessions: old + recent).archetype == .eveningSteeper)
    }
}

// MARK: - Year in books

struct InsightsYearTests {
    let fx = InsightsFixture()

    @Test func anEmptyYearIsEmptyButWellFormed() {
        let year = fx.engine(fx.data()).yearInBooks(year: 2026)
        #expect(year.isEmpty)
        #expect(year.booksFinished == 0 && year.pages == 0 && year.minutes == 0 && year.cups == 0)
        #expect(year.months.count == 12)
        #expect(year.months.map(\.month) == Array(1...12))
        #expect(year.months.allSatisfy { $0.ring == 0 })
        #expect(year.longestBook == nil && year.firstFinished == nil && year.topGenre == nil && year.topAuthor == nil)
        #expect(year.averageRating == nil && year.busiestMonth == nil && year.favouriteHour == nil)
        #expect(year.longestStreak == 0)
    }

    /// Three books finished in 2026, one in 2025, one marked finished with no sessions at all.
    func busyYear() -> LeafData {
        let items = [
            fx.item("hobbit", shelf: .finished, pages: 300, genres: ["fantasy"], author: "J. R. R. Tolkien", started: fx.date(2026, 2, 1), finished: fx.date(2026, 2, 10, 22), rating: 5),
            fx.item("fellowship", shelf: .finished, pages: 600, genres: ["fantasy", "adventure"], author: "J.R.R. Tolkien", started: fx.date(2026, 3, 1), finished: fx.date(2026, 3, 20, 21), rating: 4),
            fx.item("tiny", shelf: .finished, pages: 100, genres: ["poetry"], author: "Pat Poet", started: fx.date(2026, 6, 4), finished: fx.date(2026, 6, 4, 22)),
            fx.item("marked", shelf: .finished, pages: 250, genres: ["mystery"], author: "Mo Mystery", finished: fx.date(2026, 8, 8)),
            fx.item("old", shelf: .finished, pages: 200, genres: ["history"], finished: fx.date(2025, 12, 30)),
            fx.item("paused", shelf: .paused, pages: 400, page: 100),
        ]
        var sessions: [ReadingSession] = []
        // The Hobbit: 10 days, 30 pages a day at 20:00, 30 minutes each.
        for d in 1...10 { sessions.append(fx.session("hobbit", at: fx.date(2026, 2, d, 20), minutes: 30, pages: 30, from: (d - 1) * 30)) }
        // The Fellowship: 20 days of 30 pages at 21:00, 45 minutes each.
        for d in 1...20 { sessions.append(fx.session("fellowship", at: fx.date(2026, 3, d, 21), minutes: 45, pages: 30, from: (d - 1) * 30)) }
        // A one-day read of the tiny book.
        sessions.append(fx.session("tiny", at: fx.date(2026, 6, 4, 19), minutes: 60, pages: 100))
        // A book that has since been removed, and last year's reading.
        sessions.append(fx.session("removed", at: fx.date(2026, 9, 1, 8), minutes: 25, pages: 25))
        sessions.append(fx.session("old", at: fx.date(2025, 12, 29, 20), minutes: 90, pages: 80))
        let journal = [
            fx.entry("hobbit", "In a hole in the ground", page: 1, at: fx.date(2026, 2, 2)),
            fx.entry("hobbit", kind: .thought, "Cosy", page: 5, at: fx.date(2026, 2, 3)),
            fx.entry("fellowship", "Not all those who wander are lost", page: 90, at: fx.date(2026, 3, 5)),
            fx.entry("old", "Last year", at: fx.date(2025, 5, 5)),
        ]
        return fx.data(items: items, sessions: sessions, journal: journal)
    }

    @Test func totalsForABusyYear() {
        let year = fx.engine(busyYear()).yearInBooks(year: 2026)
        #expect(year.booksFinished == 4)
        // 10 x 30 + 20 x 30 + 100 + 25 pages from sessions, plus the 250 pages of the book marked finished.
        #expect(year.pages == 300 + 600 + 100 + 25 + 250)
        // 300 + 900 + 60 + 25 minutes, with the removed book's session included.
        #expect(abs(year.minutes - 1285) < 1e-9)
        #expect(year.cups == 51)
        #expect(year.pots == 12)
        #expect(year.cupMinutes == 25)
        #expect(year.sessionCount == 32)
        #expect(year.daysRead == 32)
        #expect(year.quotesSaved == 2)
        #expect(year.notesSaved == 1)
        #expect(!year.isEmpty)
    }

    @Test func favouritesAndExtremes() {
        let year = fx.engine(busyYear()).yearInBooks(year: 2026)
        #expect(year.longestBook?.bookID == "fellowship")
        #expect(year.shortestBook?.bookID == "tiny")
        #expect(year.firstFinished?.bookID == "hobbit")
        #expect(year.lastFinished?.bookID == "marked")
        #expect(year.finishedBooks.map(\.bookID) == ["hobbit", "fellowship", "tiny", "marked"])
        // The tiny book took one day at 100 pages a day; the marked book has no known start.
        #expect(year.fastestBook?.bookID == "tiny")
        #expect(year.fastestBook?.days == 1)
        #expect(year.finishedBooks.first { $0.bookID == "marked" }?.days == nil)
        #expect(year.topAuthor?.name == "J. R. R. Tolkien" || year.topAuthor?.name == "J.R.R. Tolkien")
        #expect(year.topAuthor?.books == 2 && year.topAuthor?.pages == 900)
        #expect(year.topGenre?.tag == "fantasy")
        #expect(year.topGenre?.books == 2)
        #expect(abs((year.averageRating ?? 0) - 4.5) < 1e-9)
        #expect(year.ratedBooks == 2)
        #expect(year.busiestMonth == 3)
        // 21:00 holds 900 timed minutes against 300 at 20:00.
        #expect(year.favouriteHour == 21)
    }

    @Test func monthRingsFormACollage() {
        let year = fx.engine(busyYear()).yearInBooks(year: 2026)
        let monthTotal: Double = year.months.map(\.minutes).reduce(0, +)
        #expect(abs(monthTotal - year.minutes) < 1e-9)
        let monthly: Int = year.months.reduce(0) { $0 + $1.booksFinished }
        #expect(monthly == year.booksFinished)
        #expect(year.months[2].ring == 1)
        #expect(year.months[0].ring == 0 && year.months[3].ring == 0)
        #expect(year.months.allSatisfy { $0.ring == 0 || ($0.ring >= 0.1 && $0.ring <= 1) })
        #expect(year.months[1].ring > 0 && year.months[1].ring < 1)
        #expect(year.months[1].cups == 12)
    }

    @Test func longestStreakStaysWithinTheYear() {
        let year = fx.engine(busyYear()).yearInBooks(year: 2026)
        // Feb 1 to Feb 10 is ten days; Mar 1 to Mar 20 is twenty.
        #expect(year.longestStreak == 20)
        #expect(fx.engine(busyYear()).yearInBooks(year: 2025).longestStreak == 1)
    }

    @Test func eachYearOwnsItsOwnReading() {
        let engine = fx.engine(busyYear())
        let last = engine.yearInBooks(year: 2025)
        #expect(last.booksFinished == 1)
        #expect(last.minutes == 90)
        #expect(last.pages == 80)
        #expect(last.quotesSaved == 1)
        #expect(engine.yearInBooks(year: 2024).isEmpty)
    }

    @Test func cupsFollowTheReadersCupLength() {
        let data = fx.data(sessions: [fx.session("b", at: fx.day(-1), minutes: 100, pages: 10)]) { $0.cupMinutes = 20 }
        let year = fx.engine(data).yearInBooks(year: 2026)
        #expect(year.cups == 5 && year.pots == 1 && year.cupMinutes == 20)
        let bad = fx.data(sessions: [fx.session("b", at: fx.day(-1), minutes: 100, pages: 10)]) { $0.cupMinutes = 0 }
        #expect(fx.engine(bad).yearInBooks(year: 2026).cups == 100)
    }

    @Test func leapDayLandsInFebruary() {
        let sessions = [
            fx.session("b", at: fx.date(2028, 2, 29, 9), minutes: 30, pages: 20),
            fx.session("b", at: fx.date(2028, 3, 1, 9), minutes: 10, pages: 5),
        ]
        let year = fx.engine(fx.data(sessions: sessions), now: fx.date(2028, 6, 1)).yearInBooks(year: 2028)
        #expect(year.months[1].minutes == 30 && year.months[2].minutes == 10)
        #expect(year.longestStreak == 2)
    }

    @Test func newYearsEveAndDayStayApart() {
        let items = [fx.item("a", shelf: .finished, finished: fx.date(2026, 12, 31, 23, 59)), fx.item("b2", shelf: .finished, finished: fx.date(2027, 1, 1, 0, 1))]
        let sessions = [fx.session("a", at: fx.date(2026, 12, 31, 23, 30), minutes: 20, pages: 20), fx.session("b2", at: fx.date(2027, 1, 1, 0, 30), minutes: 10, pages: 10)]
        let engine = fx.engine(fx.data(items: items, sessions: sessions), now: fx.date(2027, 6, 1))
        #expect(engine.yearInBooks(year: 2026).booksFinished == 1)
        #expect(engine.yearInBooks(year: 2026).minutes == 20)
        #expect(engine.yearInBooks(year: 2027).booksFinished == 1)
        #expect(engine.yearInBooks(year: 2027).minutes == 10)
        #expect(engine.yearInBooks(year: 2026).months[11].booksFinished == 1)
    }

    @Test func aBookFinishedBeforeMidnightHereCanBeNextYearElsewhere() {
        // 23:30 on New Year's Eve in New York is already January in Tokyo.
        let finished = fx.date(2026, 12, 31, 23, 30)
        let data = fx.data(items: [fx.item("a", shelf: .finished, finished: finished)])
        let tokyo = InsightsFixture(timeZone: "Asia/Tokyo")
        let later = fx.date(2027, 6, 1)
        #expect(InsightsEngine(data: data, now: later, calendar: fx.calendar).yearInBooks(year: 2026).booksFinished == 1)
        #expect(InsightsEngine(data: data, now: later, calendar: tokyo.calendar).yearInBooks(year: 2026).booksFinished == 0)
        #expect(InsightsEngine(data: data, now: later, calendar: tokyo.calendar).yearInBooks(year: 2027).booksFinished == 1)
    }

    @Test func unratedAndOutOfRangeRatingsAreIgnored() {
        let items = [
            fx.item("a", shelf: .finished, finished: fx.date(2026, 4, 1), rating: 3),
            fx.item("b2", shelf: .finished, finished: fx.date(2026, 4, 2), rating: 9),
            fx.item("c", shelf: .finished, finished: fx.date(2026, 4, 3)),
        ]
        let year = fx.engine(fx.data(items: items)).yearInBooks(year: 2026)
        #expect(year.averageRating == 3 && year.ratedBooks == 1)
    }

    @Test func booksMarkedFinishedAddPagesButNeverTime() {
        let items = [fx.item("a", shelf: .finished, pages: 321, finished: fx.date(2026, 4, 1))]
        let year = fx.engine(fx.data(items: items)).yearInBooks(year: 2026)
        #expect(year.pages == 321 && year.minutes == 0 && year.booksFinished == 1)
        #expect(!year.isEmpty)
        #expect(year.favouriteHour == nil)
    }

    @Test func pausedAndUnfinishedBooksNeverCountAsFinished() {
        let items = [fx.item("a", shelf: .paused, page: 200), fx.item("b2", shelf: .reading, page: 300), fx.item("c", shelf: .toRead)]
        #expect(fx.engine(fx.data(items: items)).yearInBooks(year: 2026).booksFinished == 0)
    }

    @Test func aFinishedBookWithoutADateBelongsToNoYear() {
        var item = fx.item("a", shelf: .finished)
        item.finishedAt = nil
        let engine = fx.engine(fx.data(items: [item]))
        #expect(engine.yearInBooks(year: 2026).booksFinished == 0)
        #expect(engine.genreMix().count == 1)
    }

    @Test func sameDataSameYear() {
        let data = busyYear()
        var shuffled = data
        shuffled.items.reverse()
        shuffled.sessions.reverse()
        shuffled.journal.reverse()
        #expect(fx.engine(data).yearInBooks(year: 2026) == fx.engine(shuffled).yearInBooks(year: 2026))
    }
}

// MARK: - Weekly letter

struct InsightsWeeklyLetterTests {
    let fx = InsightsFixture()

    /// The week ending Sunday Oct 18 runs Monday Oct 12 to Sunday Oct 18; the one before runs Oct 5 to Oct 11.
    func thisWeek() -> LeafData {
        let items = [
            fx.item("a", shelf: .finished, pages: 200, finished: fx.date(2026, 10, 16, 21)),
            fx.item("b", shelf: .reading, pages: 400, page: 100),
        ]
        var sessions: [ReadingSession] = []
        sessions.append(fx.session("a", at: fx.date(2026, 10, 12, 20), minutes: 30, pages: 30))
        sessions.append(fx.session("a", at: fx.date(2026, 10, 14, 20), minutes: 50, pages: 50))
        sessions.append(fx.session("b", at: fx.date(2026, 10, 14, 22), minutes: 20, pages: 20))
        sessions.append(fx.session("a", at: fx.date(2026, 10, 16, 20), minutes: 40, pages: 40))
        sessions.append(fx.session("b", at: fx.date(2026, 10, 18, 9), minutes: 10, pages: 10))
        // Last week: 100 minutes over two days.
        sessions.append(fx.session("a", at: fx.date(2026, 10, 6, 20), minutes: 60, pages: 60))
        sessions.append(fx.session("a", at: fx.date(2026, 10, 9, 20), minutes: 40, pages: 35))
        let journal = [fx.entry("a", "A line", at: fx.date(2026, 10, 15)), fx.entry("a", kind: .thought, "A thought", at: fx.date(2026, 10, 15))]
        return fx.data(items: items, sessions: sessions, journal: journal)
    }

    @Test func aQuietWeekIsQuiet() {
        let letter = fx.engine(fx.data()).weeklyLetter(weekEnding: fx.now)
        #expect(letter.trend == .quiet)
        #expect(letter.week.minutes == 0 && letter.week.pages == 0 && letter.week.booksFinished == 0)
        #expect(letter.bestDay == nil && letter.topBook == nil && letter.streak == 0)
        #expect(letter.minutesChangeFraction == nil)
        #expect(letter.finishedBooks.isEmpty)
    }

    @Test func thisWeekAgainstLast() throws {
        let letter = fx.engine(thisWeek()).weeklyLetter(weekEnding: fx.now)
        #expect(letter.week.start == fx.date(2026, 10, 12, 0))
        #expect(letter.week.end == fx.date(2026, 10, 18, 0))
        #expect(letter.previous.start == fx.date(2026, 10, 5, 0))
        #expect(letter.previous.end == fx.date(2026, 10, 11, 0))
        #expect(letter.week.minutes == 150 && letter.previous.minutes == 100)
        #expect(letter.week.cups == 6 && letter.previous.cups == 4)
        #expect(letter.week.pages == 150 && letter.previous.pages == 95)
        #expect(letter.week.sessions == 5 && letter.week.daysRead == 4)
        #expect(letter.week.booksFinished == 1 && letter.previous.booksFinished == 0)
        #expect(letter.minutesChange == 50)
        let fraction = try #require(letter.minutesChangeFraction)
        #expect(abs(fraction - 0.5) < 1e-9)
        #expect(letter.pagesChange == 55 && letter.booksChange == 1)
        #expect(letter.trend == .up)
        #expect(letter.quotesSaved == 1)
        #expect(letter.finishedBooks.map(\.bookID) == ["a"])
    }

    @Test func bestDayAndTopBook() throws {
        let letter = fx.engine(thisWeek()).weeklyLetter(weekEnding: fx.now)
        let best = try #require(letter.bestDay)
        #expect(best.date == fx.date(2026, 10, 14, 0))
        #expect(best.minutes == 70)
        #expect(letter.topBook?.bookID == "a")
        #expect(letter.topBook?.minutes == 120)
        #expect(letter.topBook?.title == "Title a")
    }

    @Test func streakIsCountedAsOfTheWeeksLastDay() {
        let engine = fx.engine(thisWeek())
        // Reading on the 12th, 14th, 16th and 18th with every day planned: only the 18th counts back to nothing.
        #expect(engine.weeklyLetter(weekEnding: fx.now).streak == 1)
        let strict = fx.engine(fx.data(sessions: (12...18).map { fx.session("a", at: fx.date(2026, 10, $0, 20), minutes: 10, pages: 5) }))
        #expect(strict.weeklyLetter(weekEnding: fx.now).streak == 7)
        #expect(strict.weeklyLetter(weekEnding: fx.date(2026, 10, 15, 9)).streak == 4)
    }

    @Test func windowEdgesAreInclusiveAndTheDayBeforeIsOut() {
        let sessions = [
            fx.session("b", at: fx.date(2026, 10, 11, 23, 59), minutes: 99, pages: 9),
            fx.session("b", at: fx.date(2026, 10, 12, 0, 1), minutes: 10, pages: 5),
            fx.session("b", at: fx.date(2026, 10, 18, 23, 59), minutes: 20, pages: 5),
            fx.session("b", at: fx.date(2026, 10, 19, 0, 1), minutes: 77, pages: 5),
        ]
        let letter = fx.engine(fx.data(sessions: sessions)).weeklyLetter(weekEnding: fx.date(2026, 10, 18, 7))
        #expect(letter.week.minutes == 30)
        #expect(letter.previous.minutes == 99)
    }

    @Test func aLettersContentsDoNotDependOnNow() {
        let early = fx.engine(thisWeek(), now: fx.date(2026, 10, 18, 21)).weeklyLetter(weekEnding: fx.date(2026, 10, 18, 21))
        let late = fx.engine(thisWeek(), now: fx.date(2027, 3, 3)).weeklyLetter(weekEnding: fx.date(2026, 10, 18, 21))
        #expect(early.week == late.week && early.previous == late.previous)
        #expect(early.bestDay == late.bestDay && early.finishedBooks == late.finishedBooks)
    }

    @Test func trendBandsAreSteadyWithinTenPercent() {
        func trend(this: Double, last: Double) -> WeeklyLetterData.Trend {
            var sessions: [ReadingSession] = []
            if this > 0 { sessions.append(fx.session("b", at: fx.date(2026, 10, 15, 20), minutes: this, pages: 10)) }
            if last > 0 { sessions.append(fx.session("b", at: fx.date(2026, 10, 8, 20), minutes: last, pages: 10)) }
            return fx.engine(fx.data(sessions: sessions)).weeklyLetter(weekEnding: fx.now).trend
        }
        #expect(trend(this: 105, last: 100) == .steady)
        #expect(trend(this: 95, last: 100) == .steady)
        #expect(trend(this: 112, last: 100) == .up)
        #expect(trend(this: 80, last: 100) == .down)
        #expect(trend(this: 30, last: 0) == .fresh)
        #expect(trend(this: 0, last: 30) == .down)
        #expect(trend(this: 0, last: 0) == .quiet)
    }

    @Test func aWeekThatCrossesADaylightSavingChangeStillHasSevenDays() {
        // US clocks went forward on Sunday March 8 2026.
        let sessions = [
            fx.session("b", at: fx.date(2026, 3, 8, 1, 30), minutes: 10, pages: 5),
            fx.session("b", at: fx.date(2026, 3, 8, 12), minutes: 20, pages: 5),
            fx.session("b", at: fx.date(2026, 3, 2, 8), minutes: 5, pages: 5),
            fx.session("b", at: fx.date(2026, 3, 1, 23), minutes: 100, pages: 5),
        ]
        let letter = fx.engine(fx.data(sessions: sessions), now: fx.date(2026, 3, 9, 8)).weeklyLetter(weekEnding: fx.date(2026, 3, 8, 21))
        #expect(letter.week.start == fx.date(2026, 3, 2, 0))
        #expect(letter.week.minutes == 35)
        #expect(letter.previous.minutes == 100)
        #expect(letter.bestDay?.date == fx.date(2026, 3, 8, 0))
    }

    @Test func removedBooksCountInTimeButCannotBeNamed() {
        let sessions = [fx.session("gone", at: fx.date(2026, 10, 15, 20), minutes: 45, pages: 20)]
        let letter = fx.engine(fx.data(sessions: sessions)).weeklyLetter(weekEnding: fx.now)
        #expect(letter.week.minutes == 45 && letter.week.pages == 20)
        #expect(letter.topBook == nil)
        #expect(letter.bestDay?.minutes == 45)
    }
}

// MARK: - Journal

struct InsightsJournalTests {
    let fx = InsightsFixture()

    func sample() -> [JournalEntry] {
        [
            fx.entry("hobbit", "In a hole in the ground there lived a hobbit.", page: 1, favourite: true, at: fx.day(-30), title: "The Hobbit", author: "J. R. R. Tolkien"),
            fx.entry("hobbit", kind: .thought, "Bilbo is a lot like me", page: 30, at: fx.day(-29), title: "The Hobbit", author: "J. R. R. Tolkien"),
            fx.entry("hobbit", "Not all those who wander are lost", page: 12, at: fx.day(-10), title: "The Hobbit", author: "J. R. R. Tolkien"),
            fx.entry("hobbit", kind: .thought, "A thought with no page", at: fx.day(-9), title: "The Hobbit", author: "J. R. R. Tolkien"),
            fx.entry("dune", "Fear is the mind-killer.", page: 9, favourite: true, at: fx.day(-5), title: "Dune", author: "Frank Herbert"),
            fx.entry("cafe", kind: .thought, "Crème brûlée, un café", page: 3, at: fx.day(-2), title: "Café Society", author: "Zoë Étoile"),
        ]
    }

    func tools(_ entries: [JournalEntry]? = nil, library: [LibraryItem] = []) -> JournalTools {
        JournalTools(entries: entries ?? sample(), library: library, calendar: fx.calendar)
    }

    @Test func emptyJournalIsHandled() {
        let empty = tools([])
        #expect(empty.search().isEmpty)
        #expect(empty.groupedByBook().isEmpty)
        #expect(empty.quoteOfTheDay(now: fx.now) == nil)
        #expect(empty.summaries().isEmpty)
        #expect(empty.markdown() == "# Reading journal\n\nNothing saved yet.\n")
        #expect(empty.markdown(forBook: "x") == "")
        #expect(empty.summary(forBook: "x").entryCount == 0)
    }

    @Test func searchFiltersCombineAndSortNewestFirst() {
        let journal = tools()
        let everything = journal.search()
        #expect(everything.count == 6)
        #expect(zip(everything, everything.dropFirst()).allSatisfy { $0.createdAt >= $1.createdAt })
        #expect(journal.search(.init(bookID: "hobbit")).count == 4)
        #expect(journal.search(.init(kind: .quote)).count == 3)
        #expect(journal.search(.init(kind: .thought)).count == 3)
        #expect(journal.search(.init(favouritesOnly: true)).count == 2)
        #expect(journal.search(.init(bookID: "hobbit", kind: .quote, favouritesOnly: true)).count == 1)
        #expect(journal.search(.init(bookID: "nope")).isEmpty)
    }

    @Test func textSearchIgnoresCaseAndAccentsAndNeedsEveryWord() {
        let journal = tools()
        #expect(journal.search(.init(text: "HOBBIT")).count == 4)
        #expect(journal.search(.init(text: "creme brulee")).count == 1)
        #expect(journal.search(.init(text: "café")).count == 1)
        #expect(journal.search(.init(text: "zoe etoile")).count == 1)
        #expect(journal.search(.init(text: "wander lost")).count == 1)
        #expect(journal.search(.init(text: "wander dragon")).isEmpty)
        #expect(journal.search(.init(text: "   ")).count == 6)
        #expect(journal.search(.init(text: "herbert")).count == 1)
        #expect(journal.search(.init(bookID: "hobbit", kind: .thought, text: "bilbo")).count == 1)
    }

    @Test func groupsAreByBookNewestWritingFirstAndReadInPageOrder() {
        let groups = tools().groupedByBook()
        #expect(groups.map(\.bookID) == ["cafe", "dune", "hobbit"])
        let hobbit = groups[2]
        #expect(hobbit.title == "The Hobbit" && hobbit.author == "J. R. R. Tolkien")
        #expect(hobbit.entries.map(\.page) == [1, 12, 30, nil])
        #expect(groups.map(\.entries.count).reduce(0, +) == 6)
        #expect(tools().groupedByBook(.init(kind: .quote)).map(\.bookID) == ["dune", "hobbit"])
    }

    @Test func titlesFallBackToTheLibraryForOldEntries() {
        let bare = fx.entry("b", "Words", title: "")
        var old = bare
        old.bookAuthor = ""
        let library = [fx.item("b")]
        #expect(tools([old], library: library).groupedByBook().first?.title == "Title b")
        #expect(tools([old], library: library).groupedByBook().first?.author == "Ann Author")
        #expect(tools([old]).groupedByBook().first?.title == "")
        #expect(tools([old], library: library).search(.init(text: "title b")).count == 1)
    }

    @Test func bookSummaryCountsAndDates() throws {
        let summary = tools().summary(forBook: "hobbit")
        #expect(summary.entryCount == 4 && summary.quotes == 2 && summary.thoughts == 2)
        #expect(summary.favourites == 1)
        #expect(summary.firstEntry == fx.day(-30) && summary.lastEntry == fx.day(-9))
        #expect(summary.firstPage == 1 && summary.lastPage == 30)
        #expect(summary.favouriteQuote?.text.hasPrefix("In a hole") == true)
        #expect(summary.featuredQuote == summary.favouriteQuote)
        #expect(summary.title == "The Hobbit")
        let noStar = tools().summary(forBook: "cafe")
        #expect(noStar.favouriteQuote == nil && noStar.featuredQuote == nil && noStar.quotes == 0)
        let unstarred = tools(sample().map { var e = $0; e.isFavorite = false; return e }).summary(forBook: "hobbit")
        #expect(unstarred.favouriteQuote == nil)
        #expect(unstarred.featuredQuote?.text.hasPrefix("Not all") == true)
    }

    @Test func summariesFollowTheGroups() {
        #expect(tools().summaries().map(\.bookID) == ["cafe", "dune", "hobbit"])
    }

    // MARK: Quote of the day

    func quotes(_ count: Int) -> [JournalEntry] {
        (0..<count).map { fx.entry("b", "Quote number \($0)", page: $0, at: fx.day(-100 + $0)) }
    }

    @Test func theQuoteStaysTheSameAllDayAndCanChangeTomorrow() {
        let journal = tools(quotes(9))
        let morning = journal.quoteOfTheDay(now: fx.day(0, hour: 6))
        #expect(morning != nil)
        #expect(morning == journal.quoteOfTheDay(now: fx.day(0, hour: 23, minute: 59)))
        #expect(morning == journal.quoteOfTheDay(now: fx.day(0, hour: 0, minute: 0)))
        #expect(morning != journal.quoteOfTheDay(now: fx.day(1, hour: 6)))
    }

    @Test func everyQuoteComesUpEquallyOften() {
        for count in [1, 2, 3, 7, 12] {
            let journal = tools(quotes(count))
            let window = (0..<count * 4).compactMap { journal.quoteOfTheDay(now: fx.day(2000 + $0))?.id }
            let counts = Dictionary(grouping: window, by: { $0 }).mapValues(\.count)
            #expect(counts.count == count)
            #expect(counts.values.allSatisfy { $0 >= 3 && $0 <= 5 })
        }
    }

    @Test func aWholeCycleShowsEveryQuoteOnce() {
        let count = 8
        let journal = tools(quotes(count))
        let first = JournalTools.dayNumber(fx.day(3000), calendar: fx.calendar)
        let aligned = Int(first % Int64(count))
        let startOffset = (count - aligned) % count
        let shown = (0..<count).compactMap { journal.quoteOfTheDay(now: fx.day(3000 + startOffset + $0))?.id }
        #expect(Set(shown).count == count)
    }

    @Test func theQuoteIgnoresInputOrderAndThoughts() {
        var entries = quotes(6) + [fx.entry("b", kind: .thought, "Just a thought")]
        let one = tools(entries).quoteOfTheDay(now: fx.now)
        entries.reverse()
        #expect(tools(entries).quoteOfTheDay(now: fx.now) == one)
        #expect(one?.kind == .quote)
        let blank = tools([fx.entry("b", "   \n ")])
        #expect(blank.quoteOfTheDay(now: fx.now) == nil)
    }

    @Test func theSeedAndFavouritesChangeTheDraw() {
        let journal = tools(quotes(20))
        let draws = (0..<20).map { journal.quoteOfTheDay(now: fx.day($0))?.id }
        let reseeded = (0..<20).map { journal.quoteOfTheDay(now: fx.day($0), seed: 7)?.id }
        #expect(draws != reseeded)
        #expect(Set(reseeded.compactMap { $0 }).count > 1)
        let starred = quotes(10).enumerated().map { var e = $1; e.isFavorite = $0 < 3; return e }
        let favouritesOnly = (0..<12).compactMap { tools(starred).quoteOfTheDay(now: fx.day($0), favouritesOnly: true) }
        #expect(favouritesOnly.count == 12 && favouritesOnly.allSatisfy { $0.isFavorite })
        #expect(tools(quotes(4)).quoteOfTheDay(now: fx.now, favouritesOnly: true) == nil)
    }

    @Test func theQuoteChangesAtLocalMidnight() {
        let journal = tools(quotes(9))
        // 23:30 in New York and 04:30 the next morning in UTC: the same instant, a different calendar day.
        let instant = fx.day(0, hour: 23, minute: 30)
        let utc = InsightsFixture(timeZone: "UTC")
        let utcTools = JournalTools(entries: quotes(9), calendar: utc.calendar)
        let nextLocal = journal.quoteOfTheDay(now: fx.day(1, hour: 0, minute: 30))
        #expect(journal.quoteOfTheDay(now: instant) != nextLocal)
        #expect(utcTools.quoteOfTheDay(now: instant) == utcTools.quoteOfTheDay(now: fx.day(1, hour: 0, minute: 30)))
    }

    // MARK: Markdown

    @Test func oneBooksJournalExportsInReadingOrderWithPages() {
        let text = tools().markdown(forBook: "hobbit")
        let expected = """
        # The Hobbit

        *J\\. R\\. R\\. Tolkien* · 2 quotes · 2 thoughts

        > In a hole in the ground there lived a hobbit.
        >
        > — p. 1, \(iso(fx.day(-30))) ★

        > Not all those who wander are lost
        >
        > — p. 12, \(iso(fx.day(-10)))

        Bilbo is a lot like me

        *p. 30, \(iso(fx.day(-29)))*

        A thought with no page

        *\(iso(fx.day(-9)))*

        """
        #expect(text == expected.replacingOccurrences(of: "\\.", with: "."))
    }

    func iso(_ date: Date) -> String {
        let c = fx.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    @Test func wholeJournalIsAlphabeticalAndStable() {
        let text = tools().markdown()
        #expect(text.hasPrefix("# Reading journal\n\n6 entries from 3 books.\n"))
        let titles = text.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }
        #expect(titles == ["## Café Society", "## Dune", "## The Hobbit"])
        #expect(text.contains("p. 9"))
        #expect(text.contains("p. 3"))
        #expect(tools(sample().reversed()).markdown() == text)
        #expect(tools(sample().shuffledByHash()).markdown() == text)
        #expect(text.hasSuffix("\n") && !text.hasSuffix("\n\n"))
    }

    @Test func exportsFilterLikeSearchDoes() {
        let favourites = tools().markdown(filter: .init(favouritesOnly: true))
        #expect(favourites.contains("Fear is the mind-killer."))
        #expect(favourites.contains("In a hole in the ground"))
        #expect(!favourites.contains("Bilbo"))
        #expect(favourites.hasPrefix("# Reading journal\n\n2 entries from 2 books.\n"))
        #expect(tools().markdown(filter: .init(text: "nothing like this")) == "# Reading journal\n\nNothing saved yet.\n")
        #expect(tools().markdown(forBook: "missing") == "")
    }

    @Test func multilineAndMarkdownLookingTextIsKeptSafe() {
        let entries = [
            fx.entry("b", "Line one\nLine two\n\nLine four", page: 4, at: fx.day(-3), title: "A *Star* [Is] Born_", author: "Ann # Author"),
            fx.entry("b", kind: .thought, "# Not a heading\n- not a list\n1. not numbered\n> not quoted\nplain", at: fx.day(-2), title: "A *Star* [Is] Born_", author: "Ann # Author"),
        ]
        let text = tools(entries).markdown(forBook: "b")
        #expect(text.hasPrefix("# A \\*Star\\* \\[Is\\] Born\\_\n"))
        #expect(text.contains("> Line one\n> Line two\n>\n> Line four\n>\n> — p. 4,"))
        #expect(text.contains("\\# Not a heading\n\\- not a list\n\\1. not numbered\n\\> not quoted\nplain"))
        #expect(!text.contains("\n# Not a heading"))
    }

    @Test func exportDatesFollowTheCalendarsTimeZone() {
        // 23:30 New York on Oct 17 is already Oct 18 in UTC.
        let entry = fx.entry("b", "Late", at: fx.date(2026, 10, 17, 23, 30))
        let utc = InsightsFixture(timeZone: "UTC")
        #expect(JournalTools(entries: [entry], calendar: fx.calendar).markdown().contains("2026-10-17"))
        #expect(JournalTools(entries: [entry], calendar: utc.calendar).markdown().contains("2026-10-18"))
    }
}

private extension Array {
    /// A repeatable, order-scrambling shuffle (no randomness) for checking that results do not depend on input order.
    func shuffledByHash() -> [Element] {
        enumerated().sorted { (SeededGenerator.hash("\($0.offset)") ^ 0x5555) < (SeededGenerator.hash("\($1.offset)") ^ 0x5555) }.map(\.element)
    }
}

// MARK: - Odd and large data

struct InsightsRobustnessTests {
    let fx = InsightsFixture()

    @Test func everythingHandlesEmptyData() {
        let engine = fx.engine(fx.data())
        #expect(engine.heatmap(year: 2026).count == 365)
        #expect(engine.bestTimeOfDay() == nil)
        #expect(engine.speedTrend().label == .notEnoughData)
        #expect(engine.genreMix().isEmpty && engine.lengthMix().isEmpty)
        #expect(engine.tbrDepth().queueBooks == 0)
        #expect(engine.personality().isDefault)
        #expect(engine.yearInBooks(year: 2026).isEmpty)
        #expect(engine.weeklyLetter(weekEnding: fx.now).trend == .quiet)
        #expect(engine.yearGoalPacing().status == .noGoal)
        #expect(engine.currentStreak() == 0 && engine.longestStreak() == 0)
    }

    @Test func zeroLengthAndBackwardsSessionsDoNotBreakAnything() {
        let sessions = [
            fx.session("b", at: fx.day(-1), minutes: 0, pages: 0),
            ReadingSession(bookID: "b", startedAt: fx.day(-2), seconds: -30, fromPage: 50, toPage: 10),
            ReadingSession(bookID: "b", startedAt: fx.day(-3), seconds: 1e9, fromPage: 0, toPage: 1_000_000),
            fx.session("b", at: fx.day(-4), minutes: 120, pages: 4, kind: .manual),
        ]
        let engine = fx.engine(fx.data(items: [fx.item("b", pages: 10_000_000)], sessions: sessions))
        let year = engine.yearInBooks(year: 2026)
        #expect(year.minutes.isFinite && year.pages >= 0)
        #expect(engine.heatmap(year: 2026).allSatisfy { $0.ring >= 0 && $0.ring <= 1 && $0.minutes >= 0 })
        #expect(engine.speedTrend().sampleCount <= 1)
        #expect(engine.currentStreak() >= 0)
        _ = engine.personality()
        _ = engine.bestTimeOfDay()
        _ = engine.weeklyLetter(weekEnding: fx.now)
    }

    @Test func oldFilesWithoutTheNewFieldsStillWork() throws {
        let json = """
        {"items":[{"book":{"id":"a","title":"A","author":"X","pages":300,"words":81000,"genres":["fantasy"],"popularity":0},"shelf":"finished","finishedAt":800000000},
                  {"book":{"id":"b","title":"B","author":"Y","pages":200,"words":54000,"genres":[],"popularity":0},"shelf":"toRead"}],
         "sessions":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bookID":"a","startedAt":799000000,"seconds":1800,"fromPage":0,"toPage":30}],
         "preferences":{"wpm":250,"dailyMinutes":15}}
        """
        let data = try JSONDecoder().decode(LeafData.self, from: Data(json.utf8))
        let engine = InsightsEngine(data: data, now: Date(timeIntervalSinceReferenceDate: 801_000_000), calendar: fx.calendar)
        #expect(engine.genreMix().first?.tag == "fantasy")
        #expect(engine.tbrDepth().queueBooks == 1)
        #expect(engine.yearInBooks(year: 2026).booksFinished == 1)
        #expect(engine.weeklyLetter(weekEnding: engine.now).week.minutes >= 0)
        _ = engine.personality()
    }

    @Test func aLongHistoryOfThousandsOfBooksStaysFast() {
        // Three years of daily reading, 1,000 books and a busy journal.
        let timedStart = fx.day(-1096)
        var items: [LibraryItem] = []
        for index in 0..<1000 {
            let shelf: Shelf
            var finished: Date?
            switch index % 10 {
            case 0...2:
                shelf = .finished
                finished = fx.calendar.date(byAdding: .day, value: index % 1090, to: timedStart)
            case 3: shelf = .reading
            case 4: shelf = .paused
            default: shelf = .toRead
            }
            let genres = [["fantasy"], ["mystery", "thriller"], ["history"], ["romance"], []][index % 5]
            items.append(fx.item("book\(index)", shelf: shelf, pages: 150 + (index * 7) % 500, genres: genres, author: "Author \(index % 120)", started: timedStart, finished: finished, rating: index % 6 == 0 ? nil : 1 + index % 5))
        }
        let sessions = (1...1096).map { offset -> ReadingSession in
            fx.session("book\(offset % 1000)", at: fx.day(-offset, hour: 6 + offset % 17), minutes: Double(15 + (offset * 13) % 60), pages: 10 + (offset * 7) % 40, from: offset % 100)
        }
        let journal = (0..<400).map { index in
            fx.entry("book\(index % 1000)", kind: index % 3 == 0 ? .thought : .quote, "Entry \(index) about reading", page: index % 300, favourite: index % 7 == 0, at: fx.day(-(index * 2) % 1000))
        }
        let data = fx.data(items: items, sessions: sessions, journal: journal) { $0.yearlyGoal = 40 }

        let clock = ContinuousClock()
        var summary = 0
        let elapsed = clock.measure {
            let engine = fx.engine(data)
            for year in 2024...2026 {
                summary += engine.heatmap(year: year).count + engine.yearInBooks(year: year).booksFinished
            }
            summary += engine.bestTimeOfDay()?.sessionCount ?? 0
            summary += engine.speedTrend().points.count
            summary += engine.genreMix().count + engine.lengthMix().count
            summary += engine.tbrDepth().queueBooks
            summary += engine.personality().evidence.count
            summary += engine.weeklyLetter(weekEnding: fx.now).week.sessions
            summary += engine.yearGoalPacing().finished
            summary += engine.currentStreak() + engine.longestStreak()
            let journalTools = JournalTools(data: data, calendar: fx.calendar)
            summary += journalTools.search(.init(text: "reading")).count
            summary += journalTools.markdown().count
            summary += journalTools.quoteOfTheDay(now: fx.now) == nil ? 0 : 1
        }
        #expect(summary > 0)
        // A budget with room for a busy runner (it shares the machine with every other test, in a Debug build): it is
        // here to catch a slow algorithm, which would take seconds, not a slow afternoon.
        #expect(elapsed < .milliseconds(1500), "took \(elapsed)")
    }

    @Test func theSameDataAlwaysGivesTheSameAnswers() {
        let sessions = fx.reader(offsets: (1...200).reversed().map { -$0 }, hour: { 6 + $0 % 16 }, minutes: { 10 + Double($0 % 50) })
        let data = fx.data(items: [fx.item("b", pages: 100_000), fx.item("f", shelf: .finished)], sessions: sessions)
        let a = fx.engine(data)
        let b = fx.engine(data)
        #expect(a.personality() == b.personality())
        #expect(a.bestTimeOfDay() == b.bestTimeOfDay())
        #expect(a.speedTrend() == b.speedTrend())
        #expect(a.heatmap(year: 2026) == b.heatmap(year: 2026))
        #expect(a.yearInBooks(year: 2026) == b.yearInBooks(year: 2026))
        #expect(a.weeklyLetter(weekEnding: fx.now) == b.weeklyLetter(weekEnding: fx.now))
    }
}
