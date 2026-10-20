import SwiftUI

/// The Library tab (DESIGN.md §6): the large title, a trailing `plus` that opens the by-hand form, a segmented
/// switcher over Reading, To read and Finished that follows `router.libraryShelf`, and one plain line saying what the
/// shelf holds. Books set aside sit at the end of Reading rather than on a fourth tab.
/// Lives inside `MainTabs`' navigation stack; book rows push `BookRoute`.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showsAddSheet = false
    /// Finished books as a wall of spines instead of a grid of covers; remembered on this device.
    @AppStorage("library.finishedAsShelf") private var finishedAsShelf = false
    /// Screenshots show the wall without changing what the reader chose.
    @State private var stagedShelf: Bool?
    /// The book waiting on "Remove from Library?".
    @State private var pendingRemoval: Book?

    init() {}

    private var pausedCount: Int { store.data.items(on: .paused).count }

    private var showsShelfWall: Bool { stagedShelf ?? finishedAsShelf }

    /// What the shelf on screen holds, how many, and the one gesture worth knowing. Empty shelves say it themselves.
    private var caption: String? {
        switch router.libraryShelf {
        case .reading, .paused:
            let count = store.reading.count
            guard count > 0 else { return nil }
            let open = count == 1 ? "The book you're reading now" : "The \(count) books you're reading now"
            return pausedCount > 0 ? open + ". Books you've set aside wait below." : open + "."
        case .toRead:
            let count = store.toRead.count
            guard count > 0 else { return nil }
            return "\(count == 1 ? "One book" : "\(count) books") to read next, in the order Leaf plans them. Hold one to move it."
        case .finished:
            let count = store.finished.count
            guard count > 0 else { return nil }
            if showsShelfWall { return "A shelf for every year, in the order you finished them. Hold a spine to see when." }
            return count == 1 ? "The book you've finished." : "The \(count) books you've finished, newest first."
        }
    }

    var body: some View {
        @Bindable var router = router
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ShelfSwitcher(selection: $router.libraryShelf)
                        .padding(.top, Space.s)
                    if let caption {
                        Text(caption)
                            .leafStyle(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Space.s)
                            .contentTransition(.opacity)
                    }
                    shelf
                        .padding(.top, Space.l)
                }
                .leafMargins()
                .padding(.bottom, Space.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onAppear {
                showSetAsideIfAsked(proxy)
                if let stage = router.libraryStage {
                    stagedShelf = true
                    // A held spine or the poster is the wall's to stage.
                    if stage == "shelf" { router.libraryStage = nil }
                }
            }
            .onChange(of: router.libraryShelf) { _, _ in showSetAsideIfAsked(proxy) }
        }
        .paperBackground()
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if router.libraryShelf == .finished {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.shared.selection()
                        let next = !showsShelfWall
                        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                            stagedShelf = nil
                            finishedAsShelf = next
                        }
                    } label: {
                        Image(systemName: showsShelfWall ? "square.grid.3x2" : "books.vertical")
                    }
                    .accessibilityLabel(showsShelfWall ? "Show as covers" : "Show as a shelf")
                }
            }
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
            VStack(alignment: .leading, spacing: 0) {
                LibraryReadingShelf(onRemove: requestRemoval)
                if pausedCount > 0 {
                    SectionHeader("Set aside")
                        .id(Self.setAsideID)
                    LibraryPausedShelf(onRemove: requestRemoval)
                }
            }
            .transition(.opacity)
        case .toRead:
            LibraryQueueShelf(onRemove: requestRemoval)
                .transition(.opacity)
        case .finished:
            if showsShelfWall {
                LibraryShelfWall()
                    .transition(.opacity)
            } else {
                LibraryFinishedShelf(onRemove: requestRemoval)
                    .transition(.opacity)
            }
        }
    }

    private static let setAsideID = "library.setAside"

    /// Anything that asks for the old Paused shelf (a link, a screenshot stage) lands on Reading, at Set aside.
    private func showSetAsideIfAsked(_ proxy: ScrollViewProxy) {
        guard router.libraryShelf == .paused else { return }
        router.libraryShelf = .reading
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                proxy.scrollTo(Self.setAsideID, anchor: .top)
            }
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
