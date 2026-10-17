import SwiftUI

/// Today (DESIGN.md §6): a dateline, a greeting, and today's reading set like the front page of a
/// small paper. Lives inside `MainTabs`' navigation stack; its only toolbar item opens Settings.
struct TodayView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var strikeDrawn = false

    private enum Mode {
        case empty
        case goalMet
        case plan([TodayEntry])
        case rest
    }

    // MARK: State

    private var isLibraryEmpty: Bool { store.reading.isEmpty && store.toRead.isEmpty }

    private var goalMet: Bool { store.goalMetToday && !isLibraryEmpty }

    private var isLive: Bool { store.activeSession != nil }

    private var mode: Mode {
        if isLibraryEmpty { return .empty }
        if store.goalMetToday { return .goalMet }
        let entries = store.todayAssignments.map { TodayEntry(item: $0.item, assignment: $0.assignment) }
        return entries.isEmpty ? .rest : .plan(entries)
    }

    /// Books already shown in the hero, so the lists below don't repeat them.
    private var featuredIDs: Set<String> {
        switch mode {
        case .plan(let entries):
            return Set(entries.map { $0.id })
        case .goalMet:
            if let id = store.nextBook?.id { return [id] }
            return []
        case .empty, .rest:
            return []
        }
    }

    /// "On your desk": the other books open in Reading (focus mode, when there is more than one).
    private var deskItems: [LibraryItem] {
        guard store.reading.count > 1 else { return [] }
        let featured = featuredIDs
        return store.reading.filter { !featured.contains($0.id) }
    }

    private var upNextItem: LibraryItem? {
        let featured = featuredIDs
        return store.toRead.first { !featured.contains($0.id) }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                dateline
                    .inkIn(0)
                Text(greeting)
                    .leafStyle(.masthead)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Space.xl)
                    .inkIn(1)
                issue
            }
            .leafMargins()
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.shared.tap()
                    router.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .onAppear {
            if goalMet { drawStrike(after: .milliseconds(450), playsHaptic: false) }
        }
        .onChange(of: goalMet) { old, new in
            if new {
                drawStrike(after: .milliseconds(900), playsHaptic: !old)
            } else {
                strikeDrawn = false
            }
        }
    }

    // MARK: Dateline and greeting

    private var dateline: some View {
        VStack(spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(LeafFormat.format(store.now, template: "EEEEdMMMM", calendar: store.calendar))
                    .leafStyle(.eyebrow)
                Spacer(minLength: Space.m)
                Text("No. \(store.issueNumber)")
                    .leafStyle(.eyebrow)
                    .accessibilityLabel(issueSpoken)
            }
            DoubleRule()
        }
    }

    private var issueSpoken: String {
        let number = store.issueNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        let ordinal = formatter.string(from: NSNumber(value: number)) ?? "\(number)"
        return "Issue \(number), your \(ordinal) day with Leaf"
    }

    private var greeting: String {
        switch store.calendar.component(.hour, from: store.now) {
        case 5...11: return "Good morning."
        case 12...16: return "Good afternoon."
        case 17...21: return "Good evening."
        default: return "Still up?"
        }
    }

    // MARK: The issue

    @ViewBuilder
    private var issue: some View {
        switch mode {
        case .empty:
            EmptyState(
                title: "An empty issue.",
                message: "Add a book and Leaf will plan the pages.",
                actionTitle: "Find a book",
                prominent: true
            ) {
                router.tab = .search
            }
            .inkIn(2)
        case .goalMet:
            if let item = store.nextBook {
                TodayHero(
                    item: item,
                    numeral: store.preferences.dailyMinutes,
                    eyebrow: "Done for today",
                    spokenMinutes: "Done for today. Your \(store.preferences.dailyMinutes) minutes are read.",
                    isDone: true,
                    strikeDrawn: strikeDrawn,
                    assignment: nil,
                    finish: store.plan.book(item.id)?.finish,
                    isLive: isLive,
                    onStart: { start(bookID: item.id) },
                    onOpen: { router.open(item.book) }
                )
                .inkIn(2)
            }
            followUps
        case .plan(let entries):
            planHero(entries)
                .inkIn(2)
            followUps
        case .rest:
            restBlock
                .inkIn(2)
            followUps
        }
    }

    @ViewBuilder
    private func planHero(_ entries: [TodayEntry]) -> some View {
        let sum: Double = entries.reduce(0.0) { $0 + $1.assignment.minutes }
        let total = max(1, Int(sum.rounded()))
        let hasStarted = store.minutesReadToday >= 1
        let eyebrow = hasStarted ? "Min left" : "Min"
        let goal = store.preferences.dailyMinutes
        let spoken = hasStarted
            ? "\(total) minutes left. \(Int(store.minutesReadToday.rounded())) of \(goal) minutes read today."
            : "\(total) minutes"
        let progress: Double? = hasStarted ? store.goalProgress : nil
        if entries.count > 1 {
            TodayIssue(
                entries: entries,
                totalMinutes: total,
                eyebrow: eyebrow,
                spokenMinutes: spoken,
                isLive: isLive,
                goalProgress: progress,
                onStart: { start(bookID: entries.first?.id) },
                onStartBook: { start(bookID: $0) },
                onOpen: { router.open($0) }
            )
        } else if let entry = entries.first {
            TodayHero(
                item: entry.item,
                numeral: total,
                eyebrow: eyebrow,
                spokenMinutes: spoken,
                isDone: false,
                strikeDrawn: false,
                assignment: entry.assignment,
                finish: store.plan.book(entry.item.id)?.finish,
                isLive: isLive,
                goalProgress: progress,
                onStart: { start(bookID: entry.item.id) },
                onOpen: { router.open(entry.item.book) }
            )
        }
    }

    private var restBlock: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("A rest day.")
                .leafStyle(.masthead)
                .accessibilityAddTraits(.isHeader)
            Text("Nothing’s scheduled. Read anyway if you like.")
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
            SecondaryGlassButton(isLive ? "Return to session" : "Read anyway") {
                start(bookID: nil)
            }
            .sessionZoomSource(ReadingSessionLauncher.heroSource)
        }
        .padding(.top, Space.l)
    }

    // MARK: Below the hero

    @ViewBuilder
    private var followUps: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("This week")
            WeekStrip(days: store.week, streak: store.streak)
        }
        .inkIn(3)

        let desk = deskItems
        if !desk.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("On your desk")
                ForEach(desk) { item in
                    TodayBookLine(
                        item: item,
                        caption: "p. \(item.currentPage) of \(item.book.pages)",
                        showsProgress: true,
                        onOpen: { router.open(item.book) }
                    )
                }
            }
            .inkIn(4)
        }

        if let next = upNextItem {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Up next")
                TodayBookLine(
                    item: next,
                    caption: beginsCaption(for: next),
                    onOpen: { router.open(next.book) }
                )
            }
            .inkIn(5)
        }
    }

    /// "begins Mon 27 Oct", or "begins tomorrow".
    private func beginsCaption(for item: LibraryItem) -> String {
        guard let start = store.plan.book(item.id)?.start else { return "Next in your queue" }
        let calendar = store.calendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: store.now), to: calendar.startOfDay(for: start)).day ?? 0
        switch days {
        case ...0: return "begins today"
        case 1: return "begins tomorrow"
        default: return "begins \(LeafFormat.format(start, template: "EEEdMMM", calendar: calendar))"
        }
    }

    // MARK: Actions

    private func start(bookID: String?) {
        ReadingSessionLauncher.start(bookID: bookID, store: store, router: router, from: ReadingSessionLauncher.heroSource)
    }

    /// The ribbon strike draws once the day is done. `goalReached` plays only when nothing else is on
    /// screen (a session or its wrap-up sheet already has its own moment).
    private func drawStrike(after delay: Duration, playsHaptic: Bool) {
        guard !strikeDrawn else { return }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard goalMet, !strikeDrawn else { return }
            withAnimation(Motion.strike) { strikeDrawn = true }
            if playsHaptic && router.lastOutcome == nil && !router.showSession {
                Haptics.shared.play(.goalReached)
            }
        }
    }
}

// MARK: - Previews

private func todayPreviewStore(_ configure: (LibraryStore) -> Void = { _ in }) -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    configure(store)
    return store
}

private struct TodayPreviewHost: View {
    var body: some View {
        NavigationStack {
            TodayView()
        }
    }
}

#Preview("Today") {
    TodayPreviewHost()
        .environment(todayPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Today · goal met") {
    TodayPreviewHost()
        .environment(todayPreviewStore { store in
            let session = ReadingSession(
                bookID: DemoData.hobbit.id,
                startedAt: Date().addingTimeInterval(-60),
                seconds: 14 * 60,
                fromPage: 142,
                toPage: 158
            )
            store.log(session)
        })
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Today · side by side") {
    TodayPreviewHost()
        .environment(todayPreviewStore { store in
            store.updatePreferences { $0.planMode = .sideBySide }
        })
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Today · rest day") {
    TodayPreviewHost()
        .environment(todayPreviewStore { store in
            let weekday = Calendar.current.component(.weekday, from: Date())
            store.updatePreferences { $0.readingDays.remove(weekday) }
        })
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Today · empty") {
    TodayPreviewHost()
        .environment(LibraryStore(persistence: .ephemeral()))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
