import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Shared fixtures

/// Dates, calendars and random contexts for the voice tests. Everything is deterministic.
enum VoiceTestKit {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// A quiet Wednesday in June: no holiday, no weekday line, no streak. Anything the engine says comes from the hour.
    static func plain(hour: Int = 21, minute: Int = 0) -> GreetingContext {
        GreetingContext(date: date(2026, 6, 17, hour, minute), calendar: calendar)
    }

    static let titles: [String?] = [
        nil, "", "   ", "The Hobbit", "The Lost Boys", "A Short History of Nearly Everything: And Other Long Subtitles",
        String(repeating: "Extraordinarily Long Title ", count: 12), "{title}", "Émile & Zoë’s “Quotes”",
    ]

    static let bookStates: [GreetingBookState] = [
        .none, .justStarted, .midway, .nearFinish(pagesLeft: 1), .nearFinish(pagesLeft: 11), .nearFinish(pagesLeft: 400),
        .nearFinish(pagesLeft: 0), .nearFinish(pagesLeft: -3), .finishedToday, .stalled,
    ]

    static func randomContext(_ rng: inout SeededGenerator) -> GreetingContext {
        func pick<T>(_ items: [T]) -> T { items[Int(rng.next() % UInt64(items.count))] }
        let base = date(2026, 1, 1, 0, 0)
        let minutes = Int(rng.next() % (900 * 1440))
        let when = calendar.date(byAdding: .minute, value: minutes, to: base)!
        return GreetingContext(
            date: when,
            calendar: calendar,
            southernHemisphere: rng.next() % 5 == 0,
            weather: pick(GreetingWeather.allCases),
            streak: pick([-4, 0, 1, 2, 3, 6, 7, 8, 14, 21, 30, 99, 100, 365, 400, 1000, Int.max]),
            daysSinceLastSession: pick([nil, nil, 0, 1, 2, 3, 13, 14, 60, 4000]),
            bookState: pick(bookStates),
            bookTitle: pick(titles),
            goalState: pick(GreetingGoalState.allCases),
            isRestDay: rng.next() % 4 == 0,
            isFirstLaunchOfDay: rng.next() % 2 == 0,
            isFirstEverLaunch: rng.next() % 12 == 0,
            teaName: pick([nil, "", "Earl Grey", "Genmaicha"]),
            minutesToGoal: pick([nil, -5, 0, 1, 13, 90, 100_000])
        )
    }

    /// The pool line behind a greeting, if it came from the pool.
    static func line(for greeting: Greeting) -> GreetingLine? {
        GreetingPool.all.first { $0.id == greeting.lineID }
    }
}

// MARK: - The pool and the tone rules

struct GreetingPoolToneTests {
    let lines = GreetingPool.all

    /// A generous set of facts, to render every line the way the app would.
    var richValues: VoiceValues {
        VoiceValues(title: "The Hobbit", pagesLeft: 11, streak: 7, minutes: 13, tea: "Earl Grey", day: "Sunday")
    }

    @Test func poolHasAtLeastThreeHundredDistinctLines() {
        #expect(lines.count >= 300)
        #expect(Set(lines.map(\.template)).count == lines.count)
        #expect(Set(lines.map(\.id)).count == lines.count)
    }

    @Test func noDuplicatesEvenIgnoringPunctuationAndCase() {
        let keys = lines.map { VoiceTone.normalized($0.template).filter { $0.isLetter || $0.isNumber || $0 == " " } }
        #expect(Set(keys).count == keys.count)
    }

    @Test func noExclamationMarks() {
        let bad = lines.filter { $0.template.contains("!") || $0.template.contains("¡") }
        #expect(bad.isEmpty, "\(bad.map(\.template))")
    }

    @Test func headlinesAreShort() {
        var failures: [String] = []
        for line in lines {
            if VoiceTone.wordCount(line.headline) > VoiceTone.maxHeadlineWords { failures.append(line.template) }
            if let subline = line.subline, VoiceTone.wordCount(subline) > VoiceTone.maxSublineWords { failures.append(line.template) }
            if line.headline.isEmpty { failures.append("empty headline in \(line.id)") }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func filledHeadlinesStayShortEvenWithALongTitle() {
        let values = VoiceValues(title: "A Short History of Nearly Everything: And Other Long Subtitles", pagesLeft: 20, streak: 21, minutes: 25, tea: "Earl Grey", day: "Wednesday")
        var failures: [String] = []
        for line in lines {
            guard let headline = VoiceTemplate.fill(line.headline, with: values) else { continue }
            if VoiceTone.wordCount(headline) > VoiceTone.maxHeadlineWords { failures.append(headline) }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func noGuiltWords() {
        var failures: [String] = []
        for line in lines {
            let violations = VoiceTone.violations(headline: line.headline, subline: line.subline)
            if !violations.isEmpty { failures.append("\(line.template): \(violations)") }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    /// The same rule, checked a second way (a regular expression with word boundaries) so it does not rest on the
    /// tokenizer inside `VoiceTone` alone.
    @Test func noGuiltWordsByRegularExpression() throws {
        let pattern = "\\b(miss|missed|missing|lose|loses|losing|lost|behind|failing|fail|failed|lazy)\\b|should have|don't break|lost your streak|break your streak"
        let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        var failures: [String] = []
        for line in lines {
            let text = line.template.replacingOccurrences(of: "’", with: "'")
            if expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { failures.append(line.template) }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func noStreakThreatsOrNagging() {
        let nagging = ["streak", "don't forget", "haven't", "didn't", "you should", "you must", "need to", "have to"]
        var failures: [String] = []
        for line in lines where line.moment.tag != .streak {
            let text = VoiceTone.normalized(line.template)
            for word in nagging where text.contains(word) { failures.append(line.template) }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func cozyWordsAreSeasoningNotTheMeal() {
        let cozy = lines.filter { VoiceTone.isCozy($0.template) }
        let share = Double(cozy.count) / Double(lines.count)
        #expect(share >= 0.20 && share <= 0.40, "cozy share \(share)")
    }

    @Test func noSingleBucketDrownsInTea() {
        // Big buckets should not be wall-to-wall tea even if the whole pool is in range.
        var failures: [String] = []
        for moment in GreetingMoment.allCases {
            let bucket = GreetingPool.lines(in: moment)
            guard bucket.count >= 8 else { continue }
            let share = Double(bucket.filter { VoiceTone.isCozy($0.template) }.count) / Double(bucket.count)
            if share > 0.5 { failures.append("\(moment): \(share)") }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func everyMomentHasAtLeastThreeLines() {
        for moment in GreetingMoment.allCases {
            #expect(GreetingPool.lines(in: moment).count >= 3, "\(moment)")
        }
    }

    @Test func everyMomentHasThreeLinesThatNeedNothingOptional() {
        // When a title, a tea or a minutes figure is missing, a bucket must still have lines it can use at any hour.
        for moment in GreetingMoment.allCases {
            let bucket = GreetingPool.lines(in: moment)
            let unrestricted = bucket.filter { $0.dayparts == nil }
            if unrestricted.isEmpty {
                // Night-only moon lines: still three that need nothing extra.
                #expect(bucket.filter { $0.placeholders.isSubset(of: moment.guaranteedPlaceholders) }.count >= 3, "\(moment)")
            } else {
                #expect(unrestricted.filter { $0.placeholders.isSubset(of: moment.guaranteedPlaceholders) }.count >= 3, "\(moment)")
            }
        }
    }

    @Test func everyDaypartHasAtLeastEightLines() {
        for daypart in Daypart.allCases {
            let bucket = GreetingPool.lines(in: GreetingMoment.daypart(daypart))
            #expect(bucket.count >= 8, "\(daypart)")
            #expect(bucket.allSatisfy { $0.dayparts == nil }, "\(daypart) lines must suit their whole daypart")
        }
    }

    @Test func everyPlaceholderIsSupported() {
        var failures: [String] = []
        for line in lines {
            let problems = VoiceTemplate.problems(in: line.headline) + VoiceTemplate.problems(in: line.subline ?? "")
            if !problems.isEmpty { failures.append("\(line.template): \(problems)") }
        }
        #expect(failures.isEmpty, "\(failures)")
        #expect(VoicePlaceholder.allCases.map(\.rawValue).sorted() == ["day", "minutes", "pages", "streak", "tea", "title"])
    }

    @Test func everyLineFillsCleanlyWithRichFacts() {
        var failures: [String] = []
        for line in lines {
            guard let headline = VoiceTemplate.fill(line.headline, with: richValues) else { failures.append(line.template); continue }
            if headline.contains("{") || headline.contains("}") { failures.append(headline) }
            if let template = line.subline {
                guard let subline = VoiceTemplate.fill(template, with: richValues), !subline.contains("{") else { failures.append(line.template); continue }
            }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func typographyIsTypographic() {
        var failures: [String] = []
        for line in lines {
            let text = line.template
            if text.contains("'") || text.contains("\"") { failures.append("straight quote: \(text)") }
            if text.contains("  ") || text != text.trimmingCharacters(in: .whitespaces) { failures.append("spacing: \(text)") }
            guard let first = line.headline.first else { continue }
            if !(first.isUppercase || first == "{") { failures.append("lowercase start: \(text)") }
            for part in [line.headline, line.subline].compactMap({ $0 }) {
                if let last = part.last, !".?…".contains(last) { failures.append("no end mark: \(part)") }
            }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func sublinesNeverRepeatTheHeadline() {
        let bad = lines.filter { $0.subline != nil && $0.subline == $0.headline }
        #expect(bad.isEmpty)
    }

    @Test func theSampleLinesFromTheNotesAreAllThere() {
        // NEXT.md section 5, with typographic apostrophes and the title's italics marks removed.
        let samples = [
            "Early bird. The kettle's barely warm.", "Quiet house. Good light.",
            "Morning. Ten minutes before the day begins?", "Lunch with a chapter.",
            "Tea o'clock.", "The afternoon is better with a book in it.", "The lamp's calling.",
            "Good evening. Kettle on?", "Dinner's done. You've earned a chapter.",
            "Still up? One more page, then bed.", "The whole house is asleep. Except you and the book.",
            "Rain on the window. Perfect.", "Blanket weather.", "Leaves are turning. So are your pages.",
            "Slow Sunday. No rush.", "Seven evenings in a row. The tea tastes better.",
            "Welcome back. Your bookmark's right where you left it.",
            "Eleven pages from the end of *The Hobbit*. The kettle can wait.",
            "Today's pages are done. Anything more is a gift.", "Day off. The book will keep.", "Welcome to your nook.",
        ]
        let rendered = Set(lines.compactMap { line -> String? in
            guard let headline = VoiceTemplate.fill(line.headline, with: richValues) else { return nil }
            guard let template = line.subline else { return headline }
            return VoiceTemplate.fill(template, with: richValues).map { headline + " " + $0 }
        })
        var missing: [String] = []
        for sample in samples {
            let wanted = sample.replacingOccurrences(of: "'", with: "’").replacingOccurrences(of: "*", with: "")
            if !rendered.contains(wanted) { missing.append(sample) }
        }
        #expect(missing.isEmpty, "\(missing)")
    }

    @Test func stillUpIsTheLateNightLine() throws {
        let late = GreetingPool.lines(in: .late)
        let signature = try #require(late.first { $0.headline == "Still up?" && $0.subline == "One more page, then bed." })
        #expect(late.allSatisfy { $0.weight <= signature.weight })
        #expect(signature.weight > 5 * (late.filter { $0.id != signature.id }.map(\.weight).max() ?? 1))
    }

    @Test func linesWithRestrictedHoursAreSensible() {
        for line in lines {
            if let dayparts = line.dayparts { #expect(!dayparts.isEmpty, "\(line.template)") }
            #expect(line.weight > 0)
        }
    }
}

struct VoiceToneTests {
    @Test func acceptsKindLines() {
        #expect(VoiceTone.isAcceptable(headline: "Still up?", subline: "One more page, then bed."))
        #expect(VoiceTone.isAcceptable(headline: "The close of a good book."))
    }

    @Test func rejectsGuiltAndShouting() {
        #expect(!VoiceTone.isAcceptable(headline: "Read now!"))
        #expect(!VoiceTone.isAcceptable(headline: "We missed you."))
        #expect(!VoiceTone.isAcceptable(headline: "Don’t lose your place."))
        #expect(!VoiceTone.isAcceptable(headline: "You’re falling behind."))
        #expect(!VoiceTone.isAcceptable(headline: "Don’t break the streak."))
        #expect(!VoiceTone.isAcceptable(headline: "A lazy day."))
        #expect(!VoiceTone.isAcceptable(headline: "You should have read."))
        #expect(!VoiceTone.isAcceptable(headline: ""))
        #expect(!VoiceTone.isAcceptable(headline: "Fine", subline: "Wow!"))
        #expect(!VoiceTone.isAcceptable(headline: "One more chapter ✨ tonight."))
    }

    @Test func lengthLimitIsEnforced() {
        let long = Array(repeating: "word", count: 13).joined(separator: " ") + "."
        #expect(VoiceTone.violations(headline: long).contains(.tooLong(words: 13, limit: 12)))
        #expect(VoiceTone.wordCount("  Tea   o’clock. ") == 2)
        #expect(VoiceTone.wordCount("— …") == 0)
    }

    @Test func namesAreIgnoredWhenAsked() {
        #expect(!VoiceTone.isAcceptable(headline: "Back to The Lost Boys."))
        #expect(VoiceTone.isAcceptable(headline: "Back to The Lost Boys.", ignoring: ["The Lost Boys"]))
    }

    @Test func cozyDetectionHandlesPossessivesAndCase() {
        #expect(VoiceTone.isCozy("The Kettle’s barely warm."))
        #expect(VoiceTone.isCozy("Pour a cup."))
        #expect(!VoiceTone.isCozy("Quiet house. Good light."))
    }

    @Test func curlyApostrophesDoNotHideBannedPhrases() {
        #expect(!VoiceTone.isAcceptable(headline: "Don’t break it."))
    }
}

// MARK: - Placeholders and helpers

struct VoiceTemplateTests {
    @Test func spellsSmallNumbersAndKeepsLargeOnesAsDigits() {
        #expect(VoiceText.count(0) == "zero")
        #expect(VoiceText.count(11) == "eleven")
        #expect(VoiceText.count(20) == "twenty")
        #expect(VoiceText.count(21) == "21")
        #expect(VoiceText.count(7, spelled: false) == "7")
        #expect(VoiceText.count(-3) == "-3")
        #expect(VoiceText.pagesPhrase(1) == "one page")
        #expect(VoiceText.pagesPhrase(11) == "eleven pages")
        #expect(VoiceText.pagesPhrase(34) == "34 pages")
        #expect(VoiceText.minutesPhrase(1) == "one minute")
        #expect(VoiceText.minutesPhrase(13, spelled: false) == "13 minutes")
    }

    @Test func weekdayNamesWrapAndNeverDependOnTheLocale() {
        #expect(VoiceText.weekdayName(1) == "Sunday")
        #expect(VoiceText.weekdayName(7) == "Saturday")
        #expect(VoiceText.weekdayName(8) == "Sunday")
        #expect(VoiceText.weekdayName(0) == "Saturday")
        #expect(VoiceText.weekdayName(-6) == "Sunday")
    }

    @Test func fillsEveryPlaceholder() {
        let values = VoiceValues(title: "The Hobbit", pagesLeft: 11, streak: 7, minutes: 13, tea: "Earl Grey", day: "Sunday")
        let filled = VoiceTemplate.fill("{day}: {title}, {pages}, {streak} days, {minutes}, {tea}.", with: values)
        #expect(filled == "Sunday: The Hobbit, eleven pages, seven days, thirteen minutes, Earl Grey.")
        let digits = VoiceValues(pagesLeft: 11, streak: 7, minutes: 13, spellsNumbers: false)
        #expect(VoiceTemplate.fill("{pages} {streak} {minutes}", with: digits) == "11 pages 7 13 minutes")
    }

    @Test func capitalizesNumberWordsAtTheStartOfASentence() {
        let values = VoiceValues(pagesLeft: 11, minutes: 1)
        #expect(VoiceTemplate.fill("{pages} to go. {minutes} more.", with: values) == "Eleven pages to go. One minute more.")
        #expect(VoiceTemplate.fill("Only {pages} to go.", with: values) == "Only eleven pages to go.")
    }

    @Test func aTemplateWithAnUnfilledPlaceholderIsNeverFilled() {
        #expect(VoiceTemplate.fill("{title} is waiting.", with: VoiceValues()) == nil)
        #expect(VoiceTemplate.fill("{title} is waiting.", with: VoiceValues(title: "   ")) == nil)
        #expect(VoiceTemplate.fill("{pages} left.", with: VoiceValues(pagesLeft: 0)) == nil)
        #expect(VoiceTemplate.fill("{streak} days.", with: VoiceValues(streak: 1)) == nil)
        #expect(VoiceTemplate.fill("{minutes}.", with: VoiceValues(minutes: 0)) == nil)
        #expect(VoiceTemplate.fill("{tea}.", with: VoiceValues(tea: "")) == nil)
        #expect(VoiceTemplate.fill("{nonsense}.", with: VoiceValues(title: "x")) == nil)
        #expect(VoiceTemplate.fill("No placeholders.", with: VoiceValues()) == "No placeholders.")
    }

    @Test func fillingDoesNotExpandBracesInsideValues() {
        let filled = VoiceTemplate.fill("Back to {title}.", with: VoiceValues(title: "{pages}"))
        #expect(filled == "Back to {pages}.")
    }

    @Test func findsPlaceholdersAndProblems() {
        #expect(VoiceTemplate.placeholders(in: "{title} and {pages} and {title}") == [.title, .pages])
        #expect(VoiceTemplate.problems(in: "{title} {oops} {").sorted() == ["oops", "{"])
        #expect(VoiceTemplate.problems(in: "stray } brace") == ["}"])
        #expect(VoiceTemplate.problems(in: "clean {day}").isEmpty)
    }

    @Test func shortTitlesDropSubtitlesAndCapLength() {
        #expect(VoiceText.shortTitle("The Hobbit") == "The Hobbit")
        #expect(VoiceText.shortTitle("Dune: Deluxe Edition") == "Dune")
        #expect(VoiceText.shortTitle("Piranesi (Illustrated)") == "Piranesi")
        #expect(VoiceText.shortTitle("One Two Three Four Five Six Seven Eight") == "One Two Three Four Five Six…")
        let long = VoiceText.shortTitle(String(repeating: "Extraordinary ", count: 8), maxCharacters: 20)
        #expect(long.count <= 21)
        #expect(long.hasSuffix("…"))
        #expect(VoiceText.shortTitle(":") == ":")
        #expect(!VoiceText.shortTitle("").contains("…") || VoiceText.shortTitle("").isEmpty)
    }

    @Test func choosingIsDeterministicAndRespectsWeights() {
        let items = ["a", "b", "c"]
        #expect(VoiceText.choose(items, seed: 42, salt: "x") == VoiceText.choose(items, seed: 42, salt: "x"))
        #expect(VoiceText.choose([String](), seed: 1, salt: "x") == nil)
        var heavy = 0
        for seed in 0..<500 where VoiceText.choose(items, seed: SeededGenerator.hash("s\(seed)"), salt: "w", weight: { $0 == "b" ? 50 : 1 }) == "b" { heavy += 1 }
        #expect(heavy > 400)
        // Zero or negative weights fall back to a plain pick instead of crashing.
        #expect(VoiceText.choose(items, seed: 3, salt: "z", weight: { _ in 0 }) != nil)
        #expect(VoiceText.choose(items, seed: 3, salt: "z", weight: { _ in -1 }) != nil)
    }

    @Test func stableIDsAreStable() {
        #expect(VoiceText.stableID("late", "Still up?") == VoiceText.stableID("late", "Still up?"))
        #expect(VoiceText.stableID("late", "Still up?") != VoiceText.stableID("late", "Still up"))
        #expect(VoiceText.stableID("late", "x").hasPrefix("late."))
    }
}

// MARK: - The moment

struct GreetingContextTests {
    let calendar = VoiceTestKit.calendar

    @Test func derivesTheTimeFacts() {
        let context = GreetingContext(date: VoiceTestKit.date(2026, 10, 18, 21, 30), calendar: calendar)
        #expect(context.daypart == .evening)
        #expect(context.season == .autumn)
        #expect(context.weekday == 1)
        #expect(context.weekdayName == "Sunday")
        #expect(context.holiday == .spookySeason)
        #expect(context.weather == .unknown)
        #expect(context.isFirstLaunchOfDay)
        #expect(!context.isFirstEverLaunch)
    }

    @Test func southernHemisphereFlipsTheSeason() {
        let north = GreetingContext(date: VoiceTestKit.date(2026, 7, 4), calendar: calendar)
        let south = GreetingContext(date: VoiceTestKit.date(2026, 7, 4), calendar: calendar, southernHemisphere: true)
        #expect(north.season == .summer)
        #expect(south.season == .winter)
    }

    @Test func fixedHolidays() {
        let cases: [(Int, Int, Int, GreetingHoliday?)] = [
            (2026, 12, 31, .newYearsEve), (2027, 1, 1, .newYear), (2026, 2, 14, .valentines),
            (2026, 10, 31, .halloween), (2026, 10, 15, .spookySeason), (2026, 10, 1, .spookySeason),
            (2026, 12, 24, .christmasEve), (2026, 12, 25, .christmas), (2026, 12, 10, .christmasSeason),
            (2026, 12, 23, .christmasSeason), (2026, 12, 26, nil), (2026, 6, 15, nil), (2026, 2, 13, nil), (2026, 11, 3, nil),
        ]
        for (year, month, day, expected) in cases {
            let holiday = GreetingHoliday.of(VoiceTestKit.date(year, month, day, 12), calendar: calendar)
            #expect(holiday == expected, "\(year)-\(month)-\(day): \(String(describing: holiday))")
        }
    }

    @Test func thanksgivingIsTheFourthThursdayOfNovember() {
        for (year, day) in [(2024, 28), (2025, 27), (2026, 26), (2027, 25), (2028, 23)] {
            #expect(GreetingHoliday.of(VoiceTestKit.date(year, 11, day, 12), calendar: calendar) == .thanksgiving, "\(year)")
        }
        // The third and fifth Thursdays are ordinary days.
        #expect(GreetingHoliday.of(VoiceTestKit.date(2026, 11, 19, 12), calendar: calendar) == nil)
        #expect(GreetingHoliday.of(VoiceTestKit.date(2024, 11, 21, 12), calendar: calendar) == nil)
        // Exactly one Thanksgiving per year.
        for year in 2020...2040 {
            var count = 0
            for day in 1...30 where GreetingHoliday.of(VoiceTestKit.date(year, 11, day, 12), calendar: calendar) == .thanksgiving { count += 1 }
            #expect(count == 1, "\(year)")
        }
    }

    @Test func easterIsComputed() {
        let known: [(Int, Int, Int)] = [(2000, 4, 23), (2011, 4, 24), (2019, 4, 21), (2024, 3, 31), (2025, 4, 20), (2026, 4, 5), (2027, 3, 28), (2038, 4, 25)]
        for (year, month, day) in known {
            let easter = GreetingHoliday.easterSunday(year: year)
            #expect(easter?.month == month && easter?.day == day, "\(year)")
            #expect(GreetingHoliday.of(VoiceTestKit.date(year, month, day, 12), calendar: calendar) == .easter, "\(year)")
        }
        #expect(GreetingHoliday.easterSunday(year: 1500) == nil)
        // Easter always falls on a Sunday between 22 March and 25 April.
        for year in 1990...2060 {
            guard let easter = GreetingHoliday.easterSunday(year: year) else { continue }
            let date = VoiceTestKit.date(year, easter.month, easter.day, 12)
            #expect(calendar.component(.weekday, from: date) == 1, "\(year)")
            #expect((easter.month == 3 && easter.day >= 22) || (easter.month == 4 && easter.day <= 25), "\(year)")
        }
    }

    @Test func holidaysFollowTheReadersClockNotUTC() {
        // 11:30 pm on Halloween in New York is already November 1 in UTC.
        let lateHalloween = VoiceTestKit.date(2026, 10, 31, 23, 30)
        #expect(GreetingContext(date: lateHalloween, calendar: calendar).holiday == .halloween)
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let morning = tokyo.date(from: DateComponents(year: 2026, month: 12, day: 25, hour: 7))!
        #expect(GreetingContext(date: morning, calendar: tokyo).holiday == .christmas)
    }

    @Test func holidaysSurviveAnotherCalendarSystem() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "America/New_York")!
        let halloween = VoiceTestKit.date(2026, 10, 31, 12)
        #expect(GreetingContext(date: halloween, calendar: buddhist).holiday == .halloween)
    }

    @Test func moonPhasesMatchKnownDates() {
        #expect(GreetingMoonPhase.of(VoiceTestKit.utc(2026, 3, 3)) == .full)
        #expect(GreetingMoonPhase.of(VoiceTestKit.utc(2026, 2, 17)) == .new)
        #expect(GreetingMoonPhase.of(VoiceTestKit.utc(2020, 10, 31)) == .full)
        #expect(GreetingMoonPhase.of(VoiceTestKit.utc(2024, 4, 8, 18)) == .new)
        #expect(GreetingMoonPhase.of(VoiceTestKit.utc(2000, 1, 21, 5)) == .full)
        // A week after a new moon is a first quarter.
        #expect(GreetingMoonPhase.of(VoiceTestKit.utc(2026, 2, 24)) == .firstQuarter)
    }

    @Test func moonAgeStaysInsideOneMonthForAnyDate() {
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<500 {
            let seconds = (Double(rng.next() % 4_000_000_000) - 1_500_000_000)
            let age = GreetingMoonPhase.age(of: Date(timeIntervalSince1970: seconds))
            #expect(age >= 0 && age < GreetingMoonPhase.synodicMonth)
        }
        #expect(GreetingMoonPhase.age(of: Date(timeIntervalSince1970: .nan)) == 0)
        _ = GreetingMoonPhase.of(.distantFuture)
        _ = GreetingMoonPhase.of(.distantPast)
        // The phases cycle through all eight in order over one month.
        var seen: [GreetingMoonPhase] = []
        for day in 0..<30 {
            let phase = GreetingMoonPhase.of(Date(timeIntervalSince1970: 947_182_440 + Double(day) * 86_400))
            if seen.last != phase { seen.append(phase) }
        }
        #expect(Set(seen).count == 8)
    }

    @Test func classifiesTheBookFromPlainNumbers() {
        typealias State = GreetingBookState
        #expect(State.classify(currentPage: 0, totalPages: 0) == .none)
        #expect(State.classify(currentPage: 300, totalPages: 300) == .none)
        #expect(State.classify(currentPage: 999, totalPages: 300) == .none)
        #expect(State.classify(currentPage: 300, totalPages: 300, finishedToday: true) == .finishedToday)
        #expect(State.classify(currentPage: 0, totalPages: 300) == .justStarted)
        #expect(State.classify(currentPage: 20, totalPages: 300) == .justStarted)
        #expect(State.classify(currentPage: 150, totalPages: 300) == .midway)
        #expect(State.classify(currentPage: 290, totalPages: 300) == .nearFinish(pagesLeft: 10))
        #expect(State.classify(currentPage: 275, totalPages: 300) == .nearFinish(pagesLeft: 25))
        #expect(State.classify(currentPage: 274, totalPages: 300) == .midway)
        // Long books count the last 30 pages as near the end, never more.
        #expect(State.classify(currentPage: 870, totalPages: 900) == .nearFinish(pagesLeft: 30))
        #expect(State.classify(currentPage: 860, totalPages: 900) == .midway)
        #expect(State.classify(currentPage: 150, totalPages: 300, daysSinceLastRead: 14) == .stalled)
        #expect(State.classify(currentPage: 150, totalPages: 300, daysSinceLastRead: 13) == .midway)
        #expect(State.classify(currentPage: 0, totalPages: 300, daysSinceLastRead: 90) == .justStarted)
        // Near the end beats stalled: ten pages to go is the better thing to say.
        #expect(State.classify(currentPage: 290, totalPages: 300, daysSinceLastRead: 40) == .nearFinish(pagesLeft: 10))
        #expect(State.classify(currentPage: -5, totalPages: 300) == .justStarted)
    }
}

// MARK: - The engine

struct GreetingEngineTests {
    let calendar = VoiceTestKit.calendar

    func seed(_ n: Int) -> UInt64 { SeededGenerator.hash("voice-test-\(n)") }

    /// A context where every rung of the priority ladder applies at once.
    func everything() -> GreetingContext {
        GreetingContext(
            date: VoiceTestKit.date(2026, 10, 31, 21),
            calendar: calendar,
            weather: .rain,
            streak: 7,
            daysSinceLastSession: 20,
            bookState: .nearFinish(pagesLeft: 11),
            bookTitle: "The Hobbit",
            goalState: .met,
            isRestDay: true,
            isFirstLaunchOfDay: true,
            isFirstEverLaunch: true,
            teaName: "Earl Grey",
            minutesToGoal: 13
        )
    }

    @Test func isDeterministic() {
        var rng = SeededGenerator(seed: 99)
        for _ in 0..<200 {
            let context = VoiceTestKit.randomContext(&rng)
            let seed = rng.next()
            let previous: String? = rng.next() % 2 == 0 ? nil : "late.00000000"
            #expect(GreetingEngine.line(for: context, seed: seed, previousLineID: previous) == GreetingEngine.line(for: context, seed: seed, previousLineID: previous))
        }
    }

    @Test func differentDaysCanSayDifferentThings() {
        let context = VoiceTestKit.plain()
        let lines = Set((0..<60).map { GreetingEngine.line(for: context, seed: seed($0)).lineID })
        #expect(lines.count > 8)
    }

    @Test func dailySeedChangesAtMidnightOnly() {
        let a = GreetingContext(date: VoiceTestKit.date(2026, 6, 17, 0, 5), calendar: calendar)
        let b = GreetingContext(date: VoiceTestKit.date(2026, 6, 17, 23, 55), calendar: calendar)
        let c = GreetingContext(date: VoiceTestKit.date(2026, 6, 18, 0, 5), calendar: calendar)
        #expect(GreetingEngine.dailySeed(for: a) == GreetingEngine.dailySeed(for: b))
        #expect(GreetingEngine.dailySeed(for: a) != GreetingEngine.dailySeed(for: c))
    }

    // MARK: Priority

    @Test func priorityLadderFromTheTopDown() {
        var context = everything()
        func tags(_ context: GreetingContext) -> Set<GreetingTag> {
            Set((0..<80).map { GreetingEngine.line(for: context, seed: seed($0)).tag })
        }

        #expect(tags(context) == [.firstEver])

        context.isFirstEverLaunch = false
        #expect(tags(context) == [.nearFinish])

        context.bookState = .finishedToday
        #expect(tags(context) == [.finishedToday])

        context.bookState = .stalled
        #expect(tags(context) == [.welcomeBack])

        context.isFirstLaunchOfDay = false
        #expect(tags(context) == [.goalMet])

        context.goalState = .partial
        #expect(tags(context) == [.restDay])

        context.isRestDay = false
        #expect(tags(context) == [.streak])

        context.streak = 0
        #expect(tags(context) == [.stalled])

        context.bookState = .none
        #expect(tags(context) == [.holiday])

        context.holiday = nil
        let rest = tags(context)
        let allowed: Set<GreetingTag> = [.goalProgress, .weather, .moon, .weekday, .season, .daypart]
        #expect(rest.isSubset(of: allowed), "\(rest)")
        #expect(rest.contains(.daypart))
    }

    @Test func eachTopTierUsesItsOwnBucket() {
        var context = VoiceTestKit.plain()
        context.isFirstEverLaunch = true
        #expect(GreetingEngine.line(for: context, seed: 1).moment == .firstEver)

        context = VoiceTestKit.plain()
        context.bookState = .nearFinish(pagesLeft: 9)
        #expect(GreetingEngine.line(for: context, seed: 1).moment == .nearFinish)

        context = VoiceTestKit.plain()
        context.goalState = .met
        #expect(GreetingEngine.line(for: context, seed: 1).moment == .goalMet)

        context = VoiceTestKit.plain()
        context.isRestDay = true
        #expect(GreetingEngine.line(for: context, seed: 1).moment == .restDay)
    }

    @Test func welcomeBackNeedsAGapAndAFirstLaunch() {
        func moments(gap: Int?, first: Bool) -> Set<GreetingMoment?> {
            var context = VoiceTestKit.plain()
            context.daysSinceLastSession = gap
            context.isFirstLaunchOfDay = first
            return Set((0..<60).map { GreetingEngine.line(for: context, seed: seed($0)).moment })
        }
        #expect(moments(gap: 2, first: true).isDisjoint(with: [.welcomeBack, .welcomeBackLong]))
        #expect(moments(gap: nil, first: true).isDisjoint(with: [.welcomeBack, .welcomeBackLong]))
        #expect(moments(gap: 3, first: true) == [.welcomeBack])
        #expect(moments(gap: 13, first: true) == [.welcomeBack])
        #expect(moments(gap: 14, first: true) == [.welcomeBackLong])
        #expect(moments(gap: 400, first: true) == [.welcomeBackLong])
        #expect(moments(gap: 20, first: false).isDisjoint(with: [.welcomeBack, .welcomeBackLong]))
    }

    @Test func streakMilestones() {
        for streak in [7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300, 365, 400, 500, 1000] {
            #expect(GreetingEngine.isStreakMilestone(streak), "\(streak)")
        }
        for streak in [-1, 0, 1, 2, 6, 8, 13, 15, 29, 31, 99, 101, 366, 399, 401] {
            #expect(!GreetingEngine.isStreakMilestone(streak), "\(streak)")
        }
        #expect(GreetingEngine.milestoneMoment(for: 7) == .streakWeek)
        #expect(GreetingEngine.milestoneMoment(for: 14) == .streakFortnight)
        #expect(GreetingEngine.milestoneMoment(for: 30) == .streakMonth)
        #expect(GreetingEngine.milestoneMoment(for: 100) == .streakCentury)
        #expect(GreetingEngine.milestoneMoment(for: 365) == .streakOther)
        for (streak, moment) in [(7, GreetingMoment.streakWeek), (14, .streakFortnight), (30, .streakMonth), (100, .streakCentury), (50, .streakOther)] {
            var context = VoiceTestKit.plain()
            context.streak = streak
            #expect(GreetingEngine.line(for: context, seed: 5).moment == moment, "\(streak)")
        }
    }

    @Test func streakLinesFillTheStreakNumber() {
        var context = VoiceTestKit.plain()
        context.streak = 50
        var texts = Set<String>()
        for n in 0..<40 { texts.insert(GreetingEngine.line(for: context, seed: seed(n)).text) }
        #expect(texts.allSatisfy { $0.contains("50") })
        #expect(texts.count > 1)
    }

    @Test func theSevenEveningsLineOnlyAppearsInTheEvening() {
        var context = VoiceTestKit.plain(hour: 9)
        context.streak = 7
        for n in 0..<60 { #expect(!GreetingEngine.line(for: context, seed: seed(n)).text.contains("evenings")) }
        context = VoiceTestKit.plain(hour: 21)
        context.streak = 7
        let evening = Set((0..<80).map { GreetingEngine.line(for: context, seed: seed($0)).text })
        #expect(evening.contains("Seven evenings in a row. The tea tastes better."))
    }

    @Test func theDayOfAHolidayAlwaysShowsIt() {
        for (month, day, moment) in [(12, 25, GreetingMoment.christmas), (12, 24, .christmasEve), (10, 31, .halloween), (2, 14, .valentines), (1, 1, .newYear), (12, 31, .newYearsEve), (11, 26, .thanksgiving)] {
            let year = month == 1 ? 2027 : 2026
            for hour in [6, 13, 22] {
                let context = GreetingContext(date: VoiceTestKit.date(year, month, day, hour), calendar: calendar)
                for n in 0..<20 { #expect(GreetingEngine.line(for: context, seed: seed(n)).moment == moment, "\(month)/\(day)") }
            }
        }
        let easter = GreetingContext(date: VoiceTestKit.date(2026, 4, 5, 10), calendar: calendar)
        #expect(GreetingEngine.line(for: easter, seed: 1).moment == .easter)
    }

    @Test func holidayWindowsOnlyTakeSomeTurns() {
        let context = GreetingContext(date: VoiceTestKit.date(2026, 10, 14, 10), calendar: calendar)
        let moments = (0..<300).map { GreetingEngine.line(for: context, seed: seed($0)).moment }
        let spooky = moments.filter { $0 == .spookySeason }.count
        let daypart = moments.filter { $0 == .morning }.count
        #expect(spooky > 20)
        #expect(daypart > 60)
    }

    @Test func weatherTakesSomeTurnsAndTheClockTakesTheRest() {
        var context = VoiceTestKit.plain(hour: 10)
        context.weather = .rain
        let tags = (0..<300).map { GreetingEngine.line(for: context, seed: seed($0)).tag }
        let weather = tags.filter { $0 == .weather }.count
        let daypart = tags.filter { $0 == .daypart }.count
        #expect(weather > 40, "weather \(weather)")
        #expect(daypart > 90, "daypart \(daypart)")
        let rainLines = (0..<300).compactMap { n -> GreetingMoment? in
            let greeting = GreetingEngine.line(for: context, seed: seed(n))
            return greeting.tag == .weather ? greeting.moment : nil
        }
        #expect(Set(rainLines) == [.rain])
    }

    @Test func weatherIsNeverRequired() {
        let context = VoiceTestKit.plain(hour: 10)
        #expect(context.weather == .unknown)
        let tags = Set((0..<200).map { GreetingEngine.line(for: context, seed: seed($0)).tag })
        #expect(!tags.contains(.weather))
    }

    @Test func eachWeatherSpeaksInItsOwnBucket() {
        let expected: [GreetingWeather: GreetingMoment] = [.clear: .clear, .rain: .rain, .snow: .snow, .cold: .cold, .hot: .hot, .wind: .wind, .fog: .fog]
        for (weather, moment) in expected {
            var context = VoiceTestKit.plain(hour: 11)
            context.weather = weather
            let moments = Set((0..<200).compactMap { n -> GreetingMoment? in
                let greeting = GreetingEngine.line(for: context, seed: seed(n))
                return greeting.tag == .weather ? greeting.moment : nil
            })
            #expect(moments == [moment], "\(weather)")
        }
    }

    @Test func theMoonOnlyAppearsAfterDark() {
        for hour in [8, 12, 15] {
            var context = GreetingContext(date: VoiceTestKit.date(2026, 3, 3, hour), calendar: calendar)
            context.moon = .full
            #expect(!(0..<150).contains { GreetingEngine.line(for: context, seed: seed($0)).tag == .moon })
        }
        var night = GreetingContext(date: VoiceTestKit.date(2026, 6, 17, 22), calendar: calendar)
        night.moon = .full
        #expect((0..<300).contains { GreetingEngine.line(for: night, seed: seed($0)).moment == .fullMoon })
    }

    @Test func lateNightKeepsItsSignatureLine() {
        let context = VoiceTestKit.plain(hour: 23, minute: 30)
        #expect(context.daypart == .late)
        let signature = "Still up? One more page, then bed."
        let hits = (0..<400).filter { GreetingEngine.line(for: context, seed: seed($0)).text == signature }.count
        #expect(hits > 120, "signature appeared \(hits) times in 400 nights")
        // Past midnight is still "late"; the small hours get their own sample line.
        let small = VoiceTestKit.plain(hour: 3)
        #expect(small.daypart == .smallHours)
        let line = "The whole house is asleep. Except you and the book."
        #expect((0..<400).contains { GreetingEngine.line(for: small, seed: seed($0)).text == line })
    }

    @Test func ordinaryHoursUseTheirOwnDaypartLines() {
        let hours: [(Int, Daypart)] = [(6, .dawn), (9, .morning), (12, .lunch), (15, .afternoon), (16, .teaTime), (18, .dusk), (20, .evening), (23, .late), (3, .smallHours)]
        for (hour, daypart) in hours {
            let context = VoiceTestKit.plain(hour: hour)
            #expect(context.daypart == daypart)
            let greetings = (0..<100).map { GreetingEngine.line(for: context, seed: seed($0)) }
            let fromClock = greetings.filter { $0.tag == .daypart }
            #expect(fromClock.count > 25, "\(daypart)")
            #expect(fromClock.allSatisfy { $0.moment == GreetingMoment.daypart(daypart) })
        }
    }

    // MARK: Placeholders

    @Test func nearTheEndSampleLineIsFilled() {
        var context = VoiceTestKit.plain()
        context.bookState = .nearFinish(pagesLeft: 11)
        context.bookTitle = "The Hobbit"
        var texts = Set<String>()
        for n in 0..<120 {
            let greeting = GreetingEngine.line(for: context, seed: seed(n))
            #expect(greeting.tag == .nearFinish)
            texts.insert(greeting.text)
        }
        #expect(texts.contains("Eleven pages from the end of The Hobbit. The kettle can wait."))
        #expect(texts.allSatisfy { $0.lowercased().contains("eleven pages") && !$0.contains("{") })
        #expect(texts.contains { $0.contains("The Hobbit") })
    }

    @Test func singularAndLargePageCountsReadWell() {
        var context = VoiceTestKit.plain()
        context.bookState = .nearFinish(pagesLeft: 1)
        let one = (0..<60).map { GreetingEngine.line(for: context, seed: seed($0)).text }
        #expect(one.allSatisfy { $0.lowercased().contains("one page") && !$0.lowercased().contains("one pages") })
        context.bookState = .nearFinish(pagesLeft: 34)
        let many = (0..<60).map { GreetingEngine.line(for: context, seed: seed($0)).text }
        #expect(many.allSatisfy { $0.contains("34 pages") })
    }

    @Test func aLineThatCannotBeFilledIsNeverChosen() {
        // Near the end with no title: only lines that need nothing but the page count.
        var context = VoiceTestKit.plain()
        context.bookState = .nearFinish(pagesLeft: 7)
        context.bookTitle = nil
        for n in 0..<200 {
            let greeting = GreetingEngine.line(for: context, seed: seed(n))
            #expect(greeting.tag == .nearFinish)
            let line = VoiceTestKit.line(for: greeting)
            #expect(line?.placeholders.contains(.title) == false)
            #expect(!greeting.text.contains("{"))
        }
        // A partly done goal with no minutes figure never claims a number of minutes.
        context = VoiceTestKit.plain()
        context.goalState = .partial
        context.minutesToGoal = nil
        for n in 0..<200 { #expect(GreetingEngine.line(for: context, seed: seed(n)).tag != .goalProgress) }
        // And with one, the number is in the line.
        context.minutesToGoal = 13
        let partial = (0..<300).map { GreetingEngine.line(for: context, seed: seed($0)) }.filter { $0.tag == .goalProgress }
        #expect(partial.count > 30)
        #expect(partial.allSatisfy { $0.text.lowercased().contains("thirteen minutes") })
    }

    @Test func blankTitlesAreTreatedAsMissing() {
        var context = VoiceTestKit.plain()
        context.bookState = .stalled
        for title in ["", "   ", "\n"] {
            context.bookTitle = title
            for n in 0..<60 {
                let greeting = GreetingEngine.line(for: context, seed: seed(n))
                #expect(greeting.tag == .stalled)
                #expect(VoiceTestKit.line(for: greeting)?.placeholders.contains(.title) == false)
            }
        }
    }

    @Test func longTitlesAreShortenedInsideTheLine() {
        var context = VoiceTestKit.plain()
        context.bookState = .nearFinish(pagesLeft: 9)
        context.bookTitle = "A Short History of Nearly Everything: And Other Long Subtitles"
        let texts = (0..<80).map { GreetingEngine.line(for: context, seed: seed($0)).text }
        #expect(texts.allSatisfy { !$0.contains("Subtitles") })
        #expect(texts.contains { $0.contains("A Short History of Nearly Everything") })
        // A title with no subtitle is cut to six words.
        context.bookTitle = "One Two Three Four Five Six Seven Eight"
        let cut = (0..<80).map { GreetingEngine.line(for: context, seed: seed($0)).text }
        #expect(cut.allSatisfy { !$0.contains("Seven") })
        #expect(cut.contains { $0.contains("One Two Three Four Five Six…") })
    }

    @Test func everyChosenLineOnlyUsesFactsTheContextHas() {
        var rng = SeededGenerator(seed: 2026)
        var failures: [String] = []
        for _ in 0..<1000 {
            let context = VoiceTestKit.randomContext(&rng)
            let greeting = GreetingEngine.line(for: context, seed: rng.next())
            if (greeting.text.contains("{") || greeting.text.contains("}")) && context.bookTitle != "{title}" { failures.append("braces: \(greeting.text)") }
            guard let line = VoiceTestKit.line(for: greeting) else { failures.append("not in pool: \(greeting.lineID)"); continue }
            if !line.placeholders.isSubset(of: GreetingEngine.values(for: context).available) { failures.append("unfillable: \(line.template)") }
            if let dayparts = line.dayparts, !dayparts.contains(context.daypart) { failures.append("wrong hour: \(line.template)") }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    // MARK: Rotation

    @Test func neverRepeatsYesterdaysLineOverSixtyDays() {
        let hours = [(8, 0), (13, 0), (17, 0), (21, 0), (23, 40), (3, 0)]
        for (hour, minute) in hours {
            var memory = GreetingMemory()
            var previous: String?
            var seen = Set<String>()
            for offset in 0..<60 {
                let when = VoiceTestKit.date(2026, 11, 2 + offset, hour, minute)
                let context = GreetingContext(date: when, calendar: calendar)
                let id = memory.previousLineID(on: when, calendar: calendar)
                let greeting = GreetingEngine.line(for: context, seed: GreetingEngine.dailySeed(for: context), previousLineID: id)
                #expect(greeting.lineID != previous, "day \(offset) at \(hour):\(minute) repeated \(greeting.text)")
                memory.record(greeting, on: when, calendar: calendar)
                previous = greeting.lineID
                seen.insert(greeting.lineID)
            }
            #expect(seen.count >= 15, "only \(seen.count) different lines at \(hour):\(minute)")
        }
    }

    @Test func neverRepeatsYesterdayWhateverTheContext() {
        var rng = SeededGenerator(seed: 321)
        var memory = GreetingMemory()
        var previous: String?
        var failures: [String] = []
        for offset in 0..<400 {
            var context = VoiceTestKit.randomContext(&rng)
            // Put the random context on consecutive days so the memory sees a real run of days.
            context.date = calendar.date(byAdding: .day, value: offset, to: VoiceTestKit.date(2027, 1, 1, 12))!
            context = rebuilt(context)
            let id = memory.previousLineID(on: context.date, calendar: calendar)
            let greeting = GreetingEngine.line(for: context, seed: GreetingEngine.dailySeed(for: context), previousLineID: id)
            if greeting.lineID == previous { failures.append("day \(offset): \(greeting.text)") }
            memory.record(greeting, on: context.date, calendar: calendar)
            previous = greeting.lineID
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    /// The derived fields follow the date, so rebuild after moving it.
    private func rebuilt(_ context: GreetingContext) -> GreetingContext {
        GreetingContext(
            date: context.date, calendar: context.calendar, southernHemisphere: context.southernHemisphere, weather: context.weather,
            streak: context.streak, daysSinceLastSession: context.daysSinceLastSession, bookState: context.bookState,
            bookTitle: context.bookTitle, goalState: context.goalState, isRestDay: context.isRestDay,
            isFirstLaunchOfDay: context.isFirstLaunchOfDay, isFirstEverLaunch: context.isFirstEverLaunch,
            teaName: context.teaName, minutesToGoal: context.minutesToGoal
        )
    }

    @Test func rerenderingDoesNotFlicker() {
        var memory = GreetingMemory()
        let yesterday = VoiceTestKit.date(2026, 11, 2, 21)
        let first = GreetingEngine.line(for: GreetingContext(date: yesterday, calendar: calendar), seed: 1)
        memory.record(first, on: yesterday, calendar: calendar)

        let now = VoiceTestKit.date(2026, 11, 3, 21)
        let context = GreetingContext(date: now, calendar: calendar)
        let seed = GreetingEngine.dailySeed(for: context)
        var shown = Set<String>()
        for _ in 0..<10 {
            let previous = memory.previousLineID(on: now, calendar: calendar)
            let greeting = GreetingEngine.line(for: context, seed: seed, previousLineID: previous)
            memory.record(greeting, on: now, calendar: calendar)
            shown.insert(greeting.lineID)
        }
        #expect(shown.count == 1)
        #expect(!shown.contains(first.lineID))
    }

    @Test func previousLineIsExcludedFromEveryBucket() {
        // Take the line the engine would show, call it yesterday's, and the new answer must differ.
        var rng = SeededGenerator(seed: 4242)
        for _ in 0..<400 {
            let context = VoiceTestKit.randomContext(&rng)
            let seed = rng.next()
            let first = GreetingEngine.line(for: context, seed: seed)
            let second = GreetingEngine.line(for: context, seed: seed, previousLineID: first.lineID)
            #expect(second.lineID != first.lineID || first.lineID == "fallback")
        }
    }

    // MARK: Robustness

    @Test func everyCombinationOfTheMainFactsReturnsAHeadline() {
        let hours = [2, 6, 9, 12, 15, 16, 18, 21, 23]
        let streaks = [0, 7]
        var count = 0
        var failures: [String] = []
        for hour in hours {
            for weather in GreetingWeather.allCases {
                for book in VoiceTestKit.bookStates {
                    for goal in GreetingGoalState.allCases {
                        for rest in [false, true] {
                            for streak in streaks {
                                var context = GreetingContext(date: VoiceTestKit.date(2026, 10, 18, hour), calendar: calendar, weather: weather, streak: streak, bookState: book, bookTitle: "The Hobbit", goalState: goal, isRestDay: rest)
                                context.minutesToGoal = goal == .partial ? 9 : nil
                                let greeting = GreetingEngine.line(for: context, seed: UInt64(count))
                                count += 1
                                if greeting.headline.trimmingCharacters(in: .whitespaces).isEmpty || greeting.lineID.isEmpty { failures.append("\(context)") }
                            }
                        }
                    }
                }
            }
        }
        #expect(count == 9 * 8 * 10 * 3 * 2 * 2)
        #expect(failures.isEmpty, "\(failures.prefix(3))")
    }

    @Test func randomContextsNeverCrashOrReturnNothing() {
        var rng = SeededGenerator(seed: 777)
        var failures: [String] = []
        for _ in 0..<2500 {
            let context = VoiceTestKit.randomContext(&rng)
            let greeting = GreetingEngine.line(for: context, seed: rng.next(), previousLineID: rng.next() % 3 == 0 ? "junk" : nil)
            let literal = context.bookTitle == "{title}"
            if greeting.headline.isEmpty || (greeting.headline.contains("{") && !literal) { failures.append(greeting.text) }
            if let subline = greeting.subline, subline.isEmpty { failures.append("empty subline: \(greeting.headline)") }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    @Test func greetingsObeyTheToneRulesOnceFilled() {
        var rng = SeededGenerator(seed: 55)
        var failures: [String] = []
        for _ in 0..<1000 {
            let context = VoiceTestKit.randomContext(&rng)
            let greeting = GreetingEngine.line(for: context, seed: rng.next())
            let names = [context.bookTitle, context.teaName].compactMap { $0 } + [VoiceText.shortTitle(context.bookTitle ?? "")]
            let violations = VoiceTone.violations(headline: greeting.headline, subline: greeting.subline, ignoring: names)
                .filter { if case .tooLong = $0 { return false } else { return true } }
            if !violations.isEmpty { failures.append("\(greeting.text): \(violations)") }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    @Test func extremeDatesAreFine() {
        for date in [Date.distantPast, Date.distantFuture, Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: -1e10)] {
            let context = GreetingContext(date: date, calendar: calendar, streak: Int.max, daysSinceLastSession: Int.max)
            let greeting = GreetingEngine.line(for: context, seed: 0)
            #expect(!greeting.headline.isEmpty)
        }
    }

    @Test func templateWriterMatchesTheEngine() async {
        var context = VoiceTestKit.plain(hour: 23)
        context.weather = .rain
        let writer: any GreetingWriter = TemplateGreetingWriter()
        for n in 0..<20 {
            let direct = GreetingEngine.line(for: context, seed: seed(n), previousLineID: "x")
            let viaWriter = await writer.greeting(for: context, seed: seed(n), previousLineID: "x")
            #expect(direct == viaWriter)
        }
    }

    @Test func tagsAndMomentsAreConsistent() {
        for moment in GreetingMoment.allCases {
            for line in GreetingPool.lines(in: moment) { #expect(line.moment == moment) }
            _ = moment.tag
        }
        #expect(GreetingMoment.daypart(.late) == .late)
        #expect(Set(Daypart.allCases.map { GreetingMoment.daypart($0) }).count == Daypart.allCases.count)
        #expect(Set(GreetingHoliday.allCases.map { GreetingMoment.holiday($0) }).count == GreetingHoliday.allCases.count)
        #expect(Set(Season.allCases.map { GreetingMoment.season($0) }).count == 4)
        #expect(GreetingMoment.weather(.unknown) == nil)
        #expect(GreetingMoment.holiday(.christmasSeason).tag == .holiday)
    }
}

struct GreetingMemoryTests {
    let calendar = VoiceTestKit.calendar

    func greeting(_ id: String) -> Greeting {
        Greeting(headline: "Hi.", subline: nil, tag: .daypart, moment: .evening, lineID: id)
    }

    @Test func startsEmpty() {
        var memory = GreetingMemory()
        #expect(memory.previousLineID(on: VoiceTestKit.date(2026, 6, 1), calendar: calendar) == nil)
    }

    @Test func yesterdaysLastLineBecomesThePreviousLine() {
        var memory = GreetingMemory()
        memory.record(greeting("a"), on: VoiceTestKit.date(2026, 6, 1, 8), calendar: calendar)
        memory.record(greeting("b"), on: VoiceTestKit.date(2026, 6, 1, 21), calendar: calendar)
        #expect(memory.previousLineID(on: VoiceTestKit.date(2026, 6, 1, 22), calendar: calendar) == nil)
        #expect(memory.previousLineID(on: VoiceTestKit.date(2026, 6, 2, 8), calendar: calendar) == "b")
        // It stays "b" all day, even after today's lines are recorded.
        memory.record(greeting("c"), on: VoiceTestKit.date(2026, 6, 2, 8), calendar: calendar)
        #expect(memory.previousLineID(on: VoiceTestKit.date(2026, 6, 2, 20), calendar: calendar) == "b")
        #expect(memory.previousLineID(on: VoiceTestKit.date(2026, 6, 3, 8), calendar: calendar) == "c")
    }

    @Test func aGapOfDaysKeepsTheLastLineSeen() {
        var memory = GreetingMemory()
        memory.record(greeting("a"), on: VoiceTestKit.date(2026, 6, 1), calendar: calendar)
        #expect(memory.previousLineID(on: VoiceTestKit.date(2026, 6, 20), calendar: calendar) == "a")
        // Opening and not recording does not lose it.
        #expect(memory.previousLineID(on: VoiceTestKit.date(2026, 6, 21), calendar: calendar) == "a")
    }

    @Test func roundTripsThroughJSON() throws {
        var memory = GreetingMemory()
        memory.record(greeting("a"), on: VoiceTestKit.date(2026, 6, 1), calendar: calendar)
        _ = memory.previousLineID(on: VoiceTestKit.date(2026, 6, 2), calendar: calendar)
        let data = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(GreetingMemory.self, from: data)
        #expect(decoded == memory)
    }
}

// MARK: - Notifications

struct NotificationCopyTests {
    let templates = NotificationCopy.templates
    let calendar = VoiceTestKit.calendar

    @Test func poolIsRichAndEveryKindHasEnough() {
        #expect(templates.count >= 40)
        for kind in NotificationCopy.Kind.allCases {
            #expect(templates.filter { $0.kind == kind }.count >= 3, "\(kind)")
        }
        #expect(Set(templates.map(\.id)).count == templates.count)
        #expect(Set(templates.map { $0.title + $0.body }).count == templates.count)
    }

    @Test func everyTemplateObeysTheToneRules() {
        var failures: [String] = []
        for template in templates {
            let problems = VoiceTemplate.problems(in: template.title) + VoiceTemplate.problems(in: template.body)
            if !problems.isEmpty { failures.append("placeholder \(template.title)") }
            let title = VoiceTone.violations(in: template.title, maxWords: 8)
            let body = VoiceTone.violations(in: template.body, maxWords: 20)
            if !title.isEmpty || !body.isEmpty { failures.append("\(template.title) / \(template.body): \(title + body)") }
            if template.title.contains("Leaf") { failures.append("brand in title: \(template.title)") }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func everyTemplateFitsALockScreenEvenWithTheWorstFacts() {
        let worst = VoiceValues(
            title: String(repeating: "Extraordinarily Long Title ", count: 6),
            pagesLeft: 999, streak: 365, minutes: 240, spellsNumbers: false, maxTitleCharacters: NotificationCopy.maxBookTitleLength
        )
        var failures: [String] = []
        for template in templates {
            guard let title = VoiceTemplate.fill(template.title, with: worst), let body = VoiceTemplate.fill(template.body, with: worst) else {
                failures.append("unfillable with rich facts: \(template.title)")
                continue
            }
            if title.count > NotificationCopy.maxTitleLength { failures.append("title \(title.count): \(title)") }
            if body.count > NotificationCopy.maxBodyLength { failures.append("body \(body.count): \(body)") }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func remindersAreDeterministic() {
        let context = NotificationContext(bookTitle: "The Hobbit", minutes: 20, streak: 4, daypart: .evening)
        for seed in 0..<50 as Range<UInt64> {
            #expect(NotificationCopy.reminder(for: context, seed: seed, previousID: "x") == NotificationCopy.reminder(for: context, seed: seed, previousID: "x"))
        }
    }

    @Test func remindersVaryAcrossDays() {
        let context = NotificationContext(bookTitle: "The Hobbit", minutes: 20, daypart: .evening)
        let ids = Set((0..<40).map { NotificationCopy.reminder(for: context, seed: SeededGenerator.hash("d\($0)")).id })
        #expect(ids.count >= 8)
    }

    @Test func neverTheSameAsTheLastOneOverSixtyDays() {
        let dayparts: [Daypart] = [.morning, .afternoon, .teaTime, .evening, .late]
        var rng = SeededGenerator(seed: 9)
        for daypart in dayparts {
            var days: [NotificationDay] = []
            for offset in 0..<60 {
                let date = VoiceTestKit.date(2026, 11, 2 + offset, 20)
                let context = NotificationContext(
                    bookTitle: rng.next() % 5 == 0 ? nil : "The Hobbit",
                    minutes: Int(rng.next() % 60),
                    streak: Int(rng.next() % 12),
                    isRestDay: rng.next() % 8 == 0,
                    daypart: daypart,
                    pagesLeft: rng.next() % 4 == 0 ? Int(rng.next() % 40) : nil
                )
                days.append(NotificationDay(context: context, seed: SeededGenerator.daySeed(date, calendar: calendar)))
            }
            let messages = NotificationCopy.series(days)
            #expect(messages.count == 60)
            for (a, b) in zip(messages, messages.dropFirst()) { #expect(a.id != b.id, "\(daypart): \(a.title)") }
            // The first message also avoids the one handed in from before.
            let continued = NotificationCopy.series(days, previousID: messages[0].id)
            #expect(continued[0].id != messages[0].id)
        }
    }

    @Test func aRestDayGetsRestDayCopy() {
        let restIDs = Set(templates.filter { $0.kind == .restDay }.map(\.id))
        for n in 0..<60 {
            let context = NotificationContext(bookTitle: "The Hobbit", minutes: 20, streak: 9, isRestDay: true, daypart: .evening, pagesLeft: 5)
            #expect(restIDs.contains(NotificationCopy.reminder(for: context, seed: SeededGenerator.hash("r\(n)")).id))
        }
    }

    @Test func aBookNearItsEndSometimesSaysSo() {
        let context = NotificationContext(bookTitle: "The Hobbit", minutes: 20, daypart: .evening, pagesLeft: 5)
        let messages = (0..<200).map { NotificationCopy.reminder(for: context, seed: SeededGenerator.hash("n\($0)")) }
        let near = messages.filter { $0.title.contains("Almost") || $0.body.contains("5 pages") }
        #expect(near.count > 40)
        #expect(messages.contains { !$0.body.contains("5 pages") })
        // Far from the end: never.
        let far = NotificationContext(bookTitle: "The Hobbit", minutes: 20, daypart: .evening, pagesLeft: 200)
        #expect(!(0..<100).contains { NotificationCopy.reminder(for: far, seed: SeededGenerator.hash("f\($0)")).body.contains("200 pages") })
    }

    @Test func aRunOfDaysIsMentionedNowAndThenAndNeverThreatened() {
        let context = NotificationContext(bookTitle: "The Hobbit", minutes: 20, streak: 12, daypart: .evening)
        let messages = (0..<300).map { NotificationCopy.reminder(for: context, seed: SeededGenerator.hash("s\($0)")) }
        let mentions = messages.filter { ($0.title + $0.body).contains("12") }
        #expect(mentions.count > 20 && mentions.count < 150, "\(mentions.count)")
        for message in messages {
            #expect(VoiceTone.violations(in: message.title + " " + message.body, maxWords: 30, ignoring: ["The Hobbit"]).isEmpty)
        }
        // Not on a short run.
        let short = NotificationContext(bookTitle: "The Hobbit", minutes: 20, streak: 2, daypart: .evening)
        #expect(!(0..<100).contains { NotificationCopy.reminder(for: short, seed: SeededGenerator.hash("t\($0)")).title.contains("days in a row") })
    }

    @Test func missingFactsNeverLeakPlaceholders() {
        var rng = SeededGenerator(seed: 31)
        var failures: [String] = []
        for _ in 0..<1500 {
            let title = [nil, "", "The Hobbit", String(repeating: "Very Long Title ", count: 20)][Int(rng.next() % 4)]
            let context = NotificationContext(
                bookTitle: title,
                minutes: [-5, 0, 1, 15, 1000][Int(rng.next() % 5)],
                streak: [-1, 0, 2, 3, 400][Int(rng.next() % 5)],
                isRestDay: rng.next() % 5 == 0,
                daypart: Daypart.allCases[Int(rng.next() % 9)],
                pagesLeft: [nil, -4, 0, 1, 12, 31, 500][Int(rng.next() % 7)]
            )
            let message = NotificationCopy.reminder(for: context, seed: rng.next(), previousID: rng.next() % 2 == 0 ? nil : "junk")
            let text = message.title + " " + message.body
            if text.contains("{") || text.contains("}") || message.title.isEmpty || message.body.isEmpty { failures.append(text) }
            if message.title.count > NotificationCopy.maxTitleLength || message.body.count > NotificationCopy.maxBodyLength { failures.append("long: \(text)") }
            if text.contains(" 0 ") || text.contains("-") && text.contains("minutes") { failures.append("odd number: \(text)") }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    @Test func goalReachedNudgeMentionsTheMinutes() {
        var bodies = Set<String>()
        for n in 0..<120 {
            let message = NotificationCopy.goalReached(minutes: 25, seed: SeededGenerator.hash("g\(n)"))
            #expect(!message.title.isEmpty && !message.body.isEmpty)
            #expect(!(message.title + message.body).contains("{"))
            #expect(message.title.count <= NotificationCopy.maxTitleLength && message.body.count <= NotificationCopy.maxBodyLength)
            bodies.insert(message.body)
        }
        #expect(bodies.count >= 4)
        #expect(bodies.contains("That’s today’s 25 minutes. Anything more is a gift."))
        let none = NotificationCopy.goalReached(minutes: 0, seed: 1)
        #expect(!(none.title + none.body).contains("{") && !(none.title + none.body).contains(" 0 "))
        let again = NotificationCopy.goalReached(minutes: 25, seed: 4, previousID: NotificationCopy.goalReached(minutes: 25, seed: 4).id)
        #expect(again.id != NotificationCopy.goalReached(minutes: 25, seed: 4).id)
    }
}

// MARK: - Session wrap-up

struct SessionWrapUpTests {
    @Test func theRightKindWins() {
        func kind(pages: Int = 10, minutes: Double = 20, goal: Bool = false, finished: Bool = false, best: Bool = false) -> SessionWrapUpLine.Kind {
            SessionWrapUp.kind(for: SessionWrapUpInput(pagesRead: pages, minutes: minutes, goalMetNow: goal, bookFinished: finished, isPersonalBest: best))
        }
        #expect(kind(goal: true, finished: true, best: true) == .bookFinished)
        #expect(kind(goal: true, best: true) == .personalBest)
        #expect(kind(goal: true) == .goalMet)
        #expect(kind(pages: 0) == .quiet)
        #expect(kind(minutes: 50) == .longSitting)
        #expect(kind(minutes: 3) == .quick)
        #expect(kind(pages: 1, minutes: 20) == .quick)
        #expect(kind() == .regular)
        #expect(kind(pages: 0, goal: true) == .goalMet)
    }

    @Test func detailsAlwaysCarryTheRealNumbers() {
        #expect(SessionWrapUp.detail(pages: 12, minutes: 25) == "12 pages in 25 min")
        #expect(SessionWrapUp.detail(pages: 1, minutes: 25) == "1 page in 25 min")
        #expect(SessionWrapUp.detail(pages: 12, minutes: 0.1) == "12 pages")
        #expect(SessionWrapUp.detail(pages: 0, minutes: 25) == "25 min with the book")
        #expect(SessionWrapUp.detail(pages: 0, minutes: 0) == "A moment with the book")
        #expect(SessionWrapUp.detail(pages: 20, minutes: 65) == "20 pages in 1 h 5 min")
        #expect(SessionWrapUp.detail(pages: -4, minutes: -9) == "A moment with the book")
        #expect(SessionWrapUp.detail(pages: 3, minutes: .nan) == "3 pages")
        #expect(SessionWrapUp.detail(pages: 3, minutes: .infinity) == "3 pages")
        #expect(!SessionWrapUp.detail(pages: Int.max, minutes: 1e12).isEmpty)
    }

    @Test func everyKindHasEnoughLinesAllOfThemKind() {
        for kind in SessionWrapUpLine.Kind.allCases {
            let lines = SessionWrapUp.templates[kind] ?? []
            #expect(lines.count >= 4, "\(kind)")
            let bare = lines.filter { VoiceTemplate.placeholders(in: $0).isEmpty }
            #expect(bare.count >= 3, "\(kind) needs three lines that don't depend on a title")
            for line in lines {
                #expect(VoiceTone.violations(in: line, maxWords: 12).isEmpty, "\(line)")
                #expect(VoiceTemplate.problems(in: line).isEmpty, "\(line)")
                #expect(line.count <= 60, "\(line)")
            }
            #expect(Set(lines).count == lines.count)
        }
    }

    @Test func linesAreDeterministicAndVary() {
        let input = SessionWrapUpInput(pagesRead: 14, minutes: 25)
        #expect(SessionWrapUp.line(for: input, seed: 5) == SessionWrapUp.line(for: input, seed: 5))
        let headlines = Set((0..<60).map { SessionWrapUp.line(for: input, seed: SeededGenerator.hash("w\($0)")).headline })
        #expect(headlines.count >= 5)
    }

    @Test func neverRepeatsThePreviousLine() {
        for kindInput in [
            SessionWrapUpInput(pagesRead: 14, minutes: 25),
            SessionWrapUpInput(pagesRead: 30, minutes: 60, goalMetNow: true),
            SessionWrapUpInput(pagesRead: 30, minutes: 60, bookFinished: true, bookTitle: "The Hobbit"),
            SessionWrapUpInput(pagesRead: 0, minutes: 4),
        ] {
            var previous: String?
            for n in 0..<60 {
                let line = SessionWrapUp.line(for: kindInput, seed: SeededGenerator.hash("p\(n)"), previousID: previous)
                #expect(line.id != previous)
                previous = line.id
            }
        }
    }

    @Test func titlesAreUsedWhenKnownAndNeverRequired() {
        let withTitle = SessionWrapUpInput(pagesRead: 30, minutes: 40, bookFinished: true, bookTitle: "The Hobbit")
        let texts = (0..<120).map { SessionWrapUp.line(for: withTitle, seed: SeededGenerator.hash("t\($0)")).headline }
        #expect(texts.contains { $0.contains("The Hobbit") })
        let without = SessionWrapUpInput(pagesRead: 30, minutes: 40, bookFinished: true)
        for n in 0..<120 {
            let line = SessionWrapUp.line(for: without, seed: SeededGenerator.hash("t\(n)"))
            #expect(!line.headline.contains("{") && !line.headline.isEmpty)
        }
    }

    @Test func goalMetIsNotLostWhenABookIsFinished() {
        let input = SessionWrapUpInput(pagesRead: 30, minutes: 40, goalMetNow: true, bookFinished: true)
        let line = SessionWrapUp.line(for: input, seed: 3)
        #expect(line.kind == .bookFinished)
        #expect(line.detail.contains("goal is done"))
    }

    @Test func randomInputsAreSafeAndKind() {
        var rng = SeededGenerator(seed: 8)
        var failures: [String] = []
        for _ in 0..<1000 {
            let input = SessionWrapUpInput(
                pagesRead: [-3, 0, 1, 2, 40, 1_000_000][Int(rng.next() % 6)],
                minutes: [-1, 0, 0.2, 3, 25, 50, 600, .nan, .infinity][Int(rng.next() % 9)],
                goalMetNow: rng.next() % 2 == 0, bookFinished: rng.next() % 3 == 0, isPersonalBest: rng.next() % 3 == 0,
                bookTitle: [nil, "", "The Lost Boys", String(repeating: "Long ", count: 40)][Int(rng.next() % 4)]
            )
            let line = SessionWrapUp.line(for: input, seed: rng.next())
            if line.headline.isEmpty || line.detail.isEmpty || line.headline.contains("{") { failures.append("\(input)") }
            let names = [input.bookTitle ?? "", VoiceText.shortTitle(input.bookTitle ?? "", maxCharacters: 32)]
            if !VoiceTone.violations(in: line.headline, maxWords: 20, ignoring: names).isEmpty { failures.append(line.headline) }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }
}

// MARK: - Live Activity and watch

struct GlanceLinesTests {
    let longTitle = String(repeating: "Extraordinarily Long Title ", count: 8)

    @Test func liveActivityLinesNeverExceedTwentyEightCharacters() {
        var failures: [String] = []
        for moment in LiveActivityMoment.allCases {
            for title in [nil, "", "Dune", "The Hobbit", longTitle, "Émile & Zoë’s “Quotes”"] as [String?] {
                for minutes in [nil, 0, 1, 13, 120] as [Int?] {
                    for pages in [nil, 0, 1, 11, 999] as [Int?] {
                        for seed in 0..<12 as Range<UInt64> {
                            let line = LiveActivityLines.line(for: moment, bookTitle: title, minutesToGoal: minutes, pagesLeft: pages, seed: seed)
                            if line.isEmpty || line.count > LiveActivityLines.maxLength || line.contains("{") { failures.append("\(moment): \(line)") }
                        }
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
        #expect(LiveActivityLines.maxLength == 28)
    }

    @Test func liveActivityTemplatesAreSoundAndMostFitAsWritten() {
        for moment in LiveActivityMoment.allCases {
            let templates = LiveActivityLines.templates[moment] ?? []
            #expect(templates.count >= 5, "\(moment)")
            #expect(Set(templates).count == templates.count)
            let plain = templates.filter { VoiceTemplate.placeholders(in: $0).isEmpty }
            #expect(plain.count >= 3, "\(moment) needs lines that need nothing")
            for template in plain {
                #expect(template.count <= LiveActivityLines.maxLength, "\(template)")
            }
            for template in templates {
                #expect(VoiceTemplate.problems(in: template).isEmpty)
                #expect(VoiceTone.violations(in: template, maxWords: 8).isEmpty, "\(template)")
                #expect(!template.contains("!"))
            }
            #expect(LiveActivityLines.fallback(for: moment).count <= LiveActivityLines.maxLength)
        }
    }

    @Test func liveActivityLinesAreStablePerSeedAndVary() {
        for moment in LiveActivityMoment.allCases {
            #expect(LiveActivityLines.line(for: moment, bookTitle: "Dune", seed: 7) == LiveActivityLines.line(for: moment, bookTitle: "Dune", seed: 7))
            let lines = Set((0..<60).map { LiveActivityLines.line(for: moment, bookTitle: "Dune", minutesToGoal: 12, pagesLeft: 9, seed: SeededGenerator.hash("l\($0)")) })
            #expect(lines.count >= 3, "\(moment)")
        }
    }

    @Test func liveActivityTitlesAreShortenedToFit() {
        var sawTitle = false
        for seed in 0..<80 as Range<UInt64> {
            let line = LiveActivityLines.line(for: .reading, bookTitle: longTitle, seed: seed)
            #expect(line.count <= 28)
            if line.contains("Extraordinarily") { sawTitle = true }
        }
        #expect(sawTitle)
        #expect(LiveActivityLines.fit("Reading {title}", title: "Dune", minutes: nil, pagesLeft: nil) == "Reading Dune")
        #expect(LiveActivityLines.fit("Reading {title}", title: nil, minutes: nil, pagesLeft: nil) == nil)
    }

    @Test func watchLinesNeverExceedTwentyCharacters() {
        var failures: [String] = []
        for moment in WatchLines.Moment.allCases {
            let templates = WatchLines.stateTemplates[moment] ?? []
            #expect(templates.count >= 3, "\(moment)")
            for template in templates where template.count > WatchLines.maxLength { failures.append(template) }
            for seed in 0..<30 as Range<UInt64> {
                let line = WatchLines.line(for: moment, seed: seed)
                if line.isEmpty || line.count > WatchLines.maxLength { failures.append(line) }
            }
        }
        for daypart in Daypart.allCases {
            let pool = WatchLines.greetings[daypart] ?? []
            #expect(pool.count >= 3, "\(daypart)")
            for line in pool where line.count > WatchLines.maxLength { failures.append(line) }
        }
        #expect(failures.isEmpty, "\(failures)")
        #expect(WatchLines.maxLength == 20)
    }

    @Test func watchLinesObeyTheToneRules() {
        let all = WatchLines.stateTemplates.values.flatMap { $0 } + WatchLines.greetings.values.flatMap { $0 }
        for line in all {
            #expect(VoiceTone.violations(in: line, maxWords: 5).isEmpty, "\(line)")
            #expect(!line.contains("{"))
        }
        #expect(Set(all).count >= all.count - 3)
    }

    @Test func watchGreetingFollowsTheMomentAndTheHour() {
        let calendar = VoiceTestKit.calendar
        func line(_ context: GreetingContext, _ n: UInt64 = 1) -> String { WatchLines.greeting(for: context, seed: n) }

        var context = VoiceTestKit.plain(hour: 23, minute: 30)
        let late = Set((0..<60 as Range<UInt64>).map { line(context, $0) })
        #expect(late.contains("Still up?"))
        #expect(late.isSubset(of: Set(WatchLines.greetings[.late] ?? [])))

        context.goalState = .met
        #expect(Set(WatchLines.stateTemplates[.goalReached] ?? []).contains(line(context)))
        context = VoiceTestKit.plain()
        context.isRestDay = true
        #expect(Set(WatchLines.stateTemplates[.restDay] ?? []).contains(line(context)))
        context = VoiceTestKit.plain()
        context.bookState = .nearFinish(pagesLeft: 8)
        #expect(Set(WatchLines.stateTemplates[.almostThere] ?? []).contains(line(context)))
        context.bookState = .finishedToday
        #expect(Set(WatchLines.stateTemplates[.bookFinished] ?? []).contains(line(context)))

        for hour in [2, 6, 9, 12, 15, 16, 18, 20, 23] {
            let ctx = GreetingContext(date: VoiceTestKit.date(2026, 6, 17, hour), calendar: calendar)
            for n in 0..<20 as Range<UInt64> {
                let text = line(ctx, n)
                #expect(text.count <= 20 && !text.isEmpty)
            }
        }
    }

    @Test func watchGreetingNeverRepeatsThePreviousLine() {
        let context = VoiceTestKit.plain(hour: 9)
        var previous: String?
        for n in 0..<80 as Range<UInt64> {
            let text = WatchLines.greeting(for: context, seed: n, previousLine: previous)
            #expect(text != previous)
            previous = text
        }
        var statePrevious: String?
        for n in 0..<80 as Range<UInt64> {
            let text = WatchLines.line(for: .paused, seed: n, previousLine: statePrevious)
            #expect(text != statePrevious)
            statePrevious = text
        }
    }
}

// MARK: - Weekly letter

struct WeeklyLetterTextTests {
    func input(minutes: Double = 250, cups: Int = 10, pages: Int = 142, finished: Int = 0, titles: [String] = [], days: Int = 5, bestDay: Int? = 3, bestMinutes: Double? = 52, streak: Int = 0, last: Double? = nil) -> WeeklyLetterInput {
        WeeklyLetterInput(minutes: minutes, cups: cups, pages: pages, booksFinished: finished, finishedTitles: titles, daysRead: days, bestDayWeekday: bestDay, bestDayMinutes: bestMinutes, streak: streak, lastWeekMinutes: last)
    }

    func sentenceCount(of text: String) -> Int {
        var count = 0
        let characters = Array(text)
        for (index, character) in characters.enumerated() where ".?".contains(character) {
            let next = index + 1 < characters.count ? characters[index + 1] : " "
            if next == " " { count += 1 }
        }
        return count
    }

    @Test func alwaysThreeToFiveSentences() {
        var rng = SeededGenerator(seed: 12)
        var failures: [String] = []
        for _ in 0..<1500 {
            let letter = WeeklyLetterText.compose(
                WeeklyLetterInput(
                    minutes: [-30, 0, 0.2, 20, 90, 250, 600, 10_000, .nan, .infinity][Int(rng.next() % 10)],
                    cups: [-2, 0, 1, 3, 40][Int(rng.next() % 5)],
                    pages: [-5, 0, 1, 90, 5000][Int(rng.next() % 5)],
                    booksFinished: [-1, 0, 1, 2, 5][Int(rng.next() % 5)],
                    finishedTitles: [[], ["The Hobbit"], ["The Hobbit", "Dune"], ["", " "]][Int(rng.next() % 4)],
                    daysRead: [-1, 0, 1, 5, 7][Int(rng.next() % 5)],
                    bestDayWeekday: [nil, 0, 1, 4, 7, 12][Int(rng.next() % 6)],
                    bestDayMinutes: [nil, 0, 30, .nan, 400][Int(rng.next() % 5)],
                    streak: [0, 2, 3, 30, 400][Int(rng.next() % 5)],
                    lastWeekMinutes: [nil, 0, -5, 100, 250, 500, .nan][Int(rng.next() % 7)]
                ),
                seed: rng.next()
            )
            if !(3...5).contains(letter.sentences.count) { failures.append("count \(letter.sentences.count): \(letter.body)") }
            if sentenceCount(of: letter.body) != letter.sentences.count { failures.append("split: \(letter.body)") }
            for sentence in letter.sentences where !(sentence.hasSuffix(".") || sentence.hasSuffix("?")) { failures.append("end: \(sentence)") }
            if letter.body.contains("{") || letter.body.contains("nan") || letter.body.contains("inf") { failures.append(letter.body) }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    @Test func aFullWeekMentionsTheRealNumbers() {
        let letter = WeeklyLetterText.compose(input(minutes: 250, cups: 10, pages: 142, finished: 1, titles: ["The Hobbit"], streak: 12, last: 200), seed: 1)
        #expect(letter.sentences.count == 5)
        #expect(letter.body.contains("4 h 10 min"))
        #expect(letter.body.contains("142 pages"))
        #expect(letter.body.contains("10 cups"))
        #expect(letter.body.contains("5 days"))
        #expect(letter.body.contains("You finished The Hobbit."))
        #expect(letter.body.contains("12 days in a row"))
        #expect(WeeklyLetterText.titles.contains(letter.title))
    }

    @Test func aQuietWeekIsGentleAndShort() {
        let letter = WeeklyLetterText.compose(input(minutes: 0, cups: 0, pages: 0, days: 0, bestDay: nil, bestMinutes: nil), seed: 4)
        #expect(letter.sentences.count == 3)
        #expect(!letter.body.contains("0 min") && !letter.body.contains("0 pages") && !letter.body.contains("0 cups"))
        #expect(VoiceTone.violations(in: letter.body, maxWords: 60).isEmpty)
    }

    @Test func comparisonFollowsTheNumbers() {
        func body(_ minutes: Double, last: Double?) -> String {
            WeeklyLetterText.compose(input(minutes: minutes, last: last), seed: 6).body
        }
        let up = Set((0..<40).map { WeeklyLetterText.compose(input(minutes: 300, last: 100), seed: SeededGenerator.hash("u\($0)")).body })
        #expect(up.contains { $0.contains("more") })
        let down = Set((0..<40).map { WeeklyLetterText.compose(input(minutes: 100, last: 300), seed: SeededGenerator.hash("d\($0)")).body })
        #expect(down.allSatisfy { $0.contains("fine") || $0.contains("allowed") || $0.contains("softer") || $0.contains("quieter") || $0.contains("fewer") })
        let same = Set((0..<40).map { WeeklyLetterText.compose(input(minutes: 250, last: 245), seed: SeededGenerator.hash("s\($0)")).body })
        #expect(same.allSatisfy { $0.contains("last week") })
        #expect(!body(250, last: nil).contains("last week"))
        #expect(!body(250, last: 0).contains("last week"))
    }

    @Test func bestDayAndFinishedBooksAreNamed() {
        let letter = WeeklyLetterText.compose(input(finished: 0, bestDay: 3, bestMinutes: 52), seed: 2)
        #expect(letter.body.contains("Tuesday was your best day, with 52 min."))
        let two = WeeklyLetterText.compose(input(finished: 2, titles: ["The Hobbit", "Dune"]), seed: 2)
        #expect(two.body.contains("You finished two books, The Hobbit and Dune."))
        let many = WeeklyLetterText.compose(input(finished: 4), seed: 2)
        #expect(many.body.contains("You finished four books."))
        let untitled = WeeklyLetterText.compose(input(finished: 1), seed: 2)
        #expect(untitled.body.contains("You finished a book this week."))
    }

    @Test func isDeterministicAndVaries() {
        let a = input(finished: 1, titles: ["Dune"], streak: 5, last: 100)
        #expect(WeeklyLetterText.compose(a, seed: 9) == WeeklyLetterText.compose(a, seed: 9))
        let bodies = Set((0..<60).map { WeeklyLetterText.compose(a, seed: SeededGenerator.hash("v\($0)")).body })
        #expect(bodies.count >= 12)
    }

    @Test func everyLetterIsWarm() {
        var rng = SeededGenerator(seed: 77)
        var failures: [String] = []
        for _ in 0..<800 {
            let letter = WeeklyLetterText.compose(
                input(minutes: [0, 30, 200, 900][Int(rng.next() % 4)], cups: Int(rng.next() % 30), pages: Int(rng.next() % 500), finished: Int(rng.next() % 3), titles: ["The Lost Boys", "Dune"], days: Int(rng.next() % 8), streak: Int(rng.next() % 40), last: [nil, 0, 100, 400][Int(rng.next() % 4)]),
                seed: rng.next()
            )
            let violations = VoiceTone.violations(in: letter.body, maxWords: 90, ignoring: ["The Lost Boys"])
            if !violations.isEmpty { failures.append("\(letter.body): \(violations)") }
        }
        #expect(failures.isEmpty, "\(failures.prefix(3))")
    }
}

// MARK: - Optional AI

struct AIGreetingPromptTests {
    let context = VoiceTestKit.plain(hour: 21)

    @Test func acceptsAGentleSingleSentence() {
        #expect(AIGreetingPrompt.clean("Evenings like this suit a good chapter.", context: context) == "Evenings like this suit a good chapter.")
        #expect(AIGreetingPrompt.clean("  Kettle on, book open?  \n", context: context) == "Kettle on, book open?")
    }

    @Test func tidiesQuotesApostrophesAndTheFinalStop() {
        #expect(AIGreetingPrompt.clean("\"The lamp's on and the page is waiting\"", context: context) == "The lamp’s on and the page is waiting.")
        #expect(AIGreetingPrompt.clean("“A quiet evening for a book.”", context: context) == "A quiet evening for a book.")
    }

    @Test func rejectsAnythingThatBreaksTheToneRules() {
        let bad = [
            "", "   ", "Read now!", "One more page.\nThen bed.", "Time for a chapter. Then another.",
            "Don't lose your place tonight.", "You're falling behind on your book.", "We missed you this week.",
            "A very long sentence that keeps going on and on well past the limit.", "Hi.", "Day 7 of reading.",
            "Open your book ✨ tonight.", "Reading: a nice idea.", "A #cozy evening.", "Dear reader, *hello* there.",
            "Keep your streak alive tonight.", "Don’t break the streak tonight.",
        ]
        for text in bad { #expect(AIGreetingPrompt.clean(text, context: context) == nil, "\(text)") }
    }

    @Test func aBookTitleDoesNotTripTheGuiltFilter() {
        var withTitle = context
        withTitle.bookTitle = "The Lost Boys"
        #expect(AIGreetingPrompt.clean("The Lost Boys is waiting for you.", context: withTitle) != nil)
        #expect(AIGreetingPrompt.clean("The Lost Boys is waiting for you.", context: context) == nil)
        #expect(AIGreetingPrompt.clean("You lost your place in The Lost Boys.", context: withTitle) == nil)
    }

    @Test func wordLimitsAreExact() {
        let ten = "One two three four five six seven eight nine ten."
        let eleven = "One two three four five six seven eight nine ten eleven."
        #expect(AIGreetingPrompt.clean(ten, context: context) != nil)
        #expect(AIGreetingPrompt.clean(eleven, context: context) == nil)
        #expect(AIGreetingPrompt.clean("Hello there.", context: context) != nil)
    }

    @Test func generatedGreetingsAreTaggedAndIdentified() {
        let greeting = AIGreetingPrompt.greeting(from: "A quiet evening for a book.", context: context)
        #expect(greeting.tag == .generated)
        #expect(greeting.moment == nil)
        #expect(greeting.subline == nil)
        #expect(greeting.lineID.hasPrefix("generated."))
        #expect(greeting.lineID == AIGreetingPrompt.greeting(from: "A quiet evening for a book.", context: context).lineID)
    }

    @Test func onlyAmbientGreetingsAreEligible() {
        for tag in GreetingTag.allCases {
            let greeting = Greeting(headline: "x", subline: nil, tag: tag, moment: nil, lineID: "x")
            let expected: Set<GreetingTag> = [.daypart, .weather, .season, .weekday, .moon, .book]
            #expect(AIGreetingPrompt.isEligible(greeting) == expected.contains(tag), "\(tag)")
        }
    }

    @Test func promptHoldsOnlyFactsAndTheInstructionsHoldTheRules() {
        var rich = context
        rich.weather = .rain
        rich.bookTitle = "The Hobbit"
        rich.isRestDay = true
        rich.moon = .full
        let prompt = AIGreetingPrompt.prompt(for: rich)
        for fragment in ["evening", "Wednesday", "summer", "rain", "full moon", "The Hobbit", "rest day"] {
            #expect(prompt.contains(fragment), "\(fragment)")
        }
        #expect(!prompt.contains("!"))
        #expect(!AIGreetingPrompt.prompt(for: context).contains("Weather"))
        #expect(!AIGreetingPrompt.prompt(for: context).contains("The Hobbit"))
        let rules = AIGreetingPrompt.instructions.lowercased()
        for fragment in ["one short sentence", "fewer than 10 words", "exclamation", "guilt", "only the facts"] {
            #expect(rules.contains(fragment), "\(fragment)")
        }
    }

    @Test func promptShortensLongTitles() {
        var long = context
        long.bookTitle = "A Short History of Nearly Everything: And Other Long Subtitles"
        let prompt = AIGreetingPrompt.prompt(for: long)
        #expect(!prompt.contains("Subtitles"))
        #expect(prompt.contains("A Short History of Nearly Everything"))
    }
}
