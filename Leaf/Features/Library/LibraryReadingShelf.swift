import SwiftUI

/// The Reading shelf (DESIGN.md §6): tall rows of a cover M with its ribbon, the title, the author,
/// the page span bar, and "p. 142 of 310 · done by 26 Oct". Tapping a row opens the book.
struct LibraryReadingShelf: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router

    let onRemove: (Book) -> Void

    init(onRemove: @escaping (Book) -> Void) {
        self.onRemove = onRemove
    }

    var body: some View {
        let items = store.reading
        if items.isEmpty {
            EmptyState(
                title: "Nothing open.",
                message: "Start a book from To read or Search.",
                actionTitle: "Find a book"
            ) {
                router.tab = .search
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    LibraryReadingRow(
                        item: item,
                        todayTo: todayTo(for: item),
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

    /// The page today's assignment reaches, or the current page when nothing is scheduled.
    private func todayTo(for item: LibraryItem) -> Int {
        let assignment = store.plan.today?.assignments.first { $0.bookID == item.id }
        return assignment?.toPage ?? item.currentPage
    }
}

private struct LibraryReadingRow: View {
    let item: LibraryItem
    let todayTo: Int
    let finish: Date?
    let now: Date
    let calendar: Calendar
    let onFinish: () -> Void
    let onMoveToQueue: () -> Void
    let onRemove: () -> Void

    var body: some View {
        NavigationLink(value: BookRoute(book: item.book)) {
            HStack(alignment: .top, spacing: Space.l) {
                BookCover(book: item.book, size: .m, ribbon: true)
                    .libraryBookZoomSource(item.id)
                    .padding(.bottom, BookCover.Size.m.ribbonTail)

                VStack(alignment: .leading, spacing: Space.s) {
                    Text(item.book.title)
                        .leafStyle(.headline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.book.author)
                        .leafStyle(.author)
                        .lineLimit(2)
                    Spacer(minLength: Space.s)
                    PageSpanBar(current: item.currentPage, todayTo: todayTo, total: item.book.pages)
                    Text(caption)
                        .leafStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: BookCover.Size.m.height, alignment: .topLeading)
            }
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .overlay(alignment: .bottom) { Hairline() }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens book details")
        .contextMenu {
            Button(action: onFinish) {
                Label("Mark finished", systemImage: "checkmark.circle")
            }
            Button(action: onMoveToQueue) {
                Label("Move to To read", systemImage: "bookmark")
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
