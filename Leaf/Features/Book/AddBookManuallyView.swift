import SwiftUI

/// Adds a book by hand (DESIGN.md §6): Title, Author, Pages and an optional Year under a live
/// generated cover that updates as you type, then "Start reading" or "Add to To read".
/// Presented as a sheet; it carries its own navigation bar with Cancel.
struct AddBookManuallyView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var title = ""
    @State private var author = ""
    @State private var pagesText = ""
    @State private var yearText = ""
    /// Fixed for the life of the form, so the cover's palette doesn't change as you type.
    @State private var draftID = "custom-" + UUID().uuidString
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case title, author, pages, year
    }

    init() {}

    // MARK: Parsed input

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedAuthor: String { author.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var pages: Int? {
        guard let value = Int(pagesText), value >= 1 else { return nil }
        return value
    }
    private var year: Int? {
        guard let value = Int(yearText), (1000...2100).contains(value) else { return nil }
        return value
    }
    private var isValid: Bool { !trimmedTitle.isEmpty && pages != nil }

    /// What the cover shows while the form is half filled in.
    private var draft: Book {
        Book(
            id: draftID,
            title: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle,
            author: trimmedAuthor.isEmpty ? "Author" : trimmedAuthor,
            year: year,
            pages: pages ?? 300
        )
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.xxl) {
                    BookCover(book: draft, size: .l)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.l)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Space.xl) {
                        field("Title", text: $title, prompt: "The name on the spine", focus: .title)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                            .onSubmit { focus = .author }
                        field("Author", text: $author, prompt: "Who wrote it", focus: .author)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                            .onSubmit { focus = .pages }
                        numbers
                    }
                }
                .leafMargins()
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .paperBackground()
            .navigationTitle("Add a book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focus = nil
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                buttons
            }
            .onChange(of: pagesText) { _, new in
                let digits = Self.digits(new, limit: 5)
                if digits != new { pagesText = digits }
            }
            .onChange(of: yearText) { _, new in
                let digits = Self.digits(new, limit: 4)
                if digits != new { yearText = digits }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
    }

    /// Pages and Year side by side, stacked at accessibility sizes.
    @ViewBuilder
    private var numbers: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xl))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Space.xl))
        layout {
            field("Pages", text: $pagesText, prompt: "310", focus: .pages, keyboard: .numberPad)
            field("Year (optional)", text: $yearText, prompt: "1937", focus: .year, keyboard: .numberPad)
        }
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        prompt: String,
        focus field: Field,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow(label)
            TextField(prompt, text: text)
                .font(LeafType.title)
                .foregroundStyle(Color.ink)
                .keyboardType(keyboard)
                .focused($focus, equals: field)
                .padding(.vertical, Space.s)
                .accessibilityLabel(label)
            Hairline(color: focus == field ? .ink : .hairlineStrong)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttons: some View {
        GlassEffectContainer(spacing: Space.m) {
            VStack(spacing: Space.m) {
                PrimaryGlassButton("Start reading", systemImage: "play.fill") {
                    add(to: .reading)
                }
                .disabled(!isValid)
                SecondaryGlassButton("Add to To read", systemImage: "plus", compact: true) {
                    add(to: .toRead)
                }
                .disabled(!isValid)
            }
        }
        .leafMargins()
        .padding(.top, Space.s)
        .padding(.bottom, Space.s)
    }

    // MARK: Actions

    private func add(to shelf: Shelf) {
        guard isValid, let pages else { return }
        let book = Book(
            id: draftID,
            title: trimmedTitle,
            author: trimmedAuthor.isEmpty ? "Unknown author" : trimmedAuthor,
            year: year,
            pages: pages
        )
        store.add(book, to: shelf)
        router.libraryShelf = shelf
        Haptics.shared.success()
        dismiss()
    }

    private static func digits(_ text: String, limit: Int) -> String {
        String(text.filter { "0123456789".contains($0) }.prefix(limit))
    }
}

#Preview("Add a book") {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return AddBookManuallyView()
        .environment(store)
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
