import Foundation

/// What to offer a reader whose book has gone quiet.
enum StallSuggestion: String, Hashable, Sendable {
    /// Set the book aside for now (the store's `pause`); it keeps its page.
    case setAside
    /// The book is nearly done, so the kindest nudge is a few pages rather than a rest.
    case almostThere
}

/// A Reading book with no progress for a while.
struct StalledBook: Identifiable, Hashable, Sendable {
    var bookID: String
    var title: String
    var daysIdle: Int
    /// The last time the reader read it or touched its page, if known.
    var lastTouched: Date?
    var percentRead: Int
    var suggestion: StallSuggestion

    var id: String { bookID }
}

extension ForecastEngine {
    /// Reading-shelf books with no progress for `thresholdDays` (14 by default), longest quiet first. Paused, finished
    /// and queued books are never reported, and neither is a book with a live session on it.
    func stalledBooks(thresholdDays: Int? = nil) -> [StalledBook] {
        let threshold = max(1, thresholdDays ?? options.stallDays)
        var lastRead: [String: Date] = [:]
        for record in records where record.pages > 0 {
            if let existing = lastRead[record.bookID], existing >= record.startedAt { continue }
            lastRead[record.bookID] = record.startedAt
        }
        var stalled: [StalledBook] = []
        for item in reading {
            if data.activeSession?.bookID == item.id { continue }
            let touches = [lastRead[item.id], item.startedAt, item.updatedAt > .distantPast ? item.updatedAt : nil].compactMap { $0 }
            let last = touches.max() ?? item.addedAt
            guard last <= now else { continue }
            let idle = today - days.number(last)
            guard idle >= threshold else { continue }
            let percent = item.percent
            stalled.append(StalledBook(
                bookID: item.id, title: item.book.title, daysIdle: idle, lastTouched: last,
                percentRead: percent, suggestion: percent >= 85 ? .almostThere : .setAside
            ))
        }
        return stalled.sorted { $0.daysIdle == $1.daysIdle ? $0.bookID < $1.bookID : $0.daysIdle > $1.daysIdle }
    }
}
