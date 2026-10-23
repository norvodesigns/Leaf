import Foundation

/// What kind of day the Today screen is showing.
enum TodayMode: String, Codable, Sendable {
    /// No books and no history: the very first visit.
    case brandNew
    /// Something to read today.
    case reading
    /// Today's goal is done. Anything more is a gift.
    case goalMet
    /// A rest day.
    case restDay
    /// Nothing is being read: time to pick.
    case betweenBooks
}

/// The book Today is about.
struct TodayBook: Hashable, Sendable {
    var item: LibraryItem
    /// Today's reading for it from the plan, if any.
    var assignment: Assignment?
    /// The reader hasn't said where they are yet: the screen should offer "Where are you?" first.
    var needsPosition: Bool
}

/// A gentle prompt on Today. Never guilt.
struct TodayNudge: Hashable, Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        case confirmPosition(bookID: String)
        case stalledBook(bookID: String, days: Int)
        case pausedBookWaiting(bookID: String, page: Int)
        case challengeEnding(challengeID: String, daysLeft: Int)
        case yearGoalBehind(booksBehind: Int)
    }

    var kind: Kind
    var text: String

    var id: String { "\(kind)" }
}

/// Everything the Today screen needs, worked out once so the screen only has to draw it.
struct TodayBrief: Sendable {
    var mode: TodayMode
    var greeting: Greeting
    /// The tea for this hour, and how long to steep it.
    var tea: Tea
    var steepSeconds: Int
    var current: TodayBook?
    /// Today's reading times with the book and pages for each, earliest first.
    var slots: [SlotPlan]
    var nextSlot: SlotPlan?
    var minutesReadToday: Double
    var goalMinutes: Int
    var goalProgress: Double
    var minutesToGoal: Int
    var cupMinutes: Int
    var cupsToday: Double
    var streak: Int
    var week: [DayStat]
    var yearGoal: YearGoalPacing?
    var nudges: [TodayNudge]
    /// Books to pick from: several when between books, otherwise one suggestion.
    var picks: [Recommendation]
    /// Challenges the reader has joined that are running now.
    var challenges: [ChallengeProgress]
    var quote: JournalEntry?
    /// "Probably done Sunday." Filled in by the caller from the forecast, which is computed off the main thread.
    var forecastSentence: String?
}

struct TodayBriefInput: Sendable {
    var data: LeafData
    var plan: ReadingPlan
    var now: Date
    var calendar: Calendar
    var weather: CozyWeather?
    /// True for the first time Today is shown this calendar day. Work it out once per launch.
    var isFirstLaunchOfDay: Bool = true
    var previousGreetingID: String?
    /// Set for a fresh greeting (Today asks for one on every open): the seed to pick it with, in place of the day's.
    var greetingSeed: UInt64?
    /// Lines shown lately, newest first, for a fresh greeting to steer clear of (`GreetingMemory.linesToAvoid`).
    var recentGreetingIDs: [String] = []
    /// Books to suggest from (the catalog's browse pool). Empty means no suggestions.
    var candidates: [Book] = []
    var stats: CatalogStats?
    /// What the reader likes in a tea; today's tea leans toward it.
    var teaPreferences: TeaPreferences = TeaPreferences()

    init(data: LeafData, plan: ReadingPlan, now: Date, calendar: Calendar, weather: CozyWeather? = nil, isFirstLaunchOfDay: Bool = true, previousGreetingID: String? = nil, candidates: [Book] = [], stats: CatalogStats? = nil, teaPreferences: TeaPreferences = TeaPreferences(), greetingSeed: UInt64? = nil, recentGreetingIDs: [String] = []) {
        self.data = data
        self.plan = plan
        self.now = now
        self.calendar = calendar
        self.weather = weather
        self.isFirstLaunchOfDay = isFirstLaunchOfDay
        self.previousGreetingID = previousGreetingID
        self.candidates = candidates
        self.stats = stats
        self.teaPreferences = teaPreferences
        self.greetingSeed = greetingSeed
        self.recentGreetingIDs = recentGreetingIDs
    }
}

enum TodayBriefBuilder {
    /// Days without progress before a book on the Reading shelf gets a gentle nudge.
    static let stalledAfterDays = 14
    static let maxNudges = 3

    static func build(_ input: TodayBriefInput) -> TodayBrief {
        let data = input.data
        let calendar = input.calendar
        let now = input.now
        let prefs = data.preferences
        let seed = SeededGenerator.daySeed(now, calendar: calendar)

        // The day so far.
        let minutesToday = ReadingStats.minutesRead(on: now, sessions: data.sessions, calendar: calendar)
        let goal = prefs.dailyMinutes
        let goalMet = goal > 0 && minutesToday >= Double(goal)
        let minutesToGoal = goal > 0 ? max(0, Int((Double(goal) - minutesToday).rounded(.up))) : 0
        let streak = ReadingStats.streak(sessions: data.sessions, readingDays: prefs.readingDays, today: now, calendar: calendar)
        let week = ReadingStats.week(containing: now, sessions: data.sessions, readingDays: prefs.readingDays, calendar: calendar)
        let isReadingDay = prefs.readingDays.contains(calendar.component(.weekday, from: now))

        // The book to read.
        let reading = data.items(on: .reading)
        let today = input.plan.today
        let planned = today?.assignments.compactMap { assignment in
            data.items.first { $0.id == assignment.bookID }.map { (item: $0, assignment: assignment) }
        } ?? []
        let currentPair = planned.first
        let currentItem = currentPair?.item ?? reading.first ?? data.items(on: .toRead).first
        let current = currentItem.map {
            TodayBook(item: $0, assignment: currentPair?.assignment, needsPosition: !$0.positionConfirmed && $0.shelf != .finished)
        }

        // What kind of day it is.
        let hasHistory = !data.sessions.isEmpty || !data.items(on: .finished).isEmpty
        let mode: TodayMode
        if data.items.isEmpty && !hasHistory {
            mode = .brandNew
        } else if current == nil {
            mode = .betweenBooks
        } else if goalMet {
            mode = .goalMet
        } else if !isReadingDay {
            mode = .restDay
        } else {
            mode = .reading
        }

        // Tea for the hour.
        let daypart = Daypart.of(now, calendar: calendar)
        let season = Season.of(now, calendar: calendar)
        let lastTea = data.sessions.sorted { $0.startedAt > $1.startedAt }.first { $0.teaID != nil }?.teaID
        let tea = TeaSuggester.suggest(daypart: daypart, season: season, weather: input.weather, lastTeaID: lastTea, favoriteTeaID: prefs.favoriteTeaID, seed: seed, preferences: input.teaPreferences.withRatings(from: data.cabinet))
        let steep = TeaSuggester.steepSeconds(for: tea, strength: .regular)

        // The voice.
        let lastSession = data.sessions.map(\.startedAt).max()
        let daysSince = lastSession.map { max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: now)).day ?? 0) }
        let finishedToday = data.items(on: .finished).contains { $0.finishedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        let bookState: GreetingBookState = currentItem.map {
            GreetingBookState.classify(currentPage: $0.currentPage, totalPages: $0.book.pages, finishedToday: finishedToday, daysSinceLastRead: lastRead(of: $0, sessions: data.sessions, now: now, calendar: calendar))
        } ?? (finishedToday ? .finishedToday : .none)
        let greetingContext = GreetingContext(
            date: now, calendar: calendar, weather: greetingWeather(input.weather), streak: streak, daysSinceLastSession: daysSince,
            bookState: bookState, bookTitle: currentItem?.book.title,
            goalState: goalMet ? .met : (minutesToday > 0 ? .partial : .notStarted),
            isRestDay: !isReadingDay, isFirstLaunchOfDay: input.isFirstLaunchOfDay, isFirstEverLaunch: mode == .brandNew,
            teaName: tea.name, minutesToGoal: minutesToday > 0 && !goalMet ? minutesToGoal : nil
        )
        var avoid = input.recentGreetingIDs
        if let previous = input.previousGreetingID, !avoid.contains(previous) { avoid.append(previous) }
        let greeting = GreetingEngine.line(for: greetingContext, seed: input.greetingSeed ?? GreetingEngine.dailySeed(for: greetingContext), avoiding: avoid)

        // Reading times.
        let slots = today.map { SlotPlanner.plan(day: $0, slots: prefs.effectiveReadingSlots, calendar: calendar) } ?? []
        let nextSlot = SlotPlanner.next(in: slots, day: today?.date ?? now, now: now, calendar: calendar)

        // Suggestions: several when there is nothing being read, one otherwise.
        var picks: [Recommendation] = []
        if let stats = input.stats, !input.candidates.isEmpty {
            let context = RecommendationContext(library: data.items, sessions: data.sessions, dismissed: [], wpm: prefs.wpm, dailyMinutes: prefs.dailyMinutes, now: now, calendar: calendar)
            let limit = (mode == .betweenBooks || mode == .brandNew) ? 6 : 1
            picks = Recommender(stats: stats, context: context).recommend(from: input.candidates, limit: limit, seed: seed)
        }

        let insights = InsightsEngine(data: data, now: now, calendar: calendar)
        let pacing = insights.yearGoalPacing()
        let yearGoal: YearGoalPacing? = pacing.status == .noGoal ? nil : pacing
        let challenges = ChallengeEvaluator.allProgress(data: data, now: now, calendar: calendar).filter { $0.status == .active && !$0.isComplete }
        let quote = JournalTools(data: data, calendar: calendar).quoteOfTheDay(now: now, seed: seed)

        let nudges = nudges(data: data, current: current, challenges: challenges, pacing: pacing, now: now, calendar: calendar)

        return TodayBrief(
            mode: mode, greeting: greeting, tea: tea, steepSeconds: steep, current: current, slots: slots, nextSlot: nextSlot,
            minutesReadToday: minutesToday, goalMinutes: goal, goalProgress: goal > 0 ? min(1, minutesToday / Double(goal)) : 0,
            minutesToGoal: minutesToGoal, cupMinutes: prefs.cupMinutes, cupsToday: Cups.count(minutes: minutesToday, cupMinutes: prefs.cupMinutes),
            streak: streak, week: week, yearGoal: yearGoal, nudges: nudges, picks: picks, challenges: Array(challenges.prefix(2)), quote: quote,
            forecastSentence: nil
        )
    }

    // MARK: Helpers

    static func greetingWeather(_ weather: CozyWeather?) -> GreetingWeather {
        switch weather {
        case .clear?: return .clear
        case .rain?: return .rain
        case .snow?: return .snow
        case .fog?: return .fog
        case .cold?: return .cold
        case .hot?: return .hot
        case .cloudy?, nil: return .unknown
        }
    }

    /// Days since the reader last made progress in a book (a session, or when they started it).
    private static func lastRead(of item: LibraryItem, sessions: [ReadingSession], now: Date, calendar: Calendar) -> Int? {
        guard let last = sessions.filter({ $0.bookID == item.id }).map(\.startedAt).max() ?? item.startedAt else { return nil }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0)
    }

    private static func nudges(data: LeafData, current: TodayBook?, challenges: [ChallengeProgress], pacing: YearGoalPacing, now: Date, calendar: Calendar) -> [TodayNudge] {
        var result: [TodayNudge] = []

        if let current, current.needsPosition, current.item.shelf == .reading {
            result.append(TodayNudge(kind: .confirmPosition(bookID: current.item.id), text: "Where are you in \(current.item.book.title)? A page or a percentage is enough."))
        }

        // The longest-waiting book on the Reading shelf.
        let stalled = data.items(on: .reading)
            .compactMap { item -> (LibraryItem, Int)? in
                guard item.progress > 0, let days = lastRead(of: item, sessions: data.sessions, now: now, calendar: calendar), days >= stalledAfterDays else { return nil }
                return (item, days)
            }
            .max { $0.1 < $1.1 }
        if let (item, days) = stalled {
            result.append(TodayNudge(kind: .stalledBook(bookID: item.id, days: days), text: "\(item.book.title) has been waiting \(days) days. Pick it back up, or set it aside for later."))
        }

        // A paused book worth coming back to.
        let waiting = data.items(on: .paused)
            .filter { $0.progress >= 0.4 && ($0.pausedAt.map { now.timeIntervalSince($0) >= 30 * 86_400 } ?? false) }
            .max { $0.progress < $1.progress }
        if let waiting {
            result.append(TodayNudge(kind: .pausedBookWaiting(bookID: waiting.id, page: waiting.currentPage), text: "\(waiting.book.title) is waiting at page \(waiting.currentPage), whenever you’re ready."))
        }

        if let ending = challenges.filter({ ($0.daysLeft ?? .max) <= 7 }).min(by: { ($0.daysLeft ?? .max) < ($1.daysLeft ?? .max) }), let left = ending.daysLeft {
            result.append(TodayNudge(kind: .challengeEnding(challengeID: ending.challengeID, daysLeft: left), text: ending.statusLine))
        }

        if pacing.status == .behind, pacing.booksAheadOrBehind <= -2 {
            let behind = abs(pacing.booksAheadOrBehind)
            result.append(TodayNudge(kind: .yearGoalBehind(booksBehind: behind), text: "A short book would bring the year goal back within reach."))
        }

        return Array(result.prefix(maxNudges))
    }
}
