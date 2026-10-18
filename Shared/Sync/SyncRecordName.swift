import Foundation

/// Turns ids into the text a CloudKit record name allows: ASCII only, at most 255 characters. Everything outside
/// letters, digits, hyphen and underscore becomes `%XX`, so the dot is free to separate the parts of a name.
enum SyncKey {
    private static let hexDigits = Array("0123456789ABCDEF")

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x5F:
                out.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                out.append("%")
                out.append(hexDigits[Int(byte >> 4)])
                out.append(hexDigits[Int(byte & 0x0F)])
            }
        }
        return out
    }

    /// The inverse of `escape`. Nil for text that `escape` could not have produced.
    static func unescape(_ text: String) -> String? {
        let bytes = Array(text.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x25 {
                guard index + 2 < bytes.count, let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) else { return nil }
                out.append(high << 4 | low)
                index += 3
            } else {
                out.append(byte)
                index += 1
            }
        }
        return String(bytes: out, encoding: .utf8)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x41 + 10
        case 0x61...0x66: return byte - 0x61 + 10
        default: return nil
        }
    }

    /// A stable key for a speed test: the moment in whole milliseconds and the passage. Used both in the record
    /// name and as the merge key, so two tests are "the same test" exactly when they share a record.
    static func speedTestKey(date: Date, passageID: String) -> String {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        let clamped: Int64 = milliseconds.isFinite ? Int64(max(-9.0e15, min(9.0e15, milliseconds))) : 0
        return String(clamped) + "-" + escape(passageID)
    }

    /// The tombstone key that removes one year of a challenge, for stores that want to be precise.
    /// A tombstone keyed by the bare challenge id removes every year that was joined before the deletion.
    static func challengeTombstoneKey(id: String, year: Int?) -> String {
        id + "." + (year.map(String.init) ?? "none")
    }
}

/// The name of a record in the reader's CloudKit zone, and what it stands for. Names are the identity of a record,
/// so the same entity always maps to the same name on every device.
enum SyncRecordName: Hashable, Sendable {
    case item(String)
    case session(UUID)
    case journal(UUID)
    case preferences
    /// The associated value is the already-safe key from `SyncKey.speedTestKey`.
    case speedTest(String)
    case dismissal(String)
    case challenge(id: String, year: Int?)
    case tombstone(Tombstone.Kind, String)

    private static let itemPrefix = "item."
    private static let sessionPrefix = "session."
    private static let journalPrefix = "journal."
    private static let preferencesName = "prefs"
    private static let speedTestPrefix = "speedtest."
    private static let dismissalPrefix = "dismissal."
    private static let challengePrefix = "challenge."
    private static let tombstonePrefix = "tombstone."

    var string: String {
        switch self {
        case .item(let id): return SyncRecordName.itemPrefix + SyncKey.escape(id)
        case .session(let id): return SyncRecordName.sessionPrefix + id.uuidString
        case .journal(let id): return SyncRecordName.journalPrefix + id.uuidString
        case .preferences: return SyncRecordName.preferencesName
        case .speedTest(let key): return SyncRecordName.speedTestPrefix + key
        case .dismissal(let id): return SyncRecordName.dismissalPrefix + SyncKey.escape(id)
        case .challenge(let id, let year):
            return SyncRecordName.challengePrefix + SyncKey.escape(id) + "." + (year.map(String.init) ?? "none")
        case .tombstone(let kind, let key):
            return SyncRecordName.tombstonePrefix + kind.rawValue + "." + SyncKey.escape(key)
        }
    }

    var type: SyncRecordType {
        switch self {
        case .item: return .item
        case .session: return .session
        case .journal: return .journal
        case .preferences: return .preferences
        case .speedTest: return .speedTest
        case .dismissal: return .dismissal
        case .challenge: return .challenge
        case .tombstone: return .tombstone
        }
    }

    /// Whether CloudKit will accept the name.
    var isValid: Bool { string.utf8.count <= SyncPolicy.maxRecordNameLength }

    /// Reads a record name back. Nil for a name this version of Leaf did not write.
    init?(_ string: String) {
        if string == SyncRecordName.preferencesName {
            self = .preferences
            return
        }
        if let rest = SyncRecordName.rest(of: string, after: SyncRecordName.itemPrefix) {
            guard let id = SyncKey.unescape(rest) else { return nil }
            self = .item(id)
        } else if let rest = SyncRecordName.rest(of: string, after: SyncRecordName.sessionPrefix) {
            guard let id = UUID(uuidString: rest) else { return nil }
            self = .session(id)
        } else if let rest = SyncRecordName.rest(of: string, after: SyncRecordName.journalPrefix) {
            guard let id = UUID(uuidString: rest) else { return nil }
            self = .journal(id)
        } else if let rest = SyncRecordName.rest(of: string, after: SyncRecordName.speedTestPrefix) {
            self = .speedTest(rest)
        } else if let rest = SyncRecordName.rest(of: string, after: SyncRecordName.dismissalPrefix) {
            guard let id = SyncKey.unescape(rest) else { return nil }
            self = .dismissal(id)
        } else if let rest = SyncRecordName.rest(of: string, after: SyncRecordName.challengePrefix) {
            guard let dot = rest.lastIndex(of: "."), let id = SyncKey.unescape(String(rest[..<dot])) else { return nil }
            let yearText = String(rest[rest.index(after: dot)...])
            if yearText == "none" {
                self = .challenge(id: id, year: nil)
            } else if let year = Int(yearText) {
                self = .challenge(id: id, year: year)
            } else {
                return nil
            }
        } else if let rest = SyncRecordName.rest(of: string, after: SyncRecordName.tombstonePrefix) {
            guard let dot = rest.firstIndex(of: "."),
                  let kind = Tombstone.Kind(rawValue: String(rest[..<dot])),
                  let key = SyncKey.unescape(String(rest[rest.index(after: dot)...])) else { return nil }
            self = .tombstone(kind, key)
        } else {
            return nil
        }
    }

    private static func rest(of string: String, after prefix: String) -> String? {
        string.hasPrefix(prefix) ? String(string.dropFirst(prefix.count)) : nil
    }
}
