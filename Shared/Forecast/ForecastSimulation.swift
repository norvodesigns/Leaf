import Foundation

/// One book as the simulation sees it.
struct ForecastSimBook: Sendable {
    var id: String
    /// Words left to read at the page the reader is on.
    var words: Double
    var pace: ForecastBookPace
    /// The reader has not said where they are, so they may be further along than the page shows.
    var positionUncertain: Bool
}

/// Books the reader has not picked yet. Once the library is read through, the rest of the year is filled with books of
/// the usual length so the year-end count is not capped by whatever happens to be on the shelf.
struct ForecastPhantom: Sendable {
    var medianWords: Double
    var lengthSigma = 0.4
    var meanPace: Double
    var sharedSD: Double
    var ownSD: Double
}

/// Everything one simulation needs, with no reference to the library, the calendar or the clock.
struct ForecastScenario: Sendable {
    /// Books in reading order: the Reading shelf, then the queue.
    var books: [ForecastSimBook]
    /// How many books share each day. One in focus mode; the size of the Reading shelf side by side.
    var slots: Int
    /// Weekday index (0 = Sunday) of day zero, which is today.
    var dayZeroWeekday: Int
    /// Beta parameters of the chance of reading on each weekday, and which weekdays are reading days at all.
    var alpha: [Double]
    var beta: [Double]
    var active: [Bool]
    /// Compensates the cap on the busy-week multiplier (see `ForecastAdherenceModel.busyWeekScale`), by weekday.
    var chanceScale: [Double]
    var weekSigma: Double
    var minutesMean: Double
    var minutesSigma: Double
    var weekdayScale: [Double]
    /// Day-to-day spread of speed.
    var daySigma: Double
    /// Speed multiplier by whole minutes of a sitting, 0 through 600.
    var lengthFactors: [Double]
    /// Minutes already read today.
    var readToday: Double
    /// Share of the reader's sittings that start later than now (1 at midnight, near 0 late at night).
    var shareAfterNow: Double
    /// Speed multiplier for what is left of today (time-of-day effect).
    var todayPaceFactor: Double
    /// Days from today to December 31, inclusive of both.
    var yearEndDay: Int
    var horizon: Int
    var phantom: ForecastPhantom?
    /// False when there is no reading time or no reading day, so nothing ever finishes.
    var canRead: Bool

    static let maxMinutes = 600
}

/// What a simulation produced: for each book the day offset it finished on in each run (sorted), and the books finished
/// by year end in each run (sorted).
struct ForecastSimOutput: Sendable {
    /// `Int32.max` means the book was not finished within the horizon.
    var finishDays: [[Int32]]
    /// Books from the library finished by December 31, per run.
    var libraryTotals: [Int32]
    /// The same plus books the reader has yet to pick.
    var yearTotals: [Int32]
}

/// Monte Carlo over days, not minutes: each simulated day decides whether the reader reads, for how long and how
/// fast, and spends the time down the queue the way `Planner` does. A run costs a few operations per day, so two
/// thousand futures take a fraction of a second.
enum ForecastSimulator {
    static let never = Int32.max

    private static let streamParams: UInt64 = 1
    private static let streamDays: UInt64 = 2
    private static let streamWeeks: UInt64 = 3
    private static let streamPicks: UInt64 = 4
    private static let streamWeekday: UInt64 = 10

    private static func limited(_ z: Double) -> Double { min(4, max(-4, z)) }

    static func run(_ scenario: ForecastScenario, seed: UInt64, runs requested: Int) -> ForecastSimOutput {
        let s = scenario
        let n = s.books.count
        let runs = max(1, requested)
        let slotCount = max(1, s.slots)
        var finish = [Int32](repeating: never, count: n * runs)
        var libraryTotals = [Int32](repeating: 0, count: runs)
        var yearTotals = [Int32](repeating: 0, count: runs)

        var wordsLeft = [Double](repeating: 0, count: n + 1)
        var pace = [Double](repeating: 0, count: n + 1)
        var done = [Bool](repeating: true, count: n + 1)
        var started = [Bool](repeating: false, count: n + 1)
        var weekdayChance = [Double](repeating: 0, count: 7)
        var activeBooks = [Int](repeating: 0, count: slotCount)

        let sigmaM = s.minutesSigma
        let sigmaD = s.daySigma
        let sigmaW = s.weekSigma
        let weekCentre = sigmaW * sigmaW / 2
        let minutesCentre = sigmaM * sigmaM / 2
        let usePhantom = s.phantom != nil
        let yearEnd = s.yearEndDay
        let horizon = s.horizon

        for run in 0..<runs {
            var paramRng = ForecastRandom.stream(seed: seed, run: run, salt: streamParams)
            var dayRng = ForecastRandom.stream(seed: seed, run: run, salt: streamDays)
            var weekRng = ForecastRandom.stream(seed: seed, run: run, salt: streamWeeks)
            var pickRng = ForecastRandom.stream(seed: seed, run: run, salt: streamPicks)

            // The reader's habits in this future: a draw of how reliably they read on each weekday.
            for w in 0..<7 {
                if s.active[w] {
                    var rng = ForecastRandom.stream(seed: seed, run: run, salt: streamWeekday + UInt64(w))
                    weekdayChance[w] = ForecastRandom.beta(a: s.alpha[w], b: s.beta[w], &rng) * s.chanceScale[w]
                } else {
                    weekdayChance[w] = 0
                }
            }

            // Their pace in this future: one draw shared by every book, one per book.
            let sharedZ = limited(ForecastRandom.normal(&paramRng))
            var remaining = 0
            var libraryCount = 0
            for i in 0..<n {
                let book = s.books[i]
                let ownZ = limited(ForecastRandom.normal(&paramRng))
                let u = paramRng.unit()
                pace[i] = exp(book.pace.mean + book.pace.sharedSD * sharedZ + book.pace.ownSD * ownZ)
                var left = book.words
                if book.positionUncertain { left *= 0.7 + 0.3 * u }
                wordsLeft[i] = left
                started[i] = false
                if left <= 0.5 {
                    done[i] = true
                    finish[i * runs + run] = 0
                    libraryCount += 1
                } else {
                    done[i] = false
                    remaining += 1
                }
            }
            done[n] = true

            var day = 0
            var cursor = 0
            var weekMultiplier = 1.0
            var phantomCount = 0

            while s.canRead && day < horizon {
                if remaining == 0 && (!usePhantom || day > yearEnd) { break }
                // Two uniforms every day, whatever happens, so a what-if never shifts tomorrow's luck.
                let u1 = dayRng.unit()
                let u2 = dayRng.unit()
                if day % 7 == 0 {
                    weekMultiplier = exp(sigmaW * limited(ForecastRandom.normal(&weekRng)) - weekCentre)
                }
                let weekday = (s.dayZeroWeekday + day) % 7
                var chance = min(weekdayChance[weekday] * weekMultiplier, ForecastAdherenceModel.chanceCap)
                if day == 0 {
                    if s.readToday > 0 {
                        chance = s.active[weekday] ? 1 : 0
                    } else if chance > 0 {
                        let f = s.shareAfterNow
                        chance = chance * f / (1 - chance * (1 - f))
                    }
                }

                if chance > 0 && u1 < chance {
                    let scale = s.minutesMean * s.weekdayScale[weekday]
                    var minutes = scale * exp(sigmaM * limited(ForecastRandom.inverseNormal(u1 / chance)) - minutesCentre)
                    minutes = min(max(minutes, 1), min(Double(ForecastScenario.maxMinutes), scale * 5))
                    if day == 0 { minutes = max(0, minutes - s.readToday) }

                    if minutes >= 0.5 {
                        let paceFactor = exp(sigmaD * limited(ForecastRandom.inverseNormal(u2))) * (day == 0 ? s.todayPaceFactor : 1)
                        var budget = minutes
                        var spentToday = 0.0

                        while budget >= Planner.minimumChunk {
                            var count = 0
                            var scan = cursor
                            while scan < n && count < slotCount {
                                if !done[scan] {
                                    activeBooks[count] = scan
                                    count += 1
                                }
                                scan += 1
                            }
                            if count == 0 {
                                // The library is read through: carry on with a new pick until the year is out.
                                guard let phantom = s.phantom, day <= yearEnd else { break }
                                if done[n] {
                                    let lengthZ = limited(ForecastRandom.normal(&pickRng))
                                    let ownZ = limited(ForecastRandom.normal(&pickRng))
                                    wordsLeft[n] = min(max(phantom.medianWords * exp(phantom.lengthSigma * lengthZ), 8_000), 400_000)
                                    pace[n] = exp(phantom.meanPace + phantom.sharedSD * sharedZ + phantom.ownSD * ownZ)
                                    done[n] = false
                                    started[n] = false
                                }
                                activeBooks[0] = n
                                count = 1
                            }
                            if spentToday > 0 && budget < Planner.minimumToStartNewBook {
                                var anyNew = false
                                for j in 0..<count where !started[activeBooks[j]] { anyNew = true }
                                if anyNew { break }
                            }

                            let share = budget / Double(count)
                            let sitting = s.lengthFactors[min(ForecastScenario.maxMinutes, Int(share.rounded()))]
                            var spentRound = 0.0
                            var finishedOne = false
                            for j in 0..<count {
                                let i = activeBooks[j]
                                let rate = pace[i] * paceFactor * sitting
                                let need = wordsLeft[i] / rate
                                let spend = need < share ? need : share
                                if spend <= 0 { continue }
                                started[i] = true
                                spentRound += spend
                                if need <= share {
                                    wordsLeft[i] = 0
                                    done[i] = true
                                    finishedOne = true
                                    if i < n {
                                        finish[i * runs + run] = Int32(day)
                                        remaining -= 1
                                        if day <= yearEnd { libraryCount += 1 }
                                    } else if day <= yearEnd {
                                        phantomCount += 1
                                    }
                                } else {
                                    wordsLeft[i] -= spend * rate
                                }
                            }
                            budget -= spentRound
                            spentToday += spentRound
                            if !finishedOne || spentRound <= 0 { break }
                            while cursor < n && done[cursor] { cursor += 1 }
                        }
                    }
                }
                day += 1
            }
            libraryTotals[run] = Int32(libraryCount)
            yearTotals[run] = Int32(libraryCount + phantomCount)
        }

        var perBook: [[Int32]] = []
        perBook.reserveCapacity(n)
        for i in 0..<n {
            perBook.append(Array(finish[(i * runs)..<((i + 1) * runs)]).sorted())
        }
        return ForecastSimOutput(finishDays: perBook, libraryTotals: libraryTotals.sorted(), yearTotals: yearTotals.sorted())
    }
}
