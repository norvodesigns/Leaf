import Foundation

// MARK: - A read-through

/// One time through a book, from the day it was begun to the day it was finished, and how the reader rated it then.
///
/// When a finished book is started again, its read-through moves into `LibraryItem.reads` and the item's own dates
/// start over. The current read-through lives in the item's `startedAt`, `finishedAt` and `rating` until it too is
/// finished and the book is begun again. `LibraryItem.readThroughs` puts both together.
struct ReadThrough: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var startedAt: Date?
    var finishedAt: Date
    /// 1 to 5, or nil when this read-through wasn't rated.
    var rating: Int?
    /// Last change, for iCloud merging (newest wins per read-through).
    var updatedAt: Date

    init(id: UUID, startedAt: Date?, finishedAt: Date, rating: Int? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.rating = rating.map { min(5, max(1, $0)) }
        self.updatedAt = updatedAt ?? finishedAt
    }

    /// A read-through of `bookID` that finished at `finishedAt`, with the id every device gives it.
    init(bookID: String, startedAt: Date?, finishedAt: Date, rating: Int? = nil, updatedAt: Date? = nil) {
        self.init(
            id: ReadThrough.stableID(bookID: bookID, finishedAt: finishedAt),
            startedAt: startedAt, finishedAt: finishedAt, rating: rating, updatedAt: updatedAt
        )
    }

    /// The same read-through gets the same id on every device: it comes from the book and the finish (to the second),
    /// so two devices that both keep a finish when a book is started again keep one read-through, not two.
    static func stableID(bookID: String, finishedAt: Date) -> UUID {
        let second = Int64(finishedAt.timeIntervalSince1970.rounded())
        let key = "read|\(bookID)|\(second)"
        func hex(_ value: UInt64) -> String {
            let text = String(value, radix: 16, uppercase: true)
            return String(repeating: "0", count: 16 - text.count) + text
        }
        let all = Array(hex(SeededGenerator.hash(key)) + hex(SeededGenerator.hash(key + "|2")))
        let text = String(all[0..<8]) + "-" + String(all[8..<12]) + "-" + String(all[12..<16]) + "-"
            + String(all[16..<20]) + "-" + String(all[20..<32])
        return UUID(uuidString: text) ?? UUID()
    }

    enum CodingKeys: String, CodingKey {
        case id, startedAt, finishedAt, rating, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let finishedAt = try c.decode(Date.self, forKey: .finishedAt)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            startedAt: try c.decodeIfPresent(Date.self, forKey: .startedAt),
            finishedAt: finishedAt,
            rating: try c.decodeIfPresent(Int.self, forKey: .rating),
            updatedAt: try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }

    /// Oldest finish first, then by id.
    static func isEarlier(_ a: ReadThrough, _ b: ReadThrough) -> Bool {
        if a.finishedAt != b.finishedAt { return a.finishedAt < b.finishedAt }
        return a.id.uuidString < b.id.uuidString
    }

    /// Calendar days from start to finish, counting both ends; nil when the start is unknown.
    func days(calendar: Calendar) -> Int? {
        guard let startedAt else { return nil }
        let span = calendar.dateComponents([.day], from: calendar.startOfDay(for: startedAt), to: calendar.startOfDay(for: finishedAt)).day ?? 0
        return max(1, span + 1)
    }
}

// MARK: - A book's read-throughs

extension LibraryItem {
    /// Every finished read-through, oldest first: the earlier ones, then the current one when the book is on Finished.
    var readThroughs: [ReadThrough] {
        var all = reads
        if shelf == .finished, let finishedAt {
            var current = ReadThrough(bookID: id, startedAt: startedAt, finishedAt: finishedAt, updatedAt: updatedAt)
            // The book's own rating as it stands, unclamped: statistics decide what counts as a rating.
            current.rating = rating
            // A stale copy that still shows the finish already kept in `reads` must not count it twice.
            let kept = all.contains { $0.id == current.id || abs($0.finishedAt.timeIntervalSince(finishedAt)) < 60 }
            if !kept { all.append(current) }
        }
        return all.sorted(by: ReadThrough.isEarlier)
    }

    /// The book as it stood at one read-through: finished, with that read-through's dates and rating. Statistics that
    /// count finishes use these, so a book read twice counts twice.
    func asOf(_ read: ReadThrough) -> LibraryItem {
        var copy = self
        copy.shelf = .finished
        copy.startedAt = read.startedAt
        copy.finishedAt = read.finishedAt
        copy.rating = read.rating
        copy.currentPage = book.pages
        return copy
    }

    /// The item with its current finish kept in `reads`, as when a finished book is started again or put back on a
    /// shelf. Unchanged when the book isn't finished.
    func keepingCurrentRead(now: Date) -> LibraryItem {
        guard shelf == .finished, let finishedAt else { return self }
        var copy = self
        let read = ReadThrough(bookID: id, startedAt: startedAt, finishedAt: finishedAt, rating: rating, updatedAt: now)
        if !copy.reads.contains(where: { $0.id == read.id }) { copy.reads.append(read) }
        copy.reads.sort(by: ReadThrough.isEarlier)
        return copy
    }
}

// MARK: - Reads before reads were kept

enum ReadsHistory {
    /// "First read", "Second read" … "Read 11".
    static func ordinal(_ number: Int) -> String {
        let words = ["First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth", "Tenth"]
        guard number >= 1 else { return "A read" }
        return number <= words.count ? "\(words[number - 1]) read" : "Read \(number)"
    }

    /// Earlier read-throughs the sessions show but `reads` doesn't hold: Leaf used to start a reread over without
    /// keeping the last finish. A session that ended more than a day before the current `startedAt` belongs to an
    /// earlier read-through (`SyncPolicy.readThroughSlack`, the merge's own rule); each one that reached the last page
    /// closes a read that began with the first such session after the previous close. Unrated, stamped at the finish.
    static func recovered(for item: LibraryItem, sessions: [ReadingSession]) -> [ReadThrough] {
        guard let current = item.startedAt, item.book.pages > 0 else { return [] }
        let boundary = current.addingTimeInterval(-SyncPolicy.readThroughSlack)
        let earlier = sessions
            .filter { $0.bookID == item.id && $0.startedAt.addingTimeInterval(max(0, $0.seconds)) < boundary }
            .sorted { (a: ReadingSession, b: ReadingSession) -> Bool in
                if a.startedAt != b.startedAt { return a.startedAt < b.startedAt }
                return a.id.uuidString < b.id.uuidString
            }
        var found: [ReadThrough] = []
        var start: Date?
        for session in earlier {
            if start == nil { start = session.startedAt }
            guard session.toPage >= item.book.pages else { continue }
            let finish = session.startedAt.addingTimeInterval(max(0, session.seconds))
            found.append(ReadThrough(bookID: item.id, startedAt: start, finishedAt: finish))
            start = nil
        }
        return found.filter { read in
            !item.reads.contains { $0.id == read.id || abs($0.finishedAt.timeIntervalSince(read.finishedAt)) < 60 }
        }
    }
}

extension LeafData {
    /// Old saved data, from before Leaf kept every read-through: earlier ones recovered from sessions. Deterministic
    /// and unstamped, so every device recovers the same read-throughs without sending anything; they travel with the
    /// book the next time it changes.
    func withRecoveredReads() -> LeafData {
        var sessionsByBook: [String: [ReadingSession]] = [:]
        for session in sessions { sessionsByBook[session.bookID, default: []].append(session) }
        var copy = self
        for index in copy.items.indices {
            let item = copy.items[index]
            let found = ReadsHistory.recovered(for: item, sessions: sessionsByBook[item.id] ?? [])
            guard !found.isEmpty else { continue }
            copy.items[index].reads = (item.reads + found).sorted(by: ReadThrough.isEarlier)
        }
        return copy
    }
}
