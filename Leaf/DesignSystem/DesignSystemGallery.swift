#if DEBUG
import SwiftUI

/// Every design-system piece on one page, for previews and visual review. Debug builds only.
struct DesignSystemGallery: View {
    @Environment(LibraryStore.self) private var store
    @State private var minutes = 25
    @State private var page = 158
    @State private var days: Set<Int> = [2, 3, 4, 5, 6]
    @State private var shelf: Shelf = .toRead

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Eyebrow("Thursday 16 October")
                        Spacer()
                        Eyebrow("No. \(store.issueNumber)")
                    }
                    .padding(.top, Space.s)
                    .padding(.bottom, Space.s)
                    DoubleRule()
                    Text("Good evening.")
                        .leafStyle(.masthead)
                        .padding(.top, Space.l)
                        .inkIn(0)

                    hero.inkIn(1)

                    SectionHeader("This week")
                    WeekStrip(days: store.week, streak: store.streak)

                    SectionHeader("Shelves")
                    ShelfSwitcher(selection: $shelf, counts: [.reading: store.reading.count, .toRead: store.toRead.count, .finished: store.finished.count])

                    SectionHeader("Running order")
                    VStack(spacing: Space.m) {
                        ForEach(Array(store.toRead.prefix(3).enumerated()), id: \.element.id) { offset, item in
                            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                                IndexNumeral(offset + 1)
                                Text(item.book.title).leafStyle(.headline).lineLimit(1)
                                LeaderDots()
                                Text(finishText(for: item.id))
                                    .leafStyle(.data)
                            }
                        }
                        HStack {
                            DeltaChip(daysSooner: 6)
                            DeltaChip(daysSooner: -4)
                        }
                    }

                    SectionHeader("Facts")
                    StatTileRow {
                        StatTile(value: "310", label: "Pages")
                        StatTile(value: "95K", label: "Words")
                        StatTile(value: "6 h 22 m", label: "At your pace")
                    }

                    SectionHeader("Minutes")
                    MinutesDial(minutes: $minutes)

                    SectionHeader("Page reached")
                    PageScrubber(page: $page, range: 142...310, estimate: 158)

                    SectionHeader("Reading days")
                    WeekdayPicker(selection: $days)

                    SectionHeader("Rings")
                    HStack(spacing: Space.xl) {
                        ProgressRing.accessory(progress: store.goalProgress)
                        ProgressRing(progress: 0.6, diameter: 84, lineWidth: 7)
                    }

                    SectionHeader("Motion and atmosphere")
                    HStack(spacing: Space.s) {
                        ForEach([Color.teaPaper, .chai, .matcha, .rooibos, .steam, .amber, .rose], id: \.self) { token in
                            Circle().fill(token).frame(width: 22, height: 22)
                        }
                    }
                    .padding(.bottom, Space.m)
                    VStack(spacing: 0) {
                        ForEach(MotionGallery.Section.allCases) { section in
                            NavigationLink(value: section) {
                                HStack {
                                    Text(section.title).leafStyle(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Color.inkTertiary)
                                }
                                .frame(minHeight: Space.hitTarget)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            Hairline()
                        }
                    }
                    .padding(.bottom, Space.l)

                    EmptyState(title: "The queue is clear.", message: "Add the books you mean to get to.")
                }
                .leafMargins()
                .padding(.bottom, Space.section)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .paperBackground()
            .navigationTitle("Design")
            .navigationDestination(for: MotionGallery.Section.self) { section in
                MotionGallery(section: section)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.shared.tap()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    private func finishText(for id: String) -> String {
        guard let finish = store.plan.book(id)?.finish else { return "—" }
        return LeafFormat.shortDate(finish)
    }

    private var hero: some View {
        let item = store.reading.first
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("22").leafStyle(.heroNumeral)
                    Eyebrow("Min")
                    Text("of").leafStyle(.pullQuote).padding(.top, Space.s)
                    Text(item?.book.title ?? "The Hobbit").leafStyle(.title)
                    Text(item?.book.author ?? "").leafStyle(.author)
                }
                Spacer(minLength: 0)
                if let item {
                    BookCover(book: item.book, size: .l, ribbon: true, swaysRibbon: true)
                }
            }
            .padding(.top, Space.xxl)
            Text("about pp. 142–158").leafStyle(.pullQuote)
            PageSpanBar(current: item?.currentPage ?? 0, todayTo: 158, total: item?.book.pages ?? 310)
            Text("p. 142 of 310 · done by Sun 26 Oct").leafStyle(.caption)
            PrimaryGlassButton("Start reading", systemImage: "play.fill") {}
                .padding(.top, Space.s)
            SecondaryGlassButton("Read a little more") {}
        }
    }
}

#Preview("Gallery · light") {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return DesignSystemGallery()
        .environment(store)
        .environment(AppRouter())
        .environment(BookCatalog.shared)
        .tint(.accent)
        .preferredColorScheme(.light)
}

#Preview("Gallery · dark") {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return DesignSystemGallery()
        .environment(store)
        .environment(AppRouter())
        .environment(BookCatalog.shared)
        .tint(.accent)
        .preferredColorScheme(.dark)
}
#endif
