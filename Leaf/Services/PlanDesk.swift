import Foundation
import Observation

/// What the Forecast page draws from the engine, worked out in one pass.
struct ForecastSnapshot: Sendable {
    var result: ForecastResult
    /// "Six more minutes tonight makes it Saturday", for the book being read first.
    var tonight: ForecastTonight?
    var tonightBookID: String?
    var catchUp: ForecastCatchUp
    var stalled: [StalledBook]
    /// What the yearly goal asks for, when there is one.
    var yearPlan: ForecastYearPlan?
}

/// The Insights page: everything the stats engine says about the reader.
struct InsightsSnapshot: Sendable {
    var year: Int
    var heatmap: [HeatCell]
    var bestTime: BestTimeOfDay?
    var speed: SpeedTrend
    var genres: [InsightsEngine.GenreShare]
    var lengths: [InsightsEngine.LengthShare]
    var tbr: TBRDepth
    var personality: ReadingPersonality
    var pacing: YearGoalPacing
    var yearInBooks: YearInBooks
    var letter: WeeklyLetterData
}

/// The Challenges page: joined challenges, the ones on offer, and every stamp earned.
struct ChallengeSnapshot: Sendable {
    var progress: [ChallengeProgress]
    var offers: [ChallengeOffer]
    var stamps: [StampEntry]
}

/// The Plan tab's engines, run off the main actor and kept until the library changes.
///
/// A refresh computes the challenges first (cheap, and a join should show at once), then the forecast (with any
/// what-if re-run against the same inputs, so the two always compare like with like), then insights, then the
/// backtest, which replays the reader's history and is the slowest. What-ifs, finish lines and suggested orders run on demand
/// with the same day seed as the baseline, so the difference between two results is the change itself.
@MainActor
@Observable
final class PlanDesk {
    private(set) var forecast: ForecastSnapshot?
    private(set) var insights: InsightsSnapshot?
    private(set) var challenges: ChallengeSnapshot?
    private(set) var backtest: BacktestReport?
    private(set) var isWorking = false

    /// The forecast with the what-if controls applied, and how it differs from `forecast`.
    private(set) var whatIf: ForecastResult?
    private(set) var comparison: ForecastComparison?

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var whatIfTask: Task<Void, Never>?
    /// The what-if last asked for, so a refresh can re-run it against fresh data.
    @ObservationIgnored private var whatIfAsk: (minutes: Int?, days: Set<Int>?)?

    private struct Inputs: Sendable {
        var data: LeafData
        var now: Date
        var calendar: Calendar
        var seed: UInt64

        @MainActor
        init(_ store: LibraryStore) {
            data = store.data
            now = store.now
            calendar = store.calendar
            seed = SeededGenerator.daySeed(store.now, calendar: store.calendar)
        }

        var engine: ForecastEngine { ForecastEngine(data: data, now: now, calendar: calendar) }
    }

    func refresh(from store: LibraryStore) {
        let inputs = Inputs(store)
        let tonightBookID = store.reading.first?.id
        refreshTask?.cancel()
        isWorking = true
        let ask = whatIfAsk
        refreshTask = Task { [weak self] in
            let challenges = await Task.detached(priority: .userInitiated) { PlanDesk.challengeSnapshot(inputs) }.value
            guard !Task.isCancelled, let self else { return }
            self.challenges = challenges

            let (forecast, whatIf) = await Task.detached(priority: .userInitiated) {
                let snapshot = PlanDesk.forecastSnapshot(inputs, tonightBookID: tonightBookID)
                let rerun = ask.map { inputs.engine.whatIf(dailyMinutes: $0.minutes, readingDays: $0.days, seed: inputs.seed) }
                return (snapshot, rerun)
            }.value
            guard !Task.isCancelled else { return }
            self.forecast = forecast
            self.isWorking = false
            if let result = self.forecast?.result { WatchBridge.shared.forecast = result }
            // Only if the controls haven't moved since: a newer what-if is already on its way.
            if let whatIf, let ask, let current = self.whatIfAsk, current.minutes == ask.minutes, current.days == ask.days {
                self.whatIf = whatIf
                self.comparison = whatIf.comparison(against: forecast.result)
            }

            let insights = await Task.detached(priority: .utility) { PlanDesk.insightsSnapshot(inputs) }.value
            guard !Task.isCancelled else { return }
            self.insights = insights

            let backtest = await Task.detached(priority: .background) { inputs.engine.backtest() }.value
            guard !Task.isCancelled else { return }
            self.backtest = backtest
        }
    }

    // MARK: What if

    /// Re-runs the forecast with other minutes or reading days, a moment after the controls stop moving.
    func runWhatIf(dailyMinutes: Int?, readingDays: Set<Int>?, store: LibraryStore) {
        whatIfTask?.cancel()
        guard dailyMinutes != nil || readingDays != nil else {
            clearWhatIf()
            return
        }
        let inputs = Inputs(store)
        whatIfAsk = (dailyMinutes, readingDays)
        whatIfTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                inputs.engine.whatIf(dailyMinutes: dailyMinutes, readingDays: readingDays, seed: inputs.seed)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.whatIf = result
            self.comparison = self.forecast.map { result.comparison(against: $0.result) }
        }
    }

    func clearWhatIf() {
        whatIfTask?.cancel()
        whatIfAsk = nil
        whatIf = nil
        comparison = nil
    }

    /// "Keep this plan": the what-if becomes the forecast at once, so nothing flickers back to the old numbers while
    /// the refresh that the new preferences trigger catches up.
    func adoptWhatIf() {
        whatIfTask?.cancel()
        if let whatIf, var snapshot = forecast {
            snapshot.result = whatIf
            forecast = snapshot
        }
        whatIfAsk = nil
        whatIf = nil
        comparison = nil
    }

    // MARK: Gone-quiet books the reader chose to keep

    private static let keptKey = "leaf.plan.keptQuietBooks"
    /// How long "Keep it" quiets the prompt for that book.
    static let keepQuietDays = 14

    /// Remembers "Keep it" for a book that had gone quiet, so the prompt rests for two weeks.
    func keepQuietBook(_ bookID: String, now: Date) {
        var kept = UserDefaults.standard.dictionary(forKey: Self.keptKey) as? [String: Double] ?? [:]
        kept[bookID] = now.timeIntervalSince1970
        UserDefaults.standard.set(kept, forKey: Self.keptKey)
        keptVersion += 1
    }

    /// Whether the reader said "Keep it" to this book in the last two weeks.
    func isKeptQuiet(_ bookID: String, now: Date) -> Bool {
        _ = keptVersion
        guard let kept = UserDefaults.standard.dictionary(forKey: Self.keptKey) as? [String: Double], let stamp = kept[bookID] else { return false }
        return now.timeIntervalSince1970 - stamp < Double(Self.keepQuietDays) * 86_400
    }

    /// Bumped on "Keep it" so views that ask `isKeptQuiet` redraw.
    private var keptVersion = 0

    // MARK: On demand

    /// What it takes to finish a book by a date.
    func inversePlan(bookID: String, by target: Date, store: LibraryStore) async -> ForecastInversePlan {
        let inputs = Inputs(store)
        return await Task.detached(priority: .userInitiated) {
            inputs.engine.inversePlan(bookID: bookID, by: target, seed: inputs.seed)
        }.value
    }

    /// A suggested To read order for a goal, with the days each book moves.
    func smartOrder(goal: ForecastOrderGoal, store: LibraryStore) async -> OrderSuggestion {
        let inputs = Inputs(store)
        return await Task.detached(priority: .userInitiated) {
            inputs.engine.smartOrder(goal: goal, seed: inputs.seed)
        }.value
    }

    // MARK: Engines

    private nonisolated static func forecastSnapshot(_ inputs: Inputs, tonightBookID: String?) -> ForecastSnapshot {
        let engine = inputs.engine
        let result = engine.forecast(seed: inputs.seed)
        let tonight = tonightBookID.flatMap { engine.tonightOnly(bookID: $0) }
        let goal = inputs.data.preferences.yearlyGoal
        return ForecastSnapshot(
            result: result,
            tonight: tonight,
            tonightBookID: tonight == nil ? nil : tonightBookID,
            catchUp: engine.catchUp(),
            stalled: engine.stalledBooks(),
            yearPlan: goal.map { engine.inversePlan(booksThisYear: $0, seed: inputs.seed) }
        )
    }

    private nonisolated static func insightsSnapshot(_ inputs: Inputs) -> InsightsSnapshot {
        let engine = InsightsEngine(data: inputs.data, now: inputs.now, calendar: inputs.calendar)
        let year = engine.currentYear
        return InsightsSnapshot(
            year: year,
            heatmap: engine.heatmap(year: year),
            bestTime: engine.bestTimeOfDay(),
            speed: engine.speedTrend(),
            genres: engine.genreMix(year: year),
            lengths: engine.lengthMix(year: year),
            tbr: engine.tbrDepth(),
            personality: engine.personality(),
            pacing: engine.yearGoalPacing(),
            yearInBooks: engine.yearInBooks(year: year),
            letter: engine.weeklyLetter(weekEnding: inputs.now)
        )
    }

    private nonisolated static func challengeSnapshot(_ inputs: Inputs) -> ChallengeSnapshot {
        ChallengeSnapshot(
            progress: ChallengeEvaluator.allProgress(data: inputs.data, now: inputs.now, calendar: inputs.calendar),
            offers: ChallengeEvaluator.availableChallenges(now: inputs.now, calendar: inputs.calendar, enrolled: inputs.data.challenges),
            stamps: StampLedger.entries(data: inputs.data, now: inputs.now, calendar: inputs.calendar)
        )
    }
}
