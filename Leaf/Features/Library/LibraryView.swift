import SwiftUI

/// The Library tab (DESIGN.md §6): the large title, a trailing `plus` that opens the by-hand form,
/// and a shelf switcher over Reading, To read and Finished that follows `router.libraryShelf`.
/// Lives inside `MainTabs`' navigation stack; book rows push `BookRoute`.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var showsAddSheet = false
    /// The book waiting on "Remove from Library?".
    @State private var pendingRemoval: Book?

    init() {}

    private var counts: [Shelf: Int] {
        [.reading: store.reading.count, .toRead: store.toRead.count, .finished: store.finished.count]
    }

    var body: some View {
        @Bindable var router = router
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShelfSwitcher(selection: $router.libraryShelf, counts: counts)
                    .padding(.top, Space.s)
                    .padding(.bottom, Space.m)
                shelf
            }
            .leafMargins()
            .padding(.bottom, Space.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.shared.tap()
                    showsAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add a book by hand")
            }
        }
        .sheet(isPresented: $showsAddSheet) {
            AddBookManuallyView()
        }
        .confirmationDialog(
            "Remove from Library?",
            isPresented: removalBinding,
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { book in
            Button("Remove", role: .destructive) {
                LibraryShelfActions.remove(book.id, store: store)
            }
        } message: { book in
            Text("“\(book.title)” will leave your shelves and your plan.")
        }
    }

    // MARK: Shelves

    @ViewBuilder
    private var shelf: some View {
        switch router.libraryShelf {
        case .reading, .paused:
            LibraryReadingShelf(onRemove: requestRemoval)
                .transition(.opacity)
        case .toRead:
            LibraryQueueShelf(onRemove: requestRemoval)
                .transition(.opacity)
        case .finished:
            LibraryFinishedShelf(onRemove: requestRemoval)
                .transition(.opacity)
        }
    }

    private func requestRemoval(_ book: Book) {
        pendingRemoval = book
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { isPresented in
                if !isPresented { pendingRemoval = nil }
            }
        )
    }
}

// MARK: - Previews

@MainActor
private func libraryPreviewStore() -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return store
}

#Preview("Library · Reading") {
    NavigationStack {
        LibraryView()
            .navigationDestination(for: BookRoute.self) { route in
                BookDetailView(book: route.book)
            }
    }
    .environment(libraryPreviewStore())
    .environment(AppRouter())
    .environment(BookCatalog.shared)
}

#Preview("Library · To read") {
    let router = AppRouter()
    router.libraryShelf = .toRead
    return NavigationStack {
        LibraryView()
            .navigationDestination(for: BookRoute.self) { route in
                BookDetailView(book: route.book)
            }
    }
    .environment(libraryPreviewStore())
    .environment(router)
    .environment(BookCatalog.shared)
}

#Preview("Library · Finished") {
    let router = AppRouter()
    router.libraryShelf = .finished
    return NavigationStack {
        LibraryView()
            .navigationDestination(for: BookRoute.self) { route in
                BookDetailView(book: route.book)
            }
    }
    .environment(libraryPreviewStore())
    .environment(router)
    .environment(BookCatalog.shared)
}

#Preview("Library · Empty") {
    NavigationStack {
        LibraryView()
    }
    .environment(LibraryStore(persistence: .ephemeral()))
    .environment(AppRouter())
    .environment(BookCatalog.shared)
}
