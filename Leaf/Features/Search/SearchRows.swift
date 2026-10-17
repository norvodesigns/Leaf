import SwiftUI

// MARK: - Result row

/// One search result (DESIGN.md §6): cover S, title, author, "1937 · 310 pp", and how long it takes at the
/// reader's pace. The text opens the book; the glass `plus` on the right adds it, and turns into a
/// `checkmark` once it is on a shelf.
struct SearchResultRow: View {
    let book: Book
    let wpm: Double
    /// The shelf the book is already on, if any.
    let shelf: Shelf?
    /// Add (or move) the book: the shelf, and whether it goes to the front of that shelf.
    let onAdd: (Shelf, Bool) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            NavigationLink(value: BookRoute(book: book)) {
                HStack(alignment: .center, spacing: Space.l) {
                    BookCover(book: book, size: .s)
                    details
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.pressable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            .accessibilityHint("Opens the book")

            SearchAddMenu(book: book, shelf: shelf, onAdd: onAdd)
        }
        .padding(.vertical, Space.s)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(book.title)
                .leafStyle(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(book.author)
                .leafStyle(.author)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Text(facts)
                .leafStyle(.caption)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Label(paceText, systemImage: "clock")
                .leafStyle(.caption)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        }
    }

    /// "1937 · 310 pp"
    private var facts: String {
        var parts: [String] = []
        if let year = book.year { parts.append(String(year)) }
        parts.append("\(book.pages) pp")
        return parts.joined(separator: " · ")
    }

    /// "≈ 6 h 22 min at your pace"
    private var paceText: String {
        "≈ \(LeafFormat.duration(minutes: book.minutes(atWPM: wpm))) at your pace"
    }

    private var spokenLabel: String {
        var parts = [book.title, "by \(book.author)"]
        if let year = book.year { parts.append(String(year)) }
        parts.append("\(book.pages) pages")
        parts.append("about \(LeafFormat.duration(minutes: book.minutes(atWPM: wpm))) at your pace")
        if let shelf { parts.append(SearchShelfName.status(shelf)) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Add menu

/// The 36 pt glass `plus` with its menu: "Start reading", "Add to top of To read", "Add to end of To read".
/// Once the book is in the library the same button shows a `checkmark`, and its menu offers to move it.
struct SearchAddMenu: View {
    let book: Book
    let shelf: Shelf?
    let onAdd: (Shelf, Bool) -> Void

    var body: some View {
        Menu {
            SearchAddActions(shelf: shelf, onAdd: onAdd)
        } label: {
            GlassIcon(systemImage: shelf == nil ? "plus" : "checkmark", diameter: 36)
                .contentTransition(.symbolEffect(.replace))
                .padding(4)
                .contentShape(.rect)
        }
        .accessibilityLabel(spokenLabel)
    }

    private var spokenLabel: String {
        guard let shelf else { return "Add \(book.title)" }
        return "\(book.title), \(SearchShelfName.status(shelf)). Change shelf"
    }
}

/// The three ways to add a book, shared by the row's menu and a cover's context menu. For a book already
/// on a shelf it shows where it is and offers the moves that still make sense.
struct SearchAddActions: View {
    let shelf: Shelf?
    let onAdd: (Shelf, Bool) -> Void

    var body: some View {
        if let shelf {
            Button {} label: {
                Label(SearchShelfName.status(shelf), systemImage: "checkmark")
            }
            .disabled(true)
            if shelf != .reading {
                Button {
                    onAdd(.reading, false)
                } label: {
                    Label("Start reading", systemImage: "book")
                }
            }
            if shelf == .toRead {
                Button {
                    onAdd(.toRead, true)
                } label: {
                    Label("Move to top of To read", systemImage: "arrow.up.to.line")
                }
            }
        } else {
            Button {
                onAdd(.reading, false)
            } label: {
                Label("Start reading", systemImage: "book")
            }
            Button {
                onAdd(.toRead, true)
            } label: {
                Label("Add to top of To read", systemImage: "arrow.up.to.line")
            }
            Button {
                onAdd(.toRead, false)
            } label: {
                Label("Add to end of To read", systemImage: "arrow.down.to.line")
            }
        }
    }
}

enum SearchShelfName {
    /// "On your Reading shelf", "On your To read list", "Finished".
    static func status(_ shelf: Shelf?) -> String {
        switch shelf {
        case .reading: return "On your Reading shelf"
        case .toRead: return "On your To read list"
        case .finished: return "Finished"
        case nil: return "Not in your library"
        }
    }
}

// MARK: - Carousel

/// A themed row on the empty Search tab: a SectionHeader eyebrow over a horizontal carousel of M covers
/// with their titles in `caption`. Long-press a cover to add it without opening it.
struct SearchCollectionRow: View {
    let collection: BookCollection
    let isFirst: Bool
    let shelfOf: (String) -> Shelf?
    let onAdd: (Book, Shelf, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(collection.subtitle, topSpacing: isFirst ? 0 : Space.xxxl)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Space.m) {
                    ForEach(collection.books) { book in
                        SearchCarouselCover(
                            book: book,
                            shelf: shelfOf(book.id),
                            onAdd: { shelf, front in onAdd(book, shelf, front) }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(collection.title)
    }
}

/// One cover in a carousel: it opens the book, and its context menu adds it.
struct SearchCarouselCover: View {
    let book: Book
    let shelf: Shelf?
    let onAdd: (Shelf, Bool) -> Void

    var body: some View {
        NavigationLink(value: BookRoute(book: book)) {
            VStack(alignment: .leading, spacing: Space.s) {
                BookCover(book: book, size: .m)
                Text(book.title)
                    .leafStyle(.caption, color: .ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: BookCover.Size.m.width, alignment: .topLeading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .contextMenu {
            SearchAddActions(shelf: shelf, onAdd: onAdd)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title), by \(book.author)")
        .accessibilityHint("Opens the book")
    }
}
