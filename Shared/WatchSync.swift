import Foundation

/// What the iPhone tells the watch. The phone is the source of truth; the watch keeps the last copy for offline use.
struct WatchSnapshot: Codable, Hashable, Sendable {
    var generatedAt: Date
    var dailyMinutes: Int
    var minutesReadToday: Double
    var isReadingDay: Bool
    var streak: Int
    var wpm: Double
    var today: [WatchAssignment]
    var reading: [WatchBook]
    var week: [WatchDay]
    var activeSession: ActiveSession?
    var hasOnboarded: Bool

    static let empty = WatchSnapshot(
        generatedAt: .distantPast, dailyMinutes: 20, minutesReadToday: 0, isReadingDay: true,
        streak: 0, wpm: ReadingSpeed.typicalAdultWPM, today: [], reading: [], week: [],
        activeSession: nil, hasOnboarded: false
    )

    var goalProgress: Double {
        guard dailyMinutes > 0 else { return 0 }
        return min(1, minutesReadToday / Double(dailyMinutes))
    }

    var minutesLeftToday: Double { max(0, Double(dailyMinutes) - minutesReadToday) }

    func book(_ id: String) -> WatchBook? { reading.first { $0.id == id } }
}

struct WatchBook: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var author: String
    var currentPage: Int
    var pages: Int
    var wordsPerPage: Double
    var paletteSeed: Int
    var finish: Date?

    var progress: Double { pages > 0 ? min(1, Double(currentPage) / Double(pages)) : 0 }
}

struct WatchAssignment: Codable, Hashable, Identifiable, Sendable {
    var bookID: String
    var title: String
    var minutes: Double
    var fromPage: Int
    var toPage: Int

    var id: String { bookID }
}

struct WatchDay: Codable, Hashable, Identifiable, Sendable {
    var date: Date
    var minutes: Double
    var goal: Int
    var isReadingDay: Bool

    var id: Date { date }
}

/// Events sent in either direction between the two devices.
enum SyncEvent: Codable, Hashable, Sendable {
    /// A session started, paused, or resumed (the newest `revision` wins).
    case sessionChanged(ActiveSession)
    /// A live session was thrown away without logging.
    case sessionCancelled(UUID)
    /// A session ended and should be logged. `activeID` is the live session it came from, if any.
    case sessionLogged(ReadingSession, activeID: UUID?)
    /// The watch wants a fresh snapshot.
    case requestSnapshot
}

/// Packs payloads into WatchConnectivity-friendly dictionaries.
enum SyncCodec {
    static let snapshotKey = "leaf.snapshot"
    static let eventKey = "leaf.event"

    static func encode<T: Encodable>(_ value: T, key: String) -> [String: Any] {
        guard let data = try? encoder.encode(value) else { return [:] }
        return [key: data]
    }

    static func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: Any], key: String) -> T? {
        guard let data = dictionary[key] as? Data else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
