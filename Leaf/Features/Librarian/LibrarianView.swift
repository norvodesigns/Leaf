import SwiftUI

/// "Ask the Librarian": a written, offline conversation that ends in a shelf of picks. Three short questions (mood,
/// time, length) answered with glass chips, the librarian's replies as glass notes, then a carousel where every book
/// says why it's there. Level 2 in Canopy terms: a sheet reached from Search and Discover, Forest as its accent.
/// Nothing is spoken and nothing leaves the device; the finding is `Librarian` over the browse pool.
struct LibrarianScreen: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(BookCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = LibrarianModel()
    @State private var showsDeck = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Canopy.Space.l) {
                        LibrarianHeader()
                            .padding(.bottom, Canopy.Space.s)
                        ForEach(model.entries) { entry in
                            entryView(entry)
                                .id(entry.id)
                                .canopyFocusInTransition()
                        }
                        if model.isWriting {
                            LibrarianWriting()
                                .transition(.opacity)
                        }
                        prompt
                            .padding(.top, Canopy.Space.xs)
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomID)
                    }
                    .padding(.horizontal, Canopy.Space.margin)
                    .padding(.vertical, Canopy.Space.l)
                    .animation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion), value: model.entries.count)
                    .animation(Canopy.Motion.resolved(Canopy.Motion.snappy, reduceMotion: reduceMotion), value: model.step)
                    .animation(Canopy.Motion.fade, value: model.isWriting)
                }
                .scrollDismissesKeyboard(.never)
                .onChange(of: model.entries.count) { _, _ in
                    scrollToLatest(proxy)
                }
                .onChange(of: model.step) { _, _ in
                    scrollToLatest(proxy)
                }
            }
            .canopyBackdrop(.forest)
            .navigationTitle("Ask the Librarian")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: BookRoute.self) { route in
                BookDetailView(book: route.book)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        CanopyFeel.play(.tap)
                        router.showLibrarian = false
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showsDeck) {
                LibrarianDeckSheet(pool: model.matches)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await begin() }
    }

    private static let bottomID = "librarian.bottom"

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        // A new shelf of picks scrolls to its top so the covers are in view; anything else to the open question.
        let target: AnyHashable
        if case .picks? = model.entries.last?.kind, let last = model.entries.last {
            target = last.id
        } else {
            target = Self.bottomID
        }
        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
            proxy.scrollTo(target, anchor: target == AnyHashable(Self.bottomID) ? .bottom : .top)
        }
    }

    private func begin() async {
        await catalog.load()
        if reduceMotion || router.librarianStage != nil { model.replyPause = .zero }
        model.start(
            seed: SeededGenerator.daySeed(store.now, calendar: store.calendar),
            source: { [store, catalog] in
                (catalog.books, catalog.stats, store.recommendationContext(catalog: catalog))
            },
            similar: { [store, catalog] book in
                await catalog.similar(to: book, context: store.recommendationContext(catalog: catalog), limit: 16, because: store.similarReason(for: book))
            }
        )
        // Screenshots: answer the questions so the shelf of picks is on screen.
        if let stage = router.librarianStage {
            router.librarianStage = nil
            if stage == "answer" {
                model.chooseMood(LibrarianMood.mood(id: "cozy"))
                model.chooseTime(.weekend)
            }
        }
    }

    // MARK: Entries

    @ViewBuilder
    private func entryView(_ entry: LibrarianEntry) -> some View {
        switch entry.kind {
        case .says(let text):
            LibrarianSays(text: text)
        case .reader(let text):
            ReaderSays(text: text)
        case .picks(let title, let picks):
            LibrarianShelf(title: title, picks: picks, wpm: store.wpm) { book in
                model.moreLike(book)
            }
        }
    }

    // MARK: The open question

    @ViewBuilder
    private var prompt: some View {
        if !model.isWriting {
            switch model.step {
            case .mood:
                LibrarianChoices {
                    ForEach(LibrarianMood.all) { mood in
                        CanopyChip(mood.label, systemImage: mood.symbol) { model.chooseMood(mood) }
                    }
                    CanopyChip("Surprise me", systemImage: "dice") { model.chooseMood(nil) }
                }
            case .time:
                LibrarianChoices {
                    ForEach(LibrarianAsk.Time.allCases, id: \.self) { time in
                        CanopyChip(time.label, systemImage: symbol(for: time), accent: .dusk) { model.chooseTime(time) }
                    }
                    CanopyChip("No rush", systemImage: "infinity", accent: .dusk) { model.chooseTime(nil) }
                }
            case .length:
                LibrarianChoices {
                    ForEach(LibrarianAsk.Length.allCases, id: \.self) { length in
                        CanopyChip(length == .any ? length.label : "\(length.label), \(length.detail)", systemImage: symbol(for: length)) {
                            model.chooseLength(length)
                        }
                    }
                }
            case .thinking:
                EmptyView()
            case .answered:
                LibrarianChoices {
                    CanopyChip("Show me others", systemImage: "arrow.clockwise") { model.again() }
                    if model.matches.count >= 3 {
                        CanopyChip("Swipe through the shelf", systemImage: "rectangle.stack") { showsDeck = true }
                    }
                    CanopyChip("Ask something else", systemImage: "arrow.uturn.backward") { model.startOver() }
                }
            }
        }
    }

    private func symbol(for time: LibrarianAsk.Time) -> String {
        switch time {
        case .tonight: "moon"
        case .weekend: "sun.max"
        case .thisWeek: "calendar"
        case .longHaul: "books.vertical"
        }
    }

    private func symbol(for length: LibrarianAsk.Length) -> String {
        switch length {
        case .slim: "book.closed"
        case .middling: "book"
        case .doorstop: "text.book.closed"
        case .any: "ellipsis"
        }
    }
}

// MARK: - Header

/// The librarian's name and the promise that this is private and offline. No glow: Canopy's page is clean cream.
private struct LibrarianHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: Canopy.Space.m) {
            LibrarianAvatar(size: 52)
            VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                Text("The Librarian")
                    .canopyText(.subline, color: Canopy.text)
                Text("Knows every shelf. Works offline, only on this phone.")
                    .canopyText(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The lamp on a round of glass, in Forest.
private struct LibrarianAvatar: View {
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: "lamp.desk")
            .font(.system(size: size * 0.44, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(CanopyAccent.forest.color)
            .frame(width: size, height: size)
            .canopyGlass(.forest, interactive: false, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Bubbles

/// The librarian's note: plain words on a glass card, with the lamp beside it.
private struct LibrarianSays: View {
    let text: String

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 6, bottomLeading: Canopy.Radius.control, bottomTrailing: Canopy.Radius.control, topTrailing: Canopy.Radius.control), style: .continuous)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Canopy.Space.s) {
            LibrarianAvatar()
            Text(text)
                .canopyText(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Canopy.Space.l)
                .padding(.vertical, Canopy.Space.m)
                .canopyGlass(interactive: false, in: shape)
            Spacer(minLength: Canopy.Space.xxl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The librarian: \(text)")
    }
}

/// The reader's answer, on the right in Forest glass.
private struct ReaderSays: View {
    let text: String

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: Canopy.Radius.control, bottomLeading: Canopy.Radius.control, bottomTrailing: 6, topTrailing: Canopy.Radius.control), style: .continuous)
    }

    var body: some View {
        HStack {
            Spacer(minLength: Canopy.Space.xxxl)
            Text(text)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(CanopyAccent.forest.color)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Canopy.Space.l)
                .padding(.vertical, Canopy.Space.s + Canopy.Space.xxs)
                .canopyGlass(.forest, interactive: false, in: shape)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(text)")
    }
}

/// Three dots while the librarian "writes". The symbol effect is the system's, so Reduce Motion is honoured.
private struct LibrarianWriting: View {
    var body: some View {
        HStack(spacing: Canopy.Space.s) {
            LibrarianAvatar()
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(Canopy.textTertiary)
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .frame(width: 56, height: 36)
                .canopyGlass(interactive: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The librarian is looking")
    }
}

// MARK: - Choices

/// The answers to the open question: glass chips wrapped onto as many lines as they need, merged in one container.
private struct LibrarianChoices<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: Canopy.Space.s) {
            WrapLayout(spacing: Canopy.Space.s) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Lays children out left to right, wrapping to a new line when a row is full, each line aligned to the trailing
/// edge (the reader's side of the conversation).
private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.maxX - row.width
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Search's way in

/// The invitation on Search and Discover: the lamp and one line, on a glass card.
struct LibrarianBanner: View {
    let action: () -> Void

    var body: some View {
        Button {
            CanopyFeel.play(.tap)
            action()
        } label: {
            HStack(spacing: Canopy.Space.l) {
                LibrarianAvatar(size: 48)
                VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                    Text("Ask the Librarian")
                        .canopyText(.headline)
                    Text("Tell me a mood and how much time you have.")
                        .canopyText(.caption)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Canopy.textTertiary)
                    .accessibilityHidden(true)
            }
            .canopyCard(padding: Canopy.Space.l)
            .contentShape(RoundedRectangle(cornerRadius: Canopy.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ask the Librarian. Tell me a mood and how much time you have.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Deck

/// "Swipe through the shelf": the swipe deck, dealt from everything that fit the last answer.
private struct LibrarianDeckSheet: View {
    let pool: [Book]

    @Environment(LibraryStore.self) private var store
    @Environment(BookCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var model = SwipeDeckModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: Canopy.Space.l) {
                Text("Everything that fit, best first. Right to keep, left to pass.")
                    .canopyText(.caption)
                    .multilineTextAlignment(.center)
                SwipeDeckView(model: model, style: .full, wpm: store.wpm) {
                    dismiss()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Canopy.Space.margin)
            .padding(.top, Canopy.Space.s)
            .canopyBackdrop(.forest)
            .navigationTitle("The shelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        CanopyFeel.play(.tap)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            DeckCommit.connect(model, store: store)
            model.load(
                pool: pool,
                stats: catalog.stats,
                context: store.recommendationContext(catalog: catalog),
                seed: SeededGenerator.daySeed(store.now, calendar: store.calendar) &+ 7
            )
        }
    }
}
