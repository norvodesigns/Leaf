import Foundation

/// The parts of sharing a circle over iCloud that don't need CloudKit: who "me" is on this device, joining a circle
/// someone shared, and writing the reader's own progress into their member so the others see it. Pure.
///
/// In a shared circle every member that stands for a person in the share carries that person's iCloud user record
/// name in `remoteID`. `kind` is relative to the device that holds the copy, so each device works it out again from
/// `remoteID` (`localized`) before merging or showing a copy it fetched.
enum CircleShareRules {
    /// The circle as this device sees it: the member whose `remoteID` is this iCloud user is `.me`, and once there is
    /// one, every other member is a friend. Without a match (a circle that was never shared) nothing changes.
    static func localized(_ circle: ReadingCircle, me: String?) -> ReadingCircle {
        guard let me, circle.members.contains(where: { $0.remoteID == me }) else { return circle }
        var copy = circle
        for index in copy.members.indices {
            copy.members[index].kind = copy.members[index].remoteID == me ? .me : .friend
        }
        // The reader first, as everywhere else.
        if let mine = copy.members.firstIndex(where: { $0.kind == .me }), mine != 0 {
            copy.members.insert(copy.members.remove(at: mine), at: 0)
        }
        return copy
    }

    /// The owner, before sharing: their own member names their iCloud user, so the copies the others get can tell
    /// them apart. Stamped `now` when it changes.
    static func claimingMe(_ circle: ReadingCircle, me: String, now: Date) -> ReadingCircle {
        guard let index = circle.members.firstIndex(where: { $0.kind == .me }), circle.members[index].remoteID != me else { return circle }
        var copy = circle
        copy.members[index].remoteID = me
        copy.members[index].updatedAt = now
        copy.updatedAt = now
        return copy
    }

    /// Someone who accepted an invitation: a member for them if the circle has none yet, first in the list, with
    /// the name the share knows them by. Stamped `now`, which also moves the circle so the join travels.
    static func joining(_ circle: ReadingCircle, me: String, name: String, paletteToken: String, now: Date) -> ReadingCircle {
        guard !circle.members.contains(where: { $0.remoteID == me }) else { return localized(circle, me: me) }
        // Whoever was "me" in the copy that arrived is someone else here.
        var copy = circle
        for index in copy.members.indices { copy.members[index].kind = .friend }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = CircleMember(name: trimmed.isEmpty ? "A friend" : trimmed, kind: .me, paletteToken: paletteToken, remoteID: me, updatedAt: now)
        copy.members.insert(joined, at: 0)
        copy.updatedAt = now
        return localized(copy, me: me)
    }

    /// The reader's page (from their library) written into their own member, so the others see how far they are,
    /// and noted in the member's log for the circle's standings and "lately" list. The first time it is where they
    /// start. Unchanged when there is no page, or it is already there and logged.
    static func withMyPage(_ circle: ReadingCircle, page: Int?, now: Date) -> ReadingCircle {
        guard let page, let index = circle.members.firstIndex(where: { $0.kind == .me }) else { return circle }
        let clamped = min(max(0, page), circle.book.pages)
        guard circle.members[index].page != clamped || circle.members[index].log.isEmpty else { return circle }
        var copy = circle
        copy.members[index].move(to: clamped, at: now)
        copy.updatedAt = now
        return copy
    }

    /// The reader's own copy of a circle's book: the same book, or else another edition of it (the same title, with
    /// or without a subtitle, by the same author), so a circle doesn't need the exact edition its owner picked. A copy
    /// on Reading comes first, then Paused, To Read and Finished.
    static func libraryCopy(of book: Book, in items: [LibraryItem]) -> LibraryItem? {
        if let same = items.first(where: { $0.id == book.id }) { return same }
        let key = editionKey(book)
        let order: [Shelf] = [.reading, .paused, .toRead, .finished]
        let rank = { (item: LibraryItem) in order.firstIndex(of: item.shelf) ?? order.count }
        return items.filter { editionKey($0.book) == key }.min { rank($0) < rank($1) }
    }

    /// What joining a circle does to the library.
    enum BookStep: Equatable {
        /// No copy yet: the circle's book goes on Reading.
        case add
        /// A copy waiting on To Read or Paused moves to Reading.
        case startReading(String)
        /// A copy being read or already finished stays where it is.
        case keep(String)
    }

    /// Someone who joins usually doesn't have the book yet; on Reading, their page in the circle moves as they read.
    static func bookStep(for book: Book, in items: [LibraryItem]) -> BookStep {
        guard let copy = libraryCopy(of: book, in: items) else { return .add }
        switch copy.shelf {
        case .toRead, .paused: return .startReading(copy.id)
        case .reading, .finished: return .keep(copy.id)
        }
    }

    /// Title without its subtitle, and author, folded as the recommender folds titles for de-duplication.
    private static func editionKey(_ book: Book) -> String {
        let title = book.title.split(separator: ":", maxSplits: 1).first.map(String.init) ?? book.title
        return TasteProfile.normalizeAuthor(title) + "|" + TasteProfile.normalizeAuthor(book.author)
    }

    /// The zone a shared circle lives in. One zone per circle, shared as a whole.
    static func zoneName(for circleID: UUID) -> String { zonePrefix + circleID.uuidString }

    /// The circle a zone holds, or nil for any other zone.
    static func circleID(inZone name: String) -> UUID? {
        guard name.hasPrefix(zonePrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(zonePrefix.count)))
    }

    static let zonePrefix = "Circle-"
}
