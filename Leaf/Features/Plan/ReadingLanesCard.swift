import SwiftUI

/// Every book on Reading on one shared timeline (docs/design/REDESIGN.md §4.2): a lane per book with its likely
/// finish as a dot and the range around it as a soft bar, today at the left edge. One glance says which book lands
/// first and when they're all done; tapping a lane opens "Finish by…" for that book.
struct ReadingLanesCard: View {
    let books: [LibraryItem]
    let result: ForecastResult
    /// How a what-if moves each book, if one is being tried.
    var delta: (String) -> ForecastBookDelta? = { _ in nil }
    let narrator: ForecastNarrator
    let onFinishLine: (String?) -> Void

    private struct Lane: Identifiable {
        let item: LibraryItem
        let forecast: BookForecast
        var id: String { item.id }
        var mid: Int? { forecast.medianOffset }
        var low: Int? { forecast.p10Offset }
        var high: Int? { forecast.p90Offset }
    }

    private var lanes: [Lane] {
        books.compactMap { item in result.book(item.id).map { Lane(item: item, forecast: $0) } }
            .sorted { ($0.mid ?? .max) < ($1.mid ?? .max) }
    }

    /// Days across the timeline: the latest likely-late finish, with a little room after it.
    private var span: Int {
        let latest = lanes.compactMap { $0.high ?? $0.mid }.max() ?? 14
        return max(14, Int((Double(latest) * 1.08).rounded(.up)))
    }

    var body: some View {
        let lanes = lanes
        VStack(alignment: .leading, spacing: Canopy.Space.l) {
            CanopyLabel("Now reading", linkTitle: "Finish by…") { onFinishLine(nil) }
            Text(summary(lanes))
                .canopyText(.quote)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Canopy.Space.l) {
                ForEach(lanes) { lane in
                    row(lane)
                }
            }
            axis
            Text(caption(lanes))
                .canopyText(.caption, color: Canopy.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .canopyCard()
    }

    // MARK: Rows

    private func row(_ lane: Lane) -> some View {
        Button {
            CanopyFeel.play(.tap)
            onFinishLine(lane.id)
        } label: {
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                HStack(spacing: Canopy.Space.m) {
                    BookCover(book: lane.item.book, size: .xs)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lane.item.book.title)
                            .canopyText(.headline)
                            .lineLimit(1)
                        Text("p. \(LeafFormat.number(lane.item.currentPage)) of \(LeafFormat.number(lane.item.book.pages)) · \(lane.item.percent)%")
                            .canopyText(.caption)
                            .monospacedDigit()
                    }
                    Spacer(minLength: Canopy.Space.s)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(lane.forecast.median.map { Self.capitalizedFirst(narrator.day($0)) } ?? "Not in sight")
                            .canopyText(.statSmall, color: CanopyAccent.forest.color)
                        if let earlier = delta(lane.id)?.medianDaysEarlier, earlier != 0 {
                            DeltaChip(daysSooner: earlier)
                        }
                    }
                }
                track(lane)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lane.item.book.title). \(narrator.bookSentence(lane.forecast))")
        .accessibilityHint("Opens Finish by")
    }

    /// The lane: a hairline track from today, the likely range as a soft bar, the likely finish as a dot.
    private func track(_ lane: Lane) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (offset: Int) in CGFloat(min(offset, span)) / CGFloat(span) * width }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Canopy.separator)
                    .frame(height: 2)
                if let mid = lane.mid {
                    let low = lane.low ?? mid
                    let high = lane.high ?? mid
                    Capsule()
                        .fill(CanopyAccent.forest.soft)
                        .frame(width: max(10, x(high) - x(low)), height: 10)
                        .offset(x: x(low))
                    Circle()
                        .fill(CanopyAccent.forest.color)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Canopy.surface, lineWidth: 2))
                        .offset(x: min(width - 12, max(0, x(mid) - 6)))
                }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
    }

    /// Today, the middle, and the end of the timeline.
    private var axis: some View {
        let origin = lanes.first?.forecast.origin ?? narrator.now
        let calendar = narrator.calendar
        let middle = calendar.date(byAdding: .day, value: span / 2, to: origin) ?? origin
        let end = calendar.date(byAdding: .day, value: span, to: origin) ?? origin
        return HStack {
            Text("Today")
            Spacer()
            Text(LeafFormat.format(middle, template: "MMMd", calendar: calendar))
            Spacer()
            Text(LeafFormat.format(end, template: "MMMd", calendar: calendar))
        }
        .font(.system(.caption2, weight: .medium))
        .foregroundStyle(Canopy.textTertiary)
        .accessibilityHidden(true)
    }

    // MARK: Words

    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "Circe first, around Nov 12. All three done by about Jan 14."
    private func summary(_ lanes: [Lane]) -> String {
        let dated = lanes.filter { $0.forecast.median != nil }
        guard let first = dated.first, let firstDate = first.forecast.median else {
            return "Read a few sittings and Leaf will place your finishes."
        }
        if dated.count == 1 {
            return narrator.bookSentence(first.forecast)
        }
        let last = dated.last?.forecast.median ?? firstDate
        let all = dated.count == 2 ? "Both" : "All \(narrator.number(dated.count))"
        return "\(first.item.book.title) first, around \(narrator.day(firstDate)). \(all) done by about \(narrator.day(last))."
    }

    private func caption(_ lanes: [Lane]) -> String {
        if lanes.contains(where: { $0.forecast.positionUncertain }) {
            return "The dot is the likely finish, the bar the range. A rough guess until you confirm your page."
        }
        if lanes.contains(where: { $0.forecast.sessions < 3 }) {
            return "The dot is the likely finish, the bar the range. Ranges narrow as you read each book."
        }
        return "The dot is the likely finish, the bar the range."
    }
}
