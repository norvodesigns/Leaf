import Foundation

/// "Still up?" works because it sounds like a person who noticed. This is that person, for the whole app.
///
/// Pure and deterministic: the context plus the daily seed pick the line, so a re-render never flickers, and the
/// previous day's line is passed in so the voice never says the same thing two days running.
///
/// What wins, in order:
/// 1. First ever launch.
/// 2. Close to the end of the book. 3. Finished a book today.
/// 4. Welcome back after a gap (first launch of the day only).
/// 5. Today's goal met. 6. Rest day. 7. A streak milestone (7, 14, 30, 100 ...). 8. A stalled book.
/// 9. The day itself, if it is a holiday.
/// 10. Otherwise, some of the time (more by day than at night, so "Still up?" keeps its place): a nudge toward the
///     goal, or the weather, moon, streak, book, weekday, season or a holiday season, weighted among whatever applies.
/// 11. The time of day.
enum GreetingEngine {
    /// How often the optional "ambient" sources (weather, season ...) take the turn from the time-of-day line.
    static func ambientChance(for daypart: Daypart) -> Double {
        switch daypart {
        case .late: return 0.25
        case .smallHours: return 0.4
        default: return 0.55
        }
    }

    /// Streak lengths that get a celebration of their own.
    static let streakMilestones: Set<Int> = [7, 14, 21, 30, 50, 75, 100, 150, 200, 250, 300, 365]

    static func isStreakMilestone(_ streak: Int) -> Bool {
        streakMilestones.contains(streak) || (streak > 365 && streak % 100 == 0)
    }

    /// Days away before "welcome back" and "a long time" lines.
    static let welcomeBackAfterDays = 3
    static let welcomeBackLongAfterDays = 14

    /// One seed per calendar day, for callers that do not have their own.
    static func dailySeed(for context: GreetingContext) -> UInt64 {
        SeededGenerator.daySeed(context.date, calendar: context.calendar)
    }

    // MARK: Entry point

    /// The greeting for this moment. `previousLineID` is the id of the last line shown on the day before; keep passing
    /// the same value all day (see `GreetingMemory`) or the line will change under the reader's thumb.
    static func line(for context: GreetingContext, seed: UInt64, previousLineID: String? = nil) -> Greeting {
        line(for: context, seed: seed, avoiding: previousLineID.map { [$0] } ?? [])
    }

    /// A greeting that steers clear of the lines in `recent` (newest first): Today asks for a fresh one, with a fresh
    /// seed, every time the app is opened. The same buckets win as always; inside one, a line shown lately is never
    /// picked while the bucket has another, and the newest (the line on screen a moment ago) is never picked at all.
    static func line(for context: GreetingContext, seed: UInt64, avoiding recent: [String]) -> Greeting {
        let values = self.values(for: context)

        for moment in priorityMoments(for: context) {
            let options = eligible(moment, context: context, values: values, avoiding: recent)
            if let pick = VoiceText.choose(options, seed: seed, salt: "line|\(moment.rawValue)|\(context.daypart.rawValue)", weight: { $0.line.weight }) {
                return greeting(from: pick)
            }
        }

        if let pick = ambientPick(context: context, values: values, seed: seed, avoiding: recent) {
            return greeting(from: pick)
        }

        let timeOfDay = GreetingMoment.daypart(context.daypart)
        let options = eligible(timeOfDay, context: context, values: values, avoiding: recent)
        if let pick = VoiceText.choose(options, seed: seed, salt: "line|\(timeOfDay.rawValue)|\(context.daypart.rawValue)", weight: { $0.line.weight }) {
            return greeting(from: pick)
        }

        // Unreachable with the shipped pool (every daypart has a dozen lines), but never return nothing.
        let anyLine = eligible(timeOfDay, context: context, values: values, avoiding: [])
        if let pick = anyLine.first { return greeting(from: pick) }
        return Greeting(headline: "Hello, reader.", subline: "Your book is ready when you are.", tag: .daypart, moment: nil, lineID: "fallback")
    }

    /// The buckets that outrank everything else for this context, best first. Exposed so tests (and curious readers
    /// of the code) can see the order without running the whole engine.
    static func priorityMoments(for context: GreetingContext) -> [GreetingMoment] {
        var result: [GreetingMoment] = []
        if context.isFirstEverLaunch { result.append(.firstEver) }
        if case .nearFinish(let left) = context.bookState, left > 0 { result.append(.nearFinish) }
        if context.bookState == .finishedToday { result.append(.finishedToday) }
        if context.isFirstLaunchOfDay, let gap = context.daysSinceLastSession {
            if gap >= welcomeBackLongAfterDays {
                result.append(.welcomeBackLong)
            } else if gap >= welcomeBackAfterDays {
                result.append(.welcomeBack)
            }
        }
        if context.goalState == .met { result.append(.goalMet) }
        if context.isRestDay { result.append(.restDay) }
        if isStreakMilestone(context.streak) { result.append(milestoneMoment(for: context.streak)) }
        if context.bookState == .stalled { result.append(.stalled) }
        if let holiday = context.holiday, !holiday.isWindow { result.append(GreetingMoment.holiday(holiday)) }
        return result
    }

    static func milestoneMoment(for streak: Int) -> GreetingMoment {
        switch streak {
        case 7: return .streakWeek
        case 14: return .streakFortnight
        case 30: return .streakMonth
        case 100: return .streakCentury
        default: return .streakOther
        }
    }

    // MARK: Facts

    /// The facts the context can offer to a template.
    static func values(for context: GreetingContext) -> VoiceValues {
        var values = VoiceValues()
        values.title = VoiceText.clean(context.bookTitle)
        if case .nearFinish(let left) = context.bookState, left > 0 { values.pagesLeft = left }
        if context.streak >= 2 { values.streak = context.streak }
        if let minutes = context.minutesToGoal, minutes > 0 { values.minutes = minutes }
        values.tea = VoiceText.clean(context.teaName)
        values.day = context.weekdayName
        return values
    }

    // MARK: Candidates

    private struct Rendered {
        var line: GreetingLine
        var headline: String
        var subline: String?
    }

    private static func greeting(from pick: Rendered) -> Greeting {
        Greeting(headline: pick.headline, subline: pick.subline, tag: pick.line.moment.tag, moment: pick.line.moment, lineID: pick.line.id)
    }

    /// The lines in a bucket that suit this hour, can be filled from what we know, and were not shown lately: none of
    /// `recent` while the bucket has anything else, and never the newest of them.
    private static func eligible(_ moment: GreetingMoment, context: GreetingContext, values: VoiceValues, avoiding recent: [String]) -> [Rendered] {
        let all = renderable(moment, context: context, values: values)
        let fresh = all.filter { !recent.contains($0.line.id) }
        guard fresh.isEmpty, recent.count > 1 else { return fresh }
        return all.filter { $0.line.id != recent.first }
    }

    /// The lines in a bucket that suit this hour and can be filled from what we know.
    private static func renderable(_ moment: GreetingMoment, context: GreetingContext, values: VoiceValues) -> [Rendered] {
        let available = values.available
        var result: [Rendered] = []
        for line in GreetingPool.lines(in: moment) {
            if let dayparts = line.dayparts, !dayparts.contains(context.daypart) { continue }
            guard line.placeholders.isSubset(of: available), let headline = VoiceTemplate.fill(line.headline, with: values, available: available) else { continue }
            var subline: String?
            if let template = line.subline {
                guard let filled = VoiceTemplate.fill(template, with: values, available: available) else { continue }
                subline = filled
            }
            result.append(Rendered(line: line, headline: headline, subline: subline))
        }
        return result
    }

    // MARK: Ambient sources

    /// With the ambient chance, one of the sources that apply right now takes the turn, weighted so a rainy Sunday is
    /// more likely to talk about rain than about the season.
    private static func ambientPick(context: GreetingContext, values: VoiceValues, seed: UInt64, avoiding recent: [String]) -> Rendered? {
        let daypart = context.daypart.rawValue
        guard VoiceText.chance(ambientChance(for: context.daypart), seed: seed, salt: "ambient|\(daypart)") else { return nil }

        var sources: [(moment: GreetingMoment, weight: Double)] = []
        if context.goalState == .partial, (context.minutesToGoal ?? 0) > 0 { sources.append((.goalPartial, 3)) }
        if let holiday = context.holiday, holiday.isWindow { sources.append((GreetingMoment.holiday(holiday), 3)) }
        if let weather = GreetingMoment.weather(context.weather) {
            let weight: Double
            switch context.weather {
            case .rain, .snow: weight = 4
            case .clear: weight = 2
            default: weight = 3
            }
            sources.append((weather, weight))
        }
        switch context.moon {
        case .full: sources.append((.fullMoon, 3))
        case .new: sources.append((.newMoon, 1.5))
        default: break
        }
        if context.streak >= 3, !isStreakMilestone(context.streak) { sources.append((.streakGoing, 2)) }
        switch context.bookState {
        case .justStarted: sources.append((.justStarted, 2))
        case .midway: sources.append((.midway, 1.5))
        default: break
        }
        switch context.weekday {
        case 1: sources.append((.sunday, 3))
        case 2: sources.append((.monday, 2))
        case 6: sources.append((.friday, 2.5))
        case 7: sources.append((.saturday, 2.5))
        default: break
        }
        sources.append((GreetingMoment.season(context.season), 1.5))

        // Only sources that actually have something to say right now can take the turn.
        var live: [(moment: GreetingMoment, weight: Double, options: [Rendered])] = []
        for source in sources {
            let options = eligible(source.moment, context: context, values: values, avoiding: recent)
            if !options.isEmpty { live.append((source.moment, source.weight, options)) }
        }
        guard let chosen = VoiceText.choose(live, seed: seed, salt: "source|\(daypart)", weight: { $0.weight }) else { return nil }
        return VoiceText.choose(chosen.options, seed: seed, salt: "line|\(chosen.moment.rawValue)|\(daypart)", weight: { $0.line.weight })
    }
}

/// Remembers which line was shown, so the engine can be told what yesterday's was without the caller juggling dates.
///
/// Call `previousLineID(on:calendar:)` for the value to hand the engine (it stays the same all day), and `record` after
/// a greeting is shown. Codable, so the app can keep it in UserDefaults or the data file.
struct GreetingMemory: Codable, Equatable, Sendable {
    /// The calendar day the two ids below describe, as "2026-10-18".
    private(set) var dayKey = ""
    /// The last line shown on the most recent earlier day.
    private(set) var yesterdayLineID: String?
    /// The last line shown today.
    private(set) var latestLineID: String?
    /// The last few lines shown, newest first, across days. Optional so memories saved before it still decode.
    private var recentLineIDs: [String]?

    /// How many recent lines a fresh greeting steers clear of.
    static let recentLimit = 8

    init() {}

    mutating func previousLineID(on date: Date, calendar: Calendar) -> String? {
        rollOver(to: Self.key(for: date, calendar: calendar))
        return yesterdayLineID
    }

    /// What a fresh greeting (one per open) should not repeat, newest first: the lines shown lately, and yesterday's.
    mutating func linesToAvoid(on date: Date, calendar: Calendar) -> [String] {
        rollOver(to: Self.key(for: date, calendar: calendar))
        var lines = recentLineIDs ?? []
        if let yesterdayLineID, !lines.contains(yesterdayLineID) { lines.append(yesterdayLineID) }
        return lines
    }

    mutating func record(_ greeting: Greeting, on date: Date, calendar: Calendar) {
        rollOver(to: Self.key(for: date, calendar: calendar))
        latestLineID = greeting.lineID
        var recent = recentLineIDs ?? []
        recent.removeAll { $0 == greeting.lineID }
        recent.insert(greeting.lineID, at: 0)
        recentLineIDs = Array(recent.prefix(Self.recentLimit))
    }

    private mutating func rollOver(to key: String) {
        guard key != dayKey else { return }
        if latestLineID != nil { yesterdayLineID = latestLineID }
        latestLineID = nil
        dayKey = key
    }

    private static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
