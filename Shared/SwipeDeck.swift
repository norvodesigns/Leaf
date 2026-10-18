import Foundation

/// A stack of covers to swipe through: keep it for later, pass, or start it now. It is the fastest way to build a
/// To read list, and it learns as it goes: every swipe updates the reader's taste, and the cards still waiting are
/// re-picked every few swipes so the deck follows what they just said.
///
/// The deck is a value type with no UI in it; the screen shows `peek(_:)`, and commits `keeps`, `starts` and
/// `passes` to the library when the reader is done (or as they swipe).
struct SwipeDeck {
    enum Choice: String, Codable, Sendable {
        /// Add to To read.
        case keep
        /// Not for me.
        case pass
        /// Add to Reading now.
        case startNow
    }

    struct Card: Identifiable, Hashable, Sendable {
        var book: Book
        /// Why this card is here ("Because you finished X", "Something a little different").
        var reason: RecommendationReason
        /// 0 to 1: how likely this reader is to finish a book of this kind at their pace.
        var finishLikelihood: Double

        var id: String { book.id }
    }

    /// A swipe that has been recorded, newest last.
    struct Swipe: Hashable, Sendable {
        var book: Book
        var choice: Choice
    }

    private let stats: CatalogStats
    private let pool: [Book]
    private var context: RecommendationContext
    private let seed: UInt64
    private let batchSize: Int
    /// How many swipes between re-picking the waiting cards.
    private let refreshEvery: Int

    private var queue: [Card] = []
    private var served = Set<String>()
    private var refills = 0
    private var swipesSinceRefill = 0
    private(set) var swipes: [Swipe] = []

    /// - Parameters:
    ///   - pool: the books to draw from (the catalog's browse pool).
    ///   - context: what the recommender knows about this reader right now.
    ///   - seed: use the day's seed so reopening the deck shows the same start.
    init(pool: [Book], stats: CatalogStats, context: RecommendationContext, seed: UInt64, batchSize: Int = 16, refreshEvery: Int = 4) {
        self.pool = pool
        self.stats = stats
        self.context = context
        self.seed = seed
        self.batchSize = max(4, batchSize)
        self.refreshEvery = max(1, refreshEvery)
        refill()
    }

    // MARK: Reading the deck

    /// The next cards, top first, without consuming them (for drawing the visible stack).
    mutating func peek(_ count: Int) -> [Card] {
        if queue.count < count { refill() }
        return Array(queue.prefix(count))
    }

    var top: Card? { queue.first }

    /// Cards still queued. The deck refills itself, so this only reaches zero when the pool is used up.
    var queuedCount: Int { queue.count }

    var keeps: [Book] { swipes.filter { $0.choice == .keep }.map(\.book) }
    var starts: [Book] { swipes.filter { $0.choice == .startNow }.map(\.book) }
    var passes: [Book] { swipes.filter { $0.choice == .pass }.map(\.book) }

    // MARK: Swiping

    /// Records a swipe on the top card and removes it. Returns the card that was swiped, or nil if the deck is empty.
    @discardableResult
    mutating func swipe(_ choice: Choice) -> Card? {
        if queue.isEmpty { refill() }
        guard !queue.isEmpty else { return nil }
        let card = queue.removeFirst()
        record(choice, for: card.book)
        swipesSinceRefill += 1
        if swipesSinceRefill >= refreshEvery || queue.count < 3 { refill() }
        return card
    }

    /// Takes back the last swipe and puts that card back on top.
    @discardableResult
    mutating func undo() -> Card? {
        guard let last = swipes.popLast() else { return nil }
        context.library.removeAll { $0.id == last.book.id }
        context.dismissed.removeAll { $0.id == last.book.id }
        let card = Card(book: last.book, reason: .popular, finishLikelihood: Recommender(stats: stats, context: context).finishLikelihood(for: last.book, content: 0.5))
        queue.insert(card, at: 0)
        return card
    }

    // MARK: Learning

    private mutating func record(_ choice: Choice, for book: Book) {
        swipes.append(Swipe(book: book, choice: choice))
        switch choice {
        case .keep:
            context.library.append(LibraryItem(book: book, shelf: .toRead, order: Double(context.library.count), addedAt: context.now))
        case .startNow:
            context.library.append(LibraryItem(book: book, shelf: .reading, order: Double(context.library.count), addedAt: context.now, startedAt: context.now))
        case .pass:
            context.dismissed.append(book)
        }
    }

    /// Re-picks the waiting cards from the current taste. Cards already shown are never repeated.
    private mutating func refill() {
        swipesSinceRefill = 0
        refills += 1
        let recommender = Recommender(stats: stats, context: context)
        // The first picks for a reader we know nothing about should probe widely; once there is taste, stay closer.
        let diversity = recommender.profile.isCold ? 0.9 : 0.65
        let candidates = pool.filter { !served.contains($0.id) }
        let picks = recommender.recommend(
            from: candidates, limit: batchSize, seed: seed &+ UInt64(refills) &* 0x9E37_79B9,
            diversity: diversity, exploration: 0.2, maxPerAuthor: 1
        )
        queue = picks.map { Card(book: $0.book, reason: $0.reason, finishLikelihood: $0.finishLikelihood) }
        for card in queue { served.insert(card.book.id) }
    }
}
