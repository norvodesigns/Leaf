import SwiftUI

/// The Plan tab (NEXT.md section 10): Forecast, Insights and Challenges under one switcher. The engines run once per
/// change to the library in a shared `PlanDesk`, off the main actor, so switching pages is instant.
struct PlanView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var desk = PlanDesk()

    /// Everything the forecast and the stats depend on; a change re-runs the engines.
    private struct DataKey: Equatable {
        var now: Date
        var items: [String]
        var sessions: Int
        var journal: Int
        var challenges: Int
        var preferences: ReadingPreferences
    }

    private var dataKey: DataKey {
        DataKey(
            now: store.now,
            items: store.data.items.map { "\($0.id)|\($0.shelf.rawValue)|\($0.currentPage)|\($0.order)" },
            sessions: store.data.sessions.count,
            journal: store.data.journal.count,
            challenges: store.data.challenges.count,
            preferences: store.preferences
        )
    }

    var body: some View {
        @Bindable var router = router
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PlanSectionSwitcher(selection: $router.planSection)
                        .padding(.bottom, Space.m)
                    switch router.planSection {
                    case .forecast:
                        if store.plan.books.isEmpty {
                            EmptyState(
                                title: "Nothing to forecast yet.",
                                message: "Add a book to Reading or To read and Leaf will work out the odds.",
                                actionTitle: "Find a book"
                            ) {
                                router.tab = .search
                            }
                            .padding(.top, Space.xxxl)
                        } else {
                            ForecastPage(desk: desk)
                        }
                    case .insights:
                        InsightsPage(desk: desk)
                    case .challenges:
                        ChallengesPage(desk: desk)
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
        .task(id: dataKey) {
            desk.refresh(from: store)
        }
        .sheet(item: $router.planSheet) { sheet in
            PlanSheetHost(sheet: sheet, desk: desk)
        }
    }

    // MARK: Staging

    private struct StageKey: Equatable {
        var stage: String?
        var ready: Bool
    }

    private var isReady: Bool {
        switch router.planSection {
        case .forecast: desk.forecast != nil
        case .insights: desk.insights != nil
        case .challenges: desk.challenges != nil
        }
    }

    /// Screenshots: once the page has its numbers, scroll to the part named by `router.planStage`.
    private func scrollToStage(_ proxy: ScrollViewProxy) async {
        guard let stage = router.planStage, isReady else { return }
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
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.xl) {
                ForEach(PlanSection.allCases) { section in
                    tab(section)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollClipDisabled()
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

/// The Plan tab's sheets, each waiting for the numbers it needs.
private struct PlanSheetHost: View {
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
