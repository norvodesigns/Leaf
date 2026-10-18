import Foundation

/// A book as Leaf knows it: from the bundled catalog, Open Library, or added by hand.
struct Book: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var author: String
    var year: Int?
    var pages: Int
    var words: Int
    var coverID: Int?
    var genres: [String]
    var popularity: Int
    /// Specific subjects ("dragons", "found family", "series:discworld"). Optional so older saved books still load.
    var themes: [String]?

    init(
        id: String,
        title: String,
        author: String,
        year: Int? = nil,
        pages: Int,
        words: Int? = nil,
        coverID: Int? = nil,
        genres: [String] = [],
        popularity: Int = 0,
        themes: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.year = year
        self.pages = max(1, pages)
        self.words = max(1, words ?? Book.estimatedWords(pages: pages, genres: genres))
        self.coverID = coverID
        self.genres = genres
        self.popularity = popularity
        self.themes = themes
    }

    /// Words per printed page by genre. Used when we only know the page count.
    static func wordsPerPage(genres: [String]) -> Double {
        if genres.contains("graphic") { return 60 }
        if genres.contains("children") { return 120 }
        if genres.contains("poetry") { return 140 }
        if genres.contains("young-adult") { return 250 }
        return 270
    }

    static func estimatedWords(pages: Int, genres: [String]) -> Int {
        Int((Double(max(pages, 1)) * wordsPerPage(genres: genres)).rounded())
    }

    var wordsPerPage: Double { pages > 0 ? Double(words) / Double(pages) : 270 }

    /// Minutes to read the whole book at `wpm`.
    func minutes(atWPM wpm: Double) -> Double { Double(words) / max(wpm, 1) }

    enum CoverSize: String, Sendable { case small = "S", medium = "M", large = "L" }

    func coverURL(_ size: CoverSize = .medium) -> URL? {
        guard let coverID, coverID > 0 else { return nil }
        return URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-\(size.rawValue).jpg")
    }

    var isCustom: Bool { id.hasPrefix("custom-") }

    /// A stable small integer derived from the id, for picking generated-cover palettes.
    var paletteSeed: Int {
        var hash: UInt64 = 1469598103934665603
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash % 1_000_003)
    }
}

enum Shelf: String, Codable, CaseIterable, Sendable {
    case reading, toRead, finished
}

/// A book on one of the user's shelves.
struct LibraryItem: Codable, Hashable, Identifiable, Sendable {
    var book: Book
    var shelf: Shelf
    /// The last page the reader finished (0 = not started).
    var currentPage: Int
    /// Position within the shelf; lower comes first.
    var order: Double
    var addedAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var rating: Int?

    var id: String { book.id }

    init(book: Book, shelf: Shelf, currentPage: Int = 0, order: Double, addedAt: Date = Date(), startedAt: Date? = nil, finishedAt: Date? = nil, rating: Int? = nil) {
        self.book = book
        self.shelf = shelf
        self.currentPage = currentPage
        self.order = order
        self.addedAt = addedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.rating = rating
    }

    var progress: Double {
        guard book.pages > 0 else { return 0 }
        return min(1, max(0, Double(currentPage) / Double(book.pages)))
    }

    var pagesLeft: Int { max(0, book.pages - currentPage) }

    var wordsLeft: Double { Double(pagesLeft) * book.wordsPerPage }

    func minutesLeft(atWPM wpm: Double) -> Double { wordsLeft / max(wpm, 1) }
}

/// One stretch of reading, logged when a session ends.
struct ReadingSession: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var bookID: String
    var startedAt: Date
    var seconds: Double
    var fromPage: Int
    var toPage: Int

    init(id: UUID = UUID(), bookID: String, startedAt: Date, seconds: Double, fromPage: Int, toPage: Int) {
        self.id = id
        self.bookID = bookID
        self.startedAt = startedAt
        self.seconds = seconds
        self.fromPage = fromPage
        self.toPage = toPage
    }

    var pagesRead: Int { max(0, toPage - fromPage) }
    var minutes: Double { seconds / 60 }
}

/// Which device started a live session.
enum SessionDevice: String, Codable, Sendable { case phone, watch }

/// A reading session that is in progress right now. Shared live between iPhone and Apple Watch.
struct ActiveSession: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var bookID: String
    var startedAt: Date
    /// Set while paused.
    var pausedAt: Date?
    /// Total seconds spent paused before `pausedAt`.
    var pausedSeconds: Double
    var startPage: Int
    var origin: SessionDevice
    /// Bumped on every change so both devices can keep the newest copy.
    var revision: Int

    init(id: UUID = UUID(), bookID: String, startedAt: Date = Date(), startPage: Int, origin: SessionDevice) {
        self.id = id
        self.bookID = bookID
        self.startedAt = startedAt
        self.pausedAt = nil
        self.pausedSeconds = 0
        self.startPage = startPage
        self.origin = origin
        self.revision = 0
    }

    var isPaused: Bool { pausedAt != nil }

    func elapsed(at now: Date = Date()) -> Double {
        let end = pausedAt ?? now
        return max(0, end.timeIntervalSince(startedAt) - pausedSeconds)
    }

    mutating func pause(at now: Date = Date()) {
        guard pausedAt == nil else { return }
        pausedAt = now
        revision += 1
    }

    mutating func resume(at now: Date = Date()) {
        guard let pausedAt else { return }
        pausedSeconds += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
        revision += 1
    }
}

struct SpeedTestResult: Codable, Hashable, Sendable {
    var date: Date
    var passageID: String
    var words: Int
    var seconds: Double
    var correct: Int
    var total: Int

    var rawWPM: Double { ReadingSpeed.wpm(words: words, seconds: seconds) }
    var effectiveWPM: Double { ReadingSpeed.effectiveWPM(words: words, seconds: seconds, correct: correct, total: total) }
}

/// How much haptic feedback Leaf plays.
enum HapticsLevel: String, Codable, CaseIterable, Sendable {
    /// Core Haptics signature patterns plus UIKit feedback.
    case full
    /// UIKit feedback generators only.
    case subtle
    case off
}

enum AppearancePreference: String, Codable, CaseIterable, Sendable {
    case system, day, night
}

enum PlanMode: String, Codable, CaseIterable, Sendable {
    /// Finish one book before starting the next.
    case focus
    /// Split the daily time across every book on the Reading shelf.
    case sideBySide
}

struct ReadingPreferences: Codable, Hashable, Sendable {
    var wpm: Double = ReadingSpeed.typicalAdultWPM
    var dailyMinutes: Int = 20
    /// Calendar weekdays (1 = Sunday … 7 = Saturday).
    var readingDays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    var planMode: PlanMode = .focus
    var reminderEnabled: Bool = false
    var reminderHour: Int = 20
    var reminderMinute: Int = 30
    var hasOnboarded: Bool = false
    /// When onboarding finished; Today's "No. 42" issue number counts from here.
    var onboardedAt: Date?
    /// Let real sessions refine the words-per-minute estimate.
    var learnFromSessions: Bool = true
    var hapticsLevel: HapticsLevel = .full
    var appearance: AppearancePreference = .system

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReadingPreferences()
        wpm = try c.decodeIfPresent(Double.self, forKey: .wpm) ?? d.wpm
        dailyMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyMinutes) ?? d.dailyMinutes
        readingDays = try c.decodeIfPresent(Set<Int>.self, forKey: .readingDays) ?? d.readingDays
        planMode = try c.decodeIfPresent(PlanMode.self, forKey: .planMode) ?? d.planMode
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? d.reminderEnabled
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? d.reminderHour
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? d.reminderMinute
        hasOnboarded = try c.decodeIfPresent(Bool.self, forKey: .hasOnboarded) ?? d.hasOnboarded
        onboardedAt = try c.decodeIfPresent(Date.self, forKey: .onboardedAt)
        learnFromSessions = try c.decodeIfPresent(Bool.self, forKey: .learnFromSessions) ?? d.learnFromSessions
        hapticsLevel = try c.decodeIfPresent(HapticsLevel.self, forKey: .hapticsLevel) ?? d.hapticsLevel
        appearance = try c.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? d.appearance
    }
}

/// Everything Leaf stores on the device.
struct LeafData: Codable, Sendable {
    var version: Int = 1
    var items: [LibraryItem] = []
    var sessions: [ReadingSession] = []
    var speedTests: [SpeedTestResult] = []
    var preferences = ReadingPreferences()
    var activeSession: ActiveSession?
    /// Books the reader said "not for me" to. Never recommended again, and a mild signal about taste.
    var dismissed: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try c.decodeIfPresent([LibraryItem].self, forKey: .items) ?? []
        sessions = try c.decodeIfPresent([ReadingSession].self, forKey: .sessions) ?? []
        speedTests = try c.decodeIfPresent([SpeedTestResult].self, forKey: .speedTests) ?? []
        preferences = try c.decodeIfPresent(ReadingPreferences.self, forKey: .preferences) ?? ReadingPreferences()
        activeSession = try c.decodeIfPresent(ActiveSession.self, forKey: .activeSession)
        dismissed = try c.decodeIfPresent([String].self, forKey: .dismissed) ?? []
    }

    func items(on shelf: Shelf) -> [LibraryItem] {
        let filtered = items.filter { $0.shelf == shelf }
        if shelf == .finished {
            return filtered.sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        }
        return filtered.sorted { $0.order < $1.order }
    }
}
