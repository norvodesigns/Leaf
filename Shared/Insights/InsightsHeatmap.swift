import Foundation

/// One day on the year heatmap. The heatmap is drawn as tea-ring stamps: a read day leaves a ring whose size follows
/// `ring`, and a finished book leaves a bigger one with its date.
struct HeatCell: Hashable, Identifiable, Sendable {
    /// Start of the day.
    var date: Date
    var minutes: Double
    /// 0 for a day with no reading, otherwise 0.1 to 1. Grows with the square root of the minutes, so the ring's area
    /// follows the time spent, and is scaled to the reader's goal and their typical day (see `InsightsEngine.heatmap`).
    var ring: Double
    /// Whether this weekday is one of the days the reader chose to read on. A rest day with reading is still a read day.
    var isReadingDay: Bool
    var isFuture: Bool
    var isToday: Bool
    /// Position in a week-by-week grid whose rows start on the calendar's first weekday: 0...6.
    var row: Int
    /// Which week of the grid the day is in, counting from the week that holds January 1st.
    var column: Int
    /// Books finished on this day, by id.
    var finishedBookIDs: [String]

    var id: Date { date }
    var isRestDay: Bool { !isReadingDay }
    var didRead: Bool { minutes > 0 }

    /// A ring size for `minutes` against a `reference` day. Half the reference gives about 0.55, the reference itself
    /// about 0.74 and twice the reference or more gives 1.
    static func ringScale(minutes: Double, reference: Double) -> Double {
        guard minutes > 0 else { return 0 }
        let ratio = minutes / max(reference, 1)
        return min(1, 0.1 + 0.9 * (ratio / 2).squareRoot())
    }
}

extension InsightsEngine {
    /// Every day of `year`, oldest first (365 or 366 cells), for the tea-ring year.
    ///
    /// The ring is sized against a reference day: the daily goal, pulled toward the reader's typical day (the median
    /// of their read days that year) as that evidence builds up. A reader whose goal is 20 minutes but who really reads
    /// for an hour still gets a ring that grows and shrinks instead of a wall of full-size ones.
    func heatmap(year: Int) -> [HeatCell] {
        guard let first = startOfYear(year), let next = startOfYear(year + 1) else { return [] }
        let count = max(0, daysBetween(first, next))
        guard count > 0 else { return [] }

        let reference = referenceDay(from: first, to: next)
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var finished: [Date: [String]] = [:]
        for item in finishedItems(year: year) {
            guard let when = item.finishedAt else { continue }
            finished[calendar.startOfDay(for: when), default: []].append(item.id)
        }

        var cells: [HeatCell] = []
        cells.reserveCapacity(count)
        var date = first
        for index in 0..<count {
            let minutes = minutesByDay[date] ?? 0
            let linear = index + offset
            cells.append(HeatCell(
                date: date,
                minutes: minutes,
                ring: HeatCell.ringScale(minutes: minutes, reference: reference),
                isReadingDay: schedule.contains(calendar.component(.weekday, from: date)),
                isFuture: date > today,
                isToday: date == today,
                row: linear % 7,
                column: linear / 7,
                finishedBookIDs: (finished[date] ?? []).sorted()
            ))
            date = addDays(1, to: date)
        }
        return cells
    }

    /// The day length a ring of about three quarters size stands for.
    func referenceDay(from first: Date, to next: Date) -> Double {
        let goal = Double(max(0, data.preferences.dailyMinutes))
        let readMinutes = readDays
            .filter { $0 >= first && $0 < next && $0 <= today }
            .compactMap { minutesByDay[$0] }
        guard !readMinutes.isEmpty else { return max(goal, 20) }
        let typical = InsightsMath.median(readMinutes)
        // Trust the typical day more as the evidence grows, but never let it take over from the goal completely.
        let weight = 0.5 * min(1, Double(readMinutes.count) / 10)
        let blended = goal > 0 ? goal * (1 - weight) + typical * weight : typical
        return min(240, max(5, blended))
    }
}
