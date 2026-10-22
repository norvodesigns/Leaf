import SwiftUI

/// Search (DESIGN.md §6). With nothing typed, themed rows of covers to browse. While typing, books on this
/// device appear at once and Open Library results merge in after a short pause. If Open Library can't be
/// reached the list quietly stays local.
///
/// Adding is the fast path: the `plus` on a result opens the quick-add sheet, a typed ISBN is looked up directly,
/// the barcode button scans the back cover, and "Add it by hand" opens the form already holding what was typed.
/// Every add can be undone from the toast for a few seconds.
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
    /// The hand-add form, opened with whatever is already known.
    @State private var manualDraft: ManualBookDraft?
    @State private var quickAdd: QuickAddRequest?
    @State private var showsScanner = false
    /// Ask the Librarian, presented from here because Search is itself a sheet over Library.
    @State private var showsLibrarian = false
    /// Search is itself a sheet now, so the deck opens from here rather than from the tabs.
    @State private var showsDeck = false
    /// What the scanner found, presented once its sheet has gone.
    @State private var scanOutcome: ISBNScanOutcome?
    /// A typed ISBN that Open Library knows without a page count, so the form can start from it.
    @State private var isbnMatch: OpenLibrary.ISBNMatch?
    /// The search field has focus (the Library's "Add a book" opens Search ready to type).
    @State private var searchActive = false
    /// The book just added, while it can still be taken back.
    @State private var lastAdd: AddedNote?
    /// How long a toast stays; screenshot runs hold it long enough to be captured.
    @State private var toastSeconds = 5.0
    /// The error haptic plays once per stretch offline, not on every keystroke.
    @State private var hasBuzzedOffline = false
    /// The book just marked "Not for me", while it can still be taken back.
    @State private var undoBook: Book?

    /// Where the Open Library half of a search stands.
    private enum RemotePhase {
        case idle, loading, live, offline
    }

    /// An add that can be undone: the book, where it was before (nil if it was not in the library), and where it went.
    private struct AddedNote: Identifiable, Equatable {
        let id = UUID()
        let book: Book
        let previous: Shelf?
        let shelf: Shelf

        var message: String {
            switch shelf {
            case .reading: return "“\(book.title)” is on your Reading shelf."
            case .toRead: return "“\(book.title)” is in your Up next."
            case .finished: return "“\(book.title)” is on your Finished shelf."
            case .paused: return "“\(book.title)” is paused."
            }
        }
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if trimmedQuery.isEmpty {
                        browse(proxy)
                    } else {
                        results
                    }
                }
                .leafMargins()
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxl)
            }
            .task(id: collectionsBuilt) {
                await applyStage(proxy)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let note = lastAdd {
                UndoToast(message: note.message) {
                    undoAdd(note)
                }
                .padding(.bottom, Canopy.Space.s)
                .canopyFocusInTransition()
                .task(id: note.id) {
                    try? await Task.sleep(for: .seconds(toastSeconds))
                    guard !Task.isCancelled, lastAdd?.id == note.id else { return }
                    withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) { lastAdd = nil }
                }
            } else if let book = undoBook {
                UndoToast(message: "“\(book.title)” won’t be suggested.") {
                    withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
                        store.undismiss(book.id)
                        undoBook = nil
                    }
                }
                .padding(.bottom, Canopy.Space.s)
                .canopyFocusInTransition()
                .task(id: book.id) {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled, undoBook?.id == book.id else { return }
                    withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) { undoBook = nil }
                }
            }
        }
        .navigationDestination(for: BookCollection.self) { collection in
            CollectionGridView(collection: collection)
        }
        .navigationDestination(for: SimilarRoute.self) { route in
            SimilarBooksView(book: route.book)
        }
        .navigationDestination(for: TasteRoute.self) { _ in
            TasteView()
        }
        .toolbar {
            if router.showSearch {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        CanopyFeel.play(.tap)
                        router.showSearch = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close search")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    CanopyFeel.play(.tap)
                    showsScanner = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                }
                .accessibilityLabel("Scan a book’s barcode")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: TasteRoute()) {
                    Image(systemName: "heart.text.square")
                }
                .accessibilityLabel("Your taste")
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, isPresented: $searchActive, prompt: "Title, author or ISBN")
        .autocorrectionDisabled()
        .task(id: SearchKey(text: trimmedQuery, catalogReady: catalog.isLoaded)) {
            await runSearch(trimmedQuery)
        }
        .task(id: collectionsKey) {
            await rebuildCollections()
        }
        .onAppear {
            consumeRouterQuery()
            consumeAddIntent()
        }
        .onChange(of: router.searchQuery) { _, newValue in
            if newValue != nil { consumeRouterQuery() }
        }
        .onChange(of: router.addBookIntent) { _, newValue in
            if newValue != nil { consumeAddIntent() }
        }
        .sheet(item: $manualDraft) { draft in
            AddBookManuallyView(draft: draft)
        }
        .sheet(item: $quickAdd) { request in
            QuickAddSheet(
                request: request,
                shelf: store.shelf(of: request.book.id),
                wpm: store.wpm,
                onChoose: { choice in applyQuickAdd(request.book, choice) },
                onOpen: { router.searchPath.append(BookRoute(book: request.book)) }
            )
        }
        .sheet(isPresented: $showsScanner, onDismiss: presentScanOutcome) {
            ISBNScanSheet { outcome in
                scanOutcome = outcome
            }
        }
        .sheet(isPresented: $showsLibrarian) {
            LibrarianScreen()
        }
        .sheet(isPresented: $showsDeck) {
            SwipeDeckScreen()
        }
    }

    // MARK: Browse

    @ViewBuilder
    private func browse(_ proxy: ScrollViewProxy) -> some View {
        if !catalog.isLoaded {
            searching("Opening the catalog…")
        } else if !collectionsBuilt {
            searching("Setting out the shelves…")
        } else if collections.isEmpty {
            EmptyState(
                title: "Look up a book.",
                message: "Type a title or an author to see how long it takes at your pace."
            )
        } else {
            // "Loved by readers" is the cold-start row; any other personal row means Leaf has learned something.
            if !collections.contains(where: { $0.kind == .personal && $0.id != "loved" }) {
                SearchFrontTableNote {
                    router.searchPath.append(TasteRoute())
                }
                .padding(.top, Space.s)
            }
            LibrarianBanner {
                showsLibrarian = true
            }
            .padding(.top, Space.s)
            DeckBanner(covers: Array(collections.first?.books.prefix(3) ?? [])) {
                showsDeck = true
            }
            .padding(.top, Space.s)
            .padding(.bottom, Space.l)
            Section {
                ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                    SearchShelfRow(
                        collection: collection,
                        kind: SearchShelfKind(collection),
                        isFirst: index == 0,
                        wpm: store.wpm,
                        shelfOf: { store.shelf(of: $0) },
                        onAdd: { book, shelf, front in applyQuickAdd(book, Self.choice(shelf, atFront: front), feel: .keep) },
                        onDismiss: { dismiss($0) }
                    )
                    .id(collection.id)
                }
                OpenLibraryCredit()
                manualAddLink
            } header: {
                SearchJumpBar(categories: jumpCategories) { category in
                    guard let target = collections.first(where: { SearchShelfKind($0).category == category }) else { return }
                    withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(target.id, anchor: .top)
                    }
                }
                .padding(.bottom, Space.l)
            }
        }
    }

    /// The jump bar offers only the kinds of row there are today.
    private var jumpCategories: [SearchShelfKind.Category] {
        let present = Set(collections.map { SearchShelfKind($0).category })
        return SearchShelfKind.Category.allCases.filter { present.contains($0) }
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
        if isTypingISBN {
            Text("Keep going: an ISBN has 10 or 13 digits, on the back cover by the barcode or on the copyright page.")
                .canopyText(.body, color: Canopy.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Canopy.Space.l)
            manualAddLink
        } else if books.isEmpty {
            if phase == .loading {
                searching(ISBN.parse(trimmedQuery) == nil ? "Searching…" : "Looking up the ISBN…")
            } else {
                EmptyState(
                    title: "Nothing matches “\(trimmedQuery)”.",
                    message: emptyMessage,
                    actionTitle: "Add it by hand"
                ) {
                    manualDraft = draftFromQuery
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
                            onAdd: { shelf, front in applyQuickAdd(book, Self.choice(shelf, atFront: front), feel: .keep) },
                            onQuickAdd: { tapAdd(book) },
                            onOptions: { quickAdd = QuickAddRequest(book: book) }
                        )
                        Rectangle()
                            .fill(Canopy.separator)
                            .frame(height: 1)
                            .padding(.leading, BookCover.Size.s.width + Canopy.Space.l)
                    }
                    .canopyFocusInTransition()
                }
            }
            .animation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion), value: books.map(\.id))
            manualAddLink
        }
    }

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Canopy.Space.s) {
                Text(resultsEyebrow)
                    .canopyText(.label)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Canopy.Space.s)
                if phase == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Searching Open Library")
                }
            }
            Rectangle()
                .fill(Canopy.separator)
                .frame(height: 1)
            if phase == .offline {
                Text("Open Library couldn’t be reached, so these are the books on this device.")
                    .canopyText(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Canopy.Space.xs)
            }
        }
        .padding(.bottom, Canopy.Space.s)
    }

    private var resultsEyebrow: String {
        if isTypingISBN { return "ISBN" }
        if ISBN.parse(trimmedQuery) != nil, phase == .live { return "Found by ISBN" }
        switch phase {
        case .live where remoteQuery == trimmedQuery: return "From Open Library"
        case .offline: return "Offline, books on this device"
        default: return "On this device"
        }
    }

    private func searching(_ text: String) -> some View {
        HStack(spacing: Canopy.Space.s) {
            ProgressView()
            Text(text)
                .canopyText(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Canopy.Space.xxl)
        .accessibilityElement(children: .combine)
    }

    private var manualAddLink: some View {
        GlassEffectContainer(spacing: Canopy.Space.m) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Canopy.Space.m) {
                    manualAddButton
                    scanButton
                }
                VStack(spacing: Canopy.Space.m) {
                    manualAddButton
                    scanButton
                }
            }
        }
        .padding(.top, Canopy.Space.xl)
    }

    private var manualAddButton: some View {
        CanopyGlassButton("Add by hand", systemImage: "square.and.pencil", accent: .forest, compact: true) {
            manualDraft = draftFromQuery
        }
        .accessibilityHint("For a book that isn’t listed")
    }

    private var scanButton: some View {
        CanopyGlassButton("Scan a barcode", systemImage: "barcode.viewfinder", accent: .forest, compact: true) {
            showsScanner = true
        }
    }

    private var emptyMessage: String {
        if let isbnMatch { return "Open Library knows “\(isbnMatch.title)” but not its page count. Add that and it’s yours." }
        if ISBN.parse(trimmedQuery) != nil {
            return phase == .offline
                ? "This edition isn’t among the books on this device; looking it up needs a connection."
                : "Open Library has no book with this ISBN."
        }
        return phase == .offline ? "You’re offline, so only books on this device were searched." : ""
    }

    /// The form starts from what is known: an ISBN match, or the words typed as a title. Never from a bare ISBN.
    private var draftFromQuery: ManualBookDraft {
        if let isbnMatch {
            return ManualBookDraft(title: isbnMatch.title, author: isbnMatch.author ?? "", pages: isbnMatch.pages, year: isbnMatch.year)
        }
        let text = trimmedQuery
        guard !text.isEmpty, !ISBN.looksLikeISBN(text) else { return ManualBookDraft() }
        return ManualBookDraft(title: text)
    }

    /// A few digits in: not yet an ISBN, and not worth searching titles for.
    private var isTypingISBN: Bool {
        ISBN.looksLikeISBN(trimmedQuery) && ISBN.parse(trimmedQuery) == nil
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
        isbnMatch = nil
        if let isbn = ISBN.parse(text) {
            await lookUpISBN(isbn, typed: text)
            return
        }
        if ISBN.looksLikeISBN(text) {
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
                CanopyFeel.play(.warning)
            }
        }
    }

    /// A typed ISBN skips the title search: the catalog answers offline when it lists the edition, else Open Library.
    private func lookUpISBN(_ isbn: String, typed text: String) async {
        localResults = []
        remoteResults = []
        phase = .loading
        let result = await ISBNLookup.resolve(isbn, catalog: catalog)
        guard !Task.isCancelled else { return }
        remoteQuery = text
        switch result {
        case .found(let book):
            remoteResults = [book]
            phase = .live
        case .partial(let match):
            isbnMatch = match
            phase = .live
        case .notFound:
            phase = .live
        case .offline:
            phase = .offline
        }
    }

    // MARK: Actions

    /// The result row's `+` (REDESIGN §4.3): a book not yet in the library goes to Up next in one tap, with a light
    /// page-turn and the Undo toast. A book already on a shelf opens the sheet instead, which shows where it is.
    private func tapAdd(_ book: Book) {
        if store.shelf(of: book.id) == nil {
            applyQuickAdd(book, .wantToRead(next: true), feel: .pageLogged)
        } else {
            CanopyFeel.play(.tap)
            quickAdd = QuickAddRequest(book: book)
        }
    }

    private static func choice(_ shelf: Shelf, atFront: Bool) -> QuickAddChoice {
        switch shelf {
        case .reading: return .startReading
        case .finished: return .alreadyRead
        case .toRead, .paused: return .wantToRead(next: atFront)
        }
    }

    /// Puts a book where the reader chose and offers Undo. `feel` is played here when the control that asked has not
    /// already played one (the sheet's buttons have); Already read plays the shelf's own finish moment.
    private func applyQuickAdd(_ book: Book, _ choice: QuickAddChoice, feel: CanopyFeel? = nil) {
        let previous = store.shelf(of: book.id)
        let shelf: Shelf
        switch choice {
        case .startReading:
            add(book, to: .reading, atFront: false)
            shelf = .reading
        case .wantToRead(let next):
            add(book, to: .toRead, atFront: next)
            shelf = .toRead
        case .alreadyRead:
            LibraryShelfActions.markFinished(book, store: store, readBeforeLeaf: true)
            shelf = .finished
        }
        if let feel, choice != .alreadyRead { CanopyFeel.play(feel) }
        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
            undoBook = nil
            lastAdd = AddedNote(book: book, previous: previous, shelf: shelf)
        }
    }

    /// Takes an add back: off the shelves if it was new, otherwise back where it was.
    private func undoAdd(_ note: AddedNote) {
        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
            if let previous = note.previous {
                store.move(note.book.id, to: previous)
            } else {
                store.remove(note.book.id)
            }
            lastAdd = nil
        }
    }

    /// After the scanner's sheet is gone: the found book in the quick-add sheet, or the form with what was learned.
    private func presentScanOutcome() {
        guard let outcome = scanOutcome else { return }
        scanOutcome = nil
        switch outcome {
        case .found(let book): quickAdd = QuickAddRequest(book: book, note: "Found from the barcode")
        case .addByHand(let draft): manualDraft = draft
        }
    }

    /// The Library's add menu and the screenshot runs: open ready to type, or straight to the scanner or the form.
    private func consumeAddIntent() {
        guard let intent = router.addBookIntent else { return }
        router.addBookIntent = nil
        switch intent {
        case .search:
            // Let the tab finish appearing first, or the field doesn't take focus.
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                searchActive = true
            }
        case .scan: showsScanner = true
        case .manual: manualDraft = ManualBookDraft()
        }
    }

    /// Adds a book to a shelf, or moves it if it is already in the library. A book that is already in
    /// the library is moved rather than re-added, so a page count the reader edited is never overwritten.
    private func add(_ book: Book, to shelf: Shelf, atFront: Bool, feel: CanopyFeel? = nil) {
        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
            if store.item(book.id) == nil {
                store.add(book, to: shelf)
            } else {
                store.move(book.id, to: shelf)
            }
            if atFront { store.moveToFront(book.id) }
        }
        if let feel { CanopyFeel.play(feel) }
    }

    /// "Not for me": the book leaves every row and the next suggestions lean away from it. Undo for a few seconds.
    private func dismiss(_ book: Book) {
        Haptics.shared.tap()
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            store.dismiss(book.id)
            lastAdd = nil
            undoBook = book
            // Gone from every row at once; the rebuild that follows the dismissal takes a moment.
            for index in collections.indices {
                collections[index].books.removeAll { $0.id == book.id }
            }
        }
    }

    /// Screenshots: once the rows exist, scroll to a kind of row, open a whole row, or show the Undo toast.
    private func applyStage(_ proxy: ScrollViewProxy) async {
        guard collectionsBuilt, let stage = router.searchStage else { return }
        router.searchStage = nil
        try? await Task.sleep(for: .milliseconds(500))
        let styles: [String: SearchShelfKind.Style] = ["series": .series, "author": .author, "time": .time, "seasonal": .seasonal]
        switch stage {
        case "seeall":
            if let first = collections.first { router.searchPath.append(first) }
        case "undo":
            if let book = collections.first?.books.first { dismiss(book) }
        case "quickadd":
            quickAdd = QuickAddRequest(book: catalog.search("the name of the wind", limit: 1).first ?? DemoData.dune)
        case "added":
            toastSeconds = 60
            applyQuickAdd(catalog.search("the name of the wind", limit: 1).first ?? DemoData.dune, .wantToRead(next: true))
        case "scan":
            showsScanner = true
        case "manual":
            manualDraft = ManualBookDraft(title: "The Thursday Murder Club", author: "Richard Osman")
        default:
            if let style = styles[stage], let row = collections.first(where: { SearchShelfKind($0).style == style }) {
                proxy.scrollTo(row.id, anchor: .top)
            }
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
