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

    // Added with the watch overhaul. All optional or defaulted so an older phone or watch still understands the rest.

    /// A line written by the phone's voice engine, so the wrist sounds like the phone.
    var greeting: WatchGreeting?
    /// The tea the phone suggests for this hour.
    var tea: WatchTea?
    /// Length of one "cup" of reading in minutes.
    var cupMinutes: Int
    /// The first few books waiting in To read.
    var queue: [WatchBook]
    /// A finish-date sentence per book being read.
    var forecasts: [WatchForecast]
    var yearGoal: WatchYearGoal?
    /// Whether the phone has Live Activities on (the watch mirrors them in the Smart Stack).
    var liveActivities: Bool

    static let empty = WatchSnapshot(
        generatedAt: .distantPast, dailyMinutes: 20, minutesReadToday: 0, isReadingDay: true,
        streak: 0, wpm: ReadingSpeed.typicalAdultWPM, today: [], reading: [], week: [],
        activeSession: nil, hasOnboarded: false
    )

    init(
        generatedAt: Date, dailyMinutes: Int, minutesReadToday: Double, isReadingDay: Bool, streak: Int, wpm: Double,
        today: [WatchAssignment], reading: [WatchBook], week: [WatchDay], activeSession: ActiveSession?, hasOnboarded: Bool,
        greeting: WatchGreeting? = nil, tea: WatchTea? = nil, cupMinutes: Int = 25, queue: [WatchBook] = [],
        forecasts: [WatchForecast] = [], yearGoal: WatchYearGoal? = nil, liveActivities: Bool = true
    ) {
        self.generatedAt = generatedAt
        self.dailyMinutes = dailyMinutes
        self.minutesReadToday = minutesReadToday
        self.isReadingDay = isReadingDay
        self.streak = streak
        self.wpm = wpm
        self.today = today
        self.reading = reading
        self.week = week
        self.activeSession = activeSession
        self.hasOnboarded = hasOnboarded
        self.greeting = greeting
        self.tea = tea
        self.cupMinutes = cupMinutes
        self.queue = queue
        self.forecasts = forecasts
        self.yearGoal = yearGoal
        self.liveActivities = liveActivities
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt, dailyMinutes, minutesReadToday, isReadingDay, streak, wpm, today, reading, week, activeSession, hasOnboarded
        case greeting, tea, cupMinutes, queue, forecasts, yearGoal, liveActivities
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            generatedAt: try c.decode(Date.self, forKey: .generatedAt),
            dailyMinutes: try c.decode(Int.self, forKey: .dailyMinutes),
            minutesReadToday: try c.decode(Double.self, forKey: .minutesReadToday),
            isReadingDay: try c.decode(Bool.self, forKey: .isReadingDay),
            streak: try c.decode(Int.self, forKey: .streak),
            wpm: try c.decode(Double.self, forKey: .wpm),
            today: try c.decode([WatchAssignment].self, forKey: .today),
            reading: try c.decode([WatchBook].self, forKey: .reading),
            week: try c.decode([WatchDay].self, forKey: .week),
            activeSession: try c.decodeIfPresent(ActiveSession.self, forKey: .activeSession),
            hasOnboarded: try c.decode(Bool.self, forKey: .hasOnboarded),
            greeting: try c.decodeIfPresent(WatchGreeting.self, forKey: .greeting),
            tea: try c.decodeIfPresent(WatchTea.self, forKey: .tea),
            cupMinutes: try c.decodeIfPresent(Int.self, forKey: .cupMinutes) ?? 25,
            queue: try c.decodeIfPresent([WatchBook].self, forKey: .queue) ?? [],
            forecasts: try c.decodeIfPresent([WatchForecast].self, forKey: .forecasts) ?? [],
            yearGoal: try c.decodeIfPresent(WatchYearGoal.self, forKey: .yearGoal),
            liveActivities: try c.decodeIfPresent(Bool.self, forKey: .liveActivities) ?? true
        )
    }

    var goalProgress: Double {
        guard dailyMinutes > 0 else { return 0 }
        return min(1, minutesReadToday / Double(dailyMinutes))
    }

    var minutesLeftToday: Double { max(0, Double(dailyMinutes) - minutesReadToday) }

    /// Cups read today, as a fraction (for the filling-teacup complication).
    var cupsToday: Double { Cups.count(minutes: minutesReadToday, cupMinutes: cupMinutes) }

    func book(_ id: String) -> WatchBook? { reading.first { $0.id == id } ?? queue.first { $0.id == id } }
}

/// A greeting the phone wrote for the wrist.
struct WatchGreeting: Codable, Hashable, Sendable {
    var headline: String
    var subline: String?
}

/// A tea suggestion with its steep time, so the watch can run the steeping timer on its own.
struct WatchTea: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var steepSeconds: Int
}

/// "Probably done Sunday." for one book, written by the phone's forecast narrator.
struct WatchForecast: Codable, Hashable, Identifiable, Sendable {
    var bookID: String
    var sentence: String
    var median: Date?

    var id: String { bookID }
}

struct WatchYearGoal: Codable, Hashable, Sendable {
    var year: Int
    var finished: Int
    var goal: Int
    var sentence: String
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

    // Added with the watch overhaul. A phone that doesn't know a case ignores the message.

    /// A thought or dictated quote from the wrist, attached to a book.
    case journalAdded(bookID: String, kind: JournalEntry.Kind, text: String, page: Int?)
    /// "Where was I?" corrected from the wrist.
    case pageSet(bookID: String, page: Int)
    /// A book moved to another shelf from the wrist (mark finished, set aside, start).
    case shelfChanged(bookID: String, shelf: Shelf, rating: Int?)
    /// A book dictated on the wrist: the phone looks it up in the catalog and adds it to To read.
    case addBook(query: String)
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
