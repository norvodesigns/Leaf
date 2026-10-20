import Foundation

/// One book's whole story as beads on a line: every sitting (pages, minutes, tea), notes, quotes and tasting notes in
/// between, grouped into read-throughs ("Second read", "First read") with the current one first. Pure.
struct BookTimeline: Hashable, Sendable {
    struct Bead: Identifiable, Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case started
            case sitting(minutes: Double, fromPage: Int, toPage: Int, teaName: String?, isTyped: Bool)
            case note(text: String, page: Int?, isFavorite: Bool)
            case quote(text: String, page: Int?, isFavorite: Bool)
            case tasting(teaName: String, summary: String, rating: Int?)
            case finished(rating: Int?, days: Int?)
            case setAside
        }

        var id: String
        var date: Date
        var kind: Kind
    }

    struct Chapter: Identifiable, Hashable, Sendable {
        /// "Reading now", "Second read", "First read".
        var title: String
        /// "11 Sept 2024 to 2 Oct 2024 · 22 days", worked out by the view from these.
        var startedAt: Date?
        var finishedAt: Date?
        /// The read-through this chapter is, when it is finished.
        var read: ReadThrough?
        var isCurrent: Bool
        /// Oldest first, so the line reads from the start to the finish.
        var beads: [Bead]
        var minutes: Double
        var sittings: Int

        var id: String { read?.id.uuidString ?? "current" }
    }

    /// Newest read-through first.
    var chapters: [Chapter]
    var timesFinished: Int

    var isEmpty: Bool { chapters.allSatisfy { $0.beads.isEmpty } }

    static func build(item: LibraryItem, data: LeafData, calendar: Calendar) -> BookTimeline {
        let reads = item.readThroughs
        let sessions = data.sessions
            .filter { $0.bookID == item.id }
            .sorted { (a: ReadingSession, b: ReadingSession) -> Bool in
                if a.startedAt != b.startedAt { return a.startedAt < b.startedAt }
                return a.id.uuidString < b.id.uuidString
            }
        let journal = data.journal.filter { $0.bookID == item.id }
        let tastings = data.tastings.filter { $0.bookID == item.id }

        // Each finished read-through owns what happened after the previous finish, up to and including its own.
        var bounds: [(read: ReadThrough?, end: Date?)] = reads.map { ($0, $0.finishedAt) }
        let hasCurrent = item.shelf != .finished
        if hasCurrent { bounds.append((nil, nil)) }

        var chapters: [Chapter] = []
        var previousEnd: Date?
        for (index, bound) in bounds.enumerated() {
            func belongs(_ date: Date) -> Bool {
                if let previousEnd, date <= previousEnd { return false }
                if let end = bound.end, date > end.addingTimeInterval(60) { return false }
                return true
            }
            var beads: [Bead] = []
            var minutes = 0.0
            var count = 0
            for session in sessions where belongs(session.startedAt) {
                let sessionMinutes: Double = max(0, session.seconds) / 60
                let teaName: String? = TeaShelf.tea(id: session.teaID, cabinet: data.cabinet)?.name
                let isTyped: Bool = session.kind == .manual
                minutes += sessionMinutes
                count += 1
                let kind = Bead.Kind.sitting(
                    minutes: sessionMinutes, fromPage: session.fromPage, toPage: session.toPage, teaName: teaName, isTyped: isTyped
                )
                beads.append(Bead(id: "session.\(session.id.uuidString)", date: session.startedAt, kind: kind))
            }
            for entry in journal where belongs(entry.createdAt) {
                let kind: Bead.Kind = entry.kind == .quote
                    ? .quote(text: entry.text, page: entry.page, isFavorite: entry.isFavorite)
                    : .note(text: entry.text, page: entry.page, isFavorite: entry.isFavorite)
                beads.append(Bead(id: "journal.\(entry.id.uuidString)", date: entry.createdAt, kind: kind))
            }
            for note in tastings where belongs(note.createdAt) {
                let teaName: String = note.teaName.isEmpty ? "A tea" : note.teaName
                let kind = Bead.Kind.tasting(teaName: teaName, summary: note.summary, rating: note.rating)
                beads.append(Bead(id: "tasting.\(note.id.uuidString)", date: note.createdAt, kind: kind))
            }

            let start: Date?
            if let read = bound.read {
                start = read.startedAt
            } else {
                start = item.startedAt
            }
            if let start, bound.read != nil || belongs(start) {
                beads.append(Bead(id: "start.\(index)", date: start, kind: .started))
            }
            if let read = bound.read {
                let kind = Bead.Kind.finished(rating: read.rating, days: read.days(calendar: calendar))
                beads.append(Bead(id: "finish.\(read.id.uuidString)", date: read.finishedAt, kind: kind))
            } else if item.shelf == .paused, let pausedAt = item.pausedAt {
                beads.append(Bead(id: "aside", date: pausedAt, kind: .setAside))
            }
            beads.sort(by: BookTimeline.comesBefore)

            let title: String
            if let read = bound.read, let position = reads.firstIndex(of: read) {
                title = ReadsHistory.ordinal(position + 1)
            } else {
                title = item.shelf == .paused ? "Set aside" : (reads.isEmpty ? "This read" : "Reading again")
            }
            if bound.read != nil || !beads.isEmpty {
                chapters.append(Chapter(
                    title: title, startedAt: start, finishedAt: bound.read?.finishedAt, read: bound.read,
                    isCurrent: bound.read == nil, beads: beads, minutes: minutes, sittings: count
                ))
            }
            previousEnd = bound.end ?? previousEnd
        }
        return BookTimeline(chapters: chapters.reversed(), timesFinished: reads.count)
    }

    /// Oldest first; on the same moment a start comes first and a finish last.
    private static func comesBefore(_ a: Bead, _ b: Bead) -> Bool {
        if a.date != b.date { return a.date < b.date }
        if rank(a.kind) != rank(b.kind) { return rank(a.kind) < rank(b.kind) }
        return a.id < b.id
    }

    private static func rank(_ kind: Bead.Kind) -> Int {
        switch kind {
        case .started: return 0
        case .sitting: return 1
        case .note, .quote: return 2
        case .tasting: return 3
        case .setAside: return 4
        case .finished: return 5
        }
    }
}
