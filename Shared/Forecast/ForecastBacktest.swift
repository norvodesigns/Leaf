import Foundation

struct BacktestOptions: Sendable {
    /// Simulated futures per checkpoint. Fewer than the live forecast, because there are many checkpoints.
    var runs = 300
    var seed: UInt64 = 7
    /// Only the most recently finished books are replayed.
    var maxBooks = 40
    /// Where in each book's reading span the forecast is made (0.2 is a fifth of the way through).
    var fractions: [Double] = [0.2, 0.45, 0.7]
    /// Which quantiles bound the range being scored. The default is the 10th to the 90th: an 80 percent range.
    var lowQuantile = 0.1
    var highQuantile = 0.9

    var nominalCoverage: Double { highQuantile - lowQuantile }
}

/// How much to read into a backtest.
enum BacktestQuality: Int, Comparable, Sendable {
    /// Too few finished books to say anything.
    case insufficient = 0
    case rough = 1
    case solid = 2

    static func < (lhs: BacktestQuality, rhs: BacktestQuality) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One past forecast and what really happened. Day counts are from the day the forecast was made.
struct BacktestCheckpoint: Hashable, Sendable {
    var bookID: String
    var asOf: Date
    var predictedMedian: Int
    var predictedLow: Int
    var predictedHigh: Int
    var actual: Int
    /// Where the real finish fell in the forecast, 0 (earlier than every simulated future) to 1 (later than all of
    /// them); a middling value for a tie. A well-calibrated forecast spreads these evenly.
    var percentile: Double

    var covered: Bool { actual >= predictedLow && actual <= predictedHigh }
    var absoluteError: Int { abs(actual - predictedMedian) }
}

/// How well the forecast would have done on the reader's own past. Numbers only: screens write the sentence.
struct BacktestReport: Sendable {
    var checkpoints: [BacktestCheckpoint]
    /// The coverage the ranges were meant to have (0.8 for the 10th to 90th percentile).
    var nominalCoverage: Double
    /// Finished books that were replayed.
    var bookCount: Int

    var sampleSize: Int { checkpoints.count }

    /// Coverage measured on `percentile` instead of whole days. Finishing dates are whole days, so a narrow range lands
    /// on its end days more often than its nominal share; this removes that rounding and is the cleaner calibration
    /// score (it should be close to `nominalCoverage`).
    func smoothedCoverage(low: Double = 0.1, high: Double = 0.9) -> Double? {
        guard !checkpoints.isEmpty else { return nil }
        return Double(checkpoints.filter { $0.percentile >= low && $0.percentile <= high }.count) / Double(checkpoints.count)
    }

    /// Share of checkpoints where the book finished inside the predicted range.
    var coverage: Double? {
        guard !checkpoints.isEmpty else { return nil }
        return Double(checkpoints.filter(\.covered).count) / Double(checkpoints.count)
    }

    var meanAbsoluteErrorDays: Double? {
        guard !checkpoints.isEmpty else { return nil }
        return Double(checkpoints.reduce(0) { $0 + $1.absoluteError }) / Double(checkpoints.count)
    }

    var medianAbsoluteErrorDays: Double? {
        guard !checkpoints.isEmpty else { return nil }
        let sorted = checkpoints.map(\.absoluteError).sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? Double(sorted[mid]) : Double(sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Average of actual minus predicted median: positive means books tend to take longer than forecast.
    var biasDays: Double? {
        guard !checkpoints.isEmpty else { return nil }
        return Double(checkpoints.reduce(0) { $0 + ($1.actual - $1.predictedMedian) }) / Double(checkpoints.count)
    }

    /// Share of books that finished before the range began.
    var earlyRate: Double? {
        guard !checkpoints.isEmpty else { return nil }
        return Double(checkpoints.filter { $0.actual < $0.predictedLow }.count) / Double(checkpoints.count)
    }

    /// Share of books that finished after the range ended.
    var lateRate: Double? {
        guard !checkpoints.isEmpty else { return nil }
        return Double(checkpoints.filter { $0.actual > $0.predictedHigh }.count) / Double(checkpoints.count)
    }

    var quality: BacktestQuality {
        if bookCount < 2 || sampleSize < 6 { return .insufficient }
        return sampleSize < 20 ? .rough : .solid
    }
}

extension ForecastEngine {
    /// Replays the reader's history. For each finished book it goes back to a few moments while the book was being
    /// read, forecasts its finish using only what was known then (sessions up to that day, and the words-per-minute
    /// setting as the app would have had it), and compares the range with the day the book was really finished.
    func backtest(options bt: BacktestOptions = BacktestOptions()) -> BacktestReport {
        var recordsByBook: [String: [ForecastSessionRecord]] = [:]
        for record in records { recordsByBook[record.bookID, default: []].append(record) }

        let finished = data.items
            .filter { $0.shelf == .finished && $0.finishedAt != nil && !(recordsByBook[$0.id] ?? []).isEmpty }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            .prefix(bt.maxBooks)

        var checkpoints: [BacktestCheckpoint] = []
        for item in finished {
            guard let mine = recordsByBook[item.id], let firstDay = mine.first?.day, let lastDay = mine.last?.day, let finishedAt = item.finishedAt else { continue }
            let finishDay = max(days.number(finishedAt), lastDay)
            let span = finishDay - firstDay
            guard span >= 1 else { continue }

            var checkpointDays: [Int] = []
            for fraction in bt.fractions {
                let day = firstDay + 1 + Int((Double(span) * fraction).rounded(.down))
                if day > firstDay, day <= finishDay, !checkpointDays.contains(day) { checkpointDays.append(day) }
            }
            for day in checkpointDays {
                if let checkpoint = replay(item: item, bookRecords: mine, checkpointDay: day, finishDay: finishDay, recordsByBook: recordsByBook, options: bt) {
                    checkpoints.append(checkpoint)
                }
            }
        }
        return BacktestReport(checkpoints: checkpoints, nominalCoverage: bt.nominalCoverage, bookCount: finished.count)
    }

    /// One past forecast: the state at the start of `checkpointDay`, forecast, and scored against `finishDay`.
    private func replay(item: LibraryItem, bookRecords: [ForecastSessionRecord], checkpointDay: Int, finishDay: Int, recordsByBook: [String: [ForecastSessionRecord]], options bt: BacktestOptions) -> BacktestCheckpoint? {
        let known = records.prefix { $0.day < checkpointDay }
        let mineKnown = bookRecords.filter { $0.day < checkpointDay }
        guard !mineKnown.isEmpty else { return nil }
        let page = min(item.book.pages, mineKnown.map(\.toPage).max() ?? 0)
        guard page < item.book.pages else { return nil }

        // Books being read at the same time, which matter when the reader splits their days between books.
        var sub = LeafData()
        sub.preferences = data.preferences
        sub.preferences.wpm = reconstructedWPM(before: checkpointDay, records: known)
        var target = item
        target.shelf = .reading
        target.currentPage = page
        target.positionConfirmed = true
        sub.items = [target]
        if data.preferences.planMode == .sideBySide {
            for other in data.items where other.id != item.id {
                guard let theirs = recordsByBook[other.id] else { continue }
                let before = theirs.filter { $0.day < checkpointDay }
                let after = theirs.contains { $0.day >= checkpointDay }
                guard let reached = before.map(\.toPage).max(), after, reached < other.book.pages else { continue }
                var companion = other
                companion.shelf = .reading
                companion.currentPage = reached
                companion.positionConfirmed = true
                companion.order = other.order + 1
                sub.items.append(companion)
            }
        }

        let start = days.start(ofDay: checkpointDay)
        let engine = ForecastEngine(data: sub, now: start, calendar: calendar, options: options, days: days, records: Array(known))
        let sc = engine.scenario(includeFuturePicks: false)
        guard let index = sc.books.firstIndex(where: { $0.id == item.id }) else { return nil }
        let sim = ForecastSimulator.run(sc, seed: bt.seed, runs: bt.runs)
        let sorted = sim.finishDays[index]
        let horizon = options.horizonDays
        return BacktestCheckpoint(
            bookID: item.id,
            asOf: start,
            predictedMedian: ForecastQuantile.offset(sorted: sorted, 0.5) ?? horizon,
            predictedLow: ForecastQuantile.offset(sorted: sorted, bt.lowQuantile) ?? horizon,
            predictedHigh: ForecastQuantile.offset(sorted: sorted, bt.highQuantile) ?? horizon,
            actual: finishDay - checkpointDay,
            percentile: ForecastQuantile.percentile(of: finishDay - checkpointDay, in: sorted)
        )
    }

    /// The words-per-minute setting as the app would have had it before `day`: the latest speed test, nudged by every
    /// session since, exactly as `LibraryStore.log` does. Using today's value would let the future leak into the past.
    func reconstructedWPM(before day: Int, records known: ArraySlice<ForecastSessionRecord>) -> Double {
        var wpm = ReadingSpeed.typicalAdultWPM
        let tests = data.speedTests
            .filter { days.number($0.date) < day }
            .sorted { $0.date < $1.date }
        var next = 0
        for record in known {
            while next < tests.count && tests[next].date <= record.startedAt {
                wpm = tests[next].effectiveWPM
                next += 1
            }
            if data.preferences.learnFromSessions,
               let observed = ReadingSpeed.observedWPM(pagesRead: record.pages, wordsPerPage: record.wordsPerPage, seconds: record.seconds) {
                wpm = ReadingSpeed.calibrated(current: wpm, observed: observed)
            }
        }
        while next < tests.count {
            wpm = tests[next].effectiveWPM
            next += 1
        }
        return wpm
    }
}
