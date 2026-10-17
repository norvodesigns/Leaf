import SwiftUI

/// The shared time axis behind the Plan's rows: maps dates to a 0…1 position.
struct TimelineScale: Equatable {
    let start: Date
    let end: Date

    /// Day-aligned; always at least a week long.
    init(start: Date, end: Date, calendar: Calendar = .current) {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        let minimum = calendar.date(byAdding: .day, value: 7, to: first) ?? first.addingTimeInterval(7 * 86_400)
        self.start = first
        self.end = max(last, minimum)
    }

    /// From today to a week past the last planned finish.
    init(covering books: [PlannedBook], today: Date, calendar: Calendar = .current) {
        let last = books.compactMap(\.finish).max() ?? today
        let padded = calendar.date(byAdding: .day, value: 7, to: last) ?? last
        self.init(start: today, end: padded, calendar: calendar)
    }

    /// 0 at `start`, 1 at `end`, clamped.
    func fraction(of date: Date) -> CGFloat {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return CGFloat(min(1, max(0, date.timeIntervalSince(start) / total)))
    }

    /// The first day of each month after `start`, up to `end`.
    func monthStarts(calendar: Calendar = .current) -> [Date] {
        guard var month = calendar.dateInterval(of: .month, for: start)?.start else { return [] }
        var result: [Date] = []
        for _ in 0..<240 {
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
            if month > end { break }
            result.append(month)
        }
        return result
    }
}

/// A PlanRow's band (DESIGN.md §5): a 6 pt capsule from start to the end of the finish day on the
/// shared axis. `accent` for Reading books, `hairlineStrong` for To read. With no finish date it
/// runs to the edge and fades out. Animate date changes with `Motion.paper`.
struct TimelineBand: View {
    let start: Date
    let finish: Date?
    let scale: TimelineScale
    var isReading: Bool

    init(start: Date, finish: Date?, scale: TimelineScale, isReading: Bool) {
        self.start = start
        self.finish = finish
        self.scale = scale
        self.isReading = isReading
    }

    /// For a planned book.
    init(_ planned: PlannedBook, scale: TimelineScale) {
        self.init(start: planned.start, finish: planned.finish, scale: scale, isReading: planned.isReading)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let color = isReading ? Color.accent : Color.hairlineStrong
            let x0 = scale.fraction(of: start) * width
            let endOfFinish = finish.map { Calendar.current.date(byAdding: .day, value: 1, to: $0) ?? $0 }
            let x1 = endOfFinish.map { scale.fraction(of: $0) * width } ?? width
            let bandWidth = max(x1 - x0, 6)
            Capsule()
                .fill(finish == nil
                    ? AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0)], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(color))
                .frame(width: bandWidth, height: 6)
                .offset(x: min(x0, max(width - bandWidth, 0)))
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// The Plan list overlay: 1 px `hairline` gridlines at 50% on month starts and a 1 pt `ribbon`
/// rule at today. Put it behind the rows' band column with matching horizontal insets.
struct TimelineGrid: View {
    let scale: TimelineScale
    var today: Date

    @Environment(\.displayScale) private var displayScale

    init(scale: TimelineScale, today: Date = Date()) {
        self.scale = scale
        self.today = today
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let pixel = 1 / max(displayScale, 1)
            ZStack(alignment: .topLeading) {
                ForEach(scale.monthStarts(), id: \.self) { month in
                    Rectangle()
                        .fill(Color.hairline.opacity(0.5))
                        .frame(width: pixel)
                        .offset(x: scale.fraction(of: month) * width)
                }
                Rectangle()
                    .fill(Color.ribbon)
                    .frame(width: 1)
                    .offset(x: scale.fraction(of: today) * width)
            }
            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Month eyebrows ("NOV", "DEC") along the top of the Plan list, skipping any that would collide.
struct TimelineMonthLabels: View {
    let scale: TimelineScale

    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = 16

    init(scale: TimelineScale) {
        self.scale = scale
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ForEach(visibleMonths(width: width), id: \.self) { month in
                    Text(LeafFormat.format(month, template: "MMM"))
                        .leafStyle(.eyebrow)
                        .fixedSize()
                        .offset(x: scale.fraction(of: month) * width + Space.xs)
                }
            }
            .frame(width: width, alignment: .topLeading)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func visibleMonths(width: CGFloat) -> [Date] {
        var kept: [Date] = []
        var lastX = -CGFloat.infinity
        for month in scale.monthStarts() {
            let x = scale.fraction(of: month) * width
            guard x - lastX >= 36, x <= width - 24 else { continue }
            kept.append(month)
            lastX = x
        }
        return kept
    }
}

#Preview("Timeline") {
    let today = Date()
    let calendar = Calendar.current
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
    let scale = TimelineScale(start: today, end: day(120))
    return VStack(alignment: .leading, spacing: Space.l) {
        TimelineMonthLabels(scale: scale)
        VStack(spacing: Space.xl) {
            TimelineBand(start: day(0), finish: day(10), scale: scale, isReading: true)
            TimelineBand(start: day(11), finish: day(40), scale: scale, isReading: false)
            TimelineBand(start: day(41), finish: day(75), scale: scale, isReading: false)
            TimelineBand(start: day(76), finish: nil, scale: scale, isReading: false)
        }
        .background { TimelineGrid(scale: scale, today: today) }
    }
    .leafMargins()
    .frame(maxHeight: .infinity)
    .paperBackground()
}
