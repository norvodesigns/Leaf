import Foundation

// MARK: - Kinds and windows

enum ChallengeKind: String, Codable, CaseIterable, Sendable {
    case seasonalReadathon, yearlyGoal, cupGoal, genreBingo, streak, teaTasting
}

/// The stretch of time a challenge counts reading from. It is a rule, never a pair of fixed dates, so the same
/// challenge comes round again every year without the catalog going stale.
enum ChallengeWindow: Hashable, Sendable {
    /// One meteorological season (the same months as `Season`). Winter belongs to the year it starts in, so
    /// "Winter 2026" runs from December 2026 to the end of February 2027.
    case season(Season)
    /// January to December.
    case calendarYear
    /// From the day the reader joins, for this many days, or with no end at all when nil.
    case sinceJoining(days: Int?)

    /// The first month of a season in the northern hemisphere. Kept in step with `Season.of` by a test.
    static func firstMonth(of season: Season) -> Int {
        switch season {
        case .spring: return 3
        case .summer: return 6
        case .autumn: return 9
        case .winter: return 12
        }
    }

    /// The instance (year) this window would count for if the reader joined on `date`.
    func instanceYear(containing date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 1970
        switch self {
        case .season(let season):
            // January and February still belong to the winter that began the December before.
            if season == .winter, (parts.month ?? 1) <= 2 { return year - 1 }
            return year
        case .calendarYear, .sinceJoining:
            return year
        }
    }

    /// The dates this window covers for one instance. `joinedAt` only matters for `sinceJoining`.
    func span(year: Int, joinedAt: Date, calendar: Calendar) -> ChallengeSpan {
        switch self {
        case .season(let season):
            let start = calendar.date(from: DateComponents(year: year, month: ChallengeWindow.firstMonth(of: season), day: 1)) ?? joinedAt
            return ChallengeSpan(start: start, end: calendar.date(byAdding: .month, value: 3, to: start))
        case .calendarYear:
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? joinedAt
            return ChallengeSpan(start: start, end: calendar.date(byAdding: .year, value: 1, to: start))
        case .sinceJoining(let days):
            let start = calendar.startOfDay(for: joinedAt)
            return ChallengeSpan(start: start, end: days.flatMap { calendar.date(byAdding: .day, value: max(1, $0), to: start) })
        }
    }

    /// Whether the window is tied to the calendar. `sinceJoining` windows are open whenever the reader chooses.
    var isCalendarBound: Bool {
        if case .sinceJoining = self { return false }
        return true
    }
}

/// Dates from `start` up to, but not including, `end`. Open-ended when `end` is nil.
struct ChallengeSpan: Hashable, Sendable {
    var start: Date
    var end: Date?

    func contains(_ date: Date) -> Bool {
        guard date >= start else { return false }
        guard let end else { return true }
        return date < end
    }
}

// MARK: - Tasks

/// Which books fit a prompt, by genre, theme and length. Genres and themes are matched case-insensitively against
/// `Book.genres` and `Book.themes`; a book fits if it has any of the genres or any of the themes.
struct ChallengeBookMatcher: Hashable, Sendable {
    /// Lowercased on the way in, so a prompt written "Ghosts" still finds a book tagged "ghosts".
    private(set) var genres: Set<String> = []
    private(set) var themes: Set<String> = []
    var minPages: Int?
    var maxPages: Int?

    init(genres: Set<String> = [], themes: Set<String> = [], minPages: Int? = nil, maxPages: Int? = nil) {
        self.genres = Set(genres.map { $0.lowercased() })
        self.themes = Set(themes.map { $0.lowercased() })
        self.minPages = minPages
        self.maxPages = maxPages
    }

    func matches(_ book: Book) -> Bool {
        if let minPages, book.pages < minPages { return false }
        if let maxPages, book.pages > maxPages { return false }
        if genres.isEmpty && themes.isEmpty { return true }
        if !genres.isEmpty, book.genres.contains(where: { genres.contains($0.lowercased()) }) { return true }
        if !themes.isEmpty, (book.themes ?? []).contains(where: { themes.contains($0.lowercased()) }) { return true }
        return false
    }
}

/// What it takes to tick a task off.
enum ChallengeTaskGoal: Hashable, Sendable {
    /// A finished book that fits. A book fills at most one prompt in a challenge.
    case book(ChallengeBookMatcher)
    /// This percent of the challenge's target (books or cups) reached.
    case milestone(percent: Int)
    /// A full pot of tea (four cups) read within this 7-day block, counting from 1.
    case week(Int)
    /// This many reading evenings in a row.
    case evenings(Int)
    /// This many different teas read with.
    case teas(Int)
}

struct ChallengeTask: Identifiable, Hashable, Sendable {
    /// Unique within its challenge, and stable.
    var id: String
    var title: String
    var goal: ChallengeTaskGoal
}

// MARK: - Stamps

/// When a stamp is earned.
enum StampUnlock: Hashable, Sendable {
    /// When this task is complete.
    case task(String)
    /// When the whole challenge is complete.
    case completion
    /// Bingo: when this many lines (rows, columns, diagonals) are full.
    case lines(Int)
}

/// A collectible stamp, as data. `rings` is how many tea rings it is stamped with; the drawing is the UI’s job.
struct StampDesign: Identifiable, Hashable, Sendable {
    /// Stable, kebab-case, starting with the challenge id and a dot.
    var id: String
    var name: String
    /// 1 to 5 rings: the more rings, the harder it was to earn.
    var rings: Int
    var paletteToken: String
    var unlock: StampUnlock
}

// MARK: - Challenges

/// How a challenge is scored.
enum ChallengeRule: Hashable, Sendable {
    /// Each task is a prompt answered by a different finished book.
    case bookPrompts
    /// Books finished in the window against a target. Uses `preferences.yearlyGoal`, or the default when it is unset.
    case booksFinished(defaultTarget: Int)
    /// Cups read in the window against a target.
    case cups(target: Int)
    /// A full pot of tea each week.
    case weeklyPots
    /// Evenings in a row, with rest days skipped over.
    case eveningStreak
    /// Different teas read with.
    case differentTeas
}

struct Challenge: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var kind: ChallengeKind
    var window: ChallengeWindow
    var rule: ChallengeRule
    var tasks: [ChallengeTask]
    var stamps: [StampDesign]
    /// What the count is a count of, for sentences like "3 of 6 prompts".
    var unitSingular: String
    var unitPlural: String
    var paletteToken: String

    func unitName(for count: Int) -> String { count == 1 ? unitSingular : unitPlural }
}

// MARK: - Progress

enum ChallengeStatus: String, Codable, Sendable {
    /// Joined for an instance that has not begun.
    case upcoming
    case active
    case completed
    /// The window closed before it was finished.
    case ended
    /// The challenge is no longer in the catalog.
    case retired
}

/// One task's state.
struct ChallengeTaskState: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var isComplete: Bool
    /// When it was completed, from the reader's own history.
    var completedAt: Date?
    /// What completed it: a book id for a prompt, a tea id for a tasting, nil otherwise.
    var evidence: String?
}

/// A stamp the reader has earned in one challenge instance.
struct ChallengeStamp: Identifiable, Hashable, Sendable {
    var design: StampDesign
    /// The instance year, so the same design earned in two different years is two stamps.
    var year: Int
    var earnedAt: Date

    var id: String { "\(design.id)@\(year)" }
}

struct ChallengeProgress: Hashable, Sendable {
    var challengeID: String
    var year: Int
    var span: ChallengeSpan
    var tasks: [ChallengeTaskState]
    /// Progress in the challenge's own units: prompts answered, books, cups, weeks, evenings or teas.
    var current: Int
    var target: Int
    /// 0 to 1.
    var fraction: Double
    var stamps: [ChallengeStamp]
    var isComplete: Bool
    /// Whole days remaining, counting today, or nil when the window has no end.
    var daysLeft: Int?
    var status: ChallengeStatus
    /// One calm sentence for the card.
    var statusLine: String

    var completedTaskIDs: [String] { tasks.filter(\.isComplete).map(\.id) }
}

/// A challenge the reader could join now (or soon).
struct ChallengeOffer: Identifiable, Hashable, Sendable {
    var challenge: Challenge
    /// The instance year it would count for.
    var year: Int
    /// The dates it covers, or nil for a challenge that starts whenever the reader joins.
    var span: ChallengeSpan?
    /// 0 when it is open now, otherwise how many days until it opens.
    var startsInDays: Int
    var daysLeft: Int?
    var isJoined: Bool

    var id: String { "\(challenge.id)@\(year)" }
    var isOpenNow: Bool { startsInDays == 0 }
}
