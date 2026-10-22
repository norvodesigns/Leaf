import SwiftUI

/// The Reading shelf (docs/design/REDESIGN.md §4.3): big covers two to a row on cream glass cards, each with the
/// title, author, how far in, and "p. 142 of 310 · done by 26 Oct". Tapping a card opens the book.
struct LibraryReadingShelf: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize

    let onRemove: (Book) -> Void

    init(onRemove: @escaping (Book) -> Void) {
        self.onRemove = onRemove
    }

    var body: some View {
        let items = store.reading
        if items.isEmpty {
            EmptyState(
                title: "Nothing open.",
                message: "Start a book from Up next or Search.",
                actionTitle: "Find a book"
            ) {
                router.tab = .search
            }
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Canopy.Space.cardGap) {
                ForEach(items) { item in
                    LibraryReadingRow(
                        item: item,
                        finish: store.plan.book(item.id)?.finish,
                        now: store.now,
                        calendar: store.calendar,
                        onFinish: { LibraryShelfActions.markFinished(item.book, store: store) },
                        onMoveToQueue: { LibraryShelfActions.move(item.id, to: .toRead, store: store) },
                        onRemove: { onRemove(item.book) }
                    )
                }
            }
        }
    }

    /// Two big covers to a row (docs/design/REDESIGN.md §4.3); one at accessibility sizes, so titles and authors
    /// aren't cut short.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Canopy.Space.cardGap, alignment: .top),
              count: typeSize.isAccessibilitySize ? 1 : 2)
    }
}

private struct LibraryReadingRow: View {
    let item: LibraryItem
    let finish: Date?
    let now: Date
    let calendar: Calendar
    let onFinish: () -> Void
    let onMoveToQueue: () -> Void
    let onRemove: () -> Void

    var body: some View {
        NavigationLink(value: BookRoute(book: item.book)) {
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                BookCover(book: item.book, size: .m)
                    .libraryBookZoomSource(item.id)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Canopy.Space.xs)
                Text(item.book.title)
                    .canopyText(.bookTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.book.author)
                    .canopyText(.caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: Canopy.Space.s) {
                    Text("\(item.percent)%")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(CanopyAccent.forest.color)
                    CanopyProgressBar(value: item.progress, height: 4)
                }
                Text(caption)
                    .canopyText(.caption, color: Canopy.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .canopyCard(padding: Canopy.Space.l)
            .contentShape(RoundedRectangle(cornerRadius: Canopy.Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens book details")
        .contextMenu {
            Button(action: onFinish) {
                Label("Mark finished", systemImage: "checkmark.circle")
            }
            Button(action: onMoveToQueue) {
                Label("Move to Up next", systemImage: "bookmark")
            }
            Button(role: .destructive, action: onRemove) {
                Label("Remove from Library", systemImage: "trash")
            }
        }
    }

    /// "p. 142 of 310 · done by 26 Oct"
    private var caption: String {
        var parts: [String] = []
        if item.currentPage > 0 {
            parts.append("p. \(LeafFormat.number(item.currentPage)) of \(LeafFormat.number(item.book.pages))")
        } else {
            parts.append("\(LeafFormat.number(item.book.pages)) pages")
        }
        if let finish {
            parts.append(LibraryDates.donePhrase(finish, now: now, calendar: calendar))
        }
        return parts.joined(separator: " · ")
    }
}
