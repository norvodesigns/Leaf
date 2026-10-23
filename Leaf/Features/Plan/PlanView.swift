import SwiftUI

/// The Plan tab (docs/design/REDESIGN.md §4.2): today's reading times, each with its book and pages, then the forecast.
/// Insights, challenges and circles moved to You. The engines run once per change to the library in a `PlanDesk`, off
/// the main actor.
struct PlanView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var desk = PlanDesk()

    var body: some View {
        @Bindable var router = router
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Canopy.Space.section) {
                    PlanTimesCard()
                    if store.plan.books.isEmpty {
                        EmptyState(
                            title: "Nothing to forecast yet.",
                            message: "Add a book to Reading or Up next and Leaf will work out the odds.",
                            actionTitle: "Find a book"
                        ) {
                            router.tab = .search
                        }
                        .padding(.top, Space.xl)
                    } else {
                        ForecastPage(desk: desk)
                    }
                }
                .leafMargins()
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxl)
            }
            .task(id: StageKey(stage: router.planStage, ready: isReady)) {
                await scrollToStage(proxy)
            }
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.large)
        .task(id: PlanDeskKey(store: store)) {
            desk.refresh(from: store)
        }
        .sheet(item: router.planSheetBinding(on: .plan)) { sheet in
            PlanSheetHost(sheet: sheet, desk: desk)
        }
    }

    // MARK: Staging

    private struct StageKey: Equatable {
        var stage: String?
        var ready: Bool
    }

    private var isReady: Bool { desk.forecast != nil }

    /// Screenshots: once the page has its numbers, scroll to the part named by `router.planStage`.
    private func scrollToStage(_ proxy: ScrollViewProxy) async {
        guard router.tab == .plan, let stage = router.planStage, isReady else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        proxy.scrollTo(stage, anchor: .top)
        router.planStage = nil
    }
}

/// "Forecast · Insights · Challenges" as underlined serif words, like the Library's shelves. Scrolls sideways when
/// large text makes the three too wide.
struct PlanSectionSwitcher: View {
    @Binding var selection: PlanSection

    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Space.xl) {
                    ForEach(PlanSection.allCases) { section in
                        tab(section).id(section)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollClipDisabled()
            // At the largest sizes the chosen word slides fully into view rather than sitting cut at the edge.
            .onChange(of: selection) { _, section in
                withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(section, anchor: .center)
                }
            }
        }
        // Words this big are headings already; past AX1 they only push "Challenges" off screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func tab(_ section: PlanSection) -> some View {
        let isActive = section == selection
        return Button {
            guard !isActive else { return }
            Haptics.shared.selection()
            withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                selection = section
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(section.title)
                    .font(LeafType.title)
                    .foregroundStyle(isActive ? Color.ink : Color.inkTertiary)
                    .lineLimit(1)
                    .fixedSize()
                ZStack {
                    if isActive {
                        Capsule()
                            .fill(Color.ribbon)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
                .frame(height: 2)
            }
            .frame(minHeight: Space.hitTarget, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Everything the forecast and the stats depend on; a change re-runs the engines (Plan and You).
struct PlanDeskKey: Equatable {
    var now: Date
    var items: [String]
    var sessions: Int
    var journal: Int
    var challenges: Int
    var preferences: ReadingPreferences

    @MainActor
    init(store: LibraryStore) {
        now = store.now
        items = store.data.items.map { "\($0.id)|\($0.shelf.rawValue)|\($0.currentPage)|\($0.order)|\($0.positionConfirmed)|\($0.progressMode)" }
        sessions = store.data.sessions.count
        journal = store.data.journal.count
        challenges = store.data.challenges.count
        preferences = store.preferences
    }
}

extension AppRouter {
    /// The plan sheet, presented only by the tab that is showing, so Plan and You don't both try.
    func planSheetBinding(on tab: AppTab) -> Binding<PlanSheet?> {
        Binding(
            get: { self.tab == tab ? self.planSheet : nil },
            set: { self.planSheet = $0 }
        )
    }
}

/// Today's reading times on Plan: which book at what time, with one tap to change the time or swap the book
/// (`SlotTimeSheet`, `SlotBookSheet`). Edit opens the full reading-times editor (days, names, adding and removing).
struct PlanTimesCard: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let plans = store.slotPlans()
        let next = store.nextSlotToday
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Today’s reading times", linkTitle: "Edit") {
                router.readingSlotToEdit = nil
                router.showReadingTimes = true
            }
            if plans.isEmpty {
                Text("Pick a time or two and Leaf will share each day’s pages between them, a book to each if you like.")
                    .canopyText(.callout, color: Canopy.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                CanopyGlassButton("Add a reading time", systemImage: "plus", accent: .dusk, compact: true, feel: .planChanged) {
                    router.readingSlotToEdit = nil
                    router.showReadingTimes = true
                }
            } else {
                ForEach(plans) { plan in
                    CanopySlotRow(
                        time: LeafFormat.time(hour: plan.slot.hour, minute: plan.slot.minute),
                        period: plan.slot.label,
                        title: title(for: plan),
                        detail: detail(for: plan),
                        paletteIndex: bookID(for: plan).flatMap { store.item($0) }.map { CoverPalette.index(for: $0.book) },
                        state: state(for: plan, next: next),
                        onTime: { router.slotEdit = .time(plan.slot.id) },
                        onSwap: { router.slotEdit = .book(plan.slot.id) }
                    )
                }
            }
        }
        .canopyCard()
        .firstUseTip(.planTimes, pointer: 0.14, isAvailable: !plans.isEmpty)
    }

    private func bookID(for plan: SlotPlan) -> String? {
        plan.slot.bookID ?? (plan.parts.count == 1 ? plan.parts.first?.bookID : nil)
    }

    private func title(for plan: SlotPlan) -> String {
        if let id = bookID(for: plan), let item = store.item(id) { return item.book.title }
        return plan.parts.isEmpty ? "Nothing planned" : "Shared"
    }

    private func detail(for plan: SlotPlan) -> String {
        guard let first = plan.parts.first else { return "A free time today" }
        let minutes = Int(plan.minutes.rounded())
        let last = plan.parts.last ?? first
        // No-break spaces keep "7 min" and "pp. 143–148" whole, so a narrow row wraps at the dot, never after "pp.".
        if plan.parts.count == 1 {
            return "\(minutes)\u{00A0}min · pp.\u{00A0}\(first.fromPage)–\(first.toPage)"
        }
        return "\(minutes) min · \(plan.parts.count) books, to p. \(last.toPage)"
    }

    private func state(for plan: SlotPlan, next: SlotPlan?) -> CanopySlotState {
        plan.id == next?.id ? .next : .later
    }
}

/// The plan sheets, each waiting for the numbers it needs.
struct PlanSheetHost: View {
    let sheet: PlanSheet
    let desk: PlanDesk

    var body: some View {
        switch sheet {
        case .finishLine(let bookID):
            FinishLineSheet(desk: desk, initialBookID: bookID)
                .presentationDetents([.large])
        case .smartOrder:
            SmartOrderSheet(desk: desk)
                .presentationDetents([.large])
        case .yearInBooks:
            if let summary = desk.insights?.yearInBooks {
                YearInBooksView(summary: summary)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).paperBackground()
            }
        case .weeklyLetter:
            if let letter = desk.insights?.letter {
                WeeklyLetterView(letter: letter)
                    .presentationDetents([.large])
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).paperBackground()
            }
        case .readingLog:
            HistorySheet { ReadingLogView() }
        case .numbers:
            HistorySheet { StatsDepthView() }
        case .quoteCard(let entryID):
            QuoteCardSheet(initialEntryID: entryID)
                .presentationDetents([.large])
        }
    }
}

// MARK: - Previews

@MainActor
private func planPreviewStore(_ configure: (LibraryStore) -> Void = { _ in }) -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    configure(store)
    return store
}

private struct PlanPreviewHost: View {
    var section: PlanSection = .forecast
    @State private var router = AppRouter()

    var body: some View {
        NavigationStack {
            PlanView()
                .navigationDestination(for: BookRoute.self) { route in
                    Text(route.book.title)
                }
        }
        .environment(router)
        .onAppear { router.planSection = section }
    }
}

#Preview("Forecast") {
    PlanPreviewHost()
        .environment(planPreviewStore())
        .environment(BookCatalog.shared)
}

#Preview("Forecast · dark") {
    PlanPreviewHost()
        .environment(planPreviewStore())
        .environment(BookCatalog.shared)
        .preferredColorScheme(.dark)
}

#Preview("Insights") {
    PlanPreviewHost(section: .insights)
        .environment(planPreviewStore())
        .environment(BookCatalog.shared)
}

#Preview("Challenges · dark") {
    PlanPreviewHost(section: .challenges)
        .environment(planPreviewStore())
        .environment(BookCatalog.shared)
        .preferredColorScheme(.dark)
}

#Preview("Plan · empty") {
    PlanPreviewHost()
        .environment(LibraryStore(persistence: .ephemeral()))
        .environment(BookCatalog.shared)
}
