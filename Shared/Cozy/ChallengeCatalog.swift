import Foundation

/// The cozy challenges, as data. Ids and task ids are saved (enrollments, stamp ids), so they are permanent.
///
/// Each seasonal readathon has six prompts and each prompt wants a different finished book, so the prompts are worded
/// to overlap a little: a spooky mystery could answer either, and the evaluator finds the arrangement that fills the
/// most prompts. Copy keeps to the app’s voice: calm, no pressure, no exclamation marks.
enum ChallengeCatalog {
    static let all: [Challenge] = [
        spookySeason, winterHearth, springRain, summerPorch,
        yearlyGoal, hundredCups, potAWeek, sevenEvenings, cozyBingo, teaTasting, tastingNotebook,
    ]

    static let ids: [String] = all.map(\.id)

    static func challenge(id: String) -> Challenge? { all.first { $0.id == id } }

    // MARK: Helpers

    private static func prompt(_ id: String, _ title: String, genres: Set<String> = [], themes: Set<String> = [], minPages: Int? = nil, maxPages: Int? = nil) -> ChallengeTask {
        ChallengeTask(id: id, title: title, goal: .book(ChallengeBookMatcher(genres: genres, themes: themes, minPages: minPages, maxPages: maxPages)))
    }

    private static func stamp(_ challenge: String, _ slug: String, _ name: String, rings: Int, _ token: String, _ unlock: StampUnlock) -> StampDesign {
        StampDesign(id: "\(challenge).\(slug)", name: name, rings: rings, paletteToken: token, unlock: unlock)
    }

    // MARK: Seasonal readathons

    static let spookySeason = Challenge(
        id: "spooky-season", title: "Spooky Season", subtitle: "Six chapters by candlelight, September to November.",
        kind: .seasonalReadathon, window: .season(.autumn), rule: .bookPrompts,
        tasks: [
            prompt("ghost", "A ghost story", themes: ["ghosts"]),
            prompt("gothic", "Something gothic", themes: ["gothic"]),
            prompt("witch", "Witches and spells", themes: ["witches", "magic"]),
            prompt("creature", "A creature feature", themes: ["monsters", "vampires", "werewolves & shifters"]),
            prompt("dark", "Horror, with the lights on", genres: ["horror"]),
            prompt("short", "A tale for one sitting", maxPages: 200),
        ],
        stamps: [
            stamp("spooky-season", "lantern", "Lantern", rings: 1, CozyPalette.amber, .task("ghost")),
            stamp("spooky-season", "candle", "Candle", rings: 1, CozyPalette.paper, .task("gothic")),
            stamp("spooky-season", "cauldron", "Cauldron", rings: 2, CozyPalette.matcha, .task("witch")),
            stamp("spooky-season", "bat", "Bat", rings: 2, CozyPalette.chai, .task("creature")),
            stamp("spooky-season", "moth", "Moth", rings: 2, CozyPalette.steam, .task("dark")),
            stamp("spooky-season", "raven", "Raven", rings: 3, CozyPalette.rooibos, .task("short")),
            stamp("spooky-season", "harvest-moon", "Harvest Moon", rings: 5, CozyPalette.amber, .completion),
        ],
        unitSingular: "prompt", unitPlural: "prompts", paletteToken: CozyPalette.rooibos
    )

    static let winterHearth = Challenge(
        id: "winter-hearth", title: "Winter Hearth", subtitle: "Six long evenings by the fire, December to February.",
        kind: .seasonalReadathon, window: .season(.winter), rule: .bookPrompts,
        tasks: [
            prompt("snowy", "Something wintry", themes: ["winter", "christmas"]),
            prompt("cozy", "A cozy read", themes: ["cozy", "feel-good", "tea & cafes", "small town life", "found family"]),
            prompt("long-night", "A big one for long nights", minPages: 400),
            prompt("fairy-tale", "A fairy tale or a myth", themes: ["fairy tales & folklore", "mythology"]),
            prompt("letters", "Letters and diaries", themes: ["letters & diaries"]),
            prompt("old-friend", "An old friend", genres: ["classics"]),
        ],
        stamps: [
            stamp("winter-hearth", "snowflake", "Snowflake", rings: 1, CozyPalette.steam, .task("snowy")),
            stamp("winter-hearth", "mitten", "Mitten", rings: 1, CozyPalette.chai, .task("cozy")),
            stamp("winter-hearth", "ember", "Ember", rings: 2, CozyPalette.amber, .task("long-night")),
            stamp("winter-hearth", "pinecone", "Pinecone", rings: 2, CozyPalette.matcha, .task("fairy-tale")),
            stamp("winter-hearth", "quilt", "Quilt", rings: 2, CozyPalette.paper, .task("letters")),
            stamp("winter-hearth", "armchair", "Armchair", rings: 3, CozyPalette.rooibos, .task("old-friend")),
            stamp("winter-hearth", "midwinter", "Midwinter Hearth", rings: 5, CozyPalette.amber, .completion),
        ],
        unitSingular: "prompt", unitPlural: "prompts", paletteToken: CozyPalette.steam
    )

    static let springRain = Challenge(
        id: "spring-rain", title: "Spring Rain", subtitle: "Six showers and six open windows, March to May.",
        kind: .seasonalReadathon, window: .season(.spring), rule: .bookPrompts,
        tasks: [
            prompt("rainy", "A rainy-day read", themes: ["rainy days", "england", "scotland & ireland"]),
            prompt("growing", "Something growing", genres: ["nature"], themes: ["gardens & nature", "nature & environment"]),
            prompt("fresh-start", "A fresh start", genres: ["self-help"], themes: ["habits & mindset", "second chances", "mindfulness & meaning"]),
            prompt("love", "A love story", genres: ["romance"], themes: ["love stories"]),
            prompt("grown-up", "Growing up", themes: ["coming of age", "school life"]),
            prompt("verse", "A poem or a short story", genres: ["poetry", "short-stories"]),
        ],
        stamps: [
            stamp("spring-rain", "raindrop", "Raindrop", rings: 1, CozyPalette.steam, .task("rainy")),
            stamp("spring-rain", "seedling", "Seedling", rings: 1, CozyPalette.matcha, .task("growing")),
            stamp("spring-rain", "umbrella", "Umbrella", rings: 2, CozyPalette.chai, .task("fresh-start")),
            stamp("spring-rain", "blossom", "Blossom", rings: 2, CozyPalette.rose, .task("love")),
            stamp("spring-rain", "kite", "Kite", rings: 2, CozyPalette.amber, .task("grown-up")),
            stamp("spring-rain", "puddle", "Puddle", rings: 3, CozyPalette.paper, .task("verse")),
            stamp("spring-rain", "rainbow", "Rainbow", rings: 5, CozyPalette.rose, .completion),
        ],
        unitSingular: "prompt", unitPlural: "prompts", paletteToken: CozyPalette.matcha
    )

    static let summerPorch = Challenge(
        id: "summer-porch", title: "Summer Porch", subtitle: "Six long afternoons with something cold to drink, June to August.",
        kind: .seasonalReadathon, window: .season(.summer), rule: .bookPrompts,
        tasks: [
            prompt("water", "By the water", themes: ["seaside & islands", "pirates & the sea"]),
            prompt("journey", "A journey", genres: ["travel"], themes: ["road trips", "travel & places", "adventure"]),
            prompt("hammock", "A page-turner for the hammock", genres: ["thriller"], themes: ["psychological suspense"]),
            prompt("sunny-love", "A sunny love story", genres: ["romance"]),
            prompt("funny", "Something funny", genres: ["humor"], themes: ["humor"]),
            prompt("long-days", "A long one for long days", minPages: 450),
        ],
        stamps: [
            stamp("summer-porch", "shell", "Shell", rings: 1, CozyPalette.paper, .task("water")),
            stamp("summer-porch", "compass", "Compass", rings: 1, CozyPalette.chai, .task("journey")),
            stamp("summer-porch", "hammock", "Hammock", rings: 2, CozyPalette.matcha, .task("hammock")),
            stamp("summer-porch", "sunhat", "Sunhat", rings: 2, CozyPalette.amber, .task("sunny-love")),
            stamp("summer-porch", "lemonade", "Lemonade", rings: 2, CozyPalette.amber, .task("funny")),
            stamp("summer-porch", "firefly", "Firefly", rings: 3, CozyPalette.steam, .task("long-days")),
            stamp("summer-porch", "midsummer", "Midsummer", rings: 5, CozyPalette.amber, .completion),
        ],
        unitSingular: "prompt", unitPlural: "prompts", paletteToken: CozyPalette.amber
    )

    // MARK: Goals

    static let yearlyGoal = Challenge(
        id: "yearly-goal", title: "Yearly book goal", subtitle: "A shelf that fills at your own pace.",
        kind: .yearlyGoal, window: .calendarYear, rule: .booksFinished(defaultTarget: 12),
        tasks: [
            ChallengeTask(id: "quarter", title: "A quarter of the way", goal: .milestone(percent: 25)),
            ChallengeTask(id: "half", title: "Halfway there", goal: .milestone(percent: 50)),
            ChallengeTask(id: "three-quarters", title: "Three quarters done", goal: .milestone(percent: 75)),
            ChallengeTask(id: "goal", title: "Goal reached", goal: .milestone(percent: 100)),
        ],
        stamps: [
            stamp("yearly-goal", "quarter-pot", "Quarter Pot", rings: 1, CozyPalette.steam, .task("quarter")),
            stamp("yearly-goal", "half-pot", "Half Pot", rings: 2, CozyPalette.matcha, .task("half")),
            stamp("yearly-goal", "three-quarter-pot", "Three-Quarter Pot", rings: 3, CozyPalette.amber, .task("three-quarters")),
            stamp("yearly-goal", "full-pot", "Full Pot", rings: 5, CozyPalette.rooibos, .completion),
        ],
        unitSingular: "book", unitPlural: "books", paletteToken: CozyPalette.matcha
    )

    static let hundredCups = Challenge(
        id: "hundred-cups", title: "100 Cups", subtitle: "A hundred sittings, counted from the day you start.",
        kind: .cupGoal, window: .sinceJoining(days: nil), rule: .cups(target: 100),
        tasks: [
            ChallengeTask(id: "ten", title: "The first ten", goal: .milestone(percent: 10)),
            ChallengeTask(id: "quarter", title: "Twenty-five cups", goal: .milestone(percent: 25)),
            ChallengeTask(id: "half", title: "Fifty cups", goal: .milestone(percent: 50)),
            ChallengeTask(id: "three-quarters", title: "Seventy-five cups", goal: .milestone(percent: 75)),
            ChallengeTask(id: "hundred", title: "One hundred cups", goal: .milestone(percent: 100)),
        ],
        stamps: [
            stamp("hundred-cups", "saucer", "Saucer", rings: 1, CozyPalette.paper, .task("quarter")),
            stamp("hundred-cups", "teapot", "Teapot", rings: 2, CozyPalette.chai, .task("half")),
            stamp("hundred-cups", "samovar", "Samovar", rings: 3, CozyPalette.amber, .task("three-quarters")),
            stamp("hundred-cups", "hundredth-cup", "The Hundredth Cup", rings: 5, CozyPalette.rooibos, .completion),
        ],
        unitSingular: "cup", unitPlural: "cups", paletteToken: CozyPalette.chai
    )

    static let potAWeek = Challenge(
        id: "pot-a-week", title: "A Pot of Tea a Week", subtitle: "Four cups of reading, each week, for eight weeks.",
        kind: .cupGoal, window: .sinceJoining(days: 56), rule: .weeklyPots,
        tasks: (1...8).map { ChallengeTask(id: "week-\($0)", title: "Week \($0): a pot", goal: .week($0)) },
        stamps: [
            stamp("pot-a-week", "warm-pot", "Warm Pot", rings: 1, CozyPalette.chai, .task("week-2")),
            stamp("pot-a-week", "steeped", "Steeped", rings: 2, CozyPalette.amber, .task("week-4")),
            stamp("pot-a-week", "well-steeped", "Well Steeped", rings: 3, CozyPalette.rooibos, .task("week-6")),
            stamp("pot-a-week", "every-week", "Every Week", rings: 5, CozyPalette.matcha, .completion),
        ],
        unitSingular: "week", unitPlural: "weeks", paletteToken: CozyPalette.amber
    )

    static let sevenEvenings = Challenge(
        id: "seven-evenings", title: "Seven Evenings", subtitle: "Seven reading evenings in a row. Rest days don’t break it.",
        kind: .streak, window: .sinceJoining(days: 60), rule: .eveningStreak,
        tasks: [
            ChallengeTask(id: "evenings-1", title: "One evening", goal: .evenings(1)),
            ChallengeTask(id: "evenings-2", title: "Two in a row", goal: .evenings(2)),
            ChallengeTask(id: "evenings-3", title: "Three in a row", goal: .evenings(3)),
            ChallengeTask(id: "evenings-4", title: "Four in a row", goal: .evenings(4)),
            ChallengeTask(id: "evenings-5", title: "Five in a row", goal: .evenings(5)),
            ChallengeTask(id: "evenings-6", title: "Six in a row", goal: .evenings(6)),
            ChallengeTask(id: "evenings-7", title: "Seven in a row", goal: .evenings(7)),
        ],
        stamps: [
            stamp("seven-evenings", "three-lamps", "Three Lamps", rings: 1, CozyPalette.amber, .task("evenings-3")),
            stamp("seven-evenings", "five-lamps", "Five Lamps", rings: 2, CozyPalette.amber, .task("evenings-5")),
            stamp("seven-evenings", "lamplighter", "Lamplighter", rings: 5, CozyPalette.amber, .completion),
        ],
        unitSingular: "evening", unitPlural: "evenings", paletteToken: CozyPalette.amber
    )

    // MARK: Bingo and tasting

    /// Nine squares in reading order (three rows of three). A finished book fills one square.
    static let cozyBingo = Challenge(
        id: "cozy-bingo", title: "Cozy Bingo", subtitle: "Nine kinds of book on one card. Fill a line, or the lot.",
        kind: .genreBingo, window: .calendarYear, rule: .bookPrompts,
        tasks: [
            prompt("cozy", "A cozy corner", themes: ["cozy", "feel-good", "tea & cafes", "small town life"]),
            prompt("whodunit", "A whodunit", genres: ["mystery"]),
            prompt("other-worlds", "Another world", genres: ["fantasy", "science-fiction"]),
            prompt("love-story", "A love story", genres: ["romance"], themes: ["love stories"]),
            prompt("old-friend", "An old friend", genres: ["classics"]),
            prompt("after-dark", "After dark", genres: ["horror"], themes: ["ghosts", "gothic"]),
            prompt("true-stories", "True stories", genres: ["history", "biography", "memoir", "science", "nature", "essays", "travel"]),
            prompt("funny", "Something funny", genres: ["humor"], themes: ["humor"]),
            prompt("short-forms", "Poems, plays and pictures", genres: ["poetry", "drama", "graphic", "short-stories"]),
        ],
        stamps: [
            stamp("cozy-bingo", "first-line", "First Line", rings: 2, CozyPalette.matcha, .lines(1)),
            stamp("cozy-bingo", "three-lines", "Three Lines", rings: 3, CozyPalette.amber, .lines(3)),
            stamp("cozy-bingo", "full-card", "Full Card", rings: 5, CozyPalette.rooibos, .completion),
        ],
        unitSingular: "square", unitPlural: "squares", paletteToken: CozyPalette.paper
    )

    /// The eight lines of the bingo card, as indexes into its tasks.
    static let bingoLines: [[Int]] = [
        [0, 1, 2], [3, 4, 5], [6, 7, 8],
        [0, 3, 6], [1, 4, 7], [2, 5, 8],
        [0, 4, 8], [2, 4, 6],
    ]

    static let teaTasting = Challenge(
        id: "tea-tasting", title: "Tea Tasting", subtitle: "Read with six different teas.",
        kind: .teaTasting, window: .sinceJoining(days: nil), rule: .differentTeas,
        tasks: [
            ChallengeTask(id: "tea-1", title: "A first tea", goal: .teas(1)),
            ChallengeTask(id: "tea-2", title: "A second tea", goal: .teas(2)),
            ChallengeTask(id: "tea-3", title: "A third tea", goal: .teas(3)),
            ChallengeTask(id: "tea-4", title: "A fourth tea", goal: .teas(4)),
            ChallengeTask(id: "tea-5", title: "A fifth tea", goal: .teas(5)),
            ChallengeTask(id: "tea-6", title: "A sixth tea", goal: .teas(6)),
        ],
        stamps: [
            stamp("tea-tasting", "curious-sip", "Curious Sip", rings: 1, CozyPalette.steam, .task("tea-2")),
            stamp("tea-tasting", "tasting-flight", "Tasting Flight", rings: 3, CozyPalette.matcha, .task("tea-4")),
            stamp("tea-tasting", "tea-taster", "Tea Taster", rings: 5, CozyPalette.chai, .completion),
        ],
        unitSingular: "tea", unitPlural: "teas", paletteToken: CozyPalette.chai
    )

    /// Depth rather than breadth of reading: a note after the cup, on more teas and more families of tea.
    static let tastingNotebook = Challenge(
        id: "tasting-notebook", title: "Tasting Notebook", subtitle: "A few words after the cup, across the families of tea.",
        kind: .teaTasting, window: .sinceJoining(days: nil), rule: .tastingNotes,
        tasks: [
            ChallengeTask(id: "note-1", title: "A first tasting note", goal: .tasted(1)),
            ChallengeTask(id: "note-3", title: "Notes on three teas", goal: .tasted(3)),
            ChallengeTask(id: "note-6", title: "Notes on six teas", goal: .tasted(6)),
            ChallengeTask(id: "family-3", title: "Three families of tea", goal: .tastedFamilies(3)),
            ChallengeTask(id: "family-5", title: "Five families of tea", goal: .tastedFamilies(5)),
        ],
        stamps: [
            stamp("tasting-notebook", "first-note", "First Note", rings: 1, CozyPalette.steam, .task("note-1")),
            stamp("tasting-notebook", "steady-palate", "Steady Palate", rings: 3, CozyPalette.matcha, .task("note-6")),
            stamp("tasting-notebook", "tea-scholar", "Tea Scholar", rings: 5, CozyPalette.chai, .completion),
        ],
        unitSingular: "entry", unitPlural: "entries", paletteToken: CozyPalette.matcha
    )
}
