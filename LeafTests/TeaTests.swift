import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Fixtures

private var teaCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func teaDate(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    teaCalendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

private let teaNow = teaDate(10, 14, 9)

private func teaBook(_ id: String, genres: [String] = [], themes: [String] = [], pages: Int = 300, year: Int? = nil) -> Book {
    Book(id: id, title: "Book \(id)", author: "Author \(id)", year: year, pages: pages, genres: genres, themes: themes)
}

private func teaItem(_ book: Book, shelf: Shelf = .reading, page: Int = 0, order: Double = 0, paired: String? = nil) -> LibraryItem {
    LibraryItem(
        book: book, shelf: shelf, currentPage: page, order: order, addedAt: teaDate(1, 1),
        startedAt: shelf == .reading ? teaDate(9, 1) : nil, pairedTeaID: paired
    )
}

private func teaSession(_ book: String, day: Int, minutes: Double, tea: String?, from: Int = 0, to: Int = 10) -> ReadingSession {
    ReadingSession(bookID: book, startedAt: teaDate(10, day, 20), seconds: minutes * 60, fromPage: from, toPage: to, teaID: tea)
}

private func teaUUID(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
}

/// The app's voice: no exclamation marks, typographic apostrophes, a full stop at the end.
private func teaCopyIsClean(_ text: String) -> Bool {
    !text.isEmpty && !text.contains("!") && !text.contains("'") && text.hasSuffix(".")
}

// MARK: - Pairing

struct TeaPairingTests {
    @Test func aCozyMysteryPairsWithAMaltyBlackTea() throws {
        let book = teaBook("cozy", genres: ["mystery"], themes: ["cozy", "small town life"])
        let best = try #require(TeaPairing.best(for: book))
        #expect(best.tea.id == "english-breakfast")
        #expect(best.tea.family == .black)
        #expect(best.reason.contains("cozy mystery"))
    }

    @Test func aLongClassicPairsWithOolong() throws {
        let book = teaBook("middlemarch", genres: ["classics"], pages: 880, year: 1871)
        let best = try #require(TeaPairing.best(for: book))
        #expect(best.tea.family == .oolong)
        #expect(best.reason.contains("oolong"))
        // A short classic is not a long one: the black teas the classics would know come first.
        let short = try #require(TeaPairing.best(for: teaBook("gatsby", genres: ["classics"], pages: 180, year: 1925)))
        #expect(short.tea.family == .black)
    }

    @Test func poetryPairsWithADelicateGreen() throws {
        let book = teaBook("odes", genres: ["poetry"], pages: 96)
        let best = try #require(TeaPairing.best(for: book))
        #expect(best.tea.id == "jasmine-green")
        #expect(best.tea.family == .green)
        #expect(best.reason.contains("delicate"))
        let picks = TeaPairing.picks(for: book, limit: 3)
        #expect(picks.allSatisfy { $0.tea.family == .green || $0.tea.family == .white })
    }

    @Test func aBookNoRuleKnowsStillGetsAPairing() throws {
        let book = teaBook("plain")
        let picks = TeaPairing.picks(for: book, limit: 3)
        #expect(picks.count == 3)
        let best = try #require(picks.first)
        #expect(best.tea.family == .black)
        #expect(teaCopyIsClean(best.reason))
    }

    @Test func picksAreBestFirstLimitedAndDeterministic() {
        let book = teaBook("f", genres: ["fantasy"], themes: ["dragons", "winter"], pages: 640)
        let picks = TeaPairing.picks(for: book, limit: 4)
        #expect(picks.count == 4)
        #expect(zip(picks, picks.dropFirst()).allSatisfy { $0.score >= $1.score })
        #expect(TeaPairing.picks(for: book, limit: 4) == picks)
        #expect(TeaPairing.picks(for: book, limit: 0).isEmpty)
        #expect(TeaPairing.picks(for: book, from: []).isEmpty)
        #expect(TeaPairing.picks(for: book, limit: 100).count == TeaCatalog.all.count)
    }

    @Test func picksOnlyFromTheTeasItIsGiven() throws {
        let cabinet = [
            CabinetTea(name: "Grandma’s blend", family: .herbal, steepSeconds: 400).tea,
            CabinetTea(name: "Smoky lot", family: .oolong, steepSeconds: 180).tea,
        ]
        let classic = teaBook("anna", genres: ["classics"], pages: 860)
        let best = try #require(TeaPairing.best(for: classic, from: cabinet))
        #expect(best.tea.name == "Smoky lot")
        #expect(TeaPairing.picks(for: classic, from: cabinet, limit: 5).count == 2)
        // A reader's own oolong takes the family's line, not a line naming a tea they don't have.
        #expect(best.reason.contains("oolong"))
    }

    @Test func aPinnedTeaGetsItsOwnReason() {
        let book = teaBook("cozy", genres: ["mystery"], themes: ["cozy"])
        let sencha = TeaCatalog.tea(id: "sencha")!
        let reason = TeaPairing.reason(for: sencha, with: book)
        #expect(teaCopyIsClean(reason))
        #expect(!reason.contains("malty black"))
    }

    /// Words that name one catalog tea, and the words that name a family.
    private static let teaWords: [String: [String]] = [
        "earl-grey": ["earl grey"], "english-breakfast": ["english breakfast"], "darjeeling": ["darjeeling"],
        "lapsang-souchong": ["lapsang"], "sencha": ["sencha"], "jasmine-green": ["jasmine"], "genmaicha": ["genmaicha"],
        "hojicha": ["hojicha"], "silver-needle": ["silver needle"], "milk-oolong": ["milk oolong"],
        "roasted-oolong": ["roasted oolong"], "chamomile": ["chamomile"], "peppermint": ["peppermint", "mint"],
        "lemon-ginger": ["lemon ginger"], "apple-cinnamon": ["apple"], "hibiscus": ["hibiscus"], "masala-chai": ["masala"],
    ]
    private static let familyWords: [String: Set<TeaFamily>] = [
        "black tea": [.black], "oolong": [.oolong], "white tea": [.white], "herbal": [.herbal], "rooibos": [.rooibos],
        "matcha": [.matcha], "chai": [.chai], "green": [.green, .matcha],
    ]

    /// Every tea a rule gives weight to (catalog teas, and a tea of the reader's own in each family) gets a line
    /// about it: never one naming another tea or another family.
    @Test func aReasonNamesOnlyTheTeaItIsFor() {
        let own = TeaFamily.allCases.map { CabinetTea(name: "Own \($0.rawValue)", family: $0, steepSeconds: 200).tea }
        for rule in TeaPairing.rules {
            for tea in TeaCatalog.all + own where rule.weight(for: tea) > 0 {
                let reason = rule.reason(for: tea).lowercased()
                for (id, words) in Self.teaWords where id != tea.id {
                    for word in words { #expect(!reason.contains(word), "\(tea.id): \(reason)") }
                }
                for (word, families) in Self.familyWords where reason.contains(word) {
                    #expect(families.contains(tea.family), "\(tea.id): \(reason)")
                }
            }
        }
    }

    /// A tea a rule names never ranks below an unnamed tea of its own family.
    @Test func aNamedTeaWeighsAtLeastItsFamily() {
        for rule in TeaPairing.rules {
            for (id, weight) in rule.teas {
                guard let tea = TeaCatalog.tea(id: id), let family = rule.families[tea.family] else { continue }
                #expect(weight >= family, "\(id): \(rule.line)")
            }
        }
    }

    /// Rule themes are the catalog's own theme names (scripts/add_themes.py), or they would never match a book.
    @Test func ruleThemesAreInTheCatalogsVocabulary() throws {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/add_themes.py")
        guard let text = try? String(contentsOf: script, encoding: .utf8) else { return }
        let regex = try NSRegularExpression(pattern: #"^\s*\("([^"]+)",\s*r""#, options: [.anchorsMatchLines])
        let range = NSRange(text.startIndex..., in: text)
        let vocabulary = Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
        try #require(vocabulary.count > 50)
        for rule in TeaPairing.rules {
            for theme in rule.themes.union(rule.alsoThemes) {
                #expect(vocabulary.contains(theme), "\(theme)")
            }
        }
    }

    @Test func everyRuleNamesRealTeasAndSpeaksInTheAppsVoice() {
        let known = Set(TeaCatalog.all.map(\.id))
        for rule in TeaPairing.rules {
            #expect(Set(rule.teas.keys).isSubset(of: known), "\(rule.line)")
            #expect(Set(rule.teaLines.keys).isSubset(of: known), "\(rule.line)")
            #expect(!rule.teas.isEmpty || !rule.families.isEmpty)
            #expect(teaCopyIsClean(rule.line), "\(rule.line)")
            for line in rule.lines.values { #expect(teaCopyIsClean(line), "\(line)") }
            for line in rule.teaLines.values { #expect(teaCopyIsClean(line), "\(line)") }
        }
        for tea in TeaCatalog.all {
            #expect(teaCopyIsClean(TeaPairing.reason(for: tea, with: teaBook("x"))), "\(tea.id)")
        }
    }
}

// MARK: - Cabinet

struct TeaCabinetTests {
    @Test func aTinKeepsTheCatalogIdSoStatsStillCountIt() {
        let earl = TeaCatalog.tea(id: "earl-grey")!
        var tin = CabinetTea(tin: earl, now: teaNow)
        #expect(tin.teaID == "earl-grey")
        tin.name = "Earl Grey Supreme"
        tin.steepSeconds = 200
        tin.brand = "Harney"
        let tea = tin.tea
        #expect(tea.id == "earl-grey")
        #expect(tea.name == "Earl Grey Supreme")
        #expect(tea.steepSeconds == 200)
        #expect(tea.caffeine == earl.caffeine)
        #expect(tin.displayName == "Earl Grey Supreme · Harney")
        #expect(TeaShelf.tea(id: "earl-grey", cabinet: [tin])?.steepSeconds == 200)
        #expect(TeaShelf.tea(id: "earl-grey", cabinet: [])?.steepSeconds == earl.steepSeconds)
    }

    @Test func aTeaOfTheReadersOwnFollowsItsFamily() {
        let own = CabinetTea(id: teaUUID(1), name: "Mountain mist", brand: "", family: .black, steepSeconds: 210)
        #expect(own.teaID == "custom.00000000-0000-0000-0000-000000000001")
        #expect(own.displayName == "Mountain mist")
        let tea = own.tea
        #expect(tea.id == own.teaID)
        // As much caffeine as the catalog's mildest black tea, no more.
        #expect(tea.caffeine == .medium)
        #expect(!tea.dayparts.contains(.late))
        #expect(tea.dayparts.contains(.morning))
        #expect(TeaShelf.tea(id: own.teaID, cabinet: [own])?.name == "Mountain mist")
        #expect(TeaShelf.tea(id: own.teaID, cabinet: []) == nil)
        #expect(TeaShelf.tea(id: nil, cabinet: [own]) == nil)
        #expect(TeaShelf.tea(id: "", cabinet: [own]) == nil)
        // A tea with no name still reads as something.
        #expect(CabinetTea(name: "", family: .rooibos, steepSeconds: 300).tea.name == TeaFamily.rooibos.title)
    }

    @Test func twoTinsOfOneTeaOfferItOnceAndTheOneInStockWins() {
        let earl = TeaCatalog.tea(id: "earl-grey")!
        var older = CabinetTea(tin: earl, now: teaDate(9, 1))
        older.id = teaUUID(1)
        older.isOutOf = true
        var newer = CabinetTea(tin: earl, now: teaDate(9, 2))
        newer.id = teaUUID(2)
        newer.steepSeconds = 200
        let cabinet = [older, newer]
        #expect(TeaShelf.inStock(cabinet).map(\.id) == ["earl-grey"])
        #expect(TeaShelf.tea(id: "earl-grey", cabinet: cabinet)?.steepSeconds == 200)
        newer.isOutOf = false
        older.isOutOf = false
        older.updatedAt = teaDate(9, 5)
        older.steepSeconds = 180
        #expect(TeaShelf.inStock([older, newer]).map(\.steepSeconds) == [180])
        let choices = TeaShelf.ritualChoices(cabinet: [older, newer], daypart: .morning, season: .autumn)
        #expect(choices.teas.filter { $0.id == "earl-grey" }.count == 1)
    }

    /// The reader's own tea is never ruled out at an hour when the catalog offers a tea of the same family.
    @Test func aTeaOfYourOwnIsNoStricterThanLeafsOwn() {
        for family in TeaFamily.allCases {
            let own = CabinetTea(name: "Own", family: family, steepSeconds: 200).tea
            for daypart in Daypart.allCases {
                let catalogOffers = TeaSuggester.allowed(at: daypart).contains { $0.family == family }
                if catalogOffers {
                    #expect(!TeaSuggester.allowed(at: daypart, from: [own]).isEmpty, "\(family) at \(daypart)")
                }
            }
        }
    }

    @Test func ratingsStayBetweenOneAndFive() {
        #expect(CabinetTea(name: "A", family: .green, steepSeconds: 60, rating: 9).rating == 5)
        #expect(CabinetTea(name: "A", family: .green, steepSeconds: 60, rating: 0).rating == 1)
        #expect(TastingNote(teaID: "sencha", teaName: "Sencha", rating: -3).rating == 1)
        #expect(TastingNote(teaID: "sencha", teaName: "Sencha").rating == nil)
    }

    @Test func theRitualOffersWhatIsInTheCabinet() {
        let cabinet = [
            CabinetTea(id: teaUUID(1), catalogID: "sencha", name: "Sencha", family: .green, steepSeconds: 90, addedAt: teaDate(9, 1)),
            CabinetTea(id: teaUUID(2), name: "Mountain mist", family: .black, steepSeconds: 210, addedAt: teaDate(9, 2)),
            CabinetTea(id: teaUUID(3), catalogID: "chamomile", name: "Chamomile", family: .herbal, steepSeconds: 300, isOutOf: true, addedAt: teaDate(9, 3)),
        ]
        let morning = TeaShelf.ritualChoices(cabinet: cabinet, daypart: .morning, season: .autumn)
        #expect(morning.fromCabinet)
        #expect(!morning.cabinetUnsuitable)
        #expect(Set(morning.teas.map(\.id)) == ["sencha", cabinet[1].teaID])
        #expect(TeaShelf.inStock(cabinet).map(\.id) == ["sencha", cabinet[1].teaID])
    }

    @Test func lateAtNightTheCatalogFillsInWhenTheCabinetIsAllCaffeine() {
        let cabinet = [
            CabinetTea(tin: TeaCatalog.tea(id: "english-breakfast")!, now: teaDate(9, 1)),
            CabinetTea(name: "Mountain mist", family: .black, steepSeconds: 210, addedAt: teaDate(9, 2)),
        ]
        let late = TeaShelf.ritualChoices(cabinet: cabinet, daypart: .late, season: .winter)
        #expect(!late.fromCabinet)
        #expect(late.cabinetUnsuitable)
        #expect(!late.teas.isEmpty)
        #expect(late.teas.allSatisfy { $0.caffeine == TeaCaffeine.none })
    }

    @Test func anEmptyOrOutOfCabinetUsesTheCatalogQuietly() {
        let out = [CabinetTea(catalogID: "sencha", name: "Sencha", family: .green, steepSeconds: 90, isOutOf: true)]
        for cabinet in [[], out] {
            let choices = TeaShelf.ritualChoices(cabinet: cabinet, daypart: .afternoon, season: .spring)
            #expect(!choices.fromCabinet)
            #expect(!choices.cabinetUnsuitable)
            #expect(!choices.teas.isEmpty)
        }
    }

    @Test func theRitualStartsWithThePinnedPairingWhenItIsOnOffer() {
        let book = teaBook("cozy", genres: ["mystery"], themes: ["cozy"])
        let choices = ["sencha", "english-breakfast", "rooibos"].compactMap { TeaCatalog.tea(id: $0) }
        #expect(TeaShelf.preferred(for: book, pinnedTeaID: "rooibos", choices: choices)?.id == "rooibos")
        // Pinned but not on offer (caffeine at night, or out of it): the best pairing among the choices.
        #expect(TeaShelf.preferred(for: book, pinnedTeaID: "lapsang-souchong", choices: choices)?.id == "english-breakfast")
        #expect(TeaShelf.preferred(for: nil, pinnedTeaID: nil, choices: choices)?.id == "sencha")
        #expect(TeaShelf.preferred(for: book, pinnedTeaID: nil, choices: []) == nil)
    }
}

// MARK: - History and the week's pairing

struct TeaHistoryTests {
    @Test func minutesBooksAndNotesAddUpPerTea() throws {
        let own = CabinetTea(id: teaUUID(7), name: "Mountain mist", family: .black, steepSeconds: 210)
        var data = LeafData()
        data.items = [teaItem(teaBook("a")), teaItem(teaBook("b"))]
        data.cabinet = [own]
        data.sessions = [
            teaSession("a", day: 1, minutes: 30, tea: "sencha"),
            teaSession("a", day: 2, minutes: 20, tea: "sencha"),
            teaSession("b", day: 3, minutes: 25, tea: "sencha"),
            teaSession("b", day: 4, minutes: 40, tea: own.teaID),
            teaSession("b", day: 5, minutes: 15, tea: nil),
        ]
        data.tastings = [
            TastingNote(teaID: "sencha", teaName: "Sencha", family: .green, rating: 4, createdAt: teaDate(10, 2)),
            TastingNote(teaID: "sencha", teaName: "Sencha", family: .green, rating: 5, createdAt: teaDate(10, 3)),
            TastingNote(teaID: "custom.gone", teaName: "Market oolong", family: .oolong, createdAt: teaDate(10, 4)),
        ]
        let history = TeaHistory.build(data: data)
        let first = try #require(history.mostReadWith)
        #expect(first.teaID == "sencha")
        #expect(first.minutes == 75)
        #expect(first.sessions == 3)
        #expect(first.books == 2)
        #expect(first.tastings == 2)
        #expect(first.averageRating == 4.5)
        #expect(first.lastBrewed == teaDate(10, 3, 20))
        #expect(history.teas.map(\.name) == ["Sencha", "Mountain mist", "Market oolong"])
        // A tea that left the cabinet keeps the name its tasting note wrote down.
        #expect(history.teas.last?.family == .oolong)
        #expect(history.minutesWithTea == 115)
        #expect(history.minutesInAll == 130)
        #expect(abs(history.teaShare - 115.0 / 130.0) < 1e-9)
        // Books, most recently read first, with their teas by minutes.
        #expect(history.books.map(\.bookID) == ["b", "a"])
        #expect(history.books[0].teas.map(\.name) == ["Mountain mist", "Sencha"])
        #expect(history.tastings.first?.teaName == "Market oolong")
    }

    @Test func anEmptyHistoryIsEmpty() {
        let history = TeaHistory.build(data: LeafData())
        #expect(history.isEmpty)
        #expect(history.mostReadWith == nil)
        #expect(history.teaShare == 0)
    }

    @Test func theWeeksBookIsTheOneAboutToBeFinished() throws {
        let nearly = teaItem(teaBook("nearly", genres: ["poetry"], pages: 200), page: 196, order: 0)
        let early = teaItem(teaBook("early", genres: ["mystery"], themes: ["cozy"], pages: 600), page: 20, order: 1)
        var data = LeafData()
        data.items = [early, nearly]
        data.preferences.dailyMinutes = 30
        data.preferences.readingDays = Set(1...7)
        data.sessions = (1...10).map { teaSession($0 % 2 == 0 ? "nearly" : "early", day: $0, minutes: 30, tea: "sencha", from: $0 * 10, to: $0 * 10 + 15) }
        let forecast = ForecastEngine(data: data, now: teaNow, calendar: teaCalendar).forecast(seed: 3, runs: 200)
        let pick = try #require(TeaOfTheWeek.pick(data: data, forecast: forecast, now: teaNow, calendar: teaCalendar))
        #expect(pick.bookID == "nearly")
        #expect(pick.line.hasPrefix("Likely finished"))
        #expect(pick.line.hasSuffix("to see it home."))
        #expect(pick.tea.family == .green || pick.tea.family == .white)
        #expect(!pick.isPinned)
        #expect(teaCopyIsClean(pick.line))
    }

    @Test func withoutAForecastTheFurthestAlongBookIsTheWeeks() throws {
        var data = LeafData()
        data.items = [
            teaItem(teaBook("one", pages: 400), page: 40, order: 0),
            teaItem(teaBook("two", genres: ["mystery"], themes: ["cozy"], pages: 300), page: 150, order: 1),
        ]
        let pick = try #require(TeaOfTheWeek.pick(data: data, forecast: nil, now: teaNow, calendar: teaCalendar))
        #expect(pick.bookID == "two")
        #expect(pick.tea.id == "english-breakfast")
        #expect(pick.line == "Your book for the week, with a pot of English Breakfast beside it.")
    }

    @Test func thePinnedPairingAndTheCabinetWin() throws {
        var data = LeafData()
        data.items = [teaItem(teaBook("next", genres: ["mystery"], themes: ["cozy"]), shelf: .toRead, paired: "rooibos")]
        let pinned = try #require(TeaOfTheWeek.pick(data: data, forecast: nil, now: teaNow, calendar: teaCalendar))
        #expect(pinned.tea.id == "rooibos")
        #expect(pinned.isPinned)
        #expect(pinned.line.hasPrefix("Next up"))

        data.items[0].pairedTeaID = nil
        data.cabinet = [CabinetTea(id: teaUUID(4), catalogID: "earl-grey", name: "Earl Grey", family: .black, steepSeconds: 200)]
        let fromCabinet = try #require(TeaOfTheWeek.pick(data: data, forecast: nil, now: teaNow, calendar: teaCalendar))
        #expect(fromCabinet.tea.id == "earl-grey")
        #expect(fromCabinet.tea.steepSeconds == 200)
        #expect(TeaOfTheWeek.pick(data: LeafData(), forecast: nil, now: teaNow, calendar: teaCalendar) == nil)
    }
}

// MARK: - Tasting Notebook

struct TastingNotebookTests {
    private func progress(_ notes: [TastingNote], joined: Date = teaDate(10, 1)) -> ChallengeProgress {
        var data = LeafData()
        data.tastings = notes
        let enrollment = ChallengeEnrollment(id: ChallengeCatalog.tastingNotebook.id, joinedAt: joined, year: nil)
        return ChallengeEvaluator.progress(for: enrollment, data: data, now: teaNow, calendar: teaCalendar)
    }

    @Test func notesCountEachTeaOnceAndEachFamilyOnce() {
        let notes = [
            TastingNote(teaID: "sencha", teaName: "Sencha", createdAt: teaDate(10, 2)),
            TastingNote(teaID: "sencha", teaName: "Sencha", createdAt: teaDate(10, 3)),
            TastingNote(teaID: "earl-grey", teaName: "Earl Grey", createdAt: teaDate(10, 4)),
            TastingNote(teaID: "custom.x", teaName: "Market oolong", family: .oolong, createdAt: teaDate(10, 5)),
        ]
        let p = progress(notes)
        let done = Set(p.completedTaskIDs)
        #expect(done == ["note-1", "note-3", "family-3"])
        #expect(p.tasks.first { $0.id == "family-3" }?.evidence == TeaFamily.oolong.title)
        #expect(p.current == 3)
        #expect(p.target == 5)
        #expect(!p.isComplete)
    }

    @Test func notesFromBeforeJoiningDoNotCount() {
        let notes = [TastingNote(teaID: "sencha", teaName: "Sencha", createdAt: teaDate(9, 2))]
        #expect(progress(notes).completedTaskIDs.isEmpty)
    }

    @Test func theNotebookIsInTheCatalogWithAFinalStamp() {
        let challenge = ChallengeCatalog.tastingNotebook
        #expect(ChallengeCatalog.all.contains { $0.id == challenge.id })
        #expect(challenge.stamps.contains { $0.unlock == .completion })
        #expect(challenge.rule == .tastingNotes)
    }
}

// MARK: - Old saved data

struct TeaMigrationTests {
    private func stripping(_ keys: [String], from data: Data) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in keys { object.removeValue(forKey: key) }
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func dataSavedBeforeTheCabinetStillLoads() throws {
        var data = LeafData()
        data.items = [teaItem(teaBook("a"))]
        data.sessions = [teaSession("a", day: 1, minutes: 20, tea: "sencha")]
        let old = try stripping(["cabinet", "tastings"], from: JSONEncoder().encode(data))
        let loaded = try JSONDecoder().decode(LeafData.self, from: old)
        #expect(loaded.cabinet.isEmpty)
        #expect(loaded.tastings.isEmpty)
        #expect(loaded.items.map(\.id) == ["a"])
        #expect(loaded.sessions.count == 1)
    }

    @Test func aBookSavedBeforePairingsHasNone() throws {
        let item = teaItem(teaBook("a"), paired: "sencha")
        let encoded = try JSONEncoder().encode(item)
        #expect(try JSONDecoder().decode(LibraryItem.self, from: encoded).pairedTeaID == "sencha")
        let old = try stripping(["pairedTeaID"], from: encoded)
        #expect(try JSONDecoder().decode(LibraryItem.self, from: old).pairedTeaID == nil)
    }

    @Test func theCabinetAndNotesRoundTrip() throws {
        var data = LeafData()
        data.cabinet = [CabinetTea(id: teaUUID(1), catalogID: "sencha", name: "Sencha", brand: "Ippodo", family: .green, notes: "Grassy", steepSeconds: 70, rating: 5, isOutOf: true, addedAt: teaDate(9, 1), updatedAt: teaDate(9, 5))]
        data.tastings = [TastingNote(id: teaUUID(2), teaID: "sencha", teaName: "Sencha", family: .green, bookID: "a", strength: .strong, aromas: ["grassy"], rating: 4, text: "Bright", createdAt: teaDate(9, 6))]
        let loaded = try JSONDecoder().decode(LeafData.self, from: JSONEncoder().encode(data))
        #expect(loaded.cabinet == data.cabinet)
        #expect(loaded.tastings == data.tastings)
    }

    @Test func sparseRecordsFillInDefaults() throws {
        let tea = try JSONDecoder().decode(CabinetTea.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000009","name":"Hojicha","family":"green"}"#.utf8))
        #expect(tea.steepSeconds == TeaFamily.green.defaultSteepSeconds)
        #expect(!tea.isOutOf)
        #expect(tea.updatedAt == tea.addedAt)
        let note = try JSONDecoder().decode(TastingNote.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000010","teaID":"sencha","strength":"scalding","family":"purple"}"#.utf8))
        #expect(note.strength == nil)
        #expect(note.family == nil)
        #expect(note.aromas.isEmpty)
        #expect(note.updatedAt == note.createdAt)
    }
}

// MARK: - Sync

struct TeaSyncTests {
    private let now = teaDate(10, 14)

    private func tea(_ n: Int, name: String, updated: Date, outOf: Bool = false) -> CabinetTea {
        CabinetTea(id: teaUUID(n), name: name, family: .black, steepSeconds: 200, isOutOf: outOf, addedAt: teaDate(9, 1), updatedAt: updated)
    }

    private func note(_ n: Int, rating: Int?, updated: Date) -> TastingNote {
        TastingNote(id: teaUUID(n), teaID: "sencha", teaName: "Sencha", rating: rating, createdAt: teaDate(9, 1), updatedAt: updated)
    }

    @Test func stateFromAnOlderLayoutFetchesEverythingOnce() {
        #expect(SyncPolicy.syncLayout >= 2)
        #expect(SyncPolicy.needsFullFetch(savedLayout: nil))
        #expect(SyncPolicy.needsFullFetch(savedLayout: 1))
        #expect(!SyncPolicy.needsFullFetch(savedLayout: SyncPolicy.syncLayout))
    }

    @Test func recordNamesRoundTrip() {
        let id = teaUUID(5)
        #expect(SyncRecordName.cabinetTea(id).string == "tea.00000000-0000-0000-0000-000000000005")
        #expect(SyncRecordName.tasting(id).string == "tasting.00000000-0000-0000-0000-000000000005")
        #expect(SyncRecordName("tea.00000000-0000-0000-0000-000000000005") == .cabinetTea(id))
        #expect(SyncRecordName("tasting.00000000-0000-0000-0000-000000000005") == .tasting(id))
        #expect(SyncRecordName("tea.not-a-uuid") == nil)
        #expect(SyncRecordName.cabinetTea(id).type == .cabinetTea)
        #expect(SyncRecordName.tasting(id).type == .tasting)
        #expect(SyncRecordName.tombstone(.cabinetTea, id.uuidString).string.hasPrefix("tombstone.cabinetTea."))
    }

    @Test func theNewestEditWinsWhicheverSideMerges() {
        var mine = LeafData()
        var theirs = LeafData()
        mine.cabinet = [tea(1, name: "Old name", updated: teaDate(10, 1))]
        theirs.cabinet = [tea(1, name: "New name", updated: teaDate(10, 2), outOf: true)]
        mine.tastings = [note(2, rating: 5, updated: teaDate(10, 3))]
        theirs.tastings = [note(2, rating: 2, updated: teaDate(10, 2))]
        for merged in [mine.merged(with: theirs, now: now), theirs.merged(with: mine, now: now)] {
            #expect(merged.cabinet.map(\.name) == ["New name"])
            #expect(merged.cabinet.first?.isOutOf == true)
            #expect(merged.tastings.map(\.rating) == [5])
        }
    }

    @Test func aTieIsSettledTheSameWayOnBothSides() {
        var mine = LeafData()
        var theirs = LeafData()
        mine.cabinet = [tea(1, name: "Alpha", updated: teaDate(10, 1))]
        theirs.cabinet = [tea(1, name: "Beta", updated: teaDate(10, 1))]
        mine.tastings = [note(3, rating: 1, updated: teaDate(10, 1))]
        theirs.tastings = [note(3, rating: 4, updated: teaDate(10, 1))]
        let a = mine.merged(with: theirs, now: now)
        let b = theirs.merged(with: mine, now: now)
        #expect(a.cabinet == b.cabinet)
        #expect(a.tastings == b.tastings)
    }

    @Test func aDeletionWinsOnlyOverOlderEdits() {
        var mine = LeafData()
        mine.cabinet = [tea(1, name: "Edited before", updated: teaDate(10, 1)), tea(2, name: "Edited after", updated: teaDate(10, 5)), tea(3, name: "Same moment", updated: teaDate(10, 3))]
        mine.tastings = [note(4, rating: 3, updated: teaDate(10, 1))]
        var theirs = LeafData()
        theirs.tombstones = [
            Tombstone(kind: .cabinetTea, key: teaUUID(1).uuidString, deletedAt: teaDate(10, 3)),
            Tombstone(kind: .cabinetTea, key: teaUUID(2).uuidString, deletedAt: teaDate(10, 3)),
            Tombstone(kind: .cabinetTea, key: teaUUID(3).uuidString, deletedAt: teaDate(10, 3)),
            Tombstone(kind: .tasting, key: teaUUID(4).uuidString, deletedAt: teaDate(10, 3)),
        ]
        for merged in [mine.merged(with: theirs, now: now), theirs.merged(with: mine, now: now)] {
            // Ordered by addedAt (the same here), then id.
            #expect(merged.cabinet.map(\.name) == ["Edited after", "Same moment"])
            #expect(merged.tastings.isEmpty)
        }
        // A journal tombstone with the same key never touches a tea.
        var other = LeafData()
        other.tombstones = [Tombstone(kind: .journal, key: teaUUID(1).uuidString, deletedAt: teaDate(10, 9))]
        #expect(mine.merged(with: other, now: now).cabinet.count == 3)
    }

    @Test func changesAndRecordsCarryTheCabinetAndNotes() throws {
        var before = LeafData()
        before.cabinet = [tea(1, name: "Kept", updated: teaDate(10, 1)), tea(2, name: "Removed", updated: teaDate(10, 1))]
        var after = before
        after.cabinet.removeAll { $0.id == teaUUID(2) }
        after.cabinet[0].isOutOf = true
        after.cabinet[0].updatedAt = teaDate(10, 2)
        after.tastings = [note(3, rating: 4, updated: teaDate(10, 2))]
        let delta = SyncDiff.changes(from: before, to: after)
        #expect(delta.saves.contains(SyncRecordName.cabinetTea(teaUUID(1)).string))
        #expect(delta.saves.contains(SyncRecordName.tasting(teaUUID(3)).string))
        #expect(delta.deletes == [SyncRecordName.cabinetTea(teaUUID(2)).string])

        let records = SyncRecordMapper.records(from: after)
        let rebuilt = SyncRecordMapper.delta(from: records, basedOn: LeafData())
        #expect(rebuilt.cabinet == after.cabinet)
        #expect(rebuilt.tastings == after.tastings)
        let changed = SyncDiff.recordNames(in: after, changedSince: teaDate(10, 1, 13), includeUndated: false)
        #expect(Set(changed) == [SyncRecordName.cabinetTea(teaUUID(1)).string, SyncRecordName.tasting(teaUUID(3)).string])
    }
}
