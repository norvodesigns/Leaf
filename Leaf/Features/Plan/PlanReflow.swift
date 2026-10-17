import Foundation

/// How a plan's finish dates moved between two moments (a mode switch, a new daily-minutes value).
/// Plain Foundation, so the arithmetic is easy to check in isolation.
enum PlanReflow {
    /// Finish dates by book id. Books with no finish date are left out.
    static func finishes(of plan: ReadingPlan) -> [String: Date] {
        var result: [String: Date] = [:]
        for book in plan.books {
            if let finish = book.finish { result[book.id] = finish }
        }
        return result
    }

    /// Whole calendar days from `old` to `new`: positive when the date moved later.
    static func days(from old: Date, to new: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: old)
        let end = calendar.startOfDay(for: new)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// For every book in both snapshots whose finish moved: days sooner (positive) or later (negative).
    static func deltas(from old: [String: Date], to new: [String: Date], calendar: Calendar) -> [String: Int] {
        var result: [String: Int] = [:]
        for (id, newDate) in new {
            guard let oldDate = old[id] else { continue }
            let sooner = -days(from: oldDate, to: newDate, calendar: calendar)
            if sooner != 0 { result[id] = sooner }
        }
        return result
    }

    /// The riffle that goes with a set of deltas: how many dates moved, and whether they moved earlier overall.
    static func riffle(for deltas: [String: Int]) -> (count: Int, earlier: Bool) {
        let net = deltas.values.reduce(0, +)
        return (deltas.count, net >= 0)
    }
}
