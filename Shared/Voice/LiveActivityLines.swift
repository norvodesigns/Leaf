import Foundation

/// The states a reading Live Activity can be in. The cases match `ReadingActivityState`, so the mapping is one line.
enum LiveActivityMoment: String, CaseIterable, Sendable {
    case reading, paused, goalReached, finishing
}

/// Lines for the Lock Screen and Dynamic Island. The island is tiny, so every line is at most `maxLength` characters
/// (counted as a reader sees them), even with a very long book title. A template that would not fit is skipped.
enum LiveActivityLines {
    static let maxLength = 28

    static let templates: [LiveActivityMoment: [String]] = [
        .reading: [
            "Reading {title}",
            "In {title}",
            "Page by page",
            "A quiet read",
            "Steeped in {title}",
            "Just you and the book",
            "Deep in a good book",
            "{minutes} to today’s goal",
            "Nothing but pages",
        ],
        .paused: [
            "Paused. Take your time.",
            "Resting your eyes",
            "Bookmark in place",
            "Paused with {title}",
            "Back when you’re ready",
            "Your place is saved",
            "A breather",
        ],
        .goalReached: [
            "Goal met",
            "Goal met. Read on?",
            "Today’s pages: done",
            "Anything more is a gift",
            "That’s the goal",
            "Pages done. Stay a while?",
            "Goal met. Lovely.",
        ],
        .finishing: [
            "Last pages of {title}",
            "Nearly done",
            "The final stretch",
            "{pages} to go",
            "The ending is close",
            "So close to the end",
            "Finishing {title}",
        ],
    ]

    /// A line for the activity. Deterministic for a seed (use something that changes only when the state does, such as
    /// the session's start time, so the words do not shuffle while the timer runs). Never longer than `maxLength`.
    static func line(for moment: LiveActivityMoment, bookTitle: String? = nil, minutesToGoal: Int? = nil, pagesLeft: Int? = nil, seed: UInt64) -> String {
        var candidates = (templates[moment] ?? []).map { (template: $0, rank: SeededGenerator.hash("\(seed)|\($0)")) }
        candidates.sort { $0.rank < $1.rank }

        for candidate in candidates {
            if let text = fit(candidate.template, title: bookTitle, minutes: minutesToGoal, pagesLeft: pagesLeft) { return text }
        }
        return fallback(for: moment)
    }

    /// The template filled so it fits, shrinking the title as far as needed; nil if it cannot fit or cannot be filled.
    static func fit(_ template: String, title: String?, minutes: Int?, pagesLeft: Int?) -> String? {
        var limit = 24
        while limit >= 8 {
            let values = VoiceValues(title: title, pagesLeft: pagesLeft, minutes: minutes, spellsNumbers: false, maxTitleCharacters: limit)
            guard let text = VoiceTemplate.fill(template, with: values) else { return nil }
            if text.count <= maxLength { return text }
            limit -= 2
        }
        return nil
    }

    /// Plain lines with nothing to fill, for when a template cannot be.
    static func fallback(for moment: LiveActivityMoment) -> String {
        switch moment {
        case .reading: return "Page by page"
        case .paused: return "Paused. Take your time."
        case .goalReached: return "Goal met"
        case .finishing: return "Nearly done"
        }
    }
}

/// Short lines for the wrist. Twenty characters is a glance, so these are single phrases.
enum WatchLines {
    static let maxLength = 20

    enum Moment: String, CaseIterable, Sendable {
        case reading, paused, goalReached, bookFinished, steepReady, restDay, almostThere
    }

    static let stateTemplates: [Moment: [String]] = [
        .reading: ["Page by page.", "Reading.", "Quiet, please.", "In the story."],
        .paused: ["Paused.", "Take your time.", "Resting.", "Back soon?"],
        .goalReached: ["Goal met.", "Today’s done.", "All read today.", "Nicely read."],
        .bookFinished: ["Book finished.", "The last page.", "Well read.", "Finished."],
        .steepReady: ["Tea’s ready.", "Steeped.", "Pour and read.", "Cup’s ready."],
        .restDay: ["Day off.", "Rest day.", "The book will keep.", "Easy day."],
        .almostThere: ["Almost there.", "So close.", "The last stretch.", "Nearly done."],
    ]

    static let greetings: [Daypart: [String]] = [
        .dawn: ["Early bird.", "Quiet house.", "First light.", "Up early."],
        .morning: ["Good morning.", "Morning, reader.", "A fresh page?", "Morning pages."],
        .lunch: ["Lunch with a page?", "Midday pause.", "A page at noon?", "Lunch break."],
        .afternoon: ["Afternoon page?", "Slow afternoon.", "A little escape?", "Afternoon."],
        .teaTime: ["Tea o’clock.", "Kettle on?", "Teatime.", "Pour a cup."],
        .dusk: ["The lamp’s calling.", "Golden hour.", "Dusk.", "Lights coming on."],
        .evening: ["Good evening.", "Kettle on?", "Lamp on?", "Evening, reader."],
        .late: ["Still up?", "One more page?", "Late chapter?", "Still awake?"],
        .smallHours: ["Night owl.", "Small hours.", "Can’t sleep?", "Quiet night."],
    ]

    /// The watch's Today line for this moment. The big states win (goal met, rest day, a book nearly done); otherwise it
    /// is the hour's greeting. `previousLine` keeps it from repeating.
    static func greeting(for context: GreetingContext, seed: UInt64, previousLine: String? = nil) -> String {
        let moment: Moment?
        if context.goalState == .met {
            moment = .goalReached
        } else if context.isRestDay {
            moment = .restDay
        } else if case .nearFinish = context.bookState {
            moment = .almostThere
        } else if context.bookState == .finishedToday {
            moment = .bookFinished
        } else {
            moment = nil
        }
        if let moment { return line(for: moment, seed: seed, previousLine: previousLine) }

        let pool = greetings[context.daypart] ?? []
        var options = pool.filter { $0.count <= maxLength }
        if let previousLine, options.count > 1 { options.removeAll { $0 == previousLine } }
        return VoiceText.choose(options, seed: seed, salt: "watch|\(context.daypart.rawValue)") ?? "Hello, reader."
    }

    /// A line for a state of the watch app.
    static func line(for moment: Moment, seed: UInt64, previousLine: String? = nil) -> String {
        var options = (stateTemplates[moment] ?? []).filter { $0.count <= maxLength }
        if let previousLine, options.count > 1 { options.removeAll { $0 == previousLine } }
        return VoiceText.choose(options, seed: seed, salt: "watch|\(moment.rawValue)") ?? "Hello."
    }
}
