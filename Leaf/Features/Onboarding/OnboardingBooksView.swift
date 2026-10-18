import SwiftUI

/// Step viii: inline search over a three-column grid of "Popular first reads". A tap toggles a
/// `checkmark.circle.fill` badge. The first pick will go to Reading (it wears the cover ribbon) and
/// the rest to To read. The flow owns `picks` so they survive going back.
struct OnboardingBooksView: View {
    @Binding var picks: [Book]
    let wpm: Double
    /// Books already on a shelf (a repeat of onboarding): they aren't offered again.
    let existingIDs: Set<String>
    /// Screenshots and previews that land here directly start with three picks made.
    var stagesPicks = false

    @Environment(BookCatalog.self) private var catalog
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var popular: [Book] = []
    @State private var didStagePicks = false
    @FocusState private var searchIsFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    private var results: [Book] {
        guard isSearching else { return [] }
        return catalog.search(trimmedQuery, limit: 24).filter { !existingIDs.contains($0.id) }
    }

    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: Space.m, alignment: .top), count: count)
    }

    /// The heading steps aside while the reader searches, so results have room above the keyboard.
    private var showsHeading: Bool { !searchIsFocused && !isSearching }

    var body: some View {
        OnboardingPage(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: Space.xl) {
                if showsHeading {
                    OnboardingHeading(
                        title: "Pick a few first reads.",
                        message: "Tap what you’d like to read. The first goes on your desk, the rest wait their turn.",
                        centered: false
                    )
                    .transition(.opacity)
                }
                searchField
                section
            }
            .leafAnimation(Motion.paper, value: showsHeading)
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            await catalog.load()
            popular = Self.popularFirstReads(catalog: catalog, wpm: wpm, excluding: existingIDs)
            if stagesPicks, !didStagePicks, picks.isEmpty {
                didStagePicks = true
                picks = Array(popular.prefix(3))
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.inkTertiary)
                .accessibilityHidden(true)
            TextField("Title or author", text: $query)
                .textFieldStyle(.plain)
                .font(LeafType.uiBody)
                .foregroundStyle(Color.ink)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($searchIsFocused)
                .onSubmit { searchIsFocused = false }
            if !query.isEmpty {
                Button {
                    Haptics.shared.tap()
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.inkTertiary)
                        .frame(width: Space.hitTarget, height: Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.trailing, -Space.m)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.m)
        .frame(minHeight: Space.hitTarget)
        .background(Color.paperSunken, in: .capsule)
    }

    // MARK: - Grid

    @ViewBuilder
    private var section: some View {
        if isSearching {
            let found = results
            if found.isEmpty {
                Text(catalog.isLoaded ? "Nothing here matches “\(trimmedQuery)”. You can add it by hand later." : "Looking through the catalog…")
                    .leafStyle(.body, color: .inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader("Results", topSpacing: 0)
                    grid(found)
                        .padding(.top, Space.s)
                }
            }
        } else if popular.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Popular first reads", topSpacing: 0)
                HStack(spacing: Space.s) {
                    ProgressView()
                    Text(catalog.isLoaded ? "Search above to add a book, or skip for now." : "Opening the catalog…")
                        .leafStyle(.caption)
                }
                .padding(.top, Space.l)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Popular first reads", topSpacing: 0)
                grid(popular)
                    .padding(.top, Space.s)
            }
        }
    }

    private func grid(_ books: [Book]) -> some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: Space.l) {
            ForEach(books) { book in
                OnboardingBookCell(
                    book: book,
                    pickIndex: picks.firstIndex { $0.id == book.id }
                ) {
                    toggle(book)
                }
            }
        }
    }

    private func toggle(_ book: Book) {
        Haptics.shared.selection()
        withAnimation(Motion.resolved(Motion.glass, reduceMotion: reduceMotion)) {
            if let index = picks.firstIndex(where: { $0.id == book.id }) {
                picks.remove(at: index)
            } else {
                picks.append(book)
            }
        }
    }

    /// The "Popular first reads" table: the catalog's best-loved books, then a few short ones,
    /// twelve in all so the grid ends on a full row.
    static func popularFirstReads(catalog: BookCatalog, wpm: Double, excluding ids: Set<String>) -> [Book] {
        catalog.starterBooks(wpm: wpm, excluding: ids, count: 12)
    }
}

/// One cover in the grid: the cover, a badge when picked, the title beneath.
private struct OnboardingBookCell: View {
    let book: Book
    /// Position in the reader's picks, or nil. The first pick wears the ribbon.
    let pickIndex: Int?
    let action: () -> Void

    private var isPicked: Bool { pickIndex != nil }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s) {
                BookCover(book: book, size: .m, ribbon: pickIndex == 0)
                    .overlay(alignment: .topTrailing) {
                        if isPicked {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.paper, Color.accent)
                                .font(.system(size: 24))
                                .background(Circle().fill(Color.paper).padding(1))
                                .offset(x: 8, y: -8)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                    // Room for the ribbon tail, so a pick doesn't move the title.
                    .padding(.bottom, BookCover.Size.m.ribbonTail)
                Text(book.title)
                    .leafStyle(.caption, color: isPicked ? .ink : .inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .leafAnimation(Motion.glass, value: isPicked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title) by \(book.author)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isPicked ? "Double tap to remove" : "Double tap to add")
        .accessibilityAddTraits(isPicked ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private var accessibilityValue: String {
        switch pickIndex {
        case .none: "Not picked"
        case .some(0): "Picked, to read first"
        case .some: "Picked"
        }
    }
}
