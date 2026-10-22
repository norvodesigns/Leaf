import Foundation

/// A deletion's identity: what was deleted, not when.
struct SyncTombstoneKey: Hashable, Sendable {
    var kind: Tombstone.Kind
    var key: String
}

extension LeafData {
    /// Merges another device's data into this one and returns the result. `self` is the local side.
    ///
    /// The merge is a pure function of the two states and `now`. For a fixed `now` it is commutative,
    /// associative and idempotent, so devices converge whatever order they exchange data in. The only two things
    /// that differ by side are the device's own settings (haptics, appearance, whether sync is on) and the live
    /// session: both always keep the local value. The tombstone clock is the only thing `now` changes.
    ///
    /// The rules, in one place (docs/SYNC.md has the table):
    /// - Library items: per book id, the newest `updatedAt` wins as a whole.
    /// - A tombstone removes an item (or journal entry, or challenge) only if it is strictly later than the
    ///   thing's own stamp, so re-adding after a delete wins. An equal stamp keeps the thing.
    /// - Sessions are a union by id and are never removed.
    /// - After merging, a book that is being read (or paused) is never behind its sessions: its page is raised to the
    ///   furthest page any of its sessions reached, clamped to the page count.
    /// - Preferences: the newest `updatedAt` wins as a whole, except the device's own settings, `hasOnboarded`
    ///   (true if either side is) and `onboardedAt` (the earliest).
    /// - Tombstones older than 90 days are dropped before anything else, so they stop having any effect, except a
    ///   removed read-through's: those are kept, since every device recovers old read-throughs from sessions again.
    func merged(with remote: LeafData, now: Date) -> LeafData {
        let cutoff = now.addingTimeInterval(-SyncPolicy.tombstoneLifetime)
        let tombstones = SyncMerge.tombstones(self.tombstones, remote.tombstones, cutoff: cutoff)
        var deletedAt: [SyncTombstoneKey: Date] = [:]
        for tombstone in tombstones { deletedAt[SyncTombstoneKey(kind: tombstone.kind, key: tombstone.key)] = tombstone.deletedAt }

        var out = LeafData()
        out.version = max(version, remote.version)
        out.tombstones = tombstones
        out.sessions = SyncMerge.sessions(self.sessions, remote.sessions)
        out.items = SyncMerge.items(self.items, remote.items, deletedAt: deletedAt, sessions: out.sessions)
        out.journal = SyncMerge.journal(self.journal, remote.journal, deletedAt: deletedAt)
        out.speedTests = SyncMerge.speedTests(self.speedTests, remote.speedTests)
        out.dismissed = SyncMerge.dismissed(self.dismissed, remote.dismissed, deletedAt: deletedAt)
        out.challenges = SyncMerge.challenges(self.challenges, remote.challenges, deletedAt: deletedAt)
        out.cabinet = SyncMerge.newest(self.cabinet, remote.cabinet, kind: .cabinetTea, deletedAt: deletedAt, stamp: \.updatedAt) {
            $0.addedAt != $1.addedAt ? $0.addedAt < $1.addedAt : $0.id.uuidString < $1.id.uuidString
        }
        out.tastings = SyncMerge.newest(self.tastings, remote.tastings, kind: .tasting, deletedAt: deletedAt, stamp: \.updatedAt) {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString
        }
        out.circles = SyncMerge.circles(self.circles, remote.circles, deletedAt: deletedAt)
        out.preferences = SyncMerge.preferences(local: preferences, remote: remote.preferences)
        // The live session never syncs. It also cannot outlive its book: if the book was deleted elsewhere there is
        // nothing left to log it against.
        if let active = activeSession, out.items.contains(where: { $0.id == active.bookID }) {
            out.activeSession = active
        }
        return out
    }

    /// The same data without the given tombstones. A device that took a deletion back (re-added the book, undid a
    /// "not for me") removes the tombstone record, and the others remove it from their lists when they hear of it.
    func removingTombstones(_ keys: [SyncTombstoneKey]) -> LeafData {
        guard !keys.isEmpty else { return self }
        let gone = Set(keys)
        var copy = self
        copy.tombstones.removeAll { gone.contains(SyncTombstoneKey(kind: $0.kind, key: $0.key)) }
        return copy
    }
}

/// The individual merge rules. Each takes both sides and returns the merged collection in a canonical order, so
/// the result does not depend on which side was local.
enum SyncMerge {
    // MARK: Ordering helpers

    /// The entity as JSON with sorted keys: a stable string of bytes to break ties with.
    static func canonicalBytes<T: Encodable>(_ value: T) -> [UInt8] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).map { Array($0) } ?? []
    }

    /// Orders text by its UTF-8 bytes. Swift's own `<` treats canonically equivalent strings as equal, which would
    /// leave ties for two different ids.
    static func bytewiseLess(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }

    /// Of two different values that share a key and a stamp, the one that wins everywhere: the larger JSON.
    private static func larger<T: Encodable & Equatable>(_ a: T, _ b: T) -> T {
        if a == b { return a }
        return canonicalBytes(a).lexicographicallyPrecedes(canonicalBytes(b)) ? b : a
    }

    // MARK: Tombstones

    static func tombstones(_ a: [Tombstone], _ b: [Tombstone], cutoff: Date) -> [Tombstone] {
        var latest: [SyncTombstoneKey: Date] = [:]
        for tombstone in a + b where tombstone.deletedAt >= cutoff || tombstone.kind == .read {
            let key = SyncTombstoneKey(kind: tombstone.kind, key: tombstone.key)
            if let existing = latest[key], existing >= tombstone.deletedAt { continue }
            latest[key] = tombstone.deletedAt
        }
        return latest
            .map { Tombstone(kind: $0.key.kind, key: $0.key.key, deletedAt: $0.value) }
            .sorted { lhs, rhs in
                lhs.kind == rhs.kind ? bytewiseLess(lhs.key, rhs.key) : lhs.kind.rawValue < rhs.kind.rawValue
            }
    }

    // MARK: Library items

    /// True when `a` must lose to `b`. Newest stamp wins. A tie goes to the larger JSON of everything except the
    /// page and its confirmation, and only after that to the further page. Keeping the page last is what lets
    /// the "never behind its sessions" repair run at any point in a chain of merges without changing who wins.
    static func loses(_ a: LibraryItem, to b: LibraryItem) -> Bool {
        if a == b { return false }
        if a.updatedAt != b.updatedAt { return a.updatedAt < b.updatedAt }
        let ka = canonicalBytes(orderingView(a))
        let kb = canonicalBytes(orderingView(b))
        if ka != kb { return ka.lexicographicallyPrecedes(kb) }
        if a.currentPage != b.currentPage { return a.currentPage < b.currentPage }
        return !a.positionConfirmed && b.positionConfirmed
    }

    private static func orderingView(_ item: LibraryItem) -> LibraryItem {
        var view = item
        // Earlier read-throughs are merged on their own, so they never decide which copy wins.
        view.reads = []
        view.currentPage = 0
        view.positionConfirmed = false
        return view
    }

    static func items(
        _ a: [LibraryItem],
        _ b: [LibraryItem],
        deletedAt: [SyncTombstoneKey: Date],
        sessions: [ReadingSession]
    ) -> [LibraryItem] {
        var best: [String: LibraryItem] = [:]
        for item in a + b {
            if let existing = best[item.id], !loses(existing, to: item) { continue }
            best[item.id] = item
        }
        var sessionsByBook: [String: [ReadingSession]] = [:]
        for session in sessions { sessionsByBook[session.bookID, default: []].append(session) }
        // Earlier read-throughs merge one by one, whichever copy of the book wins: a reread kept on one device and a
        // rating changed on another both survive.
        var readsA: [String: [ReadThrough]] = [:]
        var readsB: [String: [ReadThrough]] = [:]
        for item in a { readsA[item.id, default: []].append(contentsOf: item.reads) }
        for item in b { readsB[item.id, default: []].append(contentsOf: item.reads) }

        var out: [LibraryItem] = []
        for (id, item) in best {
            if let deleted = deletedAt[SyncTombstoneKey(kind: .item, key: id)], deleted > item.updatedAt { continue }
            var merged = item
            merged.reads = newest(readsA[id] ?? [], readsB[id] ?? [], kind: .read, deletedAt: deletedAt, stamp: \.updatedAt, order: ReadThrough.isEarlier)
            // A book deleted and then brought back keeps only the read-throughs kept after the deletion, in whatever
            // order devices merge (a read-through is never newer than the copy of the book it came with).
            if let deleted = deletedAt[SyncTombstoneKey(kind: .item, key: id)] {
                merged.reads.removeAll { deleted > $0.updatedAt }
            }
            out.append(raised(merged, toSessions: sessionsByBook[id] ?? []))
        }
        return out.sorted { lhs, rhs in
            lhs.order != rhs.order ? lhs.order < rhs.order : bytewiseLess(lhs.id, rhs.id)
        }
    }

    /// Sessions are the source of truth for progress: a book being read is never behind them (see
    /// `countsTowardCurrentRead`, so a book restarted for a reread is not dragged back to where the last read-through
    /// ended). The page only ever goes up, and the update stamp is left alone: this is a repair, not an edit.
    static func raised(_ item: LibraryItem, toSessions sessions: [ReadingSession]) -> LibraryItem {
        guard item.shelf == .reading || item.shelf == .paused else { return item }
        let latestFinish = item.reads.map(\.finishedAt).max()
        var counted = false
        var reached = 0
        for session in sessions where countsTowardCurrentRead(session, startedAt: item.startedAt, latestFinish: latestFinish) {
            counted = true
            reached = max(reached, session.toPage)
        }
        guard counted else { return item }
        var repaired = item
        repaired.currentPage = max(item.currentPage, min(reached, max(0, item.book.pages)))
        // Having a session is itself the reader saying where they are.
        repaired.positionConfirmed = true
        return repaired
    }

    /// Whether a session belongs to the read-through in progress. One that ended more than a day before the book's
    /// `startedAt` (when the store restarts a book for a reread) belongs to an earlier read-through, and so does one
    /// that ended by the finish of the latest read-through kept on the book: a book begun again on the day it was
    /// finished must not jump back to its last page.
    static func countsTowardCurrentRead(_ session: ReadingSession, startedAt: Date?, latestFinish: Date?) -> Bool {
        let end = session.startedAt.addingTimeInterval(max(0, session.seconds))
        if let startedAt, end < startedAt.addingTimeInterval(-SyncPolicy.readThroughSlack) { return false }
        if let latestFinish, end <= latestFinish.addingTimeInterval(1) { return false }
        return true
    }

    // MARK: Sessions

    static func sessions(_ a: [ReadingSession], _ b: [ReadingSession]) -> [ReadingSession] {
        var best: [UUID: ReadingSession] = [:]
        for session in a + b {
            best[session.id] = best[session.id].map { larger($0, session) } ?? session
        }
        return best.values.sorted { lhs, rhs in
            lhs.startedAt != rhs.startedAt ? lhs.startedAt < rhs.startedAt : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: Cabinet and tastings

    /// Per id, the newest stamp wins as a whole (a tie goes to the larger JSON, so both sides pick the same copy);
    /// a tombstone of `kind` removes a thing only if it is strictly later than the thing's stamp. Ordered by `order`.
    static func newest<T: Codable & Equatable & Identifiable>(
        _ a: [T],
        _ b: [T],
        kind: Tombstone.Kind,
        deletedAt: [SyncTombstoneKey: Date],
        stamp: KeyPath<T, Date>,
        order: (T, T) -> Bool
    ) -> [T] where T.ID == UUID {
        var best: [UUID: T] = [:]
        for element in a + b {
            guard let existing = best[element.id] else {
                best[element.id] = element
                continue
            }
            if existing == element { continue }
            let mine = existing[keyPath: stamp]
            let theirs = element[keyPath: stamp]
            if mine != theirs {
                best[element.id] = mine > theirs ? existing : element
            } else {
                best[element.id] = larger(existing, element)
            }
        }
        return best.values
            .filter { element in
                guard let deleted = deletedAt[SyncTombstoneKey(kind: kind, key: element.id.uuidString)] else { return true }
                return !(deleted > element[keyPath: stamp])
            }
            .sorted(by: order)
    }

    // MARK: Circles

    /// The newest copy of each circle wins as a whole (so a removed friend or a changed schedule sticks), except that
    /// each member still in it takes the newest copy of that member from either side. In a shared circle everyone
    /// moves only their own page, so two people reading at once both keep their progress. A tombstone removes a
    /// circle only if it is strictly later than the circle's stamp. Oldest circle first.
    static func circles(_ a: [ReadingCircle], _ b: [ReadingCircle], deletedAt: [SyncTombstoneKey: Date]) -> [ReadingCircle] {
        // A tie on the stamp is broken by the circle without its members' contents (only who is in it), so a copy
        // whose members were already brought up to date picks the same winner: the merge stays associative.
        func tieKey(_ circle: ReadingCircle) -> [UInt8] {
            var bare = circle
            bare.members = circle.members.map { CircleMember(id: $0.id, name: "", updatedAt: .distantPast) }
            return canonicalBytes(bare)
        }
        var best: [UUID: ReadingCircle] = [:]
        for circle in a + b {
            guard let existing = best[circle.id] else {
                best[circle.id] = circle
                continue
            }
            if existing.updatedAt != circle.updatedAt {
                if circle.updatedAt > existing.updatedAt { best[circle.id] = circle }
            } else if tieKey(existing).lexicographicallyPrecedes(tieKey(circle)) {
                best[circle.id] = circle
            }
        }
        let winners = best.values
            .filter { circle in
                guard let deleted = deletedAt[SyncTombstoneKey(kind: .circle, key: circle.id.uuidString)] else { return true }
                return !(deleted > circle.updatedAt)
            }
            .sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString }
        var membersByID: [UUID: CircleMember] = [:]
        for member in (a + b).flatMap(\.members) {
            guard let existing = membersByID[member.id] else {
                membersByID[member.id] = member
                continue
            }
            if existing == member { continue }
            if existing.updatedAt != member.updatedAt {
                membersByID[member.id] = existing.updatedAt > member.updatedAt ? existing : member
            } else {
                membersByID[member.id] = larger(existing, member)
            }
        }
        return winners.map { circle in
            var merged = circle
            merged.members = circle.members.map { membersByID[$0.id] ?? $0 }
            return merged
        }
    }

    // MARK: Journal

    static func journal(_ a: [JournalEntry], _ b: [JournalEntry], deletedAt: [SyncTombstoneKey: Date]) -> [JournalEntry] {
        var best: [UUID: JournalEntry] = [:]
        for entry in a + b {
            guard let existing = best[entry.id] else {
                best[entry.id] = entry
                continue
            }
            if existing == entry { continue }
            if existing.updatedAt != entry.updatedAt {
                best[entry.id] = existing.updatedAt > entry.updatedAt ? existing : entry
            } else {
                best[entry.id] = larger(existing, entry)
            }
        }
        return best.values
            .filter { entry in
                guard let deleted = deletedAt[SyncTombstoneKey(kind: .journal, key: entry.id.uuidString)] else { return true }
                return !(deleted > entry.updatedAt)
            }
            .sorted { lhs, rhs in
                lhs.createdAt != rhs.createdAt ? lhs.createdAt < rhs.createdAt : lhs.id.uuidString < rhs.id.uuidString
            }
    }

    // MARK: Speed tests

    static func speedTests(_ a: [SpeedTestResult], _ b: [SpeedTestResult]) -> [SpeedTestResult] {
        var best: [String: SpeedTestResult] = [:]
        for test in a + b {
            let key = SyncKey.speedTestKey(date: test.date, passageID: test.passageID)
            best[key] = best[key].map { larger($0, test) } ?? test
        }
        // Oldest first, so `speedTests.last` is the latest, as the store expects.
        return best.values.sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date < rhs.date : bytewiseLess(lhs.passageID, rhs.passageID)
        }
    }

    // MARK: Dismissals

    /// A union, minus anything a dismissal tombstone covers on either side.
    ///
    /// The one ambiguity: a dismissal has no timestamp of its own, so a tombstone cannot be compared with it. If a
    /// reader takes back a "not for me" on one device and dismisses the same book again on another before hearing
    /// of the first, the tombstone wins and the second dismissal is lost. Devices still agree, and the worst case
    /// is a book that can be suggested again, which is the safe direction.
    static func dismissed(_ a: [String], _ b: [String], deletedAt: [SyncTombstoneKey: Date]) -> [String] {
        Set(a).union(b)
            .filter { deletedAt[SyncTombstoneKey(kind: .dismissal, key: $0)] == nil }
            .sorted(by: bytewiseLess)
    }

    // MARK: Challenges

    private struct ChallengeKey: Hashable { var id: String; var year: Int? }

    /// A union by (id, year). When both sides joined the same one, the later join counts, so a re-join beats the
    /// leave that came before it. A tombstone keyed by the bare challenge id removes every year joined before it;
    /// one keyed with `SyncKey.challengeTombstoneKey` removes only that year.
    static func challenges(_ a: [ChallengeEnrollment], _ b: [ChallengeEnrollment], deletedAt: [SyncTombstoneKey: Date]) -> [ChallengeEnrollment] {
        var best: [ChallengeKey: ChallengeEnrollment] = [:]
        for enrollment in a + b {
            let key = ChallengeKey(id: enrollment.id, year: enrollment.year)
            if let existing = best[key], existing.joinedAt >= enrollment.joinedAt { continue }
            best[key] = enrollment
        }
        return best.values
            .filter { enrollment in
                let whole = deletedAt[SyncTombstoneKey(kind: .challenge, key: enrollment.id)]
                let one = deletedAt[SyncTombstoneKey(kind: .challenge, key: SyncKey.challengeTombstoneKey(id: enrollment.id, year: enrollment.year))]
                guard let deleted = [whole, one].compactMap({ $0 }).max() else { return true }
                return !(deleted > enrollment.joinedAt)
            }
            .sorted { lhs, rhs in
                if lhs.joinedAt != rhs.joinedAt { return lhs.joinedAt < rhs.joinedAt }
                if lhs.id != rhs.id { return bytewiseLess(lhs.id, rhs.id) }
                return (lhs.year ?? Int.min) < (rhs.year ?? Int.min)
            }
    }

    // MARK: Preferences

    /// The newest copy wins as a whole. The device's own settings stay local, `hasOnboarded` is true if either
    /// side is, and `onboardedAt` is the earliest known. A tie in stamp goes to the larger JSON, ignoring those
    /// special fields, so the winner is the same on both sides.
    static func preferences(local: ReadingPreferences, remote: ReadingPreferences) -> ReadingPreferences {
        var winner = local
        if local.updatedAt != remote.updatedAt {
            winner = local.updatedAt > remote.updatedAt ? local : remote
        } else {
            let (l, r) = (orderingView(local), orderingView(remote))
            let (lCustom, rCustom) = (l != defaultView, r != defaultView)
            if lCustom != rCustom {
                // Equal stamps are the norm for data from before stamps existed. Settings the reader changed beat
                // untouched defaults, so a brand-new device can never wipe an old one's choices.
                winner = rCustom ? remote : local
            } else if preferenceBytes(l).lexicographicallyPrecedes(preferenceBytes(r)) {
                winner = remote
            }
        }
        var out = winner
        out.hapticsLevel = local.hapticsLevel
        out.appearance = local.appearance
        out.syncEnabled = local.syncEnabled
        out.hasOnboarded = local.hasOnboarded || remote.hasOnboarded
        out.onboardedAt = [local.onboardedAt, remote.onboardedAt].compactMap { $0 }.min()
        return out
    }

    private static let defaultView = orderingView(ReadingPreferences())

    /// Preferences as bytes for breaking ties. `readingDays` is a Set, and a Set encodes in whatever order it
    /// happens to iterate, which differs between devices; so it is written out sorted instead.
    private static func preferenceBytes(_ prefs: ReadingPreferences) -> [UInt8] {
        var plain = prefs
        plain.readingDays = []
        return canonicalBytes(plain) + prefs.readingDays.sorted().flatMap { Array(String($0).utf8) + [0x2C] }
    }

    private static func orderingView(_ prefs: ReadingPreferences) -> ReadingPreferences {
        var view = prefs.syncNormalized
        view.hasOnboarded = false
        view.onboardedAt = nil
        return view
    }
}
