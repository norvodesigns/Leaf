import Foundation

/// The live sentences onboarding writes from the reader's choices (DESIGN.md §11 voice:
/// warm, brief, specific; minutes and pages first; curly quotes and real dashes).
enum OnboardingCopy {
    private static let smallNumbers = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    /// Words per printed page when we don't know the book yet.
    static let wordsPerPage: Double = 270

    /// "three" for 0…12, digits above.
    static func spelled(_ number: Int) -> String {
        smallNumbers.indices.contains(number) ? smallNumbers[number] : String(number)
    }

    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: - Result

    /// The book the result is translated into. Fixed, so the sentence reads the same offline.
    static let referenceTitle = "The Hobbit"
    static let referenceWords: Double = 95_000
    static let referencePages = 310

    /// Minutes to read the reference book at `wpm`.
    static func referenceMinutes(wpm: Double) -> Double {
        referenceWords / max(wpm, 1)
    }

    /// "about six hours", "about six and a half hours", "about an hour", "about 40 minutes".
    static func aboutDuration(minutes: Double) -> String {
        if minutes < 50 {
            let rounded = max(5, Int((minutes / 5).rounded()) * 5)
            return "about \(rounded) minutes"
        }
        let halfHours = Int((minutes / 30).rounded())
        let hours = halfHours / 2
        let hasHalf = halfHours % 2 == 1
        if hours > 12 {
            return "about \(Int((minutes / 60).rounded())) hours"
        }
        switch (hours, hasHalf) {
        case (1, false): return "about an hour"
        case (1, true): return "about an hour and a half"
        case (_, false): return "about \(spelled(hours)) hours"
        case (_, true): return "about \(spelled(hours)) and a half hours"
        }
    }

    /// Where the reader sits among adults, without ever making a slow reader feel behind.
    static func standing(wpm: Double) -> String {
        let percentile = ReadingSpeed.percentile(for: wpm)
        let descriptor = ReadingSpeed.descriptor(for: wpm)
        if percentile >= 55 {
            return "\(descriptor) — quicker than about \(percentile)% of adults."
        }
        if percentile >= 45 {
            return "\(descriptor) — right in step with most adult readers."
        }
        return "\(descriptor) — a careful pace, with room for the sentences to land."
    }

    // MARK: - Minutes

    /// "a novel every three weeks" (an 80,000-word novel), from `Planner.booksPerYear`.
    static func novelCadence(booksPerYear: Double) -> String? {
        guard booksPerYear > 0 else { return nil }
        let days = 365.25 / booksPerYear
        if days < 1.5 { return "about a novel a day" }
        if days < 6.5 { return "a novel every \(spelled(Int(days.rounded()))) days" }
        let weeks = Int((days / 7).rounded())
        if weeks <= 1 { return "a novel a week" }
        if weeks < 7 { return "a novel every \(spelled(weeks)) weeks" }
        let months = Int((days / 30.44).rounded())
        if months <= 1 { return "a novel a month" }
        if months < 12 { return "a novel every \(spelled(months)) months" }
        return "a novel or so a year"
    }

    /// The live preview under the MinutesDial: "About 37 pages a day — a novel every three weeks."
    /// plus "About 21 books a year at 262 words a minute."
    static func minutesPreview(minutes: Int, wpm: Double, daysPerWeek: Int) -> (quote: String, caption: String) {
        let pages = max(1, Int((Double(minutes) * wpm / wordsPerPage).rounded()))
        let perYear = Planner.booksPerYear(wpm: wpm, dailyMinutes: minutes, daysPerWeek: max(1, min(7, daysPerWeek)))
        let quote: String
        if let cadence = novelCadence(booksPerYear: perYear) {
            quote = "About \(pages) pages a day — \(cadence)."
        } else {
            quote = "About \(pages) pages a day."
        }
        let yearly = max(1, Int(perYear.rounded()))
        let books = yearly == 1 ? "one book" : "\(yearly) books"
        return (quote, "About \(books) a year at \(Int(wpm.rounded())) words a minute.")
    }

    // MARK: - Days

    /// "Five days a week, weekends off.", "Every day of the week.", "Pick at least one day."
    static func weekSummary(_ days: Set<Int>) -> String {
        let valid = days.filter { (1...7).contains($0) }
        let weekend: Set<Int> = [1, 7]
        switch valid.count {
        case 0:
            return "Pick at least one day."
        case 7:
            return "Every day of the week."
        case 1:
            if let day = valid.first { return "\(dayName(day))s only." }
        case 6:
            if let off = Set(1...7).subtracting(valid).first { return "Six days a week, \(dayName(off))s off." }
        default:
            break
        }
        if valid == weekend { return "Weekends only." }
        let count = capitalized(spelled(valid.count))
        if valid.isDisjoint(with: weekend) { return "\(count) days a week, weekends off." }
        return "\(count) days a week."
    }

    /// "That’s 2 h 5 min of reading a week."
    static func weeklyTime(minutes: Int, days: Int) -> String {
        "That’s \(LeafFormat.duration(minutes: Double(minutes * days))) of reading a week."
    }

    private static func dayName(_ weekday: Int) -> String {
        weekdayNames.indices.contains(weekday - 1) ? weekdayNames[weekday - 1] : "Day"
    }

    // MARK: - Reminder

    /// The daily reminder body (notif.daily) for a book already planned.
    static func reminderBody(minutes: Int, title: String, from: Int, to: Int, hour: Int) -> String {
        "\(minutes) minutes of \(title) \(hour >= 17 ? "tonight" : "today") — about \(LeafFormat.pages(from: from, to: to))."
    }

    /// The daily reminder body before any book is chosen, with the pages estimated from the pace.
    static func reminderBody(minutes: Int, wpm: Double, hour: Int) -> String {
        let pages = max(2, Int((Double(minutes) * wpm / wordsPerPage).rounded()))
        return "\(minutes) minutes of your first book \(hour >= 17 ? "tonight" : "today") — about \(LeafFormat.pages(from: 1, to: pages))."
    }

    // MARK: - Books

    /// How long a stack takes at the chosen schedule: "about 6 weeks", "about 9 days", "about 4 months".
    static func stackSpan(minutes: Double, dailyMinutes: Int, daysPerWeek: Int) -> String? {
        let perWeek = Double(dailyMinutes * daysPerWeek)
        guard perWeek > 0, minutes > 0 else { return nil }
        let weeks = minutes / perWeek
        let days = weeks * 7
        if days < 10.5 {
            let count = max(1, Int(days.rounded()))
            return count == 1 ? "about a day" : "about \(count) days"
        }
        if weeks < 9 { return "about \(Int(weeks.rounded())) weeks" }
        let months = weeks / 4.345
        if months < 23.5 { return "about \(Int(months.rounded())) months" }
        let years = max(1, Int((weeks / 52.18).rounded()))
        return years == 1 ? "about a year" : "about \(years) years"
    }
}
