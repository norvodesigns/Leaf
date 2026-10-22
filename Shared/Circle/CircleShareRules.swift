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

    /// The reader's page (from their library) written into their own member, so the others see how far they are.
    /// Unchanged when there is no page or it is already there.
    static func withMyPage(_ circle: ReadingCircle, page: Int?, now: Date) -> ReadingCircle {
        guard let page, let index = circle.members.firstIndex(where: { $0.kind == .me }) else { return circle }
        let clamped = min(max(0, page), circle.book.pages)
        guard circle.members[index].page != clamped else { return circle }
        var copy = circle
        copy.members[index].page = clamped
        copy.members[index].updatedAt = now
        copy.updatedAt = now
        return copy
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
