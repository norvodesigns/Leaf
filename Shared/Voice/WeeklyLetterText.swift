import Foundation

/// A week of reading, as plain numbers. The caller fills it from the sessions; this file only finds the words.
struct WeeklyLetterInput: Equatable, Sendable {
    var minutes: Double
    var cups: Int
    var pages: Int
    var booksFinished: Int
    /// Titles of the books finished, if known (used when one or two were finished).
    var finishedTitles: [String]
    var daysRead: Int
    /// The weekday of the best day (1 = Sunday), and how long was read then.
    var bestDayWeekday: Int?
    var bestDayMinutes: Double?
    /// Days in a row, counting through today.
    var streak: Int
    /// Last week's minutes, for the comparison. Nil or zero leaves the comparison out.
    var lastWeekMinutes: Double?

    init(
        minutes: Double,
        cups: Int,
        pages: Int,
        booksFinished: Int = 0,
        finishedTitles: [String] = [],
        daysRead: Int = 0,
        bestDayWeekday: Int? = nil,
        bestDayMinutes: Double? = nil,
        streak: Int = 0,
        lastWeekMinutes: Double? = nil
    ) {
        self.minutes = minutes
        self.cups = cups
        self.pages = pages
        self.booksFinished = booksFinished
        self.finishedTitles = finishedTitles
        self.daysRead = daysRead
        self.bestDayWeekday = bestDayWeekday
        self.bestDayMinutes = bestDayMinutes
        self.streak = streak
        self.lastWeekMinutes = lastWeekMinutes
    }
}

struct WeeklyLetterCopy: Equatable, Sendable {
    var title: String
    /// Three to five sentences, each ending with a full stop or a question mark.
    var sentences: [String]

    var body: String { sentences.joined(separator: " ") }
}

/// The Sunday-evening recap: a warm three to five sentences, never a scolding one. A quiet week gets as much kindness as
/// a big one. Real numbers always sit beside the cute units.
enum WeeklyLetterText {
    static let titles = ["Your week in reading", "A letter from your nook", "This week’s pages"]

    /// A week of at least this many minutes is a big one; under `lightMinutes` is a gentle one.
    static let bigWeekMinutes = 420.0
    static let lightMinutes = 90.0
    /// Within this fraction of last week counts as "about the same".
    static let sameBand = 0.15

    static func compose(_ input: WeeklyLetterInput, seed: UInt64) -> WeeklyLetterCopy {
        let minutes = input.minutes.isFinite ? max(0, input.minutes) : 0
        let title = VoiceText.choose(titles, seed: seed, salt: "letter|title") ?? titles[0]

        var sentences: [String] = []
        sentences.append(opener(minutes: minutes, seed: seed))

        if minutes < 0.5 {
            sentences.append(pick(["The pages will be right here on Monday.", "Your bookmark kept your place all week.", "The book is where you left it, and so is the kettle."], seed: seed, salt: "letter|quiet"))
        } else {
            sentences.append(numbers(input, minutes: minutes, seed: seed))
        }

        // Up to two highlights, so the letter never runs past five sentences.
        var highlights: [String] = []
        if let finished = finishedSentence(input) { highlights.append(finished) }
        if let comparison = comparisonSentence(input, minutes: minutes, seed: seed) { highlights.append(comparison) }
        if highlights.count < 2, let best = bestDaySentence(input) { highlights.append(best) }
        sentences += highlights.prefix(2)

        sentences.append(closer(input, minutes: minutes, seed: seed))
        return WeeklyLetterCopy(title: title, sentences: sentences)
    }

    // MARK: Pieces

    private static func opener(minutes: Double, seed: UInt64) -> String {
        let options: [String]
        switch minutes {
        case ..<0.5:
            options = ["A quiet week on the page.", "A rest week, and that’s allowed.", "A still week for the books."]
        case ..<lightMinutes:
            options = ["A gentle week of reading.", "A small, soft week with your books.", "A few good pages this week."]
        case ..<bigWeekMinutes:
            options = ["A steady week with your books.", "Here’s your week, and it was a good one.", "Another week of pages, nicely done."]
        default:
            options = ["What a week of reading.", "A big reading week.", "You really settled in this week."]
        }
        return pick(options, seed: seed, salt: "letter|opener")
    }

    private static func numbers(_ input: WeeklyLetterInput, minutes: Double, seed: UInt64) -> String {
        let time = LeafFormat.duration(minutes: minutes)
        let days = input.daysRead > 0 ? " over \(input.daysRead) \(input.daysRead == 1 ? "day" : "days")" : ""
        let cups = cupsPhrase(input.cups)
        let pages = input.pages > 0 ? " and \(input.pages) \(input.pages == 1 ? "page" : "pages")" : ""
        let options = [
            "You read \(time)\(days), about \(cups)\(pages).",
            "That’s \(time)\(days): \(cups)\(pages).",
            "In all, \(time)\(days), or \(cups)\(pages).",
        ]
        return pick(options, seed: seed, salt: "letter|numbers")
    }

    private static func cupsPhrase(_ cups: Int) -> String {
        switch cups {
        case ..<1: return "less than a cup"
        case 1: return "a cup"
        default: return "\(cups) cups"
        }
    }

    private static func finishedSentence(_ input: WeeklyLetterInput) -> String? {
        guard input.booksFinished > 0 else { return nil }
        let titles = input.finishedTitles.compactMap(VoiceText.clean).map { VoiceText.shortTitle($0, maxCharacters: 40) }
        if input.booksFinished == 1 {
            return titles.first.map { "You finished \($0)." } ?? "You finished a book this week."
        }
        if input.booksFinished == 2, titles.count == 2 {
            return "You finished two books, \(titles[0]) and \(titles[1])."
        }
        return "You finished \(VoiceText.count(input.booksFinished)) books."
    }

    private static func comparisonSentence(_ input: WeeklyLetterInput, minutes: Double, seed: UInt64) -> String? {
        guard let last = input.lastWeekMinutes, last.isFinite, last > 0, minutes >= 0.5 else { return nil }
        let ratio = minutes / last
        if ratio >= 1 + sameBand {
            return pick(["That’s more than last week.", "A bit more than last week, too.", "You read more than the week before."], seed: seed, salt: "letter|up")
        }
        if ratio <= 1 - sameBand {
            return pick(["A little quieter than last week, and that’s perfectly fine.", "Slightly fewer minutes than last week, which is allowed.", "A softer week than the last one, and that’s fine."], seed: seed, salt: "letter|down")
        }
        return pick(["About the same as last week, which is its own kind of lovely.", "Right in step with last week.", "Steady, just like last week."], seed: seed, salt: "letter|same")
    }

    private static func bestDaySentence(_ input: WeeklyLetterInput) -> String? {
        guard let weekday = input.bestDayWeekday, let minutes = input.bestDayMinutes, minutes.isFinite, minutes >= 1 else { return nil }
        return "\(VoiceText.weekdayName(weekday)) was your best day, with \(LeafFormat.duration(minutes: minutes))."
    }

    private static func closer(_ input: WeeklyLetterInput, minutes: Double, seed: UInt64) -> String {
        if input.streak >= 3 {
            return pick([
                "That’s \(input.streak) days in a row now, and the kettle is ready for next week.",
                "\(input.streak) days in a row so far, and here’s to the next page.",
                "You’re on \(input.streak) days in a row, and next week’s first page is waiting.",
            ], seed: seed, salt: "letter|streak")
        }
        return pick([
            "Next week’s first page is already waiting.",
            "Whenever you’re ready, your book is right here.",
            "The kettle is on for next week.",
            "Here’s to a few more pages next week.",
        ], seed: seed, salt: "letter|closer")
    }

    private static func pick(_ options: [String], seed: UInt64, salt: String) -> String {
        VoiceText.choose(options, seed: seed, salt: salt) ?? options[0]
    }
}
