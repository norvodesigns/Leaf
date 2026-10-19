import SwiftUI

/// Search (DESIGN.md §6). With nothing typed, themed rows of covers to browse. While typing, books on this
/// device appear at once and Open Library results merge in after a short pause. If Open Library can't be
/// reached the list quietly stays local.
struct SearchView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(BookCatalog.self) private var catalog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var localResults: [Book] = []
    @State private var remoteResults: [Book] = []
    /// The query `remoteResults` answers.
    @State private var remoteQuery = ""
    @State private var phase: RemotePhase = .idle
    @State private var collections: [BookCollection] = []
    /// The rows have been built at least once, so an empty list means "nothing to browse", not "not yet".
    @State private var collectionsBuilt = false
    @State private var showsManualAdd = false
    /// The error haptic plays once per stretch offline, not on every keystroke.
    @State private var hasBuzzedOffline = false

    /// Where the Open Library half of a search stands.
    private enum RemotePhase {
        case idle, loading, live, offline
    }

    private struct SearchKey: Hashable {
        let text: String
        let catalogReady: Bool
    }

    /// What the rows are built from. When any of it changes the rows are rebuilt.
    private struct CollectionsKey: Hashable {
        let catalogReady: Bool
        let wpmBucket: Int
        let libraryHash: Int
        let dismissedCount: Int
        let sessionCount: Int
        let day: Int
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if trimmedQuery.isEmpty {
                    browse
                } else {
                    results
                }
            }
            .leafMargins()
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Title or author")
        .autocorrectionDisabled()
        .task(id: SearchKey(text: trimmedQuery, catalogReady: catalog.isLoaded)) {
            await runSearch(trimmedQuery)
        }
        .task(id: collectionsKey) {
            await rebuildCollections()
        }
        .onAppear(perform: consumeRouterQuery)
        .onChange(of: router.searchQuery) { _, newValue in
            if newValue != nil { consumeRouterQuery() }
        }
        .sheet(isPresented: $showsManualAdd) {
            AddBookManuallyView()
        }
    }

    // MARK: Browse

    @ViewBuilder
    private var browse: some View {
        if !catalog.isLoaded {
            searching("Opening the catalog…")
        } else if !collectionsBuilt {
            Color.clear
                .frame(height: 1)
        } else if collections.isEmpty {
            EmptyState(
                title: "Look up a book.",
                message: "Type a title or an author to see how long it takes at your pace."
            )
        } else {
            DeckBanner(covers: Array(collections.first?.books.prefix(3) ?? [])) {
                router.showDeck = true
            }
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
            ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                SearchCollectionRow(
                    collection: collection,
                    isFirst: index == 0,
                    shelfOf: { store.shelf(of: $0) },
                    onAdd: { book, shelf, front in add(book, to: shelf, atFront: front) },
                    onDismiss: { dismiss($0) }
                )
            }
            manualAddLink
        }
    }

    private var collectionsKey: CollectionsKey {
        var library = Hasher()
        for item in store.data.items {
            library.combine(item.id)
            library.combine(item.shelf)
            library.combine(item.rating)
        }
        return CollectionsKey(
            catalogReady: catalog.isLoaded,
            wpmBucket: Int(store.wpm / 10),
            libraryHash: library.finalize(),
            dismissedCount: store.data.dismissed.count,
            sessionCount: store.data.sessions.count,
            day: Int(store.calendar.startOfDay(for: store.now).timeIntervalSince1970 / 86_400)
        )
    }

    /// The rows depend on the catalog, the reader's pace and history, and the day (they change daily), so they
    /// are built when one of those changes rather than on every render. The work happens off the main thread.
    private func rebuildCollections() async {
        guard catalog.isLoaded else {
            collections = []
            collectionsBuilt = false
            return
        }
        let rows = await catalog.collections(context: store.recommendationContext(catalog: catalog))
        guard !Task.isCancelled else { return }
        if !collectionsBuilt {
            collections = rows
            collectionsBuilt = true
        } else {
            withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                collections = rows
            }
        }
    }

    // MARK: Results

    /// Books on this device first, then whatever Open Library adds. Live results from an earlier, shorter
    /// query stay only while they still match what is typed now.
    private var displayed: [Book] {
        let text = trimmedQuery
        let remote: [Book]
        switch phase {
        case .offline, .idle:
            remote = []
        case .loading, .live:
            remote = remoteQuery == text ? remoteResults : remoteResults.filter { SearchMerge.matches($0, query: text) }
        }
        return SearchMerge.merge(local: localResults, remote: remote)
    }

    @ViewBuilder
    private var results: some View {
        let books = displayed
        resultsHeader
        if books.isEmpty {
            if phase == .loading {
                searching("Searching…")
            } else {
                EmptyState(
                    title: "Nothing matches “\(trimmedQuery)”.",
                    message: phase == .offline ? "You’re offline, so only books on this device were searched." : "",
                    actionTitle: "Add it by hand"
                ) {
                    showsManualAdd = true
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(books) { book in
                    VStack(spacing: 0) {
                        SearchResultRow(
                            book: book,
                            wpm: store.wpm,
                            shelf: store.shelf(of: book.id),
                            onAdd: { shelf, front in add(book, to: shelf, atFront: front) }
                        )
                        Hairline()
                            .padding(.leading, BookCover.Size.s.width + Space.l)
                    }
                }
            }
            manualAddLink
        }
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(resultsEyebrow)
                    .leafStyle(.eyebrow)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s)
                if phase == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Searching Open Library")
                }
            }
            Hairline()
            if phase == .offline {
                Text("Open Library couldn’t be reached, so these are the books on this device.")
                    .leafStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.xs)
            }
        }
        .padding(.bottom, Space.s)
    }

    private var resultsEyebrow: String {
        switch phase {
        case .live where remoteQuery == trimmedQuery: return "Open Library"
        case .offline: return "Offline · books on this device"
        default: return "Books on this device"
        }
    }

    private func searching(_ text: String) -> some View {
        HStack(spacing: Space.s) {
            ProgressView()
            Text(text)
                .leafStyle(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
        .accessibilityElement(children: .combine)
    }

    private var manualAddLink: some View {
        TextButton("Not here? Add it by hand.") {
            Haptics.shared.tap()
            showsManualAdd = true
        }
        .padding(.top, Space.l)
    }

    // MARK: Searching

    /// Local results immediately; Open Library after a 250 ms pause. `.task(id:)` cancels this when the
    /// query changes, so a slow answer to an old query never lands on top of a new one.
    private func runSearch(_ text: String) async {
        guard !text.isEmpty else {
            localResults = []
            remoteResults = []
            remoteQuery = ""
            phase = .idle
            return
        }
        localResults = catalog.search(text)
        guard text.count >= 2 else {
            remoteResults = []
            remoteQuery = ""
            phase = .idle
            return
        }
        if phase != .offline { phase = .loading }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do {
            let found = try await OpenLibrary.search(text)
            guard !Task.isCancelled else { return }
            remoteResults = found
            remoteQuery = text
            phase = .live
            hasBuzzedOffline = false
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            phase = .offline
            if !hasBuzzedOffline {
                hasBuzzedOffline = true
                Haptics.shared.error()
            }
        }
    }

    // MARK: Actions

    /// Adds a book to a shelf, or moves it if it is already in the library. A book that is already in
    /// the library is moved rather than re-added, so a page count the reader edited is never overwritten.
    private func add(_ book: Book, to shelf: Shelf, atFront: Bool) {
        withAnimation(Motion.resolved(Motion.glass, reduceMotion: reduceMotion)) {
            if store.item(book.id) == nil {
                store.add(book, to: shelf)
            } else {
                store.move(book.id, to: shelf)
            }
            if atFront { store.moveToFront(book.id) }
        }
        Haptics.shared.success()
    }

    /// "Not for me": the book leaves every row and the next suggestions lean away from it.
    private func dismiss(_ book: Book) {
        Haptics.shared.tap()
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            store.dismiss(book.id)
        }
    }

    /// "Find a book" buttons and screenshot runs pre-fill the query through the router.
    private func consumeRouterQuery() {
        guard let incoming = router.searchQuery else { return }
        router.searchQuery = nil
        query = incoming
    }
}

// MARK: - Previews

@MainActor
private func searchPreviewStore() -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return store
}

private struct SearchPreviewHost: View {
    var body: some View {
        NavigationStack {
            SearchView()
                .navigationDestination(for: BookRoute.self) { route in
                    Text(route.book.title)
                }
        }
        .task { await BookCatalog.shared.load() }
    }
}

#Preview("Search") {
    SearchPreviewHost()
        .environment(searchPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Search · dark") {
    SearchPreviewHost()
        .environment(searchPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
        .preferredColorScheme(.dark)
}

#Preview("Search · query") {
    let router = AppRouter()
    router.searchQuery = "dune"
    return SearchPreviewHost()
        .environment(searchPreviewStore())
        .environment(router)
        .environment(BookCatalog.shared)
}
