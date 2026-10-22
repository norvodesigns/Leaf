import SwiftUI

/// What the reader picked in the quick-add sheet.
enum QuickAddChoice: Hashable {
    case startReading
    /// To read: at the top ("Up next") or at the end.
    case wantToRead(next: Bool)
    case alreadyRead
}

/// A book waiting in the quick-add sheet. `note` is a line above it, such as "Found from the barcode".
struct QuickAddRequest: Identifiable, Hashable {
    let book: Book
    var note: String?

    var id: String { book.id }
}

/// The quick-add sheet (Canopy): the book at the top, then one tap to put it where it belongs. Start reading is the
/// screen's one Hero; Want to read, Up next and Already read are glass. A book already in the library shows where
/// it is and offers only the moves that still make sense. A `.medium` system-glass sheet, so the results stay visible
/// behind it; the book arrives with Focus In.
struct QuickAddSheet: View {
    let request: QuickAddRequest
    let shelf: Shelf?
    let wpm: Double
    let onChoose: (QuickAddChoice) -> Void
    let onOpen: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var book: Book { request.book }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Canopy.Space.xl) {
                header
                    .canopyFocusInTransition()
                actions
            }
            .padding(.horizontal, Canopy.Space.margin)
            .padding(.top, Canopy.Space.xl)
            .padding(.bottom, Canopy.Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Canopy.Space.l) {
            BookCover(book: book, size: .m)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                if let note = request.note {
                    Text(note).canopyText(.label)
                }
                Text(book.title)
                    .canopyText(.bookTitle)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(book.author)
                    .canopyText(.callout, color: Canopy.textSecondary)
                Text(facts)
                    .canopyText(.caption)
                    .padding(.top, Canopy.Space.xxs)
                if let shelf {
                    Label(SearchShelfName.status(shelf), systemImage: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .canopyText(.label)
                        .padding(.top, Canopy.Space.xxs)
                }
                Button {
                    CanopyFeel.play(.tap)
                    dismiss()
                    onOpen()
                } label: {
                    Text("About this book")
                        .canopyText(.label)
                        .frame(minHeight: Canopy.Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }

    /// "1965 · 612 pp · ≈ 9 h 40 min at your pace"
    private var facts: String {
        var parts: [String] = []
        if let year = book.year { parts.append(String(year)) }
        parts.append("\(book.pages) pp")
        parts.append("≈ \(LeafFormat.duration(minutes: book.minutes(atWPM: wpm))) at your pace")
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private var actions: some View {
        GlassEffectContainer(spacing: Canopy.Space.m) {
            VStack(spacing: Canopy.Space.m) {
                if shelf != .reading {
                    CanopyHeroButton(shelf == .finished ? "Read it again" : "Start reading", systemImage: "play.fill", feel: .startNow) {
                        choose(.startReading)
                    }
                }
                if shelf == nil {
                    CanopyGlassButton("Want to read", systemImage: "bookmark", accent: .forest, feel: .keep) {
                        choose(.wantToRead(next: false))
                    }
                }
                secondaryPair
            }
        }
    }

    /// "Up next" and "Already read" side by side, stacked at accessibility sizes.
    @ViewBuilder
    private var secondaryPair: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Canopy.Space.m))
            : AnyLayout(HStackLayout(spacing: Canopy.Space.m))
        layout {
            if shelf == nil || shelf == .toRead || shelf == .paused {
                CanopyGlassButton(shelf == .toRead ? "Move up next" : "Up next", systemImage: "arrow.up.to.line", accent: .forest, compact: true, feel: .keep) {
                    choose(.wantToRead(next: true))
                }
            }
            if shelf != .finished {
                // The finish moment plays its own haptic once the book is on the shelf.
                CanopyGlassButton("Already read", systemImage: "checkmark", accent: .forest, compact: true, feel: nil) {
                    choose(.alreadyRead)
                }
            }
        }
    }

    private func choose(_ choice: QuickAddChoice) {
        dismiss()
        onChoose(choice)
    }
}

#Preview("Quick add") {
    Color.paper
        .sheet(isPresented: .constant(true)) {
            QuickAddSheet(request: QuickAddRequest(book: DemoData.dune), shelf: nil, wpm: 240, onChoose: { _ in }, onOpen: {})
        }
}

#Preview("Quick add · on a shelf") {
    Color.paper
        .sheet(isPresented: .constant(true)) {
            QuickAddSheet(request: QuickAddRequest(book: DemoData.dune, note: "Found from the barcode"), shelf: .toRead, wpm: 240, onChoose: { _ in }, onOpen: {})
        }
        .preferredColorScheme(.dark)
}
