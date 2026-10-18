import Foundation

/// What a reminder may talk about. Small on purpose: the notification scheduler fills it from the plan.
struct NotificationContext: Equatable, Sendable {
    var bookTitle: String?
    /// Minutes planned for the day.
    var minutes: Int
    var streak: Int
    var isRestDay: Bool
    var daypart: Daypart
    /// Pages left in the book, when it is close to the end.
    var pagesLeft: Int?

    init(bookTitle: String? = nil, minutes: Int, streak: Int = 0, isRestDay: Bool = false, daypart: Daypart, pagesLeft: Int? = nil) {
        self.bookTitle = bookTitle
        self.minutes = minutes
        self.streak = streak
        self.isRestDay = isRestDay
        self.daypart = daypart
        self.pagesLeft = pagesLeft
    }
}

struct NotificationMessage: Equatable, Sendable {
    /// Stable per template. Keep the last one and pass it back so two days never read the same.
    var id: String
    var title: String
    var body: String
}

/// One reminder day: its context and its seed (use `SeededGenerator.daySeed` for the day it fires).
struct NotificationDay: Equatable, Sendable {
    var context: NotificationContext
    var seed: UInt64
}

/// Reminder copy that varies instead of repeating one template. Never guilt, never a streak threat, never the same as the
/// last one, and short enough for a lock screen: a title of at most `maxTitleLength` characters and a body of at most
/// `maxBodyLength`, even with a very long book title.
enum NotificationCopy {
    static let maxTitleLength = 32
    static let maxBodyLength = 100
    /// Book titles are cut to this many characters inside a notification.
    static let maxBookTitleLength = 26
    /// A near-finish nudge is used for this many pages or fewer.
    static let nearFinishPages = 30

    enum Kind: String, CaseIterable, Sendable {
        case generic, morning, afternoon, teaTime, evening, late, nearFinish, streak, restDay, goalReached
    }

    struct Template: Equatable, Sendable, Identifiable {
        let id: String
        let kind: Kind
        let title: String
        let body: String
        let placeholders: Set<VoicePlaceholder>

        init(_ kind: Kind, _ title: String, _ body: String) {
            self.kind = kind
            self.title = title
            self.body = body
            placeholders = VoiceTemplate.placeholders(in: title).union(VoiceTemplate.placeholders(in: body))
            id = VoiceText.stableID("notification." + kind.rawValue, title + "|" + body)
        }
    }

    // MARK: Pool

    static let templates: [Template] = [
        // Any time of day.
        Template(.generic, "Ten quiet minutes?", "{minutes} of {title} is waiting."),
        Template(.generic, "A page or two?", "{title} is right where you left it."),
        Template(.generic, "Reading time", "Today’s {minutes} are ready when you are."),
        Template(.generic, "Open the book?", "{minutes} with {title} makes a good day."),
        Template(.generic, "A small pause", "Step away for a chapter. {title} is ready."),
        Template(.generic, "Your bookmark is waiting", "Pick {title} back up whenever you like."),
        Template(.generic, "Time for a page?", "Your book is ready when you are."),
        Template(.generic, "A moment for you", "A few pages of {title}, if you fancy."),
        Template(.generic, "Your reading hour", "{minutes} today. {title} is up next."),
        Template(.generic, "Book break", "Slip away for a chapter."),

        Template(.morning, "Good morning", "Start with {minutes} of {title}?"),
        Template(.morning, "Morning pages", "A few minutes with {title} before the day starts."),
        Template(.morning, "Early reader", "{minutes} of quiet with your book?"),
        Template(.morning, "A calm start", "{title} is ready when you are."),

        Template(.afternoon, "Afternoon break", "{minutes} of {title}? The kettle can wait."),
        Template(.afternoon, "A midday chapter", "Spend part of your break with {title}."),
        Template(.afternoon, "A little escape", "{minutes} with a good book this afternoon?"),
        Template(.afternoon, "Afternoon pages", "Your book is ready when the day allows."),

        Template(.teaTime, "Tea o’clock", "Pour a cup and read {minutes} of {title}."),
        Template(.teaTime, "Kettle time", "A cup, a chair, a chapter of {title}."),
        Template(.teaTime, "Teatime", "The best hour for a story. {title} is waiting."),
        Template(.teaTime, "Late afternoon light", "A short chapter before the evening?"),

        Template(.evening, "Good evening", "Kettle on? {minutes} of {title} awaits."),
        Template(.evening, "Evening chapter", "The day’s done. {title} is open for you."),
        Template(.evening, "Lamp on", "Settle in with {title} for {minutes}."),
        Template(.evening, "The evening is yours", "A chapter of {title} would fit nicely."),
        Template(.evening, "Wind down", "A few quiet pages before the night."),

        Template(.late, "Still up?", "One more chapter of {title}, then bed."),
        Template(.late, "A late page", "A few pages of {title} before sleep."),
        Template(.late, "Night reading", "{minutes} of quiet, then lights out."),
        Template(.late, "Before you sleep", "Your book is right here."),

        // Close to the end of a book.
        Template(.nearFinish, "Almost done", "{pages} left in {title}. Finish it today?"),
        Template(.nearFinish, "The last stretch", "{title} is {pages} from the end."),
        Template(.nearFinish, "So close", "{pages} and {title} is finished."),
        Template(.nearFinish, "Nearly there", "The ending of {title} is {pages} away."),

        // A run of days, celebrated and never threatened.
        Template(.streak, "{streak} days in a row", "{minutes} of {title} tonight?"),
        Template(.streak, "A lovely run", "{streak} days of reading. Another {minutes}?"),
        Template(.streak, "Day {streak}", "Your reading habit is humming along."),
        Template(.streak, "{streak} days of pages", "{title} is ready for more."),

        // A planned day off.
        Template(.restDay, "A day off", "No plan today. {title} is there if you want it."),
        Template(.restDay, "Rest day", "Nothing scheduled. Read if you feel like it."),
        Template(.restDay, "Take it easy", "Your book will keep. Read only if it calls."),
        Template(.restDay, "No pressure today", "A page or two, or none at all."),

        // While a session runs, at the goal.
        Template(.goalReached, "Goal met", "That’s today’s {minutes}. Anything more is a gift."),
        Template(.goalReached, "Today’s reading: done", "{minutes} down. Stay if the chapter’s good."),
        Template(.goalReached, "Nicely done", "You’ve read your {minutes}. The rest is a bonus."),
        Template(.goalReached, "That’s the goal", "Keep going if you like, or close it happy."),
        Template(.goalReached, "Goal reached", "Another cup, or call it a day?"),
        Template(.goalReached, "Pages done", "Today’s reading is in the bank."),
    ]

    // MARK: Writing

    /// A reminder for one day. Deterministic for a seed; never the same template as `previousID`.
    static func reminder(for context: NotificationContext, seed: UInt64, previousID: String? = nil) -> NotificationMessage {
        let values = self.values(for: context)
        let kinds = candidateKinds(for: context, seed: seed)

        var options: [Template] = []
        for kind in kinds {
            options = usable(kind: kind, values: values, previousID: previousID)
            if !options.isEmpty { break }
        }
        if options.isEmpty { options = usable(kind: .generic, values: values, previousID: nil) }
        return message(from: options, values: values, seed: seed, salt: "reminder")
    }

    /// The "goal reached" nudge sent while a session runs.
    static func goalReached(minutes: Int, seed: UInt64, previousID: String? = nil) -> NotificationMessage {
        let values = VoiceValues(minutes: minutes, spellsNumbers: false, maxTitleCharacters: maxBookTitleLength)
        var options = usable(kind: .goalReached, values: values, previousID: previousID)
        if options.isEmpty { options = usable(kind: .goalReached, values: values, previousID: nil) }
        return message(from: options, values: values, seed: seed, salt: "goal")
    }

    /// Reminders for a run of days, each different from the one before it.
    static func series(_ days: [NotificationDay], previousID: String? = nil) -> [NotificationMessage] {
        var previous = previousID
        var result: [NotificationMessage] = []
        for day in days {
            let next = reminder(for: day.context, seed: day.seed, previousID: previous)
            result.append(next)
            previous = next.id
        }
        return result
    }

    // MARK: Choosing

    private static func values(for context: NotificationContext) -> VoiceValues {
        VoiceValues(
            title: context.bookTitle,
            pagesLeft: context.pagesLeft,
            streak: context.streak,
            minutes: context.minutes,
            spellsNumbers: false,
            maxTitleCharacters: maxBookTitleLength
        )
    }

    /// Kinds to try, best first. A rest day only gets rest-day copy; a book near its end usually gets a nudge about it;
    /// a run of days is mentioned now and then; otherwise the hour decides.
    private static func candidateKinds(for context: NotificationContext, seed: UInt64) -> [Kind] {
        if context.isRestDay { return [.restDay, .generic] }
        var kinds: [Kind] = []
        if let left = context.pagesLeft, left >= 1, left <= nearFinishPages, VoiceText.chance(0.6, seed: seed, salt: "near") {
            kinds.append(.nearFinish)
        }
        if context.streak >= 3, VoiceText.chance(0.25, seed: seed, salt: "streak") {
            kinds.append(.streak)
        }
        kinds.append(kind(for: context.daypart))
        kinds.append(.generic)
        return kinds
    }

    private static func kind(for daypart: Daypart) -> Kind {
        switch daypart {
        case .dawn, .morning: return .morning
        case .lunch, .afternoon: return .afternoon
        case .teaTime: return .teaTime
        case .dusk, .evening: return .evening
        case .late, .smallHours: return .late
        }
    }

    /// Templates of one kind that can be filled and were not the last one. The hour's own copy is weighed against the
    /// generic pool by the caller falling through, so ordinary days still vary.
    private static func usable(kind: Kind, values: VoiceValues, previousID: String?) -> [Template] {
        let available = values.available
        var pool = templates.filter { $0.kind == kind && $0.id != previousID && $0.placeholders.isSubset(of: available) }
        if kind != .generic, kind != .restDay, kind != .nearFinish, kind != .streak, kind != .goalReached {
            // Mix a little of the generic copy into the hour's own, so a given hour is not a closed loop.
            pool += templates.filter { $0.kind == .generic && $0.id != previousID && $0.placeholders.isSubset(of: available) }
        }
        return pool
    }

    private static func message(from options: [Template], values: VoiceValues, seed: UInt64, salt: String) -> NotificationMessage {
        guard let template = VoiceText.choose(options, seed: seed, salt: salt),
              let title = VoiceTemplate.fill(template.title, with: values),
              let body = VoiceTemplate.fill(template.body, with: values)
        else {
            return NotificationMessage(id: "notification.fallback", title: "Time for a page?", body: "Your book is ready when you are.")
        }
        return NotificationMessage(id: template.id, title: title, body: body)
    }
}
