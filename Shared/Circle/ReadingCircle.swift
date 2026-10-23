import Foundation

// MARK: - Model

/// A reading circle: one book, the people reading it together, and goals along the way ("page 120 by Friday"), the
/// last of them the end of the book. Like a Fitness competition: everyone's progress comes from their own reading,
/// and the circle shows who's where.
///
/// Friends join from an iCloud invitation (`CircleShareRules`, `CircleSharing`); each person's member names their
/// iCloud user (`remoteID`) and only they move it. Every entity has a stable id and an `updatedAt`, so copies merge
/// field by field (`SyncMerge.circles`). The goals are stored as `meetings`, their name from before circles were
/// shared: a goal can still say where the circle meets to talk about it.
struct ReadingCircle: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// A copy of the book, so the circle still shows if the book leaves the library.
    var book: Book
    /// The day the circle starts reading. Pace before the first meeting is measured from here.
    var startsOn: Date
    /// The goals, in date order. `CirclePlanner.normalized` keeps them sorted with pages that only go up.
    var meetings: [CircleMeeting]
    /// The reader first (`kind == .me`), then friends in the order they were added.
    var members: [CircleMember]
    var createdAt: Date
    var updatedAt: Date
    /// Put away: the circle moves to the end of the shelf and stops appearing on Today.
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        book: Book,
        startsOn: Date,
        meetings: [CircleMeeting] = [],
        members: [CircleMember] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.book = book
        self.startsOn = startsOn
        self.meetings = meetings
        self.members = members
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.archivedAt = archivedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, book, startsOn, meetings, members, createdAt, updatedAt, archivedAt
    }

    /// Fields added later decode to their defaults, so an older file still opens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        book = try c.decode(Book.self, forKey: .book)
        let created = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        createdAt = created
        startsOn = try c.decodeIfPresent(Date.self, forKey: .startsOn) ?? created
        meetings = try c.decodeIfPresent([CircleMeeting].self, forKey: .meetings) ?? []
        members = try c.decodeIfPresent([CircleMember].self, forKey: .members) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
    }

    var me: CircleMember? { members.first { $0.kind == .me } }
    var friends: [CircleMember] { members.filter { $0.kind != .me } }
    var isArchived: Bool { archivedAt != nil }
    /// The last goal's date: when the circle means to have finished the book.
    var finishBy: Date? { meetings.map(\.date).max() }
}

/// One goal: the page everyone reads up to by a date, and where the circle meets to talk about it, if it does.
struct CircleMeeting: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var date: Date
    /// Read up to and including this page by the meeting.
    var throughPage: Int
    /// Where the circle meets to talk ("Sam’s kitchen", "the café on Hill St"). Optional and free text.
    var place: String?
    var updatedAt: Date

    init(id: UUID = UUID(), date: Date, throughPage: Int, place: String? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.date = date
        self.throughPage = throughPage
        self.place = place
        self.updatedAt = updatedAt
    }
}

/// Someone in the circle.
struct CircleMember: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The reader. Their page follows the library when the book is there.
        case me
        /// Someone else: a friend who joined from an invitation (their page is their own), or, in circles from before
        /// invitations, someone added by name.
        case friend
    }

    var id: UUID
    var name: String
    var kind: Kind
    /// The last page they read to. For `.me` this is a fallback when the book isn't in the library.
    var page: Int
    /// A `CozyPalette` token for their ring.
    var paletteToken: String
    /// The iCloud user this member stands for in a shared circle. Nil for circles that were never shared, and for
    /// friends added by name before invitations.
    var remoteID: String?
    var updatedAt: Date
    /// Where their page has moved lately, oldest first (`move(to:at:)`): what the circle's standings and its "lately"
    /// list are made from. At most `CircleCheckIn.logLimit` entries.
    var log: [CircleCheckIn]

    init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .friend,
        page: Int = 0,
        paletteToken: String = CozyPalette.chai,
        remoteID: String? = nil,
        updatedAt: Date = Date(),
        log: [CircleCheckIn] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.page = page
        self.paletteToken = paletteToken
        self.remoteID = remoteID
        self.updatedAt = updatedAt
        self.log = log
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, page, paletteToken, remoteID, updatedAt, log
    }

    /// Fields added later decode to their defaults, so a copy from an older version still opens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .friend
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 0
        paletteToken = try c.decodeIfPresent(String.self, forKey: .paletteToken) ?? CozyPalette.chai
        remoteID = try c.decodeIfPresent(String.self, forKey: .remoteID)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        log = try c.decodeIfPresent([CircleCheckIn].self, forKey: .log) ?? []
    }

    /// "SM" for "Sam Marsh", "J" for "Jo". At most two letters, for the middle of a ring.
    var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    /// Joined from an invitation: their page moves as they read, on their own phone.
    var joinedFromInvite: Bool { remoteID != nil && kind == .friend }

    /// Moves them to `page` at `now` and notes it in their log. The first entry is where they started (no pages
    /// read), so joining halfway through the book isn't counted as reading. A move within half an hour of the one
    /// before folds into it, so a sitting logged page by page is one entry.
    mutating func move(to page: Int, at now: Date) {
        let delta = page - self.page
        if log.count > 1, let last = log.last, now.timeIntervalSince(last.date) < CircleCheckIn.foldWindow, now >= last.date {
            log[log.count - 1] = CircleCheckIn(date: now, page: page, pages: last.pages + delta)
        } else {
            log.append(CircleCheckIn(date: now, page: page, pages: log.isEmpty ? 0 : delta))
        }
        if log.count > CircleCheckIn.logLimit { log.removeFirst(log.count - CircleCheckIn.logLimit) }
        self.page = page
        updatedAt = now
    }
}

/// A moment someone's page moved: where they got to, and how many pages that was.
struct CircleCheckIn: Codable, Hashable, Sendable {
    var date: Date
    var page: Int
    /// Pages since the entry before. Zero for where they started; below zero when they set their page back.
    var pages: Int

    static let logLimit = 40
    /// Moves this close together are one sitting.
    static let foldWindow: TimeInterval = 30 * 60

    /// The reader's own log for a book, from their reading sessions: one entry for each sitting that moved the page.
    static func log(from sessions: [ReadingSession], bookID: String) -> [CircleCheckIn] {
        sessions
            .filter { $0.bookID == bookID && $0.toPage > $0.fromPage }
            .map { CircleCheckIn(date: $0.startedAt.addingTimeInterval(max(0, $0.seconds)), page: $0.toPage, pages: $0.toPage - $0.fromPage) }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - Snapshot

/// Where a member stands against the next goal.
enum CirclePace: String, Hashable, Sendable {
    /// Read to the end of the book.
    case finished
    /// Already at or past the next goal's page.
    case ready
    /// Close to where a steady pace would put them today.
    case onPace
    /// Behind a steady pace. Said gently, never as a warning.
    case catchingUp
}

struct CircleMemberProgress: Identifiable, Hashable, Sendable {
    var member: CircleMember
    var page: Int
    /// Of the whole book, 0 to 1.
    var fraction: Double
    /// Of the stretch to the next goal, 0 to 1.
    var sectionFraction: Double
    var pace: CirclePace
    /// 1 for whoever is furthest into the book. People on the same page share a place.
    var rank: Int = 1
    /// Pages read today and in the last seven days (today included), from their log.
    var pagesToday: Int = 0
    var pagesThisWeek: Int = 0
    /// When their page last moved forward, when the log knows.
    var lastRead: Date?
    /// Goals they reached by the goal's day.
    var goalsMet: Int = 0
    /// Pages from here to the next goal's page, 0 when they're there or there is no next goal.
    var pagesToGoal: Int = 0

    var id: UUID { member.id }
    var isMe: Bool { member.kind == .me }
}

/// Everything the circle screen shows, worked out for one moment.
struct CircleSnapshot: Hashable, Sendable {
    var circleID: UUID
    /// The goal to read towards: today's, or the first one still to come. Nil when every goal has passed.
    var nextMeeting: CircleMeeting?
    /// Its position in `meetings`, from 0.
    var nextMeetingIndex: Int?
    /// Whole days until it, 0 when it's today.
    var daysUntilNext: Int?
    /// The pages this stretch covers: after the previous goal's page, up to the next one's.
    var sectionStart: Int
    var sectionEnd: Int
    /// In the circle's order: the reader first, then friends.
    var members: [CircleMemberProgress]
    /// Pages the reader still has before the next goal.
    var myPagesToGo: Int
    /// Minutes a day at the reader's pace to be there in time, or nil when there is nothing to read.
    var myMinutesPerDay: Int?
    /// Every goal has passed.
    var isComplete: Bool
    /// One calm sentence for the top of the card.
    var statusLine: String
    /// Where the reader stands against the others ("You’re 16 pages behind Sam."), or nil when they read alone.
    var standingLine: String? = nil

    var me: CircleMemberProgress? { members.first { $0.member.kind == .me } }
    var nextGoal: CircleMeeting? { nextMeeting }

    /// Furthest into the book first; on the same page the reader goes first, then the circle's order.
    var standings: [CircleMemberProgress] {
        members.enumerated().sorted { lhs, rhs in
            if lhs.element.page != rhs.element.page { return lhs.element.page > rhs.element.page }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

/// Something that happened in a circle lately, for its "lately" list.
struct CircleActivity: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// A sitting that moved their page on.
        case read(pages: Int)
        /// They reached a goal's page (the furthest one this sitting crossed).
        case reachedGoal(page: Int, goalDate: Date)
        /// They read to the end of the book.
        case finished
        /// They joined the circle, starting at this page.
        case joined(page: Int)
    }

    var memberID: UUID
    var date: Date
    var kind: Kind

    var id: String { "\(memberID.uuidString)-\(date.timeIntervalSince1970)" }
}

// MARK: - Planner

/// The arithmetic behind a circle: an even schedule, and where everyone stands. Pure and deterministic.
enum CirclePlanner {
    /// How far below a steady pace still counts as on pace, as a share of the section.
    static let paceSlack = 0.15
    static let maximumMeetings = 24
    /// How far back the "lately" list looks.
    static let activityDays = 14

    /// `count` goals, `everyDays` apart from `firstMeeting`, splitting the pages after `startPage` evenly. Pages
    /// round to a multiple of five (people say "up to 150", not "up to 147"), the last goal is always the end of the
    /// book, and every goal reads at least one more page than the one before.
    static func schedule(
        pages: Int,
        startPage: Int = 0,
        firstMeeting: Date,
        everyDays: Int,
        count: Int,
        calendar: Calendar,
        now: Date = Date()
    ) -> [CircleMeeting] {
        let total = max(1, pages)
        let start = min(max(0, startPage), total - 1)
        let span = total - start
        let meetingCount = max(1, min(count, maximumMeetings, span))
        let gap = max(1, everyDays)
        var meetings: [CircleMeeting] = []
        var previous = start
        for index in 0..<meetingCount {
            let date = calendar.date(byAdding: .day, value: index * gap, to: firstMeeting) ?? firstMeeting
            var page: Int
            if index == meetingCount - 1 {
                page = total
            } else {
                let exact = Double(start) + Double(span) * Double(index + 1) / Double(meetingCount)
                page = Int((exact / 5).rounded()) * 5
                // Leave room for the goals still to come, and never stand still.
                page = min(max(page, previous + 1), total - (meetingCount - 1 - index))
            }
            meetings.append(CircleMeeting(date: date, throughPage: page, updatedAt: now))
            previous = page
        }
        return meetings
    }

    /// Goals from `startsOn` to finishing the book on `finishBy`: one every `everyDays` (the number of them rounded
    /// to the nearest whole), the last on `finishBy` itself at the end of the book. `everyDays` of 0, or a finish
    /// sooner than that, is a single goal: the end of the book. Every goal keeps `finishBy`'s time of day.
    static func goals(
        pages: Int,
        startPage: Int = 0,
        startsOn: Date,
        finishBy: Date,
        everyDays: Int,
        calendar: Calendar,
        now: Date = Date()
    ) -> [CircleMeeting] {
        let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: startsOn), to: calendar.startOfDay(for: finishBy)).day ?? 1)
        let gap = everyDays > 0 ? min(everyDays, days) : days
        let count = max(1, Int((Double(days) / Double(gap)).rounded()))
        let time = calendar.dateComponents([.hour, .minute], from: finishBy)
        let firstDay = calendar.date(byAdding: .day, value: gap, to: calendar.startOfDay(for: startsOn)) ?? finishBy
        let first = calendar.date(bySettingHour: time.hour ?? 19, minute: time.minute ?? 0, second: 0, of: firstDay) ?? firstDay
        var goals = schedule(pages: pages, startPage: startPage, firstMeeting: first, everyDays: gap, count: count, calendar: calendar, now: now)
        if !goals.isEmpty { goals[goals.count - 1].date = finishBy }
        return goals
    }

    /// Meetings in date order, with pages clamped to the book and never going down.
    static func normalized(_ meetings: [CircleMeeting], pages: Int) -> [CircleMeeting] {
        let total = max(1, pages)
        var lowest = 0
        return meetings.sorted { $0.date < $1.date }.map { meeting in
            var meeting = meeting
            meeting.throughPage = min(total, max(meeting.throughPage, lowest, 1))
            lowest = meeting.throughPage
            return meeting
        }
    }

    /// Where everyone stands at `now`. `myPage` is the reader's place in the library, when the book is there, and
    /// `myLog` their sittings with it (`CircleCheckIn.log(from:bookID:)`); without them the reader's own member is used.
    static func snapshot(
        for circle: ReadingCircle,
        myPage: Int?,
        myLog: [CircleCheckIn]? = nil,
        wpm: Double,
        now: Date,
        calendar: Calendar
    ) -> CircleSnapshot {
        let pages = max(1, circle.book.pages)
        let meetings = normalized(circle.meetings, pages: pages)
        let today = calendar.startOfDay(for: now)
        let nextIndex = meetings.firstIndex { calendar.startOfDay(for: $0.date) >= today }
        let next = nextIndex.map { meetings[$0] }
        let previous = nextIndex.flatMap { $0 > 0 ? meetings[$0 - 1] : nil }
        let sectionStart = previous?.throughPage ?? 0
        let sectionEnd = next?.throughPage ?? pages
        let daysUntil = next.map { max(0, calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0.date)).day ?? 0) }
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        // Where a steady reader would be today: a straight line from the last goal (or the start) to the next.
        let expected: Int = {
            guard let next else { return pages }
            let from = calendar.startOfDay(for: previous?.date ?? circle.startsOn)
            let to = calendar.startOfDay(for: next.date)
            let length = to.timeIntervalSince(from)
            guard length > 0 else { return next.throughPage }
            let share = min(1, max(0, today.timeIntervalSince(from) / length))
            return sectionStart + Int((Double(next.throughPage - sectionStart) * share).rounded())
        }()
        let slack = Int((Double(max(1, sectionEnd - sectionStart)) * paceSlack).rounded())

        var progress = circle.members.map { member -> CircleMemberProgress in
            let raw = member.kind == .me ? (myPage ?? member.page) : member.page
            let page = min(pages, max(0, raw))
            let pace: CirclePace
            if page >= pages {
                pace = .finished
            } else if let next, page >= next.throughPage {
                pace = .ready
            } else if page + slack >= expected {
                pace = .onPace
            } else {
                pace = .catchingUp
            }
            let sectionLength = max(1, sectionEnd - sectionStart)
            let sectionFraction = min(1, max(0, Double(page - sectionStart) / Double(sectionLength)))
            let log = member.kind == .me ? (myLog ?? member.log) : member.log
            let read = log.filter { $0.pages > 0 }
            return CircleMemberProgress(
                member: member, page: page, fraction: Double(page) / Double(pages),
                sectionFraction: sectionFraction, pace: pace,
                pagesToday: read.filter { $0.date >= today && $0.date <= now }.reduce(0) { $0 + $1.pages },
                pagesThisWeek: read.filter { $0.date >= weekStart && $0.date <= now }.reduce(0) { $0 + $1.pages },
                lastRead: read.last?.date,
                goalsMet: goalsMet(meetings, page: page, log: log, updatedAt: member.updatedAt, now: now, calendar: calendar),
                pagesToGoal: next.map { max(0, $0.throughPage - page) } ?? 0
            )
        }
        for index in progress.indices {
            progress[index].rank = 1 + progress.filter { $0.page > progress[index].page }.count
        }

        let readerPage = progress.first { $0.member.kind == .me }?.page ?? myPage ?? 0
        let toGo = next.map { max(0, $0.throughPage - readerPage) } ?? 0
        let minutes: Int? = {
            guard toGo > 0, let daysUntil else { return nil }
            let total = Double(toGo) * circle.book.wordsPerPage / max(wpm, 1)
            // Today counts as a reading day, so a goal tomorrow leaves two evenings.
            return max(1, Int((total / Double(daysUntil + 1)).rounded(.up)))
        }()

        return CircleSnapshot(
            circleID: circle.id,
            nextMeeting: next,
            nextMeetingIndex: nextIndex,
            daysUntilNext: daysUntil,
            sectionStart: sectionStart,
            sectionEnd: sectionEnd,
            members: progress,
            myPagesToGo: toGo,
            myMinutesPerDay: minutes,
            isComplete: next == nil && !meetings.isEmpty,
            statusLine: statusLine(next: next, daysUntil: daysUntil, toGo: toGo, minutes: minutes, myPage: readerPage,
                                   pages: pages, hasMeetings: !meetings.isEmpty, now: now, calendar: calendar),
            standingLine: standingLine(progress)
        )
    }

    /// Goals reached by the end of the goal's day. The log says when a page was first reached; a goal still to come
    /// that is already reached counts too, and without a log so does a passed goal reached by the last update.
    static func goalsMet(_ goals: [CircleMeeting], page: Int, log: [CircleCheckIn], updatedAt: Date, now: Date, calendar: Calendar) -> Int {
        goals.filter { goal in
            let deadline = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: goal.date)) ?? goal.date
            if let reached = log.first(where: { $0.page >= goal.throughPage }) {
                return reached.date < deadline
            }
            guard page >= goal.throughPage else { return false }
            return now < deadline || updatedAt < deadline
        }.count
    }

    /// "You’re 16 pages behind Sam." Against the nearest person ahead, or, out in front, the nearest behind.
    static func standingLine(_ progress: [CircleMemberProgress]) -> String? {
        guard let me = progress.first(where: \.isMe) else { return nil }
        let others = progress.filter { !$0.isMe }
        guard !others.isEmpty else { return nil }
        if me.pace == .finished, others.allSatisfy({ $0.pace == .finished }) { return "Everyone has finished the book." }
        if let ahead = others.filter({ $0.page > me.page }).min(by: { $0.page < $1.page }) {
            return "You’re \(pagesText(ahead.page - me.page)) behind \(names(others.filter { $0.page == ahead.page }))."
        }
        let level = others.filter { $0.page == me.page }
        if level.count == others.count {
            return others.count == 1 ? "You and \(firstName(others[0])) are on the same page." : "You’re all on the same page."
        }
        if level.count == 1 { return "You and \(firstName(level[0])) are out in front." }
        if level.count > 1 { return "You’re out in front with \(names(level))." }
        guard let behind = others.max(by: { $0.page < $1.page }) else { return nil }
        return "You’re out in front, \(pagesText(me.page - behind.page)) ahead of \(names(others.filter { $0.page == behind.page }))."
    }

    private static func firstName(_ progress: CircleMemberProgress) -> String {
        progress.member.name.split(separator: " ").first.map(String.init) ?? progress.member.name
    }

    /// "Sam", "Sam and Jo", "Sam and 2 others".
    private static func names(_ people: [CircleMemberProgress]) -> String {
        guard let first = people.first else { return "" }
        switch people.count {
        case 1: return firstName(first)
        case 2: return "\(firstName(first)) and \(firstName(people[1]))"
        default: return "\(firstName(first)) and \(people.count - 1) others"
        }
    }

    private static func pagesText(_ count: Int) -> String { count == 1 ? "1 page" : "\(count) pages" }

    /// What happened lately, newest first: sittings, goals reached, finishes and joins from everyone's logs over the
    /// last `activityDays` days. `myLog` stands in for the reader's own member's log, as in `snapshot`.
    static func activity(for circle: ReadingCircle, myLog: [CircleCheckIn]? = nil, now: Date, calendar: Calendar, limit: Int = 6) -> [CircleActivity] {
        let pages = max(1, circle.book.pages)
        let goals = normalized(circle.meetings, pages: pages)
        let since = calendar.date(byAdding: .day, value: -activityDays, to: calendar.startOfDay(for: now)) ?? now
        var events: [CircleActivity] = []
        for member in circle.members {
            let log = member.kind == .me ? (myLog ?? member.log) : member.log
            let isOwnLog = member.kind != .me || myLog == nil
            for (index, entry) in log.enumerated() where entry.date >= since && entry.date <= now {
                if index == 0, entry.pages == 0, isOwnLog {
                    events.append(CircleActivity(memberID: member.id, date: entry.date, kind: .joined(page: entry.page)))
                    continue
                }
                guard entry.pages > 0 else { continue }
                let before = entry.page - entry.pages
                let kind: CircleActivity.Kind
                if entry.page >= pages, before < pages {
                    kind = .finished
                } else if let goal = goals.last(where: { before < $0.throughPage && $0.throughPage <= entry.page }) {
                    kind = .reachedGoal(page: goal.throughPage, goalDate: goal.date)
                } else {
                    kind = .read(pages: entry.pages)
                }
                events.append(CircleActivity(memberID: member.id, date: entry.date, kind: kind))
            }
        }
        return Array(events.sorted { $0.date != $1.date ? $0.date > $1.date : $0.memberID.uuidString < $1.memberID.uuidString }.prefix(max(0, limit)))
    }

    private static func statusLine(
        next: CircleMeeting?, daysUntil: Int?, toGo: Int, minutes: Int?, myPage: Int, pages: Int,
        hasMeetings: Bool, now: Date, calendar: Calendar
    ) -> String {
        guard hasMeetings else { return "No goals yet. Pick a page and a day, and everyone has something to aim for." }
        guard let next, let daysUntil else {
            return myPage >= pages
                ? "Every goal has passed. A whole book, read together."
                : "Every goal has passed. Set another, or put the circle away."
        }
        // "tomorrow", "Thursday", "Nov 2": lower case where it sits mid-sentence.
        let day = LeafFormat.relativeDay(next.date, today: now, calendar: calendar)
        let when = daysUntil <= 1 ? day.lowercased() : day
        let goal: String
        switch daysUntil {
        case 0: goal = "Today’s goal"
        case 1..<7: goal = "\(day)’s goal"
        default: goal = "The goal for \(day)"
        }
        if toGo == 0 {
            return daysUntil == 0
                ? "Today’s goal is page \(next.throughPage). You’re there."
                : "\(goal) is page \(next.throughPage). You’re there already."
        }
        let left = pagesText(toGo)
        if daysUntil == 0 {
            return "\(goal) is page \(next.throughPage). \(left) to go."
        }
        let minutesText = minutes.map { $0 == 1 ? ", about a minute a day" : ", about \($0) minutes a day" } ?? ""
        return "\(left) before \(when)\(minutesText)."
    }
}

// MARK: - Discussion prompts

/// A question to bring to a meeting. Written text only.
struct CirclePrompt: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case opening, middle, closing, genre
    }

    var id: String
    var kind: Kind
    var text: String
}

/// Questions for a meeting, chosen by where the meeting falls in the book and what kind of book it is. The same
/// circle and meeting always give the same questions; `shuffle` asks for another set.
enum CirclePrompts {
    static let opening: [String] = [
        "Who did you trust first, and has that changed yet?",
        "What did the first chapter promise you?",
        "Which line from these pages would you read aloud to the others?",
        "Where would you sit in this world: front row, or somewhere you could slip out?",
        "What do you hope does not happen?",
        "Which character would you invite for tea, and which would you hide the good cups from?",
        "What did you notice about the way the book sounds, before anything much happened?",
        "If you had to guess the ending now, what would you write down?",
    ]

    static let middle: [String] = [
        "Which choice in this stretch surprised you most?",
        "Has anyone changed their mind about a character since last time?",
        "What is the book quietly asking you to care about?",
        "Which scene would you film first?",
        "Where did you slow down, and where did you race?",
        "What do you know now that a character doesn’t?",
        "Which small detail feels like it will matter later?",
        "If you could ask the author one thing about these pages, what would it be?",
    ]

    static let closing: [String] = [
        "Did the ending feel earned?",
        "Who changed the most, and who didn’t change at all?",
        "What will you still be thinking about next week?",
        "Was there a moment you wanted to put the book down and just sit with it?",
        "If this book were a tea, what would it be?",
        "Who would you hand this book to, and what would you tell them?",
        "Which page would you dog-ear, if you were the dog-earing kind?",
        "What did reading it together add that reading it alone wouldn’t have?",
    ]

    /// Lowercased genre to prompts. A book gets at most one of these per meeting.
    static let byGenre: [String: [String]] = [
        "mystery": [
            "Who is your suspect, and what is your flimsiest piece of evidence?",
            "Which clue do you think was planted for us, and which was planted for the detective?",
        ],
        "fantasy": [
            "Which rule of this world would you most like to bring home?",
            "What does the magic cost here, and is it worth it?",
        ],
        "science-fiction": [
            "Which idea in here could be true in fifty years?",
            "What does this future get right about people?",
        ],
        "romance": [
            "When did you know they would end up together, or did you?",
            "What does each of them have to give up?",
        ],
        "historical": [
            "What detail made the past feel close?",
            "Whose story does history usually leave out, and does this book let them in?",
        ],
        "literary": [
            "What is left unsaid that everyone in the book can hear?",
            "Which sentence did you read twice?",
        ],
        "memoir": [
            "What would you ask the author over dinner?",
            "Which memory felt like one of your own?",
        ],
        "classics": [
            "What still feels modern, and what has aged?",
            "Why do you think people kept reading this one?",
        ],
    ]

    /// Up to `count` questions for the meeting at `meetingIndex`: questions for where it falls in the book (the
    /// first meeting, one in the middle, the last), plus one for the book's genre when there is one.
    static func prompts(for circle: ReadingCircle, meetingIndex: Int, count: Int = 3, shuffle: Int = 0) -> [CirclePrompt] {
        guard count > 0 else { return [] }
        let meetingCount = max(1, circle.meetings.count)
        let index = min(max(0, meetingIndex), meetingCount - 1)
        let kind: CirclePrompt.Kind
        let pool: [String]
        if !circle.meetings.isEmpty, index == meetingCount - 1 {
            kind = .closing
            pool = closing
        } else if index == 0 {
            kind = .opening
            pool = opening
        } else {
            kind = .middle
            pool = middle
        }
        let seed = stableHash("\(circle.id.uuidString)#\(index)#\(shuffle)")

        var genrePrompt: CirclePrompt?
        if count > 1, let genre = circle.book.genres.map({ $0.lowercased() }).first(where: { byGenre[$0] != nil }),
           let genrePool = byGenre[genre], !genrePool.isEmpty {
            let pick = Int(seed % UInt64(genrePool.count))
            genrePrompt = CirclePrompt(id: "\(genre).\(pick)", kind: .genre, text: genrePool[pick])
        }

        // Walk the pool from a seeded start with a step coprime to its size, so picks are spread out and never repeat.
        var chosen: [CirclePrompt] = []
        let size = pool.count
        let wanted = min(size, count - (genrePrompt == nil ? 0 : 1))
        if size > 0, wanted > 0 {
            let start = Int((seed >> 8) % UInt64(size))
            let steps = [3, 5, 7, 1].filter { gcd($0, size) == 1 }
            let step = steps[Int((seed >> 16) % UInt64(steps.count))]
            for offset in 0..<wanted {
                let position = (start + offset * step) % size
                chosen.append(CirclePrompt(id: "\(kind.rawValue).\(position)", kind: kind, text: pool[position]))
            }
        }
        if let genrePrompt { chosen.append(genrePrompt) }
        return chosen
    }

    /// FNV-1a, so prompts don't change between launches the way `Hasher` would.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}
