import SwiftUI

/// The You tab (docs/design/REDESIGN.md §4.7): how it's going on top (streak, this week), then "Make it yours" (rate
/// teas, teas you like, the cabinet, settings) where it's seen without scrolling, then the deeper pages that used to
/// sit under Plan (insights, challenges, circles), then the history pages.
struct YouView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The tile badge grows with the text, so a large-text icon stays inside its circle.
    @ScaledMetric(relativeTo: .subheadline) private var badge: CGFloat = 34
    @State private var desk = PlanDesk()
    /// Kept in UserDefaults, which SwiftUI doesn't watch: read again whenever a tea page closes.
    @State private var teaPrefs = CozySettings.teaPreferences

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
                    personal
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
        .onAppear {
            teaPrefs = CozySettings.teaPreferences
        }
        .onChange(of: router.teaPage) { _, page in
            if page == nil { teaPrefs = CozySettings.teaPreferences }
        }
        .onChange(of: router.showSettings) { _, shown in
            if !shown { teaPrefs = CozySettings.teaPreferences }
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

    // MARK: Make it yours

    /// The things a reader changes to make Leaf theirs, as four tiles that each say where they stand.
    private var personal: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Make it yours", accent: .clay)
            let tiles = [
                Tile(title: "Rate your teas", detail: ratingsDetail, systemImage: "leaf.fill", accent: .clay) { router.teaPage = .ratings },
                Tile(title: "Teas you like", detail: likesDetail, systemImage: "heart.fill", accent: .bloom) { router.teaPage = .preferences },
                Tile(title: "Tea cabinet", detail: cabinetDetail, systemImage: "cup.and.heat.waves.fill", accent: .clay) { router.teaPage = .cabinet },
                Tile(title: "Settings", detail: "Pace, reading nook, sounds and look", systemImage: "slider.horizontal.3", accent: .forest) { router.showSettings = true },
            ]
            if typeSize.isAccessibilitySize {
                VStack(spacing: Canopy.Space.m) {
                    ForEach(tiles) { tileButton($0) }
                }
            } else {
                VStack(spacing: Canopy.Space.m) {
                    ForEach([0, 2], id: \.self) { start in
                        HStack(spacing: Canopy.Space.m) {
                            tileButton(tiles[start])
                            tileButton(tiles[start + 1])
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private struct Tile: Identifiable {
        var title: String
        var detail: String
        var systemImage: String
        var accent: CanopyAccent
        var action: () -> Void

        var id: String { title }
    }

    private func tileButton(_ tile: Tile) -> some View {
        Button {
            CanopyFeel.play(.tap)
            tile.action()
        } label: {
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                Image(systemName: tile.systemImage)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(tile.accent.color)
                    .frame(width: badge, height: badge)
                    .background(tile.accent.soft, in: .circle)
                    .accessibilityHidden(true)
                Text(tile.title)
                    .canopyText(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tile.detail)
                    .canopyText(.caption)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Canopy.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .canopyGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// "4 teas rated", or the invitation.
    private var ratingsDetail: String {
        let ids = Set(teaPrefs.ratings.keys).union(store.data.cabinet.filter { $0.rating != nil }.map(\.teaID))
        let count = ids.filter { id in
            TeaShelf.rating(for: id, cabinet: store.data.cabinet, preferences: teaPrefs) != nil && store.tea(id: id) != nil
        }.count
        switch count {
        case 0: return "One tap on the leaves"
        case 1: return "1 tea rated"
        default: return "\(count) teas rated"
        }
    }

    /// "Green, herbal · floral", or the invitation.
    private var likesDetail: String {
        guard teaPrefs.hasLeanings else { return "Kinds, caffeine, flavours" }
        var parts: [String] = []
        let kinds = TeaFamily.allCases.filter { teaPrefs.likedFamilies.contains($0) }.map(\.title)
        if !kinds.isEmpty { parts.append(ListFormatter.localizedString(byJoining: Array(kinds.prefix(2)))) }
        let flavours = TastingAroma.all.filter { teaPrefs.likedFlavours.contains($0) }
        if !flavours.isEmpty { parts.append(ListFormatter.localizedString(byJoining: Array(flavours.prefix(2)))) }
        if teaPrefs.caffeine != .any { parts.append("caffeine: \(teaPrefs.caffeine.title.lowercased())") }
        if parts.isEmpty { parts.append("By time of day") }
        return parts.joined(separator: " · ")
    }

    /// "5 in, 1 run out", or the invitation.
    private var cabinetDetail: String {
        let cabinet = store.data.cabinet
        guard !cabinet.isEmpty else { return "Add the teas you have" }
        let inStock = cabinet.filter { !$0.isOutOf }.count
        let out = cabinet.count - inStock
        return out > 0 ? "\(inStock) in, \(out) run out" : "\(inStock) \(inStock == 1 ? "tea" : "teas") in"
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

    /// What's been: the log, the numbers, the year, quotes and the teas read with.
    private var more: some View {
        VStack(alignment: .leading, spacing: 0) {
            CanopyLabel("Look back", accent: .bloom)
                .padding(.bottom, Canopy.Space.s)
            row("Reading log", systemImage: "list.bullet.rectangle", accent: .dusk) { router.planSheet = .readingLog }
            row("Your numbers", systemImage: "chart.bar", accent: .bloom) { router.planSheet = .numbers }
            row("Year in books", systemImage: "calendar", accent: .bloom) { router.planSheet = .yearInBooks }
            row("Quotes", systemImage: "quote.bubble", accent: .bloom) { router.planSheet = .quoteCard(entryID: nil) }
            row("Tea history", systemImage: "clock.arrow.circlepath", accent: .clay) { router.teaPage = .history }
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
