import SwiftUI

/// The librarian's answer: a carousel of glass cards, each with the cover, why it's here (Forest), how it fits the time
/// asked for (Dusk, the reading-and-time accent), and the two things a reader wants to do next: keep it, or start it.
/// "More like this" and "Not for me" sit in the card's menu and its VoiceOver actions.
struct LibrarianShelf: View {
    let title: String?
    let picks: [LibrarianPick]
    let wpm: Double
    let onMoreLike: (Book) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.s) {
            if let title {
                CanopyLabel(title)
                    .lineLimit(1)
            }
            ScrollView(.horizontal) {
                // At most eight cards, so a plain stack: fixed vertically so every card takes the tallest one's height.
                HStack(alignment: .top, spacing: Canopy.Space.m) {
                    ForEach(picks) { pick in
                        LibrarianPickCard(pick: pick, onMoreLike: onMoreLike)
                            .containerRelativeFrame(.horizontal) { width, _ in min(300, width * 0.78) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
                .padding(.vertical, Canopy.Space.xs)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Canopy.Space.margin, for: .scrollContent)
            .scrollClipDisabled()
            // The carousel runs edge to edge while the conversation keeps its margins.
            .padding(.horizontal, -Canopy.Space.margin)
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

    private var book: Book { pick.book }
    private var shelf: Shelf? { store.shelf(of: book.id) }
    private var isDismissed: Bool { store.data.dismissed.contains(book.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            NavigationLink(value: BookRoute(book: book)) {
                VStack(alignment: .leading, spacing: Canopy.Space.m) {
                    BookCover(book: book, size: typeSize.isAccessibilitySize ? .m : .l)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                        Text(book.title)
                            .font(.system(.headline, design: .serif, weight: .semibold))
                            .foregroundStyle(Canopy.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(book.author)
                            .canopyText(.caption)
                            .lineLimit(1)
                    }
                    note(pick.why, systemImage: pick.isPersonal && pick.why == pick.reason.text ? "sparkles" : "bookmark", accent: .forest)
                    note(pick.fit, systemImage: "clock", accent: .dusk)
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
        .frame(maxHeight: .infinity, alignment: .top)
        .canopyCard(padding: Canopy.Space.l)
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

    /// A short line with its job's icon: the reason in Forest, the time in Dusk. The words stay neutral.
    private func note(_ text: String, systemImage: String, accent: CanopyAccent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Canopy.Space.xs) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent.color)
                .accessibilityHidden(true)
            Text(text)
                .canopyText(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isDismissed {
            HStack {
                Text("Not for me")
                    .canopyText(.caption)
                Spacer(minLength: 0)
                Button("Undo") { toggleDismissed() }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(CanopyAccent.forest.color)
                    .frame(minWidth: Canopy.Space.hitTarget, minHeight: Canopy.Space.hitTarget)
            }
        } else if let shelf {
            HStack(spacing: Canopy.Space.xs) {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                Text(Self.label(for: shelf))
            }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(CanopyAccent.forest.color)
            .frame(maxWidth: .infinity, minHeight: Canopy.Space.hitTarget)
            .canopyFocusInTransition()
        } else {
            GlassEffectContainer(spacing: Canopy.Space.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Canopy.Space.s) { keepButton; startButton }
                    VStack(spacing: Canopy.Space.s) { keepButton; startButton }
                }
            }
        }
    }

    private static func label(for shelf: Shelf) -> String {
        switch shelf {
        case .reading: "Reading now"
        case .toRead: "In your Up next"
        case .finished: "Already read"
        case .paused: "Set aside"
        }
    }

    private var keepButton: some View {
        CanopyGlassButton("To read", systemImage: "plus", accent: .forest, compact: true, feel: .keep) {
            add(to: .toRead)
        }
    }

    private var startButton: some View {
        CanopyGlassButton("Start", systemImage: "play.fill", accent: .dusk, compact: true, feel: .startNow) {
            add(to: .reading)
        }
    }

    private func add(to shelf: Shelf) {
        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
            store.add(book, to: shelf)
        }
    }

    private func toggleDismissed() {
        CanopyFeel.play(.tap)
        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
            if isDismissed { store.undismiss(book.id) } else { store.dismiss(book.id) }
        }
    }
}
