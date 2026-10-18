import Foundation

/// One level of the pace hierarchy: the reader overall, a genre, or a single book.
struct ForecastPaceLevel: Sendable {
    /// Mean of log words-per-minute.
    var mean: Double
    /// Effective number of sessions behind it (weighted, so a two-page session counts for less).
    var sessions: Double
}

/// What the pace model says about one book, ready for the simulation.
struct ForecastBookPace: Sendable {
    /// Mean of log words-per-minute for steady reading of this book.
    var mean: Double
    /// Uncertainty shared by every book (it comes from the reader's overall level), as a standard deviation of log pace.
    var sharedSD: Double
    /// Uncertainty particular to this book.
    var ownSD: Double
    /// Usable sessions on this book so far.
    var sessions: Int
    /// The per-book multiplier that was applied (1 until the book has enough sessions).
    var correction: Double
}

/// The reader's reading speed, learned from their own sessions.
///
/// Speeds are modelled on the log scale as: a level for the reader, pulled toward the preference setting; a level for
/// each genre, pulled toward the reader; a level for each book, pulled toward its genre. "Pulled" means each level
/// behaves as if its parent contributed a few sessions of its own (`ForecastOptions.priorSessions`), so one fast
/// session does not move a book much but ten do. Two effects ride on top: a warm-up at the start of a sitting and
/// fatigue after a long one, and a small time-of-day effect. After a few sessions on a book, its own pace also gets a
/// correction, kept within 0.7 to 1.4 of its genre, so a slow book moves its own finish date.
struct ForecastPaceModel: Sendable {
    var options: ForecastOptions
    /// Mean of log words-per-minute from the preference setting, before any session.
    var priorMean: Double
    var global: ForecastPaceLevel
    var genres: [String: ForecastPaceLevel]
    var books: [String: ForecastPaceLevel]
    var bookSessions: [String: Int]
    /// Session-to-session spread of log speed once the book's own level is known.
    var sessionSigma: Double
    /// How much slower the first minutes of a sitting are (fraction of steady speed lost at minute zero).
    var warmUpLoss: Double
    /// How much speed is lost per half hour beyond 45 minutes.
    var fatigueRate: Double
    /// Log effect of the time of day, centred so the reader's usual mix of hours is neutral.
    var daypartEffects: [Daypart: Double]
    var usableSessions: Int

    /// How unsure we are that the preference setting is the reader's real pace in books (standard deviation, log scale).
    static let priorUncertainty = 0.15
    static let defaultSigma = 0.2
    static let warmUpPrior = 0.10
    static let warmUpPriorSD = 0.08
    static let fatiguePrior = 0.08
    static let fatiguePriorSD = 0.06
    static let daypartPriorSessions = 6.0

    // MARK: Session-length profile

    /// Average share of the warm-up deficit felt over a sitting of `minutes` (the deficit fades over the first ten).
    static func warmUpShare(minutes: Double) -> Double {
        guard minutes > 0 else { return 1 }
        if minutes <= 10 { return 1 - minutes / 20 }
        return 5 / minutes
    }

    /// Average fatigue over a sitting of `minutes`, in units where fatigue grows by one every half hour past 45 minutes
    /// and stops growing at three.
    static func fatigueShare(minutes: Double) -> Double {
        guard minutes > 45 else { return 0 }
        let total: Double
        if minutes <= 135 {
            total = (minutes - 45) * (minutes - 45) / 60
        } else {
            total = 135 + 3 * (minutes - 135)
        }
        return total / minutes
    }

    /// Multiplier on steady speed for a sitting of `minutes`: below one for short and very long sittings.
    func lengthFactor(minutes: Double) -> Double {
        let m = max(minutes, 0.5)
        return exp(-warmUpLoss * ForecastPaceModel.warmUpShare(minutes: m) - fatigueRate * ForecastPaceModel.fatigueShare(minutes: m))
    }

    func daypartFactor(_ daypart: Daypart) -> Double {
        exp(daypartEffects[daypart] ?? 0)
    }

    /// The daypart in which this reader is fastest, once there is enough to say (nil while every effect is tiny).
    var fastestDaypart: Daypart? {
        guard let best = daypartEffects.max(by: { $0.value < $1.value }), best.value > 0.02 else { return nil }
        return best.key
    }

    // MARK: Fitting

    static func fit(records: [ForecastSessionRecord], wpm: Double, options: ForecastOptions) -> ForecastPaceModel {
        let priorMean = log(min(max(wpm, 40), ReadingSpeed.plausibleRange.upperBound))
        let usable = records.filter { $0.wpm != nil && $0.weight > 0 }
        var model = ForecastPaceModel(
            options: options,
            priorMean: priorMean,
            global: ForecastPaceLevel(mean: priorMean, sessions: 0),
            genres: [:],
            books: [:],
            bookSessions: [:],
            sessionSigma: defaultSigma,
            warmUpLoss: warmUpPrior,
            fatigueRate: fatiguePrior,
            daypartEffects: [:],
            usableSessions: usable.count
        )
        guard !usable.isEmpty else { return model }

        // Flatten once; the loop below runs a few times.
        let count = usable.count
        var y = [Double](repeating: 0, count: count)
        var w = [Double](repeating: 0, count: count)
        var warm = [Double](repeating: 0, count: count)
        var fatigue = [Double](repeating: 0, count: count)
        var parts = [Int](repeating: 0, count: count)
        let allParts = Daypart.allCases
        var bookCounts: [String: Int] = [:]
        for (i, record) in usable.enumerated() {
            y[i] = log(record.wpm ?? 1)
            w[i] = record.weight
            warm[i] = warmUpShare(minutes: record.minutes)
            fatigue[i] = fatigueShare(minutes: record.minutes)
            parts[i] = allParts.firstIndex(of: record.daypart) ?? 0
            bookCounts[record.bookID, default: 0] += 1
        }
        model.bookSessions = bookCounts

        var d = warmUpPrior
        var f = fatiguePrior
        var dp = [Double](repeating: 0, count: allParts.count)
        var sigma = defaultSigma

        for _ in 0..<3 {
            var adjusted = [Double](repeating: 0, count: count)
            for i in 0..<count { adjusted[i] = y[i] + d * warm[i] + f * fatigue[i] - dp[parts[i]] }
            let levels = computeLevels(usable: usable, adjusted: adjusted, weights: w, prior: priorMean, options: options)
            model.global = levels.global
            model.genres = levels.genres
            model.books = levels.books
            sigma = withinBookSigma(usable: usable, adjusted: adjusted, weights: w)

            // Speed effects: regress what the book level cannot explain on the warm-up and fatigue shapes.
            var suu = 0.0, suv = 0.0, svv = 0.0, sub = 0.0, svb = 0.0
            let s2 = sigma * sigma
            for i in 0..<count {
                let mean = levels.books[usable[i].bookID]?.mean ?? levels.global.mean
                let z = mean + dp[parts[i]] - y[i]
                suu += w[i] * warm[i] * warm[i]
                suv += w[i] * warm[i] * fatigue[i]
                svv += w[i] * fatigue[i] * fatigue[i]
                sub += w[i] * warm[i] * z
                svb += w[i] * fatigue[i] * z
            }
            let pd = 1 / (warmUpPriorSD * warmUpPriorSD)
            let pf = 1 / (fatiguePriorSD * fatiguePriorSD)
            let a11 = suu / s2 + pd
            let a12 = suv / s2
            let a22 = svv / s2 + pf
            let b1 = sub / s2 + warmUpPrior * pd
            let b2 = svb / s2 + fatiguePrior * pf
            let det = a11 * a22 - a12 * a12
            if det > 1e-9 {
                d = min(max((b1 * a22 - b2 * a12) / det, 0), 0.4)
                f = min(max((a11 * b2 - a12 * b1) / det, 0), 0.3)
            }

            // Time of day: shrunk mean residual per daypart, centred on the reader's usual mix.
            var sums = [Double](repeating: 0, count: allParts.count)
            var weights = [Double](repeating: 0, count: allParts.count)
            for i in 0..<count {
                let mean = levels.books[usable[i].bookID]?.mean ?? levels.global.mean
                sums[parts[i]] += w[i] * (adjusted[i] - mean + dp[parts[i]])
                weights[parts[i]] += w[i]
            }
            var next = [Double](repeating: 0, count: allParts.count)
            let totalWeight = weights.reduce(0, +)
            for p in 0..<allParts.count {
                next[p] = sums[p] / (daypartPriorSessions + weights[p])
            }
            let centre = totalWeight > 0 ? (0..<allParts.count).reduce(0.0) { $0 + next[$1] * weights[$1] / totalWeight } : 0
            dp = next.map { min(max($0 - centre, -0.15), 0.15) }
        }

        // Final levels with the final effects.
        var adjusted = [Double](repeating: 0, count: count)
        for i in 0..<count { adjusted[i] = y[i] + d * warm[i] + f * fatigue[i] - dp[parts[i]] }
        let levels = computeLevels(usable: usable, adjusted: adjusted, weights: w, prior: priorMean, options: options)
        model.global = levels.global
        model.genres = levels.genres
        model.books = levels.books
        model.sessionSigma = sigma
        model.warmUpLoss = d
        model.fatigueRate = f
        var effects: [Daypart: Double] = [:]
        for (index, part) in allParts.enumerated() where abs(dp[index]) > 1e-6 { effects[part] = dp[index] }
        model.daypartEffects = effects
        return model
    }

    private static func computeLevels(usable: [ForecastSessionRecord], adjusted: [Double], weights: [Double], prior: Double, options: ForecastOptions) -> (global: ForecastPaceLevel, genres: [String: ForecastPaceLevel], books: [String: ForecastPaceLevel]) {
        var totalW = 0.0, totalWY = 0.0
        var genreW: [String: Double] = [:], genreWY: [String: Double] = [:]
        var bookW: [String: Double] = [:], bookWY: [String: Double] = [:]
        var bookGenre: [String: String] = [:]
        for (i, record) in usable.enumerated() {
            let w = weights[i], wy = weights[i] * adjusted[i]
            totalW += w
            totalWY += wy
            genreW[record.genre, default: 0] += w
            genreWY[record.genre, default: 0] += wy
            bookW[record.bookID, default: 0] += w
            bookWY[record.bookID, default: 0] += wy
            bookGenre[record.bookID] = record.genre
        }
        let kg = options.globalPriorSessions
        let k = options.priorSessions
        let global = ForecastPaceLevel(mean: (kg * prior + totalWY) / (kg + totalW), sessions: totalW)
        var genres: [String: ForecastPaceLevel] = [:]
        for (genre, w) in genreW {
            genres[genre] = ForecastPaceLevel(mean: (k * global.mean + (genreWY[genre] ?? 0)) / (k + w), sessions: w)
        }
        var books: [String: ForecastPaceLevel] = [:]
        for (book, w) in bookW {
            let parent = bookGenre[book].flatMap { genres[$0]?.mean } ?? global.mean
            books[book] = ForecastPaceLevel(mean: (k * parent + (bookWY[book] ?? 0)) / (k + w), sessions: w)
        }
        return (global, genres, books)
    }

    /// Pooled within-book spread of log speed (sessions with a handful of pages only, so rounding does not inflate it),
    /// pulled toward a sensible default when there is little to measure.
    private static func withinBookSigma(usable: [ForecastSessionRecord], adjusted: [Double], weights: [Double]) -> Double {
        var sumW: [String: Double] = [:], sumWY: [String: Double] = [:], counts: [String: Int] = [:]
        for (i, record) in usable.enumerated() where record.pages >= 4 {
            sumW[record.bookID, default: 0] += weights[i]
            sumWY[record.bookID, default: 0] += weights[i] * adjusted[i]
            counts[record.bookID, default: 0] += 1
        }
        var ss = 0.0
        var degrees = 0.0
        for (i, record) in usable.enumerated() where record.pages >= 4 {
            guard let n = counts[record.bookID], n >= 2, let w = sumW[record.bookID], w > 0 else { continue }
            let mean = (sumWY[record.bookID] ?? 0) / w
            ss += weights[i] * (adjusted[i] - mean) * (adjusted[i] - mean)
        }
        for n in counts.values where n >= 2 { degrees += Double(n - 1) }
        let prior = defaultSigma
        let priorDegrees = 4.0
        let variance = (priorDegrees * prior * prior + ss) / (priorDegrees + degrees)
        return min(max(variance.squareRoot(), 0.08), 0.5)
    }

    // MARK: Asking the model

    /// The pace of one book: the level, how unsure it is, and the correction applied.
    func pace(for book: Book) -> ForecastBookPace {
        let k = options.priorSessions
        let kg = options.globalPriorSessions
        let s2 = sessionSigma * sessionSigma
        let prior2 = ForecastPaceModel.priorUncertainty * ForecastPaceModel.priorUncertainty

        let globalFactor = kg / (kg + global.sessions)
        let varGlobal = s2 / (kg + global.sessions) + globalFactor * globalFactor * prior2

        let genre = genres[ForecastRecords.primaryGenre(of: book)]
        let genreSessions = genre?.sessions ?? 0
        let genreMean = genre?.mean ?? global.mean
        let genreFactor = k / (k + genreSessions)
        let varGenre = s2 / (k + genreSessions) + genreFactor * genreFactor * varGlobal

        let rawCount = bookSessions[book.id] ?? 0
        if rawCount >= options.bookCorrectionSessions, let level = books[book.id] {
            let ratio = exp(level.mean - genreMean)
            let correction = min(max(ratio, options.bookCorrectionRange.lowerBound), options.bookCorrectionRange.upperBound)
            let bookFactor = k / (k + level.sessions)
            let variance = s2 / (k + level.sessions) + bookFactor * bookFactor * varGenre
            let shared = (varGlobal.squareRoot() * genreFactor * bookFactor)
            return ForecastBookPace(
                mean: genreMean + log(correction),
                sharedSD: shared,
                ownSD: max(0, variance - shared * shared).squareRoot(),
                sessions: rawCount,
                correction: correction
            )
        }
        // No evidence about this particular book yet: its genre's pace, plus the usual book-to-book spread.
        let variance = varGenre + s2 / k
        let shared = varGlobal.squareRoot() * genreFactor
        return ForecastBookPace(
            mean: genreMean,
            sharedSD: shared,
            ownSD: max(0, variance - shared * shared).squareRoot(),
            sessions: rawCount,
            correction: 1
        )
    }

    /// Words per minute to expect while reading this book steadily (the average over sittings, not the median).
    func expectedWPM(for book: Book) -> Double {
        exp(pace(for: book).mean + sessionSigma * sessionSigma / 2)
    }

    /// The reader's overall expected speed in words per minute.
    var overallWPM: Double {
        exp(global.mean + sessionSigma * sessionSigma / 2)
    }
}
