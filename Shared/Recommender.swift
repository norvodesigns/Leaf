import Foundation

// MARK: - Inputs

/// Everything the recommender knows about the reader. Built from the library, never sent anywhere.
struct RecommendationContext: Sendable {
    var library: [LibraryItem]
    var sessions: [ReadingSession]
    /// Books the reader marked "not for me". They never come back and count as a mild negative signal.
    var dismissed: [Book]
    var wpm: Double
    var dailyMinutes: Int
    var now: Date
    var calendar: Calendar = .current

    init(library: [LibraryItem] = [], sessions: [ReadingSession] = [], dismissed: [Book] = [], wpm: Double = ReadingSpeed.typicalAdultWPM, dailyMinutes: Int = 20, now: Date = Date(), calendar: Calendar = .current) {
        self.library = library
        self.sessions = sessions
        self.dismissed = dismissed
        self.wpm = wpm
        self.dailyMinutes = dailyMinutes
        self.now = now
        self.calendar = calendar
    }

    /// IDs of every book the reader already has or has dismissed.
    var excludedIDs: Set<String> {
        Set(library.map(\.id)).union(dismissed.map(\.id))
    }

    /// The same books by title and author, so a different edition of something already owned doesn't come back.
    var excludedTitleKeys: Set<String> {
        Set(library.map { TasteProfile.titleKey($0.book) }).union(dismissed.map(TasteProfile.titleKey))
    }

    func isExcluded(_ book: Book) -> Bool {
        excludedIDs.contains(book.id) || excludedTitleKeys.contains(TasteProfile.titleKey(book))
    }
}

// MARK: - Deterministic randomness

/// A small seedable generator, so "fresh every day" recommendations are stable within a day and testable.
/// (Swift's own `Hasher` is randomly seeded each launch, so it must never be used to make a seed.)
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    /// A stable 64-bit hash of text (FNV-1a).
    static func hash(_ text: String) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    /// One seed per calendar day.
    static func daySeed(_ date: Date, calendar: Calendar = .current) -> UInt64 {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return hash("\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)")
    }
}

// MARK: - Catalog statistics

/// Corpus-wide facts the scoring needs: how rare each genre or theme is, and where a popularity count ranks.
struct CatalogStats: Sendable {
    let total: Int
    private let documentFrequency: [String: Int]
    private let sortedPopularity: [Int]
    private let hourScale: Double

    init(books: [Book]) {
        total = books.count
        var df: [String: Int] = [:]
        for book in books {
            for key in CatalogStats.featureKeys(of: book) { df[key, default: 0] += 1 }
        }
        documentFrequency = df
        sortedPopularity = books.map(\.popularity).sorted()
        hourScale = 1
    }

    /// Feature keys for one book: `g:` genres, `t:` themes, `s:` series.
    static func featureKeys(of book: Book) -> [String] {
        var keys = book.genres.map { "g:" + $0 }
        for theme in book.themes ?? [] {
            keys.append(theme.hasPrefix("series:") ? "s:" + theme.dropFirst(7) : "t:" + theme)
        }
        return keys
    }

    /// Rarer features say more about taste than common ones. A shared "fantasy" tells you little; a shared
    /// "dragons" or a shared series tells you a lot.
    func idf(_ key: String) -> Double {
        let n = Double(documentFrequency[key] ?? 0)
        return log((Double(max(total, 1)) + 1) / (n + 1)) + 1
    }

    func frequency(_ key: String) -> Int { documentFrequency[key] ?? 0 }

    /// Where a popularity count ranks among all books, 0 (obscure) to 1 (everywhere).
    func percentile(ofPopularity pop: Int) -> Double {
        guard !sortedPopularity.isEmpty else { return 0.5 }
        var low = 0, high = sortedPopularity.count
        while low < high {
            let mid = (low + high) / 2
            if sortedPopularity[mid] < pop { low = mid + 1 } else { high = mid }
        }
        return Double(low) / Double(sortedPopularity.count)
    }
}

// MARK: - Sparse feature vectors

/// A book as weighted features, normalized so cosine similarity is a dot product.
struct FeatureVector: Sendable {
    var weights: [String: Double]
    var norm: Double

    init(book: Book, stats: CatalogStats) {
        var w: [String: Double] = [:]
        let genres = book.genres
        for g in genres { w["g:" + g] = stats.idf("g:" + g) * 1.0 / Double(max(genres.count, 1)).squareRoot() }
        for theme in book.themes ?? [] {
            let isSeries = theme.hasPrefix("series:")
            let key = isSeries ? "s:" + theme.dropFirst(7) : "t:" + theme
            // Series are the strongest "more like this" signal; themes are noisier than genres.
            w[key] = stats.idf(key) * (isSeries ? 1.6 : 0.7)
        }
        weights = w
        norm = w.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
    }

    init(weights: [String: Double]) {
        self.weights = weights
        norm = weights.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
    }

    func dot(_ other: FeatureVector) -> Double {
        let (small, large) = weights.count <= other.weights.count ? (weights, other.weights) : (other.weights, weights)
        var total = 0.0
        for (key, value) in small { if let o = large[key] { total += value * o } }
        return total
    }

    func cosine(_ other: FeatureVector) -> Double {
        guard norm > 0, other.norm > 0 else { return 0 }
        return dot(other) / (norm * other.norm)
    }

    mutating func add(_ other: FeatureVector, scale: Double) {
        guard other.norm > 0 else { return }
        for (key, value) in other.weights { weights[key, default: 0] += scale * value / other.norm }
    }

    mutating func finalize() {
        weights = weights.filter { $0.value > 1e-9 }
        norm = weights.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
    }
}

// MARK: - How much a book meant to the reader

/// Turns reading behaviour into a number from -1 (it wasn't for them) to 1 (they loved it). There are no star
/// ratings in Leaf, so this reads the signals that are there: finishing, how fast, how steadily, and stalling.
enum Engagement {
    static func score(for item: LibraryItem, sessions: [ReadingSession], wpm: Double, dailyMinutes: Int, now: Date, calendar: Calendar = .current) -> Double {
        if let rating = item.rating {
            return clamp((Double(rating) - 3) / 2 * 0.85 + (item.shelf == .finished ? 0.1 : 0))
        }
        let mine = sessions.filter { $0.bookID == item.id }
        let last = mine.map(\.startedAt).max() ?? item.startedAt ?? item.addedAt
        let daysSince = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0)

        switch item.shelf {
        case .finished:
            var value = 0.6
            if let started = item.startedAt, let finished = item.finishedAt {
                let days = max(1, Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: started), to: calendar.startOfDay(for: finished)).day ?? 1))
                // How many days it "should" take at the reader's own pace, assuming they read most days.
                let minutesPerDay = max(Double(dailyMinutes), 10)
                let expected = max(1, item.book.minutes(atWPM: wpm) / minutesPerDay / 0.7)
                let ratio = expected / days
                value += ratio >= 1 ? 0.4 * tanh(ratio - 1) : -0.15 * tanh(1 - ratio)
            }
            return clamp(value)
        case .reading:
            if daysSince >= 21 && item.progress < 0.6 {
                let stall = min(1, Double(daysSince - 21) / 60)
                return clamp(-0.1 - 0.4 * stall + 0.3 * item.progress)
            }
            let steady = mine.count >= 3 ? 0.1 : 0
            return clamp(0.2 + 0.4 * item.progress + steady)
        case .toRead:
            return 0.2
        case .paused:
            // Setting a book down says little unless it was early on; far in, it was probably just life.
            return clamp(-0.15 + 0.35 * item.progress)
        }
    }

    /// Reading lingers, so a book that has been stalled for weeks counts as one the reader gave up on.
    static func isStalled(_ item: LibraryItem, sessions: [ReadingSession], now: Date, calendar: Calendar = .current) -> Bool {
        guard item.shelf == .reading, item.progress < 0.6 else { return false }
        let last = sessions.filter { $0.bookID == item.id }.map(\.startedAt).max() ?? item.startedAt ?? item.addedAt
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= 21
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(-1, x)) }
}

// MARK: - The reader's taste

enum LengthBand: Int, CaseIterable, Sendable {
    case short, medium, long

    static func of(hours: Double) -> LengthBand { hours < 6 ? .short : (hours < 14 ? .medium : .long) }
}

struct TasteAnchor: Sendable {
    var book: Book
    var engagement: Double
    var vector: FeatureVector
}

/// A summary of what the reader has loved, finished and dropped. Computed on the device from their own library.
struct TasteProfile: Sendable {
    var positive = FeatureVector(weights: [:])
    var negative = FeatureVector(weights: [:])
    /// Author name (normalized) to affinity, -1 to 1.
    var authorAffinity: [String: Double] = [:]
    var yearMean: Double?
    var yearSpread: Double = 40
    var logHoursMean: Double?
    var logHoursSpread: Double = 0.7
    var popularityMean: Double = 0.5
    /// Total absolute engagement seen so far; below ~0.8 we treat the reader as new.
    var evidence: Double = 0
    var anchors: [TasteAnchor] = []
    var stallRate: [LengthBand: Double] = [:]
    var topGenres: [String] = []
    var topThemes: [String] = []

    var isCold: Bool { evidence < 0.8 }

    /// Lowercased, accent-free, letters and digits only. Used for authors and for title de-duplication, so
    /// digits stay (otherwise "1984" and "Fahrenheit 451" lose their identity).
    static func normalizeAuthor(_ name: String) -> String {
        let tokens = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "." }
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
        // Run initials together so "J. R. R. Tolkien", "J.R.R. Tolkien" and "JRR Tolkien" agree.
        var words: [String] = []
        var inInitials = false
        for token in tokens {
            if token.count == 1, token.first?.isLetter == true {
                if inInitials { words[words.count - 1] += token } else { words.append(String(token)) }
                inInitials = true
            } else {
                words.append(String(token))
                inInitials = false
            }
        }
        return words.joined(separator: " ")
    }

    static func titleKey(_ book: Book) -> String {
        normalizeAuthor(book.title) + "|" + normalizeAuthor(book.author)
    }
}

struct TasteProfileBuilder {
    let stats: CatalogStats
    let context: RecommendationContext

    func build() -> TasteProfile {
        var profile = TasteProfile()
        var pos = FeatureVector(weights: [:])
        var neg = FeatureVector(weights: [:])
        var authors: [String: Double] = [:]
        var yearSum = 0.0, yearW = 0.0, yearSq = 0.0
        var lhSum = 0.0, lhW = 0.0, lhSq = 0.0
        var popSum = 0.0, popW = 0.0
        var stalls: [LengthBand: (stalled: Double, total: Double)] = [:]

        func absorb(_ book: Book, engagement e: Double) {
            let vector = FeatureVector(book: book, stats: stats)
            if e > 0 { pos.add(vector, scale: e) } else if e < 0 { neg.add(vector, scale: -e) }
            authors[TasteProfile.normalizeAuthor(book.author), default: 0] += e
            profile.evidence += abs(e)
            guard e > 0.05 else { return }
            if let year = book.year { yearSum += Double(year) * e; yearSq += Double(year * year) * e; yearW += e }
            let lh = log(max(0.5, book.minutes(atWPM: context.wpm) / 60))
            lhSum += lh * e; lhSq += lh * lh * e; lhW += e
            popSum += stats.percentile(ofPopularity: book.popularity) * e; popW += e
            if e >= 0.3 { profile.anchors.append(TasteAnchor(book: book, engagement: e, vector: vector)) }
        }

        for item in context.library {
            let e = Engagement.score(for: item, sessions: context.sessions, wpm: context.wpm, dailyMinutes: context.dailyMinutes, now: context.now, calendar: context.calendar)
            absorb(item.book, engagement: e)
            // Own stall rate by length: the share of books in each band the reader started but dropped.
            if item.shelf == .finished || item.shelf == .reading {
                let band = LengthBand.of(hours: item.book.minutes(atWPM: context.wpm) / 60)
                var entry = stalls[band] ?? (0, 0)
                entry.total += 1
                if Engagement.isStalled(item, sessions: context.sessions, now: context.now, calendar: context.calendar) { entry.stalled += 1 }
                stalls[band] = entry
            }
        }
        for book in context.dismissed { absorb(book, engagement: -0.6) }

        pos.finalize(); neg.finalize()
        profile.positive = pos
        profile.negative = neg
        profile.authorAffinity = authors.mapValues { tanh($0) }
        if yearW > 0 {
            let mean = yearSum / yearW
            profile.yearMean = mean
            profile.yearSpread = max(25, (max(0, yearSq / yearW - mean * mean)).squareRoot())
        }
        if lhW > 0 {
            let mean = lhSum / lhW
            profile.logHoursMean = mean
            profile.logHoursSpread = min(1.2, max(0.45, (max(0, lhSq / lhW - mean * mean)).squareRoot()))
        }
        if popW > 0 { profile.popularityMean = popSum / popW }
        for band in LengthBand.allCases {
            let entry = stalls[band] ?? (0, 0)
            // Laplace smoothing toward a mild prior of 15% so two books don't decide it.
            profile.stallRate[band] = (entry.stalled + 0.15 * 3) / (entry.total + 3)
        }
        profile.anchors.sort { $0.engagement > $1.engagement }
        if profile.anchors.count > 40 { profile.anchors = Array(profile.anchors.prefix(40)) }
        let ranked = pos.weights.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
        profile.topGenres = ranked.filter { $0.key.hasPrefix("g:") }.prefix(5).map { String($0.key.dropFirst(2)) }
        profile.topThemes = ranked.filter { $0.key.hasPrefix("t:") }.prefix(8).map { String($0.key.dropFirst(2)) }
        return profile
    }
}

// MARK: - Recommendations

enum RecommendationReason: Hashable, Sendable {
    case becauseYouFinished(title: String)
    case becauseYouAreReading(title: String)
    case moreBy(author: String, because: String?)
    case sameSeries(series: String, because: String?)
    case lovesTheme(String)
    case lovesGenre(String)
    case fitsYourEvenings(hours: Double)
    case discover(genre: String)
    case popularInGenre(String)
    case popular

    /// A short sentence for the "because" line under a cover.
    var text: String {
        switch self {
        case .becauseYouFinished(let title): return "Because you finished \(title)"
        case .becauseYouAreReading(let title): return "Because you’re reading \(title)"
        case .moreBy(let author, _): return "More from \(author)"
        case .sameSeries(let series, let because):
            return because.map { "Continues \(series), like \($0)" } ?? "From the world of \(series)"
        case .lovesTheme(let theme): return "You like books with \(theme)"
        case .lovesGenre(let genre): return "Fits your taste for \(Genre.name(genre))"
        case .fitsYourEvenings(let hours): return "About as long as the books you finish (\(Int(hours.rounded())) h)"
        case .discover(let genre): return "Something a little different: \(Genre.name(genre))"
        case .popularInGenre(let genre): return "Popular in \(Genre.name(genre))"
        case .popular: return "Popular with readers"
        }
    }
}

struct Recommendation: Identifiable, Hashable, Sendable {
    var book: Book
    var score: Double
    var reason: RecommendationReason
    /// A rough 0 to 1 sense of how likely the reader is to finish it, from their own history. A prior, not a promise.
    var finishLikelihood: Double

    var id: String { book.id }
}

/// Friendly genre names for sentences and row titles.
enum Genre {
    static func name(_ tag: String) -> String {
        switch tag {
        case "science-fiction": return "science fiction"
        case "young-adult": return "young adult"
        case "short-stories": return "short stories"
        case "self-help": return "self-help"
        default: return tag
        }
    }
}

/// Scores books against a reader's taste. Content similarity (genres, themes, series), author affinity, and how well a
/// book fits their usual length and era, then a re-rank for variety and a few deliberate stretches.
struct Recommender {
    let stats: CatalogStats
    let context: RecommendationContext
    let profile: TasteProfile

    init(stats: CatalogStats, context: RecommendationContext) {
        self.stats = stats
        self.context = context
        self.profile = TasteProfileBuilder(stats: stats, context: context).build()
    }

    // MARK: Scoring

    private struct Scored {
        var book: Book
        var vector: FeatureVector
        var score: Double
        var content: Double
        var authorAffinity: Double
    }

    private func scored(_ book: Book) -> Scored {
        let vector = FeatureVector(book: book, stats: stats)
        let pct = stats.percentile(ofPopularity: book.popularity)
        let author = profile.authorAffinity[TasteProfile.normalizeAuthor(book.author)] ?? 0
        if profile.isCold {
            // A new reader: lean on what's popular, nudged by whatever little we know.
            let content = vector.cosine(profile.positive)
            return Scored(book: book, vector: vector, score: 0.15 * content + 0.85 * pct, content: content, authorAffinity: author)
        }
        let content = vector.cosine(profile.positive) - 0.6 * vector.cosine(profile.negative)

        let hours = max(0.5, book.minutes(atWPM: context.wpm) / 60)
        let lengthFit: Double
        if let mean = profile.logHoursMean {
            let z = (log(hours) - mean) / profile.logHoursSpread
            lengthFit = exp(-0.5 * z * z)
        } else { lengthFit = 0.6 }

        let eraFit: Double
        if let year = book.year, let mean = profile.yearMean {
            let z = (Double(year) - mean) / (profile.yearSpread + 20)
            eraFit = exp(-0.5 * z * z)
        } else { eraFit = 0.5 }

        let popFit = 1 - abs(pct - profile.popularityMean)
        let value = 0.50 * content + 0.22 * max(author, -0.5) + 0.08 * eraFit + 0.10 * lengthFit + 0.05 * popFit + 0.10 * pct
        return Scored(book: book, vector: vector, score: value, content: content, authorAffinity: author)
    }

    /// Estimated chance the reader finishes this book, from the length-band they usually drop and how well it fits them.
    func finishLikelihood(for book: Book, content: Double) -> Double {
        let band = LengthBand.of(hours: book.minutes(atWPM: context.wpm) / 60)
        let stall = profile.stallRate[band] ?? 0.15
        return min(0.97, max(0.2, (1 - stall) * 0.85 + 0.25 * max(0, content)))
    }

    // MARK: Public API

    /// The best `limit` books from `candidates` for this reader. Deterministic for a given `seed`.
    func recommend(from candidates: [Book], limit: Int, seed: UInt64, diversity: Double = 0.7, exploration: Double = 0.15, maxPerAuthor: Int = 2) -> [Recommendation] {
        let excludedIDs = context.excludedIDs
        let excludedKeys = context.excludedTitleKeys
        var seenTitles = Set<String>()
        var pool: [Scored] = []
        for book in candidates where !excludedIDs.contains(book.id) {
            let key = TasteProfile.titleKey(book)
            guard !excludedKeys.contains(key), seenTitles.insert(key).inserted else { continue }
            pool.append(scored(book))
        }
        guard !pool.isEmpty else { return [] }

        var rng = SeededGenerator(seed: seed)
        for index in pool.indices { pool[index].score += (rng.unit() - 0.5) * 0.06 }
        pool.sort { $0.score > $1.score || ($0.score == $1.score && $0.book.id < $1.book.id) }

        let stretchCount = profile.isCold ? 0 : Int((Double(limit) * exploration).rounded())
        let mainCount = limit - stretchCount
        var chosen = diversify(pool, count: mainCount, diversity: diversity, maxPerAuthor: maxPerAuthor)
        let chosenIDs = Set(chosen.map(\.book.id))

        var stretch: [Scored] = []
        if stretchCount > 0 {
            stretch = discoveryPicks(from: pool.filter { !chosenIDs.contains($0.book.id) }, count: stretchCount, rng: &rng, maxPerAuthor: maxPerAuthor, taken: chosen)
        }
        chosen.append(contentsOf: stretch)

        let stretchIDs = Set(stretch.map(\.book.id))
        return chosen.map { item in
            let reason: RecommendationReason
            if stretchIDs.contains(item.book.id) {
                reason = .discover(genre: item.book.genres.first(where: { profile.topGenres.contains($0) == false }) ?? item.book.genres.first ?? "fiction")
            } else {
                reason = explain(item)
            }
            return Recommendation(book: item.book, score: item.score, reason: reason, finishLikelihood: finishLikelihood(for: item.book, content: item.content))
        }
    }

    /// Books most like `book`, for "More like this" and "Because you finished ...".
    func similar(to book: Book, in candidates: [Book], limit: Int, because: RecommendationReason? = nil, minimumScore: Double = 0.12) -> [Recommendation] {
        let target = FeatureVector(book: book, stats: stats)
        let excluded = context.excludedIDs.union([book.id])
        let excludedKeys = context.excludedTitleKeys.union([TasteProfile.titleKey(book)])
        // A same-titled book by someone else is a different edition or a catalog quirk, never a "similar" pick.
        let ownTitle = TasteProfile.normalizeAuthor(book.title)
        var rows: [(Book, Double, FeatureVector)] = []
        for other in candidates where !excluded.contains(other.id) && !excludedKeys.contains(TasteProfile.titleKey(other))
            && TasteProfile.normalizeAuthor(other.title) != ownTitle {
            let vector = FeatureVector(book: other, stats: stats)
            var s = target.cosine(vector)
            if TasteProfile.normalizeAuthor(other.author) == TasteProfile.normalizeAuthor(book.author) { s += 0.25 }
            if let a = book.year, let b = other.year { s += 0.05 * exp(-abs(Double(a - b)) / 30) }
            s += 0.04 * stats.percentile(ofPopularity: other.popularity)
            if s > minimumScore { rows.append((other, s, vector)) }
        }
        rows.sort { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0.id < $1.0.id) }
        let scoredRows = rows.prefix(limit * 3).map { Scored(book: $0.0, vector: $0.2, score: $0.1, content: $0.1, authorAffinity: 0) }
        let picked = diversify(Array(scoredRows), count: limit, diversity: 0.85, maxPerAuthor: 3)
        return picked.map { item in
            Recommendation(book: item.book, score: item.score, reason: because ?? .becauseYouFinished(title: book.title), finishLikelihood: finishLikelihood(for: item.book, content: item.content))
        }
    }

    // MARK: Re-ranking

    /// Maximal marginal relevance: keep the best score, but penalize a pick for resembling what's already chosen,
    /// and cap how many books one author can take.
    private func diversify(_ pool: [Scored], count: Int, diversity: Double, maxPerAuthor: Int) -> [Scored] {
        guard count > 0 else { return [] }
        // A reader's favourite author can fill the top of the ranking by themselves. Build the working window with a
        // little author slack so the cap leaves plenty of other books to choose from.
        var remaining: [Scored] = []
        var inWindow: [String: Int] = [:]
        for item in pool {
            let author = TasteProfile.normalizeAuthor(item.book.author)
            if inWindow[author, default: 0] >= maxPerAuthor + 2 { continue }
            inWindow[author, default: 0] += 1
            remaining.append(item)
            if remaining.count >= max(count * 6, 60) { break }
        }
        var chosen: [Scored] = []
        var perAuthor: [String: Int] = [:]
        while chosen.count < count, !remaining.isEmpty {
            var bestIndex = -1
            var bestValue = -Double.infinity
            for (index, item) in remaining.enumerated() {
                let author = TasteProfile.normalizeAuthor(item.book.author)
                if perAuthor[author, default: 0] >= maxPerAuthor { continue }
                var redundancy = 0.0
                for other in chosen {
                    var sim = 0.6 * item.vector.cosine(other.vector)
                    if TasteProfile.normalizeAuthor(other.book.author) == author { sim += 0.4 }
                    redundancy = max(redundancy, sim)
                }
                let value = diversity * item.score - (1 - diversity) * redundancy
                if value > bestValue { bestValue = value; bestIndex = index }
            }
            if bestIndex < 0 { break }
            let pick = remaining.remove(at: bestIndex)
            perAuthor[TasteProfile.normalizeAuthor(pick.book.author), default: 0] += 1
            chosen.append(pick)
        }
        return chosen
    }

    /// A few books from genres next to the reader's favourites that they haven't tried, so taste can grow.
    private func discoveryPicks(from pool: [Scored], count: Int, rng: inout SeededGenerator, maxPerAuthor: Int, taken: [Scored]) -> [Scored] {
        let favourite = Set(profile.topGenres.prefix(3))
        let adjacent = pool.filter { item in
            let genres = Set(item.book.genres)
            return !genres.isEmpty && genres.isDisjoint(with: favourite) && item.content > 0.02
        }
        let source = adjacent.isEmpty ? pool : adjacent
        let top = Array(source.prefix(max(count * 5, 20)))
        var picks: [Scored] = []
        var authors = Set(taken.map { TasteProfile.normalizeAuthor($0.book.author) })
        var indices = Array(top.indices)
        for i in stride(from: indices.count - 1, to: 0, by: -1) { indices.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        for index in indices {
            let author = TasteProfile.normalizeAuthor(top[index].book.author)
            guard !authors.contains(author) || maxPerAuthor > 1 else { continue }
            picks.append(top[index]); authors.insert(author)
            if picks.count == count { break }
        }
        return picks
    }

    // MARK: Explaining

    /// The single most believable reason a book is on the list.
    private func explain(_ item: Scored) -> RecommendationReason {
        if profile.isCold {
            if let genre = item.book.genres.first { return .popularInGenre(genre) }
            return .popular
        }
        let nearest = profile.anchors
            .map { ($0, item.vector.cosine($0.vector)) }
            .max { $0.1 < $1.1 }

        if item.authorAffinity >= 0.5 {
            let because = profile.anchors.first { TasteProfile.normalizeAuthor($0.book.author) == TasteProfile.normalizeAuthor(item.book.author) }?.book.title
            return .moreBy(author: item.book.author, because: because)
        }
        if let series = item.book.themes?.first(where: { $0.hasPrefix("series:") }),
           let anchor = profile.anchors.first(where: { $0.book.themes?.contains(series) == true }) {
            return .sameSeries(series: String(series.dropFirst(7)).capitalized, because: anchor.book.title)
        }
        if let (anchor, similarity) = nearest, similarity >= 0.3 {
            let reading = context.library.first { $0.id == anchor.book.id }?.shelf == .reading
            return reading ? .becauseYouAreReading(title: anchor.book.title) : .becauseYouFinished(title: anchor.book.title)
        }
        let sharedTheme = (item.book.themes ?? []).first { !$0.hasPrefix("series:") && profile.topThemes.contains($0) }
        if let theme = sharedTheme { return .lovesTheme(theme) }
        if let genre = item.book.genres.first(where: { profile.topGenres.contains($0) }) { return .lovesGenre(genre) }
        if let mean = profile.logHoursMean { return .fitsYourEvenings(hours: exp(mean)) }
        return .popular
    }
}
