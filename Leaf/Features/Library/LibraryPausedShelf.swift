import SwiftUI

/// The Paused shelf: books set aside without guilt. Each keeps its page; "Pick it back up" puts it back in Reading.
struct LibraryPausedShelf: View {
    @Environment(LibraryStore.self) private var store

    let onRemove: (Book) -> Void

    var body: some View {
        let items = store.data.items(on: .paused)
        if items.isEmpty {
            EmptyState(
                title: "Nothing set aside.",
                message: "When a book isn’t for now, set it aside from its page. It keeps your place and leaves the plan."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Set aside, not given up. Each keeps your page and stays out of the plan until you pick it back up.")
                    .leafStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Space.m)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        LibraryPausedRow(
                            item: item,
                            line: line(for: item),
                            onPickUp: {
                                Haptics.shared.play(.pageTurn)
                                LibraryShelfActions.move(item.id, to: .reading, store: store)
                            },
                            onRemove: { onRemove(item.book) }
                        )
                    }
                }
            }
        }
    }

    /// "Set aside 31 days ago · p. 188 of 612".
    private func line(for item: LibraryItem) -> String {
        var parts: [String] = []
        if let pausedAt = item.pausedAt {
            let days = LibraryDates.days(from: pausedAt, to: store.now, calendar: store.calendar)
            parts.append(days <= 0 ? "Set aside today" : (days == 1 ? "Set aside yesterday" : "Set aside \(days) days ago"))
        }
        if item.progressMode == .percent, item.book.pages > 0 {
            parts.append("\(Int((Double(item.currentPage) / Double(item.book.pages) * 100).rounded()))% read")
        } else if item.currentPage > 0 {
            parts.append("p. \(LeafFormat.number(item.currentPage)) of \(LeafFormat.number(item.book.pages))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct LibraryPausedRow: View {
    let item: LibraryItem
    let line: String
    let onPickUp: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.l) {
                NavigationLink(value: BookRoute(book: item.book)) {
                    HStack(alignment: .top, spacing: Space.l) {
                        BookCover(book: item.book, size: .s)
                            .saturation(0.7)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(item.book.title)
                                .leafStyle(.headline)
                                .lineLimit(2)
                            Text(item.book.author)
                                .leafStyle(.author)
                            Text(line)
                                .leafStyle(.caption)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the book")
            }
            TextButton("Pick it back up", style: .ui) {
                onPickUp()
            }
            .padding(.leading, BookCover.Size.s.width + Space.l)
            .accessibilityLabel("Pick \(item.book.title) back up")
            Hairline()
                .padding(.top, Space.s)
        }
        .padding(.vertical, Space.s)
        .contextMenu {
            Button(action: onPickUp) {
                Label("Pick it back up", systemImage: "book")
            }
            Button(role: .destructive, action: onRemove) {
                Label("Remove from Library", systemImage: "trash")
            }
        }
    }
}
