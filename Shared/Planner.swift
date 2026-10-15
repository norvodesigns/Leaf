import Foundation

struct PlanInput: Sendable {
    /// Reading shelf, in order.
    var reading: [LibraryItem]
    /// To-read queue, in order.
    var queue: [LibraryItem]
    var wpm: Double
    var dailyMinutes: Int
    var readingDays: Set<Int>
    var mode: PlanMode
    var today: Date
    /// Minutes already read today; today's assignment covers only what's left of the goal.
    var minutesReadToday: Double = 0
    var calendar: Calendar = .current
    /// Simulation horizon. Anything that would finish later has no finish date.
    var maxDays: Int = 3650
}

/// One book's slot in the plan.
struct PlannedBook: Identifiable, Hashable, Sendable {
    var id: String
    /// First day the plan has you reading it (today for books already underway).
    var start: Date
    /// Day you finish it, or nil if it's beyond the horizon (or you have no reading time).
    var finish: Date?
    /// Minutes left to read at plan time.
    var minutesLeft: Double
    /// Number of reading days it spans.
    var readingDays: Int
    var isReading: Bool
}

/// What to read on a given day for one book.
struct Assignment: Hashable, Identifiable, Sendable {
    var bookID: String
    var minutes: Double
    /// First page to read (1-based).
    var fromPage: Int
    /// Page you'll reach.
    var toPage: Int
    var finishesBook: Bool

    var id: String { bookID }
}

struct PlanDay: Hashable, Sendable {
    var date: Date
    var isReadingDay: Bool
    var assignments: [Assignment]

    var minutes: Double { assignments.reduce(0) { $0 + $1.minutes } }
}

struct ReadingPlan: Sendable {
    var books: [PlannedBook]
    /// The first few days starting today, including rest days (empty assignments).
    var days: [PlanDay]
    var generatedAt: Date

    static let empty = ReadingPlan(books: [], days: [], generatedAt: .distantPast)

    var today: PlanDay? { days.first }

    func book(_ id: String) -> PlannedBook? { books.first { $0.id == id } }

    func finishedCount(onOrBefore date: Date) -> Int {
        books.filter { ($0.finish ?? .distantFuture) <= date }.count
    }

    /// The day everything currently planned is done, if it's within the horizon.
    var allDone: Date? {
        guard !books.isEmpty, books.allSatisfy({ $0.finish != nil }) else { return nil }
        return books.compactMap(\.finish).max()
    }
}

enum Planner {
    /// Smallest amount of reading worth scheduling.
    static let minimumChunk = 0.5
    /// Don't start a fresh book on a day that already has reading, unless at least this much time is left.
    static let minimumToStartNewBook = 5.0

    static func makePlan(_ input: PlanInput, recordDays: Int = 21) -> ReadingPlan {
        let calendar = input.calendar
        let wpm = max(input.wpm, 40)
        let startDay = calendar.startOfDay(for: input.today)

        struct Track {
            var item: LibraryItem
            var isReading: Bool
            var page: Double
            var wordsLeft: Double
            var initialMinutes: Double
            var start: Date?
            var finish: Date?
            var days = 0
            var done: Bool { wordsLeft <= 0.5 }
        }

        var tracks: [Track] = (input.reading.map { ($0, true) } + input.queue.map { ($0, false) }).map { item, isReading in
            let pages = Double(item.book.pages)
            let page = min(pages, max(0, Double(item.currentPage)))
            let wordsLeft = max(0, (pages - page) * item.book.wordsPerPage)
            var track = Track(item: item, isReading: isReading, page: page, wordsLeft: wordsLeft, initialMinutes: wordsLeft / wpm)
            if track.done {
                track.start = startDay
                track.finish = startDay
            }
            return track
        }

        let slots = input.mode == .sideBySide ? max(1, input.reading.count) : 1
        let canRead = input.dailyMinutes > 0 && !input.readingDays.isEmpty
        var days: [PlanDay] = []

        var dayIndex = 0
        while dayIndex < input.maxDays {
            guard let date = calendar.date(byAdding: .day, value: dayIndex, to: startDay) else { break }
            let weekday = calendar.component(.weekday, from: date)
            let isReadingDay = input.readingDays.contains(weekday)
            var todays: [String: Assignment] = [:]
            var order: [String] = []

            if canRead && isReadingDay {
                var budget = Double(input.dailyMinutes)
                if dayIndex == 0 { budget = max(0, budget - input.minutesReadToday) }
                var spentToday = 0.0

                while budget >= minimumChunk {
                    let active = tracks.indices.filter { !tracks[$0].done }.prefix(slots)
                    guard !active.isEmpty else { break }
                    if spentToday > 0, budget < minimumToStartNewBook, active.contains(where: { tracks[$0].start == nil }) { break }

                    let share = budget / Double(active.count)
                    var spentThisRound = 0.0
                    var finishedOne = false
                    for index in active {
                        let need = tracks[index].wordsLeft / wpm
                        let spend = min(share, need)
                        guard spend > 0 else { continue }
                        let fromPage = tracks[index].page
                        let wordsRead = spend * wpm
                        tracks[index].wordsLeft = max(0, tracks[index].wordsLeft - wordsRead)
                        let pages = Double(tracks[index].item.book.pages)
                        tracks[index].page = tracks[index].done ? pages : min(pages, fromPage + wordsRead / tracks[index].item.book.wordsPerPage)
                        if tracks[index].start == nil { tracks[index].start = date }
                        if tracks[index].done {
                            tracks[index].finish = date
                            finishedOne = true
                        }
                        spentThisRound += spend

                        let id = tracks[index].item.id
                        let fromDisplay = min(Int(pages), Int(fromPage.rounded(.down)) + 1)
                        let toDisplay = max(fromDisplay, min(Int(pages), Int(tracks[index].page.rounded(.up))))
                        if var existing = todays[id] {
                            existing.minutes += spend
                            existing.toPage = toDisplay
                            existing.finishesBook = tracks[index].done
                            todays[id] = existing
                        } else {
                            todays[id] = Assignment(bookID: id, minutes: spend, fromPage: fromDisplay, toPage: toDisplay, finishesBook: tracks[index].done)
                            order.append(id)
                            tracks[index].days += 1
                        }
                    }
                    budget -= spentThisRound
                    spentToday += spentThisRound
                    if !finishedOne || spentThisRound <= 0 { break }
                }
            }

            if dayIndex < recordDays {
                days.append(PlanDay(date: date, isReadingDay: isReadingDay, assignments: order.compactMap { todays[$0] }))
            }
            let allDone = tracks.allSatisfy(\.done)
            if dayIndex >= recordDays - 1 && (allDone || !canRead) { break }
            dayIndex += 1
        }

        let books = tracks.map { track in
            PlannedBook(
                id: track.item.id,
                start: track.start ?? startDay,
                finish: track.finish,
                minutesLeft: track.initialMinutes,
                readingDays: track.days,
                isReading: track.isReading
            )
        }
        return ReadingPlan(books: books, days: days, generatedAt: input.today)
    }

    /// Back-of-the-envelope books per year, used while choosing daily minutes.
    static func booksPerYear(wpm: Double, dailyMinutes: Int, daysPerWeek: Int, averageWords: Double = 80_000) -> Double {
        guard averageWords > 0 else { return 0 }
        return Double(dailyMinutes) * Double(daysPerWeek) * (365.25 / 7) * max(wpm, 1) / averageWords
    }
}
