import Foundation

/// The forecast engine behind the Plan screen: learns the reader's pace and habits from their own history, then
/// simulates thousands of possible futures to say when each book will probably be done, with a range.
///
/// Pure and deterministic: it takes `now`, a `Calendar` and a seed, never reads the clock, and the same inputs always
/// give the same answer. Build one engine per refresh (the models are fitted in `init`), then ask it for a forecast, a
/// what-if, a backtest, an inverse plan, a better order for the queue, catch-up advice or stalled books.
struct ForecastEngine: Sendable {
    static let defaultRuns = 2000

    let data: LeafData
    let now: Date
    let calendar: Calendar
    let options: ForecastOptions

    let days: ForecastDays
    /// Day number of today.
    let today: Int
    let records: [ForecastSessionRecord]
    let fit: ForecastFit
    /// The Reading shelf in order. Paused and finished books are left out of every forecast.
    let reading: [LibraryItem]
    /// The To read queue in order.
    let queue: [LibraryItem]
    let minutesReadToday: Double

    init(data: LeafData, now: Date, calendar: Calendar, options: ForecastOptions = ForecastOptions()) {
        let days = ForecastDays(calendar: calendar)
        let records = ForecastRecords.make(sessions: data.sessions, items: data.items, days: days, now: now, options: options)
        self.init(data: data, now: now, calendar: calendar, options: options, days: days, records: records)
    }

    /// For the backtest, which forecasts from many past days and so reuses records it has already worked out.
    init(data: LeafData, now: Date, calendar: Calendar, options: ForecastOptions, days: ForecastDays, records: [ForecastSessionRecord]) {
        self.data = data
        self.now = now
        self.calendar = calendar
        self.options = options
        self.days = days
        let today = days.number(now)
        self.today = today
        self.records = records
        let first = ForecastEngine.firstDay(onboardedAt: data.preferences.onboardedAt, records: records, days: days, today: today)
        self.fit = ForecastFit.fit(
            records: records, preferences: data.preferences, wpm: data.preferences.wpm,
            today: today, firstDay: first, days: days, options: options
        )
        self.reading = data.items(on: .reading)
        self.queue = data.items(on: .toRead)
        self.minutesReadToday = records.filter { $0.day == today }.reduce(0) { $0 + $1.minutes }
    }

    /// The first day the reader used the app, as far as the data shows: onboarding or the first session.
    static func firstDay(onboardedAt: Date?, records: [ForecastSessionRecord], days: ForecastDays, today: Int) -> Int? {
        var candidates: [Int] = []
        if let onboardedAt {
            let day = days.number(onboardedAt)
            if day <= today { candidates.append(day) }
        }
        if let first = records.first { candidates.append(first.day) }
        return candidates.min()
    }

    // MARK: Forecast

    /// Simulates `runs` futures and summarizes them. The same seed always gives the same answer.
    func forecast(seed: UInt64 = 1, runs: Int = ForecastEngine.defaultRuns) -> ForecastResult {
        result(scenario: scenario(), plan: plan(), seed: seed, runs: runs, schedule: nil, aim: nil)
    }

    /// The forecast if the reader aimed for different minutes a day or different reading days. Use the same seed as
    /// the baseline and the two share their luck, so differences between them are the change itself.
    func whatIf(dailyMinutes: Int? = nil, readingDays: Set<Int>? = nil, seed: UInt64 = 1, runs: Int = ForecastEngine.defaultRuns) -> ForecastResult {
        let sc = scenario(dailyMinutes: dailyMinutes, readingDays: readingDays)
        return result(scenario: sc, plan: plan(dailyMinutes: dailyMinutes, readingDays: readingDays), seed: seed, runs: runs, schedule: readingDays, aim: dailyMinutes)
    }

    // MARK: Deterministic plan

    func planInput(dailyMinutes: Int? = nil, readingDays: Set<Int>? = nil, reading: [LibraryItem]? = nil, queue: [LibraryItem]? = nil, minutesReadToday: Double? = nil) -> PlanInput {
        PlanInput(
            reading: reading ?? self.reading,
            queue: queue ?? self.queue,
            wpm: data.preferences.wpm,
            dailyMinutes: dailyMinutes ?? data.preferences.dailyMinutes,
            readingDays: readingDays ?? data.preferences.readingDays,
            mode: data.preferences.planMode,
            today: now,
            minutesReadToday: minutesReadToday ?? self.minutesReadToday,
            calendar: calendar,
            maxDays: options.horizonDays
        )
    }

    /// The plain plan from `Planner`, with the reader's words-per-minute setting and every chosen day read in full.
    func plan(dailyMinutes: Int? = nil, readingDays: Set<Int>? = nil, reading: [LibraryItem]? = nil, queue: [LibraryItem]? = nil, minutesReadToday: Double? = nil) -> ReadingPlan {
        Planner.makePlan(planInput(dailyMinutes: dailyMinutes, readingDays: readingDays, reading: reading, queue: queue, minutesReadToday: minutesReadToday), recordDays: 1)
    }

    // MARK: Scenario

    func simBook(_ item: LibraryItem) -> ForecastSimBook {
        let pages = max(item.book.pages, 1)
        let page = min(pages, max(0, item.currentPage))
        return ForecastSimBook(
            id: item.id,
            words: Double(pages - page) * item.book.wordsPerPage,
            pace: fit.pace.pace(for: item.book),
            positionUncertain: item.shelf == .reading && !item.positionConfirmed && item.currentPage == 0
        )
    }

    /// Speed multiplier for what is left of today, from the reader's usual hours.
    private func todayPaceFactor() -> Double {
        let hour = days.minuteOfDay(now) / 60
        var weight = 0.0
        var total = 0.0
        for h in hour..<24 {
            let share = fit.timing.hourShare[h]
            weight += share
            total += share * fit.pace.daypartFactor(ForecastTimingModel.daypart(hour: h))
        }
        return weight > 0 ? total / weight : 1
    }

    /// The scenario for a set of books and, optionally, a different aim or schedule. `books` defaults to the whole
    /// plan: Reading shelf then queue.
    func scenario(dailyMinutes: Int? = nil, readingDays: Set<Int>? = nil, reading: [LibraryItem]? = nil, queue: [LibraryItem]? = nil, slots: Int? = nil, includeFuturePicks: Bool = true) -> ForecastScenario {
        let prefs = data.preferences
        let schedule = readingDays ?? prefs.readingDays
        let aim = dailyMinutes ?? prefs.dailyMinutes
        let adherence = fit.adherence.withSchedule(schedule)
        let minutes = fit.minutes.scaled(toAim: aim)
        let readingItems = reading ?? self.reading
        let queueItems = queue ?? self.queue

        let hasEvidence = includeFuturePicks && (!data.items.isEmpty || !records.isEmpty)
        var phantom: ForecastPhantom?
        if hasEvidence {
            let finished = data.items.filter { $0.shelf == .finished }
            let source = finished.isEmpty ? data.items : finished
            let words = source.map { Double($0.book.words) }.sorted()
            let median = words.isEmpty ? 80_000 : words[words.count / 2]
            let priorSD = ForecastPaceModel.priorUncertainty
            let kg = options.globalPriorSessions
            let s2 = fit.pace.sessionSigma * fit.pace.sessionSigma
            let factor = kg / (kg + fit.pace.global.sessions)
            let sharedSD = (s2 / (kg + fit.pace.global.sessions) + factor * factor * priorSD * priorSD).squareRoot()
            phantom = ForecastPhantom(
                medianWords: median,
                meanPace: fit.pace.global.mean,
                sharedSD: sharedSD,
                ownSD: (s2 / options.priorSessions).squareRoot()
            )
        }

        let yearEnd: Int = {
            let year = calendar.component(.year, from: now)
            guard let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) else { return 0 }
            return max(0, days.number(end) - today)
        }()

        return ForecastScenario(
            books: (readingItems + queueItems).map(simBook),
            slots: slots ?? (prefs.planMode == .sideBySide ? max(1, readingItems.count) : 1),
            dayZeroWeekday: days.weekday(ofDay: today) - 1,
            alpha: adherence.alpha,
            beta: adherence.beta,
            active: adherence.scheduled,
            chanceScale: (0..<7).map { ForecastAdherenceModel.busyWeekScale(chance: adherence.probability(weekdayIndex: $0), sigma: adherence.weekSigma) },
            weekSigma: adherence.weekSigma,
            minutesMean: minutes.meanMinutes,
            minutesSigma: minutes.sigma,
            weekdayScale: minutes.weekdayScale,
            daySigma: fit.pace.sessionSigma,
            lengthFactors: (0...ForecastScenario.maxMinutes).map { fit.pace.lengthFactor(minutes: Double($0)) },
            readToday: minutesReadToday,
            shareAfterNow: fit.timing.shareAfter(minuteOfDay: days.minuteOfDay(now)),
            todayPaceFactor: todayPaceFactor(),
            yearEndDay: yearEnd,
            horizon: options.horizonDays,
            phantom: phantom,
            canRead: aim > 0 && minutes.meanMinutes > 0 && adherence.anyScheduled
        )
    }

    // MARK: Result

    /// Typical minutes of a sitting, for turning words into minutes.
    var typicalSittingMinutes: Double { max(5, fit.minutes.medianMinutes) }

    /// Expected minutes left in `item` at the reader's own pace.
    func expectedMinutesLeft(_ item: LibraryItem) -> Double {
        let wpm = fit.pace.expectedWPM(for: item.book) * fit.pace.lengthFactor(minutes: typicalSittingMinutes)
        return item.wordsLeft / max(wpm, 1)
    }

    private func result(scenario sc: ForecastScenario, plan: ReadingPlan, seed: UInt64, runs: Int, schedule: Set<Int>?, aim: Int?) -> ForecastResult {
        let sim = ForecastSimulator.run(sc, seed: seed, runs: runs)
        let origin = calendar.startOfDay(for: now)
        let items = reading + queue
        var forecasts: [BookForecast] = []
        for (index, item) in items.enumerated() {
            let finishDays = sim.finishDays[index]
            var forecast = BookForecast(
                id: item.id,
                isReading: item.shelf == .reading,
                remainingMinutes: expectedMinutesLeft(item),
                deterministicFinish: plan.book(item.id)?.finish,
                confidence: .medium,
                positionUncertain: sc.books[index].positionUncertain,
                sessions: sc.books[index].pace.sessions,
                finishDays: finishDays,
                origin: origin,
                calendar: calendar
            )
            forecast.confidence = confidence(median: forecast.medianOffset, p10: forecast.p10Offset, p90: forecast.p90Offset, positionUncertain: forecast.positionUncertain)
            forecasts.append(forecast)
        }

        let year = yearForecast(sim: sim, scenario: sc)
        let prefs = data.preferences
        let adherence = fit.adherence.withSchedule(schedule ?? prefs.readingDays)
        let minutes = fit.minutes.scaled(toAim: aim ?? prefs.dailyMinutes)
        let assumptions = ForecastAssumptions(
            dailyMinutes: aim ?? prefs.dailyMinutes,
            readingDays: schedule ?? prefs.readingDays,
            planMode: prefs.planMode,
            paceWPM: fit.pace.overallWPM,
            expectedDaysPerWeek: adherence.expectedDaysPerWeek,
            typicalMinutes: minutes.meanMinutes,
            sessionCount: fit.sessionCount,
            historyDays: fit.historyDays,
            fastestDaypart: fit.pace.fastestDaypart
        )
        return ForecastResult(generatedAt: now, seed: seed, runs: max(1, runs), books: forecasts, year: year, plan: plan, assumptions: assumptions)
    }

    private func yearForecast(sim: ForecastSimOutput, scenario sc: ForecastScenario) -> YearForecast {
        let year = calendar.component(.year, from: now)
        let finishedSoFar = ReadingStats.booksFinished(in: year, items: data.items, calendar: calendar)
        let totals = sim.yearTotals.map { $0 + Int32(finishedSoFar) }
        func quantile(_ sorted: [Int32], _ q: Double, empty: Int) -> Int {
            guard !sorted.isEmpty else { return empty }
            return Int(sorted[min(sorted.count - 1, max(0, Int((q * Double(sorted.count)).rounded(.up)) - 1))])
        }
        let goal = data.preferences.yearlyGoal.flatMap { $0 > 0 ? $0 : nil }
        var forecast = YearForecast(
            year: year,
            finishedSoFar: finishedSoFar,
            low: quantile(totals, 0.1, empty: finishedSoFar),
            median: quantile(totals, 0.5, empty: finishedSoFar),
            high: quantile(totals, 0.9, empty: finishedSoFar),
            fromLibraryMedian: finishedSoFar + quantile(sim.libraryTotals, 0.5, empty: 0),
            goal: goal,
            probabilityOfGoal: nil,
            includesFuturePicks: sc.phantom != nil,
            confidence: .medium,
            totals: totals
        )
        if let goal { forecast.probabilityOfGoal = forecast.probability(atLeast: goal) }
        let width = forecast.high - forecast.low
        if fit.sessionCount < 5 {
            forecast.confidence = .low
        } else if fit.sessionCount >= 15 && fit.historyDays >= 28 && width <= max(3, forecast.median / 2) {
            forecast.confidence = .high
        }
        return forecast
    }

    /// How far to trust one book's range. Few sessions, an unconfirmed page, a wide range or no finish at all all pull
    /// it down.
    func confidence(median: Int?, p10: Int?, p90: Int?, positionUncertain: Bool) -> ForecastConfidence {
        guard let median else { return .low }
        if positionUncertain || fit.sessionCount < 5 { return .low }
        let low = p10 ?? median
        let high = p90 ?? (median * 3 + 30)
        let width = Double(high - low)
        let relative = width / Double(max(median, 7))
        if fit.sessionCount >= 15 && fit.historyDays >= 28 && (relative < 0.6 || width <= 3) { return .high }
        if relative > 1.5 && width > 14 { return .low }
        return .medium
    }
}

extension ForecastTimingModel {
    /// The daypart an hour of the day falls in (to the nearest hour).
    static func daypart(hour: Int) -> Daypart {
        switch hour {
        case 2..<5: return .smallHours
        case 5..<8: return .dawn
        case 8..<11: return .morning
        case 11..<14: return .lunch
        case 14..<16: return .afternoon
        case 16..<17: return .teaTime
        case 17..<19: return .dusk
        case 19..<23: return .evening
        default: return .late
        }
    }
}
