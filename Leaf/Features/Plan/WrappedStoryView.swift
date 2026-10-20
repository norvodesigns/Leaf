import SwiftUI
import UIKit

/// A request to play the year as a story, from Today or Insights in December, or from the Year in Books any time.
struct WrappedRequest: Identifiable, Hashable {
    var year: Int
    /// The card to open on (screenshots).
    var startCard = 0

    var id: Int { year }
}

// MARK: - The story

/// Reading Wrapped: the year told in six to eight full-screen cards (`WrappedStory`), each over its own scatter of tea
/// rings. Tap the right of the screen or swipe left for the next card, the left or a swipe right to go back, swipe down
/// to close. Cards change with a focus pull (a crossfade under Reduce Motion). Play runs the story by itself with the
/// buttons out of the way, so it can be screen-recorded; a tap pauses it. Share sends every card as an image.
struct WrappedStoryView: View {
    let request: WrappedRequest

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var story: WrappedStory?
    @State private var context: WrappedContext?
    @State private var index = 0
    @State private var isPlaying = false
    @State private var progress: CGFloat = 0
    @State private var images: [UIImage] = []
    @State private var width: CGFloat = 390

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()
            if let story, let context, story.cards.indices.contains(index) {
                if story.isEmpty {
                    emptyYear
                } else {
                    WrappedCardView(card: story.cards[index], story: story, context: context)
                        .id(story.cards[index])
                        .focusPullTransition()
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isSummaryElement)
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: go(by: 1)
                            case .decrement: go(by: -1)
                            @unknown default: break
                            }
                        }
                        .accessibilityAction(named: "Next card") { go(by: 1) }
                        .accessibilityAction(named: "Previous card") { go(by: -1) }
                }
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .top) { chrome }
        .contentShape(.rect)
        .onTapGesture(coordinateSpace: .local) { location in
            tap(at: location)
        }
        .gesture(swipe)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .task { await build() }
        .task(id: playKey) { await playCurrent() }
        .task(id: story?.year) { await renderImages() }
        .statusBarHidden(isPlaying)
        .persistentSystemOverlays(isPlaying ? .hidden : .automatic)
    }

    private var background: Color {
        guard let story, story.cards.indices.contains(index) else { return Color.paper }
        return WrappedStyle.background(story.cards[index])
    }

    // MARK: Building

    private func build() async {
        let data = store.data
        let now = store.now
        let calendar = store.calendar
        let year = request.year
        let built = await Task.detached(priority: .userInitiated) {
            InsightsEngine(data: data, now: now, calendar: calendar).wrappedStory(year: year)
        }.value
        var tints: [String: SpineTint] = [:]
        let shelf = ShelfWall.build(data: data, calendar: calendar).years.first { $0.year == year }
        for spine in shelf?.spines ?? [] {
            tints[spine.book.id] = SpineTints.shared.current(spine.book)
        }
        context = WrappedContext(
            calendar: calendar,
            tea: built.tea.flatMap { TeaShelf.tea(id: $0.teaID, cabinet: data.cabinet) },
            slowBurnBook: built.slowBurn.flatMap { highlight in store.item(highlight.bookID)?.book },
            shelf: shelf,
            tints: tints
        )
        index = max(0, min(request.startCard, built.cards.count - 1))
        withAnimation(Motion.resolved(.smooth(duration: 0.5), reduceMotion: reduceMotion)) {
            story = built
        }
    }

    /// Every card as a 720 × 1280 image for sharing, a card at a time so the story stays responsive.
    private func renderImages() async {
        guard let story, let context, !story.isEmpty else { return }
        var rendered: [UIImage] = []
        for card in story.cards {
            await Task.yield()
            guard !Task.isCancelled else { return }
            let poster = WrappedCardView(card: card, story: story, context: context, isPoster: true)
            if let image = SharePoster.render(poster, size: WrappedCardView.posterSize, scale: 2) {
                rendered.append(image)
            }
        }
        images = rendered
    }

    // MARK: Moving through

    private var playKey: String { "\(index)|\(isPlaying)" }

    private func playCurrent() async {
        guard isPlaying, let story, story.cards.indices.contains(index) else {
            progress = 0
            return
        }
        let duration = WrappedStyle.duration(story.cards[index])
        progress = 0
        withAnimation(.linear(duration: duration)) { progress = 1 }
        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled, isPlaying else { return }
        if index < story.cards.count - 1 {
            go(by: 1, haptic: false)
        } else {
            isPlaying = false
        }
    }

    private func go(by step: Int, haptic: Bool = true) {
        guard let story else { return }
        let next = index + step
        guard story.cards.indices.contains(next) else {
            if step > 0 && !isPlaying { close() }
            return
        }
        if haptic { Haptics.shared.selection() }
        withAnimation(Motion.resolved(.smooth(duration: 0.6), reduceMotion: reduceMotion)) {
            index = next
        }
    }

    private func tap(at location: CGPoint) {
        if isPlaying {
            pause()
            return
        }
        go(by: location.x < width / 3 ? -1 : 1)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if abs(dx) > abs(dy) {
                    if isPlaying { pause() }
                    if dx < -40 { go(by: 1) } else if dx > 40 { go(by: -1) }
                } else if dy > 110 {
                    close()
                }
            }
    }

    private func play() {
        guard let story else { return }
        Haptics.shared.tap()
        if index >= story.cards.count - 1 {
            withAnimation(Motion.resolved(.smooth(duration: 0.6), reduceMotion: reduceMotion)) { index = 0 }
        }
        withAnimation(Motion.fade) { isPlaying = true }
    }

    private func pause() {
        Haptics.shared.tap()
        withAnimation(Motion.fade) { isPlaying = false }
    }

    private func close() {
        isPlaying = false
        dismiss()
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: Space.s) {
            if let story, !story.isEmpty {
                segments(story)
            }
            HStack(spacing: Space.s) {
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: Space.hitTarget, height: Space.hitTarget)
                }
                .accessibilityLabel("Close")
                Spacer()
                if let story, !story.isEmpty {
                    Button {
                        play()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: Space.hitTarget, height: Space.hitTarget)
                    }
                    .accessibilityLabel("Play the story")
                    .accessibilityHint("Moves through the cards by itself. Tap to pause.")
                    if !images.isEmpty {
                        ShareLink(
                            items: images.map { Image(uiImage: $0) },
                            subject: Text("My \(String(request.year)) in books"),
                            preview: { image in SharePreview("My \(String(request.year)) in books", image: image) }
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                                .frame(width: Space.hitTarget, height: Space.hitTarget)
                        }
                        .accessibilityLabel("Share the cards")
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)
            .opacity(isPlaying ? 0 : 1)
            .allowsHitTesting(!isPlaying)
            .accessibilityHidden(isPlaying)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
    }

    private func segments(_ story: WrappedStory) -> some View {
        HStack(spacing: Space.xs) {
            ForEach(story.cards.indices, id: \.self) { position in
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.ink.opacity(0.14))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.ink.opacity(0.75))
                                .frame(width: proxy.size.width * fill(at: position))
                        }
                }
                .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Card \(index + 1) of \(story.cards.count)")
    }

    private func fill(at position: Int) -> CGFloat {
        if position < index { return 1 }
        if position > index { return 0 }
        return isPlaying ? progress : 1
    }

    private var emptyYear: some View {
        VStack(spacing: Space.m) {
            Text("Your \(String(request.year)) story fills in as you read.")
                .leafStyle(.title)
                .multilineTextAlignment(.center)
            Text("A few sittings and a finished book, and there’s a year to tell.")
                .leafStyle(.body, color: .inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.xxl)
    }
}

/// What the cards draw on besides the story: the calendar, the tea and the book in full, and the year's shelf.
struct WrappedContext {
    var calendar: Calendar
    var tea: Tea?
    var slowBurnBook: Book?
    var shelf: ShelfWall.Year?
    var tints: [String: SpineTint]
}

// MARK: - A card

/// One card: an eyebrow in the card's tea colour, one big thing, a line or two in the reader's voice, and tea rings
/// scattered round it. The same view is the share image at 360 × 640 (`isPoster`), with the year and the wordmark.
struct WrappedCardView: View {
    let card: WrappedStory.Card
    let story: WrappedStory
    let context: WrappedContext
    var isPoster = false

    static let posterSize = CGSize(width: 360, height: 640)

    private var summary: YearInBooks { story.summary }
    private var accent: Color { WrappedStyle.accent(card) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            WrappedStyle.background(card)
            TeaRingScatter(seed: "\(story.year)|\(card.rawValue)")
                .opacity(0.85)
            VStack(alignment: .leading, spacing: Space.m) {
                Eyebrow(WrappedText.eyebrow(card, year: story.year), color: accent)
                content
                Spacer(minLength: 0)
                if isPoster {
                    HStack(alignment: .lastTextBaseline) {
                        Text("My \(String(story.year)) in books")
                            .leafStyle(.caption, color: .inkTertiary)
                        Spacer()
                        Text("Leaf").leafStyle(.wordmark)
                    }
                }
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, isPoster ? Space.xxxl : 92)
            .padding(.bottom, isPoster ? Space.xxl : Space.section)
        }
        .frame(width: isPoster ? Self.posterSize.width : nil, height: isPoster ? Self.posterSize.height : nil)
    }

    @ViewBuilder
    private var content: some View {
        switch card {
        case .books: books
        case .tea: tea
        case .hour: hour
        case .streak: streak
        case .slowBurn: slowBurn
        case .quoted: quoted
        case .genre: genre
        case .month: month
        case .fastest: fastest
        case .personality: personality
        case .shelf: shelf
        }
    }

    private func big(_ number: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(number)
                .leafStyle(.heroNumeral)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .leafStyle(.title)
        }
    }

    private func statement(_ text: String) -> some View {
        Text(text)
            .leafStyle(.display)
            .lineLimit(3)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .leafStyle(.pullQuote)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .leafStyle(.body, color: .inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var books: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            big("\(summary.booksFinished)", summary.booksFinished == 1 ? "book" : "books")
            line(WrappedText.booksLine(summary))
            MonthRingCollage(months: summary.months, ringSize: isPoster ? 44 : 54, showsLabels: true)
                .padding(.top, Space.l)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(YearInBooksText.monthsSentence(summary, calendar: context.calendar))
        }
    }

    @ViewBuilder
    private var tea: some View {
        if let pick = story.tea {
            VStack(alignment: .leading, spacing: Space.m) {
                if let tea = context.tea {
                    TeaSwatch(tea: tea, size: 64)
                        .padding(.bottom, Space.xs)
                }
                statement(pick.name)
                line(WrappedText.teaLine(pick))
                detail(WrappedText.teaShare(pick))
            }
        }
    }

    @ViewBuilder
    private var hour: some View {
        if let best = story.hour {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(BestTimeOfDay.hourLabel(best.hour))
                    .leafStyle(.heroNumeral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                line(WrappedText.hourMood(best.hour))
                detail(WrappedText.hourShare(best))
            }
        }
    }

    private var streak: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            big("\(summary.longestStreak)", "days in a row")
            line(WrappedText.streakLine(summary))
        }
    }

    @ViewBuilder
    private var slowBurn: some View {
        if let book = story.slowBurn {
            VStack(alignment: .leading, spacing: Space.m) {
                if let full = context.slowBurnBook {
                    BookCover(book: full, size: .m)
                        .padding(.bottom, Space.s)
                }
                statement(book.title)
                line(WrappedText.slowBurnLine(book))
            }
        }
    }

    @ViewBuilder
    private var quoted: some View {
        if let quote = story.quoted {
            VStack(alignment: .leading, spacing: Space.m) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 30))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(quote.text)
                    .font(.custom(LeafFontName.italic, fixedSize: quote.text.count < 120 ? 26 : 20))
                    .foregroundStyle(Color.ink)
                    .lineLimit(8)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.title).leafStyle(.headline)
                    Text(WrappedText.quotedLine(quote)).leafStyle(.caption)
                }
                .padding(.top, Space.s)
            }
        }
    }

    @ViewBuilder
    private var genre: some View {
        if let top = summary.topGenre {
            VStack(alignment: .leading, spacing: Space.m) {
                statement(top.name)
                line(WrappedText.genreLine(top))
            }
        }
    }

    @ViewBuilder
    private var month: some View {
        if let busiest = summary.busiestMonth, summary.months.indices.contains(busiest - 1) {
            VStack(alignment: .leading, spacing: Space.m) {
                statement(WrappedText.monthName(busiest, year: story.year, calendar: context.calendar))
                line(WrappedText.monthLine(summary.months[busiest - 1]))
            }
        }
    }

    @ViewBuilder
    private var fastest: some View {
        if let book = summary.fastestBook, let perDay = book.pagesPerDay {
            VStack(alignment: .leading, spacing: Space.m) {
                statement(book.title)
                line("About \(Int(perDay.rounded())) pages a day, start to finish.")
            }
        }
    }

    private var personality: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            statement(story.personality.title)
            line(story.personality.blurb)
            if let evidence = story.personality.evidence.first {
                detail(evidence.text)
            }
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            statement(summary.booksFinished == 1 ? "One book on the shelf." : "\(summary.booksFinished) books on the shelf.")
            if let year = context.shelf {
                let rows = ShelfWall.rows(
                    year.spines, width: Double((isPoster ? Self.posterSize.width : 390) - Space.xxl * 2), spacing: Double(ShelfPlankRow<EmptyView>.spacing)
                )
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(Array(rows.prefix(2).enumerated()), id: \.offset) { _, row in
                        ShelfPlankRow(spines: row, shelfHeight: 104, bleed: Space.xxl) { spine in
                            ShelfSpineView(spine: spine, shelfHeight: 104, tint: context.tints[spine.book.id] ?? SpineTint(palette: CoverPalette(book: spine.book)))
                        }
                    }
                }
                .padding(.top, Space.s)
                .accessibilityHidden(true)
            }
            line("Here’s to the next shelf.")
                .padding(.top, Space.s)
        }
    }
}

// MARK: - Tea rings

/// A scatter of tea rings left on the card, mostly low and to the side so they never sit under the words. The same
/// rings every time for the same seed.
struct TeaRingScatter: View {
    let seed: String
    var count = 7

    private struct Ring {
        var x: Double
        var y: Double
        var diameter: Double
        var share: Double
        var opacity: Double
    }

    private var rings: [Ring] {
        var generator = SeededGenerator(seed: SeededGenerator.hash("rings|" + seed))
        var rings: [Ring] = []
        for index in 0..<count {
            // Two near the top corner, the rest along the foot.
            let high = index < 2
            rings.append(Ring(
                x: high ? 0.72 + 0.24 * generator.unit() : 0.04 + 0.92 * generator.unit(),
                y: high ? 0.08 + 0.14 * generator.unit() : 0.68 + 0.3 * generator.unit(),
                diameter: 40 + 80 * generator.unit(),
                share: 0.5 + 0.5 * generator.unit(),
                opacity: 0.45 + 0.45 * generator.unit()
            ))
        }
        return rings
    }

    var body: some View {
        GeometryReader { proxy in
            let all = rings
            ForEach(all.indices, id: \.self) { index in
                TeaRingStamp(mark: .read(all[index].share), seed: index * 13 + 5, diameter: CGFloat(all[index].diameter))
                    .opacity(all[index].opacity)
                    .position(x: proxy.size.width * CGFloat(all[index].x), y: proxy.size.height * CGFloat(all[index].y))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Colours and timing

enum WrappedStyle {
    static func background(_ card: WrappedStory.Card) -> Color {
        switch card {
        case .books, .shelf, .genre: return .paper
        case .tea, .slowBurn: return .teaPaper
        case .hour, .personality: return .paperSunken
        case .streak, .month, .fastest: return .paperRaised
        case .quoted: return .paper
        }
    }

    static func accent(_ card: WrappedStory.Card) -> Color {
        switch card {
        case .books, .shelf: return .accent
        case .tea: return .chai
        case .hour: return .amber
        case .streak, .genre: return .matcha
        case .slowBurn, .fastest: return .rooibos
        case .quoted: return .ribbon
        case .month: return .chai
        case .personality: return .amber
        }
    }

    /// Seconds a card stays up when the story plays itself: long enough to read it twice.
    static func duration(_ card: WrappedStory.Card) -> Double {
        switch card {
        case .quoted, .personality: return 7
        case .shelf: return 6.5
        default: return 5
        }
    }
}

// MARK: - Words

enum WrappedText {
    static func eyebrow(_ card: WrappedStory.Card, year: Int) -> String {
        switch card {
        case .books: return "Your \(String(year)), steeped"
        case .tea: return "The tea you drank most"
        case .hour: return "Your best hour"
        case .streak: return "Your longest streak"
        case .slowBurn: return "The one you took your time over"
        case .quoted: return "Your most-quoted book"
        case .genre: return "What you read most"
        case .month: return "Your busiest month"
        case .fastest: return "The one you couldn’t put down"
        case .personality: return "Your reading personality"
        case .shelf: return "Your \(String(year)) shelf"
        }
    }

    /// "4,210 pages and 98 hours of reading, about 235 cups."
    static func booksLine(_ summary: YearInBooks) -> String {
        let cups = summary.cups == 1 ? "1 cup" : "\(summary.cups) cups"
        return "\(LeafFormat.number(summary.pages)) pages and \(LeafFormat.duration(minutes: summary.minutes)) of reading, about \(cups)."
    }

    static func teaLine(_ tea: WrappedStory.TeaOfTheYear) -> String {
        let sittings = tea.sittings == 1 ? "One sitting" : "\(tea.sittings) sittings"
        return "\(sittings) with it this year, \(LeafFormat.duration(minutes: tea.minutes)) in all."
    }

    static func teaShare(_ tea: WrappedStory.TeaOfTheYear) -> String {
        guard tea.allSittings > 0 else { return "" }
        let percent = Int((Double(tea.teaSittings) / Double(tea.allSittings) * 100).rounded())
        return "A cup of something kept you company in \(percent) percent of your sittings."
    }

    static func hourMood(_ hour: Int) -> String {
        switch hour {
        case 5..<11: return "Before the day got going."
        case 11..<14: return "A chapter in the middle of the day."
        case 14..<18: return "The afternoon, with a pot on."
        case 18..<22: return "Once the day had settled."
        default: return "Long after the house went quiet."
        }
    }

    static func hourShare(_ best: WrappedStory.BestHour) -> String {
        let percent = Int((best.share * 100).rounded())
        let end = BestTimeOfDay.hourLabel((best.hour + 1) % 24)
        return "\(percent) percent of your timed reading began between \(BestTimeOfDay.hourLabel(best.hour)) and \(end)."
    }

    static func streakLine(_ summary: YearInBooks) -> String {
        "You read on \(summary.daysRead) \(summary.daysRead == 1 ? "day" : "days") this year, and never on a schedule you didn’t choose."
    }

    static func slowBurnLine(_ book: YearInBooks.BookHighlight) -> String {
        let days = book.days ?? 0
        return "\(days) days from the first page to the last. Some books are worth taking slowly."
    }

    static func quotedLine(_ quote: WrappedStory.MostQuoted) -> String {
        let count = quote.quotes == 1 ? "1 quote" : "\(quote.quotes) quotes"
        return quote.author.isEmpty ? "\(count) kept this year" : "\(quote.author) · \(count) kept this year"
    }

    static func genreLine(_ genre: YearInBooks.GenreHighlight) -> String {
        let books = genre.books == 1 ? "1 book" : "\(genre.books) books"
        return "\(books), about \(Int((genre.share * 100).rounded())) percent of your year."
    }

    static func monthName(_ month: Int, year: Int, calendar: Calendar) -> String {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return "" }
        return LeafFormat.format(date, template: "MMMM", calendar: calendar)
    }

    static func monthLine(_ month: YearInBooks.MonthRing) -> String {
        let books = month.booksFinished == 0 ? "" : ", and \(month.booksFinished) \(month.booksFinished == 1 ? "book" : "books") finished"
        return "\(LeafFormat.duration(minutes: month.minutes)) of reading\(books)."
    }
}

// MARK: - The offer

/// "Your 2026, steeped": the door to the story, offered on Today and Insights in December and the first week of
/// January. On Today it can be put off for the year.
struct WrappedOfferCard: View {
    let year: Int
    let play: () -> Void
    var notNow: (() -> Void)?

    var body: some View {
        TodayCard("Your \(String(year)), steeped", actionTitle: "Play", action: play) {
            HStack(alignment: .center, spacing: Space.l) {
                ZStack {
                    TeaRingStamp(mark: .read(1), seed: 3, diameter: 40)
                        .offset(x: -8, y: -6)
                    TeaRingStamp(mark: .read(0.7), seed: 11, diameter: 34)
                        .offset(x: 10, y: 8)
                }
                .frame(width: 56, height: 56)
                Text("Your year in books and tea, told a card at a time, to keep or to share.")
                    .leafStyle(.body, color: .inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(.rect)
            .onTapGesture(perform: play)
            if let notNow {
                TextButton("Not now", style: .caption, color: .inkTertiary, action: notNow)
            }
        }
    }
}
