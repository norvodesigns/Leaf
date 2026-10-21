import SwiftUI

/// The librarian's answer: a carousel of cards, each with the cover, why it's here, how it fits the time asked for,
/// and the two things a reader wants to do next (keep it, or start it). "More like this" and "Not for me" sit in the
/// card's menu and its VoiceOver actions.
struct LibrarianShelf: View {
    let title: String?
    let picks: [LibrarianPick]
    let wpm: Double
    let onMoreLike: (Book) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let title {
                Eyebrow(title)
                    .lineLimit(1)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Space.m) {
                    ForEach(picks) { pick in
                        LibrarianPickCard(pick: pick, onMoreLike: onMoreLike)
                            .containerRelativeFrame(.horizontal) { width, _ in min(300, width * 0.78) }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Space.margin, for: .scrollContent)
            // The carousel runs edge to edge while the conversation keeps its margins.
            .padding(.horizontal, -Space.margin)
        }
    }
}

/// One pick. Tapping the cover or title opens the book; the buttons act on the library in place.
private struct LibrarianPickCard: View {
    let pick: LibrarianPick
    let onMoreLike: (Book) -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale

    private var book: Book { pick.book }
    private var shelf: Shelf? { store.shelf(of: book.id) }
    private var isDismissed: Bool { store.data.dismissed.contains(book.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            NavigationLink(value: BookRoute(book: book)) {
                VStack(alignment: .leading, spacing: Space.m) {
                    BookCover(book: book, size: typeSize.isAccessibilitySize ? .m : .l)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.xs)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(book.title)
                            .leafStyle(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(book.author)
                            .leafStyle(.author)
                            .lineLimit(1)
                    }
                    whyThis
                    Text(pick.fit)
                        .leafStyle(.caption, color: .inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(book.title) by \(book.author). Why this: \(pick.why). \(pick.fit).")
            .accessibilityHint("Opens the book.")
            .accessibilityAddTraits(.isButton)

            Spacer(minLength: 0)
            actions
        }
        .padding(Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.paperRaised, in: Radius.shape(Radius.card))
        .overlay {
            Radius.shape(Radius.card)
                .strokeBorder(Color.hairline, lineWidth: 1 / displayScale)
        }
        .opacity(isDismissed ? 0.55 : 1)
        .contextMenu {
            Button("More like this", systemImage: "square.stack.3d.up") { onMoreLike(book) }
            if shelf == nil {
                Button(isDismissed ? "Undo not for me" : "Not for me", systemImage: isDismissed ? "arrow.uturn.backward" : "hand.thumbsdown") {
                    toggleDismissed()
                }
            }
        } preview: {
            BookCover(book: book, size: .xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "More like this") { onMoreLike(book) }
        .accessibilityAction(named: isDismissed ? "Undo not for me" : "Not for me") { toggleDismissed() }
    }

    /// The reason, with a small mark so it reads as the librarian's note rather than the blurb.
    private var whyThis: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Image(systemName: pick.isPersonal ? "sparkles" : "bookmark")
                .imageScale(.small)
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
            Text(pick.why)
                .leafStyle(.caption, color: .inkSecondary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isDismissed {
            HStack {
                Text("Not for me")
                    .leafStyle(.caption)
                Spacer(minLength: 0)
                TextButton("Undo") { toggleDismissed() }
                    .frame(minHeight: Space.hitTarget)
            }
        } else if let shelf {
            HStack(spacing: Space.xs) {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                Text(Self.label(for: shelf))
            }
            .font(LeafType.ui)
            .foregroundStyle(Color.accent)
            .frame(maxWidth: .infinity, minHeight: Space.hitTarget)
            .transition(Motion.transition(.scale(scale: 0.9).combined(with: .opacity), reduceMotion: reduceMotion))
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) { keepButton; startButton }
                VStack(spacing: Space.s) { keepButton; startButton }
            }
        }
    }

    private static func label(for shelf: Shelf) -> String {
        switch shelf {
        case .reading: "Reading now"
        case .toRead: "On your To read"
        case .finished: "Already read"
        case .paused: "Set aside"
        }
    }

    private var keepButton: some View {
        SecondaryGlassButton("Want to read", systemImage: "bookmark", compact: true, playsHaptic: false) {
            add(to: .toRead)
        }
    }

    private var startButton: some View {
        SecondaryGlassButton("Start", systemImage: "book", compact: true, playsHaptic: false) {
            add(to: .reading)
        }
    }

    private func add(to shelf: Shelf) {
        withAnimation(Motion.resolved(Motion.glass, reduceMotion: reduceMotion)) {
            store.add(book, to: shelf)
        }
        Haptics.shared.play(shelf == .reading ? .deckStart : .deckKeep)
    }

    private func toggleDismissed() {
        Haptics.shared.tap()
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            if isDismissed { store.undismiss(book.id) } else { store.dismiss(book.id) }
        }
    }
}
