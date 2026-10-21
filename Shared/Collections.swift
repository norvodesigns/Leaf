import Foundation

enum CollectionKind: String, Sendable {
    /// Built from this reader's own taste.
    case personal
    /// Built from the moment: season, time of day, holidays.
    case context
    /// A way into the catalog that anyone can browse.
    case browse
}

/// One carousel on the Search tab.
struct BookCollection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var books: [Book]
    var kind: CollectionKind = .browse
    /// Why each book is here, by book id. Filled for personal rows ("Because you finished ...").
    var reasons: [String: String] = [:]
}

/// Turns a big catalog into a long, varied list of carousels, so browsing feels as deep as the library really is.
///
/// Rows come from many angles (mood, genre, theme, series, author, decade, time budget, season, the reader's taste),
/// are ordered so neighbouring rows feel different, share books sparingly, and only appear when they have enough
/// good books. The order is stable within a day and changes between days.
struct CollectionBuilder {
    var books: [Book]
    var stats: CatalogStats
    var wpm: Double
    var dailyMinutes: Int
    var now: Date
    var calendar: Calendar = .current
    var context: RecommendationContext?
    var excluding: Set<String> = []
    var rowSize = 36
    var maxRows = 140
    var minimumBooks = 8
    /// A book may appear in this many rows on one screen, at most.
    var maxExposure = 3

    // MARK: Entry point

    /// Books the reader doesn't already have, most popular first.
    private func eligiblePool() -> [Book] {
        let blocked = excluding.union(context?.excludedIDs ?? [])
        let blockedKeys = context?.excludedTitleKeys ?? []
        return books
            .filter { !blocked.contains($0.id) && (blockedKeys.isEmpty || !blockedKeys.contains(TasteProfile.titleKey($0))) }
            .sorted { $0.popularity > $1.popularity || ($0.popularity == $1.popularity && $0.id < $1.id) }
    }

    /// A small, varied table for the first-run picker: the best-loved books, then a few short ones.
    func starterBooks(count: Int = 12) -> [Book] {
        let pool = eligiblePool()
        guard !pool.isEmpty else { return [] }
        let index = PoolIndex(pool: pool, stats: stats, wpm: wpm)
        let loved = popularDraft(index: index).candidates.prefix(9)
        let lovedIDs = Set(loved.map(\.id))
        let short = pool.indices.filter { index.hours[$0] < 4 && pool[$0].pages >= 80 && !lovedIDs.contains(pool[$0].id) }.prefix(6).map { pool[$0] }
        return Array((Array(loved) + short).prefix(count))
    }

    func build() -> [BookCollection] {
        let pool = eligiblePool()
        guard !pool.isEmpty else { return [] }

        let seed = SeededGenerator.daySeed(now, calendar: calendar)
        let index = PoolIndex(pool: pool, stats: stats, wpm: wpm)
        var drafts: [Draft] = []

        // Personal rows lead, then the moment, then everything else interleaved.
        var recommender: Recommender?
        if let context { recommender = Recommender(stats: stats, context: context) }
        drafts += personalDrafts(pool: pool, index: index, recommender: recommender, seed: seed)
        drafts += contextDrafts(index: index)

        var categories: [[Draft]] = [
            moodDrafts(index: index),
            genreDrafts(index: index, recommender: recommender),
            themeDrafts(index: index, recommender: recommender),
            timeDrafts(index: index),
            seriesDrafts(index: index),
            authorDrafts(index: index),
            decadeDrafts(index: index),
            hiddenGemDrafts(index: index),
            genreLengthDrafts(index: index),
        ]
        var rng = SeededGenerator(seed: seed ^ 0xA5A5)
        for i in categories.indices where i != 0 { categories[i] = shuffled(categories[i], rng: &rng, keepFirst: 2) }
        drafts += interleave(categories, pattern: [0, 1, 2, 0, 3, 1, 4, 2, 5, 0, 6, 1, 7, 2, 8, 3])

        return compose(drafts, pool: pool, seed: seed)
    }

    // MARK: Drafts

    private struct Draft {
        var id: String
        var title: String
        var subtitle: String
        var kind: CollectionKind
        /// Best first.
        var candidates: [Book]
        var reasons: [String: String] = [:]
        /// Personal rows are already in their final order and shouldn't be reshuffled.
        var ordered = false
    }

    /// Fast lookups over the pool, built once.
    private struct PoolIndex {
        let pool: [Book]
        let keys: [Set<String>]
        let byKey: [String: [Int]]
        let hours: [Double]
        let percentile: [Double]

        init(pool: [Book], stats: CatalogStats, wpm: Double) {
            self.pool = pool
            var keys: [Set<String>] = []
            var byKey: [String: [Int]] = [:]
            var hours: [Double] = []
            var pct: [Double] = []
            keys.reserveCapacity(pool.count)
            for (i, book) in pool.enumerated() {
                let k = Set(CatalogStats.featureKeys(of: book))
                keys.append(k)
                for key in k { byKey[key, default: []].append(i) }
                hours.append(max(0.1, book.minutes(atWPM: wpm) / 60))
                pct.append(stats.percentile(ofPopularity: book.popularity))
            }
            self.keys = keys; self.byKey = byKey; self.hours = hours; self.percentile = pct
        }

        func books(with key: String) -> [Book] { (byKey[key] ?? []).map { pool[$0] } }
        func books(where predicate: (Int) -> Bool) -> [Book] { pool.indices.filter(predicate).map { pool[$0] } }
    }

    // MARK: Personal

    private func personalDrafts(pool: [Book], index: PoolIndex, recommender: Recommender?, seed: UInt64) -> [Draft] {
        guard let recommender else { return [popularDraft(index: index)] }
        let profile = recommender.profile
        if profile.isCold { return [popularDraft(index: index)] }

        var drafts: [Draft] = []
        let candidates = candidatePool(pool: pool, profile: profile, index: index)

        let picks = recommender.recommend(from: candidates, limit: rowSize, seed: seed)
        if !picks.isEmpty {
            drafts.append(Draft(id: "for-you", title: "Picked for you", subtitle: "Chosen from what you’ve read and finished", kind: .personal,
                                candidates: picks.map(\.book), reasons: Dictionary(picks.map { ($0.book.id, $0.reason.text) }, uniquingKeysWith: { a, _ in a }), ordered: true))
        }

        // "Because you finished ..." for the books that clearly landed.
        var used = Set<String>()
        for anchor in profile.anchors.prefix(8) where drafts.filter({ $0.id.hasPrefix("because-") }).count < 3 {
            guard anchor.engagement >= 0.5, used.insert(anchor.book.id).inserted else { continue }
            let reading = recommender.context.library.first { $0.id == anchor.book.id }?.shelf == .reading
            let reason: RecommendationReason = reading ? .becauseYouAreReading(title: anchor.book.title) : .becauseYouFinished(title: anchor.book.title)
            // A weak match is worse than no row: skip books with too few features to compare.
            let similar = recommender.similar(to: anchor.book, in: candidates, limit: rowSize / 2 + 6, because: reason, minimumScore: 0.3)
            guard similar.count >= minimumBooks else { continue }
            drafts.append(Draft(id: "because-\(anchor.book.id)", title: reading ? "Because you’re reading \(anchor.book.title)" : "Because you finished \(anchor.book.title)",
                                subtitle: "More in the same spirit", kind: .personal, candidates: similar.map(\.book),
                                reasons: Dictionary(similar.map { ($0.book.id, $0.reason.text) }, uniquingKeysWith: { a, _ in a }), ordered: true))
        }

        // Pick up a series where the reader left it.
        var seenSeries = Set<String>()
        for anchor in profile.anchors {
            for theme in (anchor.book.themes ?? []) where theme.hasPrefix("series:") && seenSeries.insert(theme).inserted {
                let rest = index.books(with: "s:" + theme.dropFirst(7))
                guard rest.count >= 2 else { continue }
                let name = displayName(String(theme.dropFirst(7)))
                drafts.append(Draft(id: "continue-\(theme)", title: "Continue with \(name)", subtitle: "You enjoyed \(anchor.book.title)", kind: .personal, candidates: rest,
                                    reasons: Dictionary(rest.map { ($0.id, "Continues \(name)") }, uniquingKeysWith: { a, _ in a })))
            }
            if seenSeries.count >= 2 { break }
        }

        // Authors they keep coming back to.
        let favouriteAuthors = profile.authorAffinity.filter { $0.value >= 0.5 }.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.prefix(2)
        for (author, _) in favouriteAuthors {
            let theirs = pool.filter { TasteProfile.normalizeAuthor($0.author) == author }
            guard theirs.count >= 3, let name = theirs.first?.author else { continue }
            drafts.append(Draft(id: "author-fav-\(author)", title: "More from \(name)", subtitle: "You’ve liked their books", kind: .personal, candidates: theirs,
                                reasons: Dictionary(theirs.map { ($0.id, "More from \(name)") }, uniquingKeysWith: { a, _ in a })))
        }

        // The right length.
        if let mean = profile.logHoursMean {
            let target = exp(mean)
            let fits = pool.indices.filter { abs(log(index.hours[$0]) - mean) < 0.3 && index.keys[$0].contains(where: { profile.positive.weights[$0] != nil }) }.map { pool[$0] }
            if fits.count >= minimumBooks {
                drafts.append(Draft(id: "your-length", title: "About the length you like", subtitle: "You tend to finish books of around \(Int(target.rounded())) hours", kind: .personal,
                                    candidates: fits.sorted { recommender.profile.positive.cosine(FeatureVector(book: $0, stats: stats)) > recommender.profile.positive.cosine(FeatureVector(book: $1, stats: stats)) }))
            }
        }

        // A few deliberate stretches.
        let stretch = recommender.recommend(from: candidates, limit: rowSize / 2, seed: seed ^ 0xD15C, exploration: 1.0)
        if stretch.count >= minimumBooks {
            drafts.append(Draft(id: "different", title: "Something a little different", subtitle: "Next door to what you love, but new", kind: .personal,
                                candidates: stretch.map(\.book), reasons: Dictionary(stretch.map { ($0.book.id, $0.reason.text) }, uniquingKeysWith: { a, _ in a }), ordered: true))
        }
        return drafts
    }

    /// Scoring all of a huge catalog is wasteful: take the popular head plus everything that shares a feature with what
    /// the reader likes. At 250k books this keeps the pool in the tens of thousands.
    private func candidatePool(pool: [Book], profile: TasteProfile, index: PoolIndex) -> [Book] {
        if pool.count <= 12_000 { return pool }
        var chosen = Set<Int>(pool.indices.prefix(6_000))
        let liked = profile.positive.weights.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.prefix(40).map(\.key)
        for key in liked { chosen.formUnion((index.byKey[key] ?? []).prefix(600)) }
        return chosen.sorted().map { pool[$0] }
    }

    private func popularDraft(index: PoolIndex) -> Draft {
        // Raw popularity skews hard to self-help and business. Cap how many books of one kind lead the row so it
        // feels like a bookshop table: a bit of everything.
        func family(_ book: Book) -> String {
            let g = book.genres.first ?? "other"
            switch g {
            case "self-help", "business", "psychology", "philosophy", "politics", "religion": return "ideas"
            case "history", "biography", "memoir", "science", "nature", "travel", "essays", "food", "art": return "nonfiction"
            default: return g
            }
        }
        let limits = ["ideas": 3, "nonfiction": 4]
        var perFamily: [String: Int] = [:]
        let loved = index.pool.filter { book in
            let key = family(book)
            perFamily[key, default: 0] += 1
            return perFamily[key, default: 0] <= (limits[key] ?? 4)
        }
        return Draft(id: "loved", title: "Loved by readers", subtitle: "The most-shelved books in the catalog", kind: .personal, candidates: loved, ordered: true)
    }

    // MARK: Moods (the cozy heart of it)

    private struct Mood {
        var id: String, title: String, subtitle: String
        var weights: [String: Double]
        var avoid: Set<String> = []
        var minimum: Double
    }

    private static let moods: [Mood] = [
        Mood(id: "cozy", title: "Cozy corners", subtitle: "Tea, cats, small towns and kind people",
             weights: ["t:cozy": 3, "t:tea & cafes": 2, "t:small town life": 1, "t:food & cooking": 1.2, "t:books about books": 1.5, "t:cats": 1.2, "t:gardens & nature": 1,
                       "t:feel-good": 2, "t:seaside & islands": 1, "t:crafts & making": 1.2, "t:found family": 1.5, "t:christmas": 0.6, "t:friendship": 0.6, "t:humor": 0.4],
             avoid: ["t:horror", "t:dark & gritty", "t:war", "t:world war ii", "g:horror", "t:abuse & healing"], minimum: 2.0),
        Mood(id: "cozy-mystery", title: "Cozy mysteries", subtitle: "Murder, but make it gentle",
             weights: ["g:mystery": 2, "t:cozy": 3, "t:detectives": 1, "t:small town life": 1.2, "t:england": 0.6, "t:tea & cafes": 1.5, "t:cats": 1, "t:food & cooking": 1, "t:books about books": 1],
             avoid: ["t:dark & gritty", "g:horror", "t:psychological suspense", "t:abuse & healing"], minimum: 3.2),
        Mood(id: "rainy", title: "Rainy-day reads", subtitle: "Fog on the glass, kettle on",
             weights: ["t:rainy days": 3, "t:gothic": 1.5, "g:mystery": 1, "t:england": 0.8, "t:scotland & ireland": 0.8, "g:literary": 0.6, "t:letters & diaries": 1, "t:ghosts": 0.8, "t:detectives": 0.8],
             minimum: 2.0),
        Mood(id: "feel-good", title: "Feel-good", subtitle: "Warm, hopeful and kind",
             weights: ["t:feel-good": 3, "t:humor": 1.5, "t:friendship": 1, "t:found family": 1.5, "t:love stories": 0.6, "t:second chances": 1, "t:small town life": 1, "t:cozy": 2],
             avoid: ["t:dark & gritty", "t:horror", "t:war", "t:abuse & healing", "g:horror"], minimum: 2.2),
        Mood(id: "old-friends", title: "Old friends", subtitle: "Classics that feel like a warm coat",
             weights: ["g:classics": 2, "g:children": 1, "t:small town life": 1, "t:england": 0.8, "t:friendship": 0.8, "t:family life": 0.8, "t:coming of age": 0.6],
             avoid: ["t:dark & gritty", "g:horror", "t:war"], minimum: 2.5),
        Mood(id: "page-turners", title: "Can’t put it down", subtitle: "One more chapter, then sleep",
             weights: ["g:thriller": 2, "t:psychological suspense": 1.5, "t:crime": 1, "t:murder": 1, "t:missing persons": 1.5, "t:secrets": 1, "t:spies": 1.2, "t:heists & cons": 1.2], minimum: 2.5),
        Mood(id: "big-feelings", title: "Big feelings", subtitle: "Keep a tissue nearby",
             weights: ["t:grief & loss": 2, "t:love stories": 1, "t:family life": 1, "t:mothers & daughters": 1, "t:fathers & sons": 1, "t:coming of age": 0.8, "t:identity & self-discovery": 1,
                       "t:mental health": 1, "t:second chances": 1, "g:literary": 0.6], minimum: 2.2),
        Mood(id: "escape", title: "Escape somewhere else", subtitle: "Other worlds, other centuries",
             weights: ["g:fantasy": 1.5, "g:science-fiction": 1.2, "t:fantasy worlds": 1.5, "t:space & aliens": 1, "t:magic": 1, "t:dragons": 1, "t:time travel": 1, "t:historical europe": 0.8,
                       "t:ancient world": 0.8, "t:pirates & the sea": 0.8], minimum: 2.2),
        Mood(id: "slow", title: "Slow and lyrical", subtitle: "Sentences to savour",
             weights: ["g:literary": 2, "g:poetry": 2, "t:gardens & nature": 1, "t:seaside & islands": 1, "t:magical realism": 1.5, "t:letters & diaries": 1, "g:essays": 1, "g:nature": 1, "t:small town life": 0.5],
             avoid: ["g:thriller", "t:crime"], minimum: 2.2),
        Mood(id: "spooky", title: "Spooky season", subtitle: "Best with a blanket and the lights on",
             weights: ["g:horror": 2, "t:ghosts": 2, "t:gothic": 2, "t:vampires": 2, "t:witches": 1.5, "t:monsters": 1.5, "t:halloween & autumn": 2], minimum: 2.0),
        Mood(id: "laugh", title: "Laugh out loud", subtitle: "Funny, sharp and never mean",
             weights: ["t:humor": 3, "g:humor": 3], minimum: 2.5),
        Mood(id: "brain-food", title: "Brain food", subtitle: "Ideas to chew on over tea",
             weights: ["t:philosophy & ideas": 1.5, "t:science & discovery": 1.5, "t:mind & brain": 1.5, "t:technology & society": 1, "g:science": 1.2, "g:philosophy": 1.2, "g:psychology": 1, "g:history": 0.8, "t:language & words": 1],
             minimum: 2.2),
        Mood(id: "fresh-start", title: "A fresh start", subtitle: "Habits, mindset and small changes",
             weights: ["t:habits & mindset": 2.5, "t:mindfulness & meaning": 1.5, "g:self-help": 2, "t:leadership & work": 1, "t:health & body": 0.8], minimum: 2.0),
    ]

    private func moodDrafts(index: PoolIndex) -> [Draft] {
        Self.moods.map { mood in
            Draft(id: "mood-" + mood.id, title: mood.title, subtitle: mood.subtitle, kind: .browse, candidates: weightedMatches(index: index, weights: mood.weights, avoid: mood.avoid, minimum: mood.minimum))
        }
    }

    /// Books whose features add up to at least `minimum`, best match first (popularity breaks near-ties).
    private func weightedMatches(index: PoolIndex, weights: [String: Double], avoid: Set<String> = [], minimum: Double, extra: ((Int) -> Double)? = nil) -> [Book] {
        var scored: [(Int, Double)] = []
        for i in index.pool.indices {
            let keys = index.keys[i]
            if !avoid.isEmpty, !keys.isDisjoint(with: avoid) { continue }
            var total = 0.0
            for key in keys { total += weights[key] ?? 0 }
            if let extra { total += extra(i) }
            if total >= minimum { scored.append((i, total * (0.7 + 0.3 * index.percentile[i]))) }
        }
        scored.sort { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
        return scored.map { index.pool[$0.0] }
    }

    // MARK: Context (season, hour, holidays)

    private func contextDrafts(index: PoolIndex) -> [Draft] {
        let month = calendar.component(.month, from: now)
        let hour = calendar.component(.hour, from: now)
        var drafts: [Draft] = []

        func add(_ id: String, _ title: String, _ subtitle: String, weights: [String: Double], avoid: Set<String> = [], minimum: Double, extra: ((Int) -> Double)? = nil) {
            let matches = weightedMatches(index: index, weights: weights, avoid: avoid, minimum: minimum, extra: extra)
            drafts.append(Draft(id: "context-" + id, title: title, subtitle: subtitle, kind: .context, candidates: matches))
        }

        switch month {
        case 12:
            add("christmas", "Christmas by the fire", "Lights, snow and something warm to drink", weights: ["t:christmas": 3, "t:winter": 1.5, "t:feel-good": 1, "t:found family": 1, "t:cozy": 1.5], minimum: 2.5)
        case 1:
            add("new-year", "A fresh start", "New year, small habits", weights: ["t:habits & mindset": 2.5, "t:mindfulness & meaning": 1.5, "g:self-help": 2, "t:leadership & work": 1], minimum: 2.0)
        case 2:
            add("valentine", "For a February heart", "Love stories, slow burns and second chances", weights: ["t:love stories": 2, "t:enemies to lovers": 2, "t:second chances": 1.5, "g:romance": 1.5], minimum: 2.5)
        case 10:
            add("autumn-spooky", "Spooky season", "Candles, fog and one chapter too many", weights: ["g:horror": 2, "t:ghosts": 2, "t:gothic": 2, "t:vampires": 1.5, "t:witches": 1.5, "t:halloween & autumn": 2], minimum: 2.0)
        default: break
        }

        switch month {
        case 12, 1, 2:
            add("winter", "Winter nights", "Blankets, snow and long evenings", weights: ["t:winter": 2, "t:cozy": 2, "t:small town life": 1, "t:fantasy epics": 1, "t:christmas": 1, "t:feel-good": 1], minimum: 2.0)
        case 3, 4, 5:
            add("spring", "Spring awakenings", "New beginnings and open windows", weights: ["t:gardens & nature": 1.5, "t:coming of age": 1, "t:love stories": 0.8, "t:second chances": 1, "t:feel-good": 1, "t:seaside & islands": 0.6], minimum: 1.8)
        case 6, 7, 8:
            add("summer", "Summer porch reads", "Long light and something cold to drink", weights: ["t:summer": 2, "t:seaside & islands": 2, "t:travel & places": 1, "t:road trips": 1.5, "t:adventure": 0.6, "t:love stories": 0.6], minimum: 1.8)
        default:
            add("autumn", "Crisp-weather reads", "Leaves turning, kettle on", weights: ["t:halloween & autumn": 2.5, "t:gothic": 1.5, "g:mystery": 1, "t:ghosts": 1, "t:small town life": 0.8, "t:england": 0.5, "t:cozy": 2], minimum: 2.0)
        }

        switch hour {
        case 22..<24, 0..<5:
            add("small-hours", "For the small hours", "Short, strange or soothing", weights: ["g:poetry": 2, "g:short-stories": 2, "g:horror": 1, "t:ghosts": 1, "t:magical realism": 1, "t:cozy": 1], minimum: 1.0,
                extra: { index.hours[$0] <= 4 ? 1.0 : 0 })
        case 5..<11:
            add("morning", "With your morning cup", "Short, bright and easy to begin", weights: ["g:essays": 1.5, "g:humor": 1.5, "t:humor": 1.5, "g:short-stories": 1.5, "t:feel-good": 1.5, "g:self-help": 1], minimum: 1.5,
                extra: { index.hours[$0] <= 5 ? 1.0 : 0 })
        case 11..<17:
            add("tea-time", "Tea o’clock", "A pot, a biscuit and a good book", weights: ["t:tea & cafes": 3, "t:cozy": 2, "t:food & cooking": 1.5, "t:england": 0.8, "g:mystery": 1], minimum: 2.0)
        default:
            add("tonight", "For tonight", "A good book that fits one evening", weights: ["g:literary": 0.8, "g:classics": 0.8, "g:historical": 0.6, "t:feel-good": 1, "t:love stories": 0.6, "g:mystery": 0.8], minimum: 0.8,
                extra: { index.hours[$0] <= 4 && index.percentile[$0] >= 0.5 ? 1.2 : 0 })
        }
        return drafts
    }

    // MARK: Genres

    private static let genres: [(tag: String, title: String, subtitle: String)] = [
        ("fantasy", "Other worlds", "Magic, quests and long winter evenings"),
        ("science-fiction", "Beyond the stars", "Futures, aliens and big ideas"),
        ("mystery", "Whodunits", "Clues, red herrings and a cup of tea"),
        ("thriller", "Fast and tense", "Thrillers for one more chapter"),
        ("romance", "Love stories", "Slow burns and happy endings"),
        ("historical", "Step into the past", "Other centuries, other lives"),
        ("horror", "After dark", "Best read with the lights on"),
        ("young-adult", "Young adult favourites", "Big feelings, fast pages"),
        ("children", "Childhood classics", "Read aloud, read again"),
        ("classics", "Still worth the hype", "The books everyone mentions"),
        ("literary", "Literary fiction", "Sentences worth slowing down for"),
        ("poetry", "Poetry for slow evenings", "A few lines at a time"),
        ("drama", "On the stage", "Plays to read aloud"),
        ("short-stories", "Short stories", "One sitting at a time"),
        ("graphic", "Graphic novels", "Pictures doing half the work"),
        ("biography", "Lives well told", "Biographies"),
        ("memoir", "In their own words", "Memoirs"),
        ("history", "How we got here", "History for curious people"),
        ("science", "How the world works", "Science you can follow"),
        ("philosophy", "Big questions", "Philosophy"),
        ("psychology", "Inside the mind", "Psychology"),
        ("self-help", "Small habits, big changes", "Self-help that helps"),
        ("business", "Work and money", "Business books worth the time"),
        ("politics", "Power and people", "Politics"),
        ("religion", "Faith and meaning", "Religion and spirituality"),
        ("nature", "Out in the wild", "Nature writing"),
        ("travel", "Armchair travel", "Journeys without leaving the sofa"),
        ("essays", "Thinking out loud", "Essays"),
        ("humor", "Funny books", "Humor"),
        ("food", "For the kitchen table", "Food writing"),
        ("art", "On art and making", "Art"),
    ]

    private func genreDrafts(index: PoolIndex, recommender: Recommender?) -> [Draft] {
        var drafts = Self.genres.map { genre in
            Draft(id: "genre-" + genre.tag, title: genre.title, subtitle: genre.subtitle, kind: .browse, candidates: index.books(with: "g:" + genre.tag))
        }
        drafts = byAffinity(drafts, key: { "g:" + $0.id.dropFirst(6) }, recommender: recommender)
        return drafts
    }

    // MARK: Themes

    private static let themeRows: [(theme: String, title: String, subtitle: String)] = [
        ("dragons", "Here be dragons", "Scales, fire and old magic"),
        ("witches", "Witches", "Brooms optional"),
        ("magic", "Spells and sorcery", "Wands, wizards and wonder"),
        ("mythology", "Myths retold", "Gods, heroes and old stories"),
        ("fairy tales & folklore", "Once upon a time", "Fairy tales, folklore and retellings"),
        ("knights & castles", "Knights and castles", "Swords, vows and stone walls"),
        ("royalty & courts", "Crowns and courts", "Intrigue in fine rooms"),
        ("ghosts", "Ghost stories", "Things that go bump"),
        ("vampires", "Vampires", "Old, elegant and hungry"),
        ("gothic", "Gothic", "Moors, manors and brooding"),
        ("detectives", "Detectives at work", "Magnifying glasses required"),
        ("murder", "A little murder", "Cosy or cold, it’s all in the clues"),
        ("spies", "Spies and secrets", "Trust no one"),
        ("heists & cons", "Heists and cons", "Elaborate plans, clever crooks"),
        ("missing persons", "Gone without a trace", "Where did they go?"),
        ("psychological suspense", "Messing with your head", "Unreliable narrators and twists"),
        ("space & aliens", "Out among the stars", "Spaceships, first contact and strange planets"),
        ("time travel", "Time travelers", "Then, now and what if"),
        ("dystopia", "After the end", "Dystopias and the day after"),
        ("robots & ai", "Robots and minds", "Machines that think"),
        ("found family", "Found family", "The people you choose"),
        ("friendship", "Friends for life", "Loyalty, loud and quiet"),
        ("coming of age", "Growing up", "The year everything changed"),
        ("school life", "Back to school", "Classrooms, campuses and boarding houses"),
        ("siblings", "Brothers and sisters", "Family you didn’t pick"),
        ("mothers & daughters", "Mothers and daughters", "Complicated, close"),
        ("marriage", "Marriage", "Vows, ruts and reinventions"),
        ("enemies to lovers", "Enemies to lovers", "Sparks, snark and slow turns"),
        ("second chances", "Second chances", "Another try at love, life or both"),
        ("grief & loss", "For a hard season", "Books that sit with grief"),
        ("mental health", "Minds and moods", "Honest books about mental health"),
        ("identity & self-discovery", "Finding yourself", "Who you are and who you’ll be"),
        ("small town life", "Small-town stories", "Everyone knows everyone"),
        ("seaside & islands", "By the sea", "Salt, gulls and grey light"),
        ("gardens & nature", "In the garden", "Growing things and slow days"),
        ("food & cooking", "A taste of it", "Kitchens, recipes and long tables"),
        ("tea & cafes", "Tea and cafes", "Steam on the glass"),
        ("books about books", "For people who love books", "Libraries, bookshops and readers"),
        ("letters & diaries", "Letters and diaries", "Other people’s private pages"),
        ("cats", "Cat people", "Whiskers and warm laps"),
        ("dogs", "Good dogs", "Loyal friends"),
        ("animals", "Animal friends", "Creatures great and small"),
        ("christmas", "Christmas by the fire", "Lights, snow and something warm"),
        ("halloween & autumn", "Autumn and Halloween", "Crisp air and candlelight"),
        ("winter", "Winter nights", "Long dark evenings"),
        ("summer", "Long summer days", "Porches, beaches and slow afternoons"),
        ("rainy days", "Rain on the window", "Best with a blanket"),
        ("travel & places", "Armchair journeys", "Somewhere else, from the sofa"),
        ("england", "Set in England", "Villages, rain and tea"),
        ("london", "London stories", "The city in all its moods"),
        ("scotland & ireland", "Scotland and Ireland", "Hills, lochs and lyrical talk"),
        ("france & paris", "France and Paris", "Cafes, countryside and café noir"),
        ("italy", "Italy", "Sun, stone and long lunches"),
        ("japan", "Japan", "Quiet, precise, strange"),
        ("american south", "The American South", "Porches and secrets"),
        ("new york", "New York stories", "Eight million of them"),
        ("world war ii", "World War II", "Courage, loss and resistance"),
        ("ancient world", "The ancient world", "Rome, Greece, Egypt and beyond"),
        ("pirates & the sea", "Out to sea", "Ships, storms and the horizon"),
        ("westerns", "Frontier tales", "Dust, horses and big sky"),
        ("war", "Soldiers and wars", "Courage under fire"),
        ("class & society", "Class and society", "Money, manners and who gets in"),
        ("politics & power", "Power and politics", "Who rules and why"),
        ("immigration", "Coming to a new country", "Leaving, arriving and belonging"),
        ("slavery", "Reckoning with history", "Slavery and its long shadow"),
        ("true crime", "True crime", "Real cases, carefully told"),
        ("humor", "Funny books", "Wit, satire and silliness"),
        ("games & puzzles", "Games and puzzles", "Chess, riddles and clever contests"),
        ("art & music", "Art and music", "Studios, stages and strings"),
        ("sports", "Sports stories", "Training, rivals and the big game"),
        ("crafts & making", "Made by hand", "Knitting, baking and making things"),
        ("habits & mindset", "Better habits", "Small changes that stick"),
        ("mindfulness & meaning", "Slow down", "Calm, meaning and meditation"),
        ("business & money", "Money matters", "Business, markets and getting by"),
        ("leadership & work", "Work and leadership", "Careers, teams and getting things done"),
        ("health & body", "Body and health", "Fitness, sleep and feeling well"),
        ("mind & brain", "How minds work", "Brains, memory and behavior"),
        ("philosophy & ideas", "Big ideas", "Think about it"),
        ("science & discovery", "Science and discovery", "How we found out"),
        ("technology & society", "Tech and society", "Machines, networks and us"),
        ("nature & environment", "Nature and the planet", "Wild places and what we do to them"),
    ]

    private func themeDrafts(index: PoolIndex, recommender: Recommender?) -> [Draft] {
        let drafts = Self.themeRows.map { row in
            Draft(id: "theme-" + row.theme, title: row.title, subtitle: row.subtitle, kind: .browse, candidates: index.books(with: "t:" + row.theme))
        }
        return byAffinity(drafts, key: { "t:" + $0.id.dropFirst(6) }, recommender: recommender)
    }

    /// Rows the reader's taste leans toward come first; unknown taste keeps the given order.
    private func byAffinity(_ drafts: [Draft], key: (Draft) -> String, recommender: Recommender?) -> [Draft] {
        guard let weights = recommender?.profile.positive.weights, !weights.isEmpty else { return drafts }
        return drafts.enumerated().sorted { a, b in
            let wa = weights[key(a.element)] ?? 0, wb = weights[key(b.element)] ?? 0
            return wa != wb ? wa > wb : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Time

    private func timeDrafts(index: PoolIndex) -> [Draft] {
        let minutes = Double(max(dailyMinutes, 5))
        func days(_ i: Int) -> Double { index.hours[i] * 60 / minutes }
        func row(_ id: String, _ title: String, _ subtitle: String, _ test: @escaping (Int) -> Bool) -> Draft {
            let matches = index.pool.indices.filter { test($0) && index.pool[$0].pages >= 60 }
            return Draft(id: "time-" + id, title: title, subtitle: subtitle, kind: .browse, candidates: matches.map { index.pool[$0] })
        }
        let pace = "At \(dailyMinutes) minutes a day"
        return [
            row("evening", "Done in an evening", "Under three hours at your pace") { index.hours[$0] <= 3 },
            row("week", "Finish in a week", pace) { days($0) <= 7 && index.hours[$0] > 3 },
            row("fortnight", "About two weeks", pace) { days($0) > 7 && days($0) <= 14 },
            row("month", "A month’s companion", pace) { days($0) > 14 && days($0) <= 35 },
            row("epic", "Settle in for the season", "Big books for long evenings") { days($0) > 35 },
        ]
    }

    // MARK: Series, authors, decades, gems

    private func seriesDrafts(index: PoolIndex) -> [Draft] {
        var drafts: [Draft] = []
        for key in index.byKey.keys.sorted() where key.hasPrefix("s:") {
            let books = index.books(with: key)
            guard books.count >= 4 else { continue }
            let name = displayName(String(key.dropFirst(2)))
            drafts.append(Draft(id: "series-" + key, title: "The world of \(name)", subtitle: "\(books.count) books to start anywhere", kind: .browse, candidates: books))
        }
        return drafts.sorted { $0.candidates.count > $1.candidates.count || ($0.candidates.count == $1.candidates.count && $0.id < $1.id) }
    }

    private func authorDrafts(index: PoolIndex) -> [Draft] {
        var byAuthor: [String: [Book]] = [:]
        for book in index.pool { byAuthor[TasteProfile.normalizeAuthor(book.author), default: []].append(book) }
        let eligible = byAuthor.filter { $0.value.count >= 5 && $0.key != "various" && $0.key != "unknown author" }
        let ranked = eligible.sorted { a, b in
            let pa = a.value.reduce(0) { $0 + $1.popularity }, pb = b.value.reduce(0) { $0 + $1.popularity }
            return pa != pb ? pa > pb : a.key < b.key
        }
        return ranked.prefix(120).map { key, books in
            Draft(id: "author-" + key, title: books[0].author, subtitle: "\(books.count) books. Start anywhere.", kind: .browse, candidates: books)
        }
    }

    private func decadeDrafts(index: PoolIndex) -> [Draft] {
        var byDecade: [Int: [Book]] = [:]
        for book in index.pool {
            guard let year = book.year else { continue }
            byDecade[year < 1900 ? 1800 : year / 10 * 10, default: []].append(book)
        }
        return byDecade.keys.sorted(by: >).compactMap { decade in
            guard let books = byDecade[decade], books.count >= 20 else { return nil }
            if decade == 1800 { return Draft(id: "decade-pre1900", title: "Before 1900", subtitle: "Old friends that have lasted", kind: .browse, candidates: books) }
            return Draft(id: "decade-\(decade)", title: "The \(decade)s", subtitle: "Books from \(decade) to \(decade + 9)", kind: .browse, candidates: books)
        }
    }

    private func hiddenGemDrafts(index: PoolIndex) -> [Draft] {
        func gems(_ genre: String?) -> [Book] {
            index.pool.indices.filter { i in
                let p = index.percentile[i]
                guard p >= 0.25, p <= 0.65, index.pool[i].pages >= 120, index.pool[i].pages <= 520 else { return false }
                return genre.map { index.keys[i].contains("g:" + $0) } ?? true
            }.map { index.pool[$0] }
        }
        var drafts = [Draft(id: "gems", title: "Hidden gems", subtitle: "Loved by readers, missing from most shelves", kind: .browse, candidates: gems(nil))]
        for genre in ["fantasy", "science-fiction", "mystery", "romance", "historical", "literary", "thriller", "classics", "biography", "history"] {
            drafts.append(Draft(id: "gems-" + genre, title: "Hidden gems in \(Genre.name(genre))", subtitle: "Lesser-known, well loved", kind: .browse, candidates: gems(genre)))
        }
        return drafts
    }

    private func genreLengthDrafts(index: PoolIndex) -> [Draft] {
        var drafts: [Draft] = []
        for genre in ["fantasy", "science-fiction", "mystery", "thriller", "romance", "historical", "horror", "classics", "literary", "biography", "history", "self-help"] {
            let all = index.byKey["g:" + genre] ?? []
            let name = Genre.name(genre)
            let quick = all.filter { index.hours[$0] <= 6 && index.pool[$0].pages >= 60 }.map { index.pool[$0] }
            let big = all.filter { index.hours[$0] >= 14 }.map { index.pool[$0] }
            drafts.append(Draft(id: "quick-" + genre, title: "Quick \(name)", subtitle: "Under six hours at your pace", kind: .browse, candidates: quick))
            drafts.append(Draft(id: "big-" + genre, title: "Big \(name)", subtitle: "Settle in for a long one", kind: .browse, candidates: big))
        }
        return drafts
    }

    // MARK: Composing

    private func compose(_ drafts: [Draft], pool: [Book], seed: UInt64) -> [BookCollection] {
        var rng = SeededGenerator(seed: seed ^ 0x51ED)
        var exposure: [String: Int] = [:]
        var rows: [BookCollection] = []
        var rowIDSets: [Set<String>] = []

        for draft in drafts {
            if rows.count >= maxRows { break }
            guard draft.candidates.count >= minimumBooks else { continue }
            let picked = draft.ordered ? Array(draft.candidates.prefix(rowSize)) : pick(draft.candidates, exposure: exposure, rng: &rng)
            guard picked.count >= minimumBooks else { continue }

            let ids = Set(picked.map(\.id))
            // Skip a row that mostly repeats one already shown (two series sharing characters, say).
            if rowIDSets.contains(where: { overlap($0, ids) > 0.6 }) { continue }

            for book in picked { exposure[book.id, default: 0] += 1 }
            rowIDSets.append(ids)
            let reasons = draft.reasons.filter { ids.contains($0.key) }
            rows.append(BookCollection(id: draft.id, title: draft.title, subtitle: draft.subtitle, books: picked, kind: draft.kind, reasons: reasons))
        }
        return rows
    }

    /// Mostly the best books, a few deeper cuts, avoiding books the screen has already shown too often.
    private func pick(_ candidates: [Book], exposure: [String: Int], rng: inout SeededGenerator) -> [Book] {
        let fresh = candidates.filter { exposure[$0.id, default: 0] < maxExposure }
        let headCount = rowSize * 2 / 3
        var result = Array(fresh.prefix(headCount))
        let used = Set(result.map(\.id))
        var deeper = Array(fresh.dropFirst(headCount).filter { !used.contains($0.id) }.prefix(rowSize * 6))
        for i in stride(from: deeper.count - 1, to: 0, by: -1) { deeper.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        result += deeper.prefix(rowSize - result.count)
        if result.count < rowSize {
            // Short on fresh books: top up with anything, so a small row isn't thrown away.
            let have = Set(result.map(\.id))
            result += candidates.filter { !have.contains($0.id) }.prefix(rowSize - result.count)
        }
        return result
    }

    private func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        let smaller = min(a.count, b.count)
        guard smaller > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(smaller)
    }

    // MARK: Utilities

    private func displayName(_ raw: String) -> String {
        raw.split(separator: " ").map { word in
            guard let first = word.first else { return String(word) }
            return String(first).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private func shuffled(_ drafts: [Draft], rng: inout SeededGenerator, keepFirst: Int) -> [Draft] {
        guard drafts.count > keepFirst + 1 else { return drafts }
        var tail = Array(drafts.dropFirst(keepFirst))
        for i in stride(from: tail.count - 1, to: 0, by: -1) { tail.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        return Array(drafts.prefix(keepFirst)) + tail
    }

    /// Takes rows from the categories in a repeating pattern so neighbours feel different, then appends the rest.
    private func interleave(_ categories: [[Draft]], pattern: [Int]) -> [Draft] {
        var cursors = Array(repeating: 0, count: categories.count)
        var out: [Draft] = []
        var progress = true
        while progress {
            progress = false
            for c in pattern where c < categories.count && cursors[c] < categories[c].count {
                out.append(categories[c][cursors[c]]); cursors[c] += 1; progress = true
            }
        }
        for c in categories.indices { out += categories[c].dropFirst(cursors[c]) }
        return out
    }
}
