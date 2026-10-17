import SwiftUI

/// The Finished shelf (DESIGN.md §6): a grid of cover M, grouped by year of finishing under
/// `display` heads ("2026"). A rating, when the reader gave one, sits quietly under the cover.
struct LibraryFinishedShelf: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onRemove: (Book) -> Void

    init(onRemove: @escaping (Book) -> Void) {
        self.onRemove = onRemove
    }

    private struct YearGroup: Identifiable {
        let year: Int
        let items: [LibraryItem]
        var id: Int { year }
    }

    /// Newest year first; within a year, newest finish first (`store.finished` is already sorted).
    private var groups: [YearGroup] {
        let calendar = store.calendar
        let grouped = Dictionary(grouping: store.finished) { item in
            calendar.component(.year, from: item.finishedAt ?? item.addedAt)
        }
        return grouped.keys.sorted(by: >).map { year in
            YearGroup(year: year, items: grouped[year] ?? [])
        }
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: Space.m, alignment: .top), count: count)
    }

    var body: some View {
        let years = groups
        if years.isEmpty {
            EmptyState(title: "Your finished books will live here.", message: "")
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(years) { group in
                    yearHeader(group)
                    LazyVGrid(columns: columns, alignment: .center, spacing: Space.xl) {
                        ForEach(group.items) { item in
                            tile(item)
                        }
                    }
                    .padding(.bottom, Space.xl)
                }
            }
        }
    }

    private func yearHeader(_ group: YearGroup) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .lastTextBaseline, spacing: Space.m) {
                Text(String(group.year))
                    .leafStyle(.display)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.m)
                Eyebrow(group.items.count == 1 ? "1 book" : "\(group.items.count) books")
            }
            Hairline()
        }
        .padding(.top, Space.l)
        .padding(.bottom, Space.l)
    }

    private func tile(_ item: LibraryItem) -> some View {
        NavigationLink(value: BookRoute(book: item.book)) {
            VStack(spacing: Space.s) {
                BookCover(book: item.book, size: .m)
                    .libraryBookZoomSource(item.id)
                ratingMark(item.rating)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens book details")
        .accessibilityValue(item.rating.map { "Rated \($0) out of 5" } ?? "")
        .contextMenu {
            Button {
                Motion.animate(Motion.paper) { store.startReading(item.id) }
                Haptics.shared.tap()
            } label: {
                Label("Read again", systemImage: "book")
            }
            Button {
                LibraryShelfActions.move(item.id, to: .toRead, store: store)
            } label: {
                Label("Move to To read", systemImage: "bookmark")
            }
            Button(role: .destructive) {
                onRemove(item.book)
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
    }

    /// Filled stars only, so an unrated book stays clean.
    @ViewBuilder
    private func ratingMark(_ rating: Int?) -> some View {
        if let rating, rating > 0 {
            HStack(spacing: 1) {
                ForEach(0..<min(rating, 5), id: \.self) { _ in
                    Image(systemName: "star.fill")
                }
            }
            .font(.caption2)
            .foregroundStyle(Color.inkSecondary)
            .accessibilityHidden(true)
        } else {
            // Keeps covers on one baseline whether or not a neighbour is rated.
            Color.clear.frame(height: 12)
        }
    }
}
