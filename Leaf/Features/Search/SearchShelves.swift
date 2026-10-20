import SwiftUI

// The Search tab's browsing (NEXT.md section 17.6): up to 140 rows from `BookCatalog.collections(context:)`, given
// different shapes so the shop feels like a shop rather than one long list of covers. A hero table for "Picked for
// you", spines on a shelf for series, a portrait header for authors, the reading time on each cover for time budgets,
// a tinted panel for the season, and a plain carousel for everything else. Every personal pick says why it is there.

// MARK: - Kinds

/// How a row is drawn and which jump-bar chip it belongs to, read from the row's id (the catalog's own naming).
struct SearchShelfKind: Equatable {
    enum Style: Equatable { case hero, standard, series, author, time, seasonal }

    enum Category: String, CaseIterable, Identifiable {
        case forYou = "For you"
        case season = "This season"
        case moods = "Moods"
        case genres = "Genres"
        case themes = "Themes"
        case series = "Series"
        case authors = "Authors"
        case short = "Short reads"
        case decades = "Decades"
        case gems = "Hidden gems"

        var id: String { rawValue }
    }

    let style: Style
    let category: Category

    init(_ collection: BookCollection) {
        let kind = Self.classify(collection)
        style = kind.style
        category = kind.category
    }

    private static func classify(_ collection: BookCollection) -> (style: Style, category: Category) {
        let id = collection.id
        if id == "for-you" { return (.hero, .forYou) }
        if id.hasPrefix("continue-") { return (.series, .forYou) }
        if id.hasPrefix("author-fav-") { return (.author, .forYou) }
        if id == "your-length" { return (.time, .forYou) }
        if collection.kind == .personal { return (.standard, .forYou) }
        if collection.kind == .context || id == "spooky" { return (.seasonal, .season) }
        if id.hasPrefix("series-") { return (.series, .series) }
        if id.hasPrefix("author-") { return (.author, .authors) }
        if id.hasPrefix("time-") || id.hasPrefix("quick-") { return (.time, .short) }
        if id.hasPrefix("big-") { return (.time, .genres) }
        if id.hasPrefix("genre-") { return (.standard, .genres) }
        if id.hasPrefix("theme-") { return (.standard, .themes) }
        if id.hasPrefix("decade-") { return (.standard, .decades) }
        if id.hasPrefix("gems") { return (.standard, .gems) }
        return (.standard, .moods)
    }
}

/// "More like this" for a book, pushed on the Search tab.
struct SimilarRoute: Hashable {
    let book: Book
}

/// The "Your taste" page, pushed on the Search tab.
struct TasteRoute: Hashable {}

// MARK: - Rows

/// One browsing row in the shape its kind asks for, with a header that opens the whole row.
struct SearchShelfRow: View {
    let collection: BookCollection
    let kind: SearchShelfKind
    let isFirst: Bool
    let wpm: Double
    let shelfOf: (String) -> Shelf?
    let onAdd: (Book, Shelf, Bool) -> Void
    let onDismiss: (Book) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            switch kind.style {
            case .hero:
                carousel(size: .l, showsReason: true)
            case .series:
                SpineShelf(books: collection.books, reasons: collection.reasons, shelfOf: shelfOf, onAdd: onAdd, onDismiss: onDismiss)
            case .author:
                carousel(size: .m, showsReason: false)
            case .time:
                carousel(size: .m, showsReason: false, showsTime: true)
            case .seasonal:
                carousel(size: .m, showsReason: !collection.reasons.isEmpty)
                    .padding(.vertical, Space.m)
                    .background {
                        Radius.shape(Radius.card)
                            .fill(Self.seasonTint(collection).opacity(0.14))
                            .padding(.horizontal, -Space.s)
                    }
            case .standard:
                carousel(size: .m, showsReason: !collection.reasons.isEmpty)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(collection.title)
    }

    @ViewBuilder
    private var header: some View {
        if kind.style == .author {
            AuthorShelfHeader(collection: collection, topSpacing: isFirst ? 0 : Space.xxxl + Space.m)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(collection.title)
                        .leafStyle(.eyebrow)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Space.s)
                    NavigationLink(value: collection) {
                        Text("See all")
                            .leafStyle(.caption, color: .accent)
                            .frame(minHeight: Space.hitTarget)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("See all of \(collection.title)")
                }
                Hairline()
                    .padding(.bottom, Space.s)
            }
            .padding(.top, isFirst ? 0 : Space.xxxl)
            Text(collection.subtitle)
                .leafStyle(.caption)
                .padding(.bottom, Space.m)
        }
    }

    private func carousel(size: BookCover.Size, showsReason: Bool, showsTime: Bool = false) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: size == .l ? Space.l : Space.m) {
                ForEach(collection.books) { book in
                    SearchCarouselCover(
                        book: book,
                        shelf: shelfOf(book.id),
                        reason: collection.reasons[book.id],
                        size: size,
                        badge: showsTime ? LeafFormat.compactDuration(minutes: book.minutes(atWPM: wpm)) : nil,
                        showsReason: showsReason,
                        onAdd: { shelf, front in onAdd(book, shelf, front) },
                        onDismiss: { onDismiss(book) }
                    )
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, Space.l)
        }
        .contentMargins(.horizontal, Space.margin, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollTargetBehavior(.viewAligned)
        .padding(.horizontal, -Space.margin)
    }

    /// Autumn rows in rooibos, winter in steam, spring in matcha, summer in amber.
    static func seasonTint(_ collection: BookCollection) -> Color {
        let id = collection.id
        if id.contains("spooky") || id.contains("autumn") || id.contains("crisp") { return .rooibos }
        if id.contains("winter") || id.contains("hearth") || id.contains("snow") { return .steam }
        if id.contains("spring") || id.contains("rain") { return .matcha }
        if id.contains("summer") || id.contains("porch") { return .amber }
        return .chai
    }
}

/// An author row's header: a monogram like a bookplate, the name, the count, and "See all".
struct AuthorShelfHeader: View {
    let collection: BookCollection
    let topSpacing: CGFloat

    private var author: String { collection.books.first?.author ?? collection.title }

    private var initials: String {
        let words = author.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return String(letters).uppercased()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Text(initials)
                .font(LeafType.title)
                .foregroundStyle(Color.ink)
                .frame(width: 52, height: 52)
                .background(Color.teaPaper, in: Circle())
                .overlay { Circle().strokeBorder(Color.hairlineStrong, lineWidth: 1) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .leafStyle(.title)
                    .lineLimit(2)
                Text(collection.subtitle)
                    .leafStyle(.caption)
            }
            Spacer(minLength: Space.s)
            NavigationLink(value: collection) {
                Text("See all")
                    .leafStyle(.caption, color: .accent)
                    .frame(minHeight: Space.hitTarget)
            }
            .accessibilityLabel("See all books by \(author)")
        }
        .padding(.top, topSpacing)
        .padding(.bottom, Space.m)
        .accessibilityElement(children: .contain)
    }
}

/// A series as spines on a shelf: each book a spine in its cover colours, as tall as the book is long, with its title
/// running up the spine. Tap a spine to open the book.
struct SpineShelf: View {
    let books: [Book]
    let reasons: [String: String]
    let shelfOf: (String) -> Shelf?
    let onAdd: (Book, Shelf, Bool) -> Void
    let onDismiss: (Book) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var tallest: CGFloat { typeSize.isAccessibilitySize ? 240 : 190 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: 3) {
                    ForEach(books) { book in
                        NavigationLink(value: BookRoute(book: book)) {
                            spine(book)
                        }
                        .buttonStyle(.pressable)
                        .contextMenu {
                            if let reason = reasons[book.id] { Section(reason) { actions(book) } } else { actions(book) }
                        }
                        .accessibilityLabel("\(book.title), by \(book.author)\(reasons[book.id].map { ". \($0)" } ?? "")")
                        .accessibilityHint("Opens the book")
                    }
                }
                .padding(.bottom, 2)
            }
            .contentMargins(.horizontal, Space.margin, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .padding(.horizontal, -Space.margin)
            // The shelf board.
            Rectangle()
                .fill(Color.chai.opacity(0.45))
                .frame(height: 5)
                .padding(.horizontal, -Space.margin)
            Rectangle()
                .fill(Color.coverShadow.opacity(0.12))
                .frame(height: 6)
                .blur(radius: 3)
                .padding(.horizontal, -Space.margin)
                .padding(.bottom, Space.l)
                .accessibilityHidden(true)
        }
    }

    private func spine(_ book: Book) -> some View {
        let palette = CoverPalette(book: book)
        let height = tallest * CGFloat(0.72 + 0.28 * min(1, Double(book.pages) / 600))
        let width: CGFloat = typeSize.isAccessibilitySize ? 52 : 40 + CGFloat(min(14, book.pages / 60))
        return ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(palette.background)
            VStack(spacing: 0) {
                Rectangle().fill(palette.rule.opacity(0.6)).frame(height: 1).padding(.top, 10)
                Spacer(minLength: 0)
                Rectangle().fill(palette.rule.opacity(0.6)).frame(height: 1).padding(.bottom, 10)
            }
            .padding(.horizontal, 5)
            Text(book.title)
                .font(.system(size: typeSize.isAccessibilitySize ? 15 : 12, weight: .semibold, design: .serif))
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: height - 28)
                .rotationEffect(.degrees(-90))
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .overlay(alignment: .top) {
            if shelfOf(book.id) != nil {
                Circle().fill(Color.ribbon).frame(width: 6, height: 6).padding(.top, 4)
            }
        }
        .shadow(color: Color.coverShadow.opacity(0.18), radius: 1.5, x: 1, y: 1)
    }

    @ViewBuilder
    private func actions(_ book: Book) -> some View {
        SearchAddActions(shelf: shelfOf(book.id)) { shelf, front in onAdd(book, shelf, front) }
        if shelfOf(book.id) == nil {
            Button(role: .destructive) { onDismiss(book) } label: {
                Label("Not for me", systemImage: "hand.thumbsdown")
            }
        }
    }
}

// MARK: - Jump bar

/// A pinned strip of chips, one per kind of row, that scrolls the shop to the first row of that kind.
struct SearchJumpBar: View {
    let categories: [SearchShelfKind.Category]
    let onJump: (SearchShelfKind.Category) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.s) {
                ForEach(categories) { category in
                    Button {
                        Haptics.shared.selection()
                        onJump(category)
                    } label: {
                        Text(category.rawValue)
                            .leafStyle(.ui)
                            .padding(.horizontal, Space.m)
                            .padding(.vertical, Space.s)
                            .background(Color.paperRaised, in: .capsule)
                            .overlay { Capsule().strokeBorder(Color.hairline, lineWidth: 1) }
                            .frame(minHeight: Space.hitTarget)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Scrolls to \(category.rawValue.lowercased())")
                }
            }
        }
        .contentMargins(.horizontal, Space.margin, for: .scrollContent)
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Space.margin)
        .padding(.vertical, Space.xs)
        .background(Color.paper.padding(.horizontal, -Space.margin))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Jump to")
    }
}

// MARK: - Front table and credit

/// The first screen for a reader with no history: a shop's front table, and a word on how it learns.
struct SearchFrontTableNote: View {
    let onYourTaste: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("The front table.")
                .leafStyle(.masthead)
            Text("These are the books readers love most, from every corner of the shop. Finish a book and these rows start to learn your taste.")
                .leafStyle(.body, color: .inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextButton("How Leaf picks", style: .caption) {
                Haptics.shared.tap()
                onYourTaste()
            }
        }
        .padding(.bottom, Space.xl)
    }
}

/// "Book data from Open Library, a project of the Internet Archive."
struct OpenLibraryCredit: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Hairline()
            Text("Book data from Open Library, a project of the Internet Archive.")
                .leafStyle(.caption, color: .inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)
            if let url = URL(string: "https://openlibrary.org") {
                Link("openlibrary.org", destination: url)
                    .font(LeafType.caption)
                    .foregroundStyle(Color.accent)
                    .frame(minHeight: Space.hitTarget, alignment: .leading)
            }
        }
        .padding(.top, Space.xxl)
    }
}

// MARK: - Undo

/// "Not for me" can be taken back for a few seconds.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Text(message)
                .leafStyle(.uiBody)
                .lineLimit(2)
            Spacer(minLength: Space.s)
            Button("Undo") {
                Haptics.shared.tap()
                onUndo()
            }
            .font(LeafType.ui.weight(.semibold))
            .foregroundStyle(Color.accent)
            .frame(minHeight: Space.hitTarget)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.xs)
        .glassEffect(.regular.tint(.glassTint), in: .capsule)
        .padding(.horizontal, Space.margin)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", onUndo)
    }
}

// MARK: - See all

/// A whole row as a grid, with each personal pick's reason under its cover.
struct CollectionGridView: View {
    let collection: BookCollection

    @Environment(LibraryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 100), spacing: Space.m, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text(collection.subtitle)
                    .leafStyle(.body, color: .inkSecondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: Space.xl) {
                    ForEach(collection.books) { book in
                        NavigationLink(value: BookRoute(book: book)) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                BookCover(book: book, size: .m)
                                Text(book.title)
                                    .leafStyle(.caption, color: .ink)
                                    .lineLimit(2)
                                Text(collection.reasons[book.id] ?? LeafFormat.compactDuration(minutes: book.minutes(atWPM: store.wpm)))
                                    .leafStyle(.caption, color: .inkTertiary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(book.title), by \(book.author). \(collection.reasons[book.id] ?? "About \(LeafFormat.duration(minutes: book.minutes(atWPM: store.wpm))) at your pace").")
                    }
                }
            }
            .leafMargins()
            .padding(.vertical, Space.l)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - More like this

/// Books that share this one's genres, themes or world, each with the reason it was picked.
struct SimilarBooksView: View {
    let book: Book

    @Environment(LibraryStore.self) private var store
    @Environment(BookCatalog.self) private var catalog
    @State private var picks: [Recommendation]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: Space.m) {
                    BookCover(book: book, size: .s)
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow("More like")
                        Text(book.title).leafStyle(.headline)
                        Text(book.author).leafStyle(.author)
                    }
                }
                .padding(.bottom, Space.l)
                if let picks {
                    if picks.isEmpty {
                        Text("Nothing close enough yet. The catalog only suggests books that really share something with this one.")
                            .leafStyle(.body, color: .inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(picks) { pick in
                            VStack(spacing: 0) {
                                SearchResultRow(
                                    book: pick.book,
                                    wpm: store.wpm,
                                    shelf: store.shelf(of: pick.book.id),
                                    onAdd: { shelf, front in add(pick.book, to: shelf, atFront: front) }
                                )
                                if store.similarReason(for: book) != nil {
                                    Text(pick.reason.text)
                                        .leafStyle(.caption, color: .inkTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, BookCover.Size.s.width + Space.l)
                                        .padding(.bottom, Space.s)
                                }
                                Hairline()
                                    .padding(.leading, BookCover.Size.s.width + Space.l)
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .leafMargins()
            .padding(.vertical, Space.l)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationTitle("More like this")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(book.id)|\(catalog.isLoaded)") {
            // Before the catalog has loaded there is nothing to compare with; keep the spinner rather than say "nothing".
            guard catalog.isLoaded else { return }
            picks = await catalog.similar(to: book, context: store.recommendationContext(catalog: catalog), because: store.similarReason(for: book))
        }
    }

    private func add(_ book: Book, to shelf: Shelf, atFront: Bool) {
        if store.item(book.id) == nil { store.add(book, to: shelf) } else { store.move(book.id, to: shelf) }
        if atFront { store.moveToFront(book.id) }
        Haptics.shared.success()
    }
}

// MARK: - Your taste

/// What Leaf has learned from the reader's shelves: the genres and themes it leans towards, the length and era they
/// finish, and what "Not for me" has steered away from. Read-only: it changes as the reader reads.
struct TasteView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(BookCatalog.self) private var catalog
    @State private var profile: TasteProfile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let profile {
                    content(profile)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .leafMargins()
            .padding(.vertical, Space.l)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationTitle("Your taste")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            profile = await catalog.tasteProfile(context: store.recommendationContext(catalog: catalog))
        }
    }

    @ViewBuilder
    private func content(_ profile: TasteProfile) -> some View {
        Text(profile.isCold ? "Still getting to know you." : "What your shelves say.")
            .leafStyle(.masthead)
            .fixedSize(horizontal: false, vertical: true)
        Text(profile.isCold
             ? "Leaf learns from what you finish, how quickly, what you rate, and what you set aside or mark “Not for me”. Finish a book and the shop starts to rearrange itself around you."
             : "Picked from what you finish and how quickly, your ratings, and the books you set aside. Every pick in the shop says which of these it came from.")
            .leafStyle(.body, color: .inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.s)
        if !profile.topGenres.isEmpty {
            SectionHeader("Genres you lean towards")
            chips(profile.topGenres.prefix(8).map { Genre.name($0) })
        }
        let themes = profile.topThemes.filter { !$0.hasPrefix("series:") }
        if !themes.isEmpty {
            SectionHeader("Themes you return to")
            chips(themes.prefix(10).map(Self.themeName))
        }
        // Series live in the profile's features as "s:<name>", not among its top themes.
        let worlds = profile.positive.weights
            .filter { $0.key.hasPrefix("s:") && $0.value > 0 }
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(6)
            .map { "series:" + $0.key.dropFirst(2) }
        if !worlds.isEmpty {
            SectionHeader("Worlds you're in")
            chips(worlds.map(Self.themeName))
        }
        if let hours = profile.logHoursMean.map({ exp($0) }) {
            SectionHeader("Length")
            Text("You finish books of about \(LeafFormat.duration(minutes: hours * 60)) at your pace.")
                .leafStyle(.body)
        }
        if let year = profile.yearMean {
            SectionHeader("Era")
            Text(Self.eraSentence(year))
                .leafStyle(.body)
        }
        if !store.data.dismissed.isEmpty {
            SectionHeader("Not for me")
            Text("\(store.data.dismissed.count) \(store.data.dismissed.count == 1 ? "book" : "books") marked “Not for me”, so the shop leans away from books like \(store.data.dismissed.count == 1 ? "it" : "them").")
                .leafStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chips(_ names: [String]) -> some View {
        TasteFlow(spacing: Space.s) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .leafStyle(.ui)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .background(Color.accentSoft, in: .capsule)
            }
        }
    }

    /// "found-family" → "Found family"; "series:middle earth" → "Middle Earth".
    static func themeName(_ raw: String) -> String {
        if raw.hasPrefix("series:") { return String(raw.dropFirst(7)).replacingOccurrences(of: "-", with: " ").capitalized }
        let spaced = raw.replacingOccurrences(of: "-", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func eraSentence(_ year: Double) -> String {
        let value = Int(year.rounded())
        if value < 1900 { return "You reach for the classics: books from before 1900 on average." }
        let decade = value / 10 * 10
        return "The books you finish were written around the \(decade)s on average."
    }
}

/// Wraps chips from the leading edge.
private struct TasteFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
