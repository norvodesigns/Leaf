import Foundation

// MARK: - Model

/// A reading circle (a book club): one book, a few people, and a schedule of meetings that each read up to a page.
///
/// Local-first. Members are people the reader adds by name and moves along by hand; the reader's own place comes from
/// the library. Every entity has a stable id and an `updatedAt`, and a member can name the participant it stands for
/// (`remoteID`), so a shared version can merge circles field by field later without changing this model.
struct ReadingCircle: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// A copy of the book, so the circle still shows if the book leaves the library.
    var book: Book
    /// The day the circle starts reading. Pace before the first meeting is measured from here.
    var startsOn: Date
    /// In date order. `CirclePlanner.normalized` keeps them sorted with pages that only go up.
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
}

/// One get-together: the date, and the page everyone reads up to.
struct CircleMeeting: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var date: Date
    /// Read up to and including this page by the meeting.
    var throughPage: Int
    /// Where ("Sam’s kitchen", "the café on Hill St"). Optional and free text.
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
        /// Someone the reader added by name and moves along by hand.
        case friend
    }

    var id: UUID
    var name: String
    var kind: Kind
    /// The last page they read to. For `.me` this is a fallback when the book isn't in the library.
    var page: Int
    /// A `CozyPalette` token for their ring.
    var paletteToken: String
    /// The participant this member stands for in a shared circle. Always nil while circles are local.
    var remoteID: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .friend,
        page: Int = 0,
        paletteToken: String = CozyPalette.chai,
        remoteID: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.page = page
        self.paletteToken = paletteToken
        self.remoteID = remoteID
        self.updatedAt = updatedAt
    }

    /// "SM" for "Sam Marsh", "J" for "Jo". At most two letters, for the middle of a ring.
    var initials: String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

// MARK: - Snapshot

/// Where a member stands against the next meeting.
enum CirclePace: String, Hashable, Sendable {
    /// Read to the end of the book.
    case finished
    /// Already at or past the next meeting's page.
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
    /// Of the section for the next meeting, 0 to 1.
    var sectionFraction: Double
    var pace: CirclePace

    var id: UUID { member.id }
}

/// Everything the circle screen shows, worked out for one moment.
struct CircleSnapshot: Hashable, Sendable {
    var circleID: UUID
    /// The meeting to read towards: today's, or the first one still to come. Nil when every meeting has passed.
    var nextMeeting: CircleMeeting?
    /// Its position in `meetings`, from 0.
    var nextMeetingIndex: Int?
    /// Whole days until it, 0 when it's today.
    var daysUntilNext: Int?
    /// The pages this stretch covers: after the previous meeting's page, up to the next one's.
    var sectionStart: Int
    var sectionEnd: Int
    var members: [CircleMemberProgress]
    /// Pages the reader still has before the next meeting.
    var myPagesToGo: Int
    /// Minutes a day at the reader's pace to be there in time, or nil when there is nothing to read.
    var myMinutesPerDay: Int?
    /// Every meeting has passed.
    var isComplete: Bool
    /// One calm sentence for the top of the card.
    var statusLine: String

    var me: CircleMemberProgress? { members.first { $0.member.kind == .me } }
}

// MARK: - Planner

/// The arithmetic behind a circle: an even schedule, and where everyone stands. Pure and deterministic.
enum CirclePlanner {
    /// How far below a steady pace still counts as on pace, as a share of the section.
    static let paceSlack = 0.15
    static let maximumMeetings = 24

    /// `count` meetings, `everyDays` apart from `firstMeeting`, splitting the pages after `startPage` evenly. Pages
    /// round to a multiple of five (people say "up to 150", not "up to 147"), the last meeting is always the end of
    /// the book, and every meeting reads at least one more page than the one before.
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
                // Leave room for the meetings still to come, and never stand still.
                page = min(max(page, previous + 1), total - (meetingCount - 1 - index))
            }
            meetings.append(CircleMeeting(date: date, throughPage: page, updatedAt: now))
            previous = page
        }
        return meetings
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

    /// Where everyone stands at `now`. `myPage` is the reader's place in the library, when the book is there.
    static func snapshot(
        for circle: ReadingCircle,
        myPage: Int?,
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

        // Where a steady reader would be today: a straight line from the last meeting (or the start) to the next.
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

        let progress = circle.members.map { member -> CircleMemberProgress in
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
            return CircleMemberProgress(
                member: member, page: page, fraction: Double(page) / Double(pages),
                sectionFraction: sectionFraction, pace: pace
            )
        }

        let readerPage = progress.first { $0.member.kind == .me }?.page ?? myPage ?? 0
        let toGo = next.map { max(0, $0.throughPage - readerPage) } ?? 0
        let minutes: Int? = {
            guard toGo > 0, let daysUntil else { return nil }
            let total = Double(toGo) * circle.book.wordsPerPage / max(wpm, 1)
            // Today counts as a reading day, so a meeting tomorrow leaves two evenings.
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
                                   pages: pages, hasMeetings: !meetings.isEmpty, now: now, calendar: calendar)
        )
    }

    private static func statusLine(
        next: CircleMeeting?, daysUntil: Int?, toGo: Int, minutes: Int?, myPage: Int, pages: Int,
        hasMeetings: Bool, now: Date, calendar: Calendar
    ) -> String {
        guard hasMeetings else { return "No meetings yet. Pick a date and everyone has a page to aim for." }
        guard let next, let daysUntil else {
            return myPage >= pages
                ? "The last meeting has been. A whole book, read together."
                : "Every meeting has been. Add another, or put the circle away."
        }
        // "tomorrow", "Thursday", "Nov 2": lower case where it sits mid-sentence.
        let day = LeafFormat.relativeDay(next.date, today: now, calendar: calendar)
        let when = daysUntil <= 1 ? day.lowercased() : day
        let meeting: String
        switch daysUntil {
        case 0: meeting = "The meeting is today"
        case 1..<7: meeting = "\(day)’s meeting"
        default: meeting = "The meeting on \(day)"
        }
        if toGo == 0 {
            return daysUntil == 0
                ? "The meeting is today, up to page \(next.throughPage). You’re ready."
                : "\(meeting) reads to page \(next.throughPage). You’re there already."
        }
        let pagesText = toGo == 1 ? "1 page" : "\(toGo) pages"
        if daysUntil == 0 {
            return "\(meeting), up to page \(next.throughPage). \(pagesText) to go."
        }
        let minutesText = minutes.map { $0 == 1 ? ", about a minute a day" : ", about \($0) minutes a day" } ?? ""
        return "\(pagesText) before \(when)\(minutesText)."
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
