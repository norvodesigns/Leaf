import Foundation

/// What happened in the session that just ended.
struct SessionWrapUpInput: Equatable, Sendable {
    var pagesRead: Int
    var minutes: Double
    /// Today's goal was crossed during this session.
    var goalMetNow: Bool
    var bookFinished: Bool
    /// The longest sitting, or the most pages in one go, this reader has had.
    var isPersonalBest: Bool
    var bookTitle: String?

    init(pagesRead: Int, minutes: Double, goalMetNow: Bool = false, bookFinished: Bool = false, isPersonalBest: Bool = false, bookTitle: String? = nil) {
        self.pagesRead = pagesRead
        self.minutes = minutes
        self.goalMetNow = goalMetNow
        self.bookFinished = bookFinished
        self.isPersonalBest = isPersonalBest
        self.bookTitle = bookTitle
    }
}

struct SessionWrapUpLine: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case bookFinished, personalBest, goalMet, quiet, longSitting, quick, regular
    }

    var kind: Kind
    /// The warm line: "Goal met. Anything more is a gift."
    var headline: String
    /// The real numbers beside it, always: "12 pages in 25 min".
    var detail: String
    var id: String
}

/// End-of-session copy. The warm line changes with what happened; the numbers are always there beside it (NEXT.md
/// section 10: always show real numbers beside any cute unit).
enum SessionWrapUp {
    /// A sitting this long gets the "long, lovely" lines.
    static let longSittingMinutes = 45.0
    /// A sitting shorter than this (or a single page) is "short and sweet".
    static let quickMinutes = 5.0

    static let templates: [Kind: [String]] = [
        .bookFinished: [
            "{title}, finished.",
            "That’s {title} done.",
            "The last page, turned.",
            "Book finished. Well read.",
            "One more book on the shelf.",
            "The ending landed.",
            "Finished. Sit with it a moment.",
        ],
        .personalBest: [
            "Your longest sitting yet.",
            "A personal best.",
            "That was a big one.",
            "A new best. Quietly impressive.",
            "Best session so far. Well done.",
            "A new high, and a lovely one.",
        ],
        .goalMet: [
            "Goal met. Anything more is a gift.",
            "Today’s reading is done.",
            "That’s today’s goal, done.",
            "Goal reached. The rest is bonus.",
            "Done for today. Nicely read.",
            "Goal met. The tea is earned.",
        ],
        .quiet: [
            "A few quiet minutes. They count.",
            "Time with the book is time well spent.",
            "Quiet minutes with the book. Lovely.",
            "Sitting with a book counts.",
            "No pages turned, and that is fine.",
        ],
        .longSitting: [
            "A long, lovely sitting.",
            "That was a proper read.",
            "You really settled in.",
            "Time well spent.",
            "A deep, quiet stretch.",
            "A good long read.",
        ],
        .quick: [
            "Short and sweet.",
            "A few pages count.",
            "Every page counts.",
            "A quick visit. It still counts.",
            "Little and often works.",
        ],
        .regular: [
            "Nicely read.",
            "A good sitting.",
            "That’s a good session.",
            "Well read.",
            "Another chapter in the day.",
            "Pages turned, mind quieter.",
            "Good reading.",
            "That was a good one.",
        ],
    ]

    typealias Kind = SessionWrapUpLine.Kind

    /// Which kind of wrap-up fits: finishing a book beats a personal best, which beats a goal, and so on.
    static func kind(for input: SessionWrapUpInput) -> Kind {
        if input.bookFinished { return .bookFinished }
        if input.isPersonalBest { return .personalBest }
        if input.goalMetNow { return .goalMet }
        if input.pagesRead <= 0 { return .quiet }
        if input.minutes >= longSittingMinutes { return .longSitting }
        if input.minutes < quickMinutes || input.pagesRead == 1 { return .quick }
        return .regular
    }

    /// "12 pages in 25 min", "1 page", "25 min with the book", "A moment with the book".
    static func detail(pages: Int, minutes: Double) -> String {
        let pages = max(0, pages)
        let minutes = minutes.isFinite ? max(0, minutes) : 0
        let hasTime = minutes >= 0.5
        let pageText = "\(pages) \(pages == 1 ? "page" : "pages")"
        switch (pages > 0, hasTime) {
        case (true, true): return "\(pageText) in \(LeafFormat.duration(minutes: minutes))"
        case (true, false): return pageText
        case (false, true): return "\(LeafFormat.duration(minutes: minutes)) with the book"
        case (false, false): return "A moment with the book"
        }
    }

    /// The wrap-up for one session. Deterministic for a seed; never the same line as `previousID`.
    static func line(for input: SessionWrapUpInput, seed: UInt64, previousID: String? = nil) -> SessionWrapUpLine {
        let kind = self.kind(for: input)
        let values = VoiceValues(title: input.bookTitle, maxTitleCharacters: 32)
        let available = values.available

        var options = (templates[kind] ?? []).compactMap { template -> (id: String, text: String)? in
            guard VoiceTemplate.placeholders(in: template).isSubset(of: available),
                  let text = VoiceTemplate.fill(template, with: values) else { return nil }
            return (VoiceText.stableID("wrapup." + kind.rawValue, template), text)
        }
        if let previousID, options.count > 1 { options.removeAll { $0.id == previousID } }

        let pick = VoiceText.choose(options, seed: seed, salt: "wrapup|\(kind.rawValue)")
        var detail = self.detail(pages: input.pagesRead, minutes: input.minutes)
        // A finished book or a best should not hide that the goal was met too.
        if input.goalMetNow, kind == .bookFinished || kind == .personalBest { detail += ". Today’s goal is done, too." }

        return SessionWrapUpLine(kind: kind, headline: pick?.text ?? "Nicely read.", detail: detail, id: pick?.id ?? "wrapup.fallback")
    }
}
