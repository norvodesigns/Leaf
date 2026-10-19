import SwiftUI

/// The Insights page of the Plan tab (NEXT.md section 10): the year as tea rings on the table, when the reader reads
/// best, how their speed has moved, what they read, how deep the To read pile is, a reading personality to share, and
/// the doors to the Year in Books and the weekly letter. Cute units always sit beside the real numbers, and each card
/// reads to VoiceOver as its sentence.
struct InsightsPage: View {
    let desk: PlanDesk

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let insights = desk.insights {
            VStack(alignment: .leading, spacing: Space.m) {
                heatmapCard(insights)
                    .inkIn(0)
                YearInBooksCard(summary: insights.yearInBooks) {
                    router.planSheet = .yearInBooks
                }
                .inkIn(1)
                WeeklyLetterCard(letter: insights.letter, calendar: store.calendar) {
                    router.planSheet = .weeklyLetter
                }
                .inkIn(2)
                BestTimeCard(best: insights.bestTime)
                    .id("time")
                SpeedCard(trend: insights.speed)
                MixCard(genres: insights.genres, lengths: insights.lengths, year: insights.year)
                    .id("mix")
                TBRCard(depth: insights.tbr)
                PersonalityCard(personality: insights.personality)
                    .id("personality")
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    private func heatmapCard(_ insights: InsightsSnapshot) -> some View {
        let read = insights.heatmap.filter(\.didRead)
        let minutes = read.reduce(0) { $0 + $1.minutes }
        return TodayCard("\(String(insights.year)) in tea rings") {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("\(read.count)")
                    .leafStyle(.statNumeral)
                Text(read.isEmpty ? "days read so far" : "days read · \(LeafFormat.duration(minutes: minutes))")
                    .leafStyle(.caption)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(read.isEmpty ? "No reading logged this year yet." : "You read on \(read.count) \(read.count == 1 ? "day" : "days") this year, \(LeafFormat.duration(minutes: minutes)) in all.")
            TeaRingHeatmap(cells: insights.heatmap, calendar: store.calendar)
            Text("Each ring is a day; the bigger the ring, the longer the read. A gold drop marks a finished book.")
                .leafStyle(.caption, color: .inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Heatmap

/// A year of days as tea rings on paper, a column per week. Read days leave a ring sized by `HeatCell.ring`, rest days
/// a short dash, missed reading days a faint dot, future days nothing at all. Drawn in one `Canvas`; scrolls sideways,
/// starting at today.
struct TeaRingHeatmap: View {
    let cells: [HeatCell]
    let calendar: Calendar

    private let cell: CGFloat = 16

    /// The week with today in it; later weeks aren't drawn, so the map ends where the reader is.
    private var lastColumn: Int {
        cells.first(where: \.isToday)?.column ?? (cells.filter { !$0.isFuture }.map(\.column).max() ?? 0)
    }

    private var columns: Int { lastColumn + 1 }

    /// Where each month starts, for the labels above.
    private var monthStarts: [(column: Int, name: String)] {
        cells.filter { calendar.component(.day, from: $0.date) == 1 && $0.column <= lastColumn }
            .sorted { $0.date < $1.date }
            .map { ($0.column, LeafFormat.format($0.date, template: "MMM", calendar: calendar)) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: Space.xs) {
                ZStack(alignment: .topLeading) {
                    ForEach(monthStarts, id: \.column) { start in
                        Text(start.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.inkTertiary)
                            .offset(x: CGFloat(start.column) * cell)
                    }
                }
                .frame(width: CGFloat(columns) * cell, height: 12, alignment: .topLeading)
                Canvas { context, _ in
                    for day in cells where day.column <= lastColumn {
                        draw(day, in: &context)
                    }
                }
                .frame(width: CGFloat(columns) * cell, height: 7 * cell)
            }
            .padding(.vertical, Space.xs)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The year as tea rings")
        .accessibilityValue(monthSummary)
    }

    private func draw(_ day: HeatCell, in context: inout GraphicsContext) {
        let center = CGPoint(x: (CGFloat(day.column) + 0.5) * cell, y: (CGFloat(day.row) + 0.5) * cell)
        if day.isFuture { return }
        if day.didRead {
            // A ring with a little wobble, like a cup set down without looking.
            let wobble = CGFloat((Int(day.date.timeIntervalSince1970 / 86_400) * 37) % 7 - 3) * 0.12
            let radius = (cell / 2 - 1.5) * CGFloat(max(0.3, min(1, day.ring)))
            let rect = CGRect(x: center.x - radius + wobble, y: center.y - radius - wobble, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Color.chai.opacity(0.14 + 0.18 * min(1, day.ring))))
            context.stroke(Path(ellipseIn: rect), with: .color(Color.chai.opacity(0.75)), lineWidth: day.ring >= 1 ? 1.4 : 1)
            if !day.finishedBookIDs.isEmpty {
                let drop = CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: drop), with: .color(Color.amber))
            }
        } else if day.isRestDay {
            var dash = Path()
            dash.move(to: CGPoint(x: center.x - 2.5, y: center.y))
            dash.addLine(to: CGPoint(x: center.x + 2.5, y: center.y))
            context.stroke(dash, with: .color(Color.hairlineStrong), lineWidth: 1)
        } else {
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.2, y: center.y - 1.2, width: 2.4, height: 2.4)), with: .color(Color.inkFaint))
        }
        if day.isToday {
            let ring = CGRect(x: center.x - cell / 2 + 0.5, y: center.y - cell / 2 + 0.5, width: cell - 1, height: cell - 1)
            context.stroke(Path(ellipseIn: ring), with: .color(Color.ribbon), lineWidth: 1)
        }
    }

    /// "October: 18 days, 9 h 20 min. September: …", most recent first.
    private var monthSummary: String {
        var byMonth: [Int: (days: Int, minutes: Double)] = [:]
        for day in cells where day.didRead {
            let month = calendar.component(.month, from: day.date)
            byMonth[month, default: (0, 0)].days += 1
            byMonth[month, default: (0, 0)].minutes += day.minutes
        }
        return byMonth.keys.sorted(by: >).compactMap { month in
            guard let entry = byMonth[month], let date = calendar.date(from: DateComponents(year: 2000, month: month, day: 1)) else { return nil }
            let name = LeafFormat.format(date, template: "MMMM", calendar: calendar)
            return "\(name): \(entry.days) \(entry.days == 1 ? "day" : "days"), \(LeafFormat.duration(minutes: entry.minutes))."
        }
        .joined(separator: " ")
    }
}

// MARK: - Cards

/// When the reader reads best: the engine's reason, and a bar per part of the day by share of minutes.
struct BestTimeCard: View {
    let best: BestTimeOfDay?

    var body: some View {
        TodayCard("Best time to read") {
            if let best {
                Text(best.reason)
                    .leafStyle(.pullQuote)
                    .fixedSize(horizontal: false, vertical: true)
                let parts = best.dayparts.filter { $0.minuteShare >= 0.01 }
                let top = parts.map(\.minuteShare).max() ?? 1
                VStack(spacing: Space.xs) {
                    ForEach(parts, id: \.daypart) { part in
                        HStack(spacing: Space.s) {
                            Text(name(part.daypart))
                                .leafStyle(.caption)
                                .frame(width: 84, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(part.daypart == best.consistent.daypart ? Color.accent : Color.hairlineStrong)
                                    .frame(width: max(3, proxy.size.width * part.minuteShare / max(top, 0.01)))
                            }
                            .frame(height: 6)
                            Text("\(Int((part.minuteShare * 100).rounded()))%")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.inkTertiary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(name(part.daypart)): \(Int((part.minuteShare * 100).rounded())) percent of your reading time")
                    }
                }
            } else {
                Text("After ten sittings over five days, Leaf can tell when you read best.")
                    .leafStyle(.body, color: .inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func name(_ daypart: Daypart) -> String {
        switch daypart {
        case .smallHours: "Small hours"
        case .dawn: "Dawn"
        case .morning: "Morning"
        case .lunch: "Lunch"
        case .afternoon: "Afternoon"
        case .teaTime: "Tea time"
        case .dusk: "Dusk"
        case .evening: "Evening"
        case .late: "Late"
        }
    }
}

/// Words a minute over time, with the engine's sentence.
struct SpeedCard: View {
    let trend: SpeedTrend

    var body: some View {
        TodayCard("Reading speed") {
            if let wpm = trend.currentWPM {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(Int(wpm.rounded()))")
                        .leafStyle(.statNumeral)
                    Text("words a minute lately")
                        .leafStyle(.caption)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("About \(Int(wpm.rounded())) words a minute lately.")
            }
            if trend.label != .notEnoughData, !trend.points.isEmpty {
                SpeedTrendChart(trend: trend)
            }
            Text(trend.sentence)
                .leafStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What the year's finished books were: genres as a stacked bar with a legend, and short, medium and long reads.
struct MixCard: View {
    let genres: [InsightsEngine.GenreShare]
    let lengths: [InsightsEngine.LengthShare]
    let year: Int

    private let palette: [Color] = [.accent, .chai, .rooibos, .matcha, .amber, .rose, .steam]

    var body: some View {
        TodayCard("\(String(year)) mix") {
            if genres.isEmpty {
                Text("Finish a book this year and its genre shows up here.")
                    .leafStyle(.body, color: .inkSecondary)
            } else {
                let top = Array(genres.prefix(6))
                Text(genreSentence(top))
                    .leafStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(Array(top.enumerated()), id: \.element.id) { index, genre in
                            Rectangle()
                                .fill(palette[index % palette.count])
                                .frame(width: max(4, (proxy.size.width - CGFloat(top.count - 1) * 2) * genre.share))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                FlowLegend(items: top.enumerated().map { index, genre in
                    (palette[index % palette.count], "\(Self.display(genre.name)) \(genre.books)")
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(top.map { "\(Self.display($0.name)), \($0.books) \($0.books == 1 ? "book" : "books")" }.joined(separator: "; "))
            }
            if lengths.contains(where: { $0.books > 0 }) {
                Hairline()
                HStack(spacing: Space.m) {
                    ForEach(lengths) { length in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(length.books)")
                                .leafStyle(.statNumeral)
                            Text(length.label)
                                .leafStyle(.caption)
                            Text(length.detail)
                                .leafStyle(.caption, color: .inkTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(length.books) \(length.label), \(length.detail)")
                    }
                }
            }
        }
    }

    /// "science fiction" → "Science fiction".
    static func display(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    private func genreSentence(_ top: [InsightsEngine.GenreShare]) -> String {
        guard let first = top.first else { return "" }
        let percent = Int((first.share * 100).rounded())
        if top.count == 1 { return "All \(first.name.lowercased()) so far." }
        return "Mostly \(first.name.lowercased()): \(first.books) \(first.books == 1 ? "book" : "books"), \(percent) percent of the year."
    }
}

/// A row of colour keys that wraps, from the leading edge.
private struct FlowLegend: View {
    let items: [(Color, String)]

    var body: some View {
        LeadingFlow(spacing: Space.m, lineSpacing: Space.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Circle().fill(item.0).frame(width: 8, height: 8)
                    Text(item.1).leafStyle(.caption)
                }
            }
        }
    }
}

/// Lays its children out in rows from the leading edge, wrapping when a row is full.
private struct LeadingFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// How deep the To read pile is at the reader's pace.
struct TBRCard: View {
    let depth: TBRDepth

    var body: some View {
        TodayCard("To read pile") {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("\(depth.queueBooks)")
                    .leafStyle(.statNumeral)
                Text(depth.queueBooks == 1 ? "book waiting · \(LeafFormat.duration(minutes: depth.queueMinutes))" : "books waiting · \(LeafFormat.duration(minutes: depth.queueMinutes))")
                    .leafStyle(.caption)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(depth.queueBooks) \(depth.queueBooks == 1 ? "book" : "books") waiting, \(LeafFormat.duration(minutes: depth.queueMinutes)) of reading.")
            Text(depth.sentence)
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
            Text(depth.basis == .recent ? "At the pace of the last four weeks." : "At the pace you planned.")
                .leafStyle(.caption, color: .inkTertiary)
        }
    }
}

/// The year's wrapped, as a door: four numbers and the month rings.
struct YearInBooksCard: View {
    let summary: YearInBooks
    let open: () -> Void

    var body: some View {
        TodayCard("\(String(summary.year)) in books", actionTitle: summary.isEmpty ? nil : "Open", action: summary.isEmpty ? nil : open) {
            if summary.isEmpty {
                Text("Your year in books fills in as you read: the books, the pages, the cups, and the months as rings.")
                    .leafStyle(.body, color: .inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                filled
            }
        }
    }

    private var filled: some View {
        Group {
            HStack(alignment: .center, spacing: Space.l) {
                MonthRingCollage(months: summary.months, ringSize: 22)
                    .frame(width: 112)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("\(summary.booksFinished) \(summary.booksFinished == 1 ? "book" : "books")")
                        .leafStyle(.title)
                    Text("\(LeafFormat.number(summary.pages)) pages · \(LeafFormat.duration(minutes: summary.minutes))")
                        .leafStyle(.caption)
                    Text("\(summary.cups) \(summary.cups == 1 ? "cup" : "cups") of reading")
                        .leafStyle(.caption)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(YearInBooksText.summary(summary))
            }
            .contentShape(.rect)
            .onTapGesture(perform: open)
        }
    }
}

/// The Sunday letter, as a door.
struct WeeklyLetterCard: View {
    let letter: WeeklyLetterData
    let calendar: Calendar
    let open: () -> Void

    var body: some View {
        let copy = WeeklyLetterView.copy(for: letter, calendar: calendar)
        TodayCard("This week’s letter", actionTitle: "Read", action: open) {
            Text(copy.title)
                .leafStyle(.title)
            Text(copy.sentences.first ?? "")
                .leafStyle(.pullQuote)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(.rect)
        .onTapGesture(perform: open)
    }
}

/// The reader's archetype, with the evidence for it and a way to share it as an image.
struct PersonalityCard: View {
    let personality: ReadingPersonality

    @State private var poster: UIImage?

    var body: some View {
        TodayCard("Reading personality") {
            Text(personality.title)
                .leafStyle(.masthead)
                .fixedSize(horizontal: false, vertical: true)
            Text(personality.blurb)
                .leafStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
            if !personality.evidence.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(personality.evidence.prefix(3), id: \.key) { evidence in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Circle().fill(Color.chai).frame(width: 5, height: 5)
                            Text(evidence.text)
                                .leafStyle(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let poster {
                ShareLink(
                    item: Image(uiImage: poster),
                    preview: SharePreview(personality.title, image: Image(uiImage: poster))
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(LeafType.ui)
                        .foregroundStyle(Color.accent)
                        .frame(minHeight: Space.hitTarget)
                }
            }
        }
        .task(id: personality.archetype) {
            poster = SharePoster.render(PersonalityPoster(personality: personality))
        }
    }
}

/// The image a personality shares as: a card of paper with the title, the blurb and a tea ring.
struct PersonalityPoster: View {
    let personality: ReadingPersonality

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Eyebrow("My reading personality")
            Text(personality.title)
                .leafStyle(.display)
                .fixedSize(horizontal: false, vertical: true)
            Text(personality.blurb)
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                TeaRingStamp(mark: .read(1), seed: personality.title.count, diameter: 64)
                Spacer()
                Text("Leaf")
                    .leafStyle(.wordmark)
            }
        }
        .padding(Space.xxl)
        .frame(width: SharePoster.size.width, height: SharePoster.size.height, alignment: .topLeading)
        .background(Color.paper)
    }
}

/// Renders a poster view to an image for sharing, on paper, always in the day palette.
enum SharePoster {
    static let size = CGSize(width: 360, height: 480)

    @MainActor
    static func render<Content: View>(_ content: Content, size: CGSize = SharePoster.size) -> UIImage? {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = 3
        return renderer.uiImage
    }
}
