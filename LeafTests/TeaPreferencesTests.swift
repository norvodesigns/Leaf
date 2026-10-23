import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct TeaPreferencesTests {
    @Test func emptyPreferencesChangeNothing() {
        for daypart in [Daypart.morning, .afternoon, .evening, .late] {
            let plain = TeaSuggester.ranked(daypart: daypart, season: .autumn, seed: 7, limit: 8)
            let withEmpty = TeaSuggester.ranked(daypart: daypart, season: .autumn, seed: 7, limit: 8, preferences: TeaPreferences())
            #expect(plain.map(\.id) == withEmpty.map(\.id))
        }
        #expect(TeaPreferences().isEmpty)
    }

    @Test func aLikedKindMovesUp() throws {
        let plain = TeaSuggester.ranked(daypart: .morning, season: .autumn, seed: 3, limit: 40)
        let liked = TeaSuggester.ranked(daypart: .morning, season: .autumn, seed: 3, limit: 40, preferences: TeaPreferences(likedFamilies: [.green]))
        let before = try #require(plain.firstIndex { $0.family == .green })
        let after = try #require(liked.firstIndex { $0.family == .green })
        #expect(after <= before)
        #expect(TeaPreferences(likedFamilies: [.green]).score(liked[after], at: .morning) > 0)
    }

    @Test func aKindForTheTimeOfDayLeadsThere() throws {
        let prefs = TeaPreferences(familiesByTime: [.evening: [.rooibos]])
        let evening = TeaSuggester.ranked(daypart: .evening, season: .winter, seed: 1, limit: 40, preferences: prefs)
        let index = try #require(evening.firstIndex { $0.family == .rooibos })
        #expect(index < 3)
        // Mornings are untouched.
        let morning = TeaSuggester.ranked(daypart: .morning, season: .winter, seed: 1, limit: 40, preferences: prefs)
        #expect(morning.map(\.id) == TeaSuggester.ranked(daypart: .morning, season: .winter, seed: 1, limit: 40).map(\.id))
    }

    @Test func theCaffeineChoiceIsALimit() {
        let none = TeaPreferences(caffeine: .none)
        let morning = TeaSuggester.ranked(daypart: .morning, season: .spring, limit: 20, preferences: none)
        #expect(!morning.isEmpty)
        #expect(morning.allSatisfy { $0.caffeine == .none })

        let mornings = TeaPreferences(caffeine: .morningsOnly)
        let afternoon = TeaSuggester.ranked(daypart: .afternoon, season: .spring, limit: 20, preferences: mornings)
        #expect(afternoon.allSatisfy { $0.caffeine == .none })
        let early = TeaSuggester.ranked(daypart: .morning, season: .spring, limit: 20, preferences: mornings)
        #expect(early.contains { $0.caffeine > .none })
    }

    @Test func aLikedKindNeverBreaksTheNightRule() {
        let prefs = TeaPreferences(likedFamilies: [.black])
        let late = TeaSuggester.ranked(daypart: .late, season: .autumn, limit: 20, preferences: prefs)
        #expect(late.allSatisfy { $0.caffeine == .none })
    }

    @Test func likedFlavoursLeanTowardTeasThatTasteOfThem() {
        let tea = TeaCatalog.earlGrey
        let citrus = TeaPreferences(likedFlavours: ["citrus"])
        #expect(citrus.score(tea, at: .morning) > 0)
        #expect(TeaPreferences(likedFlavours: ["smoky"]).score(tea, at: .morning) == 0)
    }

    @Test func everyFlavourChipFindsTeasThatTasteOfIt() {
        for aroma in TastingAroma.all {
            #expect(TeaCatalog.all.contains { TastingAroma.tea($0, tastesOf: aroma) }, "no tea tastes \(aroma)")
        }
        let tea = { (id: String) in TeaCatalog.tea(id: id)! }
        #expect(TastingAroma.tea(tea("english-breakfast"), tastesOf: "malty"))
        #expect(TastingAroma.tea(tea("lapsang-souchong"), tastesOf: "smoky"))
        #expect(TastingAroma.tea(tea("peppermint"), tastesOf: "minty"))
        #expect(TastingAroma.tea(tea("moroccan-mint"), tastesOf: "minty"))
        #expect(TastingAroma.tea(tea("genmaicha"), tastesOf: "nutty"))
        // A cue has to start a word: nutmeg is not nutty, and a peach is not a sweet pea.
        #expect(!TastingAroma.tea(tea("pumpkin-spice-chai"), tastesOf: "nutty"))
        #expect(!TastingAroma.tea(tea("oriental-beauty"), tastesOf: "grassy"))
        #expect(TeaPreferences(likedFlavours: ["malty"]).score(tea("english-breakfast"), at: .morning) > 0)
    }

    @Test func fiveLeavesLeadAndOneLeafFalls() throws {
        let plain = TeaSuggester.ranked(daypart: .afternoon, season: .autumn, seed: 5, limit: 60)
        let loved = try #require(plain.last { $0.caffeine == .none })
        let doubted = try #require(plain.first)
        var prefs = TeaPreferences()
        prefs.setRating(5, for: loved.id)
        prefs.setRating(1, for: doubted.id)
        let rated = TeaSuggester.ranked(daypart: .afternoon, season: .autumn, seed: 5, limit: 60, preferences: prefs)
        #expect(try #require(rated.firstIndex(of: loved)) < plain.firstIndex(of: loved)!)
        #expect(try #require(rated.firstIndex(of: doubted)) > 0)
        // Three leaves is neutral.
        #expect(TeaPreferences(ratings: [loved.id: 3]).score(loved, at: .afternoon) == 0)
    }

    @Test func ratingsAreClampedRemovedAndKeptApartFromLeanings() {
        var prefs = TeaPreferences(likedFamilies: [.green], ratings: ["sencha": 9, "rooibos": 0])
        #expect(prefs.rating(for: "sencha") == 5)
        #expect(prefs.rating(for: "rooibos") == 1)
        prefs.setRating(nil, for: "rooibos")
        #expect(prefs.rating(for: "rooibos") == nil)
        prefs.setRating(4, for: "")
        #expect(prefs.rating(for: "") == nil)

        #expect(prefs.hasLeanings)
        let cleared = prefs.leaningsCleared
        #expect(!cleared.hasLeanings && !cleared.isEmpty)
        #expect(cleared.rating(for: "sencha") == 5 && cleared.likedFamilies.isEmpty)
    }

    @Test func aTinsRatingWinsOverThePagesRating() {
        let prefs = TeaPreferences(ratings: ["sencha": 2, "rooibos": 4])
        let cabinet = [
            CabinetTea(catalogID: "sencha", name: "Sencha", family: .green, steepSeconds: 90, rating: 5),
            CabinetTea(catalogID: "rooibos", name: "Rooibos", family: .rooibos, steepSeconds: 360),
        ]
        #expect(TeaShelf.rating(for: "sencha", cabinet: cabinet, preferences: prefs) == 5)
        // A tin with no rating of its own leaves the page's.
        #expect(TeaShelf.rating(for: "rooibos", cabinet: cabinet, preferences: prefs) == 4)
        #expect(TeaShelf.rating(for: "chamomile", cabinet: cabinet, preferences: prefs) == nil)
        let merged = prefs.withRatings(from: cabinet)
        #expect(merged.rating(for: "sencha") == 5 && merged.rating(for: "rooibos") == 4)
    }

    @Test func roundTripsAndToleratesUnknownValues() throws {
        let prefs = TeaPreferences(likedFamilies: [.oolong, .herbal], caffeine: .low, likedFlavours: ["floral"], familiesByTime: [.morning: [.green]], ratings: ["keemun": 4])
        let data = try JSONEncoder().encode(prefs)
        #expect(try JSONDecoder().decode(TeaPreferences.self, from: data) == prefs)

        let newer = Data(#"{"likedFamilies":["kombucha"],"caffeine":"decaf","likedFlavours":["floral"]}"#.utf8)
        let decoded = try JSONDecoder().decode(TeaPreferences.self, from: newer)
        #expect(decoded.likedFamilies.isEmpty)
        #expect(decoded.caffeine == .any)
        #expect(decoded.likedFlavours == ["floral"])
        #expect(decoded.rating(for: "keemun") == nil)
        let rated = try JSONDecoder().decode(TeaPreferences.self, from: Data(#"{"ratings":{"keemun":7,"sencha":"lots"}}"#.utf8))
        #expect(rated.rating(for: "keemun") == nil && rated.isEmpty)
        let fine = try JSONDecoder().decode(TeaPreferences.self, from: Data(#"{"ratings":{"keemun":7}}"#.utf8))
        #expect(fine.rating(for: "keemun") == 5)
    }
}
