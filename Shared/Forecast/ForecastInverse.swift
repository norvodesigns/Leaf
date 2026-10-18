import Foundation

/// How reachable a target is at the reader's current pace of life.
enum ForecastFeasibility: Hashable, Sendable {
    /// Their current daily minutes already get there.
    case onTrack
    /// Needs more time each day, but a reasonable amount.
    case reachable
    /// Needs a lot (over three hours a day), though not impossible.
    case stretch
    /// Cannot be done: the date has passed, there are no reading days, or it would take over eight hours a day.
    case impossible
}

/// "Six more minutes tonight makes it Saturday."
struct ForecastTonight: Hashable, Sendable {
    var extraMinutes: Int
    var newFinish: Date
    var daysEarlier: Int
}

/// The minutes a day a book needs to be finished by a date.
struct ForecastInversePlan: Sendable {
    var bookID: String
    var target: Date
    var currentMinutes: Int
    /// The fewest whole minutes a day (on the chosen reading days) for `Planner`'s plan to finish on or before the
    /// target, or nil when no amount works. Can be below `currentMinutes`.
    var minutesPerDay: Int?
    /// Minutes a day for at least `confidence` chance of being done by then, once real life is allowed to interfere.
    var likelyMinutesPerDay: Int?
    var confidence: Double
    var feasibility: ForecastFeasibility
    /// Where the plan puts the finish at the current minutes.
    var finishAtCurrent: Date?
    var tonight: ForecastTonight?
}

/// The minutes a day needed to finish a number of books this year.
struct ForecastYearPlan: Sendable {
    var target: Int
    var year: Int
    var finishedSoFar: Int
    /// Books on the Reading shelf and in the queue.
    var booksAvailable: Int
    /// How many more books than the shelves hold the target needs (the reader has to add some).
    var booksShort: Int
    var currentMinutes: Int
    /// Minutes a day for the plan to finish the target (or, with `booksShort`, every book on the shelves) by December 31.
    /// Zero when the target is already met.
    var minutesPerDay: Int?
    var likelyMinutesPerDay: Int?
    var confidence: Double
    var feasibility: ForecastFeasibility
}

extension ForecastEngine {
    static let maxPlannedMinutes = 480
    static let stretchMinutes = 180

    // MARK: Helpers

    /// The shelves as they would stand after reading `minutes` more, taken from the front of the queue at the plan's
    /// words-per-minute. This is how "extra tonight" and "catch up" are fed to `Planner`, which only knows a fixed
    /// amount per day.
    func advanced(byMinutes minutes: Double) -> (reading: [LibraryItem], queue: [LibraryItem]) {
        let wpm = max(data.preferences.wpm, 40)
        var remaining = max(0, minutes)
        func advance(_ item: LibraryItem) -> LibraryItem {
            guard remaining > 0 else { return item }
            var copy = item
            let need = item.minutesLeft(atWPM: wpm)
            if need <= remaining + 1e-9 {
                copy.currentPage = item.book.pages
                remaining -= need
            } else if need > 0 {
                let pagesRead = Int((remaining * wpm / item.book.wordsPerPage).rounded(.up))
                copy.currentPage = min(item.book.pages, item.currentPage + pagesRead)
                remaining = 0
            }
            return copy
        }
        let advancedReading = reading.map(advance)
        let advancedQueue = queue.map(advance)
        return (advancedReading, advancedQueue)
    }

    /// Smallest `value` in `1...upper` for which `works` holds, assuming it holds from some point on. Checks a step
    /// below the answer in case the planner's day rounding makes it slightly uneven.
    static func smallest(upTo upper: Int, works: (Int) -> Bool) -> Int? {
        guard works(upper) else { return nil }
        var low = 1
        var high = upper
        while low < high {
            let mid = (low + high) / 2
            if works(mid) { high = mid } else { low = mid + 1 }
        }
        while low > 1 && works(low - 1) { low -= 1 }
        return low
    }

    private func feasibility(needed: Int?, current: Int) -> ForecastFeasibility {
        guard let needed else { return .impossible }
        if needed <= current { return .onTrack }
        return needed <= ForecastEngine.stretchMinutes ? .reachable : .stretch
    }

    private var yearEndDate: Date {
        let year = calendar.component(.year, from: now)
        return calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? now
    }

    // MARK: A book by a date

    /// Solves for the minutes a day that finish `bookID` by `target`: exactly, by bisection over `Planner` (so the
    /// answer can be checked against the plan the app already shows), and as a safer figure that allows for missed days
    /// and slow patches (a bisection over the simulation, using one seed so the search is smooth).
    func inversePlan(bookID: String, by target: Date, confidence: Double = 0.8, seed: UInt64 = 1, runs: Int = 600) -> ForecastInversePlan {
        let current = data.preferences.dailyMinutes
        let targetDay = calendar.startOfDay(for: target)
        var result = ForecastInversePlan(
            bookID: bookID, target: target, currentMinutes: current, minutesPerDay: nil, likelyMinutesPerDay: nil,
            confidence: confidence, feasibility: .impossible, finishAtCurrent: nil, tonight: nil
        )
        let baseline = plan()
        guard let planned = baseline.book(bookID) else { return result }
        result.finishAtCurrent = planned.finish
        guard targetDay >= calendar.startOfDay(for: now), !data.preferences.readingDays.isEmpty else { return result }

        func finishesInTime(_ minutes: Int) -> Bool {
            guard let finish = plan(dailyMinutes: minutes).book(bookID)?.finish else { return false }
            return calendar.startOfDay(for: finish) <= targetDay
        }
        let needed = ForecastEngine.smallest(upTo: ForecastEngine.maxPlannedMinutes, works: finishesInTime)
        result.minutesPerDay = needed
        result.feasibility = feasibility(needed: needed, current: current)
        result.tonight = tonightOnly(bookID: bookID)

        // With real life in the mix: the most reading days are not read, so a safer figure is needed.
        let ordered = reading + queue
        if let index = ordered.firstIndex(where: { $0.id == bookID }) {
            let kept = data.preferences.planMode == .focus ? index + 1 : ordered.count
            let readingKept = Array(reading.prefix(kept))
            let queueKept = Array(queue.prefix(max(0, kept - reading.count)))
            let offset = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: targetDay).day ?? 0)
            func likelyEnough(_ minutes: Int) -> Bool {
                let sc = scenario(dailyMinutes: minutes, reading: readingKept, queue: queueKept, includeFuturePicks: false)
                let sim = ForecastSimulator.run(sc, seed: seed, runs: runs)
                let finishDays = sim.finishDays[index]
                var low = 0
                var high = finishDays.count
                while low < high {
                    let mid = (low + high) / 2
                    if Int(finishDays[mid]) <= offset { low = mid + 1 } else { high = mid }
                }
                return Double(low) / Double(max(1, finishDays.count)) >= confidence
            }
            result.likelyMinutesPerDay = ForecastEngine.smallest(upTo: ForecastEngine.maxPlannedMinutes, works: likelyEnough)
        }
        return result
    }

    /// The least extra reading tonight, on top of today's plan, that brings the book's finish a day or more forward.
    func tonightOnly(bookID: String, maxExtra: Int = 180) -> ForecastTonight? {
        guard let base = plan().book(bookID)?.finish else { return nil }
        let baseDay = calendar.startOfDay(for: base)
        guard baseDay > calendar.startOfDay(for: now) else { return nil }
        func finish(afterExtra extra: Int) -> Date? {
            let moved = advanced(byMinutes: Double(extra))
            return plan(reading: moved.reading, queue: moved.queue).book(bookID)?.finish
        }
        func earlier(_ extra: Int) -> Bool {
            guard let date = finish(afterExtra: extra) else { return false }
            return calendar.startOfDay(for: date) < baseDay
        }
        guard let extra = ForecastEngine.smallest(upTo: maxExtra, works: earlier), let date = finish(afterExtra: extra) else { return nil }
        let saved = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: baseDay).day ?? 0
        return ForecastTonight(extraMinutes: extra, newFinish: date, daysEarlier: saved)
    }

    // MARK: A number of books by year end

    func inversePlan(booksThisYear target: Int, confidence: Double = 0.8, seed: UInt64 = 1, runs: Int = 600) -> ForecastYearPlan {
        let year = calendar.component(.year, from: now)
        let finished = ReadingStats.booksFinished(in: year, items: data.items, calendar: calendar)
        let available = reading.count + queue.count
        let reachableTarget = min(target, finished + available)
        let current = data.preferences.dailyMinutes
        var result = ForecastYearPlan(
            target: target, year: year, finishedSoFar: finished, booksAvailable: available,
            booksShort: max(0, target - finished - available), currentMinutes: current,
            minutesPerDay: nil, likelyMinutesPerDay: nil, confidence: confidence, feasibility: .impossible
        )
        if reachableTarget <= finished {
            result.minutesPerDay = 0
            result.feasibility = target <= finished ? .onTrack : .impossible
            if target <= finished { result.likelyMinutesPerDay = 0 }
            return result
        }
        guard !data.preferences.readingDays.isEmpty else { return result }
        let yearEnd = calendar.startOfDay(for: yearEndDate)
        let needed = ForecastEngine.smallest(upTo: ForecastEngine.maxPlannedMinutes) { minutes in
            finished + plan(dailyMinutes: minutes).finishedCount(onOrBefore: yearEnd) >= reachableTarget
        }
        result.minutesPerDay = needed
        result.feasibility = result.booksShort > 0 ? .impossible : feasibility(needed: needed, current: current)
        result.likelyMinutesPerDay = ForecastEngine.smallest(upTo: ForecastEngine.maxPlannedMinutes) { minutes in
            let sc = scenario(dailyMinutes: minutes)
            let sim = ForecastSimulator.run(sc, seed: seed, runs: runs)
            let totals = sim.yearTotals.map { Int($0) + finished }
            return Double(totals.filter { $0 >= target }.count) / Double(max(1, totals.count)) >= confidence
        }
        return result
    }
}
