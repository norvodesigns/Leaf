import Foundation

/// Works out which records need to travel, by comparing data with data. The transport calls it on every local
/// change; nothing here talks to CloudKit.
enum SyncDiff {
    /// Records to save and records to delete when local data goes from `old` to `new`, sorted by name.
    ///
    /// - A removed library item deletes its record, and the tombstone the store left behind is saved.
    /// - The live `ActiveSession` is not part of the comparison, so pausing a timer queues nothing.
    /// - Preferences are compared by the fields that travel (not the device's own settings or the change stamp),
    ///   so changing haptics or appearance queues nothing.
    static func changes(from old: LeafData, to new: LeafData) -> (saves: [String], deletes: [String]) {
        var saves = Set<String>()
        var deletes = Set<String>()
        collect(old.items, new.items, as: SyncEntity.item, saves: &saves, deletes: &deletes)
        collect(old.sessions, new.sessions, as: SyncEntity.session, saves: &saves, deletes: &deletes)
        collect(old.journal, new.journal, as: SyncEntity.journal, saves: &saves, deletes: &deletes)
        collect(old.speedTests, new.speedTests, as: SyncEntity.speedTest, saves: &saves, deletes: &deletes)
        collect(old.dismissed, new.dismissed, as: SyncEntity.dismissal, saves: &saves, deletes: &deletes)
        collect(old.challenges, new.challenges, as: SyncEntity.challenge, saves: &saves, deletes: &deletes)
        collect(old.tombstones, new.tombstones, as: SyncEntity.tombstone, saves: &saves, deletes: &deletes)
        collect(old.cabinet, new.cabinet, as: SyncEntity.cabinetTea, saves: &saves, deletes: &deletes)
        collect(old.tastings, new.tastings, as: SyncEntity.tasting, saves: &saves, deletes: &deletes)
        if !old.preferences.hasSameSyncedFields(as: new.preferences) { saves.insert(SyncRecordName.preferences.string) }
        return (saves.sorted(), deletes.sorted())
    }

    private static func collect<E: Equatable>(
        _ old: [E],
        _ new: [E],
        as make: (E) -> SyncEntity,
        saves: inout Set<String>,
        deletes: inout Set<String>
    ) {
        // Most commits touch one collection; the rest compare equal in one pass and cost nothing more.
        if old == new { return }
        var before: [String: SyncEntity] = [:]
        for element in old {
            let entity = make(element)
            if entity.name.isValid { before[entity.recordName] = entity }
        }
        var after: [String: SyncEntity] = [:]
        for element in new {
            let entity = make(element)
            if entity.name.isValid { after[entity.recordName] = entity }
        }
        for (name, entity) in after {
            if let previous = before[name], previous.matches(entity) { continue }
            saves.insert(name)
        }
        for name in before.keys where after[name] == nil { deletes.insert(name) }
    }

    /// The names of records worth (re)queueing for a library, for seeding a new cloud copy or catching up after sync
    /// was off or the app was stopped before its queue was saved.
    ///
    /// Entities that carry a timestamp are included when they changed after `date`. Dismissals, challenges and the
    /// preferences carry no usable stamp, so they are included only when `includeUndated` is true.
    /// `date == nil` means everything.
    static func recordNames(in data: LeafData, changedSince date: Date?, includeUndated: Bool) -> [String] {
        var entities: [SyncEntity] = []
        func newer(_ stamp: Date) -> Bool { date.map { stamp > $0 } ?? true }
        for item in data.items where newer(item.updatedAt) { entities.append(.item(item)) }
        for session in data.sessions where newer(session.startedAt.addingTimeInterval(max(0, session.seconds))) { entities.append(.session(session)) }
        for entry in data.journal where newer(entry.updatedAt) { entities.append(.journal(entry)) }
        for test in data.speedTests where newer(test.date) { entities.append(.speedTest(test)) }
        for tombstone in data.tombstones where newer(tombstone.deletedAt) { entities.append(.tombstone(tombstone)) }
        for tea in data.cabinet where newer(tea.updatedAt) { entities.append(.cabinetTea(tea)) }
        for note in data.tastings where newer(note.updatedAt) { entities.append(.tasting(note)) }
        if includeUndated || date == nil {
            for id in data.dismissed { entities.append(.dismissal(id)) }
            for enrollment in data.challenges { entities.append(.challenge(enrollment)) }
            entities.append(.preferences(data.preferences))
        }
        return Set(entities.filter { $0.name.isValid }.map(\.recordName)).sorted()
    }

    /// Of the records that were just fetched, the names for which this device's merged state differs from what the
    /// server holds. Those need saving back, because the server is behind (this device had something newer, or
    /// merging added something). Records that merged to exactly what the server has are never sent back.
    static func behind(fetched names: [String], remote: LeafData, merged: LeafData) -> [String] {
        let theirs = SyncSnapshot(remote)
        let ours = SyncSnapshot(merged)
        return names.filter { name in
            guard let server = theirs[name], let local = ours[name] else { return false }
            return !local.matches(server)
        }.sorted()
    }

    /// Of the records the server just reported as deleted, the ones this device still holds after merging, which it
    /// should put back. A delete made by another device usually comes with a tombstone that has already removed the
    /// thing from the merged data, so nothing is listed. But a delete can also destroy a newer edit made elsewhere
    /// at the same moment, or come from a cleared cloud copy; in both cases the data still exists here, and the
    /// rule is to keep it. Tombstone records are left out: removing one is how a device takes a deletion back.
    static func restorable(deleted names: [String], in merged: LeafData) -> [String] {
        let snapshot = SyncSnapshot(merged)
        return names.filter { name in
            guard let entity = snapshot[name] else { return false }
            if case .tombstone = entity { return false }
            return true
        }.sorted()
    }

    /// Whether two states differ in anything that syncs or that merging can change (the live session included).
    static func differs(_ a: LeafData, _ b: LeafData) -> Bool {
        let delta = changes(from: a, to: b)
        return !delta.saves.isEmpty || !delta.deletes.isEmpty || a.activeSession != b.activeSession || a.version != b.version
    }
}
