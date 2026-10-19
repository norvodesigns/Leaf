import Charts
import SwiftUI

// The forecast's charts (NEXT.md section 10). Each is drawn from the engine's numbers and read to VoiceOver as the
// narrator's sentence, never as a list of plotted values.

// MARK: - Book fan chart

/// Where a book's pages are heading: the median finish as a line from today's page to the last, and the 10th to 90th
/// percentile finishes as a shaded fan around it. Tap or drag across the dates to see the chance of being done by
/// then (`BookForecast.probability(by:)`).
struct BookFanChart: View {
    let title: String
    let forecast: BookForecast
    let currentPage: Int
    let pages: Int
    let narrator: ForecastNarrator
    let calendar: Calendar
    let today: Date

    /// The date under the finger; Charts clears it when the finger lifts.
    @State private var touch: Date?
    /// The last date checked, which stays (with its odds) after the finger lifts.
    @State private var selected: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Sample: Identifiable {
        let date: Date
        let slow: Double
        let fast: Double
        let median: Double
        var id: Date { date }
    }

    private var start: Date { calendar.startOfDay(for: today) }
    private var median: Date? { forecast.median }
    private var fastest: Date { forecast.p10 ?? median ?? start }
    private var slowest: Date { forecast.p90 ?? median ?? start }

    /// The last date on the axis: a little past the slow end of the fan.
    private var end: Date {
        let span = max(7, days(from: start, to: slowest))
        return calendar.date(byAdding: .day, value: span + max(2, span / 8), to: start) ?? slowest
    }

    private var floorPage: Double {
        let left = Double(max(0, pages - currentPage))
        return max(0, Double(currentPage) - left * 0.2)
    }

    private func days(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    /// The page reached on `date` if the book finishes on `finish`, read evenly from today.
    private func page(on date: Date, finishing finish: Date) -> Double {
        let total = Double(max(1, days(from: start, to: finish)))
        let fraction = min(1, max(0, Double(days(from: start, to: date)) / total))
        return Double(currentPage) + Double(max(0, pages - currentPage)) * fraction
    }

    private var samples: [Sample] {
        let span = max(1, days(from: start, to: end))
        let stride = max(1, span / 60)
        return Swift.stride(from: 0, through: span, by: stride).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return Sample(
                date: date,
                slow: page(on: date, finishing: slowest),
                fast: page(on: date, finishing: fastest),
                median: page(on: date, finishing: median ?? slowest)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            chart
                .frame(height: 150)
            Text(oddsLine)
                .leafStyle(.caption, color: selected == nil ? Color.inkTertiary : Color.ink)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : Motion.paper, value: selected)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) forecast")
        .accessibilityValue(spokenValue)
        .accessibilityHint("Swipe up or down to check a later or earlier date.")
        .accessibilityAdjustableAction { direction in
            let base = selected ?? median ?? start
            let step = direction == .increment ? 2 : -2
            guard let next = calendar.date(byAdding: .day, value: step, to: base) else { return }
            selected = min(max(next, start), end)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(
                    x: .value("Date", sample.date),
                    yStart: .value("Slow", sample.slow),
                    yEnd: .value("Fast", sample.fast)
                )
                .foregroundStyle(Color.accent.opacity(0.16))
                .interpolationMethod(.linear)
            }
            if median != nil {
                ForEach(samples) { sample in
                    LineMark(x: .value("Date", sample.date), y: .value("Page", sample.median), series: .value("Line", "median"))
                        .foregroundStyle(Color.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            RuleMark(y: .value("Last page", pages))
                .foregroundStyle(Color.hairlineStrong)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("p. \(pages)").font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Color.inkTertiary)
                }
            PointMark(x: .value("Date", start), y: .value("Page", currentPage))
                .foregroundStyle(Color.ribbon)
                .symbolSize(28)
            if let selected {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(Color.ink.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: floorPage...Double(max(pages, currentPage + 1)))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .chartXSelection(value: $touch)
        .onChange(of: touch) { _, date in
            if let date { selected = min(max(date, start), end) }
        }
    }

    private var oddsLine: String {
        guard let selected else { return "Tap a date to see the odds." }
        return narrator.chanceSentence(forecast, by: selected)
    }

    private var spokenValue: String {
        let base = narrator.bookSentence(forecast)
        guard let selected else { return base }
        return "\(base) \(narrator.chanceSentence(forecast, by: selected))"
    }
}

// MARK: - Year chart

/// The year in books: the books finished so far as a rising step, then a fan from today to the 31st of December
/// between the low and high ends of the forecast, the median as a dashed line, and the goal as a faint line climbing
/// at a steady pace from January to its number, so the gap between the two reads at a glance.
struct YearForecastChart: View {
    let year: YearForecast
    /// When each book finished this year, oldest first.
    let finishes: [Date]
    let today: Date
    let calendar: Calendar

    private var yearStart: Date {
        calendar.date(from: DateComponents(year: year.year, month: 1, day: 1)) ?? today
    }

    private var yearEnd: Date {
        calendar.date(from: DateComponents(year: year.year, month: 12, day: 31)) ?? today
    }

    private struct Step: Identifiable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    /// The steps of books finished: one point before and after each finish so the line climbs in steps.
    private var steps: [Step] {
        var points = [Step(date: yearStart, count: 0)]
        var count = 0
        for date in finishes where date >= yearStart && date <= today {
            points.append(Step(date: date, count: count))
            count += 1
            points.append(Step(date: date.addingTimeInterval(1), count: count))
        }
        points.append(Step(date: today, count: max(count, year.finishedSoFar)))
        return points
    }

    private var ceiling: Int { max(year.goal ?? 0, year.high, year.finishedSoFar) + 1 }

    var body: some View {
        Chart {
            ForEach(steps) { step in
                LineMark(x: .value("Date", step.date), y: .value("Books", step.count), series: .value("Line", "so far"))
                    .foregroundStyle(Color.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            if today < yearEnd {
                AreaMark(x: .value("Date", today), yStart: .value("Low", year.finishedSoFar), yEnd: .value("High", year.finishedSoFar))
                    .foregroundStyle(Color.accent.opacity(0.16))
                AreaMark(x: .value("Date", yearEnd), yStart: .value("Low", year.low), yEnd: .value("High", year.high))
                    .foregroundStyle(Color.accent.opacity(0.16))
                LineMark(x: .value("Date", today), y: .value("Books", year.finishedSoFar), series: .value("Line", "median"))
                    .foregroundStyle(Color.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                LineMark(x: .value("Date", yearEnd), y: .value("Books", year.median), series: .value("Line", "median"))
                    .foregroundStyle(Color.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                PointMark(x: .value("Date", yearEnd), y: .value("Books", year.median))
                    .foregroundStyle(Color.accent)
                    .symbolSize(30)
                    .annotation(position: .leading, spacing: 4) {
                        Text("\(year.median)")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.accent)
                    }
            }
            if let goal = year.goal, goal > 0 {
                LineMark(x: .value("Date", yearStart), y: .value("Books", 0), series: .value("Line", "goal"))
                    .foregroundStyle(Color.inkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                LineMark(x: .value("Date", yearEnd), y: .value("Books", goal), series: .value("Line", "goal"))
                    .foregroundStyle(Color.inkTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                PointMark(x: .value("Date", yearEnd), y: .value("Books", goal))
                    .foregroundStyle(Color.inkTertiary)
                    .symbolSize(14)
                    .annotation(position: .leading, spacing: 4) {
                        Text("Goal \(goal)").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.inkTertiary)
                    }
            }
            PointMark(x: .value("Date", today), y: .value("Books", year.finishedSoFar))
                .foregroundStyle(Color.ribbon)
                .symbolSize(28)
        }
        .chartXScale(domain: yearStart...yearEnd)
        .chartYScale(domain: 0...ceiling)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel().font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Color.inkTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .frame(height: 170)
        .accessibilityHidden(true)
    }
}

// MARK: - Speed trend

/// Words a minute over the last months: the smoothed trend as a line over the individual sittings as faint dots.
struct SpeedTrendChart: View {
    let trend: SpeedTrend

    var body: some View {
        Chart {
            ForEach(trend.points) { point in
                PointMark(x: .value("Date", point.date), y: .value("Sitting", point.sessionWPM))
                    .foregroundStyle(Color.inkFaint)
                    .symbolSize(10)
            }
            ForEach(trend.points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Words a minute", point.wpm), series: .value("Line", "trend"))
                    .foregroundStyle(Color.accent)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel().font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Color.inkTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.inkTertiary)
            }
        }
        .frame(height: 120)
        .accessibilityHidden(true)
    }
}
