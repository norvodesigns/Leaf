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

/// The quick-add sheet: the book at the top, then one tap to put it where it belongs. Start reading, Want to
/// read (at the end, or up next), or Already read. A book that is already in the library shows where it is and
/// offers only the moves that still make sense. A half-height glass sheet, so the results stay visible behind it.
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
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                actions
            }
            .leafMargins()
            .padding(.top, Space.xl)
            .padding(.bottom, Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Space.l) {
            BookCover(book: book, size: .m)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                if let note = request.note {
                    Eyebrow(note)
                }
                Text(book.title)
                    .leafStyle(.title)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(book.author)
                    .leafStyle(.author)
                Text(facts)
                    .leafStyle(.caption)
                    .padding(.top, Space.xxs)
                if let shelf {
                    Label(SearchShelfName.status(shelf), systemImage: "checkmark.circle.fill")
                        .leafStyle(.caption, color: .accent)
                        .padding(.top, Space.xxs)
                }
                TextButton("About this book") {
                    Haptics.shared.tap()
                    dismiss()
                    onOpen()
                }
                .padding(.top, Space.xs)
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

    @ViewBuilder
    private var actions: some View {
        GlassEffectContainer(spacing: Space.m) {
            VStack(spacing: Space.m) {
                if shelf != .reading {
                    PrimaryGlassButton(shelf == .finished ? "Read it again" : "Start reading", systemImage: "book.fill", playsHaptic: false) {
                        choose(.startReading)
                    }
                }
                if shelf == nil {
                    SecondaryGlassButton("Want to read", systemImage: "bookmark", playsHaptic: false) {
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
            ? AnyLayout(VStackLayout(spacing: Space.m))
            : AnyLayout(HStackLayout(spacing: Space.m))
        layout {
            if shelf == nil || shelf == .toRead || shelf == .paused {
                SecondaryGlassButton(shelf == .toRead ? "Move up next" : "Up next", systemImage: "arrow.up.to.line", compact: true, playsHaptic: false) {
                    choose(.wantToRead(next: true))
                }
            }
            if shelf != .finished {
                SecondaryGlassButton("Already read", systemImage: "checkmark", compact: true, playsHaptic: false) {
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
