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
/// A refresh computes the forecast first (the page's top half), then insights and challenges, then the backtest,
/// which replays the reader's history and is the slowest. What-ifs, finish lines and suggested orders run on demand
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
        refreshTask = Task { [weak self] in
            let forecast = await Task.detached(priority: .userInitiated) {
                PlanDesk.forecastSnapshot(inputs, tonightBookID: tonightBookID)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.forecast = forecast
            self.isWorking = false
            if let whatIf = self.whatIf { self.comparison = whatIf.comparison(against: forecast.result) }

            let insights = await Task.detached(priority: .utility) { PlanDesk.insightsSnapshot(inputs) }.value
            guard !Task.isCancelled else { return }
            self.insights = insights

            let challenges = await Task.detached(priority: .utility) { PlanDesk.challengeSnapshot(inputs) }.value
            guard !Task.isCancelled else { return }
            self.challenges = challenges

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
        whatIf = nil
        comparison = nil
    }

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
