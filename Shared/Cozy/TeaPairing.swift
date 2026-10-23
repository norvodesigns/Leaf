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
        /// Weight per tea id. A tea the rule names never weighs less than its family does here.
        var teas: [String: Double] = [:]
        /// Weight per family, for teas the rule doesn't name (a reader's own oolong for a long classic).
        var families: [TeaFamily: Double] = [:]
        /// The line for any tea this rule weighs: it names no particular tea, only a family the rule gives weight to.
        var line: String
        /// A better line for a particular family.
        var lines: [TeaFamily: String] = [:]
        /// A line for one tea by id, the only kind of line that may name a tea.
        var teaLines: [String: String] = [:]

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
            teaLines[tea.id] ?? lines[tea.family] ?? line
        }
    }

    static let rules: [Rule] = [
        Rule(
            genres: ["mystery"], alsoThemes: ["cozy", "tea & cafes", "small town life", "cats"],
            teas: ["english-breakfast": 4, "earl-grey": 3, "roasted-oolong": 1.5],
            families: [.black: 2.5],
            line: "A strong black tea for a cozy mystery: enough to see you through the clues.",
            lines: [.oolong: "A roasted oolong for a cozy mystery: toasty, like the village tearoom."],
            teaLines: [
                "english-breakfast": "A malty black tea for a cozy mystery: strong enough to see you through the clues.",
                "earl-grey": "Earl Grey for a cozy mystery: the vicar’s favourite, and good with a slice of cake.",
            ]
        ),
        Rule(
            genres: ["mystery"], themes: ["detectives", "crime", "murder"],
            teas: ["earl-grey": 2.5, "english-breakfast": 2, "lapsang-souchong": 1.5],
            families: [.black: 1.5],
            line: "A brisk black tea for a mystery, to keep your wits about you.",
            teaLines: ["lapsang-souchong": "Smoky Lapsang for a mystery, like a detective’s pipe in the next room."]
        ),
        Rule(
            genres: ["thriller"], themes: ["psychological suspense", "spies", "heists & cons"],
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
            teaLines: ["darjeeling": "A long classic wants a patient tea; Darjeeling keeps its grace cup after cup."]
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
            teas: ["jasmine-green": 4.5, "silver-needle": 3.5, "sencha": 3, "white-peony": 3, "dragon-well": 2.5],
            families: [.green: 2, .white: 3],
            line: "Poetry wants something delicate: a light green, sipped between poems.",
            lines: [.white: "Poetry wants something delicate: a pale white tea, sipped between poems."],
            teaLines: ["dragon-well": "Dragon Well for poetry: chestnut and spring, sipped between poems."]
        ),
        Rule(
            genres: ["fantasy"], themes: ["fantasy worlds", "dragons", "magic", "quests"],
            teas: ["lapsang-souchong": 3, "masala-chai": 2.5, "roasted-oolong": 1.5],
            families: [.chai: 2],
            line: "Spiced chai for a fantasy: warmth for the road between chapters.",
            lines: [.oolong: "A roasted oolong for a fantasy: toasty, like an inn at the end of the day."],
            teaLines: ["lapsang-souchong": "Smoky Lapsang for a fantasy: campfire tea for a long road."]
        ),
        Rule(
            genres: ["science-fiction"], themes: ["space & aliens", "time travel", "robots & ai"],
            teas: ["matcha": 3, "sencha": 2.5, "genmaicha": 2, "gyokuro": 2],
            families: [.matcha: 3, .green: 1.5],
            line: "Bright green tea for the far future.",
            lines: [.matcha: "Matcha for the far future: bright, green and wide awake."],
            teaLines: [
                "sencha": "Sencha for the far future: bright, grassy and clear-headed.",
                "genmaicha": "Genmaicha for the far future: toasted rice, like rations on a long voyage.",
                "gyokuro": "Gyokuro for the far future: deep green, savoury and wide awake.",
            ]
        ),
        Rule(
            genres: ["horror"], themes: ["gothic", "ghosts", "vampires", "monsters"],
            teas: ["lapsang-souchong": 3, "hojicha": 2.5, "rooibos": 1.5],
            families: [.rooibos: 1.5],
            line: "Rooibos for the dark: no caffeine, so the only thing keeping you up is the book.",
            teaLines: [
                "lapsang-souchong": "Something smoky for the dark: a cup to hold while the candles gutter.",
                "hojicha": "Roasted hojicha for a gothic tale: low, warm and good after dark.",
            ]
        ),
        Rule(
            genres: ["romance"], themes: ["love stories", "second chances", "enemies to lovers"],
            teas: ["jasmine-green": 3, "hibiscus": 2, "lavender": 2, "milk-oolong": 1.5, "oriental-beauty": 1.5],
            families: [.herbal: 1],
            line: "A gentle herbal for a love story: soft, sweet and caffeine free.",
            lines: [.oolong: "A creamy oolong for a love story: soft and a little sweet."],
            teaLines: [
                "jasmine-green": "Jasmine for a love story: soft, floral and a little sweet.",
                "hibiscus": "Hibiscus for a love story: rosy, tart and a little sweet.",
                "lavender": "Lavender for a love story: soft, floral and caffeine free.",
                "oriental-beauty": "Oriental Beauty for a love story: honeyed, fruity and a little sweet.",
            ]
        ),
        Rule(
            genres: ["historical", "history"], themes: ["world war ii", "ancient world", "royalty & courts", "history & the past"],
            teas: ["earl-grey": 3, "darjeeling": 2.5, "lapsang-souchong": 2, "keemun": 2],
            families: [.black: 2],
            line: "A black tea with a past of its own, for a book about the past.",
            teaLines: [
                "earl-grey": "Earl Grey for history: a tea with a past of its own.",
                "darjeeling": "Darjeeling for history: the tea of hill stations and long letters home.",
                "lapsang-souchong": "Smoky Lapsang for history: said to be the first black tea of all.",
                "keemun": "Keemun for history: a black tea the old clipper ships raced home.",
            ]
        ),
        Rule(
            genres: ["biography", "memoir"],
            teas: ["masala-chai": 2.5, "milk-oolong": 2, "earl-grey": 1],
            families: [.chai: 2.5],
            line: "Chai for a life story: warm, spiced and best shared.",
            lines: [
                .oolong: "A creamy oolong for a life story: comfortable company for a long conversation.",
                .black: "A black tea for a life story: steady company through someone else’s years.",
            ]
        ),
        Rule(
            genres: ["children", "young-adult"],
            teas: ["rooibos": 3, "vanilla-rooibos": 3, "apple-cinnamon": 2.5, "chamomile": 2],
            families: [.rooibos: 3, .herbal: 2],
            line: "Rooibos for a younger read: sweet, gentle and caffeine free.",
            lines: [.herbal: "A sweet herbal for a younger read: gentle and caffeine free."],
            teaLines: ["vanilla-rooibos": "Vanilla rooibos for a younger read: sweet as a bedtime story, and caffeine free."]
        ),
        Rule(
            genres: ["nature", "travel"], themes: ["gardens & nature", "travel & places", "road trips", "seaside & islands"],
            teas: ["genmaicha": 2.5, "sencha": 2, "moroccan-mint": 2, "peppermint": 1.5],
            families: [.green: 2],
            line: "Something green for the outdoors: it tastes of a walk in the woods.",
            teaLines: [
                "genmaicha": "Genmaicha for the outdoors: toasty and grassy, like a walk in the woods.",
                "moroccan-mint": "Moroccan tea for the outdoors: sweet, green and poured from up high.",
                "peppermint": "Fresh mint for the outdoors: it tastes of a cool morning.",
            ]
        ),
        Rule(
            genres: ["philosophy", "essays", "literary"],
            teas: ["roasted-oolong": 2.5, "hojicha": 2, "darjeeling": 1.5],
            families: [.oolong: 2],
            line: "An oolong for slow thinking: it changes cup by cup, like a good argument.",
            teaLines: [
                "roasted-oolong": "Roasted oolong for slow thinking: a tea that rewards a second sip.",
                "hojicha": "Roasted hojicha for slow thinking: mellow and gentle on a long evening.",
                "darjeeling": "Darjeeling for slow thinking: light enough to sip between pages.",
            ]
        ),
        Rule(
            genres: ["self-help", "business", "science", "psychology"],
            teas: ["sencha": 2.5, "matcha": 2, "peppermint": 1.5],
            families: [.green: 2, .matcha: 2],
            line: "Something green for clear thinking: fresh and focusing.",
            lines: [.matcha: "Matcha for clear thinking: calm focus, one whisk at a time."],
            teaLines: [
                "sencha": "Sencha for clear thinking: fresh, green and focusing.",
                "peppermint": "Peppermint for clear thinking: clean, cool and caffeine free.",
            ]
        ),
        Rule(
            genres: ["humor"], themes: ["feel-good", "humor", "friendship", "found family"],
            teas: ["lemon-ginger": 2, "earl-grey": 1, "hibiscus": 1, "elderflower": 1],
            families: [.herbal: 1],
            line: "Something bright for a feel-good book: a cup that cheers.",
            teaLines: [
                "lemon-ginger": "Lemon ginger for a feel-good book: bright and warming.",
                "earl-grey": "Earl Grey for a feel-good book: bright with bergamot.",
                "hibiscus": "Hibiscus for a feel-good book: rosy and bright.",
                "elderflower": "Elderflower for a feel-good book: light, floral and bright.",
            ]
        ),
        Rule(
            themes: ["rainy days", "scotland & ireland"],
            teas: ["lapsang-souchong": 1.5, "hojicha": 1.5, "english-breakfast": 1, "golden-turmeric": 1],
            line: "A smoky, toasty cup for a rainy-day book: fog on the glass, kettle on.",
            teaLines: [
                "english-breakfast": "A strong cup for a rainy-day book: fog on the glass, kettle on.",
                "golden-turmeric": "Golden turmeric for a rainy-day book: warm hands while the windows stream.",
            ]
        ),
        Rule(
            themes: ["christmas", "winter"],
            teas: ["masala-chai": 2, "apple-cinnamon": 2, "rooibos-chai": 1.5],
            families: [.chai: 1.5],
            line: "Spiced tea for a winter book: cinnamon, clove and a warm cup in cold hands."
        ),
        Rule(
            genres: ["food"], themes: ["food & cooking", "tea & cafes"],
            teas: ["milk-oolong": 1.5, "masala-chai": 1.5, "pumpkin-spice-chai": 1.5, "earl-grey": 1],
            line: "Something creamy for a book that loves its food: a cup to go with the recipes.",
            teaLines: [
                "earl-grey": "Earl Grey for a book that loves its food: made for a slice of cake.",
                "pumpkin-spice-chai": "Pumpkin spice chai for a book that loves its food: it smells like the bakery.",
            ]
        ),
        Rule(
            maxPages: 160,
            teas: ["silver-needle": 1.5, "white-peony": 1.5, "jasmine-green": 1, "peppermint": 1],
            families: [.white: 1.5, .green: 1],
            line: "A short book and a light tea: both done before they go cold."
        ),
        Rule(
            minPages: 600,
            teas: ["milk-oolong": 2, "roasted-oolong": 2, "rooibos": 1.5, "vanilla-rooibos": 1.5],
            families: [.oolong: 2, .rooibos: 1.5],
            line: "A long book wants a forgiving tea: oolong gives cup after cup.",
            lines: [.rooibos: "A long book wants a forgiving tea: rooibos never turns bitter, however long it sits."]
        ),
        Rule(
            before: 1900,
            teas: ["darjeeling": 1.5, "earl-grey": 1.5, "lapsang-souchong": 1],
            families: [.black: 1],
            line: "An old-fashioned black tea for an old book: the characters might have drunk it."
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
