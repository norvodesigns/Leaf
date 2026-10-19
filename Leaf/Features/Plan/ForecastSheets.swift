import SwiftUI

// MARK: - Finish line

/// "Finish by a date": pick a book and scrub to a date (a book club, a holiday, the end of the year). While the date
/// moves, the plan's own arithmetic says roughly how many minutes a day it takes; once it settles, the forecast works
/// out the honest answer (`inversePlan`) with its odds, and the reader can make that their daily time.
struct FinishLineSheet: View {
    let desk: PlanDesk
    var initialBookID: String?

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bookID: String?
    @State private var offset = 30
    @State private var answer: ForecastInversePlan?
    @State private var didLoad = false

    private struct Question: Hashable {
        var bookID: String?
        var offset: Int
    }

    private var narrator: ForecastNarrator { ForecastNarrator(now: store.now, calendar: store.calendar) }
    private var candidates: [LibraryItem] { store.reading + store.toRead }
    private var item: LibraryItem? { bookID.flatMap { store.item($0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Pick a date, a book club or a holiday or the end of the year, and see what it takes.")
                        .leafStyle(.body, color: .inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    bookPicker
                    if let item {
                        FinishByScrub(scrub: dateScrub(for: item), offset: $offset, magnetOffsets: magnets(for: item.id))
                            .id(item.id)
                        answerCard
                    } else {
                        EmptyState(title: "Nothing to aim for yet.", message: "Add a book to Reading or To read first.")
                    }
                }
                .leafMargins()
                .padding(.top, Space.m)
                .padding(.bottom, Space.section)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .paperBackground()
            .navigationTitle("Finish line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: load)
        .task(id: Question(bookID: bookID, offset: offset)) {
            await ask()
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let id = initialBookID ?? store.plan.books.first?.id ?? candidates.first?.id
        choose(id)
    }

    private func choose(_ id: String?) {
        bookID = id
        answer = nil
        let likely = id.flatMap { desk.forecast?.result.book($0)?.medianOffset } ?? 30
        offset = min(max(likely, 1), 365)
    }

    private var bookPicker: some View {
        Menu {
            ForEach(candidates, id: \.id) { candidate in
                Button {
                    Haptics.shared.selection()
                    choose(candidate.id)
                } label: {
                    if candidate.id == bookID {
                        Label(candidate.book.title, systemImage: "checkmark")
                    } else {
                        Text(candidate.book.title)
                    }
                }
            }
        } label: {
            HStack(spacing: Space.m) {
                if let item { BookCover(book: item.book, size: .s) }
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("Book")
                    Text(item?.book.title ?? "Choose a book")
                        .leafStyle(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(Color.inkTertiary)
            }
            .padding(Space.m)
            .background(Color.paperRaised, in: Radius.shape(Radius.tile))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Book, \(item?.book.title ?? "none")")
        .accessibilityHint("Choose which book to finish")
    }

    /// The plan's arithmetic for the scrub's running line: the minutes still to read through this book (and the books
    /// ahead of it), shared over the reading days before the date.
    private func dateScrub(for item: LibraryItem) -> DateScrub {
        var needed = 0.0
        for planned in store.plan.books {
            needed += planned.minutesLeft
            if planned.id == item.id { break }
        }
        if needed == 0 { needed = item.minutesLeft(atWPM: store.wpm) }
        let perWeek = Double(max(1, store.preferences.readingDays.count))
        let minutes = needed
        return DateScrub(start: store.now, calendar: store.calendar, earliestDay: 1, latestDay: 365) { _, days in
            let readingDays = max(1, Double(days) * perWeek / 7)
            return minutes / readingDays
        }
    }

    /// Dates worth a detent: the likely finish, Christmas, and the last day of the year.
    private func magnets(for id: String) -> [Int] {
        let calendar = store.calendar
        let today = calendar.startOfDay(for: store.now)
        var offsets: [Int] = []
        if let likely = desk.forecast?.result.book(id)?.medianOffset { offsets.append(likely) }
        let year = calendar.component(.year, from: store.now)
        for (month, day) in [(12, 25), (12, 31)] {
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               let days = calendar.dateComponents([.day], from: today, to: date).day, days > 0 {
                offsets.append(days)
            }
        }
        return offsets
    }

    private func ask() async {
        guard let id = bookID else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let target = store.calendar.date(byAdding: .day, value: offset, to: store.calendar.startOfDay(for: store.now)) ?? store.now
        let result = await desk.inversePlan(bookID: id, by: target, store: store)
        guard !Task.isCancelled else { return }
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) { answer = result }
    }

    @ViewBuilder
    private var answerCard: some View {
        TodayCard("What it takes") {
            if let answer {
                Text(narrator.inverseSentence(answer))
                    .leafStyle(.pullQuote)
                    .fixedSize(horizontal: false, vertical: true)
                    .focusPullTransition()
                if let minutes = answer.minutesPerDay, answer.feasibility != .impossible {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("\(minutes)")
                            .leafStyle(.statNumeral)
                            .numericBlur(value: Double(minutes))
                        Text("min a day, from \(answer.currentMinutes) now")
                            .leafStyle(.caption)
                        Spacer(minLength: 0)
                        Chip(feasibilityLabel(answer.feasibility), tone: answer.feasibility == .stretch ? Chip.Tone.ribbon : Chip.Tone.accent)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(minutes) minutes a day, from \(answer.currentMinutes) now. \(feasibilityLabel(answer.feasibility)).")
                    if let tonight = answer.tonight, tonight.daysEarlier > 0 {
                        Text(narrator.tonightGain(tonight, title: item?.book.title ?? "it"))
                            .leafStyle(.caption)
                    }
                    // Offer a new daily time only when the date needs more than the reader gives now; the comfortable
                    // margin is the honest number to offer.
                    // The button saves exactly what it says, within what the daily-time dial allows.
                    let offer = min(max(minutes, answer.likelyMinutesPerDay ?? minutes), MinutesDial.range.upperBound)
                    if answer.feasibility != .onTrack, offer > store.preferences.dailyMinutes {
                        PrimaryGlassButton("Make it \(offer) min a day") {
                            store.updatePreferences { $0.dailyMinutes = offer }
                            dismiss()
                        }
                    }
                }
            } else {
                HStack(spacing: Space.s) {
                    ProgressView()
                    Text("Working it out…").leafStyle(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
        }
    }

    private func feasibilityLabel(_ feasibility: ForecastFeasibility) -> String {
        switch feasibility {
        case .onTrack: "On track"
        case .reachable: "Reachable"
        case .stretch: "A stretch"
        case .impossible: "Out of reach"
        }
    }
}

// MARK: - Smart order

/// A suggested To read order for a goal (most books by the end of the year, a change of genre each time, or a short
/// read after a long one), previewed with how many days each book moves before the reader applies it.
struct SmartOrderSheet: View {
    let desk: PlanDesk

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var goal: Goal = .mostFinished
    @State private var suggestion: OrderSuggestion?

    enum Goal: String, CaseIterable, Identifiable {
        case mostFinished, alternate, cleanser

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mostFinished: "Most books"
            case .alternate: "Mix it up"
            case .cleanser: "Breathers"
            }
        }
    }

    private var narrator: ForecastNarrator { ForecastNarrator(now: store.now, calendar: store.calendar) }

    private var yearEnd: Date {
        guard let interval = store.calendar.dateInterval(of: .year, for: store.now) else { return store.now }
        return interval.end.addingTimeInterval(-1)
    }

    private var engineGoal: ForecastOrderGoal {
        switch goal {
        case .mostFinished: .mostFinished(by: yearEnd)
        case .alternate: .alternateGenres
        case .cleanser: .palateCleanser
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Picker("Order for", selection: $goal) {
                        ForEach(Goal.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if let suggestion {
                        Text(narrator.orderSentence(suggestion))
                            .leafStyle(.pullQuote)
                            .fixedSize(horizontal: false, vertical: true)
                            .focusPullTransition()
                        rows(suggestion)
                        PrimaryGlassButton(suggestion.isChange ? "Use this order" : "Keep my order") {
                            if suggestion.isChange {
                                store.applyQueueOrder(suggestion.suggestedOrder)
                                Haptics.shared.play(.pageTurn)
                            }
                            dismiss()
                        }
                        .padding(.top, Space.s)
                    } else {
                        HStack(spacing: Space.s) {
                            ProgressView()
                            Text("Trying the orders…").leafStyle(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .leafMargins()
                .padding(.top, Space.m)
                .padding(.bottom, Space.section)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .paperBackground()
            .navigationTitle("Suggest an order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task(id: goal) {
            suggestion = nil
            let result = await desk.smartOrder(goal: engineGoal, store: store)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) { suggestion = result }
        }
    }

    private func rows(_ suggestion: OrderSuggestion) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestion.suggestedOrder.enumerated()), id: \.element) { index, id in
                if let item = store.item(id) {
                    let delta = suggestion.deltas.first { $0.bookID == id }
                    let change = suggestion.changes.first { $0.bookID == id }
                    HStack(alignment: .center, spacing: Space.m) {
                        IndexNumeral(index + 1)
                        if !typeSize.isAccessibilitySize {
                            BookCover(book: item.book, size: .s)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.book.title)
                                .leafStyle(.headline)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            Text(detail(change: change, delta: delta))
                                .leafStyle(.caption)
                            if typeSize.isAccessibilitySize, let days = delta?.daysEarlier, days != 0 {
                                DeltaChip(daysSooner: days)
                            }
                        }
                        Spacer(minLength: 0)
                        if !typeSize.isAccessibilitySize, let days = delta?.daysEarlier, days != 0 {
                            DeltaChip(daysSooner: days)
                        }
                    }
                    .padding(.vertical, Space.s)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(index + 1). \(item.book.title). \(spoken(change: change, delta: delta))")
                    Hairline()
                }
            }
        }
    }

    private func reason(_ reason: ForecastOrderReason) -> String {
        switch reason {
        case .shorterFirst: "shorter, so sooner"
        case .differentGenre: "a change of genre"
        case .palateCleanser: "a short breather"
        }
    }

    private func detail(change: OrderChange?, delta: OrderDelta?) -> String {
        var parts: [String] = []
        if let change, change.fromIndex != change.toIndex { parts.append("was \(change.fromIndex + 1) · \(reason(change.reason))") }
        if let finish = delta?.suggestedFinish { parts.append("done \(LeafFormat.format(finish, template: "MMMd", calendar: store.calendar))") }
        return parts.isEmpty ? "No change" : parts.joined(separator: " · ")
    }

    private func spoken(change: OrderChange?, delta: OrderDelta?) -> String {
        var parts: [String] = []
        if let change, change.fromIndex != change.toIndex { parts.append("Moves from number \(change.fromIndex + 1), \(reason(change.reason)).") }
        if let finish = delta?.suggestedFinish { parts.append("Probably done \(narrator.day(finish)).") }
        if let days = delta?.daysEarlier, days != 0 {
            parts.append(days > 0 ? "\(days) \(days == 1 ? "day" : "days") sooner." : "\(-days) \(days == -1 ? "day" : "days") later.")
        }
        return parts.isEmpty ? "No change." : parts.joined(separator: " ")
    }
}
