import Foundation

/// Turns entities into plain records and back. The payload is the entity's own Codable JSON, the same format as
/// the library file, so every tolerance for old data in the models (missing fields, new defaults) applies to records
/// written by an older Leaf, and an older Leaf reading a newer record simply ignores fields it does not know.
enum SyncRecordMapper {
    private struct DismissalPayload: Codable { var bookID: String }

    /// Keys are sorted so the same entity always gives the same bytes.
    private static func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    // MARK: Entity to record

    /// The record for an entity. Nil when its name is not a valid CloudKit name or its payload would not fit in
    /// one record; such an entity stays on the device and is never queued.
    static func record(for entity: SyncEntity) -> SyncRecord? {
        let name = entity.name
        guard name.isValid, let payload = payload(of: entity), payload.count <= SyncPolicy.maxPayloadBytes else { return nil }
        // CloudKit dates before 1970 are not worth the risk; the exact stamp is in the payload anyway.
        let epoch = Date(timeIntervalSince1970: 0)
        let stamp = max(entity.stamp ?? epoch, epoch)
        return SyncRecord(name: name.string, type: name.type, fields: [
            SyncRecord.payloadField: .data(payload),
            SyncRecord.updatedAtField: .date(stamp),
            SyncRecord.schemaField: .int(Int64(SyncPolicy.recordSchema)),
        ])
    }

    private static func payload(of entity: SyncEntity) -> Data? {
        switch entity {
        case .item(let value): return encode(value)
        case .session(let value): return encode(value)
        case .journal(let value): return encode(value)
        case .preferences(let value): return encode(value)
        case .speedTest(let value): return encode(value)
        case .dismissal(let id): return encode(DismissalPayload(bookID: id))
        case .challenge(let value): return encode(value)
        case .tombstone(let value): return encode(value)
        }
    }

    /// Every record for a whole library, in a stable order. Used to seed a new cloud copy.
    static func records(from data: LeafData) -> [SyncRecord] {
        let snapshot = SyncSnapshot(data)
        return snapshot.names.compactMap { name in snapshot[name].flatMap { record(for: $0) } }
    }

    // MARK: Record to entity

    /// The entity a record holds. Nil for a payload that cannot be read (a record from a newer Leaf that changed
    /// shape, or damage). Unreadable records are left alone on the server, never deleted.
    static func entity(from record: SyncRecord) -> SyncEntity? {
        guard let payload = record.payload else { return nil }
        switch record.type {
        case .item: return decode(LibraryItem.self, from: payload).map(SyncEntity.item)
        case .session: return decode(ReadingSession.self, from: payload).map(SyncEntity.session)
        case .journal: return decode(JournalEntry.self, from: payload).map(SyncEntity.journal)
        case .preferences: return decode(ReadingPreferences.self, from: payload).map(SyncEntity.preferences)
        case .speedTest: return decode(SpeedTestResult.self, from: payload).map(SyncEntity.speedTest)
        case .dismissal: return decode(DismissalPayload.self, from: payload).map { SyncEntity.dismissal($0.bookID) }
        case .challenge: return decode(ChallengeEnrollment.self, from: payload).map(SyncEntity.challenge)
        case .tombstone: return decode(Tombstone.self, from: payload).map(SyncEntity.tombstone)
        }
    }

    /// What a batch of fetched records says, as a `LeafData` that can be merged into the real one. Anything the
    /// batch does not mention is taken from `base`: the preferences and the version, so a batch with no preferences
    /// record can never reset the reader's settings to defaults.
    static func delta(from records: [SyncRecord], basedOn base: LeafData) -> LeafData {
        var delta = LeafData()
        delta.version = base.version
        delta.preferences = base.preferences
        for record in records {
            guard let entity = entity(from: record) else { continue }
            switch entity {
            case .item(let value): delta.items.append(value)
            case .session(let value): delta.sessions.append(value)
            case .journal(let value): delta.journal.append(value)
            case .preferences(let value): delta.preferences = value
            case .speedTest(let value): delta.speedTests.append(value)
            case .dismissal(let id): delta.dismissed.append(id)
            case .challenge(let value): delta.challenges.append(value)
            case .tombstone(let value): delta.tombstones.append(value)
            }
        }
        return delta
    }
}
