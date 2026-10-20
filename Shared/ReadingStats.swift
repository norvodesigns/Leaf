import Foundation

struct DayStat: Hashable, Identifiable, Sendable {
    var date: Date
    var minutes: Double
    var isReadingDay: Bool
    var isToday: Bool

    var id: Date { date }
}

enum ReadingStats {
    static func minutesRead(on day: Date, sessions: [ReadingSession], calendar: Calendar = .current) -> Double {
        sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            .reduce(0) { $0 + $1.minutes }
    }

    /// Consecutive reading days with some reading, counting back from today.
    /// Rest days never break a streak; today only counts once you've read.
    static func streak(sessions: [ReadingSession], readingDays: Set<Int>, today: Date, calendar: Calendar = .current) -> Int {
        guard !sessions.isEmpty else { return 0 }
        let readDays = Set(sessions.filter { $0.seconds >= 60 }.map { calendar.startOfDay(for: $0.startedAt) })
        let schedule = readingDays.isEmpty ? Set(1...7) : readingDays
        var day = calendar.startOfDay(for: today)
        var count = 0
        if readDays.contains(day) { count += 1 }
        for _ in 0..<3650 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            let scheduled = schedule.contains(calendar.component(.weekday, from: day))
            if readDays.contains(day) {
                count += 1
            } else if scheduled {
                break
            }
        }
        return count
    }

    /// The current calendar week, with minutes read per day.
    static func week(containing today: Date, sessions: [ReadingSession], readingDays: Set<Int>, calendar: Calendar = .current) -> [DayStat] {
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DayStat(
                date: date,
                minutes: minutesRead(on: date, sessions: sessions, calendar: calendar),
                isReadingDay: readingDays.contains(calendar.component(.weekday, from: date)),
                isToday: calendar.isDate(date, inSameDayAs: today)
            )
        }
    }

    /// Finishes in `year`, counting each read-through: a book read twice this year counts twice.
    static func booksFinished(in year: Int, items: [LibraryItem], calendar: Calendar = .current) -> Int {
        var count = 0
        for item in items {
            for read in item.readThroughs where calendar.component(.year, from: read.finishedAt) == year {
                count += 1
            }
        }
        return count
    }

    static func totalMinutes(_ sessions: [ReadingSession]) -> Double {
        sessions.reduce(0) { $0 + $1.minutes }
    }

    static func totalPages(_ sessions: [ReadingSession]) -> Int {
        sessions.reduce(0) { $0 + $1.pagesRead }
    }
}
