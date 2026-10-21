import Foundation

/// "Ask the Librarian": a short written conversation (what mood, how much time, how long a book) that ends in a handful
/// of picks, each with a true "why this" line. Entirely offline: it filters the browse pool by the answers and lets the
/// `Recommender` order what is left by taste. Nothing is spoken and nothing leaves the device.
///
/// The librarian's own words are written text from `LibrarianLines`, checked against `VoiceTone` like every other line.
struct LibrarianAsk: Hashable, Sendable {
    /// One of the moods the carousels already use (`CollectionBuilder.moods`), or nil to be surprised.
    var moodID: String?
    var time: Time?
    var length: Length?

    init(moodID: String? = nil, time: Time? = nil, length: Length? = nil) {
        self.moodID = moodID
        self.time = time
        self.length = length
    }

    /// How long the reader wants to spend with the book, at their own pace.
    enum Time: String, CaseIterable, Hashable, Sendable {
        /// One evening: up to three hours.
        case tonight
        /// Up to about eight hours.
        case weekend
        /// Finishable within a week of their usual daily minutes.
        case thisWeek
        /// Something to live in for a while: at least two weeks of their usual minutes.
        case longHaul

        var label: String {
            switch self {
            case .tonight: "Just tonight"
            case .weekend: "A weekend"
            case .thisWeek: "This week"
            case .longHaul: "Something to live in"
            }
        }

        /// Whether the answer already settles the length, so the length question can be skipped.
        var settlesLength: Bool { self == .tonight || self == .weekend }

        func fits(minutes: Double, dailyMinutes: Int) -> Bool {
            let daily = Double(max(dailyMinutes, 5))
            switch self {
            case .tonight: return minutes <= 180
            case .weekend: return minutes <= 480
            case .thisWeek: return minutes <= daily * 7
            case .longHaul: return minutes >= daily * 14
            }
        }
    }

    /// The book's size on the shelf, in pages.
    enum Length: String, CaseIterable, Hashable, Sendable {
        case slim, middling, doorstop, any

        var label: String {
            switch self {
            case .slim: "Slim"
            case .middling: "Middling"
            case .doorstop: "A doorstop"
            case .any: "Any length"
            }
        }

        var detail: String {
            switch self {
            case .slim: "under 250 pages"
            case .middling: "250 to 450 pages"
            case .doorstop: "450 pages or more"
            case .any: "whatever fits"
            }
        }

        func fits(pages: Int) -> Bool {
            switch self {
            case .slim: return pages < 250
            case .middling: return (250..<450).contains(pages)
            case .doorstop: return pages >= 450
            case .any: return true
            }
        }
    }
}

/// A mood the reader can ask for: the carousel's weights plus how the librarian talks about it.
struct LibrarianMood: Identifiable, Hashable, Sendable {
    var id: String
    /// The chip ("Cozy").
    var label: String
    /// SF Symbol for the chip.
    var symbol: String
    /// How the "why this" line names it ("for a cozy mood").
    var phrase: String

    /// The moods offered, in the order the chips show them. Each id is one of `CollectionBuilder.moods`.
    static let all: [LibrarianMood] = [
        LibrarianMood(id: "cozy", label: "Cozy", symbol: "cup.and.saucer", phrase: "a cozy mood"),
        LibrarianMood(id: "cozy-mystery", label: "A gentle mystery", symbol: "magnifyingglass", phrase: "a gentle mystery"),
        LibrarianMood(id: "page-turners", label: "Can’t put it down", symbol: "bolt", phrase: "a page-turner"),
        LibrarianMood(id: "feel-good", label: "Warm and hopeful", symbol: "sun.max", phrase: "something warm"),
        LibrarianMood(id: "escape", label: "Somewhere else", symbol: "sparkles", phrase: "an escape"),
        LibrarianMood(id: "big-feelings", label: "Big feelings", symbol: "heart", phrase: "big feelings"),
        LibrarianMood(id: "rainy", label: "Rainy day", symbol: "cloud.rain", phrase: "a rainy day"),
        LibrarianMood(id: "slow", label: "Slow and lyrical", symbol: "leaf", phrase: "slow, lovely sentences"),
        LibrarianMood(id: "laugh", label: "Make me laugh", symbol: "face.smiling", phrase: "a laugh"),
        LibrarianMood(id: "brain-food", label: "Brain food", symbol: "lightbulb", phrase: "ideas to chew on"),
        LibrarianMood(id: "spooky", label: "Spooky", symbol: "moon.stars", phrase: "something spooky"),
        LibrarianMood(id: "old-friends", label: "A classic", symbol: "books.vertical", phrase: "an old friend"),
    ]

    static func mood(id: String?) -> LibrarianMood? { all.first { $0.id == id } }

    var weights: CollectionBuilder.Mood? { CollectionBuilder.moods.first { $0.id == id } }
}

/// One book the librarian hands over.
struct LibrarianPick: Identifiable, Hashable, Sendable {
    var book: Book
    /// The recommender's own reason, kept so the UI can tell personal picks from popular ones.
    var reason: RecommendationReason
    /// The "why this" line: the most personal true thing we can say.
    var why: String
    /// How it fits the time asked for ("About 3 h, one evening at your pace").
    var fit: String
    var finishLikelihood: Double

    var id: String { book.id }

    /// Whether the reason comes from the reader's own shelves rather than general popularity.
    var isPersonal: Bool {
        switch reason {
        case .popular, .popularInGenre: false
        default: true
        }
    }
}

/// What the librarian found.
struct LibrarianAnswer: Sendable {
    enum Loosened: String, Hashable, Sendable {
        case length, time, mood
    }

    var ask: LibrarianAsk
    /// The best few, ordered by taste. Empty only when the pool has nothing at all.
    var picks: [LibrarianPick]
    /// Every book that matched (after loosening), most fitting first, for "swipe through more".
    var matches: [Book]
    /// Which answers had to be relaxed to find enough books, in the order they were relaxed.
    var loosened: [Loosened]
}

/// Finds books for a `LibrarianAsk`. A value type with no UI; run `answer` off the main thread on a large pool.
struct Librarian {
    let pool: [Book]
    let stats: CatalogStats
    let context: RecommendationContext

    /// Fewer matches than this and the librarian loosens an answer.
    var minimumMatches = 8
    /// How many mood matches to hand the recommender, best mood fit first.
    var candidateCap = 1_500

    func answer(_ ask: LibrarianAsk, limit: Int = 8, seed: UInt64, excluding shown: Set<String> = []) -> LibrarianAnswer {
        let available = pool.filter { !shown.contains($0.id) && !context.isExcluded($0) }
        var current = ask
        var loosened: [LibrarianAnswer.Loosened] = []
        var matches = self.matches(for: current, in: available)
        // Relax the least important answer first: the shelf size, then the time, then the mood's strictness.
        if matches.count < minimumMatches, current.length != nil, current.length != .any {
            current.length = nil
            loosened.append(.length)
            matches = self.matches(for: current, in: available)
        }
        if matches.count < minimumMatches, current.time != nil {
            current.time = nil
            loosened.append(.time)
            matches = self.matches(for: current, in: available)
        }
        if matches.count < minimumMatches, current.moodID != nil {
            loosened.append(.mood)
            matches = self.matches(for: current, in: available, moodStrictness: 0.5)
        }

        let recommender = Recommender(stats: stats, context: context)
        let surprise = ask.moodID == nil
        let recommendations = recommender.recommend(
            from: Array(matches.prefix(candidateCap)), limit: limit, seed: seed,
            diversity: surprise ? 0.9 : 0.7, exploration: surprise ? 0.3 : 0.15, maxPerAuthor: 1
        )
        let picks = recommendations.map { pick(from: $0, ask: current) }
        return LibrarianAnswer(ask: ask, picks: picks, matches: matches, loosened: loosened)
    }

    // MARK: Matching

    /// Books that fit every answer given, best mood match first (popularity breaks ties).
    func matches(for ask: LibrarianAsk, in books: [Book], moodStrictness: Double = 1) -> [Book] {
        let mood = LibrarianMood.mood(id: ask.moodID)?.weights
        var scored: [(book: Book, score: Double)] = []
        scored.reserveCapacity(min(books.count, 4_096))
        for book in books {
            if let length = ask.length, !length.fits(pages: book.pages) { continue }
            if let time = ask.time, !time.fits(minutes: book.minutes(atWPM: context.wpm), dailyMinutes: context.dailyMinutes) { continue }
            var score = 0.0
            if let mood {
                let keys = CatalogStats.featureKeys(of: book)
                if keys.contains(where: mood.avoid.contains) { continue }
                for key in keys { score += mood.weights[key] ?? 0 }
                guard score >= mood.minimum * moodStrictness else { continue }
            }
            scored.append((book, score))
        }
        scored.sort { $0.score > $1.score || ($0.score == $1.score && $0.book.popularity > $1.book.popularity) }
        return scored.map(\.book)
    }

    // MARK: Explaining

    private func pick(from recommendation: Recommendation, ask: LibrarianAsk) -> LibrarianPick {
        let book = recommendation.book
        let personal: Bool
        switch recommendation.reason {
        case .popular, .popularInGenre: personal = false
        default: personal = true
        }
        let why = personal ? recommendation.reason.text : (moodLine(for: book, moodID: ask.moodID) ?? recommendation.reason.text)
        return LibrarianPick(
            book: book,
            reason: recommendation.reason,
            why: why,
            fit: fitLine(for: book, time: ask.time),
            finishLikelihood: recommendation.finishLikelihood
        )
    }

    /// "Tea & cafes and cats, for a cozy mood": the two strongest themes the book shares with the mood.
    func moodLine(for book: Book, moodID: String?) -> String? {
        guard let mood = LibrarianMood.mood(id: moodID), let weights = mood.weights?.weights else { return nil }
        let themes = (book.themes ?? [])
            .filter { !$0.hasPrefix("series:") }
            .compactMap { theme in weights["t:" + theme].map { (theme, $0) } }
            .sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
            .prefix(2)
            .map(\.0)
        switch themes.count {
        case 0:
            guard let genre = book.genres.first(where: { weights["g:" + $0] != nil }) else { return nil }
            return "\(Genre.name(genre).capitalizedFirst), for \(mood.phrase)"
        case 1:
            return "\(themes[0].capitalizedFirst), for \(mood.phrase)"
        default:
            return "\(themes[0].capitalizedFirst) and \(themes[1]), for \(mood.phrase)"
        }
    }

    /// "About 3 h, one evening at your pace" / "About 9 h, a week of your usual minutes".
    func fitLine(for book: Book, time: LibrarianAsk.Time?) -> String {
        let minutes = book.minutes(atWPM: context.wpm)
        let hours = max(1, Int((minutes / 60).rounded()))
        let daily = Double(max(context.dailyMinutes, 5))
        let days = max(1, Int((minutes / daily).rounded(.up)))
        let length = minutes < 60 ? "Under an hour" : "About \(hours) h"
        switch time {
        case .tonight?:
            return "\(length), one evening at your pace"
        case .weekend?:
            return "\(length), a weekend at your pace"
        default:
            if days == 1 { return "\(length), a day of your usual reading" }
            if days <= 7 { return "\(length), \(days) days of your usual reading" }
            let weeks = Int((Double(days) / 7).rounded())
            return weeks <= 1 ? "\(length), about a week of your usual reading" : "\(length), about \(weeks) weeks of your usual reading"
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - The librarian's words

/// What the librarian says, as written text. Short, kind, never pushy, and checked by `VoiceTone` in the tests.
enum LibrarianLines {
    static let openers = [
        "Hello there. What are you in the mood for?",
        "Pull up a chair. What sort of book tonight?",
        "Tell me a mood and I’ll find the shelf.",
        "What kind of story are you after?",
    ]

    static let askTime = [
        "Lovely. How much time do you have for it?",
        "Good choice. How long would you like to spend with it?",
        "I know just the shelf. How much time are we filling?",
    ]

    static let askLength = [
        "And on the shelf, slim or substantial?",
        "One more thing. How big a book?",
        "Last question. How many pages feel right?",
    ]

    /// When the time already settles the length.
    static let skipLength = [
        "Then we’ll keep it slim. Here’s what I found.",
        "Short and sweet, then. Have a look at these.",
    ]

    static let answers = [
        "Here’s what I’d pull from the shelves.",
        "These caught my eye for you.",
        "A few I think you’ll like.",
        "I found some good ones.",
    ]

    static let surprise = [
        "A surprise, then. A few from all over the shop.",
        "Let me wander the stacks for you.",
    ]

    static let again = [
        "A few more from the same shelf.",
        "Here are some others.",
    ]

    static let loosened: [LibrarianAnswer.Loosened: String] = [
        .length: "Nothing quite that size, so I widened the shelf a little.",
        .time: "Few that short, so I let the time stretch a bit.",
        .mood: "That shelf is thin, so these are near neighbours.",
    ]

    static let nothing = "I couldn’t find anything new on that shelf. Try another mood?"

    static var all: [String] {
        openers + askTime + askLength + skipLength + answers + surprise + again + Array(loosened.values) + [nothing]
    }

    /// One line from a pool, stable for a given seed.
    static func pick(_ lines: [String], seed: UInt64) -> String {
        guard !lines.isEmpty else { return "" }
        return lines[Int(seed % UInt64(lines.count))]
    }

    /// The reply above the picks: what happened, then any loosening.
    static func reply(for answer: LibrarianAnswer, round: Int, seed: UInt64) -> String {
        if answer.picks.isEmpty { return nothing }
        if round > 0 { return pick(again, seed: seed) }
        if let first = answer.loosened.first, let line = loosened[first] { return line }
        if answer.ask.moodID == nil { return pick(surprise, seed: seed) }
        return pick(answers, seed: seed)
    }
}
