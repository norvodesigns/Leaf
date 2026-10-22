import Foundation
import Observation

/// One line of the conversation with the librarian.
struct LibrarianEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        /// The librarian, as written text.
        case says(String)
        /// The reader's answer, echoed as their side of the conversation.
        case reader(String)
        /// A shelf of picks. `title` heads a "More like X" shelf; the first answer has none.
        case picks(title: String?, [LibrarianPick])
    }

    let id: Int
    let kind: Kind
}

/// The conversation: which question is open, what the reader answered, and what the librarian found. All the
/// finding is `Librarian` (Shared), run off the main thread because the browse pool can be large.
@MainActor
@Observable
final class LibrarianModel {
    enum Step: Hashable {
        case mood, time, length, thinking, answered
    }

    private(set) var entries: [LibrarianEntry] = []
    private(set) var step: Step = .mood
    private(set) var ask = LibrarianAsk()
    /// Every book that fit the last answer, for "Swipe through more".
    private(set) var matches: [Book] = []
    /// Whether the librarian is "writing" (the three dots before a reply).
    private(set) var isWriting = false

    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var round = 0
    @ObservationIgnored private var shown = Set<String>()
    @ObservationIgnored private var seed: UInt64 = 0
    @ObservationIgnored private var source: (@MainActor () -> (pool: [Book], stats: CatalogStats, context: RecommendationContext))?
    @ObservationIgnored private var similar: (@MainActor (Book) async -> [Recommendation])?
    /// Reduce Motion: replies land at once, with no writing pause.
    @ObservationIgnored var replyPause: Duration = .milliseconds(650)

    /// Starts the conversation. `source` is read fresh for every answer, so books added meanwhile are left out.
    func start(
        seed: UInt64,
        source: @escaping @MainActor () -> (pool: [Book], stats: CatalogStats, context: RecommendationContext),
        similar: @escaping @MainActor (Book) async -> [Recommendation]
    ) {
        guard entries.isEmpty else { return }
        self.seed = seed
        self.source = source
        self.similar = similar
        append(.says(LibrarianLines.pick(LibrarianLines.openers, seed: seed)))
    }

    // MARK: Answering the questions

    /// `nil` is "Surprise me".
    func chooseMood(_ mood: LibrarianMood?) {
        guard step == .mood else { return }
        ask.moodID = mood?.id
        append(.reader(mood?.label ?? "Surprise me"))
        step = .time
        reply(LibrarianLines.pick(LibrarianLines.askTime, seed: seed &+ 1))
    }

    /// `nil` is "Any time".
    func chooseTime(_ time: LibrarianAsk.Time?) {
        guard step == .time else { return }
        ask.time = time
        append(.reader(time?.label ?? "No rush"))
        if time?.settlesLength == true {
            step = .thinking
            Task { await findPicks(lead: LibrarianLines.pick(LibrarianLines.skipLength, seed: seed)) }
        } else {
            step = .length
            reply(LibrarianLines.pick(LibrarianLines.askLength, seed: seed &+ 2))
        }
    }

    func chooseLength(_ length: LibrarianAsk.Length) {
        guard step == .length else { return }
        ask.length = length == .any ? nil : length
        append(.reader(length == .any ? length.label : "\(length.label), \(length.detail)"))
        step = .thinking
        Task { await findPicks(lead: nil) }
    }

    // MARK: After the answer

    /// "Show me others": the same ask, books not shown yet.
    func again() {
        guard step == .answered else { return }
        append(.reader("Show me others"))
        step = .thinking
        Task { await findPicks(lead: nil) }
    }

    /// "More like this" for one pick: a short shelf of its neighbours.
    func moreLike(_ book: Book) {
        guard step == .answered, let similar else { return }
        append(.reader("More like \(book.title)"))
        step = .thinking
        Task {
            let found = await similar(book)
            await pause()
            let recs = found.filter { !shown.contains($0.book.id) }.prefix(8)
            let wpm = source?().context.wpm ?? ReadingSpeed.typicalAdultWPM
            let picks = recs.map { rec in
                LibrarianPick(
                    book: rec.book, reason: rec.reason,
                    why: rec.reason.text,
                    fit: "About \(LeafFormat.duration(minutes: rec.book.minutes(atWPM: wpm))) at your pace",
                    finishLikelihood: rec.finishLikelihood
                )
            }
            shown.formUnion(picks.map(\.id))
            isWriting = false
            if picks.isEmpty {
                append(.says(LibrarianLines.nothing))
            } else {
                append(.says(LibrarianLines.moreLike(book.title)))
                append(.picks(title: "More like \(book.title)", Array(picks)))
            }
            step = .answered
        }
    }

    /// Back to the first question, keeping the conversation so far on screen.
    func startOver() {
        ask = LibrarianAsk()
        round = 0
        append(.reader("Start over"))
        step = .mood
        reply(LibrarianLines.pick(LibrarianLines.openers, seed: seed &+ UInt64(entries.count)))
    }

    // MARK: Finding

    private func findPicks(lead: String?) async {
        guard let source else { return }
        let input = source()
        let ask = ask
        let shown = shown
        let seed = seed &+ UInt64(round) &* 0x9E37_79B9 &+ SeededGenerator.hash(ask.moodID ?? "surprise")
        let finding = Task.detached(priority: .userInitiated) {
            Librarian(pool: input.pool, stats: input.stats, context: input.context)
                .answer(ask, limit: 8, seed: seed, excluding: shown)
        }
        await pause()
        let answer = await finding.value
        isWriting = false
        // "Then we'll keep it slim" only when nothing had to be loosened; otherwise the reply says what changed.
        if let lead, answer.loosened.isEmpty, !answer.picks.isEmpty {
            append(.says(lead))
        } else {
            append(.says(LibrarianLines.reply(for: answer, round: round, seed: seed)))
        }
        if !answer.picks.isEmpty {
            append(.picks(title: nil, answer.picks))
        }
        self.shown.formUnion(answer.picks.map(\.id))
        matches = answer.matches
        round += 1
        step = .answered
    }

    // MARK: Plumbing

    private func reply(_ text: String) {
        Task {
            await pause()
            isWriting = false
            append(.says(text))
        }
    }

    private func pause() async {
        guard replyPause > .zero else { return }
        isWriting = true
        try? await Task.sleep(for: replyPause)
    }

    private func append(_ kind: LibrarianEntry.Kind) {
        entries.append(LibrarianEntry(id: nextID, kind: kind))
        nextID += 1
    }
}
