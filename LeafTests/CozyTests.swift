import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Fixtures

private var czCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func czDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    czCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func czBook(_ id: String, genres: [String] = [], themes: [String] = [], pages: Int = 300) -> Book {
    Book(id: id, title: "Book \(id)", author: "Author \(id)", pages: pages, genres: genres, themes: themes)
}

private func czFinished(_ book: Book, on date: Date) -> LibraryItem {
    LibraryItem(book: book, shelf: .finished, currentPage: book.pages, order: 0, startedAt: date.addingTimeInterval(-5 * 86_400), finishedAt: date)
}

/// A session with a stable id, so histories are the same every run.
private func czSession(_ start: Date, minutes: Double, tea: String? = nil, book: String = "any") -> ReadingSession {
    let hash = SeededGenerator.hash("\(start.timeIntervalSince1970)|\(minutes)|\(tea ?? "")|\(book)")
    let tail = String(format: "%012llx", hash & 0xFFFF_FFFF_FFFF)
    return ReadingSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-\(tail)")!,
        bookID: book, startedAt: start, seconds: minutes * 60, fromPage: 0, toPage: 10, teaID: tea
    )
}

private func czData(items: [LibraryItem] = [], sessions: [ReadingSession] = [], goal: Int? = nil, cupMinutes: Int = 25, readingDays: Set<Int> = Set(1...7), challenges: [ChallengeEnrollment] = []) -> LeafData {
    var data = LeafData()
    data.items = items
    data.sessions = sessions
    data.preferences.yearlyGoal = goal
    data.preferences.cupMinutes = cupMinutes
    data.preferences.readingDays = readingDays
    data.challenges = challenges
    return data
}

private func czProgress(_ id: String, _ data: LeafData, now: Date, year: Int? = nil, joined: Date? = nil) -> ChallengeProgress {
    let enrollment = ChallengeEnrollment(id: id, joinedAt: joined ?? now, year: year)
    return ChallengeEvaluator.progress(for: enrollment, data: data, now: now, calendar: czCalendar)
}

private func czTask(_ progress: ChallengeProgress, _ id: String) -> ChallengeTaskState? {
    progress.tasks.first { $0.id == id }
}

private let czNow = czDate(2026, 10, 18)

/// No weather at all, then every kind: the suggesters have to be good in both.
private let czWeathers: [CozyWeather?] = [nil] + CozyWeather.allCases.map { Optional($0) }

private func czIsKebab(_ text: String) -> Bool {
    !text.isEmpty && text.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" } && !text.hasPrefix("-") && !text.hasSuffix("-") && !text.contains("--")
}

/// User-facing copy rules: warm and calm. No exclamation marks, and typographic apostrophes only.
private func czCopyIsClean(_ text: String) -> Bool {
    !text.contains("!") && !text.contains("'")
}

// MARK: - Tea

struct CozyTeaTests {
    @Test func catalogIntegrity() {
        let teas = TeaCatalog.all
        #expect(teas.count >= 18)
        #expect(Set(teas.map(\.id)).count == teas.count)
        #expect(TeaCatalog.tea(id: "earl-grey") != nil)
        #expect(TeaCatalog.tea(id: "sencha") != nil)
        for family in TeaFamily.allCases { #expect(!TeaCatalog.teas(in: family).isEmpty, "no tea in \(family)") }
        for tea in teas {
            #expect(czIsKebab(tea.id), "\(tea.id)")
            #expect(!tea.name.isEmpty)
            #expect(!tea.notes.isEmpty && tea.notes.allSatisfy { !$0.isEmpty })
            #expect(!tea.blurb.isEmpty && tea.blurb.hasSuffix("."))
            #expect(!tea.seasons.isEmpty && !tea.dayparts.isEmpty && !tea.moods.isEmpty)
            #expect(Set(tea.seasons).count == tea.seasons.count && Set(tea.dayparts).count == tea.dayparts.count)
            #expect(CozyPalette.isKnown(tea.paletteToken), "\(tea.id) uses \(tea.paletteToken)")
            #expect(czCopyIsClean(tea.blurb) && czCopyIsClean(tea.name), "\(tea.id)")
        }
    }

    @Test func steepTimesAreSensibleForTheirFamily() {
        let ranges: [TeaFamily: ClosedRange<Int>] = [
            .green: 60...180, .black: 180...300, .oolong: 180...300, .herbal: 300...420,
            .white: 180...300, .rooibos: 300...420, .chai: 240...360, .matcha: 30...90,
        ]
        for tea in TeaCatalog.all {
            let range = ranges[tea.family]
            #expect(range?.contains(tea.steepSeconds) == true, "\(tea.id) steeps \(tea.steepSeconds)s")
        }
        #expect(TeaCatalog.tea(id: "sencha")?.steepSeconds == 120)
        #expect((180...300).contains(TeaCatalog.tea(id: "earl-grey")?.steepSeconds ?? 0))
    }

    @Test func temperaturesAgreeInBothScales() {
        for tea in TeaCatalog.all {
            #expect((60...100).contains(tea.celsius), "\(tea.id)")
            let exact = Double(tea.celsius) * 9 / 5 + 32
            #expect(abs(exact - Double(tea.fahrenheit)) <= 4, "\(tea.id): \(tea.celsius)C vs \(tea.fahrenheit)F")
        }
        // Delicate teas are brewed cooler than black ones.
        #expect((TeaCatalog.tea(id: "sencha")?.celsius ?? 100) < (TeaCatalog.tea(id: "english-breakfast")?.celsius ?? 0))
    }

    @Test func familyAndCaffeineAreConsistent() {
        for tea in TeaCatalog.all {
            switch tea.family {
            case .herbal, .rooibos: #expect(tea.caffeine == .none, "\(tea.id)")
            case .matcha: #expect(tea.caffeine == .high)
            case .green, .white: #expect(tea.caffeine <= .medium, "\(tea.id)")
            default: break
            }
        }
    }

    @Test func tagsObeyTheCaffeineRulesOfTheHour() {
        for tea in TeaCatalog.all {
            for daypart in tea.dayparts {
                #expect(tea.caffeine <= TeaSuggester.caffeineCap(for: daypart), "\(tea.id) is tagged for \(daypart)")
            }
        }
    }

    @Test func everySeasonAndDaypartHasAtLeastThreeTeas() {
        for season in Season.allCases { #expect(TeaCatalog.tagged(season: season).count >= 3, "\(season)") }
        for daypart in Daypart.allCases {
            #expect(TeaCatalog.tagged(daypart: daypart).count >= 3, "\(daypart) tagged")
            #expect(TeaSuggester.allowed(at: daypart).count >= 3, "\(daypart) allowed")
        }
    }

    @Test func lookupHandlesUnknownAndMissingIds() {
        #expect(TeaCatalog.tea(id: nil) == nil)
        #expect(TeaCatalog.tea(id: "made-up") == nil)
        #expect(TeaCatalog.tea(id: "matcha")?.family == .matcha)
        #expect(TeaCatalog.ids == TeaCatalog.all.map(\.id))
    }

    @Test func suggestionsAreDeterministic() {
        for daypart in Daypart.allCases {
            for season in Season.allCases {
                for weather in czWeathers {
                    let a = TeaSuggester.suggest(daypart: daypart, season: season, weather: weather, lastTeaID: "sencha", favoriteTeaID: "rooibos", seed: 42)
                    let b = TeaSuggester.suggest(daypart: daypart, season: season, weather: weather, lastTeaID: "sencha", favoriteTeaID: "rooibos", seed: 42)
                    #expect(a == b)
                }
            }
        }
    }

    @Test func noCaffeineAtNight() {
        for season in Season.allCases {
            for seed in UInt64(0)..<25 {
                for weather in czWeathers {
                    // Even a caffeinated favourite has to wait for morning.
                    for favorite in ["english-breakfast", "earl-grey", "matcha", nil] as [String?] {
                        for daypart in [Daypart.late, .smallHours] {
                            let tea = TeaSuggester.suggest(daypart: daypart, season: season, weather: weather, favoriteTeaID: favorite, seed: seed)
                            #expect(tea.caffeine == .none, "\(tea.id) at \(daypart)")
                        }
                        let evening = TeaSuggester.suggest(daypart: .evening, season: season, weather: weather, favoriteTeaID: favorite, seed: seed)
                        #expect(evening.caffeine <= .low, "\(evening.id) in the evening")
                    }
                }
            }
        }
    }

    @Test func oneInTheMorningIsHerbal() {
        // 01:00 is `late`, by the same clock the rest of the app uses.
        let hour = Daypart.of(czDate(2026, 3, 3, 1, 0), calendar: czCalendar)
        #expect(hour == .late)
        for seed in UInt64(0)..<100 {
            let tea = TeaSuggester.suggest(daypart: hour, season: .winter, seed: seed)
            #expect([TeaFamily.herbal, .rooibos].contains(tea.family), "\(tea.id)")
        }
    }

    @Test func morningsLeanOnCaffeine() {
        var caffeinated = 0
        for seed in UInt64(0)..<100 where TeaSuggester.suggest(daypart: .morning, season: .autumn, seed: seed).caffeine >= .medium { caffeinated += 1 }
        #expect(caffeinated >= 90)
    }

    @Test func neverRepeatsTheLastTea() {
        for daypart in Daypart.allCases {
            for season in Season.allCases {
                for seed in UInt64(0)..<30 {
                    let first = TeaSuggester.suggest(daypart: daypart, season: season, seed: seed)
                    let next = TeaSuggester.suggest(daypart: daypart, season: season, lastTeaID: first.id, favoriteTeaID: first.id, seed: seed)
                    #expect(next.id != first.id)
                }
            }
        }
    }

    @Test func aFavouriteIsNudgedButNeverForced() {
        func picks(favorite: String?) -> Int {
            (UInt64(0)..<300).filter { TeaSuggester.suggest(daypart: .teaTime, season: .autumn, favoriteTeaID: favorite, seed: $0).id == "genmaicha" }.count
        }
        let with = picks(favorite: "genmaicha")
        let without = picks(favorite: nil)
        #expect(with > without)
        #expect(with < 300)
        // A favourite that doesn't fit the hour is not forced on the reader.
        let wrong = (UInt64(0)..<100).filter { TeaSuggester.suggest(daypart: .morning, season: .winter, favoriteTeaID: "hibiscus", seed: $0).id == "hibiscus" }.count
        #expect(wrong < 100)
    }

    @Test func weatherShiftsTheChoice() {
        for seed in UInt64(0)..<60 {
            let cold = TeaSuggester.suggest(daypart: .afternoon, season: .winter, weather: .cold, seed: seed)
            #expect(cold.moods.contains(.warming), "\(cold.id)")
            let hot = TeaSuggester.suggest(daypart: .afternoon, season: .summer, weather: .hot, seed: seed)
            #expect(hot.moods.contains(.refreshing), "\(hot.id)")
            let rain = TeaSuggester.suggest(daypart: .teaTime, season: .autumn, weather: .rain, seed: seed)
            #expect(rain.moods.contains(.rainyDay) || rain.moods.contains(.warming) || rain.moods.contains(.cozy), "\(rain.id)")
        }
    }

    @Test func differentDaysCanGiveDifferentTeas() {
        let picks = Set((UInt64(0)..<60).map { TeaSuggester.suggest(daypart: .afternoon, season: .autumn, seed: $0).id })
        #expect(picks.count >= 3)
    }

    @Test func rankedListIsDistinctAndLeadsWithTheSuggestion() {
        let list = TeaSuggester.ranked(daypart: .evening, season: .winter, seed: 9, limit: 5)
        #expect(list.count == 5)
        #expect(Set(list.map(\.id)).count == 5)
        #expect(list.first == TeaSuggester.suggest(daypart: .evening, season: .winter, seed: 9))
        #expect(TeaSuggester.ranked(daypart: .evening, season: .winter, limit: 0).isEmpty)
        #expect(TeaSuggester.ranked(daypart: .late, season: .winter, limit: 100).count == TeaSuggester.allowed(at: .late).count)
    }

    @Test func steepSecondsFollowStrength() {
        for tea in TeaCatalog.all {
            let light = TeaSuggester.steepSeconds(for: tea, strength: .light)
            let regular = TeaSuggester.steepSeconds(for: tea, strength: .regular)
            let strong = TeaSuggester.steepSeconds(for: tea, strength: .strong)
            #expect(light <= regular && regular <= strong, "\(tea.id)")
            #expect(light < strong, "\(tea.id)")
            #expect(regular == tea.steepSeconds, "\(tea.id)")
            for value in [light, regular, strong] {
                #expect(value % 5 == 0 && (TeaSuggester.minimumSteepSeconds...TeaSuggester.maximumSteepSeconds).contains(value))
            }
        }
        let sencha = TeaCatalog.tea(id: "sencha")!
        #expect(TeaSuggester.steepSeconds(for: sencha, strength: .light) == 90)
        #expect(TeaSuggester.steepSeconds(for: sencha, strength: .strong) == 150)
        var huge = sencha
        huge.steepSeconds = 100_000
        #expect(TeaSuggester.steepSeconds(for: huge, strength: .strong) == TeaSuggester.maximumSteepSeconds)
        var zero = sencha
        zero.steepSeconds = 0
        #expect(TeaSuggester.steepSeconds(for: zero, strength: .light) == TeaSuggester.minimumSteepSeconds)
    }

    @Test func ritualPlansSteepThenReadThenStretch() {
        let tea = TeaCatalog.tea(id: "earl-grey")!
        let ritual = TeaRitual.plan(tea: tea, cupMinutes: 25)
        #expect(ritual.steepSeconds == 240)
        #expect(ritual.readSeconds == 1_500)
        #expect(ritual.breakSeconds == 300)
        #expect(ritual.goalSeconds == 1_500)
        #expect(ritual.totalSeconds == 240 + 1_500 + 300)
        #expect(ritual.stage(afterElapsed: -5) == .steeping)
        #expect(ritual.stage(afterElapsed: 239) == .steeping)
        #expect(ritual.stage(afterElapsed: 240) == .reading)
        #expect(ritual.stage(afterElapsed: 1_739) == .reading)
        #expect(ritual.stage(afterElapsed: 1_740) == .stretching)
        #expect(ritual.stage(afterElapsed: Double(ritual.totalSeconds)) == .done)
        #expect(ritual.readyAt(poured: czNow) == czNow.addingTimeInterval(240))
        #expect(TeaRitual.plan(tea: tea, strength: .strong).steepSeconds > ritual.steepSeconds)
    }

    @Test func ritualKeepsTheCupLengthSane() {
        let tea = TeaCatalog.earlGrey
        #expect(TeaRitual.plan(tea: tea, cupMinutes: 0).readSeconds == 60)
        #expect(TeaRitual.plan(tea: tea, cupMinutes: -10).readSeconds == 60)
        #expect(TeaRitual.plan(tea: tea, cupMinutes: 10_000_000).readSeconds == 480 * 60)
        for minutes in [1, 5, 25, 45, 90, 480] {
            let ritual = TeaRitual.plan(tea: tea, cupMinutes: minutes)
            #expect((60...600).contains(ritual.breakSeconds))
        }
        // The reader's own setting is what drives it.
        var preferences = ReadingPreferences()
        preferences.cupMinutes = 40
        #expect(TeaRitual.plan(tea: tea, cupMinutes: preferences.cupMinutes).goalSeconds == 2_400)
    }

    @Test func aSessionAdoptsTheRitual() {
        let tea = TeaCatalog.tea(id: "sencha")!
        let ritual = TeaRitual.plan(tea: tea, cupMinutes: 30)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let session = ritual.makeSession(id: id, bookID: "hobbit", startPage: 142, origin: .phone, now: czNow, ambienceID: "rain")
        #expect(session.id == id)
        #expect(session.teaID == "sencha")
        #expect(session.goalSeconds == 1_800)
        #expect(session.ambienceID == "rain")
        #expect(session.startPage == 142 && session.startedAt == czNow)
        #expect(session.remaining(at: czNow.addingTimeInterval(600)) == 1_200)
    }

    @Test func teaAndRitualRoundTripThroughJSON() throws {
        let tea = TeaCatalog.tea(id: "masala-chai")!
        let decodedTea = try JSONDecoder().decode(Tea.self, from: JSONEncoder().encode(tea))
        #expect(decodedTea == tea)
        let ritual = TeaRitual.plan(tea: tea, strength: .light, cupMinutes: 20)
        let decoded = try JSONDecoder().decode(TeaRitual.self, from: JSONEncoder().encode(ritual))
        #expect(decoded == ritual)
    }
}

// MARK: - Ambience

struct CozyAmbienceTests {
    @Test func idsAreExactlyTheSixTheAudioEngineKnows() {
        #expect(Set(AmbienceCatalog.ids) == ["rain", "fireplace", "kettle", "cafe", "library", "none"])
        #expect(AmbienceCatalog.ids.count == 6)
        #expect(AmbienceCatalog.sounds.map(\.id).contains("none") == false)
    }

    @Test func everyAmbienceHasAllItsFields() {
        for sound in AmbienceCatalog.all {
            #expect(!sound.name.isEmpty && !sound.blurb.isEmpty && sound.blurb.hasSuffix("."))
            #expect(czCopyIsClean(sound.name) && czCopyIsClean(sound.blurb), "\(sound.id)")
            #expect((0...1).contains(sound.defaultVolume))
            #expect(!sound.symbol.isEmpty && sound.symbol.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "." })
            if sound.isSilence {
                #expect(sound.defaultVolume == 0 && sound.id == "none")
            } else {
                #expect(sound.defaultVolume > 0 && sound.defaultVolume < 1)
                #expect(!sound.seasons.isEmpty && !sound.dayparts.isEmpty && !sound.weathers.isEmpty)
                #expect(sound.loopSafe)
            }
        }
        #expect(Set(AmbienceCatalog.all.map(\.name)).count == AmbienceCatalog.all.count)
        #expect(Set(AmbienceCatalog.all.map(\.symbol)).count == AmbienceCatalog.all.count)
    }

    @Test func everySeasonAndDaypartHasAtLeastTwoSounds() {
        for season in Season.allCases { #expect(AmbienceCatalog.tagged(season: season).count >= 2, "\(season)") }
        for daypart in Daypart.allCases { #expect(AmbienceCatalog.tagged(daypart: daypart).count >= 2, "\(daypart)") }
    }

    @Test func lookupTreatsNilAsSilence() {
        #expect(AmbienceCatalog.ambience(id: nil)?.isSilence == true)
        #expect(AmbienceCatalog.ambience(id: "rain")?.name == "Rain on the window")
        #expect(AmbienceCatalog.ambience(id: "thunder") == nil)
    }

    @Test func suggestionsAreDeterministicAndNeverSilent() {
        for daypart in Daypart.allCases {
            for season in Season.allCases {
                for seed in UInt64(0)..<20 {
                    let a = AmbienceSuggester.suggest(daypart: daypart, season: season, weather: .cloudy, seed: seed)
                    let b = AmbienceSuggester.suggest(daypart: daypart, season: season, weather: .cloudy, seed: seed)
                    #expect(a == b)
                    #expect(!a.isSilence)
                    #expect(a.dayparts.contains(daypart), "\(a.id) at \(daypart)")
                }
            }
        }
    }

    @Test func noCafeMurmurInTheSmallHours() {
        for season in Season.allCases {
            for seed in UInt64(0)..<40 {
                for weather in czWeathers {
                    for daypart in [Daypart.late, .smallHours, .evening] {
                        let sound = AmbienceSuggester.suggest(daypart: daypart, season: season, weather: weather, favoriteAmbienceID: "cafe", seed: seed)
                        #expect(sound.id != "cafe" && sound.id != "kettle", "\(sound.id) at \(daypart)")
                    }
                }
            }
        }
    }

    @Test func rainAndColdChangeTheChoice() {
        for seed in UInt64(0)..<40 {
            let rainy = AmbienceSuggester.suggest(daypart: .evening, season: .autumn, weather: .rain, seed: seed)
            #expect(rainy.weathers.contains(.rain))
            let snowy = AmbienceSuggester.suggest(daypart: .evening, season: .winter, weather: .snow, seed: seed)
            #expect(snowy.weathers.contains(.snow))
        }
    }

    @Test func neverRepeatsTheLastSoundAndNudgesTheFavourite() {
        for daypart in Daypart.allCases {
            for seed in UInt64(0)..<30 {
                let first = AmbienceSuggester.suggest(daypart: daypart, season: .autumn, seed: seed)
                let next = AmbienceSuggester.suggest(daypart: daypart, season: .autumn, lastAmbienceID: first.id, favoriteAmbienceID: first.id, seed: seed)
                #expect(next.id != first.id)
            }
        }
        let plain = (UInt64(0)..<300).filter { AmbienceSuggester.suggest(daypart: .afternoon, season: .spring, seed: $0).id == "library" }.count
        let loved = (UInt64(0)..<300).filter { AmbienceSuggester.suggest(daypart: .afternoon, season: .spring, favoriteAmbienceID: "library", seed: $0).id == "library" }.count
        #expect(loved > plain)
    }

    @Test func rankedListIsDistinct() {
        let list = AmbienceSuggester.ranked(daypart: .afternoon, season: .spring, seed: 3, limit: 10)
        #expect(Set(list.map(\.id)).count == list.count)
        #expect(list.first == AmbienceSuggester.suggest(daypart: .afternoon, season: .spring, seed: 3))
    }
}

// MARK: - Challenge catalog and windows

struct CozyChallengeCatalogTests {
    @Test func catalogHasTheRequiredChallenges() {
        let required = ["spooky-season", "winter-hearth", "spring-rain", "summer-porch", "yearly-goal", "hundred-cups", "pot-a-week", "seven-evenings", "cozy-bingo", "tea-tasting"]
        for id in required { #expect(ChallengeCatalog.challenge(id: id) != nil, "missing \(id)") }
        #expect(Set(ChallengeCatalog.ids).count == ChallengeCatalog.all.count)
        #expect(Set(ChallengeCatalog.all.map(\.kind)) == Set(ChallengeKind.allCases))
        #expect(ChallengeCatalog.challenge(id: "nope") == nil)
    }

    @Test func idsTasksAndStampsAreWellFormed() {
        var stampIDs = Set<String>()
        for challenge in ChallengeCatalog.all {
            #expect(czIsKebab(challenge.id))
            #expect(!challenge.title.isEmpty && !challenge.subtitle.isEmpty)
            #expect(CozyPalette.isKnown(challenge.paletteToken))
            #expect(!challenge.tasks.isEmpty)
            let taskIDs = challenge.tasks.map(\.id)
            #expect(Set(taskIDs).count == taskIDs.count, "\(challenge.id) task ids")
            #expect(taskIDs.allSatisfy(czIsKebab))
            #expect(challenge.stamps.contains { $0.unlock == .completion }, "\(challenge.id) needs a completion stamp")
            for stamp in challenge.stamps {
                #expect(stamp.id.hasPrefix(challenge.id + "."))
                #expect(czIsKebab(stamp.id.replacingOccurrences(of: ".", with: "-")))
                #expect(stampIDs.insert(stamp.id).inserted, "duplicate stamp \(stamp.id)")
                #expect((1...5).contains(stamp.rings))
                #expect(CozyPalette.isKnown(stamp.paletteToken))
                #expect(!stamp.name.isEmpty)
                if case .task(let id) = stamp.unlock { #expect(taskIDs.contains(id), "\(stamp.id) points at \(id)") }
                if case .lines = stamp.unlock { #expect(challenge.kind == .genreBingo) }
            }
        }
    }

    @Test func copyIsWarmAndClean() {
        for challenge in ChallengeCatalog.all {
            #expect(czCopyIsClean(challenge.title) && czCopyIsClean(challenge.subtitle), "\(challenge.id)")
            for task in challenge.tasks { #expect(czCopyIsClean(task.title), "\(task.id)") }
            for stamp in challenge.stamps { #expect(czCopyIsClean(stamp.name), "\(stamp.id)") }
        }
    }

    @Test func readathonsHaveSixPromptsAndBingoHasNine() {
        for id in ["spooky-season", "winter-hearth", "spring-rain", "summer-porch"] {
            let challenge = ChallengeCatalog.challenge(id: id)
            #expect(challenge?.tasks.count == 6)
            #expect(challenge?.kind == .seasonalReadathon)
            #expect(challenge?.stamps.count == 7)
        }
        #expect(ChallengeCatalog.cozyBingo.tasks.count == 9)
        #expect(ChallengeCatalog.bingoLines.count == 8)
        #expect(ChallengeCatalog.bingoLines.allSatisfy { $0.count == 3 && $0.allSatisfy { (0..<9).contains($0) } })
        #expect(ChallengeCatalog.potAWeek.tasks.count == 8)
        #expect(ChallengeCatalog.sevenEvenings.tasks.count == 7)
        #expect(ChallengeCatalog.teaTasting.tasks.count == 6)
    }

    @Test func everyPromptCanBeAnsweredByARealBook() {
        // A prompt that nothing could ever satisfy would make a challenge impossible.
        let pool = [
            czBook("a", genres: ["horror"], themes: ["ghosts"]), czBook("b", genres: ["mystery"], themes: ["gothic"], pages: 150),
            czBook("c", genres: ["fantasy"], themes: ["witches", "magic", "mythology"], pages: 500),
            czBook("d", genres: ["romance"], themes: ["love stories", "winter"]), czBook("e", genres: ["classics"], themes: ["letters & diaries"], pages: 450),
            czBook("f", genres: ["humor", "poetry"], themes: ["seaside & islands"]), czBook("g", genres: ["history"]),
        ]
        for challenge in ChallengeCatalog.all where challenge.rule == .bookPrompts {
            for task in challenge.tasks {
                guard case .book(let matcher) = task.goal else { Issue.record("\(task.id) is not a prompt"); continue }
                let anything = matcher.genres.isEmpty && matcher.themes.isEmpty && matcher.minPages == nil && matcher.maxPages == nil
                #expect(!anything, "\(challenge.id)/\(task.id) accepts every book")
                #expect(pool.contains { matcher.matches($0) } || matcher.minPages != nil || matcher.maxPages != nil || !matcher.genres.union(matcher.themes).isEmpty)
            }
        }
    }

    @Test func matcherHonoursGenresThemesAndLength() {
        let ghosts = ChallengeBookMatcher(themes: ["Ghosts"])
        #expect(ghosts.matches(czBook("a", themes: ["ghosts"])))
        #expect(!ghosts.matches(czBook("b", genres: ["ghosts"])))
        let short = ChallengeBookMatcher(maxPages: 200)
        #expect(short.matches(czBook("c", pages: 200)) && !short.matches(czBook("d", pages: 201)))
        let longMystery = ChallengeBookMatcher(genres: ["mystery"], minPages: 400)
        #expect(longMystery.matches(czBook("e", genres: ["mystery"], pages: 400)))
        #expect(!longMystery.matches(czBook("f", genres: ["mystery"], pages: 399)))
        #expect(!longMystery.matches(czBook("g", genres: ["fantasy"], pages: 600)))
        #expect(ChallengeBookMatcher().matches(czBook("h")))
        #expect(!ChallengeBookMatcher(genres: ["x"]).matches(czBook("i")))
    }

    @Test func seasonStartMonthsAgreeWithSeasonOf() {
        for season in Season.allCases {
            let first = czDate(2026, ChallengeWindow.firstMonth(of: season), 1, 0, 0)
            #expect(Season.of(first, calendar: czCalendar) == season)
            let before = first.addingTimeInterval(-1)
            #expect(Season.of(before, calendar: czCalendar) != season)
        }
    }

    @Test func seasonWindowsCoverAcrossTheYearBoundary() {
        let cal = czCalendar
        let autumn = ChallengeWindow.season(.autumn).span(year: 2026, joinedAt: czNow, calendar: cal)
        #expect(autumn.start == czDate(2026, 9, 1, 0) && autumn.end == czDate(2026, 12, 1, 0))
        let winter = ChallengeWindow.season(.winter).span(year: 2026, joinedAt: czNow, calendar: cal)
        #expect(winter.start == czDate(2026, 12, 1, 0) && winter.end == czDate(2027, 3, 1, 0))
        #expect(winter.contains(czDate(2026, 12, 31, 23, 59)) && winter.contains(czDate(2027, 1, 1, 0)) && winter.contains(czDate(2027, 2, 28, 23, 59)))
        #expect(!winter.contains(czDate(2027, 3, 1, 0)) && !winter.contains(czDate(2026, 11, 30, 23, 59)))
        // A leap year keeps its extra day inside winter.
        let leap = ChallengeWindow.season(.winter).span(year: 2027, joinedAt: czNow, calendar: cal)
        #expect(leap.end == czDate(2028, 3, 1, 0) && leap.contains(czDate(2028, 2, 29, 12)))
    }

    @Test func instanceYearBelongsToTheYearWinterStarted() {
        let cal = czCalendar
        let winter = ChallengeWindow.season(.winter)
        #expect(winter.instanceYear(containing: czDate(2026, 12, 25), calendar: cal) == 2026)
        #expect(winter.instanceYear(containing: czDate(2027, 1, 15), calendar: cal) == 2026)
        #expect(winter.instanceYear(containing: czDate(2027, 2, 28), calendar: cal) == 2026)
        #expect(ChallengeWindow.season(.autumn).instanceYear(containing: czDate(2026, 10, 1), calendar: cal) == 2026)
        #expect(ChallengeWindow.calendarYear.instanceYear(containing: czDate(2027, 1, 1), calendar: cal) == 2027)
    }

    @Test func everyDayIsInExactlyOneSeasonWindow() {
        let cal = czCalendar
        var day = czDate(2025, 1, 1, 6)
        let end = czDate(2028, 1, 1, 6)
        while day < end {
            let season = Season.of(day, calendar: cal)
            let window = ChallengeWindow.season(season)
            let year = window.instanceYear(containing: day, calendar: cal)
            #expect(window.span(year: year, joinedAt: day, calendar: cal).contains(day), "\(day)")
            for other in Season.allCases where other != season {
                let otherWindow = ChallengeWindow.season(other)
                let spans = (year - 1...year + 1).map { otherWindow.span(year: $0, joinedAt: day, calendar: cal) }
                #expect(!spans.contains { $0.contains(day) }, "\(day) is in \(season) and \(other)")
            }
            day = cal.date(byAdding: .day, value: 17, to: day)!
        }
    }

    @Test func calendarYearAndJoiningWindows() {
        let cal = czCalendar
        let year = ChallengeWindow.calendarYear.span(year: 2026, joinedAt: czNow, calendar: cal)
        #expect(year.contains(czDate(2026, 12, 31, 23, 59)) && !year.contains(czDate(2027, 1, 1, 0)) && year.contains(czDate(2026, 1, 1, 0)))
        let joined = czDate(2026, 10, 18, 15, 30)
        let eight = ChallengeWindow.sinceJoining(days: 56).span(year: 2026, joinedAt: joined, calendar: cal)
        #expect(eight.start == czDate(2026, 10, 18, 0) && eight.end == czDate(2026, 12, 13, 0))
        let open = ChallengeWindow.sinceJoining(days: nil).span(year: 2026, joinedAt: joined, calendar: cal)
        #expect(open.end == nil && open.contains(czDate(2090, 1, 1)) && !open.contains(czDate(2026, 10, 17, 23, 59)))
    }

    @Test func offersFollowTheSeason() {
        let cal = czCalendar
        let october = ChallengeEvaluator.availableChallenges(now: czDate(2026, 10, 18), calendar: cal)
        let ids = october.map(\.challenge.id)
        #expect(ids.contains("spooky-season") && !ids.contains("winter-hearth") && !ids.contains("spring-rain") && !ids.contains("summer-porch"))
        #expect(ids.contains("yearly-goal") && ids.contains("cozy-bingo") && ids.contains("hundred-cups") && ids.contains("tea-tasting"))
        let spooky = october.first { $0.challenge.id == "spooky-season" }
        #expect(spooky?.year == 2026 && spooky?.daysLeft == 44 && spooky?.isOpenNow == true && spooky?.isJoined == false)

        // Late November: winter is about to start and is offered early, after what is open now.
        let november = ChallengeEvaluator.availableChallenges(now: czDate(2026, 11, 25), calendar: cal)
        let winter = november.first { $0.challenge.id == "winter-hearth" }
        #expect(winter?.startsInDays == 6 && winter?.isOpenNow == false && winter?.year == 2026)
        let firstSoon = november.firstIndex { !$0.isOpenNow } ?? november.count
        #expect(november[..<firstSoon].allSatisfy(\.isOpenNow) && november[firstSoon...].allSatisfy { !$0.isOpenNow })
        #expect(ChallengeEvaluator.availableChallenges(now: czDate(2026, 11, 25), calendar: cal, lookaheadDays: 3).contains { $0.challenge.id == "winter-hearth" } == false)

        // The new year's goal is offered in late December, next to this year's.
        let december = ChallengeEvaluator.availableChallenges(now: czDate(2026, 12, 20), calendar: cal)
        let goals = december.filter { $0.challenge.id == "yearly-goal" }
        #expect(goals.map(\.year) == [2026, 2027] && goals.map(\.startsInDays) == [0, 12])

        // January is still the winter that started in December.
        let january = ChallengeEvaluator.availableChallenges(now: czDate(2027, 1, 10), calendar: cal)
        #expect(january.first { $0.challenge.id == "winter-hearth" }?.year == 2026)
        #expect(january.first { $0.challenge.id == "winter-hearth" }?.isOpenNow == true)
    }

    @Test func offersKnowWhatIsJoined() {
        let cal = czCalendar
        let enrolled = [
            ChallengeEnrollment(id: "spooky-season", joinedAt: czDate(2026, 9, 3), year: 2026),
            ChallengeEnrollment(id: "yearly-goal", joinedAt: czDate(2025, 2, 1), year: 2025),
            ChallengeEnrollment(id: "tea-tasting", joinedAt: czDate(2026, 5, 1), year: nil),
        ]
        let offers = ChallengeEvaluator.availableChallenges(now: czDate(2026, 10, 18), calendar: cal, enrolled: enrolled)
        func joined(_ id: String) -> Bool? { offers.first { $0.challenge.id == id }?.isJoined }
        #expect(joined("spooky-season") == true)
        #expect(joined("tea-tasting") == true)
        // Last year's yearly goal doesn't count as having joined this year's.
        #expect(joined("yearly-goal") == false)
        #expect(joined("cozy-bingo") == false)
        let offer = offers.first { $0.challenge.id == "cozy-bingo" }!
        let enrollment = ChallengeEvaluator.enrollment(for: offer, now: czNow)
        #expect(enrollment.id == "cozy-bingo" && enrollment.year == 2026 && enrollment.joinedAt == czNow)
    }
}

// MARK: - Evaluator

struct CozyChallengeEvaluatorTests {
    private func spooky(_ books: [(Book, Date)], now: Date = czDate(2026, 10, 18)) -> ChallengeProgress {
        czProgress("spooky-season", czData(items: books.map { czFinished($0.0, on: $0.1) }), now: now, year: 2026)
    }

    @Test func emptyDataIsCalmEverywhere() {
        let empty = czData()
        for challenge in ChallengeCatalog.all {
            for now in [czDate(2026, 1, 1), czDate(2026, 7, 4), czDate(2026, 10, 18), czDate(2026, 12, 31, 23, 59), czDate(2030, 1, 1)] {
                let progress = czProgress(challenge.id, empty, now: now)
                #expect(progress.fraction == 0 && progress.current == 0 && !progress.isComplete)
                #expect(progress.stamps.isEmpty && progress.completedTaskIDs.isEmpty)
                #expect(progress.tasks.count == challenge.tasks.count)
                #expect(progress.target > 0)
                #expect(czCopyIsClean(progress.statusLine) && !progress.statusLine.isEmpty)
            }
        }
    }

    @Test func legacyDataWithNoFieldsStillEvaluates() throws {
        let data = try JSONDecoder().decode(LeafData.self, from: Data("{}".utf8))
        for challenge in ChallengeCatalog.all {
            let progress = czProgress(challenge.id, data, now: czNow)
            #expect(progress.fraction == 0 && progress.status != .retired)
        }
    }

    @Test func promptsAreFilledByDistinctBooks() {
        let progress = spooky([
            (czBook("a", themes: ["ghosts"]), czDate(2026, 9, 10)),
            (czBook("b", themes: ["gothic"]), czDate(2026, 9, 20)),
            (czBook("c", genres: ["horror"], pages: 400), czDate(2026, 10, 2)),
        ])
        #expect(Set(progress.completedTaskIDs) == ["ghost", "gothic", "dark"])
        #expect(czTask(progress, "ghost")?.evidence == "a" && czTask(progress, "ghost")?.completedAt == czDate(2026, 9, 10))
        #expect(progress.current == 3 && progress.target == 6 && progress.fraction == 0.5)
        #expect(progress.status == .active && !progress.isComplete)
    }

    @Test func oneBookNeverAnswersTwoPrompts() {
        // This book fits ghost, gothic, creature, dark and short, yet fills just one.
        let everything = czBook("x", genres: ["horror"], themes: ["ghosts", "gothic", "monsters", "witches"], pages: 150)
        let progress = spooky([(everything, czDate(2026, 9, 10))])
        #expect(progress.current == 1 && progress.completedTaskIDs.count == 1)
        #expect(progress.completedTaskIDs == ["ghost"])
        let two = spooky([(everything, czDate(2026, 9, 10)), (czBook("y", themes: ["gothic"]), czDate(2026, 9, 11))])
        #expect(two.current == 2)
        #expect(Set(two.tasks.compactMap(\.evidence)).count == 2)
    }

    @Test func booksAreRearrangedToFillMorePrompts() {
        // "a" finished first and fits ghost or gothic; "b" fits only ghost. First-fit would leave gothic empty.
        let a = czBook("a", themes: ["ghosts", "gothic"])
        let b = czBook("b", themes: ["ghosts"])
        let progress = spooky([(a, czDate(2026, 9, 1)), (b, czDate(2026, 9, 2))])
        #expect(Set(progress.completedTaskIDs) == ["ghost", "gothic"])
        #expect(czTask(progress, "ghost")?.evidence == "b" && czTask(progress, "gothic")?.evidence == "a")
    }

    @Test func promptAnswersMatchTheBestPossible() {
        // Compare with brute force over every way of giving books to prompts, on random small libraries.
        var rng = SeededGenerator(seed: 2026)
        let genres = ["horror", "mystery", "fantasy", "romance"]
        let themes = ["ghosts", "gothic", "witches", "magic", "monsters", "vampires", "cozy"]
        let challenge = ChallengeCatalog.spookySeason
        let matchers = challenge.tasks.compactMap { task -> ChallengeBookMatcher? in
            if case .book(let matcher) = task.goal { return matcher }
            return nil
        }
        for round in 0..<40 {
            let count = Int(rng.next() % 6) + 1
            var books: [Book] = []
            for i in 0..<count {
                let g = genres.filter { _ in rng.next() % 4 == 0 }
                let t = themes.filter { _ in rng.next() % 3 == 0 }
                books.append(czBook("r\(round)b\(i)", genres: g, themes: t, pages: Int(rng.next() % 500) + 100))
            }
            func best(_ prompt: Int, _ used: Set<Int>) -> Int {
                guard prompt < matchers.count else { return 0 }
                var result = best(prompt + 1, used)
                for (index, book) in books.enumerated() where !used.contains(index) && matchers[prompt].matches(book) {
                    result = max(result, 1 + best(prompt + 1, used.union([index])))
                }
                return result
            }
            let progress = spooky(books.enumerated().map { ($0.element, czDate(2026, 9, 1 + $0.offset)) })
            #expect(progress.current == best(0, []), "round \(round)")
            let evidence = progress.tasks.compactMap(\.evidence)
            #expect(Set(evidence).count == evidence.count)
            for (task, matcher) in zip(progress.tasks, matchers) {
                if let id = task.evidence, let book = books.first(where: { $0.id == id }) { #expect(matcher.matches(book)) }
            }
        }
    }

    @Test func progressNeverGoesBackwardsAsBooksAreAdded() {
        let genres = ["horror", "mystery", "fantasy", "romance", "classics", "humor", "poetry", "history", "thriller", "travel", "self-help", "nature"]
        let themes = ["ghosts", "gothic", "witches", "magic", "monsters", "vampires", "cozy", "feel-good", "winter", "christmas", "letters & diaries",
                      "mythology", "rainy days", "england", "coming of age", "seaside & islands", "road trips", "humor", "fairy tales & folklore"]
        let ids = ["spooky-season", "winter-hearth", "spring-rain", "summer-porch", "cozy-bingo", "yearly-goal"]
        for seed in [1, 7, 99, 2026] as [UInt64] {
            var rng = SeededGenerator(seed: seed)
            var items: [LibraryItem] = []
            var previous: [String: (done: Set<String>, fraction: Double)] = [:]
            for n in 0..<40 {
                let g = genres.filter { _ in rng.next() % 6 == 0 }
                let t = themes.filter { _ in rng.next() % 6 == 0 }
                let book = czBook("s\(seed)n\(n)", genres: g, themes: t, pages: Int(rng.next() % 600) + 80)
                let day = czCalendar.date(byAdding: .day, value: Int(rng.next() % 420), to: czDate(2026, 1, 1))!
                items.append(czFinished(book, on: day))
                let data = czData(items: items, goal: 20)
                for id in ids {
                    let progress = czProgress(id, data, now: czDate(2027, 6, 1), year: 2026)
                    let done = Set(progress.completedTaskIDs)
                    if let before = previous[id] {
                        #expect(done.isSuperset(of: before.done), "\(id) lost a task at book \(n)")
                        #expect(progress.fraction >= before.fraction, "\(id) went down at book \(n)")
                    }
                    #expect((0...1).contains(progress.fraction))
                    previous[id] = (done, progress.fraction)
                }
            }
        }
    }

    @Test func onlyBooksInsideTheWindowCount() {
        let book = { (id: String) in czBook(id, themes: ["ghosts"]) }
        // Autumn 2026 is September 1 up to, not including, December 1.
        #expect(spooky([(book("a"), czDate(2026, 8, 31, 23, 59))]).current == 0)
        #expect(spooky([(book("a"), czDate(2026, 9, 1, 0, 0))]).current == 1)
        #expect(spooky([(book("a"), czDate(2026, 11, 30, 23, 59))]).current == 1)
        #expect(spooky([(book("a"), czDate(2026, 12, 1, 0, 0))]).current == 0)
        #expect(spooky([(book("a"), czDate(2025, 10, 5))]).current == 0)
    }

    @Test func onlyFinishedBooksCountEachOnce() {
        var reading = czFinished(czBook("r", themes: ["ghosts"]), on: czDate(2026, 10, 1))
        reading.shelf = .reading
        var paused = czFinished(czBook("p", themes: ["gothic"]), on: czDate(2026, 10, 1))
        paused.shelf = .paused
        var undated = czFinished(czBook("u", themes: ["witches"]), on: czDate(2026, 10, 1))
        undated.finishedAt = nil
        let twice = czBook("t", themes: ["monsters"])
        let data = czData(items: [reading, paused, undated, czFinished(twice, on: czDate(2026, 10, 3)), czFinished(twice, on: czDate(2026, 10, 9))])
        let progress = czProgress("spooky-season", data, now: czNow, year: 2026)
        #expect(progress.current == 1 && progress.completedTaskIDs == ["creature"])
        #expect(czTask(progress, "creature")?.completedAt == czDate(2026, 10, 3))
    }

    @Test func joiningLateStillCreditsEarlierReading() {
        let data = czData(items: [czFinished(czBook("a", themes: ["ghosts"]), on: czDate(2026, 10, 3))])
        let progress = czProgress("spooky-season", data, now: czDate(2026, 10, 20), joined: czDate(2026, 10, 20))
        #expect(progress.year == 2026 && progress.current == 1)
    }

    @Test func enrollmentYearDefaultsToTheInstanceTheReaderJoined() {
        let data = czData(items: [czFinished(czBook("a", themes: ["winter"]), on: czDate(2027, 1, 20))])
        let joined = czDate(2027, 1, 10)
        let implied = czProgress("winter-hearth", data, now: czDate(2027, 2, 1), joined: joined)
        #expect(implied.year == 2026 && implied.current == 1)
        #expect(implied.span.start == czDate(2026, 12, 1, 0) && implied.span.end == czDate(2027, 3, 1, 0))
        // An explicit year wins.
        let explicit = czProgress("winter-hearth", data, now: czDate(2027, 2, 1), year: 2025, joined: joined)
        #expect(explicit.year == 2025 && explicit.current == 0)
    }

    // MARK: Goals

    @Test func yearlyGoalMilestonesFollowThePreferenceGoal() {
        let books = (1...4).map { czFinished(czBook("g\($0)"), on: czDate(2026, $0 * 2, 10)) }
        let data = czData(items: books, goal: 4)
        let progress = czProgress("yearly-goal", data, now: czDate(2026, 10, 18), year: 2026)
        #expect(progress.target == 4 && progress.current == 4 && progress.isComplete && progress.status == .completed)
        #expect(progress.completedTaskIDs == ["quarter", "half", "three-quarters", "goal"])
        #expect(czTask(progress, "quarter")?.completedAt == czDate(2026, 2, 10))
        #expect(czTask(progress, "goal")?.completedAt == czDate(2026, 8, 10))
        #expect(progress.stamps.map(\.design.id) == ["yearly-goal.quarter-pot", "yearly-goal.half-pot", "yearly-goal.three-quarter-pot", "yearly-goal.full-pot"])
        #expect(progress.stamps.allSatisfy { $0.year == 2026 })

        let partial = czProgress("yearly-goal", czData(items: Array(books.prefix(2)), goal: 8), now: czNow, year: 2026)
        #expect(partial.target == 8 && partial.fraction == 0.25)
        #expect(partial.completedTaskIDs == ["quarter"])
    }

    @Test func yearlyGoalHandlesUnsetZeroNegativeAndHugeGoals() {
        let book = czFinished(czBook("a"), on: czDate(2026, 5, 5))
        #expect(czProgress("yearly-goal", czData(items: [book]), now: czNow, year: 2026).target == 12)
        #expect(czProgress("yearly-goal", czData(items: [book], goal: 0), now: czNow, year: 2026).target == 12)
        #expect(czProgress("yearly-goal", czData(items: [book], goal: -5), now: czNow, year: 2026).target == 12)
        let huge = czProgress("yearly-goal", czData(items: [book], goal: Int.max), now: czNow, year: 2026)
        #expect(huge.target == ChallengeRules.maximumYearlyTarget && huge.fraction < 0.001 && !huge.isComplete)
        let one = czProgress("yearly-goal", czData(items: [book], goal: 1), now: czNow, year: 2026)
        #expect(one.isComplete && one.fraction == 1)
        // Last year's books are last year's.
        let old = czFinished(czBook("old"), on: czDate(2025, 12, 31, 23, 59))
        #expect(czProgress("yearly-goal", czData(items: [old], goal: 5), now: czNow, year: 2026).current == 0)
        // Reading more than the goal doesn't push the bar past full.
        let many = (1...6).map { czFinished(czBook("m\($0)"), on: czDate(2026, 3, $0)) }
        let over = czProgress("yearly-goal", czData(items: many, goal: 3), now: czNow, year: 2026)
        #expect(over.current == 6 && over.fraction == 1 && over.statusLine == "3 of 3 books. Nicely done.")
    }

    @Test func cupsAreCountedWithTheAppsOwnCupRule() {
        let joined = czDate(2026, 10, 18, 9)
        func run(_ sessions: [ReadingSession], cupMinutes: Int = 25) -> ChallengeProgress {
            czProgress("hundred-cups", czData(sessions: sessions, cupMinutes: cupMinutes), now: czDate(2026, 12, 1), joined: joined)
        }
        let four = (0..<4).map { czSession(czDate(2026, 10, 19 + $0, 8), minutes: 25) }
        #expect(run(four).current == 4 && run(four).fraction == 0.04)
        #expect(run(four, cupMinutes: 20).current == 5)
        // Short sittings pool: five of five minutes is a cup.
        let shorts = (0..<5).map { czSession(czDate(2026, 10, 19, 8 + $0), minutes: 5) }
        #expect(run(shorts).current == 1)
        #expect(run(shorts).current == Cups.wholeCups(minutes: 25))
        // Reading from before the day of joining isn't counted.
        #expect(run([czSession(czDate(2026, 10, 17, 22), minutes: 100)]).current == 0)
        #expect(run([czSession(czDate(2026, 10, 18, 0, 5), minutes: 100)]).current == 4)
    }

    @Test func aForgottenTimerCannotHandOutCups() {
        let joined = czDate(2026, 10, 18)
        func cups(_ seconds: Double) -> Int {
            let session = ReadingSession(bookID: "a", startedAt: czDate(2026, 10, 19, 9), seconds: seconds, fromPage: 0, toPage: 1)
            return czProgress("hundred-cups", czData(sessions: [session]), now: czDate(2026, 11, 1), joined: joined).current
        }
        #expect(cups(100 * 3600) == 14)
        #expect(cups(.infinity) == 0)
        #expect(cups(.nan) == 0)
        #expect(cups(-3600) == 0)
        #expect(cups(0) == 0)
        #expect(cups(.greatestFiniteMagnitude) == 14)
    }

    @Test func hundredCupsMilestonesAndStamps() {
        let joined = czDate(2026, 1, 1, 9)
        let sessions = (0..<100).map { czSession(czCalendar.date(byAdding: .day, value: $0, to: czDate(2026, 1, 2, 8))!, minutes: 25) }
        let progress = czProgress("hundred-cups", czData(sessions: sessions), now: czDate(2026, 12, 1), joined: joined)
        #expect(progress.isComplete && progress.current == 100 && progress.fraction == 1)
        #expect(progress.daysLeft == nil)
        #expect(czTask(progress, "ten")?.completedAt == czDate(2026, 1, 11, 8).addingTimeInterval(25 * 60))
        #expect(progress.stamps.count == 4)
        let half = czProgress("hundred-cups", czData(sessions: Array(sessions.prefix(50))), now: czDate(2026, 12, 1), joined: joined)
        #expect(half.fraction == 0.5 && half.completedTaskIDs == ["ten", "quarter", "half"])
        #expect(half.stamps.map(\.design.id) == ["hundred-cups.saucer", "hundred-cups.teapot"])
    }

    @Test func aPotAWeekNeedsFourCupsInEachSevenDayBlock() {
        // Joined on Monday October 19. Week 1 runs to Sunday the 25th; week 2 to November 1; week 3 to November 8.
        let joined = czDate(2026, 10, 19, 9)
        let sessions = [
            czSession(czDate(2026, 10, 20, 8), minutes: 100),
            czSession(czDate(2026, 10, 27, 8), minutes: 75),
            czSession(czDate(2026, 11, 3, 8), minutes: 50), czSession(czDate(2026, 11, 8, 8), minutes: 50),
            czSession(czDate(2026, 12, 14, 8), minutes: 400),
        ]
        let progress = czProgress("pot-a-week", czData(sessions: sessions), now: czDate(2026, 11, 20), joined: joined)
        #expect(progress.completedTaskIDs == ["week-1", "week-3"])
        #expect(progress.current == 2 && progress.target == 8 && progress.fraction == 0.25)
        #expect(czTask(progress, "week-3")?.completedAt == czDate(2026, 11, 8, 8).addingTimeInterval(50 * 60))
        // December 14 is day 56: the window has closed.
        #expect(progress.span.end == czDate(2026, 12, 14, 0))
        #expect(progress.stamps.isEmpty)
        #expect(progress.daysLeft == 24)
    }

    @Test func aFullEightWeeksEarnsEveryStamp() {
        let joined = czDate(2026, 10, 19, 9)
        let sessions = (0..<8).map { czSession(czCalendar.date(byAdding: .day, value: $0 * 7 + 2, to: czDate(2026, 10, 19, 8))!, minutes: 100) }
        let progress = czProgress("pot-a-week", czData(sessions: sessions), now: czDate(2026, 12, 20), joined: joined)
        #expect(progress.isComplete && progress.status == .completed)
        #expect(progress.stamps.map(\.design.id) == ["pot-a-week.warm-pot", "pot-a-week.steeped", "pot-a-week.well-steeped", "pot-a-week.every-week"])
    }

    // MARK: Streak and tea

    private func evening(_ month: Int, _ day: Int, _ hour: Int = 20, _ minute: Int = 0, minutes: Double = 20) -> ReadingSession {
        czSession(czDate(2026, month, day, hour, minute), minutes: minutes)
    }

    @Test func sevenEveningsInARowCompleteTheStreak() {
        let sessions = (19...25).map { evening(10, $0) }
        let progress = czProgress("seven-evenings", czData(sessions: sessions), now: czDate(2026, 10, 26), joined: czDate(2026, 10, 18, 9))
        #expect(progress.isComplete && progress.current == 7)
        #expect(czTask(progress, "evenings-3")?.completedAt == czDate(2026, 10, 21, 20))
        #expect(progress.stamps.map(\.design.id) == ["seven-evenings.three-lamps", "seven-evenings.five-lamps", "seven-evenings.lamplighter"])
        let six = czProgress("seven-evenings", czData(sessions: Array(sessions.prefix(6))), now: czDate(2026, 10, 26), joined: czDate(2026, 10, 18, 9))
        #expect(!six.isComplete && six.current == 6 && six.completedTaskIDs.count == 6)
    }

    @Test func aMissedScheduledEveningBreaksTheRun() {
        let sessions = [evening(10, 19), evening(10, 20), evening(10, 21), evening(10, 23), evening(10, 24)]
        let progress = czProgress("seven-evenings", czData(sessions: sessions), now: czDate(2026, 10, 26), joined: czDate(2026, 10, 18))
        #expect(progress.current == 3)
    }

    @Test func restDaysDoNotBreakTheRun() {
        // Monday to Friday reading days (Sunday is 1). Wed-Thu-Fri, then Mon-Tue after a weekend of rest.
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let sessions = [evening(10, 21), evening(10, 22), evening(10, 23), evening(10, 26), evening(10, 27)]
        let kind = czProgress("seven-evenings", czData(sessions: sessions, readingDays: weekdays), now: czDate(2026, 10, 28), joined: czDate(2026, 10, 18))
        #expect(kind.current == 5)
        let strict = czProgress("seven-evenings", czData(sessions: sessions), now: czDate(2026, 10, 28), joined: czDate(2026, 10, 18))
        #expect(strict.current == 3)
        // A missed Friday still counts as a miss.
        let missed = [evening(10, 21), evening(10, 22), evening(10, 26), evening(10, 27)]
        #expect(czProgress("seven-evenings", czData(sessions: missed, readingDays: weekdays), now: czDate(2026, 10, 28), joined: czDate(2026, 10, 18)).current == 2)
    }

    @Test func onlyRealEveningSittingsMakeAnEvening() {
        let joined = czDate(2026, 10, 18)
        func current(_ sessions: [ReadingSession]) -> Int {
            czProgress("seven-evenings", czData(sessions: sessions), now: czDate(2026, 10, 30), joined: joined).current
        }
        #expect(current([evening(10, 19, 9)]) == 0)
        #expect(current([evening(10, 19, 20, 0, minutes: 4)]) == 0)
        #expect(current([evening(10, 19, 20, 0, minutes: 5)]) == 1)
        #expect(current([evening(10, 19, 17, 29)]) == 0)
        #expect(current([evening(10, 19, 17, 30)]) == 1)
        #expect(current([evening(10, 19, 22, 59)]) == 1)
        // Still up after midnight: 00:30 belongs to the evening before, and 03:00 is nobody's evening.
        #expect(current([evening(10, 18, 21), evening(10, 20, 0, 30), evening(10, 20, 21)]) == 3)
        #expect(current([evening(10, 20, 3, 0)]) == 0)
        // Two sittings on one evening are one evening.
        #expect(current([evening(10, 19, 19), evening(10, 19, 21)]) == 1)
    }

    @Test func streakIgnoresEveningsBeforeJoining() {
        let sessions = (10...17).map { evening(10, $0) }
        let progress = czProgress("seven-evenings", czData(sessions: sessions), now: czDate(2026, 10, 25), joined: czDate(2026, 10, 18))
        #expect(progress.current == 0)
    }

    @Test func teaTastingCountsDifferentKnownTeas() {
        let sessions = [
            czSession(czDate(2026, 10, 19, 9), minutes: 20, tea: "sencha"),
            czSession(czDate(2026, 10, 20, 9), minutes: 20, tea: "sencha"),
            czSession(czDate(2026, 10, 21, 9), minutes: 20, tea: "earl-grey"),
            czSession(czDate(2026, 10, 22, 9), minutes: 20, tea: "not-a-tea"),
            czSession(czDate(2026, 10, 23, 9), minutes: 3, tea: "matcha"),
            czSession(czDate(2026, 10, 24, 9), minutes: 20, tea: nil),
            czSession(czDate(2026, 10, 25, 9), minutes: 20, tea: "chamomile"),
        ]
        let progress = czProgress("tea-tasting", czData(sessions: sessions), now: czDate(2026, 11, 1), joined: czDate(2026, 10, 18))
        #expect(progress.current == 3 && progress.completedTaskIDs == ["tea-1", "tea-2", "tea-3"])
        #expect(czTask(progress, "tea-1")?.evidence == "sencha" && czTask(progress, "tea-3")?.evidence == "chamomile")
        #expect(progress.stamps.map(\.design.id) == ["tea-tasting.curious-sip"])
        #expect(progress.daysLeft == nil)
    }

    @Test func sixDifferentTeasCompleteTheTasting() {
        let ids = ["sencha", "earl-grey", "chamomile", "rooibos", "masala-chai", "hojicha", "matcha"]
        let sessions = ids.enumerated().map { czSession(czDate(2026, 10, 19 + $0.offset, 9), minutes: 15, tea: $0.element) }
        let progress = czProgress("tea-tasting", czData(sessions: sessions), now: czDate(2026, 11, 1), joined: czDate(2026, 10, 18))
        #expect(progress.isComplete && progress.current == 6 && progress.fraction == 1)
        #expect(progress.stamps.map(\.design.id) == ["tea-tasting.curious-sip", "tea-tasting.tasting-flight", "tea-tasting.tea-taster"])
    }

    // MARK: Bingo

    private func bingoBooks() -> [Book] {
        [
            czBook("cozy", themes: ["cozy"]), czBook("mystery", genres: ["mystery"]), czBook("fantasy", genres: ["fantasy"]),
            czBook("romance", genres: ["romance"]), czBook("classic", genres: ["classics"]), czBook("horror", genres: ["horror"]),
            czBook("history", genres: ["history"]), czBook("funny", genres: ["humor"]), czBook("poetry", genres: ["poetry"]),
        ]
    }

    @Test func bingoLinesEarnTheirStamps() {
        let books = bingoBooks()
        let dates = (0..<9).map { czDate(2026, 3, 1 + $0 * 5) }
        func progress(_ count: Int) -> ChallengeProgress {
            let items = (0..<count).map { czFinished(books[$0], on: dates[$0]) }
            return czProgress("cozy-bingo", czData(items: items), now: czDate(2026, 12, 1), year: 2026)
        }
        #expect(progress(2).stamps.isEmpty)
        let row = progress(3)
        #expect(row.stamps.map(\.design.id) == ["cozy-bingo.first-line"] && row.stamps.first?.earnedAt == dates[2])
        #expect(progress(6).stamps.count == 1)
        let full = progress(9)
        #expect(full.isComplete && full.current == 9)
        // Lines finish at squares 3, 6, 7 (a column and a diagonal), 8 and 9; the third line lands with the seventh book.
        let byID = Dictionary(uniqueKeysWithValues: full.stamps.map { ($0.design.id, $0.earnedAt) })
        #expect(byID["cozy-bingo.first-line"] == dates[2] && byID["cozy-bingo.three-lines"] == dates[6] && byID["cozy-bingo.full-card"] == dates[8])
    }

    @Test func aBingoBookFillsOnlyOneSquare() {
        // A cozy mystery fits two squares but fills one; a second book is needed for the other.
        let cozyMystery = czBook("cm", genres: ["mystery"], themes: ["cozy"])
        let one = czProgress("cozy-bingo", czData(items: [czFinished(cozyMystery, on: czDate(2026, 4, 1))]), now: czNow, year: 2026)
        #expect(one.current == 1)
        let two = czProgress("cozy-bingo", czData(items: [czFinished(cozyMystery, on: czDate(2026, 4, 1)), czFinished(czBook("m2", genres: ["mystery"]), on: czDate(2026, 4, 2))]), now: czNow, year: 2026)
        #expect(Set(two.completedTaskIDs) == ["cozy", "whodunit"])
    }

    // MARK: Status

    @Test func statusLinesAreCalmAndCorrect() {
        let book = czFinished(czBook("a", themes: ["ghosts"]), on: czDate(2026, 10, 2))
        let data = czData(items: [book])

        let upcoming = czProgress("spooky-season", data, now: czDate(2026, 8, 1), year: 2026)
        #expect(upcoming.status == .upcoming && upcoming.statusLine == "Starts in 31 days.")
        #expect(czProgress("spooky-season", data, now: czDate(2026, 8, 31, 12), year: 2026).statusLine == "Starts tomorrow.")

        let active = czProgress("spooky-season", data, now: czDate(2026, 10, 18), year: 2026)
        #expect(active.status == .active && active.daysLeft == 44 && active.statusLine == "1 of 6 prompts. 44 days left.")
        let lastDay = czProgress("spooky-season", data, now: czDate(2026, 11, 30, 22), year: 2026)
        #expect(lastDay.daysLeft == 1 && lastDay.statusLine == "1 of 6 prompts. Last day.")

        let ended = czProgress("spooky-season", data, now: czDate(2026, 12, 1, 0, 0), year: 2026)
        #expect(ended.status == .ended && ended.daysLeft == 0 && ended.statusLine == "Ended at 1 of 6 prompts. Every page counted.")

        let open = czProgress("tea-tasting", czData(), now: czNow)
        #expect(open.status == .active && open.daysLeft == nil && open.statusLine == "0 of 6 teas.")
    }

    @Test func aFinishedChallengeStaysCompleteAfterTheWindowCloses() {
        let books = [("a", ["ghosts"]), ("b", ["gothic"]), ("c", ["witches"]), ("d", ["monsters"]), ("e", ["horror-x"])]
        var items = books.enumerated().map { czFinished(czBook($0.element.0, themes: $0.element.1), on: czDate(2026, 9, 2 + $0.offset)) }
        items.append(czFinished(czBook("f", genres: ["horror"], pages: 120), on: czDate(2026, 10, 1)))
        items.append(czFinished(czBook("g", pages: 90), on: czDate(2026, 10, 2)))
        let during = czProgress("spooky-season", czData(items: items), now: czDate(2026, 11, 1), year: 2026)
        let after = czProgress("spooky-season", czData(items: items), now: czDate(2027, 5, 1), year: 2026)
        #expect(during.isComplete && after.isComplete && during.status == .completed && after.status == .completed)
        #expect(during.stamps == after.stamps)
        #expect(during.stamps.count == 7 && during.stamps.last?.design.id == "spooky-season.harvest-moon")
    }

    @Test func unknownChallengesAreRetiredNotCrashes() {
        let progress = czProgress("long-gone", czData(), now: czNow, year: 2024)
        #expect(progress.status == .retired && progress.tasks.isEmpty && progress.stamps.isEmpty && progress.fraction == 0)
        #expect(progress.challengeID == "long-gone" && progress.year == 2024)
        #expect(!progress.statusLine.isEmpty)
    }

    @Test func evaluationIsRepeatable() {
        let items = bingoBooks().enumerated().map { czFinished($0.element, on: czDate(2026, 2, 1 + $0.offset)) }
        let sessions = (0..<30).map { czSession(czDate(2026, 10, 1 + $0 % 28, 8 + $0 % 14), minutes: Double(10 + $0), tea: ["sencha", "rooibos", nil][$0 % 3]) }
        let data = czData(items: items, sessions: sessions)
        for challenge in ChallengeCatalog.all {
            let a = czProgress(challenge.id, data, now: czNow, year: 2026, joined: czDate(2026, 10, 1))
            let b = czProgress(challenge.id, data, now: czNow, year: 2026, joined: czDate(2026, 10, 1))
            #expect(a == b)
        }
        // Order of the data doesn't matter either.
        let shuffled = czData(items: items.reversed(), sessions: sessions.reversed())
        for challenge in ChallengeCatalog.all {
            #expect(czProgress(challenge.id, data, now: czNow, year: 2026, joined: czDate(2026, 10, 1)) == czProgress(challenge.id, shuffled, now: czNow, year: 2026, joined: czDate(2026, 10, 1)))
        }
    }

    @Test func allProgressFollowsEnrollmentOrder() {
        let enrollments = [ChallengeEnrollment(id: "tea-tasting", joinedAt: czNow, year: nil), ChallengeEnrollment(id: "spooky-season", joinedAt: czNow, year: 2026)]
        let data = czData(challenges: enrollments)
        let all = ChallengeEvaluator.allProgress(data: data, now: czNow, calendar: czCalendar)
        #expect(all.map(\.challengeID) == ["tea-tasting", "spooky-season"])
    }

    @Test func hundredsOfSessionsAreFast() {
        let sessions = (0..<3_000).map { czSession(czCalendar.date(byAdding: .minute, value: $0 * 37, to: czDate(2026, 1, 1))!, minutes: 12, tea: "sencha") }
        let items = (0..<400).map { czFinished(czBook("p\($0)", genres: ["fantasy"], themes: ["magic"]), on: czCalendar.date(byAdding: .hour, value: $0 * 20, to: czDate(2026, 1, 1))!) }
        let data = czData(items: items, sessions: sessions, goal: 50)
        for challenge in ChallengeCatalog.all {
            let progress = czProgress(challenge.id, data, now: czDate(2026, 12, 1), year: 2026, joined: czDate(2026, 1, 1))
            #expect((0...1).contains(progress.fraction))
        }
    }
}

// MARK: - Stamps

struct CozyStampTests {
    private func sessions(onDays days: [Int], month: Int = 9, year: Int = 2026, minutes: Double = 20) -> [ReadingSession] {
        days.map { czSession(czDate(year, month, $0, 8), minutes: minutes) }
    }

    private func ledger(_ data: LeafData, now: Date = czDate(2026, 12, 31)) -> [StampEntry] {
        StampLedger.entries(data: data, now: now, calendar: czCalendar)
    }

    @Test func emptyHistoryHasNoStamps() {
        #expect(ledger(czData()).isEmpty)
        #expect(ledger(czData(challenges: [ChallengeEnrollment(id: "spooky-season", joinedAt: czNow, year: 2026)])).isEmpty)
    }

    @Test func everyFinishedBookLeavesARing() {
        let small = czBook("small", pages: 120)
        let medium = czBook("medium", pages: 300)
        let big = czBook("big", pages: 900)
        var reading = czFinished(czBook("r"), on: czDate(2026, 5, 1))
        reading.shelf = .reading
        var undated = czFinished(czBook("u"), on: czDate(2026, 5, 1))
        undated.finishedAt = nil
        let items = [czFinished(small, on: czDate(2026, 2, 1)), czFinished(medium, on: czDate(2026, 3, 1)), czFinished(big, on: czDate(2026, 4, 1)), reading, undated]
        let entries = ledger(czData(items: items)).filter { $0.source == .book }
        #expect(entries.map(\.id) == ["book.small", "book.medium", "book.big"])
        #expect(entries.map(\.rings) == [3, 4, 5])
        #expect(entries.map(\.earnedAt) == [czDate(2026, 2, 1), czDate(2026, 3, 1), czDate(2026, 4, 1)])
        #expect(entries[0].name == "Book small" && entries[0].detail == "Author small" && entries[0].bookID == "small")
        #expect(entries.allSatisfy { CozyPalette.isKnown($0.paletteToken) })
        // The same book finished twice is still one stamp, dated the first time.
        let twice = ledger(czData(items: [czFinished(small, on: czDate(2026, 8, 1)), czFinished(small, on: czDate(2026, 2, 1))])).filter { $0.source == .book }
        #expect(twice.count == 1 && twice[0].earnedAt == czDate(2026, 2, 1))
    }

    @Test func aMonthStampNeedsSevenReadingDaysAndAFinishedMonth() {
        let seven = czData(sessions: sessions(onDays: [1, 3, 5, 8, 10, 12, 20]))
        let entries = ledger(seven, now: czDate(2026, 10, 1, 0, 0)).filter { $0.source == .month }
        #expect(entries.count == 1)
        #expect(entries[0].id == "month.2026-09" && entries[0].name == "September 2026" && entries[0].detail == "7 days of reading")
        #expect(entries[0].rings == 1 && entries[0].earnedAt == czDate(2026, 10, 1, 0, 0) && entries[0].year == 2026)
        #expect(entries[0].paletteToken == CozyPalette.token(for: .autumn))
        // Pressed only once the month is over.
        #expect(ledger(seven, now: czDate(2026, 9, 30, 23, 59)).filter { $0.source == .month }.isEmpty)
        // Six days is a lovely month, but not a stamp.
        #expect(ledger(czData(sessions: sessions(onDays: [1, 3, 5, 8, 10, 12])), now: czDate(2026, 11, 1)).filter { $0.source == .month }.isEmpty)
    }

    @Test func monthRingsGrowWithDaysRead() {
        func rings(_ days: Int) -> Int? {
            let data = czData(sessions: sessions(onDays: Array(1...days)))
            return ledger(data, now: czDate(2026, 11, 1)).first { $0.source == .month }?.rings
        }
        #expect(rings(6) == nil)
        #expect(rings(7) == 1 && rings(13) == 1)
        #expect(rings(14) == 2 && rings(20) == 2)
        #expect(rings(21) == 3 && rings(27) == 3)
        #expect(rings(28) == 4 && rings(30) == 4)
    }

    @Test func aReadingDayNeedsFiveMinutesAndShortSittingsAdd() {
        // Eight days with only two minutes each, plus one day with three short sittings that add up.
        let faint = (1...8).map { czSession(czDate(2026, 9, $0, 8), minutes: 2) }
        #expect(ledger(czData(sessions: faint), now: czDate(2026, 11, 1)).filter { $0.source == .month }.isEmpty)
        let pooled = (1...7).flatMap { day in (0..<3).map { czSession(czDate(2026, 9, day, 8 + $0), minutes: 2) } }
        #expect(ledger(czData(sessions: pooled), now: czDate(2026, 11, 1)).filter { $0.source == .month }.count == 1)
    }

    @Test func decemberStampsLandInJanuary() {
        let data = czData(sessions: sessions(onDays: Array(1...10), month: 12))
        let entry = ledger(data, now: czDate(2027, 1, 2)).first { $0.source == .month }
        #expect(entry?.id == "month.2026-12" && entry?.earnedAt == czDate(2027, 1, 1, 0, 0))
        #expect(ledger(data, now: czDate(2026, 12, 31)).filter { $0.source == .month }.isEmpty)
    }

    @Test func challengeStampsAppearOnceEarnedAndWithYearInTheId() {
        let items = [czFinished(czBook("g", themes: ["ghosts"]), on: czDate(2026, 9, 12)), czFinished(czBook("h", genres: ["horror"]), on: czDate(2026, 9, 20))]
        let enrolled = czData(items: items, challenges: [ChallengeEnrollment(id: "spooky-season", joinedAt: czDate(2026, 9, 1), year: 2026)])
        let entries = ledger(enrolled, now: czDate(2026, 10, 18)).filter { $0.source == .challenge }
        #expect(entries.map(\.id) == ["challenge.spooky-season.lantern@2026", "challenge.spooky-season.moth@2026"])
        #expect(entries.map(\.earnedAt) == [czDate(2026, 9, 12), czDate(2026, 9, 20)])
        #expect(entries[0].detail == "Spooky Season 2026" && entries[0].challengeID == "spooky-season" && entries[0].year == 2026)
        // Not joined, no challenge stamps; the book stamps are still there.
        let unjoined = ledger(czData(items: items), now: czDate(2026, 10, 18))
        #expect(unjoined.filter { $0.source == .challenge }.isEmpty && unjoined.filter { $0.source == .book }.count == 2)
    }

    @Test func stampsAreStableWhenReevaluated() {
        let items = (1...9).map { czFinished(czBook("b\($0)", genres: ["mystery"], themes: ["ghosts"], pages: 100 + $0 * 80), on: czDate(2026, 3, $0 * 3)) }
        var all = sessions(onDays: Array(1...12), month: 3)
        all += sessions(onDays: Array(1...9), month: 4)
        let data = czData(items: items, sessions: all, goal: 6, challenges: [
            ChallengeEnrollment(id: "yearly-goal", joinedAt: czDate(2026, 1, 1), year: 2026),
            ChallengeEnrollment(id: "cozy-bingo", joinedAt: czDate(2026, 1, 1), year: 2026),
            ChallengeEnrollment(id: "spring-rain", joinedAt: czDate(2026, 3, 1), year: 2026),
        ])
        let first = ledger(data, now: czDate(2026, 8, 1))
        #expect(first == ledger(data, now: czDate(2026, 8, 1)))
        // Time passing with no new reading never changes or removes an earlier stamp.
        let later = ledger(data, now: czDate(2028, 1, 1))
        for entry in first { #expect(later.contains(entry), "\(entry.id) changed") }
        #expect(first.count >= 11)
        // Ids are unique and the book is in date order.
        #expect(Set(first.map(\.id)).count == first.count)
        #expect(first.map(\.earnedAt) == first.map(\.earnedAt).sorted())
        // The order of the saved data makes no difference.
        let flipped = czData(items: items.reversed(), sessions: all.reversed(), goal: 6, challenges: data.challenges.reversed())
        #expect(ledger(flipped, now: czDate(2026, 8, 1)) == first)
    }

    @Test func morereadingOnlyAddsStamps() {
        var items: [LibraryItem] = []
        var seen = Set<String>()
        for n in 1...12 {
            items.append(czFinished(czBook("n\(n)", themes: n % 2 == 0 ? ["ghosts"] : ["gothic"]), on: czDate(2026, 9, n)))
            let data = czData(items: items, goal: 12, challenges: [
                ChallengeEnrollment(id: "spooky-season", joinedAt: czDate(2026, 9, 1), year: 2026),
                ChallengeEnrollment(id: "yearly-goal", joinedAt: czDate(2026, 1, 1), year: 2026),
            ])
            let ids = Set(ledger(data, now: czDate(2026, 10, 1)).map(\.id))
            #expect(ids.isSuperset(of: seen), "stamps were lost at book \(n)")
            seen = ids
        }
        #expect(seen.contains("book.n12"))
    }

    @Test func leavingAChallengeTakesItsStampsButNotTheBooks() {
        let items = [czFinished(czBook("g", themes: ["ghosts"]), on: czDate(2026, 9, 12))]
        let joined = czData(items: items, challenges: [ChallengeEnrollment(id: "spooky-season", joinedAt: czDate(2026, 9, 1), year: 2026)])
        var left = joined
        left.challenges = []
        #expect(ledger(joined).count == 2)
        #expect(ledger(left).map(\.id) == ["book.g"])
    }

    @Test func monthNamesAreTwelveAndFixed() {
        #expect(StampLedger.monthNames.count == 12 && Set(StampLedger.monthNames).count == 12)
        #expect(StampLedger.rings(forPages: 299) == 3 && StampLedger.rings(forPages: 300) == 4 && StampLedger.rings(forPages: 600) == 5)
        #expect(StampLedger.rings(forDaysRead: 0) == 1 && StampLedger.rings(forDaysRead: 400) == 4)
    }
}
