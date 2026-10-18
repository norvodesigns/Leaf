import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Shared fixtures

/// A fixed calendar and "now" for every forecast test: Wednesday, Oct 14 2026, 9:00 in New York. Daylight saving ends
/// on Nov 1, so forecasts that run past it also exercise the calendar arithmetic.
enum ForecastFixture {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    static var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9))! }

    static func date(_ month: Int, _ day: Int, hour: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func day(_ offset: Int, from start: Date = now) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: start))!
    }

    static func offset(_ date: Date, from start: Date = now) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func book(_ id: String, pages: Int = 300, words: Int? = nil, genres: [String] = ["fantasy"]) -> Book {
        Book(id: id, title: "Book \(id)", author: "Author \(id)", pages: pages, words: words ?? pages * 270, genres: genres)
    }

    static func item(_ id: String, pages: Int = 300, page: Int = 0, shelf: Shelf = .reading, order: Double = 0, genres: [String] = ["fantasy"], confirmed: Bool? = nil, startPage: Int = 0) -> LibraryItem {
        LibraryItem(
            book: book(id, pages: pages, genres: genres), shelf: shelf, currentPage: page, order: order,
            addedAt: date(1, 1), startedAt: shelf == .reading ? date(9, 1) : nil,
            startPage: startPage, positionConfirmed: confirmed
        )
    }

    static func library(reading: [LibraryItem], queue: [LibraryItem] = [], minutes: Int = 30, days: Set<Int> = Set(1...7), mode: PlanMode = .focus, goal: Int? = nil) -> LeafData {
        var data = LeafData()
        data.items = reading + queue
        data.preferences.dailyMinutes = minutes
        data.preferences.readingDays = days
        data.preferences.planMode = mode
        data.preferences.yearlyGoal = goal
        return data
    }

    static func engine(_ data: LeafData, now: Date = now) -> ForecastEngine {
        ForecastEngine(data: data, now: now, calendar: calendar)
    }

    static func session(_ id: String, day: Int, minutes: Double, from: Int, to: Int, hour: Int = 20, kind: SessionKind = .timed, relativeTo start: Date = now) -> ReadingSession {
        let base = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: start))!
        let at = calendar.date(byAdding: .hour, value: hour, to: base)!
        return ReadingSession(bookID: id, startedAt: at, seconds: minutes * 60, fromPage: from, toPage: to, kind: kind)
    }
}

/// A small deterministic normal generator for building synthetic readers (kept separate from the engine's own).
struct ForecastTestRandom {
    var rng: SeededGenerator

    init(seed: UInt64) { rng = SeededGenerator(seed: seed) }

    mutating func unit() -> Double { rng.unit() }

    mutating func gauss() -> Double {
        let u1 = max(rng.unit(), 1e-12)
        let u2 = rng.unit()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }

    mutating func lognormal(median: Double, sigma: Double) -> Double { median * exp(sigma * gauss()) }
}

// MARK: - Synthetic readers

/// A made-up reader with a known way of reading, used to check that forecast ranges are honest. They read the way real
/// people do (some days, some weeks, noisy speed, a warm-up at the start of a sitting), not the way the model assumes.
struct ForecastPersona {
    var name: String
    var seed: UInt64
    /// Speed in books, words per minute.
    var trueWPM: Double
    /// What the onboarding passage test said.
    var testWPM: Double
    var readingDays: Set<Int> = Set(1...7)
    /// Chance of reading on each weekday (1 = Sunday).
    var dayChance: [Int: Double]
    /// Busy and quiet weeks: spread of a multiplier on those chances.
    var weekSigma = 0.0
    /// Median minutes on a day read, by weekday; `defaultMinutes` otherwise.
    var weekdayMinutes: [Int: Double] = [:]
    var defaultMinutes = 30.0
    var minutesSigma = 0.35
    var speedSigma = 0.15
    var bookSigma = 0.10
    var warmUpLoss = 0.06
    var days = 200
    var pages: ClosedRange<Int> = 220...420
    var genres = ["fantasy", "mystery", "literary"]
    var genreSpeed: [String: Double] = ["fantasy": 1.0, "mystery": 1.1, "literary": 0.88]
    var hours = [20, 21, 22, 7, 13]
    var mode: PlanMode = .focus

    /// Data as it stands on the last day: finished books with their sessions, one book in progress, a short queue.
    func build() -> (data: LeafData, now: Date) {
        let calendar = ForecastFixture.calendar
        let start = ForecastFixture.date(1, 5)
        var random = ForecastTestRandom(seed: seed)
        var data = LeafData()
        data.preferences.dailyMinutes = Int(defaultMinutes.rounded())
        data.preferences.readingDays = readingDays
        data.preferences.planMode = mode
        data.preferences.onboardedAt = start
        data.preferences.wpm = testWPM
        data.speedTests = [SpeedTestResult(date: start, passageID: "p1", words: Int(testWPM), seconds: 60, correct: 5, total: 5)]

        var index = 0
        func makeBook() -> Book {
            index += 1
            let genre = genres[index % genres.count]
            return Book(id: "\(name)-\(index)", title: "Book \(index)", author: "Author", pages: Int(Double(pages.lowerBound) + Double(pages.count) * random.unit()), words: nil, genres: [genre])
        }
        var book = makeBook()
        var bookFactor = random.lognormal(median: 1, sigma: bookSigma) * (genreSpeed[book.genres[0]] ?? 1)
        var exactPage = 0.0
        var startedAt: Date?
        var weekMultiplier = 1.0
        var currentWPM = testWPM

        for day in 0..<days {
            let date = calendar.date(byAdding: .day, value: day, to: start)!
            let weekday = calendar.component(.weekday, from: date)
            if day % 7 == 0 { weekMultiplier = weekSigma > 0 ? exp(weekSigma * random.gauss() - weekSigma * weekSigma / 2) : 1 }
            guard readingDays.contains(weekday) || (dayChance[weekday] ?? 0) > 0 else { continue }
            let chance = min(0.99, (dayChance[weekday] ?? 0) * weekMultiplier)
            guard random.unit() < chance else { continue }

            var remaining = max(3, random.lognormal(median: weekdayMinutes[weekday] ?? defaultMinutes, sigma: minutesSigma))
            let sitting = remaining
            var clock = calendar.date(byAdding: .hour, value: hours[Int(random.unit() * Double(hours.count)) % hours.count], to: date)!
            // A day's reading runs on into the next book when one is finished, as it would for a real reader.
            while remaining > 0.5 {
                let warm = 1 - warmUpLoss * min(1, 5 / sitting)
                let speed = trueWPM * bookFactor * exp(speedSigma * random.gauss()) * warm
                let from = Int(exactPage)
                let gained = remaining * speed / book.wordsPerPage
                exactPage += gained
                var to = Int(exactPage)
                let finished = to >= book.pages
                var used = remaining
                if finished {
                    to = book.pages
                    used = max(0.5, (Double(book.pages) - Double(from)) * book.wordsPerPage / speed)
                }
                let session = ReadingSession(bookID: book.id, startedAt: clock, seconds: used * 60, fromPage: from, toPage: to)
                data.sessions.append(session)
                if startedAt == nil { startedAt = clock }
                if let observed = ReadingSpeed.observedWPM(pagesRead: session.pagesRead, wordsPerPage: book.wordsPerPage, seconds: session.seconds) {
                    currentWPM = ReadingSpeed.calibrated(current: currentWPM, observed: observed)
                }
                clock = clock.addingTimeInterval(used * 60)
                remaining -= used
                if finished {
                    var item = LibraryItem(book: book, shelf: .finished, currentPage: book.pages, order: Double(index), addedAt: start, startedAt: startedAt, finishedAt: clock)
                    item.positionConfirmed = true
                    data.items.append(item)
                    book = makeBook()
                    bookFactor = random.lognormal(median: 1, sigma: bookSigma) * (genreSpeed[book.genres[0]] ?? 1)
                    exactPage = 0
                    startedAt = nil
                } else {
                    remaining = 0
                }
            }
        }
        data.preferences.wpm = currentWPM

        var reading = LibraryItem(book: book, shelf: .reading, currentPage: Int(exactPage), order: 0, addedAt: start, startedAt: startedAt ?? start)
        reading.positionConfirmed = true
        data.items.append(reading)
        for q in 0..<3 {
            let next = makeBook()
            data.items.append(LibraryItem(book: next, shelf: .toRead, order: Double(q + 1), addedAt: start))
        }
        let end = calendar.date(byAdding: .day, value: days, to: start)!
        return (data, calendar.date(byAdding: .hour, value: 9, to: end)!)
    }

    static let steady = ForecastPersona(
        name: "steady", seed: 11, trueWPM: 250, testWPM: 260,
        dayChance: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, 0.93) }), defaultMinutes: 30, minutesSigma: 0.2
    )
    static let weekendBinger = ForecastPersona(
        name: "binger", seed: 23, trueWPM: 230, testWPM: 240,
        dayChance: [1: 0.9, 7: 0.9, 2: 0.15, 3: 0.15, 4: 0.15, 5: 0.15, 6: 0.2],
        weekdayMinutes: [1: 100, 7: 90], defaultMinutes: 15, minutesSigma: 0.3
    )
    static let erratic = ForecastPersona(
        name: "erratic", seed: 37, trueWPM: 220, testWPM: 250,
        dayChance: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, 0.55) }), weekSigma: 0.6, defaultMinutes: 25, minutesSigma: 0.6, speedSigma: 0.25
    )
    static let slow = ForecastPersona(
        name: "slow", seed: 41, trueWPM: 120, testWPM: 180,
        dayChance: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, 0.85) }), defaultMinutes: 15, minutesSigma: 0.3, days: 260
    )
}

// MARK: - Test helpers

enum ForecastTestData {
    /// A reader who has read `perDay` minutes on each of the given days before today (negative offsets), in one long book.
    static func steadyReader(days: ClosedRange<Int>, skipping skipped: Set<Int> = [], minutes: Double = 30, bookID: String = "a", pages: Int = 5000, goal: Int? = nil, catchUp: CatchUpMode = .forgive) -> LeafData {
        var data = ForecastFixture.library(reading: [ForecastFixture.item(bookID, pages: pages)], minutes: Int(minutes), goal: goal)
        data.preferences.onboardedAt = ForecastFixture.day(days.lowerBound)
        data.preferences.catchUp = catchUp
        var page = 0
        let step = Int(minutes * 238 / 270)
        for day in days where !skipped.contains(day) {
            data.sessions.append(ForecastFixture.session(bookID, day: day, minutes: minutes, from: page, to: page + step))
            page += step
        }
        data.items[0].currentPage = page
        return data
    }

    static func median(_ f: BookForecast) -> Int { f.medianOffset ?? Int.max }

    static func coverage(_ checkpoints: [BacktestCheckpoint]) -> Double {
        Double(checkpoints.filter(\.covered).count) / Double(max(1, checkpoints.count))
    }

    static func smoothed(_ checkpoints: [BacktestCheckpoint]) -> Double {
        Double(checkpoints.filter { $0.percentile >= 0.1 && $0.percentile <= 0.9 }.count) / Double(max(1, checkpoints.count))
    }

    static func pooled(_ base: ForecastPersona, seeds: Int, days: Int = 280) -> [BacktestCheckpoint] {
        var all: [BacktestCheckpoint] = []
        for k in 0..<seeds {
            var persona = base
            persona.seed = base.seed &+ UInt64(k) &* 1000
            persona.days = days
            let (data, now) = persona.build()
            all += ForecastEngine(data: data, now: now, calendar: ForecastFixture.calendar).backtest(options: BacktestOptions(runs: 150)).checkpoints
        }
        return all
    }

    /// A forecast with a hand-made distribution, for narration tests.
    static func forecast(_ days: [Int32], confidence: ForecastConfidence = .medium) -> BookForecast {
        BookForecast(
            id: "x", isReading: true, remainingMinutes: 100, deterministicFinish: nil, confidence: confidence,
            positionUncertain: false, sessions: 10, finishDays: days.sorted(),
            origin: ForecastFixture.calendar.startOfDay(for: ForecastFixture.now), calendar: ForecastFixture.calendar
        )
    }
}

// MARK: - Models

struct ForecastModelTests {
    @Test func paceFallsBackToThePreferenceWithoutSessions() {
        var data = ForecastFixture.library(reading: [ForecastFixture.item("a")])
        data.preferences.wpm = 300
        let pace = ForecastFixture.engine(data).fit.pace
        #expect(abs(pace.overallWPM - 300) < 300 * 0.05)
        #expect(pace.usableSessions == 0)
        #expect(pace.pace(for: ForecastFixture.book("a")).correction == 1)
    }

    @Test func tooShortAndZeroPageSessionsSayNothingAboutSpeed() {
        var data = ForecastFixture.library(reading: [ForecastFixture.item("a")])
        data.sessions = [
            ForecastFixture.session("a", day: -3, minutes: 2, from: 0, to: 6),
            ForecastFixture.session("a", day: -2, minutes: 25, from: 6, to: 6),
            ForecastFixture.session("a", day: -1, minutes: 25, from: 6, to: 30),
        ]
        let records = ForecastFixture.engine(data).records
        #expect(records.count == 3)
        #expect(records.filter { $0.wpm != nil }.count == 1)
    }

    @Test func typedInSessionsCountForLess() {
        var data = ForecastFixture.library(reading: [ForecastFixture.item("a")])
        data.sessions = [
            ForecastFixture.session("a", day: -2, minutes: 20, from: 0, to: 20, kind: .timed),
            ForecastFixture.session("a", day: -1, minutes: 20, from: 20, to: 40, kind: .manual),
        ]
        let records = ForecastFixture.engine(data).records
        #expect(records[1].weight < records[0].weight)
        #expect(records[1].weight > 0)
    }

    @Test func aFirstSessionLoggedFromPageZeroDoesNotLookImpossiblyFast() {
        // The reader began this book on page 150, but the legacy session says it started at 0.
        var data = ForecastFixture.library(reading: [ForecastFixture.item("a", page: 170, startPage: 150)])
        data.sessions = [ForecastFixture.session("a", day: -1, minutes: 20, from: 0, to: 170)]
        let record = ForecastFixture.engine(data).records[0]
        #expect(record.pages == 20)
        #expect(record.wpm != nil)
    }

    private func bookCorrectionData(sessionsOnTarget: Int, targetWPM: Double) -> LeafData {
        var data = ForecastFixture.library(reading: [ForecastFixture.item("a", pages: 2000), ForecastFixture.item("b", pages: 2000)])
        var page = 0
        for i in 0..<20 {
            let pages = Int(20 * 240 / 270.0)
            data.sessions.append(ForecastFixture.session("b", day: -60 + i, minutes: 20, from: page, to: page + pages))
            page += pages
        }
        page = 0
        for i in 0..<sessionsOnTarget {
            let pages = Int(20 * targetWPM / 270)
            data.sessions.append(ForecastFixture.session("a", day: -30 + i, minutes: 20, from: page, to: page + pages))
            page += pages
        }
        return data
    }

    @Test func aBookGetsItsOwnCorrectionOnlyAfterThreeSessions() {
        let few = ForecastFixture.engine(bookCorrectionData(sessionsOnTarget: 2, targetWPM: 400)).fit.pace.pace(for: ForecastFixture.book("a"))
        #expect(few.correction == 1)
        let many = ForecastFixture.engine(bookCorrectionData(sessionsOnTarget: 6, targetWPM: 400)).fit.pace.pace(for: ForecastFixture.book("a"))
        #expect(many.correction > 1.05 && many.correction <= 1.4)
        let slow = ForecastFixture.engine(bookCorrectionData(sessionsOnTarget: 6, targetWPM: 90)).fit.pace.pace(for: ForecastFixture.book("a"))
        #expect(slow.correction >= 0.7 && slow.correction < 0.95)
    }

    @Test func pacePullsTowardTheParentWithFewSessions() {
        // One very fast session barely moves a book that has a long history at a steady speed.
        let base = bookCorrectionData(sessionsOnTarget: 1, targetWPM: 600)
        let level = ForecastFixture.engine(base).fit.pace.pace(for: ForecastFixture.book("a"))
        #expect(exp(level.mean) < 300)
    }

    @Test func newReadersAreAssumedToFollowThroughMostDays() {
        let data = ForecastFixture.library(reading: [ForecastFixture.item("a")], days: [2, 3, 4, 5, 6])
        let adherence = ForecastFixture.engine(data).fit.adherence
        #expect(abs(adherence.probability(weekdayIndex: 1) - 0.7) < 0.05)
        #expect(adherence.probability(weekdayIndex: 0) == 0)
        #expect(adherence.probability(weekdayIndex: 6) == 0)
    }

    @Test func adherenceLearnsWhichWeekdaysTheReaderReallyReads() {
        // Every day is a chosen reading day, but for eight weeks they read only Monday to Friday.
        var skipped: Set<Int> = []
        for day in -56...(-1) {
            let weekday = ForecastFixture.calendar.component(.weekday, from: ForecastFixture.day(day))
            if weekday == 1 || weekday == 7 { skipped.insert(day) }
        }
        let engine = ForecastFixture.engine(ForecastTestData.steadyReader(days: -56...(-1), skipping: skipped))
        let adherence = engine.fit.adherence
        #expect(adherence.probability(weekdayIndex: 0) < 0.25)
        #expect(adherence.probability(weekdayIndex: 6) < 0.25)
        #expect(adherence.probability(weekdayIndex: 2) > 0.85)
        // Minutes on a day read are fitted to what they do.
        #expect(abs(engine.fit.minutes.medianMinutes - 30) < 4)
    }

    @Test func minutesFallBackToTheDailyMinutesSetting() {
        let data = ForecastFixture.library(reading: [ForecastFixture.item("a")], minutes: 45)
        let minutes = ForecastFixture.engine(data).fit.minutes
        #expect(minutes.meanMinutes == 45)
        #expect(minutes.scaled(toAim: 45).meanMinutes == 45)
        #expect(minutes.scaled(toAim: 60).meanMinutes > minutes.meanMinutes)
    }

    @Test func recordsAreWeightedLessWhenAPageIsMostOfTheSession() {
        var data = ForecastFixture.library(reading: [ForecastFixture.item("a")])
        data.sessions = [
            ForecastFixture.session("a", day: -2, minutes: 5, from: 0, to: 2),
            ForecastFixture.session("a", day: -1, minutes: 30, from: 2, to: 32),
        ]
        let records = ForecastFixture.engine(data).records
        #expect(records[0].weight < records[1].weight)
    }
}

// MARK: - Engine

struct ForecastEngineTests {
    func tenBooks(minutes: Int = 30) -> LeafData {
        let reading = [ForecastFixture.item("b0", page: 50)]
        let queue = (1..<10).map { ForecastFixture.item("b\($0)", shelf: .toRead, order: Double($0), genres: [$0 % 2 == 0 ? "fantasy" : "mystery"]) }
        return ForecastFixture.library(reading: reading, queue: queue, minutes: minutes, goal: 12)
    }

    @Test func sameSeedGivesTheSameFutures() {
        let engine = ForecastFixture.engine(tenBooks())
        let a = engine.forecast(seed: 5, runs: 400)
        let b = engine.forecast(seed: 5, runs: 400)
        #expect(a.books.map(\.finishDays) == b.books.map(\.finishDays))
        #expect(a.year.totals == b.year.totals)
        let c = engine.forecast(seed: 6, runs: 400)
        #expect(a.books.map(\.finishDays) != c.books.map(\.finishDays))
    }

    @Test func rangesAreOrderedAndProbabilityNeverFalls() {
        let result = ForecastFixture.engine(tenBooks()).forecast(seed: 3, runs: 500)
        for book in result.books {
            guard let p10 = book.p10Offset, let median = book.medianOffset, let p90 = book.p90Offset else { continue }
            #expect(p10 <= median && median <= p90)
            var last = 0.0
            for offset in 0..<400 {
                let chance = book.probability(byOffset: offset)
                #expect(chance >= last)
                #expect(chance >= 0 && chance <= 1)
                last = chance
            }
            #expect(book.probability(byOffset: -1) == 0)
            let median9 = book.probability(by: ForecastFixture.day(median))
            #expect(median9 >= 0.5)
            let curve = book.curve()
            #expect(!curve.isEmpty)
            #expect(zip(curve, curve.dropFirst()).allSatisfy { $0.probability <= $1.probability })
        }
        // Later books in the queue finish later.
        let medians = result.books.compactMap(\.medianOffset)
        #expect(medians == medians.sorted())
    }

    @Test func pausedAndFinishedBooksAreLeftOut() {
        var data = tenBooks()
        data.items.append(ForecastFixture.item("paused", pages: 900, page: 100, shelf: .paused, order: 0))
        data.items.append(ForecastFixture.item("done", page: 300, shelf: .finished, order: 0))
        let withExtras = ForecastFixture.engine(data).forecast(seed: 2, runs: 300)
        let without = ForecastFixture.engine(tenBooks()).forecast(seed: 2, runs: 300)
        #expect(withExtras.book("paused") == nil && withExtras.book("done") == nil)
        #expect(withExtras.books.map(\.id) == without.books.map(\.id))
        // The paused book takes no reading time.
        #expect(withExtras.books.map(\.finishDays) == without.books.map(\.finishDays))
    }

    @Test func anEmptyLibraryIsFine() {
        let engine = ForecastFixture.engine(LeafData())
        let result = engine.forecast(seed: 1, runs: 200)
        #expect(result.books.isEmpty)
        #expect(result.year.finishedSoFar == 0 && result.year.median == 0)
        #expect(result.year.includesFuturePicks == false)
        #expect(engine.backtest().quality == .insufficient)
        #expect(engine.stalledBooks().isEmpty)
        #expect(engine.smartOrder(goal: .alternateGenres).isChange == false)
        #expect(engine.inversePlan(bookID: "nope", by: ForecastFixture.day(10)).feasibility == .impossible)
        #expect(engine.catchUp().action == .nothingToMakeUp)
    }

    @Test func zeroDailyMinutesMeansNoFinishDatesUntilThereIsTime() {
        let data = ForecastFixture.library(reading: [ForecastFixture.item("a", page: 100)], minutes: 0)
        let engine = ForecastFixture.engine(data)
        let result = engine.forecast(seed: 1, runs: 200)
        #expect(result.books[0].medianOffset == nil)
        #expect(result.books[0].probability(byOffset: 500) == 0)
        #expect(result.books[0].neverProbability == 1)
        #expect(result.year.median == 0)
        let planned = engine.whatIf(dailyMinutes: 30, seed: 1, runs: 200)
        #expect(planned.books[0].medianOffset != nil)
        let noDays = ForecastFixture.engine(ForecastFixture.library(reading: [ForecastFixture.item("a")], days: []))
        #expect(noDays.forecast(seed: 1, runs: 100).books[0].medianOffset == nil)
    }

    @Test func olderFilesWithoutNewFieldsStillForecast() throws {
        let json = """
        {"items":[{"book":{"id":"x","title":"T","author":"A","pages":300,"words":81000,"genres":["fantasy"],"popularity":0},
                   "shelf":"reading","currentPage":120,"order":0,"addedAt":0}],
         "sessions":[{"id":"7C2E1F00-0000-4000-8000-000000000001","bookID":"x","startedAt":800000000,"seconds":1200,"fromPage":100,"toPage":120}],
         "preferences":{"dailyMinutes":30}}
        """
        let data = try JSONDecoder().decode(LeafData.self, from: Data(json.utf8))
        #expect(data.items[0].startPage == 0)
        let engine = ForecastFixture.engine(data)
        let result = engine.forecast(seed: 1, runs: 200)
        #expect(result.books.count == 1)
        #expect(result.books[0].medianOffset != nil)
        #expect(result.books[0].positionUncertain == false)
    }

    @Test func tenBooksTwoThousandRunsAreFast() {
        let engine = ForecastFixture.engine(tenBooks())
        let clock = ContinuousClock()
        var result: ForecastResult?
        let elapsed = clock.measure { result = engine.forecast(seed: 1, runs: 2000) }
        #expect(result?.runs == 2000)
        #expect(elapsed < .seconds(1))
    }

    @Test func whatIfSharesItsLuckWithTheBaseline() {
        let engine = ForecastFixture.engine(tenBooks(minutes: 20))
        let baseline = engine.forecast(seed: 4, runs: 400)
        let same = engine.whatIf(dailyMinutes: nil, readingDays: nil, seed: 4, runs: 400)
        #expect(same.books.map(\.finishDays) == baseline.books.map(\.finishDays))

        let more = engine.whatIf(dailyMinutes: 40, seed: 4, runs: 400)
        let comparison = more.comparison(against: baseline)
        for delta in comparison.books { #expect((delta.medianDaysEarlier ?? 0) >= 0) }
        #expect(comparison.books.contains { ($0.medianDaysEarlier ?? 0) > 0 })
        #expect(comparison.yearMedianChange >= 0)
        // Every future is no later with more minutes, not only the median.
        for (a, b) in zip(more.books, baseline.books) {
            #expect(zip(a.finishDays, b.finishDays).allSatisfy { $0 <= $1 })
        }

        let fewerDays = engine.whatIf(readingDays: [2, 4, 6], seed: 4, runs: 400)
        for (a, b) in zip(fewerDays.books, baseline.books) {
            #expect(zip(a.finishDays, b.finishDays).allSatisfy { $0 >= $1 })
        }
    }

    @Test func restDaysAreNeverReadOn() {
        let data = ForecastFixture.library(reading: [ForecastFixture.item("a", pages: 600)], days: [2, 3, 4, 5, 6])
        let book = ForecastFixture.engine(data).forecast(seed: 8, runs: 400).books[0]
        for index in stride(from: 0, to: book.finishDays.count, by: 7) {
            let offset = Int(book.finishDays[index])
            guard offset != Int(ForecastSimulator.never), let date = book.date(atOffset: offset) else { continue }
            let weekday = ForecastFixture.calendar.component(.weekday, from: date)
            #expect([2, 3, 4, 5, 6].contains(weekday))
        }
    }

    @Test func readingSideBySideSharesTheDays() {
        let reading = [ForecastFixture.item("a", order: 0), ForecastFixture.item("b", order: 1)]
        let focus = ForecastFixture.engine(ForecastFixture.library(reading: reading, mode: .focus)).forecast(seed: 1, runs: 300)
        let side = ForecastFixture.engine(ForecastFixture.library(reading: reading, mode: .sideBySide)).forecast(seed: 1, runs: 300)
        #expect(ForecastTestData.median(focus.books[0]) < ForecastTestData.median(side.books[0]))
        // Together they take about the same total time either way.
        let focusLast = ForecastTestData.median(focus.books[1])
        let sideLast = ForecastTestData.median(side.books[1])
        #expect(abs(focusLast - sideLast) <= max(3, focusLast / 8))
    }

    @Test func anUnconfirmedPageLowersConfidenceAndAllowsAnEarlierFinish() {
        let confirmed = ForecastFixture.library(reading: [ForecastFixture.item("a", confirmed: true)])
        let unsure = ForecastFixture.library(reading: [ForecastFixture.item("a", confirmed: false)])
        let a = ForecastFixture.engine(confirmed).forecast(seed: 1, runs: 400).books[0]
        let b = ForecastFixture.engine(unsure).forecast(seed: 1, runs: 400).books[0]
        #expect(b.positionUncertain && !a.positionUncertain)
        #expect(b.confidence == .low)
        #expect((b.p10Offset ?? 0) <= (a.p10Offset ?? 0))
    }

    @Test func theYearRangeAndGoalOddsBehave() {
        let engine = ForecastFixture.engine(tenBooks())
        let year = engine.forecast(seed: 1, runs: 500).year
        #expect(year.low <= year.median && year.median <= year.high)
        #expect(year.fromLibraryMedian <= year.median)
        #expect(year.includesFuturePicks)
        #expect(year.goal == 12)
        var last = 1.0
        for goal in 0...20 {
            let chance = year.probability(atLeast: goal)
            #expect(chance <= last)
            last = chance
        }
        #expect(year.probability(atLeast: 0) == 1)
        #expect(year.probabilityOfGoal == year.probability(atLeast: 12))
        // Books already finished this year count toward it, and a met goal is certain.
        var data = tenBooks()
        for i in 0..<4 {
            var done = ForecastFixture.item("old\(i)", shelf: .finished)
            done.finishedAt = ForecastFixture.date(2, 1 + i)
            data.items.append(done)
        }
        data.preferences.yearlyGoal = 3
        let later = ForecastFixture.engine(data).forecast(seed: 1, runs: 300).year
        #expect(later.finishedSoFar == 4 && later.low >= 4)
        #expect(later.probabilityOfGoal == 1)
        data.preferences.yearlyGoal = nil
        #expect(ForecastFixture.engine(data).forecast(seed: 1, runs: 100).year.probabilityOfGoal == nil)
    }

    @Test func lateInTheEveningTodayIsLessLikelyToBeTheDay() {
        let data = ForecastFixture.library(reading: [ForecastFixture.item("a", pages: 300, page: 292)])
        let morning = ForecastFixture.engine(data, now: ForecastFixture.date(10, 14, hour: 7)).forecast(seed: 1, runs: 600).books[0]
        let night = ForecastFixture.engine(data, now: ForecastFixture.date(10, 14, hour: 23)).forecast(seed: 1, runs: 600).books[0]
        #expect(morning.probability(byOffset: 0) > night.probability(byOffset: 0))
        // Having already read today's goal leaves little to do.
        var done = data
        done.sessions = [ForecastFixture.session("a", day: 0, minutes: 40, from: 280, to: 292, hour: 8)]
        let readAlready = ForecastFixture.engine(done, now: ForecastFixture.date(10, 14, hour: 9)).forecast(seed: 1, runs: 600).books[0]
        #expect(readAlready.probability(byOffset: 0) < morning.probability(byOffset: 0))
    }

    @Test func randomLibrariesNeverBreakTheInvariants() {
        var random = ForecastTestRandom(seed: 99)
        for round in 0..<12 {
            var reading: [LibraryItem] = []
            var queue: [LibraryItem] = []
            for i in 0..<Int(random.unit() * 4) + 1 {
                let pages = 20 + Int(random.unit() * 900)
                let item = ForecastFixture.item("r\(round)-\(i)", pages: pages, page: Int(random.unit() * Double(pages)), shelf: i == 0 ? .reading : .toRead, order: Double(i))
                if i == 0 { reading.append(item) } else { queue.append(item) }
            }
            let minutes = Int(random.unit() * 90)
            let days: Set<Int> = Set((1...7).filter { _ in random.unit() < 0.6 })
            let data = ForecastFixture.library(reading: reading, queue: queue, minutes: minutes, days: days, mode: random.unit() < 0.5 ? .focus : .sideBySide)
            let result = ForecastFixture.engine(data).forecast(seed: UInt64(round), runs: 150)
            #expect(result.books.count == reading.count + queue.count)
            for book in result.books {
                #expect(book.finishDays == book.finishDays.sorted())
                #expect(book.probability(byOffset: 5000) <= 1)
                if let p10 = book.p10Offset, let p90 = book.p90Offset { #expect(p10 <= p90) }
            }
            #expect(result.year.low <= result.year.high)
        }
    }
}

// MARK: - Planning

struct ForecastPlanningTests {
    func queueData(minutes: Int = 20) -> LeafData {
        let reading = [ForecastFixture.item("a", pages: 300, page: 60)]
        let queue = [ForecastFixture.item("b", pages: 400, shelf: .toRead, order: 1), ForecastFixture.item("c", pages: 250, shelf: .toRead, order: 2)]
        return ForecastFixture.library(reading: reading, queue: queue, minutes: minutes)
    }

    @Test func minutesFoundByInversePlanningLandOnOrBeforeTheTarget() {
        let engine = ForecastFixture.engine(queueData())
        for id in ["a", "b", "c"] {
            for offset in [9, 21, 45, 90] {
                let target = ForecastFixture.day(offset)
                let plan = engine.inversePlan(bookID: id, by: target, runs: 200)
                guard let minutes = plan.minutesPerDay else { continue }
                let finish = Planner.makePlan(engine.planInput(dailyMinutes: minutes), recordDays: 1).book(id)?.finish
                #expect(finish != nil && finish.map { $0 <= target } == true)
                if minutes > 1 {
                    let tooLittle = Planner.makePlan(engine.planInput(dailyMinutes: minutes - 1), recordDays: 1).book(id)?.finish
                    #expect(tooLittle == nil || tooLittle.map { $0 > target } == true)
                }
                if let likely = plan.likelyMinutesPerDay { #expect(likely >= minutes) }
            }
        }
    }

    @Test func inversePlanningSaysWhenATargetCannotBeMet() {
        let engine = ForecastFixture.engine(queueData())
        #expect(engine.inversePlan(bookID: "c", by: ForecastFixture.day(-2)).feasibility == .impossible)
        #expect(engine.inversePlan(bookID: "zzz", by: ForecastFixture.day(30)).minutesPerDay == nil)
        let huge = ForecastFixture.library(reading: [ForecastFixture.item("big", pages: 5000)], minutes: 20)
        let tight = ForecastFixture.engine(huge).inversePlan(bookID: "big", by: ForecastFixture.day(2), runs: 100)
        #expect(tight.feasibility == .impossible && tight.minutesPerDay == nil)
        let noDays = ForecastFixture.engine(ForecastFixture.library(reading: [ForecastFixture.item("a")], days: []))
        #expect(noDays.inversePlan(bookID: "a", by: ForecastFixture.day(30)).feasibility == .impossible)
    }

    @Test func aTargetCloseToTheCurrentPlanIsOnTrackOrAReach() {
        let engine = ForecastFixture.engine(queueData(minutes: 30))
        let far = engine.inversePlan(bookID: "a", by: ForecastFixture.day(60), runs: 200)
        #expect(far.feasibility == .onTrack)
        #expect((far.minutesPerDay ?? 999) <= 30)
        let near = engine.inversePlan(bookID: "c", by: ForecastFixture.day(14), runs: 200)
        #expect(near.feasibility == .reachable || near.feasibility == .stretch)
        #expect((near.minutesPerDay ?? 0) > 30)
    }

    @Test func tonightOnlyNamesTheLeastExtraMinutesThatMoveTheFinishForward() {
        let engine = ForecastFixture.engine(queueData(minutes: 30))
        for id in ["a", "b"] {
            guard let tonight = engine.tonightOnly(bookID: id), let base = engine.plan().book(id)?.finish else {
                Issue.record("no tonight delta for \(id)")
                continue
            }
            #expect(tonight.extraMinutes >= 1 && tonight.daysEarlier >= 1)
            #expect(tonight.newFinish < base)
            func finish(_ extra: Int) -> Date? {
                let moved = engine.advanced(byMinutes: Double(extra))
                return engine.plan(reading: moved.reading, queue: moved.queue).book(id)?.finish
            }
            #expect(finish(tonight.extraMinutes) == tonight.newFinish)
            if tonight.extraMinutes > 1 { #expect((finish(tonight.extraMinutes - 1) ?? .distantFuture) >= base) }
        }
    }

    @Test func booksByYearEndAreSolvedAndShortfallsAreReported() {
        let engine = ForecastFixture.engine(queueData(minutes: 20))
        let plan = engine.inversePlan(booksThisYear: 3, runs: 200)
        #expect(plan.booksShort == 0)
        guard let minutes = plan.minutesPerDay else {
            Issue.record("three books by year end should be solvable")
            return
        }
        let yearEnd = ForecastFixture.date(12, 31)
        #expect(Planner.makePlan(engine.planInput(dailyMinutes: minutes), recordDays: 1).finishedCount(onOrBefore: yearEnd) >= 3)
        let greedy = engine.inversePlan(booksThisYear: 10, runs: 100)
        #expect(greedy.booksShort == 7 && greedy.feasibility == .impossible)
        #expect(engine.inversePlan(booksThisYear: 0, runs: 100).minutesPerDay == 0)
    }

    private func randomQueue(seed: UInt64) -> LeafData {
        var random = ForecastTestRandom(seed: seed)
        let genres = ["fantasy", "mystery", "literary"]
        let reading = [ForecastFixture.item("now", pages: 300, page: Int(random.unit() * 200))]
        let queue = (0..<Int(random.unit() * 4) + 5).map { i in
            ForecastFixture.item("q\(i)", pages: 90 + Int(random.unit() * 800), shelf: .toRead, order: Double(i + 1), genres: [genres[Int(random.unit() * 3) % 3]])
        }
        return ForecastFixture.library(reading: reading, queue: queue, minutes: 15 + Int(random.unit() * 45))
    }

    @Test func aSmarterOrderNeverFinishesFewerBooksByTheTarget() {
        for seed in 1...12 {
            let engine = ForecastFixture.engine(randomQueue(seed: UInt64(seed)))
            for offset in [20, 45, 90] {
                let target = ForecastFixture.day(offset)
                let suggestion = engine.smartOrder(goal: .mostFinished(by: target), seed: 3, runs: 200)
                #expect(Set(suggestion.suggestedOrder) == Set(suggestion.currentOrder) && suggestion.suggestedOrder.count == suggestion.currentOrder.count)
                let byID = Dictionary(uniqueKeysWithValues: engine.queue.map { ($0.id, $0) })
                let reordered = suggestion.suggestedOrder.compactMap { byID[$0] }
                let before = engine.plan().finishedCount(onOrBefore: target)
                let after = engine.plan(queue: reordered).finishedCount(onOrBefore: target)
                #expect(after >= before)
                #expect((suggestion.finishedByTargetSuggested ?? 0) >= (suggestion.finishedByTargetCurrent ?? 0))
                if suggestion.isChange { #expect(!suggestion.changes.isEmpty && !suggestion.deltas.isEmpty) }
            }
        }
    }

    @Test func shortestFirstHelpsWhenALongBookBlocksTheQueue() {
        let reading = [ForecastFixture.item("now", pages: 200, page: 150)]
        let queue = [
            ForecastFixture.item("long", pages: 1100, shelf: .toRead, order: 1),
            ForecastFixture.item("s1", pages: 120, shelf: .toRead, order: 2),
            ForecastFixture.item("s2", pages: 150, shelf: .toRead, order: 3),
        ]
        let engine = ForecastFixture.engine(ForecastFixture.library(reading: reading, queue: queue, minutes: 30))
        let target = ForecastFixture.day(20)
        let suggestion = engine.smartOrder(goal: .mostFinished(by: target), seed: 1, runs: 300)
        #expect(suggestion.suggestedOrder.last == "long")
        #expect((suggestion.finishedByTargetSuggested ?? 0) > (suggestion.finishedByTargetCurrent ?? 99))
        let shorter = suggestion.deltas.first { $0.bookID == "s1" }
        #expect((shorter?.daysEarlier ?? 0) > 0)
    }

    @Test func genresAlternateWhenTheyCan() {
        let genres = ["fantasy", "fantasy", "mystery", "mystery", "literary", "literary"]
        let queue = genres.enumerated().map { ForecastFixture.item("q\($0.offset)", pages: 300, shelf: .toRead, order: Double($0.offset), genres: [$0.element]) }
        let engine = ForecastFixture.engine(ForecastFixture.library(reading: [ForecastFixture.item("now", genres: ["fantasy"])], queue: queue))
        let suggestion = engine.smartOrder(goal: .alternateGenres, runs: 100)
        let byID = Dictionary(uniqueKeysWithValues: queue.map { ($0.id, $0.book.genres[0]) })
        let order = suggestion.suggestedOrder.compactMap { byID[$0] }
        #expect(order.count == 6 && Set(suggestion.suggestedOrder).count == 6)
        #expect(zip(order, order.dropFirst()).allSatisfy { $0 != $1 })
        #expect(order.first != "fantasy")
        #expect(suggestion.changes.allSatisfy { $0.reason == .differentGenre })
    }

    @Test func aShortReadFollowsAHeavyOne() {
        let specs: [(String, Int, String)] = [("heavy", 1200, "fantasy"), ("a", 300, "fantasy"), ("b", 300, "mystery"), ("tiny", 80, "poetry"), ("c", 300, "fantasy")]
        let queue = specs.enumerated().map { ForecastFixture.item($0.element.0, pages: $0.element.1, shelf: .toRead, order: Double($0.offset), genres: [$0.element.2]) }
        let engine = ForecastFixture.engine(ForecastFixture.library(reading: [ForecastFixture.item("now")], queue: queue))
        let suggestion = engine.smartOrder(goal: .palateCleanser, runs: 100)
        #expect(suggestion.suggestedOrder == ["heavy", "tiny", "a", "b", "c"])
        #expect(suggestion.changes.map(\.bookID).contains("tiny"))
    }

    @Test func missedDaysAreHandledByTheReadersCatchUpMode() {
        let missed: Set<Int> = [-4, -3, -2, -1]
        let forgive = ForecastFixture.engine(ForecastTestData.steadyReader(days: -30...(-1), skipping: missed, catchUp: .forgive)).catchUp()
        #expect(forgive.missedDays == 4 && forgive.missedMinutes == 120)
        #expect(forgive.action == .nothingToMakeUp)
        #expect(forgive.lateDays > 0)

        let shift = ForecastFixture.engine(ForecastTestData.steadyReader(days: -30...(-1), skipping: missed, catchUp: .shift)).catchUp()
        if case .datesMoved(let days) = shift.action { #expect(days == shift.lateDays && days > 0) } else { Issue.record("shift should report moved dates") }
        #expect(shift.adjustedFinish == shift.currentFinish)

        let compress = ForecastFixture.engine(ForecastTestData.steadyReader(days: -30...(-1), skipping: missed, catchUp: .compress)).catchUp()
        if case .addMinutes(let perDay, let forDays) = compress.action {
            #expect(perDay >= 1 && perDay <= 15)
            #expect(forDays >= 1 && Double(perDay * forDays) >= 100)
        } else {
            Issue.record("compress should ask for a little extra")
        }
        #expect(compress.adjustedDailyMinutes > 30)
        if let adjusted = compress.adjustedFinish, let current = compress.currentFinish { #expect(adjusted <= current) }
        if let baseline = compress.baselineFinish, let current = compress.currentFinish { #expect(baseline <= current) }
    }

    @Test func noMissedDaysMeansNothingToMakeUp() {
        for mode in CatchUpMode.allCases {
            let advice = ForecastFixture.engine(ForecastTestData.steadyReader(days: -30...(-1), catchUp: mode)).catchUp()
            #expect(advice.missedDays == 0 && advice.action == .nothingToMakeUp)
        }
    }

    @Test func booksThatWentQuietAreOfferedARest() {
        var data = ForecastFixture.library(reading: [
            ForecastFixture.item("quiet", order: 0), ForecastFixture.item("busy", order: 1), ForecastFixture.item("nearly", pages: 300, page: 280, order: 2),
        ], queue: [ForecastFixture.item("waiting", shelf: .toRead, order: 3)])
        data.items.append(ForecastFixture.item("rested", shelf: .paused, order: 0))
        data.sessions = [
            ForecastFixture.session("quiet", day: -20, minutes: 20, from: 0, to: 18),
            ForecastFixture.session("busy", day: -3, minutes: 20, from: 0, to: 18),
            ForecastFixture.session("nearly", day: -18, minutes: 20, from: 260, to: 280),
        ]
        let engine = ForecastFixture.engine(data)
        let stalled = engine.stalledBooks()
        #expect(stalled.map(\.bookID) == ["quiet", "nearly"])
        #expect(stalled[0].daysIdle == 20 && stalled[0].suggestion == .setAside)
        #expect(stalled[1].suggestion == .almostThere)
        #expect(engine.stalledBooks(thresholdDays: 25).isEmpty)
        #expect(engine.stalledBooks(thresholdDays: 2).map(\.bookID).contains("busy"))
        var live = data
        live.activeSession = ActiveSession(bookID: "quiet", startedAt: ForecastFixture.now, startPage: 18, origin: .phone)
        #expect(!ForecastFixture.engine(live).stalledBooks().map(\.bookID).contains("quiet"))
    }
}

// MARK: - Narration

struct ForecastNarratorTests {
    var narrator: ForecastNarrator { ForecastNarrator(now: ForecastFixture.now, calendar: ForecastFixture.calendar) }

    @Test func aBookRangeReadsLikeAPerson() {
        // Saturday, Sunday and Tuesday are 3, 4 and 6 days after Wednesday.
        let days: [Int32] = [Int32](repeating: 3, count: 10) + [Int32](repeating: 4, count: 45) + [Int32](repeating: 5, count: 34) + [Int32](repeating: 6, count: 11)
        let forecast = ForecastTestData.forecast(days)
        #expect(narrator.bookSentence(forecast) == "Probably done Sunday, between Saturday and Tuesday.")
        #expect(narrator.shortSentence(forecast) == "Probably done Sunday.")
    }

    @Test func farDatesUseTheMonthAndDay() {
        let forecast = ForecastTestData.forecast([Int32](repeating: 20, count: 100))
        #expect(narrator.bookSentence(forecast) == "Probably done Nov 3.")
        let wide = ForecastTestData.forecast([Int32](repeating: 12, count: 10) + [Int32](repeating: 20, count: 75) + [Int32](repeating: 30, count: 15))
        #expect(narrator.bookSentence(wide) == "Probably done Nov 3, between Oct 26 and Nov 13.")
        #expect(narrator.day(ForecastFixture.day(0)) == "today" && narrator.day(ForecastFixture.day(1)) == "tomorrow")
        #expect(narrator.day(ForecastFixture.day(6)) == "Tuesday" && narrator.day(ForecastFixture.day(7)) == "Oct 21")
    }

    @Test func uncertainAndMissingForecastsAreHonest() {
        let unsure = ForecastTestData.forecast([Int32](repeating: 4, count: 100), confidence: .low)
        #expect(narrator.bookSentence(unsure) == "Too early to say. Somewhere around Sunday.")
        let never = ForecastTestData.forecast([Int32](repeating: ForecastSimulator.never, count: 100))
        #expect(narrator.bookSentence(never) == "Not in sight yet at this pace.")
    }

    @Test func theYearReadsAsARange() {
        let year = YearForecast(year: 2026, finishedSoFar: 10, low: 18, median: 24, high: 29, fromLibraryMedian: 14, goal: nil, probabilityOfGoal: nil, includesFuturePicks: true, confidence: .medium, totals: [])
        #expect(narrator.yearSentence(year) == "On track for 24 books, somewhere between 18 and 29.")
        var behind = year
        behind.goal = 30
        behind.probabilityOfGoal = 0.1
        #expect(narrator.yearSentence(behind) == "Looking like about 24 books, somewhere between 18 and 29.")
        #expect(narrator.goalSentence(behind)?.contains("long shot") == true)
        #expect(narrator.goalSentence(year) == nil)
    }

    @Test func tonightAndChanceSentences() {
        let tonight = ForecastTonight(extraMinutes: 6, newFinish: ForecastFixture.day(3), daysEarlier: 1)
        #expect(narrator.tonightSentence(tonight) == "Six more minutes tonight makes it Saturday.")
        #expect(narrator.tonightSentence(ForecastTonight(extraMinutes: 1, newFinish: ForecastFixture.day(1), daysEarlier: 1)) == "One more minute tonight makes it tomorrow.")
        let forecast = ForecastTestData.forecast([Int32](repeating: 2, count: 30) + [Int32](repeating: 8, count: 70))
        #expect(narrator.chanceSentence(forecast, by: ForecastFixture.day(4)) == "About a 30 percent chance of finishing by Sunday.")
        #expect(narrator.chanceSentence(forecast, by: ForecastFixture.day(9)) == "Very likely by Oct 23.")
    }

    @Test func backtestsAreReportedPlainly() {
        func checkpoints(_ n: Int, covered: Int) -> [BacktestCheckpoint] {
            (0..<n).map { i in
                BacktestCheckpoint(bookID: "b\(i % 5)", asOf: ForecastFixture.now, predictedMedian: 10, predictedLow: 8, predictedHigh: 12, actual: i < covered ? 10 : 30, percentile: 0.5)
            }
        }
        let good = BacktestReport(checkpoints: checkpoints(50, covered: 39), nominalCoverage: 0.8, bookCount: 17)
        #expect(narrator.backtestSentence(good) == "Your 80 percent ranges have been right 78 percent of the time.")
        let thin = BacktestReport(checkpoints: checkpoints(3, covered: 3), nominalCoverage: 0.8, bookCount: 1)
        #expect(narrator.backtestSentence(thin) == "Not enough finished books yet to check how well these ranges hold up.")
    }

    @Test func nothingWeSayShoutsOrGuilts() {
        var data = ForecastTestData.steadyReader(days: -30...(-1), skipping: [-3, -2, -1], goal: 24, catchUp: .compress)
        data.items.append(ForecastFixture.item("b", shelf: .toRead, order: 1))
        data.items.append(ForecastFixture.item("c", shelf: .toRead, order: 2))
        let engine = ForecastFixture.engine(data)
        let result = engine.forecast(seed: 1, runs: 200)
        var lines: [String] = []
        for book in result.books {
            lines += [narrator.bookSentence(book), narrator.shortSentence(book), narrator.chanceSentence(book, by: ForecastFixture.day(30))]
        }
        lines.append(narrator.yearSentence(result.year))
        lines += narrator.goalSentence(result.year).map { [$0] } ?? []
        let inverse = engine.inversePlan(bookID: "a", by: ForecastFixture.day(20), runs: 100)
        lines.append(narrator.inverseSentence(inverse))
        if let tonight = inverse.tonight { lines.append(narrator.tonightSentence(tonight)) }
        lines.append(narrator.yearPlanSentence(engine.inversePlan(booksThisYear: 30, runs: 100)))
        lines.append(narrator.catchUpSentence(engine.catchUp()))
        lines.append(narrator.orderSentence(engine.smartOrder(goal: .alternateGenres, runs: 100)))
        lines.append(narrator.backtestSentence(engine.backtest()))
        lines.append(narrator.stallSentence(StalledBook(bookID: "a", title: "Dune", daysIdle: 19, lastTouched: nil, percentRead: 20, suggestion: .setAside)))
        lines.append(narrator.stallSentence(StalledBook(bookID: "a", title: "Dune", daysIdle: 19, lastTouched: nil, percentRead: 90, suggestion: .almostThere)))
        #expect(lines.count > 10)
        for line in lines {
            #expect(!line.contains("!"), "\(line)")
            #expect(!line.contains("'"), "\(line)")
            #expect(!line.lowercased().contains("behind schedule") && !line.lowercased().contains("failed") && !line.lowercased().contains("lazy"), "\(line)")
            #expect(line.last == "." || line.last == "?", "\(line)")
        }
    }
}

// MARK: - Calibration

struct ForecastCalibrationTests {
    /// 80 percent ranges should cover somewhere near 0.65 to 0.92. Regular readers get slightly conservative (wide)
    /// ranges and erratic ones come out a little narrow, so the bands are the measured ones with room for the seeds.
    /// Finishing dates are whole days, so a narrow range (a steady reader) lands on its end days more often than its
    /// share; `smoothed` removes that rounding.
    private func check(_ persona: ForecastPersona, seeds: Int, minimum: Int) {
        let checkpoints = ForecastTestData.pooled(persona, seeds: seeds)
        #expect(checkpoints.count >= minimum)
        let coverage = ForecastTestData.coverage(checkpoints)
        let smoothed = ForecastTestData.smoothed(checkpoints)
        #expect(coverage >= 0.65 && coverage <= 0.97, "\(persona.name) coverage \(coverage)")
        #expect(smoothed >= 0.62 && smoothed <= 0.95, "\(persona.name) smoothed \(smoothed)")
        let mean = Double(checkpoints.reduce(0) { $0 + abs($1.actual - $1.predictedMedian) }) / Double(checkpoints.count)
        #expect(mean < 8, "\(persona.name) mean error \(mean)")
    }

    @Test func steadyReader() { check(.steady, seeds: 4, minimum: 80) }
    @Test func weekendBinger() { check(.weekendBinger, seeds: 4, minimum: 80) }
    @Test func erraticReader() { check(.erratic, seeds: 5, minimum: 40) }
    @Test func slowReader() { check(.slow, seeds: 6, minimum: 40) }

    @Test func brandNewReadersAreWideButHonest() {
        var all: [BacktestCheckpoint] = []
        for k in 0..<14 {
            var persona = ForecastPersona.slow
            persona.seed = 500 &+ UInt64(k) &* 17
            persona.days = 80
            persona.pages = 150...260
            persona.testWPM = 238
            let (data, now) = persona.build()
            all += ForecastEngine(data: data, now: now, calendar: ForecastFixture.calendar).backtest().checkpoints
        }
        #expect(all.count >= 15)
        let coverage = ForecastTestData.coverage(all)
        #expect(coverage >= 0.6 && coverage <= 0.97, "new reader coverage \(coverage)")
    }

    @Test func theReportIsPlainNumbersAndRepeatable() {
        var persona = ForecastPersona.steady
        persona.days = 200
        let (data, now) = persona.build()
        let engine = ForecastEngine(data: data, now: now, calendar: ForecastFixture.calendar)
        let a = engine.backtest()
        let b = engine.backtest()
        #expect(a.checkpoints == b.checkpoints)
        #expect(a.sampleSize > 10 && a.bookCount >= 4)
        #expect(a.nominalCoverage == 0.8)
        #expect((a.coverage ?? -1) >= 0 && (a.coverage ?? 2) <= 1)
        #expect((a.meanAbsoluteErrorDays ?? -1) >= 0)
        #expect(a.checkpoints.allSatisfy { $0.predictedLow <= $0.predictedMedian && $0.predictedMedian <= $0.predictedHigh && $0.actual >= 0 })
        #expect(a.quality >= .rough)
        // The past is replayed with what was known then: nothing after a checkpoint leaks into it.
        #expect(a.checkpoints.allSatisfy { $0.asOf < now })
    }
}
