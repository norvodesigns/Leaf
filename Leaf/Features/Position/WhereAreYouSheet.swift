import SwiftUI

/// The four answers to "Where are you?".
enum PositionChoice: String, CaseIterable, Identifiable, Hashable {
    case justStarting, page, percent, alreadyRead

    var id: String { rawValue }

    var title: String {
        switch self {
        case .justStarting: "Just starting"
        case .page: "I’m on a page"
        case .percent: "I’m a percent in"
        case .alreadyRead: "Already read it"
        }
    }

    var systemImage: String {
        switch self {
        case .justStarting: "book.closed"
        case .page: "bookmark"
        case .percent: "percent"
        case .alreadyRead: "checkmark.seal"
        }
    }
}

/// "Where are you?" (NEXT.md section 3). Progress is the whole model of the app, so this is big and plain: four
/// answers as tiles, then the control for the chosen one. A page is set with the `PageScrubber` and its big numeral
/// (with a typed fallback), a percentage with a 0–100 ruler (for e-readers; the book then keeps showing
/// percentages), and "already read" files the book under Finished with an optional date.
///
/// Shown from `MainTabs` for `router.positionRequest`: before a book's first session, from Today's page chip and
/// nudge, and from book detail. When the request says so, reading starts from the answer.
struct WhereAreYouSheet: View {
    let request: PositionRequest
    let book: Book
    let now: Date

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var choice: PositionChoice
    @State private var page: Int
    @State private var percent: Int
    @State private var finishedOn: Date
    @State private var remembersDate = true
    @State private var typedPage = ""
    @FocusState private var isTyping: Bool
    /// Where Leaf already has the reader, shown as the scrubber's "est." tag.
    private let knownPage: Int?

    init(request: PositionRequest, item: LibraryItem, now: Date) {
        self.request = request
        self.book = item.book
        self.now = now
        let pages = max(1, item.book.pages)
        let current = min(max(0, item.currentPage), pages)
        knownPage = current > 0 ? current : nil
        let opening: PositionChoice
        if let asked = request.opensOn {
            opening = asked
        } else if current > 0 {
            opening = item.progressMode == .percent ? .percent : .page
        } else {
            opening = .justStarting
        }
        _choice = State(initialValue: opening)
        _page = State(initialValue: current > 0 ? current : min(pages, max(1, pages / 3)))
        _percent = State(initialValue: current > 0 ? item.percent : 30)
        _finishedOn = State(initialValue: now)
    }

    private var pages: Int { max(1, book.pages) }

    private var startsReading: Bool {
        if case .startSession = request.then { return true }
        return false
    }

    private var pageFromPercent: Int { LibraryItem.page(forPercent: Double(percent), pages: pages) }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xxl) {
                header
                choices
                control
                    .frame(maxWidth: .infinity)
                    .transition(Motion.transition(.opacity, reduceMotion: reduceMotion))
                    .id(choice)
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isTyping = false }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Space.s) {
            Eyebrow(startsReading ? "Before you begin" : "Your place")
            Text("Where are you in \(Text(book.title).italic())?")
                .leafStyle(.masthead)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(book.author)
                .leafStyle(.author)
                .multilineTextAlignment(.center)
            Text("Every date Leaf plans starts from here, so it’s worth a moment.")
                .leafStyle(.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Choices

    private var choices: some View {
        let columns: [GridItem] = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)]
        return LazyVGrid(columns: columns, spacing: Space.s) {
            ForEach(PositionChoice.allCases) { option in
                choiceTile(option)
            }
        }
    }

    private func choiceTile(_ option: PositionChoice) -> some View {
        let isSelected = option == choice
        let shape = Radius.shape(Radius.tile)
        return Button {
            select(option)
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(option.title)
                    .leafFont(.ui)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.ink : Color.inkSecondary)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(isSelected ? Color.accentSoft : Color.paperRaised, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? Color.accent : Color.hairline, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private func select(_ option: PositionChoice) {
        guard option != choice else { return }
        Haptics.shared.selection()
        isTyping = false
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            choice = option
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var control: some View {
        switch choice {
        case .justStarting:
            startingControl
        case .page:
            pageControl
        case .percent:
            percentControl
        case .alreadyRead:
            readControl
        }
    }

    private var startingControl: some View {
        VStack(spacing: Space.m) {
            VStack(spacing: -10) {
                Text("1")
                    .leafStyle(.heroNumeral)
                Eyebrow("Page one")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page one")
            Text("A fresh start. Leaf plans from the first page, and learns your pace from your first session.")
                .leafStyle(.pullQuote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pageControl: some View {
        VStack(spacing: Space.m) {
            Text("\(page)")
                .leafStyle(.heroNumeral)
                .contentTransition(.numericText(value: Double(page)))
                .leafAnimation(Motion.paper, value: page)
                .accessibilityHidden(true)
            Text("of \(LeafFormat.number(book.pages)) pages · \(percentText(forPage: page)) read")
                .leafStyle(.caption)
            PageScrubber(page: $page, range: 0...pages, estimate: knownPage)
            typedField
        }
    }

    private var typedField: some View {
        HStack(spacing: Space.s) {
            Text("Or type the page")
                .leafStyle(.caption)
            TextField("142", text: $typedPage)
                .keyboardType(.numberPad)
                .font(LeafType.data)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .frame(width: 88)
                .padding(.vertical, Space.s)
                .background(Color.paperSunken, in: .capsule)
                .focused($isTyping)
                .accessibilityLabel("Page number")
                .onChange(of: typedPage) { _, text in
                    guard let value = Int(text.filter(\.isNumber)) else { return }
                    page = min(max(0, value), pages)
                }
        }
        .frame(minHeight: Space.hitTarget)
    }

    private var percentControl: some View {
        VStack(spacing: Space.m) {
            Text("\(percent)%")
                .leafStyle(.heroNumeral)
                .contentTransition(.numericText(value: Double(percent)))
                .leafAnimation(Motion.paper, value: percent)
                .accessibilityHidden(true)
            Text("about p. \(pageFromPercent) of \(LeafFormat.number(book.pages))")
                .leafStyle(.caption)
            TickRuler(
                range: 0...100,
                value: $percent,
                spacing: 8,
                majorEvery: 5,
                labels: [0, 25, 50, 75, 100],
                voiceOverLabel: "Percent read",
                adjustStep: 1,
                valueDescription: { "\($0) percent" }
            )
            Text("For e-readers: Leaf keeps showing this book as a percentage.")
                .leafStyle(.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readControl: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("It moves to your Finished shelf, and counts toward the year if you finished it this year.")
                .leafStyle(.body, color: .inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $remembersDate.animation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion))) {
                Text("I remember when I finished")
                    .leafStyle(.uiBody)
            }
            .tint(Color.accent)
            if remembersDate {
                DatePicker("Finished on", selection: $finishedOn, in: ...now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Color.accent)
            }
        }
    }

    private func percentText(forPage page: Int) -> String {
        "\(Int((Double(page) / Double(pages) * 100).rounded()))%"
    }

    // MARK: Actions

    private var primaryTitle: String {
        switch choice {
        case .justStarting: return startsReading ? "Start from page one" : "I’m at the beginning"
        case .page: return startsReading ? "Start from p. \(page)" : "Save p. \(page)"
        case .percent: return startsReading ? "Start from \(percent)%" : "Save \(percent)%"
        case .alreadyRead: return "Move to Finished"
        }
    }

    private var actions: some View {
        VStack(spacing: Space.xxs) {
            PrimaryGlassButton(primaryTitle, playsHaptic: false) {
                confirm()
            }
            TextButton("Not now", color: .inkSecondary) {
                Haptics.shared.tap()
                dismiss()
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.m)
        .background(Color.paper)
    }

    private func confirm() {
        let position: StartingPosition
        switch choice {
        case .justStarting: position = .justStarting
        case .page: position = .page(page)
        case .percent: position = .percent(Double(percent))
        case .alreadyRead: position = .alreadyRead(on: remembersDate ? finishedOn : nil)
        }
        if choice == .alreadyRead {
            Haptics.shared.success()
        } else {
            Haptics.shared.play(.pageTurn)
        }
        store.apply(position, to: book.id)
        dismiss()

        guard choice != .alreadyRead, case .startSession(let source, let teaID, let goalSeconds) = request.then else { return }
        let store = store
        let router = router
        let bookID = book.id
        Task { @MainActor in
            // Let the sheet leave before the session cover goes up.
            try? await Task.sleep(for: .milliseconds(550))
            ReadingSessionLauncher.start(
                bookID: bookID, store: store, router: router, from: source,
                teaID: teaID, goalSeconds: goalSeconds, asksPosition: false
            )
        }
    }
}

// MARK: - Previews

@MainActor
private func positionPreviewStore() -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make(scenario: .newBook))
    return store
}

#Preview("Where are you? · first start") {
    let store = positionPreviewStore()
    let item = store.item(DemoData.piranesi.id)!
    return Color.paper
        .sheet(isPresented: .constant(true)) {
            WhereAreYouSheet(request: PositionRequest(bookID: item.id, then: .startSession(source: "hero", teaID: nil, goalSeconds: nil)), item: item, now: Date())
        }
        .environment(store)
        .environment(AppRouter())
}

#Preview("Where are you? · page, dark") {
    let store = positionPreviewStore()
    let item = store.item(DemoData.hobbit.id)!
    return Color.paper
        .sheet(isPresented: .constant(true)) {
            WhereAreYouSheet(request: PositionRequest(bookID: item.id), item: item, now: Date())
        }
        .environment(store)
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
