import Foundation

/// The few numbers the evaluator and the stamp ledger agree on.
enum ChallengeRules {
    /// A "sitting" is at least this long (five minutes). Shorter sessions still add to cups, but they don’t make an
    /// evening or a tasting.
    static let sittingSeconds = 300.0
    /// The most one session can add (six hours). A timer left running overnight shouldn’t hand out thirty cups.
    static let maximumCreditedSeconds = 6.0 * 3600
    /// The biggest yearly goal taken at face value, so nothing downstream can overflow.
    static let maximumYearlyTarget = 100_000
    /// How far ahead a coming season is offered ("Winter Hearth starts in nine days").
    static let offerLookaheadDays = 14

    /// What a session is worth to a challenge: zero for nonsense (negative, not a number), capped for the huge.
    static func creditedSeconds(_ seconds: Double) -> Double {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return min(seconds, maximumCreditedSeconds)
    }
}

/// Works out how a reader is doing in a challenge from nothing but their own history: finished books, sessions,
/// genres and tea ids. Nothing is stored, so progress is always consistent with the library, and adding books or
/// sessions can only move it forward.
///
/// Counting rules:
/// - Activity counts when it falls inside the challenge’s window, whenever the reader joined. Joining late in a
///   season still credits the book you finished last week. (`sinceJoining` windows start on the day of joining.)
/// - A finished book fills at most one prompt in a challenge. Where a book could fill several, the evaluator finds the
///   arrangement that fills the most, preferring the earliest prompts. Different challenges are independent.
/// - A book counts once, however many times it shows up in the library. Books without a finish date can’t be placed
///   in time, so they don’t count.
enum ChallengeEvaluator {
    static func progress(for enrollment: ChallengeEnrollment, data: LeafData, now: Date, calendar: Calendar) -> ChallengeProgress {
        guard let challenge = ChallengeCatalog.challenge(id: enrollment.id) else {
            return retired(enrollment)
        }
        let year = enrollment.year ?? challenge.window.instanceYear(containing: enrollment.joinedAt, calendar: calendar)
        let span = challenge.window.span(year: year, joinedAt: enrollment.joinedAt, calendar: calendar)
        let history = History(data: data, span: span)

        let outcome: Outcome
        switch challenge.rule {
        case .bookPrompts:
            outcome = prompts(challenge, history)
        case .booksFinished(let defaultTarget):
            outcome = booksFinished(challenge, history, target: yearlyTarget(data.preferences.yearlyGoal, default: defaultTarget))
        case .cups(let target):
            outcome = cups(challenge, history, target: target, cupMinutes: data.preferences.cupMinutes)
        case .weeklyPots:
            outcome = weeklyPots(challenge, history, span: span, cupMinutes: data.preferences.cupMinutes, calendar: calendar)
        case .eveningStreak:
            outcome = eveningStreak(challenge, history, span: span, readingDays: data.preferences.readingDays, calendar: calendar)
        case .differentTeas:
            outcome = differentTeas(challenge, history)
        case .tastingNotes:
            outcome = tastingNotes(challenge, history)
        }
        return assemble(challenge, year: year, span: span, outcome: outcome, now: now, calendar: calendar)
    }

    /// Progress for every challenge the reader has joined, in the order they joined.
    static func allProgress(data: LeafData, now: Date, calendar: Calendar) -> [ChallengeProgress] {
        data.challenges.map { progress(for: $0, data: data, now: now, calendar: calendar) }
    }

    /// The enrollment to save when the reader joins an offer.
    static func enrollment(for offer: ChallengeOffer, now: Date) -> ChallengeEnrollment {
        ChallengeEnrollment(id: offer.challenge.id, joinedAt: now, year: offer.year)
    }

    /// Challenges the reader could join: the ones open now, then the ones opening within `lookaheadDays`. Joined ones
    /// are included and marked, so the UI can show them differently or leave them out.
    static func availableChallenges(
        now: Date,
        calendar: Calendar,
        enrolled: [ChallengeEnrollment] = [],
        lookaheadDays: Int = ChallengeRules.offerLookaheadDays
    ) -> [ChallengeOffer] {
        var open: [ChallengeOffer] = []
        var soon: [(order: Int, offer: ChallengeOffer)] = []

        for (order, challenge) in ChallengeCatalog.all.enumerated() {
            func isJoined(year: Int) -> Bool {
                enrolled.contains { enrollment in
                    guard enrollment.id == challenge.id else { return false }
                    guard challenge.window.isCalendarBound else { return true }
                    return (enrollment.year ?? challenge.window.instanceYear(containing: enrollment.joinedAt, calendar: calendar)) == year
                }
            }
            guard challenge.window.isCalendarBound else {
                open.append(ChallengeOffer(
                    challenge: challenge, year: calendar.component(.year, from: now), span: nil,
                    startsInDays: 0, daysLeft: nil, isJoined: isJoined(year: 0)
                ))
                continue
            }
            let current = challenge.window.instanceYear(containing: now, calendar: calendar)
            for year in (current - 1)...(current + 1) {
                let span = challenge.window.span(year: year, joinedAt: now, calendar: calendar)
                if span.contains(now) {
                    open.append(ChallengeOffer(
                        challenge: challenge, year: year, span: span,
                        startsInDays: 0, daysLeft: daysLeft(span: span, now: now, calendar: calendar), isJoined: isJoined(year: year)
                    ))
                } else if span.start > now {
                    let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: span.start).day ?? 1)
                    if days <= lookaheadDays {
                        soon.append((order, ChallengeOffer(
                            challenge: challenge, year: year, span: span,
                            startsInDays: days, daysLeft: daysLeft(span: span, now: span.start, calendar: calendar), isJoined: isJoined(year: year)
                        )))
                    }
                }
            }
        }
        soon.sort { $0.offer.startsInDays < $1.offer.startsInDays || ($0.offer.startsInDays == $1.offer.startsInDays && $0.order < $1.order) }
        return open + soon.map(\.offer)
    }

    // MARK: History

    /// The part of the reader's history inside one window.
    private struct History {
        struct Finished {
            var book: Book
            var at: Date
        }

        struct Sitting {
            var key: String
            var start: Date
            var seconds: Double
            var teaID: String?
            var end: Date { start.addingTimeInterval(seconds) }
        }

        struct Tasting {
            var teaID: String
            var family: TeaFamily?
            var at: Date
        }

        var finished: [Finished] = []
        var sittings: [Sitting] = []
        var tastings: [Tasting] = []

        init(data: LeafData, span: ChallengeSpan) {
            var byBook: [String: Finished] = [:]
            for item in data.items {
                for read in item.readThroughs where span.contains(read.finishedAt) {
                    let at = read.finishedAt
                    if let existing = byBook[item.book.id], existing.at <= at { continue }
                    byBook[item.book.id] = Finished(book: item.book, at: at)
                }
            }
            finished = byBook.values.sorted { $0.at < $1.at || ($0.at == $1.at && $0.book.id < $1.book.id) }

            sittings = data.sessions.compactMap { session -> Sitting? in
                guard span.contains(session.startedAt) else { return nil }
                let seconds = ChallengeRules.creditedSeconds(session.seconds)
                guard seconds > 0 else { return nil }
                return Sitting(key: session.id.uuidString, start: session.startedAt, seconds: seconds, teaID: session.teaID)
            }
            .sorted { $0.start < $1.start || ($0.start == $1.start && $0.key < $1.key) }

            tastings = data.tastings
                .filter { span.contains($0.createdAt) }
                .sorted { $0.createdAt < $1.createdAt || ($0.createdAt == $1.createdAt && $0.id.uuidString < $1.id.uuidString) }
                .map { Tasting(teaID: $0.teaID, family: $0.family ?? TeaCatalog.tea(id: $0.teaID)?.family, at: $0.createdAt) }
        }
    }

    /// What one rule found, before the common bookkeeping.
    private struct Outcome {
        var states: [ChallengeTaskState]
        var current: Int
        var target: Int
    }

    private static func state(_ task: ChallengeTask, done: Bool, at: Date? = nil, evidence: String? = nil) -> ChallengeTaskState {
        ChallengeTaskState(id: task.id, title: task.title, isComplete: done, completedAt: done ? at : nil, evidence: done ? evidence : nil)
    }

    // MARK: Book prompts

    /// Matches finished books to prompts, one book per prompt, so that as many prompts as possible are answered.
    /// Prompts are tried in order and each may rearrange earlier answers to make room (a standard augmenting-path
    /// matching), so the set of answered prompts only ever grows as books are added.
    private struct PromptMatching {
        /// For each prompt, the books that fit it, earliest finished first.
        private let fits: [[Int]]
        /// The prompt each book currently answers.
        private var owner: [Int?]

        init(books: [Book], matchers: [ChallengeBookMatcher?]) {
            fits = matchers.map { matcher in
                guard let matcher else { return [] }
                return books.indices.filter { matcher.matches(books[$0]) }
            }
            owner = Array(repeating: nil, count: books.count)
        }

        mutating func solve() {
            for prompt in fits.indices {
                var seen = Array(repeating: false, count: owner.count)
                _ = place(prompt, seen: &seen)
            }
        }

        private mutating func place(_ prompt: Int, seen: inout [Bool]) -> Bool {
            let candidates = fits[prompt]
            for book in candidates where !seen[book] {
                seen[book] = true
                if let other = owner[book] {
                    if place(other, seen: &seen) {
                        owner[book] = prompt
                        return true
                    }
                } else {
                    owner[book] = prompt
                    return true
                }
            }
            return false
        }

        /// The book that answers each prompt, by index into the books, or nil.
        var bookByPrompt: [Int?] {
            var result = [Int?](repeating: nil, count: fits.count)
            for (book, prompt) in owner.enumerated() {
                if let prompt { result[prompt] = book }
            }
            return result
        }
    }

    private static func prompts(_ challenge: Challenge, _ history: History) -> Outcome {
        let matchers = challenge.tasks.map { task -> ChallengeBookMatcher? in
            if case .book(let matcher) = task.goal { return matcher }
            return nil
        }
        var matching = PromptMatching(books: history.finished.map(\.book), matchers: matchers)
        matching.solve()
        let answers = matching.bookByPrompt
        let states = challenge.tasks.enumerated().map { index, task -> ChallengeTaskState in
            guard let book = answers[index] else { return state(task, done: false) }
            return state(task, done: true, at: history.finished[book].at, evidence: history.finished[book].book.id)
        }
        let answered = states.filter(\.isComplete).count
        return Outcome(states: states, current: answered, target: challenge.tasks.count)
    }

    // MARK: Counts

    /// The yearly goal, or the default when none is set. Capped so the arithmetic below cannot overflow.
    private static func yearlyTarget(_ goal: Int?, default defaultTarget: Int) -> Int {
        guard let goal, goal > 0 else { return defaultTarget }
        return min(goal, ChallengeRules.maximumYearlyTarget)
    }

    /// Whole units for a percent of a target, rounded up and never below one.
    private static func threshold(percent: Int, of target: Int) -> Int {
        max(1, (target * min(100, max(0, percent)) + 99) / 100)
    }

    private static func booksFinished(_ challenge: Challenge, _ history: History, target: Int) -> Outcome {
        let count = history.finished.count
        let states = challenge.tasks.map { task -> ChallengeTaskState in
            guard case .milestone(let percent) = task.goal else { return state(task, done: false) }
            let needed = threshold(percent: percent, of: target)
            guard count >= needed else { return state(task, done: false) }
            return state(task, done: true, at: history.finished[needed - 1].at)
        }
        return Outcome(states: states, current: count, target: target)
    }

    /// Cups so far after each sitting, in order, using the same `Cups` rule as the rest of the app.
    private static func cupTimeline(_ sittings: [History.Sitting], cupMinutes: Int) -> [(end: Date, cups: Int)] {
        var seconds = 0.0
        return sittings.map { sitting in
            seconds += sitting.seconds
            return (sitting.end, Cups.wholeCups(minutes: seconds / 60, cupMinutes: cupMinutes))
        }
    }

    /// When the running total first reached `cups`, or nil if it hasn’t.
    private static func moment(reaching cups: Int, in timeline: [(end: Date, cups: Int)]) -> Date? {
        timeline.first { $0.cups >= cups }?.end
    }

    private static func cups(_ challenge: Challenge, _ history: History, target: Int, cupMinutes: Int) -> Outcome {
        let timeline = cupTimeline(history.sittings, cupMinutes: cupMinutes)
        let total = timeline.last?.cups ?? 0
        let states = challenge.tasks.map { task -> ChallengeTaskState in
            guard case .milestone(let percent) = task.goal else { return state(task, done: false) }
            let needed = threshold(percent: percent, of: target)
            guard let at = moment(reaching: needed, in: timeline) else { return state(task, done: false) }
            return state(task, done: true, at: at)
        }
        return Outcome(states: states, current: total, target: target)
    }

    // MARK: Weekly pots

    private static func weeklyPots(_ challenge: Challenge, _ history: History, span: ChallengeSpan, cupMinutes: Int, calendar: Calendar) -> Outcome {
        // Seven-day blocks counted from the day of joining, so every week is a full seven days.
        var blocks: [Int: [History.Sitting]] = [:]
        for sitting in history.sittings {
            let days = calendar.dateComponents([.day], from: span.start, to: calendar.startOfDay(for: sitting.start)).day ?? 0
            blocks[max(0, days) / 7, default: []].append(sitting)
        }
        let states = challenge.tasks.map { task -> ChallengeTaskState in
            guard case .week(let number) = task.goal, number >= 1 else { return state(task, done: false) }
            let timeline = cupTimeline(blocks[number - 1] ?? [], cupMinutes: cupMinutes)
            guard let at = moment(reaching: Cups.cupsPerPot, in: timeline) else { return state(task, done: false) }
            return state(task, done: true, at: at)
        }
        return Outcome(states: states, current: states.filter(\.isComplete).count, target: challenge.tasks.count)
    }

    // MARK: Evening streak

    /// The evening a sitting belongs to. A sitting between 23:00 and 02:00 is that evening’s, even if it runs past
    /// midnight, so "Still up?" reading doesn’t break a streak.
    private static func eveningDay(of start: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: start)
        switch Daypart.of(start, calendar: calendar) {
        case .dusk, .evening:
            return day
        case .late:
            return calendar.component(.hour, from: start) >= 23 ? day : calendar.date(byAdding: .day, value: -1, to: day)
        default:
            return nil
        }
    }

    /// Whether `next` carries on a run that was at `previous`. Days between them must all be rest days, as in the
    /// app’s own streak.
    private static func continues(from previous: Date, to next: Date, schedule: Set<Int>, calendar: Calendar) -> Bool {
        let gap = calendar.dateComponents([.day], from: previous, to: next).day ?? Int.max
        if gap < 1 { return false }
        if gap == 1 { return true }
        // Eight clear days contain every weekday, so a run cannot survive them.
        if gap > 8 { return false }
        for offset in 1..<gap {
            guard let day = calendar.date(byAdding: .day, value: offset, to: previous) else { return false }
            if schedule.contains(calendar.component(.weekday, from: day)) { return false }
        }
        return true
    }

    private static func eveningStreak(_ challenge: Challenge, _ history: History, span: ChallengeSpan, readingDays: Set<Int>, calendar: Calendar) -> Outcome {
        let schedule = readingDays.isEmpty ? Set(1...7) : readingDays
        var firstSitting: [Date: Date] = [:]
        for sitting in history.sittings where sitting.seconds >= ChallengeRules.sittingSeconds {
            guard let day = eveningDay(of: sitting.start, calendar: calendar), span.contains(day) else { continue }
            if let existing = firstSitting[day], existing <= sitting.start { continue }
            firstSitting[day] = sitting.start
        }

        var run = 0
        var best = 0
        var previous: Date?
        var reached: [Int: Date] = [:]
        for day in firstSitting.keys.sorted() {
            if let previous, continues(from: previous, to: day, schedule: schedule, calendar: calendar) { run += 1 } else { run = 1 }
            if reached[run] == nil { reached[run] = firstSitting[day] }
            best = max(best, run)
            previous = day
        }

        let states = challenge.tasks.map { task -> ChallengeTaskState in
            guard case .evenings(let length) = task.goal, let at = reached[length] else { return state(task, done: false) }
            return state(task, done: true, at: at)
        }
        return Outcome(states: states, current: min(best, challenge.tasks.count), target: challenge.tasks.count)
    }

    // MARK: Tea tasting

    /// Each different tea counts once, from its first note; a family counts from the first note on any tea in it.
    private static func tastingNotes(_ challenge: Challenge, _ history: History) -> Outcome {
        var teasSeen = Set<String>()
        var teaFirsts: [(id: String, at: Date)] = []
        var familiesSeen = Set<TeaFamily>()
        var familyFirsts: [(family: TeaFamily, at: Date)] = []
        for tasting in history.tastings {
            if !tasting.teaID.isEmpty, teasSeen.insert(tasting.teaID).inserted { teaFirsts.append((tasting.teaID, tasting.at)) }
            if let family = tasting.family, familiesSeen.insert(family).inserted { familyFirsts.append((family, tasting.at)) }
        }
        let states = challenge.tasks.map { task -> ChallengeTaskState in
            switch task.goal {
            case .tasted(let count) where count >= 1 && teaFirsts.count >= count:
                return state(task, done: true, at: teaFirsts[count - 1].at, evidence: teaFirsts[count - 1].id)
            case .tastedFamilies(let count) where count >= 1 && familyFirsts.count >= count:
                return state(task, done: true, at: familyFirsts[count - 1].at, evidence: familyFirsts[count - 1].family.title)
            default:
                return state(task, done: false)
            }
        }
        let done = states.filter(\.isComplete).count
        return Outcome(states: states, current: done, target: challenge.tasks.count)
    }

    /// A catalog tea, or one of the reader's own ("custom." and the tea's id).
    static func isRealTea(_ id: String) -> Bool {
        if TeaCatalog.tea(id: id) != nil { return true }
        guard id.hasPrefix(CabinetTea.customPrefix) else { return false }
        return UUID(uuidString: String(id.dropFirst(CabinetTea.customPrefix.count))) != nil
    }

    private static func differentTeas(_ challenge: Challenge, _ history: History) -> Outcome {
        var seen = Set<String>()
        var firsts: [(id: String, at: Date)] = []
        for sitting in history.sittings where sitting.seconds >= ChallengeRules.sittingSeconds {
            // Leaf's teas and the reader's own count; a made-up or misspelled id can’t fill the card.
            guard let id = sitting.teaID, ChallengeEvaluator.isRealTea(id), seen.insert(id).inserted else { continue }
            firsts.append((id, sitting.start))
        }
        let states = challenge.tasks.map { task -> ChallengeTaskState in
            guard case .teas(let count) = task.goal, count >= 1, firsts.count >= count else { return state(task, done: false) }
            return state(task, done: true, at: firsts[count - 1].at, evidence: firsts[count - 1].id)
        }
        return Outcome(states: states, current: min(firsts.count, challenge.tasks.count), target: challenge.tasks.count)
    }

    // MARK: Putting it together

    private static func assemble(_ challenge: Challenge, year: Int, span: ChallengeSpan, outcome: Outcome, now: Date, calendar: Calendar) -> ChallengeProgress {
        let states = outcome.states
        let isComplete = !states.isEmpty && states.allSatisfy(\.isComplete)
        let fraction = outcome.target > 0 ? min(1, max(0, Double(outcome.current) / Double(outcome.target))) : 0
        let status: ChallengeStatus
        if isComplete {
            status = .completed
        } else if now < span.start {
            status = .upcoming
        } else if let end = span.end, now >= end {
            status = .ended
        } else {
            status = .active
        }
        let left = daysLeft(span: span, now: now, calendar: calendar)
        let stamps = earnedStamps(challenge, states: states, year: year, span: span, isComplete: isComplete)
        return ChallengeProgress(
            challengeID: challenge.id, year: year, span: span, tasks: states,
            current: outcome.current, target: outcome.target, fraction: fraction, stamps: stamps,
            isComplete: isComplete, daysLeft: left, status: status,
            statusLine: statusLine(challenge, status: status, current: outcome.current, target: outcome.target, daysLeft: left, span: span, now: now, calendar: calendar)
        )
    }

    private static func earnedStamps(_ challenge: Challenge, states: [ChallengeTaskState], year: Int, span: ChallengeSpan, isComplete: Bool) -> [ChallengeStamp] {
        // Bingo: when each full line was finished, earliest first.
        var lineTimes: [Date] = []
        if challenge.kind == .genreBingo, states.count == 9 {
            for line in ChallengeCatalog.bingoLines where line.allSatisfy({ states[$0].isComplete }) {
                lineTimes.append(line.compactMap { states[$0].completedAt }.max() ?? span.start)
            }
            lineTimes.sort()
        }
        var result: [ChallengeStamp] = []
        for design in challenge.stamps {
            let earnedAt: Date?
            switch design.unlock {
            case .task(let id):
                if let task = states.first(where: { $0.id == id }), task.isComplete {
                    earnedAt = task.completedAt ?? span.start
                } else {
                    earnedAt = nil
                }
            case .completion:
                earnedAt = isComplete ? (states.compactMap(\.completedAt).max() ?? span.start) : nil
            case .lines(let count):
                earnedAt = count >= 1 && lineTimes.count >= count ? lineTimes[count - 1] : nil
            }
            if let earnedAt { result.append(ChallengeStamp(design: design, year: year, earnedAt: earnedAt)) }
        }
        return result
    }

    /// Whole days left counting today, or nil when the window never ends.
    private static func daysLeft(span: ChallengeSpan, now: Date, calendar: Calendar) -> Int? {
        guard let end = span.end else { return nil }
        guard now < end else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0
        return max(1, days)
    }

    private static func statusLine(
        _ challenge: Challenge, status: ChallengeStatus, current: Int, target: Int, daysLeft: Int?, span: ChallengeSpan, now: Date, calendar: Calendar
    ) -> String {
        let shown = min(current, target)
        let unit = challenge.unitName(for: target)
        switch status {
        case .upcoming:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: span.start).day ?? 0
            return days <= 1 ? "Starts tomorrow." : "Starts in \(days) days."
        case .active:
            let base = "\(shown) of \(target) \(unit)."
            switch daysLeft {
            case .none: return base
            case .some(1): return base + " Last day."
            case .some(let days): return base + " \(days) days left."
            }
        case .completed:
            return "\(target) of \(target) \(unit). Nicely done."
        case .ended:
            return "Ended at \(shown) of \(target) \(unit). Every page counted."
        case .retired:
            return "This challenge has left the shelf."
        }
    }

    private static func retired(_ enrollment: ChallengeEnrollment) -> ChallengeProgress {
        ChallengeProgress(
            challengeID: enrollment.id, year: enrollment.year ?? 0, span: ChallengeSpan(start: enrollment.joinedAt, end: nil),
            tasks: [], current: 0, target: 0, fraction: 0, stamps: [], isComplete: false, daysLeft: nil, status: .retired,
            statusLine: "This challenge has left the shelf."
        )
    }
}
