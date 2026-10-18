import Foundation

/// How likely the reader is to read on each weekday, learned from the last few weeks.
///
/// Each weekday gets a Beta posterior: a prior that the reader follows through on a day they chose about as often as
/// they do overall (70 percent for a typical reader, until their own record says otherwise), updated by what actually
/// happened on that weekday in the last eight weeks, with recent weeks counting a little more. Days the reader did not choose are rest days: nothing is planned for them and
/// the forecast never reads on them. Separately, `weekSigma` captures busy and quiet weeks, which make real life
/// lumpier than independent days would be.
struct ForecastAdherenceModel: Sendable {
    /// Beta parameters by weekday index, 0 = Sunday ... 6 = Saturday.
    var alpha: [Double]
    var beta: [Double]
    /// Whether the weekday is one of the reader's chosen reading days.
    var scheduled: [Bool]
    /// Relative spread of how many days get read in a week, beyond what independent days would give.
    var weekSigma: Double
    /// Scheduled days in the window that were actually available to read on.
    var opportunityDays: Int
    var readDays: Int

    static let priorMean = 0.7
    static let priorStrength = 2.5
    /// Strength of each weekday's prior once the reader's overall follow-through is known.
    static let dayPriorStrength = 2.0
    static let defaultWeekSigma = 0.2
    static let recencyDecay = 0.93

    var anyScheduled: Bool { scheduled.contains(true) }

    /// Posterior mean chance of reading on a weekday (0 = Sunday ... 6), zero on rest days.
    func probability(weekdayIndex: Int) -> Double {
        guard scheduled[weekdayIndex] else { return 0 }
        return alpha[weekdayIndex] / (alpha[weekdayIndex] + beta[weekdayIndex])
    }

    /// How much to scale a weekday's chance before the busy-week multiplier is applied, so that after the multiplier
    /// is capped at a sure thing the average chance is still what the reader's record says. Without it, a reader with
    /// wildly uneven weeks would read less in the forecast than they really do.
    static func busyWeekScale(chance p: Double, sigma: Double) -> Double {
        guard p > 0, sigma > 0.01 else { return 1 }
        var scale = 1.0
        for _ in 0..<4 {
            var expected = 0.0
            var weight = 0.0
            var z = -4.0
            while z <= 4.0 {
                let w = exp(-z * z / 2)
                let multiplier = exp(sigma * z - sigma * sigma / 2)
                expected += w * min(scale * p * multiplier, ForecastAdherenceModel.chanceCap)
                weight += w
                z += 0.25
            }
            expected /= weight
            guard expected > 1e-9 else { break }
            scale = min(max(scale * p / expected, 1), 3)
        }
        return scale
    }

    static let chanceCap = 0.99

    /// Reading days to expect in a typical week.
    var expectedDaysPerWeek: Double {
        (0..<7).reduce(0.0) { $0 + probability(weekdayIndex: $1) }
    }

    /// The same reader on a different schedule. Days they already read keep what was learned about them; a day added
    /// is assumed to go as well as their other reading days do; a day dropped becomes a rest day.
    func withSchedule(_ readingDays: Set<Int>) -> ForecastAdherenceModel {
        var copy = self
        let existing = (0..<7).filter { scheduled[$0] }
        let pooledAlpha: Double
        let pooledBeta: Double
        if existing.isEmpty {
            pooledAlpha = ForecastAdherenceModel.priorMean * ForecastAdherenceModel.priorStrength
            pooledBeta = (1 - ForecastAdherenceModel.priorMean) * ForecastAdherenceModel.priorStrength
        } else {
            pooledAlpha = existing.reduce(0.0) { $0 + alpha[$1] } / Double(existing.count)
            pooledBeta = existing.reduce(0.0) { $0 + beta[$1] } / Double(existing.count)
        }
        for index in 0..<7 {
            let chosen = readingDays.contains(index + 1)
            if chosen && !scheduled[index] {
                copy.alpha[index] = pooledAlpha
                copy.beta[index] = pooledBeta
            }
            copy.scheduled[index] = chosen
        }
        return copy
    }

    /// One day in the look-back window that the reader could have read on.
    struct Day: Sendable {
        var day: Int
        var weekdayIndex: Int
        var minutes: Double
        var weight: Double
    }

    /// The days of the look-back window, newest first: yesterday back to `historyWeeks` weeks, but not before the reader
    /// started (a day before they used the app is not a missed day).
    static func window(dayMinutes: [Int: Double], today: Int, firstDay: Int?, days: ForecastDays, weeks: Int) -> [Day] {
        guard let firstDay, firstDay < today else { return [] }
        let earliest = max(firstDay, today - 7 * weeks)
        guard earliest <= today - 1 else { return [] }
        return (earliest...(today - 1)).reversed().map { day in
            let ago = Double(today - 1 - day) / 7
            return Day(
                day: day,
                weekdayIndex: days.weekday(ofDay: day) - 1,
                minutes: dayMinutes[day] ?? 0,
                weight: pow(recencyDecay, ago)
            )
        }
    }

    static func fit(window: [Day], longWindow: [Day], schedule: Set<Int>) -> ForecastAdherenceModel {
        let scheduled = (0..<7).map { schedule.contains($0 + 1) }
        var opportunities = 0
        var reads = 0
        var readWeight = [Double](repeating: 0, count: 7)
        var missWeight = [Double](repeating: 0, count: 7)
        for day in window where scheduled[day.weekdayIndex] {
            opportunities += 1
            if day.minutes >= 1 {
                reads += 1
                readWeight[day.weekdayIndex] += day.weight
            } else {
                missWeight[day.weekdayIndex] += day.weight
            }
        }
        // A window with no reading at all says the reader has been away, not that they never will read: a returning
        // reader starts again from the prior instead of from a record of misses.
        if reads == 0 {
            readWeight = [Double](repeating: 0, count: 7)
            missWeight = [Double](repeating: 0, count: 7)
        }
        // The prior for each day is how reliably the reader follows through on their chosen days overall (starting from
        // the 70 percent a typical reader manages). A weak prior on top of each day's own record keeps a weekend binger's
        // Saturdays and a quiet Wednesday apart, while stopping eight observations from looking like certainty.
        let totalRead = readWeight.reduce(0, +)
        let totalMiss = missWeight.reduce(0, +)
        let pooled = (totalRead + priorMean * priorStrength) / (totalRead + totalMiss + priorStrength)
        var alpha = [Double](repeating: priorMean * priorStrength, count: 7)
        var beta = [Double](repeating: (1 - priorMean) * priorStrength, count: 7)
        for index in 0..<7 where scheduled[index] {
            alpha[index] = pooled * dayPriorStrength + readWeight[index]
            beta[index] = (1 - pooled) * dayPriorStrength + missWeight[index]
        }
        var model = ForecastAdherenceModel(
            alpha: alpha, beta: beta, scheduled: scheduled,
            weekSigma: defaultWeekSigma, opportunityDays: opportunities, readDays: reads
        )
        model.weekSigma = estimateWeekSigma(model: model, window: longWindow)
        return model
    }

    /// Busy and quiet weeks: how much more the number of days read in a week varies than independent days would allow.
    /// Every run of seven days in `window` is counted (not only calendar weeks, whose edges the reader does not respect),
    /// and because a run straddling two weeks averages them, the excess is scaled back up by 1.9 (the exact factor when week
    /// edges fall anywhere).
    static func estimateWeekSigma(model: ForecastAdherenceModel, window: [Day]) -> Double {
        let ordered = window.sorted { $0.day < $1.day }
        guard ordered.count >= 21, ordered.count == (ordered.last?.day ?? 0) - (ordered.first?.day ?? 0) + 1 else { return defaultWeekSigma }
        let reads = ordered.map { model.scheduled[$0.weekdayIndex] && $0.minutes >= 1 ? 1.0 : 0.0 }
        var counts: [Double] = []
        var running = reads.prefix(7).reduce(0, +)
        counts.append(running)
        for end in 7..<reads.count {
            running += reads[end] - reads[end - 7]
            counts.append(running)
        }
        let expected = (0..<7).reduce(0.0) { $0 + model.probability(weekdayIndex: $1) }
        guard expected > 0 else { return defaultWeekSigma }
        let binomial = (0..<7).reduce(0.0) { sum, i in
            let p = model.probability(weekdayIndex: i)
            return sum + p * (1 - p)
        }
        let n = Double(counts.count)
        let mean = counts.reduce(0, +) / n
        let variance = counts.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let estimate = (1.9 * max(0, variance - binomial)).squareRoot() / expected
        let weeks = min(16, Double(ordered.count) / 7)
        let blended = (2 * defaultWeekSigma + weeks * estimate) / (2 + weeks)
        return min(max(blended, 0.05), 0.7)
    }
}

/// How long the reader reads on a day they read: a log-normal fit to their daily totals, anchored on the daily-minutes
/// setting until there are days to learn from.
struct ForecastMinutesModel: Sendable {
    /// Mean minutes on a day read.
    var meanMinutes: Double
    /// Spread of log minutes.
    var sigma: Double
    /// Multiplier on the mean by weekday index (0 = Sunday): a weekend binger reads far more on Saturday.
    var weekdayScale: [Double]
    /// The daily-minutes setting this fit is anchored on.
    var aim: Int
    var daysObserved: Int

    /// The daily-minutes setting counts as this many days of evidence.
    static let priorDays = 2.0
    /// A weekday's own average counts for its days plus this one day of the overall average.
    static let weekdayPriorDays = 1.0
    static let defaultSigma = 0.4

    /// Median minutes on a day read, ignoring weekday.
    var medianMinutes: Double { meanMinutes * exp(-sigma * sigma / 2) }

    /// The same reader if they aimed for `minutes` a day: everything they do scales with the aim, so asking for the
    /// current aim changes nothing and asking for more always means more.
    func scaled(toAim minutes: Int) -> ForecastMinutesModel {
        var copy = self
        copy.aim = minutes
        if minutes <= 0 {
            copy.meanMinutes = 0
        } else if aim > 0 {
            copy.meanMinutes = meanMinutes * Double(minutes) / Double(aim)
        } else {
            copy.meanMinutes = Double(minutes)
            copy.sigma = ForecastMinutesModel.defaultSigma
            copy.weekdayScale = [Double](repeating: 1, count: 7)
        }
        return copy
    }

    static func fit(window: [ForecastAdherenceModel.Day], scheduled: [Bool], aim: Int) -> ForecastMinutesModel {
        let read = window.filter { scheduled[$0.weekdayIndex] && $0.minutes >= 1 }
        let n = Double(read.count)
        let total = read.reduce(0.0) { $0 + $1.minutes }
        let aimMinutes = Double(max(aim, 0))
        let mean: Double
        if aim > 0 {
            mean = (priorDays * aimMinutes + total) / (priorDays + n)
        } else {
            mean = read.isEmpty ? 0 : total / n
        }

        var scale = [Double](repeating: 1, count: 7)
        if !read.isEmpty {
            let dataMean = total / n
            for index in 0..<7 {
                let mine = read.filter { $0.weekdayIndex == index }
                guard !mine.isEmpty, dataMean > 0 else { continue }
                let m = mine.reduce(0.0) { $0 + $1.minutes } / Double(mine.count)
                scale[index] = min(max((weekdayPriorDays + Double(mine.count) * m / dataMean) / (weekdayPriorDays + Double(mine.count)), 0.4), 2.5)
            }
        }

        // Spread of what is left once the weekday is accounted for: a weekend binger's two hours on Saturday and ten
        // minutes on Tuesday are not one wild reader.
        var sigma = defaultSigma
        if read.count >= 2 {
            let residuals = read.map { log($0.minutes / scale[$0.weekdayIndex]) }
            let centre = residuals.reduce(0, +) / n
            let ss = residuals.reduce(0.0) { $0 + ($1 - centre) * ($1 - centre) }
            let variance = (priorDays * defaultSigma * defaultSigma + ss) / (priorDays + n - 1)
            sigma = min(max(variance.squareRoot(), 0.1), 1.0)
        }
        return ForecastMinutesModel(meanMinutes: mean, sigma: sigma, weekdayScale: scale, aim: aim, daysObserved: read.count)
    }
}

/// When in the day the reader reads, so that "will I still read today?" can be answered at nine in the morning and at
/// eleven at night.
struct ForecastTimingModel: Sendable {
    /// Share of sessions starting in each hour (sums to one).
    var hourShare: [Double]

    /// A gentle evening-heavy day, used until the reader's own pattern is known.
    static let defaultProfile: [Double] = [
        0.02, 0.01, 0.005, 0.005, 0.01, 0.02, 0.04, 0.05, 0.05, 0.04, 0.03, 0.03,
        0.04, 0.03, 0.03, 0.03, 0.04, 0.05, 0.06, 0.08, 0.10, 0.10, 0.07, 0.04,
    ]
    static let priorSessions = 6.0

    static func fit(records: [ForecastSessionRecord], today: Int, weeks: Int) -> ForecastTimingModel {
        let total = defaultProfile.reduce(0, +)
        var counts = defaultProfile.map { $0 / total * priorSessions }
        for record in records where record.day < today && record.day >= today - 7 * weeks {
            counts[min(23, max(0, record.minuteOfDay / 60))] += 1
        }
        let sum = counts.reduce(0, +)
        return ForecastTimingModel(hourShare: counts.map { $0 / sum })
    }

    /// The share of the reader's sittings that start later than this time of day.
    func shareAfter(minuteOfDay: Int) -> Double {
        let clamped = min(max(minuteOfDay, 0), 24 * 60 - 1)
        let hour = clamped / 60
        let remaining = 1 - Double(clamped % 60) / 60
        var share = hourShare[hour] * remaining
        if hour < 23 {
            for later in (hour + 1)..<24 { share += hourShare[later] }
        }
        return share
    }

    /// Share of the reader's sittings in each daypart.
    var daypartShare: [Daypart: Double] {
        var result: [Daypart: Double] = [:]
        for hour in 0..<24 {
            result[ForecastTimingModel.daypart(hour: hour), default: 0] += hourShare[hour]
        }
        return result
    }
}

/// Everything learned from the reader's history as of one day: pace, adherence, minutes and timing.
struct ForecastFit: Sendable {
    var pace: ForecastPaceModel
    var adherence: ForecastAdherenceModel
    var minutes: ForecastMinutesModel
    var timing: ForecastTimingModel
    /// Sessions of any kind in the history.
    var sessionCount: Int
    /// Days between the reader's first activity and the day being forecast from.
    var historyDays: Int

    /// - Parameters:
    ///   - records: sessions before the end of `today`, oldest first.
    ///   - wpm: the words-per-minute setting as it stood on that day.
    ///   - today: the day number being forecast from; adherence only looks at days before it.
    ///   - firstDay: the first day the reader used the app, if known.
    static func fit(records: [ForecastSessionRecord], preferences: ReadingPreferences, wpm: Double, today: Int, firstDay: Int?, days: ForecastDays, options: ForecastOptions) -> ForecastFit {
        var dayMinutes: [Int: Double] = [:]
        for record in records { dayMinutes[record.day, default: 0] += record.minutes }
        let window = ForecastAdherenceModel.window(dayMinutes: dayMinutes, today: today, firstDay: firstDay, days: days, weeks: options.historyWeeks)
        let longWindow = ForecastAdherenceModel.window(dayMinutes: dayMinutes, today: today, firstDay: firstDay, days: days, weeks: 2 * options.historyWeeks)
        let adherence = ForecastAdherenceModel.fit(window: window, longWindow: longWindow, schedule: preferences.readingDays)
        let minutes = ForecastMinutesModel.fit(window: window, scheduled: adherence.scheduled, aim: preferences.dailyMinutes)
        return ForecastFit(
            pace: ForecastPaceModel.fit(records: records, wpm: wpm, options: options),
            adherence: adherence,
            minutes: minutes,
            timing: ForecastTimingModel.fit(records: records, today: today, weeks: options.historyWeeks),
            sessionCount: records.count,
            historyDays: firstDay.map { max(0, today - $0) } ?? 0
        )
    }
}
