import SwiftUI

/// Plan (DESIGN.md §6): the whole running order as a timeline, with the numbers that matter above it
/// and the next seven days below. Changing the plan style or the daily minutes reflows the timeline
/// live: bands slide, dates roll, and a chip says how many days each book moved.
struct PlanView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Finish dates from before the current burst of adjustments, so the chips compare against the start.
    @State private var baseline: [String: Date] = [:]
    /// Days sooner (positive) or later (negative) per book since `baseline`.
    @State private var deltas: [String: Int] = [:]
    /// Per-book counters that bump when an adjustment settles, to flash the date.
    @State private var flashStamps: [String: Int] = [:]
    /// The furthest the axis has reached during an adjustment. It only grows until things settle, so
    /// bands move against a steady axis instead of everything rescaling at once.
    @State private var axisHold: Date?
    /// Dates roll one row after another (a plan-style switch) rather than all at once (a dial).
    @State private var staggered = false
    @State private var settleTask: Task<Void, Never>?

    private var plan: ReadingPlan { store.plan }

    // MARK: Body

    var body: some View {
        ScrollView {
            if plan.books.isEmpty {
                EmptyState(
                    title: "Nothing to plan yet.",
                    message: "Add a book to Reading or To read and Leaf will set the dates.",
                    actionTitle: "Find a book"
                ) {
                    router.tab = .search
                }
                .padding(.top, Space.xxxl)
            } else {
                content
            }
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.large)
        .onDisappear(perform: resetReflow)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .inkIn(0)
            stats
                .padding(.top, Space.xl)
                .inkIn(1)
            runningOrder
                .inkIn(2)
            dailyTime
                .inkIn(3)
            nextDays
                .inkIn(4)
            footer
                .inkIn(5)
        }
        .leafMargins()
        .padding(.top, Space.s)
        .padding(.bottom, Space.xxl)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(eyebrowLine)
                .leafStyle(.eyebrow)
                .contentTransition(.numericText())
            Picker("Plan style", selection: modeBinding) {
                Text("One at a time").tag(PlanMode.focus)
                Text("Side by side").tag(PlanMode.sideBySide)
            }
            .pickerStyle(.segmented)
            Text(modeCaption)
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "6 books · through 14 March 2027" (uppercased on screen).
    private var eyebrowLine: String {
        let count = plan.books.count
        let noun = count == 1 ? "book" : "books"
        guard let done = plan.allDone else { return "\(count) \(noun)" }
        return "\(count) \(noun) · through \(LeafFormat.format(done, template: "dMMMMyyyy", calendar: store.calendar))"
    }

    private var modeCaption: String {
        switch store.preferences.planMode {
        case .focus:
            return "Finish one book, then begin the next."
        case .sideBySide:
            if store.reading.count < 2 {
                return "Your time is split across everything in Reading. With one book open, nothing changes yet."
            }
            return "Your daily time is split across every book in Reading."
        }
    }

    private var modeBinding: Binding<PlanMode> {
        Binding(
            get: { store.preferences.planMode },
            set: { newMode in
                guard newMode != store.preferences.planMode else { return }
                Haptics.shared.selection()
                adjust(riffles: true, staggerRows: true) { $0.planMode = newMode }
            }
        )
    }

    // MARK: Stats

    private var stats: some View {
        StatTileRow {
            StatTile(value: "\(plan.finishedCount(onOrBefore: yearEnd))", label: "Books by \(yearEndLabel)")
            StatTile(value: allDoneValue, label: "All done")
            StatTile(value: leftValue, label: "Left to read")
        }
        .contentTransition(.numericText())
    }

    /// The last moment of this year, so a book finishing on 31 December counts.
    private var yearEnd: Date {
        guard let interval = store.calendar.dateInterval(of: .year, for: store.now) else { return store.now }
        return interval.end.addingTimeInterval(-1)
    }

    private var yearEndLabel: String {
        LeafFormat.format(yearEnd, template: "MMMd", calendar: store.calendar)
    }

    /// "Dec 14", or "Mar ’27" when it's beyond this year.
    private var allDoneValue: String {
        guard let done = plan.allDone else { return "—" }
        let calendar = store.calendar
        let year = calendar.component(.year, from: done)
        if year == calendar.component(.year, from: store.now) {
            return LeafFormat.format(done, template: "MMMd", calendar: calendar)
        }
        let month = LeafFormat.format(done, template: "MMM", calendar: calendar)
        return "\(month) ’\(String(format: "%02d", year % 100))"
    }

    /// Everything still to read at the reader's pace: "5h 20m", or "41h" once it's long.
    private var leftValue: String {
        let minutes = plan.books.reduce(0.0) { $0 + $1.minutesLeft }
        if minutes < 600 { return LeafFormat.compactDuration(minutes: minutes) }
        return "\(Int((minutes / 60).rounded()))h"
    }

    // MARK: Timeline

    private var rowModels: [PlanRowModel] {
        var models: [PlanRowModel] = []
        for planned in plan.books {
            guard let item = store.item(planned.id) else { continue }
            models.append(PlanRowModel(number: models.count + 1, planned: planned, book: item.book))
        }
        return models
    }

    private var naturalScale: TimelineScale {
        TimelineScale(covering: plan.books, today: store.now, calendar: store.calendar)
    }

    private var scale: TimelineScale {
        let natural = naturalScale
        guard let hold = axisHold, hold > natural.end else { return natural }
        return TimelineScale(start: natural.start, end: hold, calendar: store.calendar)
    }

    private var runningOrder: some View {
        let scale = self.scale
        let models = rowModels
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Running order")
            VStack(spacing: 0) {
                TimelineMonthLabels(scale: scale)
                    .padding(.leading, PlanRow.indexWidth)
                    .padding(.bottom, Space.s)
                ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                    PlanRow(
                        number: model.number,
                        book: model.book,
                        planned: model.planned,
                        scale: scale,
                        today: store.now,
                        calendar: store.calendar,
                        daysSooner: deltas[model.id],
                        flashStamp: flashStamps[model.id] ?? 0,
                        staggerIndex: staggered ? index : nil
                    )
                }
            }
            .background(alignment: .topLeading) {
                TimelineGrid(scale: scale, today: store.now)
                    .padding(.leading, PlanRow.indexWidth)
            }
        }
    }

    // MARK: Daily time

    private var displayedMinutes: Int {
        min(max(store.preferences.dailyMinutes, MinutesDial.range.lowerBound), MinutesDial.range.upperBound)
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { displayedMinutes },
            set: { newValue in
                guard newValue != store.preferences.dailyMinutes else { return }
                adjust { $0.dailyMinutes = newValue }
            }
        )
    }

    private var dailyTime: some View {
        let minutes = displayedMinutes
        let preview = OnboardingCopy.minutesPreview(
            minutes: minutes,
            wpm: store.wpm,
            daysPerWeek: store.preferences.readingDays.count
        )
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Daily time")
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("\(minutes)")
                    .leafStyle(.display)
                    .contentTransition(.numericText(value: Double(minutes)))
                    .leafAnimation(Motion.paper, value: minutes)
                Text("min a day")
                    .leafStyle(.eyebrow)
            }
            .accessibilityHidden(true)
            TickRuler(
                range: MinutesDial.range,
                value: minutesBinding,
                spacing: 8,
                majorEvery: 5,
                labels: MinutesDial.labelled,
                rigidAtLabels: true,
                voiceOverLabel: "Minutes a day",
                adjustStep: 5,
                valueDescription: { "\($0) minutes" }
            )
            Text(preview.quote)
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)
            Text(preview.caption)
                .leafStyle(.caption)
                .padding(.top, Space.xs)
        }
    }

    // MARK: Next seven days

    private var nextDays: some View {
        let days = Array(plan.days.prefix(7))
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Next 7 days")
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                PlanDayRow(
                    day: day,
                    entries: entries(for: day),
                    isToday: index == 0,
                    isDone: index == 0 && store.goalMetToday,
                    calendar: store.calendar
                )
            }
        }
    }

    private func entries(for day: PlanDay) -> [PlanDayEntry] {
        day.assignments.compactMap { assignment in
            store.item(assignment.bookID).map { PlanDayEntry(book: $0.book, assignment: assignment) }
        }
    }

    // MARK: Footer

    private var footer: some View {
        let prefs = store.preferences
        let days = prefs.readingDays.count
        let line = "\(prefs.dailyMinutes) min a day · \(days) \(days == 1 ? "day" : "days") a week · \(Int(store.wpm.rounded())) wpm"
        return VStack(alignment: .leading, spacing: Space.s) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(line)
                    .leafStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                TextButton("Change") {
                    Haptics.shared.tap()
                    router.showSettings = true
                }
            }
        }
        .padding(.top, Space.xxl)
    }

    // MARK: Reflow

    /// Applies a preference change with the timeline reflowing live. Remembers where finish dates stood
    /// before the burst so the chips can say how far each moved, and lets them go 2.5 s after the last change.
    private func adjust(riffles: Bool = false, staggerRows: Bool = false, _ change: (inout ReadingPreferences) -> Void) {
        let calendar = store.calendar
        let before = PlanReflow.finishes(of: store.plan)
        let beforeEnd = scale.end
        if baseline.isEmpty { baseline = before }
        staggered = staggerRows

        var moved: [String: Int] = [:]
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            store.updatePreferences(change)
            let after = PlanReflow.finishes(of: store.plan)
            moved = PlanReflow.deltas(from: before, to: after, calendar: calendar)
            deltas = PlanReflow.deltas(from: baseline, to: after, calendar: calendar)
            axisHold = max(beforeEnd, naturalScale.end)
        }

        if riffles, !moved.isEmpty {
            let riffle = PlanReflow.riffle(for: moved)
            Haptics.shared.riffle(count: riffle.count, earlier: riffle.earlier)
        }
        scheduleSettle()
    }

    /// Once the changes stop: flash the dates that moved, then drop the chips and let the axis re-fit.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            for id in deltas.keys { flashStamps[id, default: 0] += 1 }
            try? await Task.sleep(for: .seconds(Motion.deltaChipDuration))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                deltas = [:]
                baseline = [:]
                axisHold = nil
            }
            staggered = false
        }
    }

    private func resetReflow() {
        settleTask?.cancel()
        settleTask = nil
        deltas = [:]
        baseline = [:]
        axisHold = nil
        staggered = false
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
    var body: some View {
        NavigationStack {
            PlanView()
                .navigationDestination(for: BookRoute.self) { route in
                    Text(route.book.title)
                }
        }
    }
}

#Preview("Plan") {
    PlanPreviewHost()
        .environment(planPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Plan · dark") {
    PlanPreviewHost()
        .environment(planPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
        .preferredColorScheme(.dark)
}

#Preview("Plan · side by side") {
    PlanPreviewHost()
        .environment(planPreviewStore { store in
            store.updatePreferences { $0.planMode = .sideBySide }
        })
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Plan · empty") {
    PlanPreviewHost()
        .environment(LibraryStore(persistence: .ephemeral()))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
