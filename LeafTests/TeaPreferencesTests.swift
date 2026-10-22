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

    @Test func roundTripsAndToleratesUnknownValues() throws {
        let prefs = TeaPreferences(likedFamilies: [.oolong, .herbal], caffeine: .low, likedFlavours: ["floral"], familiesByTime: [.morning: [.green]])
        let data = try JSONEncoder().encode(prefs)
        #expect(try JSONDecoder().decode(TeaPreferences.self, from: data) == prefs)

        let newer = Data(#"{"likedFamilies":["kombucha"],"caffeine":"decaf","likedFlavours":["floral"]}"#.utf8)
        let decoded = try JSONDecoder().decode(TeaPreferences.self, from: newer)
        #expect(decoded.likedFamilies.isEmpty)
        #expect(decoded.caffeine == .any)
        #expect(decoded.likedFlavours == ["floral"])
    }
}
