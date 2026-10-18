import Foundation

/// What the reader is asked to do about days they missed.
enum ForecastCatchUpAction: Hashable, Sendable {
    /// Nothing: carry on from here.
    case nothingToMakeUp
    /// The dates have moved later by this many days.
    case datesMoved(days: Int)
    /// A little extra each day for a few reading days.
    case addMinutes(perDay: Int, forDays: Int)
}

/// Advice after missed days, shaped by the reader's `CatchUpMode`. Numbers only; `ForecastNarrator` words it.
struct ForecastCatchUp: Sendable {
    var mode: CatchUpMode
    var windowDays: Int
    /// Chosen reading days in the window with no reading at all.
    var missedDays: Int
    var missedMinutes: Double
    /// The book at the front of the plan, which the dates below are for.
    var bookID: String?
    /// Where its finish would be had nothing been missed.
    var baselineFinish: Date?
    /// Where it is from here at the usual pace.
    var currentFinish: Date?
    /// The finish with the mode applied: later than baseline for forgive and shift, nearly back to it for compress.
    var adjustedFinish: Date?
    /// Days the current finish sits behind the baseline.
    var lateDays: Int
    var action: ForecastCatchUpAction
    /// The daily minutes to plan with for the next few reading days.
    var adjustedDailyMinutes: Int
}

extension ForecastEngine {
    /// Looks at the last `windowDays` days (not counting today) for chosen reading days with no reading, and works out
    /// what the reader's catch-up mode does about them. Forgive (the default) asks for nothing. Shift reports how far the
    /// dates moved. Compress spreads the missed minutes over the next `spreadDays` reading days, never asking for more
    /// than half again on top of the daily goal.
    func catchUp(windowDays: Int = 7, spreadDays: Int = 5) -> ForecastCatchUp {
        let prefs = data.preferences
        var dayMinutes: [Int: Double] = [:]
        for record in records { dayMinutes[record.day, default: 0] += record.minutes }
        let first = ForecastEngine.firstDay(onboardedAt: prefs.onboardedAt, records: records, days: days, today: today)

        var missed = 0
        if prefs.dailyMinutes > 0, let first, windowDays > 0 {
            for day in max(first, today - windowDays)..<today where prefs.readingDays.contains(days.weekday(ofDay: day)) {
                if (dayMinutes[day] ?? 0) < 1 { missed += 1 }
            }
        }
        let missedMinutes = Double(missed * max(prefs.dailyMinutes, 0))
        let front = (reading + queue).first { $0.wordsLeft > 0 }
        var advice = ForecastCatchUp(
            mode: prefs.catchUp, windowDays: windowDays, missedDays: missed, missedMinutes: missedMinutes,
            bookID: front?.id, baselineFinish: nil, currentFinish: nil, adjustedFinish: nil, lateDays: 0,
            action: .nothingToMakeUp, adjustedDailyMinutes: prefs.dailyMinutes
        )
        guard let front else { return advice }

        let currentPlan = plan()
        advice.currentFinish = currentPlan.book(front.id)?.finish
        advice.adjustedFinish = advice.currentFinish
        guard missed > 0 else {
            advice.baselineFinish = advice.currentFinish
            return advice
        }
        let ahead = advanced(byMinutes: missedMinutes)
        advice.baselineFinish = plan(reading: ahead.reading, queue: ahead.queue).book(front.id)?.finish
        if let base = advice.baselineFinish, let current = advice.currentFinish {
            advice.lateDays = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: base), to: calendar.startOfDay(for: current)).day ?? 0)
        }

        switch prefs.catchUp {
        case .forgive:
            break
        case .shift:
            advice.action = advice.lateDays > 0 ? .datesMoved(days: advice.lateDays) : .nothingToMakeUp
        case .compress:
            let cap = max(5, prefs.dailyMinutes / 2)
            let perDay = min(cap, max(1, Int((missedMinutes / Double(max(1, spreadDays))).rounded(.up))))
            let forDays = min(14, max(1, Int((missedMinutes / Double(perDay)).rounded(.up))))
            let recovered = min(missedMinutes, Double(perDay * forDays))
            let repaid = advanced(byMinutes: recovered)
            advice.adjustedFinish = plan(reading: repaid.reading, queue: repaid.queue).book(front.id)?.finish
            advice.adjustedDailyMinutes = prefs.dailyMinutes + perDay
            advice.action = .addMinutes(perDay: perDay, forDays: forDays)
        }
        return advice
    }
}
