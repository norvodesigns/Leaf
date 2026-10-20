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
    /// ISO 639-1 code ("en"). Nil means English / unknown.
    var language: String?
    /// Page counts of other editions, most common first, so the reader can pick the copy they own.
    var pageCounts: [Int]?

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
        themes: [String]? = nil,
        language: String? = nil,
        pageCounts: [Int]? = nil
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
        self.language = language
        self.pageCounts = pageCounts
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
    /// Set aside without guilt. Keeps its page, and the plan ignores it.
    case paused

    /// The shelves every screen lists. Paused is surfaced on its own.
    static let main: [Shelf] = [.reading, .toRead, .finished]
}

/// How the reader thinks about position. Progress is always stored as a page; percent is a way to enter and show it.
enum ProgressMode: String, Codable, CaseIterable, Sendable {
    case pages, percent
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
    /// Whether the reader enters and sees position as pages or as a percentage (e-readers).
    var progressMode: ProgressMode
    /// Where the reader began, so the first session's speed isn't measured from page 0 of a book they'd half read.
    var startPage: Int
    /// False until the reader has said where they are ("Where are you?"), or has read a session.
    var positionConfirmed: Bool
    /// When the book was set aside (only meaningful on the Paused shelf).
    var pausedAt: Date?
    /// Last change, for iCloud merging (newest wins).
    var updatedAt: Date
    /// The tea the reader pinned as this book's pairing (a catalog id or a cabinet tea's "custom." id).
    var pairedTeaID: String?
    /// Earlier read-throughs, oldest first, kept when a finished book is started again (`readThroughs` adds the
    /// current one once it is finished).
    var reads: [ReadThrough]

    var id: String { book.id }

    init(
        book: Book,
        shelf: Shelf,
        currentPage: Int = 0,
        order: Double,
        addedAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        rating: Int? = nil,
        progressMode: ProgressMode = .pages,
        startPage: Int = 0,
        positionConfirmed: Bool? = nil,
        pausedAt: Date? = nil,
        updatedAt: Date? = nil,
        pairedTeaID: String? = nil,
        reads: [ReadThrough] = []
    ) {
        self.book = book
        self.shelf = shelf
        self.currentPage = currentPage
        self.order = order
        self.addedAt = addedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.rating = rating
        self.progressMode = progressMode
        self.startPage = startPage
        self.positionConfirmed = positionConfirmed ?? (currentPage > 0 || shelf == .finished)
        self.pausedAt = pausedAt
        self.updatedAt = updatedAt ?? finishedAt ?? startedAt ?? addedAt
        self.pairedTeaID = pairedTeaID
        self.reads = reads
    }

    enum CodingKeys: String, CodingKey {
        case book, shelf, currentPage, order, addedAt, startedAt, finishedAt, rating
        case progressMode, startPage, positionConfirmed, pausedAt, updatedAt, pairedTeaID, reads
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let book = try c.decode(Book.self, forKey: .book)
        let shelf = try c.decode(Shelf.self, forKey: .shelf)
        let currentPage = try c.decodeIfPresent(Int.self, forKey: .currentPage) ?? 0
        let addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        let startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        let finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        self.init(
            book: book,
            shelf: shelf,
            currentPage: currentPage,
            order: try c.decodeIfPresent(Double.self, forKey: .order) ?? 0,
            addedAt: addedAt,
            startedAt: startedAt,
            finishedAt: finishedAt,
            rating: try c.decodeIfPresent(Int.self, forKey: .rating),
            progressMode: try c.decodeIfPresent(ProgressMode.self, forKey: .progressMode) ?? .pages,
            startPage: try c.decodeIfPresent(Int.self, forKey: .startPage) ?? 0,
            // Anyone who already had this book on a shelf before the flag existed has effectively confirmed it.
            positionConfirmed: try c.decodeIfPresent(Bool.self, forKey: .positionConfirmed) ?? true,
            pausedAt: try c.decodeIfPresent(Date.self, forKey: .pausedAt),
            updatedAt: try c.decodeIfPresent(Date.self, forKey: .updatedAt),
            pairedTeaID: try c.decodeIfPresent(String.self, forKey: .pairedTeaID),
            reads: (try? c.decodeIfPresent([ReadThrough].self, forKey: .reads)) ?? []
        )
    }

    var progress: Double {
        guard book.pages > 0 else { return 0 }
        return min(1, max(0, Double(currentPage) / Double(book.pages)))
    }

    /// Whole-number percent read, 0 to 100.
    var percent: Int { Int((progress * 100).rounded()) }

    /// The page that a percentage lands on in this book.
    static func page(forPercent percent: Double, pages: Int) -> Int {
        min(max(0, pages), max(0, Int((percent / 100 * Double(pages)).rounded())))
    }

    var pagesLeft: Int { max(0, book.pages - currentPage) }

    var wordsLeft: Double { Double(pagesLeft) * book.wordsPerPage }

    func minutesLeft(atWPM wpm: Double) -> Double { wordsLeft / max(wpm, 1) }
}

/// How a session was recorded.
enum SessionKind: String, Codable, Sendable {
    /// Timed with the in-app timer.
    case timed
    /// Typed in afterwards ("read without the timer").
    case manual
}

/// One stretch of reading, logged when a session ends.
struct ReadingSession: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var bookID: String
    var startedAt: Date
    var seconds: Double
    var fromPage: Int
    var toPage: Int
    var kind: SessionKind
    /// The tea that was steeped for this session, if any (an id from the tea catalog).
    var teaID: String?
    /// The ambience that was playing, if any.
    var ambienceID: String?
    var device: SessionDevice?

    init(
        id: UUID = UUID(),
        bookID: String,
        startedAt: Date,
        seconds: Double,
        fromPage: Int,
        toPage: Int,
        kind: SessionKind = .timed,
        teaID: String? = nil,
        ambienceID: String? = nil,
        device: SessionDevice? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.startedAt = startedAt
        self.seconds = seconds
        self.fromPage = fromPage
        self.toPage = toPage
        self.kind = kind
        self.teaID = teaID
        self.ambienceID = ambienceID
        self.device = device
    }

    enum CodingKeys: String, CodingKey {
        case id, bookID, startedAt, seconds, fromPage, toPage, kind, teaID, ambienceID, device
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            bookID: try c.decode(String.self, forKey: .bookID),
            startedAt: try c.decode(Date.self, forKey: .startedAt),
            seconds: try c.decode(Double.self, forKey: .seconds),
            fromPage: try c.decode(Int.self, forKey: .fromPage),
            toPage: try c.decode(Int.self, forKey: .toPage),
            kind: try c.decodeIfPresent(SessionKind.self, forKey: .kind) ?? .timed,
            teaID: try c.decodeIfPresent(String.self, forKey: .teaID),
            ambienceID: try c.decodeIfPresent(String.self, forKey: .ambienceID),
            device: try c.decodeIfPresent(SessionDevice.self, forKey: .device)
        )
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
    /// The tea steeping for this session, if any.
    var teaID: String?
    /// Target length in seconds (a "cup", or the rest of today's goal). Nil means open-ended.
    var goalSeconds: Double?
    var ambienceID: String?

    init(
        id: UUID = UUID(),
        bookID: String,
        startedAt: Date = Date(),
        startPage: Int,
        origin: SessionDevice,
        teaID: String? = nil,
        goalSeconds: Double? = nil,
        ambienceID: String? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.startedAt = startedAt
        self.pausedAt = nil
        self.pausedSeconds = 0
        self.startPage = startPage
        self.origin = origin
        self.revision = 0
        self.teaID = teaID
        self.goalSeconds = goalSeconds
        self.ambienceID = ambienceID
    }

    enum CodingKeys: String, CodingKey {
        case id, bookID, startedAt, pausedAt, pausedSeconds, startPage, origin, revision, teaID, goalSeconds, ambienceID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bookID = try c.decode(String.self, forKey: .bookID)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
        pausedSeconds = try c.decodeIfPresent(Double.self, forKey: .pausedSeconds) ?? 0
        startPage = try c.decodeIfPresent(Int.self, forKey: .startPage) ?? 0
        origin = try c.decodeIfPresent(SessionDevice.self, forKey: .origin) ?? .phone
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        teaID = try c.decodeIfPresent(String.self, forKey: .teaID)
        goalSeconds = try c.decodeIfPresent(Double.self, forKey: .goalSeconds)
        ambienceID = try c.decodeIfPresent(String.self, forKey: .ambienceID)
    }

    var isPaused: Bool { pausedAt != nil }

    func elapsed(at now: Date = Date()) -> Double {
        let end = pausedAt ?? now
        return max(0, end.timeIntervalSince(startedAt) - pausedSeconds)
    }

    /// Seconds until the goal, or nil when the session is open-ended. Negative once the goal is passed.
    func remaining(at now: Date = Date()) -> Double? {
        goalSeconds.map { $0 - elapsed(at: now) }
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

/// A note or a quote the reader saved while reading.
struct JournalEntry: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// A thought of the reader's own.
        case thought
        /// Words copied from the book (typed, dictated, or scanned).
        case quote
    }

    var id: UUID
    var bookID: String
    /// Kept with the entry so a quote still reads properly after the book leaves the library.
    var bookTitle: String
    var bookAuthor: String
    var kind: Kind
    var text: String
    /// The page it's from, when known.
    var page: Int?
    /// The session it was written during, if any.
    var sessionID: UUID?
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookID: String,
        bookTitle: String = "",
        bookAuthor: String = "",
        kind: Kind = .thought,
        text: String,
        page: Int? = nil,
        sessionID: UUID? = nil,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.kind = kind
        self.text = text
        self.page = page
        self.sessionID = sessionID
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// Remembers a deletion so it can reach the reader's other devices instead of the item coming back.
struct Tombstone: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// A library item (key is the book id).
        case item
        /// A journal entry (key is the entry's UUID string).
        case journal
        /// A "not for me" that was taken back (key is the book id).
        case dismissal
        /// A challenge the reader left (key is the challenge id).
        case challenge
        /// A tea taken out of the cabinet (key is its UUID string).
        case cabinetTea
        /// A tasting note deleted (key is its UUID string).
        case tasting
        /// An earlier read-through taken off a book (key is the read-through's UUID string).
        case read
    }

    var kind: Kind
    var key: String
    var deletedAt: Date
}

/// A cozy challenge the reader has joined. Progress is worked out from their shelves and sessions.
struct ChallengeEnrollment: Codable, Hashable, Identifiable, Sendable {
    /// The challenge's id in the challenge catalog.
    var id: String
    var joinedAt: Date
    /// The year or season instance it counts for (yearly goals repeat).
    var year: Int?
}

/// What the plan does about days that were missed.
enum CatchUpMode: String, Codable, CaseIterable, Sendable {
    /// Move on; nothing to make up. The default, with no guilt.
    case forgive
    /// Push finish dates later by the missed time.
    case shift
    /// Ask for a little extra on the days that follow.
    case compress
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
    /// Last change, for iCloud merging (newest wins).
    var updatedAt: Date = .distantPast
    /// Books to finish this year, or nil for no goal.
    var yearlyGoal: Int?
    /// The tea the reader usually brews (an id from the tea catalog).
    var favoriteTeaID: String?
    /// The ambience they like (an id from the ambience catalog), or nil for silence.
    var ambienceID: String?
    /// Times of day set aside for reading. Empty means the single reminder time below.
    var readingSlots: [ReadingSlot] = []
    /// Length of a "cup" of reading, in minutes.
    var cupMinutes: Int = 25
    var catchUp: CatchUpMode = .forgive
    /// Which nook scene the Today header and sessions use (nil follows the season and the hour).
    var nookScene: String?
    /// A short recap on Sunday evenings.
    var weeklyLetter: Bool = false
    /// Let Apple Intelligence (when available) write greetings. Off by default; templates are always the fallback.
    var aiGreetings: Bool = false
    var liveActivities: Bool = true
    /// Back up and sync through the reader's own iCloud.
    var syncEnabled: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReadingPreferences()
        let s = decoder.decodeSkips
        wpm = try c.decode(Double.self, forKey: .wpm, or: d.wpm, skips: s)
        dailyMinutes = try c.decode(Int.self, forKey: .dailyMinutes, or: d.dailyMinutes, skips: s)
        readingDays = try c.decode(Set<Int>.self, forKey: .readingDays, or: d.readingDays, skips: s)
        planMode = try c.decode(PlanMode.self, forKey: .planMode, or: d.planMode, skips: s)
        reminderEnabled = try c.decode(Bool.self, forKey: .reminderEnabled, or: d.reminderEnabled, skips: s)
        reminderHour = try c.decode(Int.self, forKey: .reminderHour, or: d.reminderHour, skips: s)
        reminderMinute = try c.decode(Int.self, forKey: .reminderMinute, or: d.reminderMinute, skips: s)
        hasOnboarded = try c.decode(Bool.self, forKey: .hasOnboarded, or: d.hasOnboarded, skips: s)
        onboardedAt = try c.decodeOptional(Date.self, forKey: .onboardedAt, skips: s)
        learnFromSessions = try c.decode(Bool.self, forKey: .learnFromSessions, or: d.learnFromSessions, skips: s)
        hapticsLevel = try c.decode(HapticsLevel.self, forKey: .hapticsLevel, or: d.hapticsLevel, skips: s)
        appearance = try c.decode(AppearancePreference.self, forKey: .appearance, or: d.appearance, skips: s)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt, or: d.updatedAt, skips: s)
        yearlyGoal = try c.decodeOptional(Int.self, forKey: .yearlyGoal, skips: s)
        favoriteTeaID = try c.decodeOptional(String.self, forKey: .favoriteTeaID, skips: s)
        ambienceID = try c.decodeOptional(String.self, forKey: .ambienceID, skips: s)
        readingSlots = try c.decodeList(ReadingSlot.self, forKey: .readingSlots, skips: s)
        cupMinutes = try c.decode(Int.self, forKey: .cupMinutes, or: d.cupMinutes, skips: s)
        catchUp = try c.decode(CatchUpMode.self, forKey: .catchUp, or: d.catchUp, skips: s)
        nookScene = try c.decodeOptional(String.self, forKey: .nookScene, skips: s)
        weeklyLetter = try c.decode(Bool.self, forKey: .weeklyLetter, or: d.weeklyLetter, skips: s)
        aiGreetings = try c.decode(Bool.self, forKey: .aiGreetings, or: d.aiGreetings, skips: s)
        liveActivities = try c.decode(Bool.self, forKey: .liveActivities, or: d.liveActivities, skips: s)
        syncEnabled = try c.decode(Bool.self, forKey: .syncEnabled, or: d.syncEnabled, skips: s)
    }
}

/// Everything Leaf stores on the device.
struct LeafData: Codable, Sendable {
    /// 2 added iCloud-ready stamps, the Paused shelf, the journal and challenges. Older files still load.
    var version: Int = 2
    var items: [LibraryItem] = []
    var sessions: [ReadingSession] = []
    var speedTests: [SpeedTestResult] = []
    var preferences = ReadingPreferences()
    var activeSession: ActiveSession?
    /// Books the reader said "not for me" to. Never recommended again, and a mild signal about taste.
    var dismissed: [String] = []
    var journal: [JournalEntry] = []
    var challenges: [ChallengeEnrollment] = []
    /// Deletions that still need to reach other devices.
    var tombstones: [Tombstone] = []
    /// The reader's own teas.
    var cabinet: [CabinetTea] = []
    /// Notes on cups, written after reading with tea.
    var tastings: [TastingNote] = []

    init() {}

    /// Strict by default; tolerant when the decoder carries a `DecodeSkips` (the library file does), so an entry this
    /// version can't read costs that entry and not the whole library.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = decoder.decodeSkips
        version = try c.decode(Int.self, forKey: .version, or: 1, skips: s)
        items = try c.decodeList(LibraryItem.self, forKey: .items, skips: s)
        sessions = try c.decodeList(ReadingSession.self, forKey: .sessions, skips: s)
        speedTests = try c.decodeList(SpeedTestResult.self, forKey: .speedTests, skips: s)
        preferences = try c.decode(ReadingPreferences.self, forKey: .preferences, or: ReadingPreferences(), skips: s)
        activeSession = try c.decodeOptional(ActiveSession.self, forKey: .activeSession, skips: s)
        dismissed = try c.decodeList(String.self, forKey: .dismissed, skips: s)
        journal = try c.decodeList(JournalEntry.self, forKey: .journal, skips: s)
        challenges = try c.decodeList(ChallengeEnrollment.self, forKey: .challenges, skips: s)
        tombstones = try c.decodeList(Tombstone.self, forKey: .tombstones, skips: s)
        cabinet = try c.decodeList(CabinetTea.self, forKey: .cabinet, skips: s)
        tastings = try c.decodeList(TastingNote.self, forKey: .tastings, skips: s)
    }

    func items(on shelf: Shelf) -> [LibraryItem] {
        let filtered = items.filter { $0.shelf == shelf }
        if shelf == .finished {
            return filtered.sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        }
        return filtered.sorted { $0.order < $1.order }
    }
}
