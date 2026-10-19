import SwiftUI

// Book detail's newer parts (UI-5): the edition picker, the journal, and "More like this".

// MARK: - Edition

/// "Your copy has 310 pages. Others: 330, 366." Progress is page-based, so picking the right edition matters; choosing
/// another count re-plans the book with it.
struct BookEditionPicker: View {
    let item: LibraryItem

    @Environment(LibraryStore.self) private var store

    /// Other page counts this work was printed with, nearest first.
    private var others: [Int] {
        let pages = item.book.pages
        let counts = Set((item.book.pageCounts ?? []).filter { $0 > 0 && $0 != pages })
        return counts.sorted { abs($0 - pages) < abs($1 - pages) }.prefix(6).sorted()
    }

    var body: some View {
        if !others.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(sentence)
                    .leafStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Menu {
                    Section("Pages in your copy") {
                        ForEach([item.book.pages] + others, id: \.self) { count in
                            Button {
                                guard count != item.book.pages else { return }
                                Haptics.shared.selection()
                                store.updateBook(item.id, pages: count)
                            } label: {
                                if count == item.book.pages {
                                    Label("\(LeafFormat.number(count)) pages", systemImage: "checkmark")
                                } else {
                                    Text("\(LeafFormat.number(count)) pages")
                                }
                            }
                        }
                    }
                } label: {
                    Text("Change")
                        .leafStyle(.caption, color: .accent)
                        .frame(minHeight: Space.hitTarget)
                }
                .accessibilityLabel("Change edition")
                .accessibilityHint("Pick the page count of your copy")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sentence: String {
        let list = others.map { LeafFormat.number($0) }.joined(separator: ", ")
        return "Your copy has \(LeafFormat.number(item.book.pages)) pages. Others: \(list)."
    }
}

// MARK: - Journal

/// The book's journal: thoughts and quotes, newest first, with a way to add one.
struct BookJournalList: View {
    let book: Book
    let currentPage: Int

    @Environment(LibraryStore.self) private var store
    @State private var showsCapture = false
    @State private var editing: JournalEntry?

    private var entries: [JournalEntry] { store.journal(for: book.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if entries.isEmpty {
                Text("Nothing kept yet. A line you loved, or a thought you had: it stays here with the page.")
                    .leafStyle(.body, color: .inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(entries) { entry in
                    entryRow(entry)
                    Hairline()
                }
            }
            SecondaryGlassButton("Add a thought or a quote", systemImage: "square.and.pencil", compact: true) {
                showsCapture = true
            }
        }
        .sheet(isPresented: $showsCapture) {
            JournalCaptureSheet(book: book, sessionID: nil, page: currentPage)
        }
    }

    private func entryRow(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if entry.kind == .quote {
                Text("“\(entry.text)”")
                    .leafStyle(.pullQuote)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(entry.text)
                    .leafStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.s) {
                Text(meta(entry))
                    .leafStyle(.caption, color: .inkTertiary)
                if entry.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.ribbon)
                        .accessibilityLabel("Favourite")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .contextMenu {
            Button {
                store.updateJournalEntry(entry.id, isFavorite: !entry.isFavorite)
            } label: {
                Label(entry.isFavorite ? "Unfavourite" : "Favourite", systemImage: entry.isFavorite ? "heart.slash" : "heart")
            }
            ShareLink(item: entry.kind == .quote ? "“\(entry.text)” — \(book.title), \(book.author)" : entry.text) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                store.deleteJournalEntry(entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Touch and hold for more")
    }

    /// "Quote · p. 74 · 9 Oct".
    private func meta(_ entry: JournalEntry) -> String {
        var parts = [entry.kind == .quote ? "Quote" : "Thought"]
        if let page = entry.page { parts.append("p. \(page)") }
        parts.append(LeafFormat.format(entry.createdAt, template: "dMMM", calendar: store.calendar))
        return parts.joined(separator: " · ")
    }
}

// MARK: - More like this

/// A carousel of books that share this one's genres, themes or world, each with its reason.
struct BookMoreLikeThis: View {
    let book: Book

    @Environment(LibraryStore.self) private var store
    @Environment(BookCatalog.self) private var catalog
    @State private var picks: [Recommendation] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !picks.isEmpty {
                SectionHeader("More like this", topSpacing: 0)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Space.m) {
                        ForEach(picks) { pick in
                            NavigationLink(value: BookRoute(book: pick.book)) {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    BookCover(book: pick.book, size: .m)
                                    Text(pick.book.title)
                                        .leafStyle(.caption, color: .ink)
                                        .lineLimit(2)
                                        .frame(width: BookCover.Size.m.width, alignment: .leading)
                                    Text(pick.reason.text)
                                        .leafStyle(.caption, color: .inkTertiary)
                                        .lineLimit(2)
                                        .frame(width: BookCover.Size.m.width, alignment: .leading)
                                }
                            }
                            .buttonStyle(.pressable)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(pick.book.title), by \(pick.book.author). \(pick.reason.text)")
                        }
                    }
                    .padding(.bottom, Space.s)
                }
                .contentMargins(.horizontal, Space.margin, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .padding(.horizontal, -Space.margin)
            }
        }
        .task(id: "\(book.id)|\(catalog.isLoaded)") {
            guard catalog.isLoaded else { return }
            picks = await catalog.similar(to: book, context: store.recommendationContext(catalog: catalog), limit: 12)
        }
    }
}
