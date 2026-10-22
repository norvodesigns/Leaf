import Foundation

/// One field of a record, in the few shapes CloudKit stores. The transport turns these into CKRecord values and
/// back, so everything above it can be tested without CloudKit.
enum SyncValue: Hashable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case date(Date)
    case data(Data)
    case bool(Bool)

    var stringValue: String? { if case .string(let v) = self { return v } else { return nil } }
    var intValue: Int64? { if case .int(let v) = self { return v } else { return nil } }
    var doubleValue: Double? { if case .double(let v) = self { return v } else { return nil } }
    var dateValue: Date? { if case .date(let v) = self { return v } else { return nil } }
    var dataValue: Data? { if case .data(let v) = self { return v } else { return nil } }
    var boolValue: Bool? { if case .bool(let v) = self { return v } else { return nil } }
}

/// The CloudKit record types Leaf uses. These names are the schema: they must exist in the container's
/// Production environment before a TestFlight or App Store build can save them.
enum SyncRecordType: String, CaseIterable, Sendable {
    case item = "LeafItem"
    case session = "LeafSession"
    case journal = "LeafJournal"
    case preferences = "LeafPreferences"
    case speedTest = "LeafSpeedTest"
    case dismissal = "LeafDismissal"
    case challenge = "LeafChallenge"
    case tombstone = "LeafTombstone"
    case cabinetTea = "LeafTea"
    case tasting = "LeafTasting"
    case circle = "LeafCircle"
}

/// A record as plain data: its name, its type and its fields. Every record carries the same three fields.
struct SyncRecord: Hashable, Sendable {
    /// The whole entity as JSON, in the same format as the library file. Stored as an encrypted field.
    static let payloadField = "payload"
    /// When the entity last changed. Informational (and handy in the CloudKit console); merging reads the payload.
    static let updatedAtField = "updatedAt"
    /// The record layout version, `SyncPolicy.recordSchema`.
    static let schemaField = "schema"

    var name: String
    var type: SyncRecordType
    var fields: [String: SyncValue]

    var payload: Data? { fields[SyncRecord.payloadField]?.dataValue }
    var updatedAt: Date? { fields[SyncRecord.updatedAtField]?.dateValue }
    var schema: Int? { fields[SyncRecord.schemaField]?.intValue.map(Int.init) }
}
