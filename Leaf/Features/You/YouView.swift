import SwiftUI

/// The You tab (docs/design/REDESIGN.md §4.7): how it's going on top (streak, this week), then the deeper pages that
/// used to sit under Plan (insights, challenges, circles), then history, tea and settings one tap away.
struct YouView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var desk = PlanDesk()

    /// Insights, challenges or circles; the forecast belongs to Plan.
    private static let sections: [PlanSection] = [.insights, .challenges, .circles]

    private var section: PlanSection {
        router.planSection == .forecast ? .insights : router.planSection
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Canopy.Space.section) {
                    summary
                        .firstUseTip(.youCorner, edge: .top, pointer: nil)
                    VStack(alignment: .leading, spacing: Canopy.Space.l) {
                        switcher
                        switch section {
                        case .challenges: ChallengesPage(desk: desk)
                        case .circles: CirclesPage()
                        default: InsightsPage(desk: desk)
                        }
                    }
                    more
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
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    CanopyFeel.play(.tap)
                    router.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .task(id: PlanDeskKey(store: store)) {
            desk.refresh(from: store)
        }
        .sheet(item: router.planSheetBinding(on: .you)) { sheet in
            PlanSheetHost(sheet: sheet, desk: desk)
        }
    }

    // MARK: Level 0: how it's going

    private var summary: some View {
        let week = store.week
        let weekMinutes = Int(week.reduce(0) { $0 + $1.minutes }.rounded())
        let streak = store.streak
        return HStack(alignment: .top, spacing: Canopy.Space.cardGap) {
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                CanopyStat(value: "\(streak)", unit: streak == 1 ? "day" : "days", caption: "Reading streak", accent: .forest)
                HStack(spacing: 6) {
                    ForEach(week) { day in
                        Circle()
                            .fill(day.minutes > 0 ? CanopyAccent.forest.color : Canopy.separator)
                            .frame(width: 9, height: 9)
                            .overlay {
                                if day.isToday {
                                    Circle().strokeBorder(Canopy.text.opacity(0.5), lineWidth: 1).frame(width: 13, height: 13)
                                }
                            }
                    }
                }
                .accessibilityHidden(true)
            }
            .canopyCard()
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                CanopyStat(value: Self.duration(minutes: weekMinutes), caption: "Read this week")
            }
            .canopyCard()
        }
    }

    private static func duration(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: Level 1: the deeper pages

    /// The chips never break mid-word: at large text they scroll sideways instead.
    private var switcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Canopy.Space.s) {
                ForEach(Self.sections) { item in
                    CanopyChip(item.title, accent: .bloom, isSelected: item == section) {
                        withAnimation(Canopy.Motion.smooth) { router.planSection = item }
                    }
                    .fixedSize()
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var more: some View {
        VStack(alignment: .leading, spacing: 0) {
            CanopyLabel("More", accent: .bloom)
                .padding(.bottom, Canopy.Space.s)
            row("Reading log", systemImage: "list.bullet.rectangle", accent: .dusk) { router.planSheet = .readingLog }
            row("Your numbers", systemImage: "chart.bar", accent: .bloom) { router.planSheet = .numbers }
            row("Year in books", systemImage: "calendar", accent: .bloom) { router.planSheet = .yearInBooks }
            row("Quotes", systemImage: "quote.bubble", accent: .bloom) { router.planSheet = .quoteCard(entryID: nil) }
            row("Tea cabinet", systemImage: "cup.and.heat.waves", accent: .clay) { router.teaPage = .cabinet }
            row("Tea history", systemImage: "clock.arrow.circlepath", accent: .clay) { router.teaPage = .history }
            row("Teas you like", systemImage: "heart", accent: .clay) { router.teaPage = .preferences }
            row("Settings", systemImage: "gearshape", accent: nil) { router.showSettings = true }
        }
        .canopyCard()
    }

    private func row(_ title: String, systemImage: String, accent: CanopyAccent?, action: @escaping () -> Void) -> some View {
        Button {
            CanopyFeel.play(.tap)
            action()
        } label: {
            HStack(spacing: Canopy.Space.m) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent?.color ?? Canopy.textSecondary)
                    .frame(width: 28)
                Text(title).canopyText(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Canopy.textTertiary)
            }
            .frame(minHeight: Canopy.Space.hitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Staging

    private struct StageKey: Equatable {
        var stage: String?
        var ready: Bool
    }

    private var isReady: Bool {
        switch section {
        case .challenges: desk.challenges != nil
        case .circles: true
        default: desk.insights != nil
        }
    }

    /// Screenshots: once the page has its numbers, scroll to the part named by `router.planStage`.
    private func scrollToStage(_ proxy: ScrollViewProxy) async {
        guard router.tab == .you, let stage = router.planStage, isReady else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        proxy.scrollTo(stage, anchor: .top)
        router.planStage = nil
    }
}
