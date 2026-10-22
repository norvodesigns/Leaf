import Foundation

extension ReadingPreferences {
    /// This device's own settings are set to fixed values, so two preference structs can be compared (or ordered)
    /// by what actually travels between devices. Haptics and appearance are a matter of taste per device, and
    /// `syncEnabled` is about this device's own participation: turning iCloud off on the phone must not turn it
    /// off on the iPad.
    var syncNormalized: ReadingPreferences {
        var copy = self
        copy.hapticsLevel = .full
        copy.appearance = .system
        copy.syncEnabled = true
        return copy
    }

    /// Whether another copy would look the same to other devices. Ignores the device's own settings and the
    /// change stamp, so changing only haptics never uploads anything.
    func hasSameSyncedFields(as other: ReadingPreferences) -> Bool {
        var a = syncNormalized
        var b = other.syncNormalized
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }
}

/// One thing that syncs, in the shape that becomes one record. The live `ActiveSession` is deliberately absent:
/// it belongs to the device (and the watch bridge) and never leaves it.
enum SyncEntity: Equatable, Sendable {
    case item(LibraryItem)
    case session(ReadingSession)
    case journal(JournalEntry)
    case preferences(ReadingPreferences)
    case speedTest(SpeedTestResult)
    case dismissal(String)
    case challenge(ChallengeEnrollment)
    case tombstone(Tombstone)
    case cabinetTea(CabinetTea)
    case tasting(TastingNote)
    case circle(ReadingCircle)

    var name: SyncRecordName {
        switch self {
        case .item(let item): return .item(item.id)
        case .session(let session): return .session(session.id)
        case .journal(let entry): return .journal(entry.id)
        case .preferences: return .preferences
        case .speedTest(let test): return .speedTest(SyncKey.speedTestKey(date: test.date, passageID: test.passageID))
        case .dismissal(let id): return .dismissal(id)
        case .challenge(let enrollment): return .challenge(id: enrollment.id, year: enrollment.year)
        case .tombstone(let tombstone): return .tombstone(tombstone.kind, tombstone.key)
        case .cabinetTea(let tea): return .cabinetTea(tea.id)
        case .tasting(let note): return .tasting(note.id)
        case .circle(let circle): return .circle(circle.id)
        }
    }

    var recordName: String { name.string }
    var type: SyncRecordType { name.type }

    /// The moment this entity last changed, where it has one.
    var stamp: Date? {
        switch self {
        case .item(let item): return item.updatedAt
        case .session(let session): return session.startedAt
        case .journal(let entry): return entry.updatedAt
        case .preferences(let prefs): return prefs.updatedAt
        case .speedTest(let test): return test.date
        case .dismissal: return nil
        case .challenge(let enrollment): return enrollment.joinedAt
        case .tombstone(let tombstone): return tombstone.deletedAt
        case .cabinetTea(let tea): return tea.updatedAt
        case .tasting(let note): return note.updatedAt
        case .circle(let circle): return circle.updatedAt
        }
    }

    /// Equality as the cloud sees it. Preferences ignore the device's own settings and the change stamp.
    func matches(_ other: SyncEntity) -> Bool {
        if case .preferences(let a) = self, case .preferences(let b) = other { return a.hasSameSyncedFields(as: b) }
        return self == other
    }
}

/// Every syncing entity of a `LeafData`, indexed by record name. Built when a comparison or a batch needs it, so a
/// lookup is cheap and nothing is encoded until a record is actually asked for.
struct SyncSnapshot: Sendable {
    private(set) var entities: [String: SyncEntity]

    init(_ data: LeafData) {
        var map: [String: SyncEntity] = [:]
        map.reserveCapacity(data.items.count + data.sessions.count + data.journal.count + 16)
        for item in data.items { SyncSnapshot.add(.item(item), to: &map) }
        for session in data.sessions { SyncSnapshot.add(.session(session), to: &map) }
        for entry in data.journal { SyncSnapshot.add(.journal(entry), to: &map) }
        for test in data.speedTests { SyncSnapshot.add(.speedTest(test), to: &map) }
        for id in data.dismissed { SyncSnapshot.add(.dismissal(id), to: &map) }
        for enrollment in data.challenges { SyncSnapshot.add(.challenge(enrollment), to: &map) }
        for tombstone in data.tombstones { SyncSnapshot.add(.tombstone(tombstone), to: &map) }
        for tea in data.cabinet { SyncSnapshot.add(.cabinetTea(tea), to: &map) }
        for note in data.tastings { SyncSnapshot.add(.tasting(note), to: &map) }
        for circle in data.circles { SyncSnapshot.add(.circle(circle), to: &map) }
        SyncSnapshot.add(.preferences(data.preferences), to: &map)
        entities = map
    }

    private static func add(_ entity: SyncEntity, to map: inout [String: SyncEntity]) {
        let name = entity.name
        // A name CloudKit would refuse can never be saved, so it never gets queued.
        guard name.isValid else { return }
        map[name.string] = entity
    }

    subscript(name: String) -> SyncEntity? { entities[name] }

    /// All record names, sorted so queues and tests are deterministic.
    var names: [String] { entities.keys.sorted() }
}
