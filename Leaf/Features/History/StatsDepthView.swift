import SwiftUI

/// The deeper numbers (`InsightsDepth`): pace by genre and by time of day, streaks, best weeks, year by year, books
/// set aside, authors and decades, for a date range of the reader's choosing.
struct StatsDepthView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var preset: InsightsRange = .thisYear
    @State private var isCustom = false
    @State private var customStart = Date()
    @State private var customEnd = Date()

    private var interval: DateInterval {
        if isCustom {
            let start = min(customStart, customEnd)
            return DateInterval(start: store.calendar.startOfDay(for: start), end: store.calendar.startOfDay(for: max(customStart, customEnd)))
        }
        return preset.interval(data: store.data, now: store.now, calendar: store.calendar)
    }

    var body: some View {
        let depth = InsightsEngine(data: store.data, now: store.now, calendar: store.calendar).depth(in: interval)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                rangeControl
                headline(depth)
                if depth.isEmpty {
                    Text("No reading in these dates. Try a wider range.")
                        .canopyText(.body, color: Canopy.textSecondary)
                        .padding(.top, Space.l)
                } else {
                    pace("Pages an hour, by genre", depth.byGenre, empty: "Pace by genre shows once there’s half an hour of timed reading in a genre.")
                    pace("Pages an hour, by time of day", depth.byTimeOfDay, empty: "Pace by time of day shows once there’s half an hour of timed reading at that time.")
                    streaks(depth.streaks)
                    weeks(depth.bestWeeks)
                    setAside(depth.setAside)
                    groups("Authors", depth.authors, unit: "book")
                    groups("Decades", depth.decades, unit: "book")
                }
                years(depth.years)
            }
            .leafMargins()
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxxl)
        }
        .scrollIndicators(.hidden)
        .paperBackground()
        .navigationTitle("Your numbers")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            applyStage()
        }
    }

    // MARK: Range

    private var rangeControl: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            TeaFlowLayout(spacing: Space.s) {
                    ForEach(InsightsRange.allCases, id: \.self) { range in
                        chip(range.title, isOn: !isCustom && preset == range) {
                            preset = range
                            isCustom = false
                        }
                    }
                    chip("Dates…", isOn: isCustom) {
                        if !isCustom {
                            let current = preset.interval(data: store.data, now: store.now, calendar: store.calendar)
                            customStart = current.start
                            customEnd = current.end
                        }
                        isCustom = true
                    }
            }
            if isCustom {
                HStack(spacing: Space.m) {
                    DatePicker("From", selection: $customStart, in: ...store.now, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, in: ...store.now, displayedComponents: .date)
                }
                .labelsHidden()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("From and to dates")
            }
            Text(rangeLine)
                .canopyText(.caption)
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            CanopyFeel.play(.select)
            action()
        } label: {
            Chip(title, systemImage: isOn ? "checkmark" : nil, tone: isOn ? .accent : .neutral)
                .frame(minHeight: Space.hitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    /// "1 Jan 2026 to 20 Oct 2026"
    private var rangeLine: String {
        let calendar = store.calendar
        let interval = interval
        return "\(LeafFormat.format(interval.start, template: "dMMMyyyy", calendar: calendar)) to \(LeafFormat.format(interval.end, template: "dMMMyyyy", calendar: calendar))"
    }

    // MARK: Headline

    private func headline(_ depth: InsightsDepth) -> some View {
        StatTileRow {
            StatTile(value: "\(depth.booksFinished)", label: depth.booksFinished == 1 ? "Book finished" : "Books finished")
            StatTile(value: LeafFormat.number(depth.pages), label: "Pages")
            StatTile(value: LeafFormat.duration(minutes: depth.minutes), label: "Reading")
        }
        .padding(.top, Space.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(depth.booksFinished) books finished, \(depth.pages) pages, \(LeafFormat.duration(minutes: depth.minutes)) of reading")
    }

    // MARK: Pace

    @ViewBuilder
    private func pace(_ title: String, _ rows: [InsightsDepth.Pace], empty: String) -> some View {
        CanopyLabel(title, accent: .bloom)
                        .padding(.top, Space.xxl)
        if rows.isEmpty {
            Text(empty)
                .canopyText(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let top = rows.map(\.pagesPerHour).max() ?? 1
            VStack(spacing: Space.s) {
                ForEach(rows) { row in
                    DepthBar(
                        label: MixCard.display(row.name),
                        value: "\(Int(row.pagesPerHour.rounded())) pages",
                        detail: LeafFormat.duration(minutes: row.minutes),
                        fraction: top > 0 ? row.pagesPerHour / top : 0
                    )
                }
            }
        }
    }

    // MARK: Streaks and weeks

    @ViewBuilder
    private func streaks(_ rows: [InsightsDepth.Streak]) -> some View {
        CanopyLabel("Longest runs", accent: .bloom)
                        .padding(.top, Space.xxl)
        if rows.isEmpty {
            Text("Two reading days in a row (rest days don’t break a run) start the list.")
                .canopyText(.caption)
        } else {
            VStack(spacing: 0) {
                ForEach(rows) { streak in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("\(streak.days)")
                            .canopyText(.stat)
                            .frame(minWidth: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text("days in a row\(streak.isCurrent ? ", and counting" : "")")
                                .canopyText(.body)
                            Text("\(day(streak.first)) to \(day(streak.last))")
                                .canopyText(.caption)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, Space.xs)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func weeks(_ rows: [InsightsDepth.Week]) -> some View {
        CanopyLabel("Best weeks", accent: .bloom)
                        .padding(.top, Space.xxl)
        VStack(spacing: 0) {
            ForEach(rows) { week in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("Week of \(day(week.start))")
                        .canopyText(.headline)
                    LeaderDots()
                    Text(LeafFormat.duration(minutes: week.minutes))
                        .canopyText(.callout).monospacedDigit()
                }
                .padding(.top, Space.xs)
                Text("\(LeafFormat.number(week.pages)) pages · \(week.sittings) \(week.sittings == 1 ? "sitting" : "sittings") · \(week.daysRead) \(week.daysRead == 1 ? "day" : "days")")
                    .canopyText(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Space.xs)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Set aside

    @ViewBuilder
    private func setAside(_ aside: InsightsDepth.SetAside) -> some View {
        CanopyLabel("Set aside", accent: .bloom)
                        .padding(.top, Space.xxl)
        if aside.started == 0 {
            Text("No books begun in these dates.")
                .canopyText(.caption)
        } else {
            Text(setAsideLine(aside))
                .canopyText(.quote, color: Canopy.text)
                .fixedSize(horizontal: false, vertical: true)
            if !aside.titles.isEmpty {
                Text(aside.titles.prefix(4).joined(separator: " · "))
                    .canopyText(.caption)
                    .padding(.top, Space.xs)
            }
        }
    }

    /// "Of 14 books begun, you finished 11 and set 2 aside: one in seven, without guilt."
    private func setAsideLine(_ aside: InsightsDepth.SetAside) -> String {
        let begun = "Of \(aside.started) \(aside.started == 1 ? "book" : "books") begun"
        guard aside.setAside > 0 else {
            return aside.finished > 0 ? "\(begun), none were set aside. \(aside.finished) finished." : "\(begun), none finished or set aside yet."
        }
        let percent = Int(((aside.rate ?? 0) * 100).rounded())
        return "\(begun), you finished \(aside.finished) and set \(aside.setAside) aside: \(percent)% of those that ended, and no guilt in it."
    }

    // MARK: Authors and decades

    @ViewBuilder
    private func groups(_ title: String, _ rows: [InsightsDepth.Group], unit: String) -> some View {
        if !rows.isEmpty {
            CanopyLabel(title, accent: .bloom)
                        .padding(.top, Space.xxl)
            let top = Double(rows.map(\.books).max() ?? 1)
            VStack(spacing: Space.s) {
                ForEach(rows) { row in
                    DepthBar(
                        label: row.name,
                        value: "\(row.books) \(row.books == 1 ? unit : unit + "s")",
                        detail: "\(LeafFormat.number(row.pages)) pages",
                        fraction: top > 0 ? Double(row.books) / top : 0
                    )
                }
            }
        }
    }

    // MARK: Years

    @ViewBuilder
    private func years(_ rows: [InsightsDepth.YearRow]) -> some View {
        if !rows.isEmpty {
            CanopyLabel("Year by year", accent: .bloom)
                        .padding(.top, Space.xxl)
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                        Text(String(row.year))
                            .canopyText(.stat)
                            .frame(minWidth: 72, alignment: .leading)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text("\(row.booksFinished) \(row.booksFinished == 1 ? "book" : "books") · \(LeafFormat.number(row.pages)) pages")
                                .canopyText(.body)
                            Text(yearDetail(row))
                                .canopyText(.caption)
                        }
                        Spacer(minLength: 0)
                        if let average = row.averageRating {
                            TeaLeaves(rating: Int(average.rounded()))
                        }
                    }
                    .padding(.vertical, Space.s)
                    .accessibilityElement(children: .combine)
                    Divider().overlay(Canopy.separator)
                }
            }
        }
    }

    private func yearDetail(_ row: InsightsDepth.YearRow) -> String {
        var parts = [LeafFormat.duration(minutes: row.minutes), "\(row.daysRead) \(row.daysRead == 1 ? "day" : "days") read"]
        if let pace = row.pagesPerHour { parts.append("\(Int(pace.rounded())) pages an hour") }
        return parts.joined(separator: " · ")
    }

    private func day(_ date: Date) -> String {
        LeafFormat.format(date, template: "dMMMyyyy", calendar: store.calendar)
    }

    /// Screenshot staging: "range" shows the custom dates.
    private func applyStage() {
        guard let stage = router.historyStage else { return }
        router.historyStage = nil
        if stage == "alltime" { preset = .allTime }
        if stage == "range" {
            customStart = store.calendar.date(byAdding: .month, value: -3, to: store.now) ?? store.now
            customEnd = store.now
            isCustom = true
        }
    }
}

/// A labelled bar: the label and value above, a thin accent bar sized against the largest row.
private struct DepthBar: View {
    let label: String
    let value: String
    let detail: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(label)
                    .canopyText(.body)
                    .lineLimit(1)
                Spacer(minLength: Space.s)
                Text(value)
                    .canopyText(.callout).monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Canopy.separator)
                    Capsule().fill(CanopyAccent.forest.color).frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Text(detail)
                .canopyText(.caption, color: Canopy.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A sheet with its own navigation and a Done button, for the history pages opened from Plan.
struct HistorySheet<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            CanopyFeel.play(.tap)
                            dismiss()
                        }
                    }
                }
        }
        .presentationBackground(Canopy.canvas)
        .presentationDetents([.large])
    }
}
