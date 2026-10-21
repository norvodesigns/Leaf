import SwiftUI

/// The Forecast page of the Plan tab (NEXT.md section 10): what is likely, not just what is planned. The year and each
/// book in Reading get a fan chart with the narrator's sentence; then the small kindnesses (tonight only, catching up,
/// a book gone quiet); then what-if controls whose changes stay hypothetical until kept; then the plan itself as a
/// running order, the next seven days, and a quiet line on how accurate past forecasts have been.
///
/// Every number comes from `PlanDesk`, which runs the engines off the main actor, and every number has its sentence.
struct ForecastPage: View {
    let desk: PlanDesk

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The what-if controls. They start at the reader's own plan; anything else is a what-if.
    @State private var minutes = 25
    @State private var days: Set<Int> = []
    @State private var didLoad = false

    /// The plan-style switch reflows the running order live (as the old Plan screen did).
    @State private var baseline: [String: Date] = [:]
    @State private var deltas: [String: Int] = [:]
    @State private var flashStamps: [String: Int] = [:]
    @State private var axisHold: Date?
    @State private var staggered = false
    @State private var settleTask: Task<Void, Never>?

    private var narrator: ForecastNarrator { ForecastNarrator(now: store.now, calendar: store.calendar) }
    private var preferences: ReadingPreferences { store.preferences }
    private var isWhatIf: Bool { didLoad && (minutes != displayedMinutes(preferences.dailyMinutes) || days != preferences.readingDays) }
    /// The plan with the what-if applied once it has been worked out.
    private var shownPlan: ReadingPlan { (isWhatIf ? desk.whatIf?.plan : nil) ?? store.plan }
    private var shownResult: ForecastResult? { (isWhatIf ? desk.whatIf : nil) ?? desk.forecast?.result }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .coachMarkAnchor("plan.forecast")
                .inkIn(0)
            yearCard
                .padding(.top, Space.xl)
                .inkIn(1)
            nowReading
                .inkIn(2)
            care
            whatIfSection
                .coachMarkAnchor("plan.whatif")
                .id("whatif")
            runningOrder
                .id("order")
            nextDays
            footer
        }
        .onAppear(perform: load)
        .onChange(of: minutes) { _, _ in runWhatIf() }
        .onChange(of: days) { _, _ in runWhatIf() }
        .onChange(of: preferences.dailyMinutes) { _, newValue in
            minutes = displayedMinutes(newValue)
        }
        .onChange(of: preferences.readingDays) { _, newValue in
            days = newValue
        }
        .onDisappear(perform: resetReflow)
    }

    private func load() {
        guard !didLoad else { return }
        minutes = displayedMinutes(preferences.dailyMinutes)
        days = preferences.readingDays
        if router.planStage == "whatif" {
            // Screenshots: a what-if of a quarter of an hour more each day.
            minutes = displayedMinutes(preferences.dailyMinutes + 15)
        }
        didLoad = true
        runWhatIf()
    }

    private func displayedMinutes(_ value: Int) -> Int {
        min(max(value, MinutesDial.range.lowerBound), MinutesDial.range.upperBound)
    }

    private func runWhatIf() {
        guard didLoad else { return }
        guard isWhatIf, !days.isEmpty else {
            desk.clearWhatIf()
            return
        }
        let newMinutes = minutes == displayedMinutes(preferences.dailyMinutes) ? nil : minutes
        let newDays = days == preferences.readingDays ? nil : days
        desk.runWhatIf(dailyMinutes: newMinutes, readingDays: newDays, store: store)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(eyebrowLine)
                .leafStyle(.eyebrow)
                .contentTransition(.numericText())
            if let year = (isWhatIf ? desk.whatIf?.year : nil) ?? desk.forecast?.result.year {
                Text(narrator.yearSentence(year))
                    .leafStyle(.pullQuote)
                    .fixedSize(horizontal: false, vertical: true)
                    .focusPullTransition()
            } else {
                Text("Working out the odds…")
                    .leafStyle(.pullQuote, color: .inkTertiary)
                    .focusPullTransition()
            }
        }
        .animation(reduceMotion ? nil : Motion.paper, value: desk.forecast == nil)
    }

    /// "6 books · through 14 March 2027" (uppercased on screen).
    private var eyebrowLine: String {
        let count = shownPlan.books.count
        let noun = count == 1 ? "book" : "books"
        guard let done = shownPlan.allDone else { return "\(count) \(noun)" }
        return "\(count) \(noun) · through \(LeafFormat.format(done, template: "dMMMMyyyy", calendar: store.calendar))"
    }

    // MARK: Year

    @ViewBuilder
    private var yearCard: some View {
        if let snapshot = desk.forecast {
            let year = (isWhatIf ? desk.whatIf?.year : nil) ?? snapshot.result.year
            TodayCard("\(String(year.year)) in books") {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("\(year.finishedSoFar)")
                            .leafStyle(.statNumeral)
                            .numericBlur(value: Double(year.finishedSoFar))
                        Text(year.goal.map { "of \($0) finished" } ?? "finished so far")
                            .leafStyle(.caption)
                        Spacer(minLength: 0)
                        if isWhatIf, let change = desk.comparison?.yearMedianChange, change != 0 {
                            Chip(change > 0 ? "+\(change) this year" : "\(change) this year", tone: change > 0 ? Chip.Tone.accent : Chip.Tone.ribbon)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(finishedSentence(year) + yearChangeSentence)
                    YearForecastChart(year: year, finishes: finishesThisYear(year.year), today: store.now, calendar: store.calendar)
                    if let caveat = yearCaveat(year) {
                        Text(caveat)
                            .leafStyle(.caption, color: .inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let goal = narrator.goalSentence(year) {
                        Text(goal)
                            .leafStyle(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // What the goal asks for, unless the goal sentence above already says it is in hand.
                    if !isWhatIf, let plan = snapshot.yearPlan, year.finishedSoFar < plan.target, plan.feasibility != .onTrack {
                        Text(narrator.yearPlanSentence(plan))
                            .leafStyle(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            TodayCard("This year") {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 170)
            }
        }
    }

    /// " A what-if adds one book this year." for VoiceOver, alongside the chip.
    private var yearChangeSentence: String {
        guard isWhatIf, let change = desk.comparison?.yearMedianChange, change != 0 else { return "" }
        let books = abs(change) == 1 ? "one book" : "\(narrator.number(abs(change))) books"
        return change > 0 ? " This what-if adds \(books) this year." : " This what-if means \(books) fewer this year."
    }

    /// Honest small print: the count includes books not chosen yet, or it's an early guess.
    private func yearCaveat(_ year: YearForecast) -> String? {
        var parts: [String] = []
        if year.includesFuturePicks { parts.append("Counts books you haven’t picked yet, read at your usual pace.") }
        if year.confidence == .low { parts.append("An early guess; it firms up as you read.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func finishedSentence(_ year: YearForecast) -> String {
        let books = year.finishedSoFar == 1 ? "1 book" : "\(year.finishedSoFar) books"
        guard let goal = year.goal else { return "\(books) finished this year." }
        return "\(books) finished this year, of a goal of \(goal)."
    }

    private func finishesThisYear(_ year: Int) -> [Date] {
        store.finished.compactMap(\.finishedAt)
            .filter { store.calendar.component(.year, from: $0) == year }
            .sorted()
    }

    // MARK: Now reading

    @ViewBuilder
    private var nowReading: some View {
        let reading = Array(store.reading.prefix(3))
        if !reading.isEmpty, let result = shownResult {
            SectionHeader("Now reading")
                .id("reading")
            VStack(spacing: Space.m) {
                ForEach(reading, id: \.id) { item in
                    if let forecast = result.book(item.id) {
                        BookForecastCard(
                            item: item,
                            forecast: forecast,
                            delta: isWhatIf ? desk.comparison?.delta(for: item.id) : nil,
                            narrator: narrator,
                            today: store.now,
                            calendar: store.calendar
                        ) {
                            router.planSheet = .finishLine(bookID: item.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: Care

    @ViewBuilder
    private var care: some View {
        let snapshot = desk.forecast
        let stalled = (snapshot?.stalled ?? []).filter { !desk.isKeptQuiet($0.bookID, now: store.now) && store.item($0.bookID)?.shelf == .reading }
        let tonight = snapshot?.tonight
        let tonightBookID = snapshot?.tonightBookID
        let showsTonight = (tonight?.daysEarlier ?? 0) > 0 && tonightBookID != nil
        // One missed day isn't worth a card; a real gap, or a mode the reader chose, is.
        let catchUp = (snapshot?.catchUp).flatMap { catchUp -> ForecastCatchUp? in
            catchUp.missedDays >= 2 || (catchUp.missedDays > 0 && catchUp.mode != .forgive) ? catchUp : nil
        }
        if showsTonight || catchUp != nil || !stalled.isEmpty {
            SectionHeader("For you")
                .id("care")
            VStack(spacing: Space.m) {
                if showsTonight, let tonight, let bookID = tonightBookID {
                    TodayCard("Tonight only", actionTitle: "Read now", action: {
                        _ = ReadingSessionLauncher.start(bookID: bookID, store: store, router: router, from: ReadingSessionLauncher.accessorySource)
                    }) {
                        // Said as days sooner rather than a date: the plan's date and the forecast's median differ, and
                        // the gain is the same either way.
                        Text(tonightLine(tonight, bookID: bookID))
                            .leafStyle(.pullQuote)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(tonight.extraMinutes) min on top of today’s \(preferences.dailyMinutes)")
                            .leafStyle(.caption)
                    }
                }
                if let catchUp {
                    CatchUpCard(catchUp: catchUp, narrator: narrator, mode: catchUpBinding)
                }
                ForEach(stalled) { book in
                    StallCard(stalled: book, narrator: narrator) {
                        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                            store.pause(book.bookID)
                        }
                    } onKeep: {
                        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                            desk.keepQuietBook(book.bookID, now: store.now)
                        }
                    }
                }
            }
        }
    }

    private func tonightLine(_ tonight: ForecastTonight, bookID: String) -> String {
        narrator.tonightGain(tonight, title: store.item(bookID)?.book.title ?? "your book")
    }

    private var catchUpBinding: Binding<CatchUpMode> {
        Binding(
            get: { store.preferences.catchUp },
            set: { mode in
                guard mode != store.preferences.catchUp else { return }
                Haptics.shared.selection()
                store.updatePreferences { $0.catchUp = mode }
            }
        )
    }

    // MARK: What if

    private var whatIfSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("What if")
            Text("Try another daily time or other reading days. Nothing changes until you keep it.")
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Space.l)
            MinutesDial(minutes: $minutes)
            WeekdayPicker(selection: $days)
                .padding(.top, Space.l)
            whatIfOutcome
                .padding(.top, Space.l)
                .animation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion), value: isWhatIf)
        }
    }

    @ViewBuilder
    private var whatIfOutcome: some View {
        if days.isEmpty {
            Text("Pick at least one day.")
                .leafStyle(.caption, color: .ribbon)
        } else if isWhatIf {
            VStack(alignment: .leading, spacing: Space.m) {
                if let comparison = desk.comparison, let result = desk.whatIf {
                    WhatIfSummary(comparison: comparison, result: result, narrator: narrator, titles: titles)
                        .focusPullTransition()
                } else {
                    HStack(spacing: Space.s) {
                        ProgressView()
                        Text("Working it out…").leafStyle(.caption)
                    }
                }
                PrimaryGlassButton("Keep this plan") {
                    keepWhatIf()
                }
                TextButton("Put it back", style: .caption, color: .inkSecondary) {
                    Haptics.shared.tap()
                    minutes = displayedMinutes(preferences.dailyMinutes)
                    days = preferences.readingDays
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            Text("This is your plan now: \(preferences.dailyMinutes) min on \(dayCount(preferences.readingDays)).")
                .leafStyle(.caption)
        }
    }

    private func dayCount(_ days: Set<Int>) -> String {
        days.count == 7 ? "every day" : (days.count == 1 ? "1 day a week" : "\(days.count) days a week")
    }

    private func titles(_ id: String) -> String {
        store.item(id)?.book.title ?? "This book"
    }

    private func keepWhatIf() {
        let newMinutes = minutes
        let newDays = days
        adjust { prefs in
            prefs.dailyMinutes = newMinutes
            prefs.readingDays = newDays
        }
        desk.adoptWhatIf()
    }

    // MARK: Running order

    private var rowModels: [PlanRowModel] {
        var models: [PlanRowModel] = []
        for planned in shownPlan.books {
            guard let item = store.item(planned.id) else { continue }
            models.append(PlanRowModel(number: models.count + 1, planned: planned, book: item.book))
        }
        return models
    }

    private var naturalScale: TimelineScale {
        TimelineScale(covering: shownPlan.books, today: store.now, calendar: store.calendar)
    }

    private var scale: TimelineScale {
        let natural = naturalScale
        guard let hold = axisHold, hold > natural.end else { return natural }
        return TimelineScale(start: natural.start, end: hold, calendar: store.calendar)
    }

    /// Days sooner per book: against the real plan during a what-if, else since the last plan-style switch.
    private var shownDeltas: [String: Int] {
        guard isWhatIf, let whatIf = desk.whatIf else { return deltas }
        return PlanReflow.deltas(from: PlanReflow.finishes(of: store.plan), to: PlanReflow.finishes(of: whatIf.plan), calendar: store.calendar)
    }

    private var runningOrder: some View {
        let scale = self.scale
        let models = rowModels
        let moved = shownDeltas
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader("The plan")
            Picker("Plan style", selection: modeBinding) {
                Text("One at a time").tag(PlanMode.focus)
                Text("Side by side").tag(PlanMode.sideBySide)
            }
            .pickerStyle(.segmented)
            Text(modeCaption)
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
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
                        daysSooner: moved[model.id],
                        flashStamp: flashStamps[model.id] ?? 0,
                        staggerIndex: staggered ? index : nil
                    )
                }
            }
            .background(alignment: .topLeading) {
                TimelineGrid(scale: scale, today: store.now)
                    .padding(.leading, PlanRow.indexWidth)
            }
            HStack(spacing: Space.s) {
                SecondaryGlassButton("Finish by a date", systemImage: "flag.checkered", compact: true) {
                    router.planSheet = .finishLine(bookID: nil)
                }
                if store.toRead.count >= 2 {
                    SecondaryGlassButton("Suggest an order", systemImage: "arrow.up.arrow.down", compact: true) {
                        router.planSheet = .smartOrder
                    }
                }
            }
            .padding(.top, Space.l)
        }
    }

    private var modeCaption: String {
        let base: String
        switch preferences.planMode {
        case .focus:
            base = "Finish one book, then begin the next."
        case .sideBySide:
            base = store.reading.count < 2
                ? "Your time is split across everything in Reading. With one book open, nothing changes yet."
                : "Your daily time is split across every book in Reading."
        }
        return base + " These dates assume every planned minute; the forecast above allows for real life."
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

    // MARK: Next seven days

    private var nextDays: some View {
        let days = Array(shownPlan.days.prefix(7))
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(isWhatIf ? "Next 7 days, if so" : "Next 7 days")
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
        VStack(alignment: .leading, spacing: Space.s) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(assumptionLine)
                    .leafStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                TextButton("Change") {
                    Haptics.shared.tap()
                    router.showSettings = true
                }
            }
            if let backtest = desk.backtest {
                Text(narrator.backtestSentence(backtest))
                    .leafStyle(.caption, color: .inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(.top, Space.xxl)
        .animation(Motion.fade, value: desk.backtest == nil)
    }

    /// "From 13 sittings: 25 min a day, about 5 days a week, 262 words a minute."
    private var assumptionLine: String {
        guard let assumptions = desk.forecast?.result.assumptions else {
            let days = preferences.readingDays.count
            return "\(preferences.dailyMinutes) min a day · \(days) \(days == 1 ? "day" : "days") a week · \(Int(store.wpm.rounded())) wpm"
        }
        guard assumptions.sessionCount > 0 else {
            return "\(assumptions.dailyMinutes) min a day at \(Int(assumptions.paceWPM.rounded())) words a minute, until your first sittings show your real rhythm."
        }
        let sittings = assumptions.sessionCount == 1 ? "1 sitting" : "\(assumptions.sessionCount) sittings"
        let perWeek = Int(assumptions.expectedDaysPerWeek.rounded())
        return "From \(sittings): \(assumptions.dailyMinutes) min a day, about \(perWeek) \(perWeek == 1 ? "day" : "days") a week, \(Int(assumptions.paceWPM.rounded())) words a minute."
    }

    // MARK: Reflow

    /// Applies a preference change with the running order reflowing live, and remembers where finish dates stood so
    /// the chips can say how far each moved. The chips go 2.5 s after the last change.
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

// MARK: - Cards

/// One book in Reading: its cover, the narrator's sentence, the fan chart, and a way into "finish by a date".
struct BookForecastCard: View {
    let item: LibraryItem
    let forecast: BookForecast
    /// How a what-if moves it, if one is being tried.
    let delta: ForecastBookDelta?
    let narrator: ForecastNarrator
    let today: Date
    let calendar: Calendar
    let onFinishLine: () -> Void

    var body: some View {
        TodayCard("p. \(item.currentPage) of \(item.book.pages)", actionTitle: "Finish by…", action: onFinishLine) {
            HStack(alignment: .top, spacing: Space.m) {
                BookCover(book: item.book, size: .s)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(item.book.title)
                        .leafStyle(.headline)
                        .lineLimit(2)
                    Text(narrator.bookSentence(forecast))
                        .leafStyle(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    if let delta, let earlier = delta.medianDaysEarlier, earlier != 0 {
                        DeltaChip(daysSooner: earlier)
                            .accessibilityLabel(narrator.changeSentence(delta))
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if forecast.median != nil {
                BookFanChart(
                    title: item.book.title,
                    forecast: forecast,
                    currentPage: item.currentPage,
                    pages: item.book.pages,
                    narrator: narrator,
                    calendar: calendar,
                    today: today
                )
            }
            Text(confidenceLine)
                .leafStyle(.caption, color: .inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confidenceLine: String {
        let sittings = forecast.sessions == 1 ? "1 sitting" : "\(forecast.sessions) sittings"
        if forecast.positionUncertain { return "A rough guess until you confirm your page." }
        if forecast.sessions == 0 { return "From your pace overall; no sittings with this book yet." }
        switch forecast.confidence {
        case .low: return "A rough guess from \(sittings) with this book."
        case .medium: return "Getting clearer, from \(sittings) with this book."
        case .high: return "A confident range, from \(sittings) with this book."
        }
    }
}

/// Missed days, and what the plan does about them: forgive (the default), shift the dates, or catch up gently.
struct CatchUpCard: View {
    let catchUp: ForecastCatchUp
    let narrator: ForecastNarrator
    @Binding var mode: CatchUpMode

    var body: some View {
        TodayCard("Catching up") {
            Text(narrator.catchUpSentence(catchUp))
                .leafStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
            Picker("When you miss a day", selection: $mode) {
                Text("Forgive").tag(CatchUpMode.forgive)
                Text("Shift").tag(CatchUpMode.shift)
                Text("Catch up").tag(CatchUpMode.compress)
            }
            .pickerStyle(.segmented)
            Text(caption)
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caption: String {
        switch mode {
        case .forgive: "Leaf moves on. Nothing to make up, and no guilt."
        case .shift: "Leaf tells you how far your finish dates moved."
        case .compress: "Leaf suggests a few extra minutes a day until you’re back on track."
        }
    }
}

/// A book that has gone quiet: set it aside (it keeps its page), or keep it where it is.
struct StallCard: View {
    let stalled: StalledBook
    let narrator: ForecastNarrator
    let onSetAside: () -> Void
    let onKeep: () -> Void

    var body: some View {
        TodayCard(stalled.suggestion == .setAside ? "Gone quiet" : "Nearly there") {
            Text(narrator.stallSentence(stalled))
                .leafStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.m) {
                if stalled.suggestion == .setAside {
                    SecondaryGlassButton("Set it aside", compact: true, action: onSetAside)
                }
                TextButton(stalled.suggestion == .setAside ? "Keep it" : "Thanks", style: .caption, color: .inkSecondary) {
                    Haptics.shared.tap()
                    onKeep()
                }
            }
        }
    }
}

/// What a what-if changes: the year, the goal's odds, and each book's finish, every number with its sentence.
struct WhatIfSummary: View {
    let comparison: ForecastComparison
    let result: ForecastResult
    let narrator: ForecastNarrator
    let titles: (String) -> String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(narrator.yearSentence(result.year))
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
            if let change = comparison.goalProbabilityChange, abs(change) >= 0.01 {
                let points = Int((change * 100).rounded())
                Text(points > 0 ? "The goal gets \(points) points likelier." : "The goal gets \(-points) points less likely.")
                    .leafStyle(.caption)
            }
            ForEach(comparison.books.filter { ($0.medianDaysEarlier ?? 0) != 0 }.prefix(4), id: \.bookID) { delta in
                Group {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(titles(delta.bookID))
                                .leafStyle(.headline)
                            DeltaChip(daysSooner: delta.medianDaysEarlier ?? 0)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text(titles(delta.bookID))
                                .leafStyle(.headline)
                                .lineLimit(2)
                                .layoutPriority(1)
                            LeaderDots()
                            DeltaChip(daysSooner: delta.medianDaysEarlier ?? 0)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(titles(delta.bookID)). \(narrator.changeSentence(delta))")
            }
        }
    }
}

extension ForecastNarrator {
    /// "Eight more minutes tonight brings The Hobbit a day sooner." The gain in days rather than a date, because the
    /// plan's date and the forecast's median for the same book differ and the gain is the same either way.
    func tonightGain(_ tonight: ForecastTonight, title: String) -> String {
        let spoken = number(tonight.extraMinutes)
        let minutes = tonight.extraMinutes == 1 ? "One more minute" : spoken.prefix(1).uppercased() + spoken.dropFirst() + " more minutes"
        let days = tonight.daysEarlier == 1 ? "a day" : "\(number(tonight.daysEarlier)) days"
        return "\(minutes) tonight brings \(title) \(days) sooner."
    }
}
