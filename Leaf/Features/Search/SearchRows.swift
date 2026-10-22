import SwiftUI

// MARK: - Result row

/// One search result (Canopy): cover S, the title in New York, author, "1937 · 310 pp", and how long it takes at the
/// reader's pace. The text opens the book; the glass `plus` on the right adds it, and turns into a Forest
/// `checkmark` once it is on a shelf. With `onQuickAdd` the `plus` is one tap (Search adds to Up next) and a long
/// press offers the other shelves and "More options"; without it the `plus` is the menu.
struct SearchResultRow: View {
    let book: Book
    let wpm: Double
    /// The shelf the book is already on, if any.
    let shelf: Shelf?
    /// Add (or move) the book: the shelf, and whether it goes to the front of that shelf.
    let onAdd: (Shelf, Bool) -> Void
    /// The one-tap add. It plays its own haptic.
    var onQuickAdd: (() -> Void)?
    /// Opens the quick-add sheet for this book (the long-press menu's last entry).
    var onOptions: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: Canopy.Space.m) {
            NavigationLink(value: BookRoute(book: book)) {
                HStack(alignment: .center, spacing: Canopy.Space.l) {
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
                Button(action: onQuickAdd) {
                    Image(systemName: shelf == nil ? "plus" : "checkmark")
                        .font(.system(.body, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(CanopyAccent.forest.color)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: Canopy.Space.hitTarget, height: Canopy.Space.hitTarget)
                        .canopyGlass(shelf == nil ? nil : .forest, in: Circle())
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shelf == nil ? "Add \(book.title) to Up next" : "\(book.title), \(SearchShelfName.status(shelf)). Change shelf")
                .accessibilityHint(shelf == nil ? "Touch and hold for other shelves" : "")
                .contextMenu {
                    SearchAddActions(shelf: shelf, onAdd: onAdd)
                    if let onOptions {
                        Button(action: onOptions) {
                            Label("More options…", systemImage: "ellipsis.circle")
                        }
                    }
                }
            } else {
                SearchAddMenu(book: book, shelf: shelf, onAdd: onAdd)
            }
        }
        .padding(.vertical, Canopy.Space.s)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
            Text(book.title)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .foregroundStyle(Canopy.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(book.author)
                .canopyText(.callout, color: Canopy.textSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Text(facts)
                .canopyText(.caption)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            Label(paceText, systemImage: "clock")
                .canopyText(.caption, color: CanopyAccent.dusk.color)
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

/// The ways to add a book (start, up next, later, already read), shared by the row's menu and a cover's context menu. For a book already
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
                    Label("Start reading", systemImage: "play.fill")
                }
            }
            if shelf == .toRead {
                Button {
                    onAdd(.toRead, true)
                } label: {
                    Label("Move up next", systemImage: "arrow.up.to.line")
                }
            }
        } else {
            Button {
                onAdd(.reading, false)
            } label: {
                Label("Start reading", systemImage: "play.fill")
            }
            Button {
                onAdd(.toRead, true)
            } label: {
                Label("Up next", systemImage: "arrow.up.to.line")
            }
            Button {
                onAdd(.toRead, false)
            } label: {
                Label("Want to read, later", systemImage: "arrow.down.to.line")
            }
            Button {
                onAdd(.finished, false)
            } label: {
                Label("Already read", systemImage: "checkmark")
            }
        }
    }
}

enum SearchShelfName {
    /// "On your Reading shelf", "In your Up next", "Finished".
    static func status(_ shelf: Shelf?) -> String {
        switch shelf {
        case .reading: return "On your Reading shelf"
        case .toRead: return "In your Up next"
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
