import Foundation

/// Turns forecast numbers into the sentences the Plan screen, cards, watch and VoiceOver read out. Warm and plain:
/// no guilt, no exclamation marks, typographic apostrophes, weekday names for the next six days and "Nov 3" after that.
struct ForecastNarrator: Sendable {
    var now: Date
    var calendar: Calendar

    init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }

    // MARK: Words

    /// "today", "tomorrow", "Sunday" (within the next six days), otherwise "Nov 3" ("Nov 3, 2027" in another year).
    func day(_ date: Date) -> String {
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let diff = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        switch diff {
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...6: return LeafFormat.format(date, template: "EEEE", calendar: calendar)
        default: return LeafFormat.shortDate(date, today: now, calendar: calendar)
        }
    }

    /// Small numbers as words ("six"), larger as digits.
    func number(_ value: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
        return value >= 0 && value < words.count ? words[value] : "\(value)"
    }

    private func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private func plural(_ count: Int, _ one: String, _ many: String) -> String {
        count == 1 ? "\(number(count)) \(one)" : "\(number(count)) \(many)"
    }

    private func books(_ count: Int) -> String { count == 1 ? "1 book" : "\(count) books" }

    // MARK: Books

    /// "Probably done Sunday, between Saturday and Tuesday."
    func bookSentence(_ forecast: BookForecast) -> String {
        guard let median = forecast.median else { return "Not in sight yet at this pace." }
        let middle = day(median)
        let low = forecast.p10.map(day) ?? middle
        let high = forecast.p90.map(day) ?? middle
        let range: String
        if low == middle && high == middle {
            range = ""
        } else if low == middle {
            range = ", possibly as late as \(high)"
        } else if high == middle {
            range = ", possibly as early as \(low)"
        } else {
            range = ", between \(low) and \(high)"
        }
        if forecast.confidence == .low {
            return range.isEmpty ? "Too early to say. Somewhere around \(middle)." : "Too early to say. Somewhere around \(middle)\(range)."
        }
        return "Probably done \(middle)\(range)."
    }

    /// The short line for a card or the watch: "Probably done Sunday."
    func shortSentence(_ forecast: BookForecast) -> String {
        guard let median = forecast.median else { return "Not in sight yet." }
        return forecast.confidence == .low ? "Around \(day(median))." : "Probably done \(day(median))."
    }

    /// "About a 70 percent chance of finishing by Friday."
    func chanceSentence(_ forecast: BookForecast, by date: Date) -> String {
        let chance = forecast.probability(by: date)
        let when = day(date)
        if chance >= 0.95 { return "Very likely by \(when)." }
        if chance <= 0.05 { return "Unlikely by \(when)." }
        let percent = Int((chance * 20).rounded()) * 5
        return "About a \(percent) percent chance of finishing by \(when)."
    }

    /// How a what-if moved a book: "That brings it forward three days, to Oct 29."
    func changeSentence(_ delta: ForecastBookDelta) -> String {
        guard let earlier = delta.medianDaysEarlier, let new = delta.newMedian else { return "No finish date yet." }
        if earlier == 0 { return "No change to the finish date." }
        let span = plural(abs(earlier), "day", "days")
        return earlier > 0 ? "That brings it forward \(span), to \(day(new))." : "That moves it back \(span), to \(day(new))."
    }

    // MARK: Year

    /// "On track for 24 books, somewhere between 18 and 29."
    func yearSentence(_ year: YearForecast) -> String {
        if year.low == year.high { return "On track for \(books(year.median))." }
        let range = "somewhere between \(year.low) and \(year.high)"
        if let goal = year.goal, year.median < goal {
            return "Looking like about \(books(year.median)), \(range)."
        }
        return "On track for \(books(year.median)), \(range)."
    }

    /// A gentle word about the yearly goal, or nil when there is none.
    func goalSentence(_ year: YearForecast) -> String? {
        guard let goal = year.goal, let chance = year.probabilityOfGoal else { return nil }
        if year.finishedSoFar >= goal { return "Your goal of \(goal) is done. Everything from here is a gift." }
        if chance >= 0.85 { return "Your goal of \(goal) is well within reach." }
        if chance >= 0.5 { return "Your goal of \(goal) looks reachable." }
        if chance >= 0.15 { return "Your goal of \(goal) is a stretch, but still in reach." }
        return "A goal of \(goal) is a long shot this year; \(year.median) is closer to your current rhythm."
    }

    // MARK: Planning

    func inverseSentence(_ plan: ForecastInversePlan) -> String {
        let when = day(plan.target)
        guard let minutes = plan.minutesPerDay else { return "\(capitalized(when)) isn’t reachable, even with long days." }
        let amount = LeafFormat.duration(minutes: Double(minutes))
        var sentence: String
        switch plan.feasibility {
        case .onTrack: sentence = "You’re already on track for \(when). \(amount) a day would be enough."
        case .reachable: sentence = "About \(amount) a day gets you there by \(when)."
        case .stretch: sentence = "That’s a stretch: about \(amount) a day to be done by \(when)."
        case .impossible: sentence = "\(capitalized(when)) isn’t reachable, even with long days."
        }
        if let likely = plan.likelyMinutesPerDay, likely > minutes, plan.feasibility != .impossible {
            sentence += " For a comfortable margin, closer to \(LeafFormat.duration(minutes: Double(likely)))."
        }
        return sentence
    }

    func yearPlanSentence(_ plan: ForecastYearPlan) -> String {
        if plan.booksShort > 0 {
            return "That goal needs \(plural(plan.booksShort, "more book", "more books")) on your shelves first."
        }
        guard let minutes = plan.minutesPerDay else { return "That goal isn’t reachable this year." }
        if minutes == 0 { return "You’ve already reached \(books(plan.target)) this year." }
        let amount = LeafFormat.duration(minutes: Double(minutes))
        switch plan.feasibility {
        case .onTrack: return "You’re already on track for \(books(plan.target)). \(amount) a day would be enough."
        case .reachable: return "About \(amount) a day gets you to \(books(plan.target)) by the end of the year."
        default: return "\(books(plan.target)) is a stretch: about \(amount) a day."
        }
    }

    /// "Six more minutes tonight makes it Saturday."
    func tonightSentence(_ tonight: ForecastTonight) -> String {
        let minutes = tonight.extraMinutes == 1 ? "One more minute" : "\(capitalized(number(tonight.extraMinutes))) more minutes"
        return "\(minutes) tonight makes it \(day(tonight.newFinish))."
    }

    func orderSentence(_ suggestion: OrderSuggestion) -> String {
        guard suggestion.isChange else { return "Your order already works well for this." }
        switch suggestion.goal {
        case .mostFinished(let date):
            let now = suggestion.finishedByTargetSuggested ?? 0
            let before = suggestion.finishedByTargetCurrent ?? 0
            return "This order finishes \(books(now)) by \(day(date)), up from \(before)."
        case .alternateGenres:
            return "This order keeps similar books from sitting side by side."
        case .palateCleanser:
            return "A short read after each heavy one gives you room to breathe."
        }
    }

    // MARK: Care

    func stallSentence(_ stalled: StalledBook) -> String {
        switch stalled.suggestion {
        case .setAside:
            return "You haven’t picked up “\(stalled.title)” in \(stalled.daysIdle) days. Set it aside for now? It will keep your page."
        case .almostThere:
            return "“\(stalled.title)” is nearly finished. A few pages whenever you feel like it."
        }
    }

    func catchUpSentence(_ catchUp: ForecastCatchUp) -> String {
        switch catchUp.action {
        case .nothingToMakeUp: return "Nothing to make up. Pick up wherever you are."
        case .datesMoved(let days): return "Your dates have moved back \(plural(days, "day", "days"))."
        case .addMinutes(let perDay, let forDays):
            return "\(capitalized(number(perDay))) extra minutes a day for \(plural(forDays, "day", "days")) gets you back on track."
        }
    }

    func backtestSentence(_ report: BacktestReport) -> String {
        guard report.quality != .insufficient, let coverage = report.coverage else {
            return "Not enough finished books yet to check how well these ranges hold up."
        }
        let nominal = Int((report.nominalCoverage * 100).rounded())
        return "Your \(nominal) percent ranges have been right \(Int((coverage * 100).rounded())) percent of the time."
    }
}
