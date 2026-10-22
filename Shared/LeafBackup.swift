import Foundation

/// A whole-library backup as one JSON file the reader keeps wherever they like, and its import. Importing merges with
/// the same rules iCloud uses (`LeafData.merged`), so a backup adds what's missing and never wipes newer changes. Pure.
enum LeafBackup {
    static let format = "leaf-backup"
    static let version = 1

    /// The file's outer shape: what it is, when it was made, and the library.
    struct File: Codable {
        var format: String
        var version: Int
        var exportedAt: Date
        var data: LeafData
    }

    enum Failure: Error, Equatable {
        /// Not JSON, or JSON that isn't a Leaf library.
        case notABackup
        /// From a newer Leaf with a layout this version can't read.
        case tooNew(version: Int)
    }

    /// The library as backup JSON, in a stable key order. Dates are kept exactly as the app holds them (merging
    /// compares exact moments); the live session is left out.
    static func encode(_ data: LeafData, exportedAt: Date) throws -> Data {
        var library = data
        library.activeSession = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(File(format: format, version: version, exportedAt: exportedAt, data: library))
    }

    /// A backup's library. Also takes a bare library file, and dates written either as ISO text or as numbers.
    static func decode(_ bytes: Data) throws -> LeafData {
        for strategy in [JSONDecoder.DateDecodingStrategy.deferredToDate, .iso8601WithFractions] {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = strategy
            if let file = try? decoder.decode(File.self, from: bytes) {
                guard file.format == format else { throw Failure.notABackup }
                guard file.version <= version else { throw Failure.tooNew(version: file.version) }
                return file.data
            }
            if let bare = try? decoder.decode(LeafData.self, from: bytes), looksLikeALibrary(bytes) {
                return bare
            }
        }
        throw Failure.notABackup
    }

    /// The local library with a backup merged in, as iCloud would merge another device. The live session, this
    /// device's own settings and anything newer here are kept.
    static func merge(_ backup: LeafData, into local: LeafData, now: Date) -> LeafData {
        var incoming = backup
        incoming.activeSession = nil
        return local.merged(with: incoming, now: now)
    }

    /// What importing would bring in that this library doesn't have yet, for the confirmation sheet.
    struct Preview: Hashable, Sendable {
        var books: Int
        var sittings: Int
        var notes: Int
        var teas: Int
        var tastings: Int
        var circles: Int = 0
        var exportedAt: Date?

        var isEmpty: Bool { books == 0 && sittings == 0 && notes == 0 && teas == 0 && tastings == 0 && circles == 0 }
    }

    static func preview(of backup: LeafData, against local: LeafData, exportedAt: Date? = nil) -> Preview {
        let books = Set(local.items.map(\.id))
        let sittings = Set(local.sessions.map(\.id))
        let notes = Set(local.journal.map(\.id))
        let teas = Set(local.cabinet.map(\.id))
        let tastings = Set(local.tastings.map(\.id))
        let circles = Set(local.circles.map(\.id))
        return Preview(
            books: backup.items.filter { !books.contains($0.id) }.count,
            sittings: backup.sessions.filter { !sittings.contains($0.id) }.count,
            notes: backup.journal.filter { !notes.contains($0.id) }.count,
            teas: backup.cabinet.filter { !teas.contains($0.id) }.count,
            tastings: backup.tastings.filter { !tastings.contains($0.id) }.count,
            circles: backup.circles.filter { !circles.contains($0.id) }.count,
            exportedAt: exportedAt
        )
    }

    /// When the file says it was made, if it is a backup file.
    static func exportedAt(_ bytes: Data) -> Date? {
        for strategy in [JSONDecoder.DateDecodingStrategy.deferredToDate, .iso8601WithFractions] {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = strategy
            if let file = try? decoder.decode(File.self, from: bytes) { return file.exportedAt }
        }
        return nil
    }

    /// "Leaf backup 2026-10-20.json"
    static func fileName(now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "Leaf backup \(formatter.string(from: now)).json"
    }

    /// A bare `LeafData` decodes from almost any JSON object (every field has a default), so a bare file must at
    /// least carry one of the library's own keys.
    private static func looksLikeALibrary(_ bytes: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return false }
        return ["items", "sessions", "preferences", "journal"].contains { object[$0] != nil }
    }
}

extension JSONDecoder.DateDecodingStrategy {
    /// ISO 8601 text, with or without fractional seconds, for backups written by hand or by other tools.
    static var iso8601WithFractions: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = LeafBackupDates.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
            }
            return date
        }
    }
}

/// Reads ISO 8601 dates in backups, with fractional seconds when there are any.
enum LeafBackupDates {
    static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
