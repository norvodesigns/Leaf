import Foundation

/// The teas Leaf knows, as data. Ids are saved on reading sessions, so they are permanent. New teas can be added, but
/// an existing id keeps its meaning.
///
/// Times and temperatures follow what the tin would say: black and oolong three to five minutes, green about two,
/// herbal five to seven. Each tea's caffeine, dayparts and seasons are chosen together, so the suggester can trust the
/// tags (nothing tagged for late evening has caffeine in it).
enum TeaCatalog {
    /// The tea to fall back on if anything ever asks for one and finds nothing.
    static let earlGrey = Tea(
        id: "earl-grey", name: "Earl Grey", family: .black, steepSeconds: 240, celsius: 95, fahrenheit: 203, caffeine: .medium,
        notes: ["bergamot", "citrus peel", "malt"],
        blurb: "Bergamot and a little brightness, the reliable friend of any chapter.",
        seasons: [.autumn, .winter, .spring], dayparts: [.morning, .lunch, .afternoon, .teaTime],
        moods: [.cozy, .focus, .uplifting], paletteToken: CozyPalette.steam
    )

    static let all: [Tea] = [
        earlGrey,
        Tea(
            id: "english-breakfast", name: "English Breakfast", family: .black, steepSeconds: 270, celsius: 100, fahrenheit: 212, caffeine: .high,
            notes: ["malt", "toast", "brisk"],
            blurb: "Strong, steady and ready before you are. Add milk and begin.",
            seasons: [.autumn, .winter, .spring], dayparts: [.dawn, .morning],
            moods: [.wakeUp, .focus, .warming], paletteToken: CozyPalette.chai
        ),
        Tea(
            id: "darjeeling", name: "Darjeeling", family: .black, steepSeconds: 180, celsius: 90, fahrenheit: 194, caffeine: .medium,
            notes: ["muscatel", "floral", "light tannin"],
            blurb: "Light, floral and a little grape, good company for a long paragraph.",
            seasons: [.spring, .summer, .autumn], dayparts: [.morning, .lunch, .afternoon, .teaTime],
            moods: [.calm, .focus, .uplifting], paletteToken: CozyPalette.amber
        ),
        Tea(
            id: "lapsang-souchong", name: "Lapsang Souchong", family: .black, steepSeconds: 240, celsius: 95, fahrenheit: 203, caffeine: .medium,
            notes: ["pine smoke", "campfire", "dried longan"],
            blurb: "Smoke and pine, like a fire in the next room. Made for rainy afternoons.",
            seasons: [.autumn, .winter], dayparts: [.afternoon, .teaTime, .dusk],
            moods: [.warming, .rainyDay, .cozy], paletteToken: CozyPalette.rooibos
        ),
        Tea(
            id: "sencha", name: "Sencha", family: .green, steepSeconds: 120, celsius: 80, fahrenheit: 176, caffeine: .low,
            notes: ["fresh grass", "sea breeze", "sweet greens"],
            blurb: "Fresh and green, ready in two minutes. A clear head for a clear page.",
            seasons: [.spring, .summer], dayparts: [.morning, .lunch, .afternoon],
            moods: [.focus, .refreshing, .calm], paletteToken: CozyPalette.matcha
        ),
        Tea(
            id: "jasmine-green", name: "Jasmine Green", family: .green, steepSeconds: 150, celsius: 80, fahrenheit: 176, caffeine: .low,
            notes: ["jasmine blossom", "honey", "soft grass"],
            blurb: "Flowers in the cup. It’s spring in here, whatever the window says.",
            seasons: [.spring, .summer], dayparts: [.morning, .lunch, .afternoon, .teaTime, .dusk],
            moods: [.calm, .uplifting, .refreshing], paletteToken: CozyPalette.steam
        ),
        Tea(
            id: "genmaicha", name: "Genmaicha", family: .green, steepSeconds: 150, celsius: 85, fahrenheit: 185, caffeine: .low,
            notes: ["toasted rice", "roasted nuts", "mellow greens"],
            blurb: "Green tea with toasted rice, like popcorn and a hug. Gentle on a quiet afternoon.",
            seasons: [.autumn, .winter, .spring], dayparts: [.afternoon, .teaTime, .dusk, .evening],
            moods: [.cozy, .calm, .warming], paletteToken: CozyPalette.amber
        ),
        Tea(
            id: "hojicha", name: "Hojicha", family: .green, steepSeconds: 120, celsius: 95, fahrenheit: 203, caffeine: .low,
            notes: ["roasted", "caramel", "cocoa"],
            blurb: "Roasted until mellow, with hardly any buzz. The evening cup for when you still want some character.",
            seasons: [.autumn, .winter], dayparts: [.teaTime, .dusk, .evening],
            moods: [.windDown, .cozy, .warming], paletteToken: CozyPalette.rooibos
        ),
        Tea(
            id: "matcha", name: "Matcha", family: .matcha, steepSeconds: 45, celsius: 75, fahrenheit: 167, caffeine: .high,
            notes: ["umami", "sweet grass", "cream"],
            blurb: "Whisked, not steeped. Bright and creamy, and good for one focused hour.",
            seasons: [.spring, .summer], dayparts: [.dawn, .morning, .lunch],
            moods: [.focus, .wakeUp, .uplifting], paletteToken: CozyPalette.matcha
        ),
        Tea(
            id: "silver-needle", name: "Silver Needle", family: .white, steepSeconds: 240, celsius: 80, fahrenheit: 176, caffeine: .low,
            notes: ["honeydew", "hay", "soft sweetness"],
            blurb: "Barely there and quietly sweet. It lets the book do the talking.",
            seasons: [.spring, .summer], dayparts: [.lunch, .afternoon, .teaTime, .dusk, .evening],
            moods: [.calm, .refreshing, .windDown], paletteToken: CozyPalette.steam
        ),
        Tea(
            id: "milk-oolong", name: "Milk Oolong", family: .oolong, steepSeconds: 210, celsius: 90, fahrenheit: 194, caffeine: .medium,
            notes: ["cream", "orchid", "butter"],
            blurb: "Creamy and soft, like a blanket you can drink.",
            seasons: [.autumn, .winter, .spring], dayparts: [.morning, .lunch, .afternoon, .teaTime, .dusk],
            moods: [.cozy, .calm, .warming], paletteToken: CozyPalette.paper
        ),
        Tea(
            id: "roasted-oolong", name: "Roasted Oolong", family: .oolong, steepSeconds: 270, celsius: 95, fahrenheit: 203, caffeine: .medium,
            notes: ["roasted nuts", "stone fruit", "mineral"],
            blurb: "Toasty and deep with a sweet finish, unhurried like the best chapters.",
            seasons: [.autumn, .winter], dayparts: [.afternoon, .teaTime, .dusk],
            moods: [.warming, .focus, .cozy], paletteToken: CozyPalette.amber
        ),
        Tea(
            id: "chamomile", name: "Chamomile", family: .herbal, steepSeconds: 360, celsius: 100, fahrenheit: 212, caffeine: .none,
            notes: ["apple", "honey", "hay"],
            blurb: "Soft as a lullaby. For the last chapter of the day.",
            seasons: [.spring, .summer, .autumn, .winter], dayparts: [.dusk, .evening, .late, .smallHours],
            moods: [.calm, .windDown, .cozy], paletteToken: CozyPalette.paper
        ),
        Tea(
            id: "peppermint", name: "Peppermint", family: .herbal, steepSeconds: 300, celsius: 100, fahrenheit: 212, caffeine: .none,
            notes: ["cool mint", "sweet", "clean"],
            blurb: "Cool and clear, with no caffeine at all. A fresh start for a tired afternoon.",
            seasons: [.spring, .summer, .autumn], dayparts: [.lunch, .afternoon, .teaTime, .dusk, .evening, .late],
            moods: [.refreshing, .focus, .calm], paletteToken: CozyPalette.matcha
        ),
        Tea(
            id: "lemon-ginger", name: "Lemon Ginger", family: .herbal, steepSeconds: 360, celsius: 100, fahrenheit: 212, caffeine: .none,
            notes: ["lemon", "warm ginger", "honey"],
            blurb: "Sunshine with a little spice. Warm hands, warm chest, easy pages.",
            seasons: [.autumn, .winter, .spring], dayparts: [.dawn, .morning, .evening, .late, .smallHours],
            moods: [.warming, .cozy, .uplifting], paletteToken: CozyPalette.amber
        ),
        Tea(
            id: "apple-cinnamon", name: "Apple Cinnamon", family: .herbal, steepSeconds: 360, celsius: 100, fahrenheit: 212, caffeine: .none,
            notes: ["baked apple", "cinnamon", "clove"],
            blurb: "Tastes like autumn in a mug. Best with a blanket and a slow book.",
            seasons: [.autumn, .winter], dayparts: [.teaTime, .dusk, .evening, .late, .smallHours],
            moods: [.cozy, .warming, .windDown], paletteToken: CozyPalette.rooibos
        ),
        Tea(
            id: "hibiscus", name: "Hibiscus", family: .herbal, steepSeconds: 360, celsius: 100, fahrenheit: 212, caffeine: .none,
            notes: ["cranberry", "tart", "floral"],
            blurb: "Ruby red and tart, lovely over ice on a long porch afternoon.",
            seasons: [.spring, .summer], dayparts: [.lunch, .afternoon, .teaTime, .dusk, .evening],
            moods: [.refreshing, .uplifting], paletteToken: CozyPalette.rose
        ),
        Tea(
            id: "rooibos", name: "Rooibos", family: .rooibos, steepSeconds: 360, celsius: 100, fahrenheit: 212, caffeine: .none,
            notes: ["sweet wood", "vanilla", "caramel"],
            blurb: "Red bush from South Africa, sweet and woody and naturally caffeine free. The evening classic.",
            seasons: [.autumn, .winter, .spring], dayparts: [.teaTime, .dusk, .evening, .late, .smallHours],
            moods: [.cozy, .windDown, .calm], paletteToken: CozyPalette.rooibos
        ),
        Tea(
            id: "masala-chai", name: "Masala Chai", family: .chai, steepSeconds: 300, celsius: 100, fahrenheit: 212, caffeine: .medium,
            notes: ["cardamom", "ginger", "cinnamon", "clove"],
            blurb: "Spiced, milky and a little bold. It warms you from the hands inward.",
            seasons: [.autumn, .winter], dayparts: [.dawn, .morning, .afternoon, .teaTime],
            moods: [.warming, .cozy, .wakeUp], paletteToken: CozyPalette.chai
        ),
    ]

    static let ids: [String] = all.map(\.id)

    /// Built so that a duplicated id (which the catalog tests forbid) can never crash the app at launch.
    private static let index: [String: Tea] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// The tea with this id, or nil for an unknown one (an old save, or a tea added by a newer version).
    static func tea(id: String?) -> Tea? {
        guard let id else { return nil }
        return index[id]
    }

    static func teas(in family: TeaFamily) -> [Tea] { all.filter { $0.family == family } }

    /// Teas tagged for this daypart and season, ignoring caffeine. A catalog check uses this to make sure no moment
    /// of the year is left with a thin choice.
    static func tagged(daypart: Daypart? = nil, season: Season? = nil) -> [Tea] {
        all.filter { tea in
            (daypart.map { tea.dayparts.contains($0) } ?? true) && (season.map { tea.seasons.contains($0) } ?? true)
        }
    }
}
