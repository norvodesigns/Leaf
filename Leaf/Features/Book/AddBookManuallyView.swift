import SwiftUI

/// Adds a book by hand (Canopy): Title, Author, Pages and an optional Year under a live
/// generated cover that updates as you type, then "Start reading" or "Want to read".
/// Presented as a sheet; it carries its own navigation bar with Cancel. It opens with whatever is already known
/// (what was typed in Search, or what a barcode found) and the cursor in the first empty field, so most books
/// need only a page count.
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

    init(draft: ManualBookDraft = ManualBookDraft()) {
        _title = State(initialValue: draft.title)
        _author = State(initialValue: draft.author)
        _pagesText = State(initialValue: draft.pages.map { String($0) } ?? "")
        _yearText = State(initialValue: draft.year.map { String($0) } ?? "")
    }

    /// The first field still empty; the year is optional, so it never asks for focus.
    private var firstEmptyField: Field {
        if trimmedTitle.isEmpty { return .title }
        if trimmedAuthor.isEmpty { return .author }
        return .pages
    }

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
                VStack(spacing: Canopy.Space.xl) {
                    // Medium, so the whole form still fits above the keyboard.
                    BookCover(book: draft, size: .m)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Canopy.Space.l)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Canopy.Space.l) {
                        field("Title", text: $title, prompt: "The name on the spine", focus: .title, font: CanopyType.bookTitle.font)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                            .onSubmit { focus = .author }
                        field("Author", text: $author, prompt: "Who wrote it", focus: .author)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                            .onSubmit { focus = .pages }
                        numbers
                    }
                    .canopyCard()
                }
                .padding(.horizontal, Canopy.Space.margin)
                .padding(.bottom, Canopy.Space.xl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .canopyBackdrop()
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
            .task {
                // Wait for the sheet to settle, or the keyboard fights the presentation.
                try? await Task.sleep(for: .milliseconds(450))
                if focus == nil { focus = firstEmptyField }
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
    }

    /// Pages and Year side by side, stacked at accessibility sizes.
    @ViewBuilder
    private var numbers: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Canopy.Space.l))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Canopy.Space.l))
        layout {
            field("Pages", text: $pagesText, prompt: "310", focus: .pages, keyboard: .numberPad, font: Self.numberFont)
            field("Year (optional)", text: $yearText, prompt: "1937", focus: .year, keyboard: .numberPad, font: Self.numberFont)
        }
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        prompt: String,
        focus field: Field,
        keyboard: UIKeyboardType = .default,
        font: Font = .system(.title3, weight: .medium)
    ) -> some View {
        VStack(alignment: .leading, spacing: Canopy.Space.xs) {
            Text(label).canopyText(.label)
            TextField(prompt, text: text)
                .font(font)
                .foregroundStyle(Canopy.text)
                .keyboardType(keyboard)
                .focused($focus, equals: field)
                .padding(.vertical, Canopy.Space.s)
                .frame(minHeight: Canopy.Space.hitTarget)
                .accessibilityLabel(label)
            Rectangle()
                .fill(focus == field ? CanopyAccent.forest.color : Canopy.separator)
                .frame(height: focus == field ? 2 : 1)
                .animation(Canopy.Motion.snappy, value: focus == field)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttons: some View {
        GlassEffectContainer(spacing: Canopy.Space.m) {
            VStack(spacing: Canopy.Space.m) {
                CanopyHeroButton("Start reading", systemImage: "play.fill", feel: .startNow) {
                    add(to: .reading)
                }
                .disabled(!isValid)
                CanopyGlassButton("Want to read", systemImage: "bookmark", accent: .forest, compact: true, feel: .keep) {
                    add(to: .toRead)
                }
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.4)
            }
        }
        .padding(.horizontal, Canopy.Space.margin)
        .padding(.vertical, Canopy.Space.s)
    }

    /// Numbers are rounded (Canopy §4).
    private static let numberFont = Font.system(.title3, design: .rounded, weight: .medium).monospacedDigit()

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
