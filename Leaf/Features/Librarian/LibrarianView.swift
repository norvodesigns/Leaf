import SwiftUI

/// "Ask the Librarian": a written, offline conversation that ends in a shelf of picks. Three short questions (mood,
/// time, length) answered with chips, the librarian's replies as paper notes, then a carousel where every book says
/// why it's there. Nothing is spoken and nothing leaves the device; the finding is `Librarian` over the browse pool.
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
                    VStack(alignment: .leading, spacing: Space.l) {
                        LibrarianHeader()
                            .padding(.bottom, Space.s)
                        ForEach(model.entries) { entry in
                            entryView(entry)
                                .id(entry.id)
                                .transition(Motion.transition(.inkIn, reduceMotion: reduceMotion))
                        }
                        if model.isWriting {
                            LibrarianWriting()
                                .transition(.opacity)
                        }
                        prompt
                            .padding(.top, Space.xs)
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomID)
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.vertical, Space.l)
                    .animation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion), value: model.entries.count)
                    .animation(Motion.resolved(Motion.fade, reduceMotion: reduceMotion), value: model.step)
                    .animation(Motion.fade, value: model.isWriting)
                }
                .scrollDismissesKeyboard(.never)
                .onChange(of: model.entries.count) { _, _ in
                    scrollToLatest(proxy)
                }
                .onChange(of: model.step) { _, _ in
                    scrollToLatest(proxy)
                }
            }
            .paperBackground()
            .navigationTitle("Ask the Librarian")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: BookRoute.self) { route in
                BookDetailView(book: route.book)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.shared.tap()
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
        .presentationBackground(Color.paper)
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
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
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
                        LibrarianChoice(mood.label, systemImage: mood.symbol) { model.chooseMood(mood) }
                    }
                    LibrarianChoice("Surprise me", systemImage: "dice", tone: .accent) { model.chooseMood(nil) }
                }
            case .time:
                LibrarianChoices {
                    ForEach(LibrarianAsk.Time.allCases, id: \.self) { time in
                        LibrarianChoice(time.label, systemImage: symbol(for: time)) { model.chooseTime(time) }
                    }
                    LibrarianChoice("No rush", systemImage: "infinity") { model.chooseTime(nil) }
                }
            case .length:
                LibrarianChoices {
                    ForEach(LibrarianAsk.Length.allCases, id: \.self) { length in
                        LibrarianChoice(length.label, detail: length == .any ? nil : length.detail, systemImage: symbol(for: length)) {
                            model.chooseLength(length)
                        }
                    }
                }
            case .thinking:
                EmptyView()
            case .answered:
                LibrarianChoices {
                    LibrarianChoice("Show me others", systemImage: "arrow.clockwise") { model.again() }
                    if model.matches.count >= 3 {
                        LibrarianChoice("Swipe through the shelf", systemImage: "rectangle.stack") { showsDeck = true }
                    }
                    LibrarianChoice("Ask something else", systemImage: "arrow.uturn.backward", tone: .quiet) { model.startOver() }
                }
            }
        }
    }

    private func symbol(for time: LibrarianAsk.Time) -> String {
        switch time {
        case .tonight: "moon"
        case .weekend: "sun.horizon"
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

/// A lamp's warm pool of light, the librarian's name, and the promise that this is private and offline.
private struct LibrarianHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            LibrarianAvatar(size: 52)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("The Librarian")
                    .leafStyle(.title)
                Text("Knows every shelf. Works offline, and only on this phone.")
                    .leafStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            // The lamp glow: a static gradient, nothing animated.
            RadialGradient(colors: [Color.lamp, Color.lamp.opacity(0)], center: .center, startRadius: 0, endRadius: 120)
                .frame(width: 240, height: 240)
                .offset(x: -94, y: -94)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LibrarianAvatar: View {
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: "lamp.desk.fill")
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(Color.amber)
            .frame(width: size, height: size)
            .background(Color.paperRaised, in: .circle)
            .overlay { Circle().strokeBorder(Color.hairline, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

// MARK: - Bubbles

/// The librarian's note: serif on raised paper, with the lamp beside it.
private struct LibrarianSays: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            LibrarianAvatar()
            Text(text)
                .leafStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
                .background(Color.paperRaised, in: UnevenRoundedRectangle(cornerRadii: .init(topLeading: 6, bottomLeading: Radius.tile, bottomTrailing: Radius.tile, topTrailing: Radius.tile), style: .continuous))
                .overlay {
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 6, bottomLeading: Radius.tile, bottomTrailing: Radius.tile, topTrailing: Radius.tile), style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                }
            Spacer(minLength: Space.xxl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The librarian: \(text)")
    }
}

/// The reader's answer, on the right in the accent.
private struct ReaderSays: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: Space.xxxl)
            Text(text)
                .leafStyle(.ui, color: .accent)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.s + Space.xxs)
                .background(Color.accentSoft, in: UnevenRoundedRectangle(cornerRadii: .init(topLeading: Radius.tile, bottomLeading: Radius.tile, bottomTrailing: 6, topTrailing: Radius.tile), style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(text)")
    }
}

/// Three dots while the librarian "writes". The symbol effect is the system's, so Reduce Motion is honoured.
private struct LibrarianWriting: View {
    var body: some View {
        HStack(spacing: Space.s) {
            LibrarianAvatar()
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(Color.inkTertiary)
                .symbolEffect(.variableColor.iterative, options: .repeating)
                .frame(width: 56, height: 36)
                .background(Color.paperRaised, in: Radius.shape(Radius.tile))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The librarian is looking")
    }
}

// MARK: - Choices

/// The answers to the open question, wrapped onto as many lines as they need.
private struct LibrarianChoices<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        WrapLayout(spacing: Space.s) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct LibrarianChoice: View {
    enum Tone { case plain, accent, quiet }

    let title: String
    var detail: String?
    var systemImage: String?
    var tone: Tone = .plain
    let action: () -> Void

    init(_ title: String, detail: String? = nil, systemImage: String? = nil, tone: Tone = .plain, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tone = tone
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.shared.selection()
            action()
        } label: {
            HStack(spacing: Space.xs + Space.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(LeafType.ui)
                    if let detail {
                        Text(detail)
                            .font(LeafType.caption)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Space.l - Space.xxs)
            .padding(.vertical, Space.s)
            .frame(minHeight: Space.hitTarget)
            .background(fill, in: Radius.shape(Radius.tile))
            .overlay {
                Radius.shape(Radius.tile)
                    .strokeBorder(tone == .accent ? Color.clear : Color.hairline, lineWidth: 1)
            }
            .contentShape(Radius.shape(Radius.tile))
        }
        .buttonStyle(.pressable)
    }

    private var foreground: Color {
        switch tone {
        case .plain: .ink
        case .accent: .accent
        case .quiet: .inkSecondary
        }
    }

    private var fill: Color {
        switch tone {
        case .plain: .paperRaised
        case .accent: .accentSoft
        case .quiet: .clear
        }
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

/// The invitation on Search: the lamp and one line.
struct LibrarianBanner: View {
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            HStack(spacing: Space.l) {
                LibrarianAvatar(size: 52)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Ask the Librarian")
                        .leafStyle(.headline)
                    Text("Tell me a mood and how much time you have.")
                        .leafStyle(.caption)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.inkTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Space.l)
            .background {
                ZStack(alignment: .leading) {
                    Color.paperRaised
                    RadialGradient(colors: [Color.lamp, Color.lamp.opacity(0)], center: .leading, startRadius: 0, endRadius: 160)
                }
                .clipShape(Radius.shape(Radius.card))
            }
            .overlay {
                Radius.shape(Radius.card)
                    .strokeBorder(Color.hairline, lineWidth: 1 / displayScale)
            }
            .contentShape(Radius.shape(Radius.card))
        }
        .buttonStyle(.pressable)
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
            VStack(spacing: Space.l) {
                Text("Everything that fit, best first. Right to keep, left to pass.")
                    .leafStyle(.caption)
                    .multilineTextAlignment(.center)
                SwipeDeckView(model: model, style: .full, wpm: store.wpm) {
                    dismiss()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s)
            .paperBackground()
            .navigationTitle("The shelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.shared.tap()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
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
