import SwiftUI

// MARK: - Model

/// The swipe deck on screen: a `SwipeDeck` (the engine, a value type) plus the three cards showing and what just
/// happened, so the view can offer Undo. Where a swipe goes is up to the owner: the library (`DeckCommit`) for Search
/// and Today, the reader's picks in onboarding.
@MainActor
@Observable
final class SwipeDeckModel {
    /// The top card first.
    private(set) var cards: [SwipeDeck.Card] = []
    private(set) var lastSwipe: SwipeDeck.Swipe?
    private(set) var isLoaded = false
    private(set) var keptCount = 0
    private(set) var startedCount = 0
    private(set) var passedCount = 0

    @ObservationIgnored private var deck: SwipeDeck?
    @ObservationIgnored var onSwipe: (@MainActor (SwipeDeck.Choice, Book) -> Void)?
    @ObservationIgnored var onUndo: (@MainActor (SwipeDeck.Swipe) -> Void)?

    static let visibleCount = 3

    /// Deals the deck once. Use the day's seed so reopening it shows the same start.
    func load(pool: [Book], stats: CatalogStats, context: RecommendationContext, seed: UInt64) {
        guard deck == nil, !pool.isEmpty else { return }
        var fresh = SwipeDeck(pool: pool, stats: stats, context: context, seed: seed)
        cards = fresh.peek(Self.visibleCount)
        deck = fresh
        isLoaded = true
    }

    var canUndo: Bool { lastSwipe != nil }

    var hasSwiped: Bool { keptCount + startedCount + passedCount > 0 }

    func swipe(_ choice: SwipeDeck.Choice) {
        guard var current = deck, let card = current.swipe(choice) else { return }
        cards = current.peek(Self.visibleCount)
        lastSwipe = current.swipes.last
        deck = current
        switch choice {
        case .keep: keptCount += 1
        case .startNow: startedCount += 1
        case .pass: passedCount += 1
        }
        onSwipe?(choice, card.book)
    }

    func undo() {
        guard var current = deck, let last = current.swipes.last else { return }
        current.undo()
        cards = current.peek(Self.visibleCount)
        lastSwipe = current.swipes.last
        deck = current
        switch last.choice {
        case .keep: keptCount = max(0, keptCount - 1)
        case .startNow: startedCount = max(0, startedCount - 1)
        case .pass: passedCount = max(0, passedCount - 1)
        }
        onUndo?(last)
    }
}

/// Swipes that go straight to the library: keep to To read, start now to Reading (it asks "Where are you?" on its
/// first session), pass to "not for me". Undo takes each back.
@MainActor
enum DeckCommit {
    static func apply(_ choice: SwipeDeck.Choice, book: Book, store: LibraryStore) {
        switch choice {
        case .keep: store.add(book, to: .toRead)
        case .startNow: store.add(book, to: .reading)
        case .pass: store.dismiss(book.id)
        }
    }

    static func undo(_ swipe: SwipeDeck.Swipe, store: LibraryStore) {
        switch swipe.choice {
        case .keep, .startNow: store.remove(swipe.book.id)
        case .pass: store.undismiss(swipe.book.id)
        }
    }

    /// Wires a model to the library.
    static func connect(_ model: SwipeDeckModel, store: LibraryStore) {
        model.onSwipe = { choice, book in apply(choice, book: book, store: store) }
        model.onUndo = { swipe in undo(swipe, store: store) }
    }
}

// MARK: - Deck view

/// The card stack (NEXT.md section 2.5): drag right to keep, left to pass, up to start now. A tick as the card crosses
/// into a choice, a heavier one for a keeper. Every swipe has a button too, and VoiceOver gets the same three choices
/// as actions on the card. Undo puts the last card back. Reduce Motion drops the tilt and the fling.
///
/// `.compact` sits inside a scrolling screen (Today), so its cards only move sideways and "start now" is a button.
struct SwipeDeckView: View {
    enum Style {
        case compact, full
    }

    let model: SwipeDeckModel
    var style: Style = .full
    let wpm: Double
    /// The card's height; nil for the style's own.
    var height: CGFloat?
    var onBrowse: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGSize = .zero
    @State private var armed: SwipeDeck.Choice?
    @State private var isFlinging = false

    private var threshold: CGFloat { style == .compact ? 90 : 110 }

    var body: some View {
        VStack(spacing: Space.l) {
            if !model.isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: cardHeight)
            } else if model.cards.isEmpty {
                emptyDeck
            } else {
                stack
                    .frame(height: cardHeight + 2 * 12)
                controls
            }
            statusLine
        }
    }

    private var cardHeight: CGFloat { height ?? (style == .compact ? 300 : 440) }

    // MARK: Stack

    private var stack: some View {
        ZStack {
            ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                let isTop = index == 0
                let depth = CGFloat(index)
                let scale: CGFloat = 1 - depth * 0.05
                let drop: CGFloat = depth * 12
                let lift: Double = isTop && drag != .zero ? 0.18 : 0
                let tilt: Double = isTop ? rotation : 0
                SwipeCard(card: card, wpm: wpm, roomy: cardHeight >= 420)
                    .frame(height: cardHeight)
                    .overlay(alignment: .top) {
                        if isTop { stamp }
                    }
                    .shadow(color: Color.coverShadow.opacity(lift), radius: 16, y: 10)
                    .scaleEffect(scale, anchor: .top)
                    .offset(y: drop)
                    .offset(isTop ? drag : .zero)
                    .rotationEffect(.degrees(tilt), anchor: .bottom)
                    .zIndex(Double(Self.zBase - index))
                    .allowsHitTesting(isTop && !isFlinging)
                    .modifier(DeckGesture(isEnabled: isTop, simultaneous: style == .compact, gesture: dragGesture))
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Keep for later") { fling(.keep) }
                    .accessibilityAction(named: "Not for me") { fling(.pass) }
                    .accessibilityAction(named: "Start now") { fling(.startNow) }
                    .accessibilityHidden(!isTop)
            }
        }
        .padding(.horizontal, Space.s)
    }

    private static let zBase = 10

    private var rotation: Double {
        guard !reduceMotion else { return 0 }
        return max(-14, min(14, Double(drag.width / 18)))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isFlinging else { return }
                let translation = style == .compact
                    ? CGSize(width: value.translation.width, height: 0)
                    : value.translation
                drag = translation
                let zone = choice(for: translation)
                if zone != armed {
                    if zone != nil { Haptics.shared.selection() }
                    armed = zone
                }
            }
            .onEnded { value in
                guard !isFlinging else { return }
                let translation = style == .compact
                    ? CGSize(width: value.predictedEndTranslation.width, height: 0)
                    : value.predictedEndTranslation
                if let picked = choice(for: drag) ?? choice(for: translation) {
                    fling(picked)
                } else {
                    armed = nil
                    withAnimation(Motion.resolved(Motion.board, reduceMotion: reduceMotion)) {
                        drag = .zero
                    }
                }
            }
    }

    private func choice(for translation: CGSize) -> SwipeDeck.Choice? {
        if style == .full, translation.height < -threshold, abs(translation.height) > abs(translation.width) {
            return .startNow
        }
        if translation.width > threshold { return .keep }
        if translation.width < -threshold { return .pass }
        return nil
    }

    /// Sends the top card off in the direction of `choice`, then records it.
    private func fling(_ choice: SwipeDeck.Choice) {
        guard !isFlinging, !model.cards.isEmpty else { return }
        switch choice {
        case .keep: Haptics.shared.play(.deckKeep)
        case .startNow: Haptics.shared.play(.deckStart)
        case .pass: Haptics.shared.soft(0.45)
        }
        armed = choice
        if reduceMotion {
            withAnimation(Motion.fade) {
                model.swipe(choice)
                drag = .zero
                armed = nil
            }
            return
        }
        isFlinging = true
        let target: CGSize
        switch choice {
        case .keep: target = CGSize(width: 700, height: drag.height + 40)
        case .pass: target = CGSize(width: -700, height: drag.height + 40)
        case .startNow: target = CGSize(width: drag.width, height: -1000)
        }
        withAnimation(.easeIn(duration: 0.22)) {
            drag = target
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                drag = .zero
                armed = nil
            }
            withAnimation(Motion.paper) {
                model.swipe(choice)
            }
            isFlinging = false
        }
    }

    // MARK: Stamp

    @ViewBuilder
    private var stamp: some View {
        let shown = armed ?? choice(for: drag)
        let upward: CGFloat = style == .full ? -drag.height : 0
        let progress: CGFloat = min(1, max(abs(drag.width), upward) / threshold)
        if let shown {
            DeckStamp(choice: shown)
                .opacity(Double(progress))
                .padding(.top, Space.xxl)
                .accessibilityHidden(true)
        }
    }

    // MARK: Controls

    private var controls: some View {
        GlassEffectContainer(spacing: Space.m) {
            HStack(spacing: Space.l) {
                GlassIconButton(systemImage: "xmark", label: "Not for me", diameter: 52, playsHaptic: false) {
                    fling(.pass)
                }
                GlassIconButton(systemImage: "arrow.uturn.backward", label: "Undo", diameter: 40) {
                    undo()
                }
                .disabled(!model.canUndo || isFlinging)
                .opacity(model.canUndo ? 1 : 0.4)
                GlassIconButton(systemImage: "book", label: "Start now", diameter: 52, playsHaptic: false) {
                    fling(.startNow)
                }
                GlassIconButton(systemImage: "bookmark", label: "Keep for later", diameter: 52, playsHaptic: false) {
                    fling(.keep)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func undo() {
        guard model.canUndo else { return }
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            model.undo()
        }
    }

    /// "Kept *Circe*." and the running count.
    private var statusLine: some View {
        Text(status)
            .leafStyle(.caption)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .contentTransition(.opacity)
            .animation(Motion.resolved(Motion.fade, reduceMotion: reduceMotion), value: status)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var status: String {
        guard let last = model.lastSwipe else {
            return style == .full ? "Right to keep for later, left to pass, up to start now." : "Right to keep for later, left to pass."
        }
        let title = last.book.title
        let what: String
        switch last.choice {
        case .keep: what = "Kept \(title) for later."
        case .startNow: what = "\(title) is on your desk."
        case .pass: what = "Passed on \(title)."
        }
        var counts: [String] = []
        if model.keptCount > 0 { counts.append("\(model.keptCount) kept") }
        if model.startedCount > 0 { counts.append("\(model.startedCount) to start") }
        return counts.isEmpty ? what : "\(what) \(counts.joined(separator: " · "))"
    }

    private var emptyDeck: some View {
        VStack(spacing: Space.m) {
            Text("❦")
                .leafStyle(.index)
            Text("That’s the deck for now.")
                .leafStyle(.title)
            Text("Come back tomorrow for a fresh one, or browse the shelves.")
                .leafStyle(.body, color: .inkSecondary)
                .multilineTextAlignment(.center)
            if let onBrowse {
                TextButton("Browse the shelves") { onBrowse() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight)
    }
}

/// Attaches the deck's drag to the top card only: exclusive on a full screen, alongside scrolling inside a list.
private struct DeckGesture<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let simultaneous: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if simultaneous {
            content.simultaneousGesture(gesture, including: isEnabled ? .all : .subviews)
        } else {
            content.gesture(gesture, including: isEnabled ? .all : .subviews)
        }
    }
}

// MARK: - Card

/// One book on the deck: the cover, the title, how long it is at the reader's pace, and why it's here.
struct SwipeCard: View {
    let card: SwipeDeck.Card
    let wpm: Double
    /// A tall card: a large cover and the title in `title`. Otherwise a medium cover and `headline`.
    var roomy: Bool = true

    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var book: Book { card.book }

    var body: some View {
        VStack(spacing: Space.m) {
            BookCover(book: book, size: coverSize)
                .padding(.top, Space.l)
            VStack(spacing: Space.xxs) {
                Text(book.title)
                    .leafStyle(roomy ? .title : .headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(book.author)
                    .leafStyle(.author)
                    .lineLimit(1)
            }
            Text(meta)
                .leafStyle(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(card.reason.text)
                .leafStyle(.caption, color: .inkSecondary)
                .italic()
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, Space.l)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paperRaised, in: Radius.shape(Radius.card))
        .overlay {
            Radius.shape(Radius.card)
                .strokeBorder(Color.hairline, lineWidth: 1 / displayScale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title) by \(book.author). \(meta). \(card.reason.text)")
        .accessibilityHint("Swipe up or down to keep it, pass, or start now.")
    }

    private var coverSize: BookCover.Size {
        if typeSize.isAccessibilitySize { return .s }
        return roomy ? .l : .m
    }

    /// "2018 · 404 pages · about 6 h at your pace"
    private var meta: String {
        var parts: [String] = []
        if let year = book.year { parts.append(String(year)) }
        parts.append("\(LeafFormat.number(book.pages)) pages")
        parts.append("about \(LeafFormat.duration(minutes: book.minutes(atWPM: wpm)))")
        return parts.joined(separator: " · ")
    }
}

/// The word stamped on a card as it crosses into a choice.
private struct DeckStamp: View {
    let choice: SwipeDeck.Choice

    private var text: String {
        switch choice {
        case .keep: "Keep"
        case .pass: "Pass"
        case .startNow: "Start now"
        }
    }

    private var color: Color {
        switch choice {
        case .keep: .accent
        case .pass: .inkSecondary
        case .startNow: .ribbon
        }
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(.headline, weight: .heavy))
            .tracking(2)
            .foregroundStyle(color)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.xs)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(color, lineWidth: 2.5)
            }
            .background(Color.paperRaised.opacity(0.85), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .rotationEffect(.degrees(choice == .pass ? 10 : -10))
    }
}

// MARK: - Screens

/// The deck as a sheet, from Search and from Today: the whole screen for the cards, every swipe straight to the library.
struct SwipeDeckScreen: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(BookCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var model = SwipeDeckModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.l) {
                Text("Picked from your taste, and learning as you swipe.")
                    .leafStyle(.caption)
                    .multilineTextAlignment(.center)
                SwipeDeckView(model: model, style: .full, wpm: store.wpm) {
                    router.showDeck = false
                    router.tab = .search
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s)
            .paperBackground()
            .navigationTitle("Picks for you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.shared.tap()
                        router.showDeck = false
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
        .task {
            await catalog.load()
            DeckCommit.connect(model, store: store)
            model.load(
                pool: catalog.books,
                stats: catalog.stats,
                context: store.recommendationContext(catalog: catalog),
                seed: SeededGenerator.daySeed(store.now, calendar: store.calendar)
            )
        }
    }
}

/// Today's between-books card: the deck in place, so the next book is a swipe away. Kept and started books go
/// straight to the library; the card stays until the reader says they're done.
struct TodayDeckCard: View {
    let isFirstShelf: Bool
    let onSwiped: () -> Void
    let onDone: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(BookCatalog.self) private var catalog
    @State private var model = SwipeDeckModel()

    private var headerAction: () -> Void {
        if model.hasSwiped { return onDone }
        return { router.showDeck = true }
    }

    var body: some View {
        TodayCard(
            isFirstShelf ? "Start your shelf" : "Your next book",
            actionTitle: model.hasSwiped ? "Done" : "Full screen",
            action: headerAction
        ) {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(isFirstShelf
                     ? "A few books to start with. Keep the ones you like; Leaf plans the pages."
                     : "Nothing on your desk. Keep what you fancy and Leaf will plan it.")
                    .leafStyle(.body, color: .inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SwipeDeckView(model: model, style: .compact, wpm: store.wpm) {
                    router.tab = .search
                }
            }
        }
        .task {
            await catalog.load()
            model.onSwipe = { [store] choice, book in
                DeckCommit.apply(choice, book: book, store: store)
                onSwiped()
            }
            model.onUndo = { [store] swipe in DeckCommit.undo(swipe, store: store) }
            model.load(
                pool: catalog.books,
                stats: catalog.stats,
                context: store.recommendationContext(catalog: catalog),
                seed: SeededGenerator.daySeed(store.now, calendar: store.calendar)
            )
        }
    }
}

/// Search's way into the deck: three covers fanned out and an invitation.
struct DeckBanner: View {
    let covers: [Book]
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            HStack(spacing: Space.l) {
                ZStack {
                    ForEach(Array(covers.prefix(3).enumerated()), id: \.element.id) { index, book in
                        BookCover(book: book, size: .s)
                            .rotationEffect(.degrees(Double(index - 1) * 8), anchor: .bottom)
                            .offset(x: CGFloat(index - 1) * 14)
                            .zIndex(Double(index == 1 ? 3 : index))
                    }
                }
                .frame(width: 96, height: 76)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Can’t decide?")
                        .leafStyle(.headline)
                    Text("Swipe through picks for you. Right to keep, left to pass.")
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
            .background(Color.paperRaised, in: Radius.shape(Radius.card))
            .overlay {
                Radius.shape(Radius.card)
                    .strokeBorder(Color.hairline, lineWidth: 1 / displayScale)
            }
            .contentShape(Radius.shape(Radius.card))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Can’t decide? Swipe through picks for you")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

@MainActor
private func deckPreviewStore() -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return store
}

#Preview("Deck") {
    Color.paper
        .sheet(isPresented: .constant(true)) {
            SwipeDeckScreen()
        }
        .environment(deckPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Deck card · dark") {
    ScrollView {
        TodayDeckCard(isFirstShelf: true, onSwiped: {}, onDone: {})
            .padding(20)
    }
    .paperBackground()
    .environment(deckPreviewStore())
    .environment(AppRouter())
    .environment(BookCatalog.shared)
    .preferredColorScheme(.dark)
}
