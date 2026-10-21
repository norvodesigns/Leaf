import SwiftUI

// MARK: - Result row

/// One search result (DESIGN.md §6): cover S, title, author, "1937 · 310 pp", and how long it takes at the
/// reader's pace. The text opens the book; the glass `plus` on the right adds it, and turns into a
/// `checkmark` once it is on a shelf. With `onQuickAdd` the `plus` opens the quick-add sheet (one tap to a big
/// choice) and the menu moves to a long press; without it the `plus` is the menu.
struct SearchResultRow: View {
    let book: Book
    let wpm: Double
    /// The shelf the book is already on, if any.
    let shelf: Shelf?
    /// Add (or move) the book: the shelf, and whether it goes to the front of that shelf.
    let onAdd: (Shelf, Bool) -> Void
    /// Opens the quick-add sheet for this book.
    var onQuickAdd: (() -> Void)?

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

            if let onQuickAdd {
                Button {
                    Haptics.shared.tap()
                    onQuickAdd()
                } label: {
                    GlassIcon(systemImage: shelf == nil ? "plus" : "checkmark", diameter: 40)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(minWidth: Space.hitTarget, minHeight: Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shelf == nil ? "Add \(book.title)" : "\(book.title), \(SearchShelfName.status(shelf)). Change shelf")
                .contextMenu {
                    SearchAddActions(shelf: shelf, onAdd: onAdd)
                }
            } else {
                SearchAddMenu(book: book, shelf: shelf, onAdd: onAdd)
            }
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

/// The 40 pt glass `plus` (a 44 pt target) with its menu: "Start reading", "Add to top of To read", "Add to end of To read".
/// Once the book is in the library the same button shows a `checkmark`, and its menu offers to move it.
struct SearchAddMenu: View {
    let book: Book
    let shelf: Shelf?
    let onAdd: (Shelf, Bool) -> Void

    var body: some View {
        Menu {
            SearchAddActions(shelf: shelf, onAdd: onAdd)
        } label: {
            GlassIcon(systemImage: shelf == nil ? "plus" : "checkmark", diameter: 40)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: Space.hitTarget, minHeight: Space.hitTarget)
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
        case .paused: return "Paused"
        case nil: return "Not in your library"
        }
    }
}

// MARK: - Carousel

/// One cover in a browsing row: it opens the book; its menu adds it, finds more like it, or says "Not for me".
/// Hero rows show the reason a pick was made under the cover; time-budget rows wear the reading time on the cover.
struct SearchCarouselCover: View {
    let book: Book
    let shelf: Shelf?
    /// Why this book is here ("Because you finished ..."), when it was picked for the reader.
    var reason: String?
    var size: BookCover.Size = .m
    /// A short label on the cover, such as the reading time at the reader's pace.
    var badge: String?
    /// Print the reason under the title, not only in the menu.
    var showsReason = false
    let onAdd: (Shelf, Bool) -> Void
    let onDismiss: () -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationLink(value: BookRoute(book: book)) {
            VStack(alignment: .leading, spacing: Space.s) {
                BookCover(book: book, size: size)
                    .overlay(alignment: .bottomLeading) {
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.paper.opacity(0.92), in: .capsule)
                                .padding(6)
                        }
                    }
                Text(book.title)
                    .leafStyle(.caption, color: .ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: size.width, alignment: .topLeading)
                if showsReason, let reason {
                    Text(reason)
                        .leafStyle(.caption, color: .inkTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: size.width, alignment: .topLeading)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .contextMenu {
            if let reason { Section(reason) { menuActions } } else { menuActions }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Opens the book")
        .accessibilityAction(named: "More like this") { moreLikeThis() }
        .accessibilityActions {
            if shelf == nil {
                Button("Not for me", action: onDismiss)
            }
        }
    }

    private var spokenLabel: String {
        var parts = ["\(book.title), by \(book.author)"]
        if let reason { parts.append(reason) }
        if let badge { parts.append("\(badge) at your pace") }
        return parts.joined(separator: ". ")
    }

    private func moreLikeThis() {
        Haptics.shared.tap()
        router.searchPath.append(SimilarRoute(book: book))
    }

    @ViewBuilder
    private var menuActions: some View {
        SearchAddActions(shelf: shelf, onAdd: onAdd)
        Button(action: moreLikeThis) {
            Label("More like this", systemImage: "sparkles")
        }
        if shelf == nil {
            Button(role: .destructive, action: onDismiss) {
                Label("Not for me", systemImage: "hand.thumbsdown")
            }
        }
    }
}
