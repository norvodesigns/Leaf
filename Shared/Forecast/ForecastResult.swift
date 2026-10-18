import Foundation

/// How much to trust a forecast. Text-free on purpose: screens decide how to show it.
enum ForecastConfidence: Int, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: ForecastConfidence, rhs: ForecastConfidence) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A point on the fan chart: the chance a book is done by a date.
struct ForecastCurvePoint: Hashable, Sendable {
    var date: Date
    var probability: Double
}

/// A day offset that stands for "not within the horizon".
private let neverOffset = Int(ForecastSimulator.never)

enum ForecastQuantile {
    /// The share of simulated futures that finished before `day`, counting half of those that finished on it.
    static func percentile(of day: Int, in sorted: [Int32]) -> Double {
        guard !sorted.isEmpty else { return 0.5 }
        func count(_ predicate: (Int) -> Bool) -> Int {
            var low = 0
            var high = sorted.count
            while low < high {
                let mid = (low + high) / 2
                if predicate(Int(sorted[mid])) { low = mid + 1 } else { high = mid }
            }
            return low
        }
        let before = count { $0 < day }
        let upTo = count { $0 <= day }
        return (Double(before) + Double(upTo)) / 2 / Double(sorted.count)
    }

    /// The value at quantile `q` of a sorted list of finish days, or nil when it is "not within the horizon".
    static func offset(sorted: [Int32], _ q: Double) -> Int? {
        guard !sorted.isEmpty else { return nil }
        let index = min(sorted.count - 1, max(0, Int((q * Double(sorted.count)).rounded(.up)) - 1))
        let value = Int(sorted[index])
        return value == neverOffset ? nil : value
    }
}

/// The forecast for one book: the distribution of its finish day over every simulated future, plus the plain
/// deterministic date from `Planner` for comparison.
struct BookForecast: Identifiable, Sendable {
    let id: String
    var isReading: Bool
    /// Expected minutes left at the reader's own pace.
    var remainingMinutes: Double
    /// Where `Planner` puts the finish with the reader's words-per-minute setting and every chosen day read in full.
    var deterministicFinish: Date?
    var confidence: ForecastConfidence
    /// The reader has not said where they are in this book, so the forecast allows for them being further on.
    var positionUncertain: Bool
    /// Usable sessions on this book so far.
    var sessions: Int
    /// Days from `origin` to the finish in each simulated future, sorted; `Int32.max` means not within the horizon.
    var finishDays: [Int32]
    /// Start of today in the reader's calendar.
    var origin: Date
    var calendar: Calendar

    var runs: Int { finishDays.count }

    /// Days from today to the finish at a quantile (0.5 is the median), or nil when that many futures never finish it.
    func dayOffset(forQuantile q: Double) -> Int? {
        ForecastQuantile.offset(sorted: finishDays, q)
    }

    func date(atOffset offset: Int) -> Date? {
        calendar.date(byAdding: .day, value: offset, to: origin)
    }

    func date(forQuantile q: Double) -> Date? {
        dayOffset(forQuantile: q).flatMap { date(atOffset: $0) }
    }

    var medianOffset: Int? { dayOffset(forQuantile: 0.5) }
    var p10Offset: Int? { dayOffset(forQuantile: 0.1) }
    var p90Offset: Int? { dayOffset(forQuantile: 0.9) }
    var median: Date? { date(forQuantile: 0.5) }
    var p10: Date? { date(forQuantile: 0.1) }
    var p90: Date? { date(forQuantile: 0.9) }

    /// Share of futures in which the book is not finished within the horizon.
    var neverProbability: Double {
        guard !finishDays.isEmpty else { return 1 }
        return 1 - probability(byOffset: neverOffset - 1)
    }

    /// Chance the book is finished by the end of `offset` days from today.
    func probability(byOffset offset: Int) -> Double {
        guard !finishDays.isEmpty, offset >= 0 else { return 0 }
        var low = 0
        var high = finishDays.count
        while low < high {
            let mid = (low + high) / 2
            if Int(finishDays[mid]) <= offset { low = mid + 1 } else { high = mid }
        }
        return Double(low) / Double(finishDays.count)
    }

    /// Chance the book is finished by the end of `date`. Never decreases as the date moves later.
    func probability(by date: Date) -> Double {
        let target = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: origin, to: target).day ?? 0
        return probability(byOffset: offset)
    }

    /// The cumulative curve for a fan chart, from the first plausible day to the last, in at most `points` steps.
    func curve(points: Int = 24) -> [ForecastCurvePoint] {
        guard let first = dayOffset(forQuantile: 0.02) else { return [] }
        let last = dayOffset(forQuantile: 0.98) ?? finishDays.filter { Int($0) != neverOffset }.map { Int($0) }.max() ?? first
        let count = max(2, points)
        let span = max(1, last - first)
        var result: [ForecastCurvePoint] = []
        var previous = -1
        for step in 0..<count {
            let offset = first + Int((Double(span) * Double(step) / Double(count - 1)).rounded())
            guard offset != previous, let date = date(atOffset: offset) else { continue }
            previous = offset
            result.append(ForecastCurvePoint(date: date, probability: probability(byOffset: offset)))
        }
        return result
    }
}

/// Books finished this calendar year, as a range.
struct YearForecast: Sendable {
    var year: Int
    /// Books already finished this year.
    var finishedSoFar: Int
    /// Total for the year by December 31: the 10th, 50th and 90th percentile over the simulated futures.
    var low: Int
    var median: Int
    var high: Int
    /// The median counting only books already on a shelf.
    var fromLibraryMedian: Int
    var goal: Int?
    /// Chance of reaching the goal, when there is one.
    var probabilityOfGoal: Double?
    /// Whether the range assumes the reader will pick up more books of the usual length once the shelf is read.
    var includesFuturePicks: Bool
    var confidence: ForecastConfidence
    /// Books finished by year end in each simulated future (this year's earlier finishes included), sorted.
    var totals: [Int32]

    /// Chance of finishing at least `books` this year.
    func probability(atLeast books: Int) -> Double {
        guard !totals.isEmpty else { return finishedSoFar >= books ? 1 : 0 }
        var low = 0
        var high = totals.count
        while low < high {
            let mid = (low + high) / 2
            if Int(totals[mid]) < books { low = mid + 1 } else { high = mid }
        }
        return Double(totals.count - low) / Double(totals.count)
    }
}

/// The facts the forecast rested on, so a screen can say "based on 14 sessions" without recomputing anything.
struct ForecastAssumptions: Sendable {
    var dailyMinutes: Int
    var readingDays: Set<Int>
    var planMode: PlanMode
    /// The reader's overall expected speed in words per minute.
    var paceWPM: Double
    /// Reading days to expect in a week, given how often they have actually read.
    var expectedDaysPerWeek: Double
    /// Minutes on a typical day they read.
    var typicalMinutes: Double
    var sessionCount: Int
    var historyDays: Int
    var fastestDaypart: Daypart?
}

/// How one book's forecast moved between two results. Positive numbers mean sooner.
struct ForecastBookDelta: Hashable, Sendable {
    var bookID: String
    var oldMedian: Date?
    var newMedian: Date?
    var medianDaysEarlier: Int?
    var p10DaysEarlier: Int?
    var p90DaysEarlier: Int?
}

struct ForecastComparison: Sendable {
    var books: [ForecastBookDelta]
    /// New year median minus old year median.
    var yearMedianChange: Int
    var goalProbabilityChange: Double?

    func delta(for id: String) -> ForecastBookDelta? { books.first { $0.bookID == id } }
}

/// The whole forecast: a distribution for every book still to read, the year, and the plain plan beside them.
struct ForecastResult: Sendable {
    var generatedAt: Date
    var seed: UInt64
    var runs: Int
    /// Reading shelf then queue, in plan order. Paused and finished books are not here.
    var books: [BookForecast]
    var year: YearForecast
    /// The deterministic plan from `Planner`, for comparison.
    var plan: ReadingPlan
    var assumptions: ForecastAssumptions

    func book(_ id: String) -> BookForecast? { books.first { $0.id == id } }

    /// How this result differs from `baseline`, which should come from the same engine and seed so the difference is
    /// the change you made and not luck.
    func comparison(against baseline: ForecastResult) -> ForecastComparison {
        let deltas: [ForecastBookDelta] = books.compactMap { now in
            guard let before = baseline.book(now.id) else { return nil }
            func earlier(_ old: Int?, _ new: Int?) -> Int? {
                guard let old, let new else { return nil }
                return old - new
            }
            return ForecastBookDelta(
                bookID: now.id,
                oldMedian: before.median,
                newMedian: now.median,
                medianDaysEarlier: earlier(before.medianOffset, now.medianOffset),
                p10DaysEarlier: earlier(before.p10Offset, now.p10Offset),
                p90DaysEarlier: earlier(before.p90Offset, now.p90Offset)
            )
        }
        let goalChange: Double? = {
            guard let new = year.probabilityOfGoal, let old = baseline.year.probabilityOfGoal else { return nil }
            return new - old
        }()
        return ForecastComparison(books: deltas, yearMedianChange: year.median - baseline.year.median, goalProbabilityChange: goalChange)
    }
}
