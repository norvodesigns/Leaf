import Foundation

/// Suggests teas for a book from what it is (genres and themes), how long it is and when it was written, with one
/// line in the app's voice saying why. Pure and deterministic: the same book and teas always give the same picks.
///
/// Each rule that fits the book adds weight to a few teas; a tea's score is the sum. The reason shown for a tea is
/// the line of the rule that gave it the most weight, written for that tea's family where the rule says so. Teas
/// no rule mentions can still be picked (from a reader's own cabinet, say) through a gentle fit by family, so a
/// pairing always comes out.
enum TeaPairing {
    struct Pick: Hashable, Sendable {
        var tea: Tea
        var score: Double
        var reason: String
    }

    /// Teas for a book, best first. `teas` is the catalog unless the reader's cabinet is asked.
    static func picks(for book: Book, from teas: [Tea] = TeaCatalog.all, limit: Int = 3) -> [Pick] {
        guard !teas.isEmpty, limit > 0 else { return [] }
        let matched = rules.filter { $0.matches(book) }
        var scored: [Pick] = teas.map { tea in
            var total = 0.0
            var best: (weight: Double, reason: String)?
            for rule in matched {
                let weight = rule.weight(for: tea)
                guard weight > 0 else { continue }
                total += weight
                if weight > (best?.weight ?? 0) {
                    best = (weight, rule.reason(for: tea))
                }
            }
            if let best {
                return Pick(tea: tea, score: total, reason: best.reason)
            }
            // No rule speaks for this tea: a small score by family, so a cabinet of unlisted teas still pairs.
            return Pick(tea: tea, score: fallbackWeight(tea), reason: fallbackReason(tea))
        }
        scored.sort { $0.score > $1.score || ($0.score == $1.score && $0.tea.id < $1.tea.id) }
        return Array(scored.prefix(limit))
    }

    /// The single best tea for a book.
    static func best(for book: Book, from teas: [Tea] = TeaCatalog.all) -> Pick? {
        picks(for: book, from: teas, limit: 1).first
    }

    /// The line for a tea the reader pinned themselves, which may not be the engine's favourite.
    static func reason(for tea: Tea, with book: Book) -> String {
        picks(for: book, from: [tea], limit: 1).first?.reason ?? fallbackReason(tea)
    }

    // MARK: Rules

    struct Rule: Sendable {
        var genres: Set<String> = []
        var themes: Set<String> = []
        /// Every one of these must be present too (a cozy mystery is a mystery and cozy).
        var alsoThemes: Set<String> = []
        var minPages: Int?
        var maxPages: Int?
        var before: Int?
        /// Weight per tea id.
        var teas: [String: Double] = [:]
        /// Weight per family, for teas the rule doesn't name (a reader's own oolong for a long classic).
        var families: [TeaFamily: Double] = [:]
        var line: String
        /// A better line for a particular family.
        var lines: [TeaFamily: String] = [:]

        func matches(_ book: Book) -> Bool {
            let bookGenres = Set(book.genres)
            let bookThemes = Set(book.themes ?? [])
            if !genres.isEmpty || !themes.isEmpty {
                guard !genres.isDisjoint(with: bookGenres) || !themes.isDisjoint(with: bookThemes) else { return false }
            }
            if !alsoThemes.isEmpty, alsoThemes.isDisjoint(with: bookThemes) { return false }
            if let minPages, book.pages < minPages { return false }
            if let maxPages, book.pages > maxPages || book.pages <= 0 { return false }
            if let before {
                guard let year = book.year, year < before else { return false }
            }
            return true
        }

        func weight(for tea: Tea) -> Double {
            teas[tea.id] ?? families[tea.family] ?? 0
        }

        func reason(for tea: Tea) -> String {
            lines[tea.family] ?? line
        }
    }

    static let rules: [Rule] = [
        Rule(
            genres: ["mystery"], alsoThemes: ["cozy", "tea & cafes", "small town life", "cats"],
            teas: ["english-breakfast": 4, "earl-grey": 3, "roasted-oolong": 1.5],
            families: [.black: 2.5],
            line: "A malty black tea for a cozy mystery: strong enough to see you through the clues."
        ),
        Rule(
            genres: ["mystery"], themes: ["detectives", "crime", "murder"],
            teas: ["earl-grey": 2.5, "english-breakfast": 2, "lapsang-souchong": 1],
            families: [.black: 1.5],
            line: "A brisk black tea for a mystery, to keep your wits about you."
        ),
        Rule(
            genres: ["thriller"], themes: ["psychological suspense", "spies", "heists"],
            teas: ["matcha": 2.5, "sencha": 2, "english-breakfast": 1.5],
            families: [.green: 1.5, .matcha: 2.5],
            line: "Something bright and green for a thriller: a steady hand for the twists.",
            lines: [.black: "A brisk black tea for a thriller: one more chapter, one more cup."]
        ),
        Rule(
            genres: ["classics"], minPages: 400,
            teas: ["milk-oolong": 4, "roasted-oolong": 4, "darjeeling": 1.5],
            families: [.oolong: 3.5],
            line: "A long classic and a pot of oolong: both open up over many cups.",
            lines: [.black: "A long classic wants a patient tea; Darjeeling keeps its grace cup after cup."]
        ),
        Rule(
            genres: ["classics"],
            teas: ["darjeeling": 2.5, "earl-grey": 2, "milk-oolong": 1],
            families: [.black: 1.5],
            line: "An old favourite for an old favourite: a black tea the classics would know.",
            lines: [.oolong: "A gentle oolong for a classic: it rewards the slow reader."]
        ),
        Rule(
            genres: ["poetry"],
            teas: ["jasmine-green": 4.5, "silver-needle": 3.5, "sencha": 2.5],
            families: [.green: 3, .white: 3],
            line: "Poetry wants something delicate: a light green, sipped between poems.",
            lines: [.white: "Poetry wants something delicate: a pale white tea, sipped between poems."]
        ),
        Rule(
            genres: ["fantasy"], themes: ["fantasy worlds", "dragons", "magic", "quests"],
            teas: ["lapsang-souchong": 3, "masala-chai": 2.5, "roasted-oolong": 1.5],
            families: [.chai: 2],
            line: "Smoky Lapsang for a fantasy: campfire tea for a long road.",
            lines: [.chai: "Spiced chai for a fantasy: warmth for the road between chapters.", .oolong: "A roasted oolong for a fantasy: toasty, like an inn at the end of the day."]
        ),
        Rule(
            genres: ["science-fiction"], themes: ["space & aliens", "time travel", "robots & ai"],
            teas: ["matcha": 3, "sencha": 2.5, "genmaicha": 1.5],
            families: [.matcha: 3, .green: 2],
            line: "Bright, grassy green tea for the far future.",
            lines: [.matcha: "Matcha for the far future: bright, green and wide awake."]
        ),
        Rule(
            genres: ["horror"], themes: ["gothic", "ghosts", "haunted houses", "vampires"],
            teas: ["lapsang-souchong": 3, "hojicha": 2.5, "rooibos": 1.5],
            families: [.rooibos: 1.5],
            line: "Something smoky for the dark: a cup to hold while the candles gutter.",
            lines: [.green: "Roasted hojicha for a gothic tale: low, warm and good after dark.", .rooibos: "Rooibos for the dark: no caffeine, so the only thing keeping you up is the book."]
        ),
        Rule(
            genres: ["romance"], themes: ["love stories", "second chances"],
            teas: ["jasmine-green": 3, "hibiscus": 2, "milk-oolong": 1.5],
            families: [.herbal: 1],
            line: "Jasmine for a love story: soft, floral and a little sweet.",
            lines: [.herbal: "Something rosy for a love story: tart, bright and a little sweet.", .oolong: "A creamy oolong for a love story: soft and a little sweet."]
        ),
        Rule(
            genres: ["historical", "history"], themes: ["world war ii", "ancient world", "victorian era", "royalty"],
            teas: ["earl-grey": 3, "darjeeling": 2.5, "lapsang-souchong": 1],
            families: [.black: 2],
            line: "Earl Grey for history: a tea with a past of its own."
        ),
        Rule(
            genres: ["biography", "memoir"],
            teas: ["masala-chai": 2.5, "milk-oolong": 2, "earl-grey": 1],
            families: [.chai: 2.5],
            line: "Chai for a life story: warm, spiced and best shared.",
            lines: [.oolong: "A creamy oolong for a life story: comfortable company for a long conversation."]
        ),
        Rule(
            genres: ["children", "young-adult"],
            teas: ["rooibos": 3, "apple-cinnamon": 2.5, "chamomile": 2],
            families: [.rooibos: 3, .herbal: 2],
            line: "Rooibos for a younger read: sweet, gentle and caffeine free.",
            lines: [.herbal: "A fruity herbal for a younger read: sweet, gentle and caffeine free."]
        ),
        Rule(
            genres: ["nature", "travel"], themes: ["gardens & nature", "journeys", "seaside & islands"],
            teas: ["genmaicha": 2.5, "sencha": 2, "peppermint": 1.5],
            families: [.green: 2],
            line: "Genmaicha for the outdoors: toasty and grassy, like a walk in the woods.",
            lines: [.herbal: "Fresh mint for the outdoors: it tastes of a cool morning."]
        ),
        Rule(
            genres: ["philosophy", "essays", "literary"],
            teas: ["roasted-oolong": 2.5, "hojicha": 2, "darjeeling": 1.5],
            families: [.oolong: 2],
            line: "Roasted oolong for slow thinking: a tea that rewards a second sip."
        ),
        Rule(
            genres: ["self-help", "business", "science", "psychology"],
            teas: ["sencha": 2.5, "matcha": 2, "peppermint": 1.5],
            families: [.green: 2, .matcha: 2],
            line: "Sencha for clear thinking: fresh, green and focusing.",
            lines: [.herbal: "Peppermint for clear thinking: clean, cool and caffeine free.", .matcha: "Matcha for clear thinking: calm focus, one whisk at a time."]
        ),
        Rule(
            themes: ["feel-good", "humor", "friendship", "found family"],
            teas: ["lemon-ginger": 2, "earl-grey": 1, "hibiscus": 1],
            families: [.herbal: 1],
            line: "Lemon ginger for a feel-good book: bright and warming."
        ),
        Rule(
            themes: ["rainy days", "scotland & ireland"],
            teas: ["lapsang-souchong": 1.5, "hojicha": 1.5, "english-breakfast": 1],
            line: "A smoky, toasty cup for a rainy-day book: fog on the glass, kettle on."
        ),
        Rule(
            themes: ["christmas", "winter"],
            teas: ["masala-chai": 2, "apple-cinnamon": 2],
            families: [.chai: 1.5],
            line: "Spiced tea for a winter book: cinnamon, clove and a warm cup in cold hands."
        ),
        Rule(
            themes: ["food & cooking", "tea & cafes"],
            teas: ["milk-oolong": 1.5, "masala-chai": 1.5, "earl-grey": 1],
            line: "Something creamy for a book that loves its food: a cup to go with the recipes."
        ),
        Rule(
            maxPages: 160,
            teas: ["silver-needle": 1.5, "jasmine-green": 1, "peppermint": 1],
            families: [.white: 1.5, .green: 1],
            line: "A short book and a light tea: both done before they go cold."
        ),
        Rule(
            minPages: 600,
            teas: ["milk-oolong": 2, "roasted-oolong": 2, "rooibos": 1.5],
            families: [.oolong: 2, .rooibos: 1.5],
            line: "A long book wants a forgiving tea: oolong gives cup after cup.",
            lines: [.rooibos: "A long book wants a forgiving tea: rooibos never turns bitter, however long it sits."]
        ),
        Rule(
            before: 1900,
            teas: ["darjeeling": 1.5, "earl-grey": 1.5, "lapsang-souchong": 1],
            families: [.black: 1],
            line: "A black tea from the same century as the book: the characters might have drunk it."
        ),
    ]

    // MARK: Fallback

    private static func fallbackWeight(_ tea: Tea) -> Double {
        switch tea.family {
        case .black: return 0.3
        case .oolong, .chai: return 0.25
        case .green, .rooibos: return 0.2
        case .white, .herbal, .matcha: return 0.15
        }
    }

    private static func fallbackReason(_ tea: Tea) -> String {
        switch tea.family {
        case .black: return "A black tea goes with almost any book: steady, warm and there when you look up."
        case .green, .matcha: return "Something green and bright, to keep you good company."
        case .white: return "A pale, gentle tea that never gets in the way of the words."
        case .oolong: return "An oolong that changes cup by cup, like a good book does."
        case .herbal: return "A caffeine-free cup, so you can read as late as the book wants."
        case .rooibos: return "Rooibos: sweet, forgiving and caffeine free."
        case .chai: return "Spiced chai: warmth to hold while you read."
        }
    }
}
