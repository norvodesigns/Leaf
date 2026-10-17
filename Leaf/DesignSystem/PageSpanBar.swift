import SwiftUI

/// Where you are in a book and what today covers (DESIGN.md §5). A 4 pt `hairline` track; pages read
/// fill `ink`; today's span fills `accentSoft` with a 1 pt `accent` stroke; a 2×12 `ribbon` caret
/// marks the current page. Turns `accent` when the book is finished. 12 pt tall, full width.
struct PageSpanBar: View {
    /// The last page read.
    var current: Int
    /// The page today's assignment reaches (pass `current` when there's nothing scheduled).
    var todayTo: Int
    /// The book's page count.
    var total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(current: Int, todayTo: Int, total: Int) {
        self.current = current
        self.todayTo = todayTo
        self.total = total
    }

    private var isFinished: Bool { total > 0 && current >= total }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let pages = Double(max(total, 1))
            let readX: CGFloat = width * CGFloat(fraction(Double(current) / pages))
            let toX: CGFloat = width * CGFloat(fraction(Double(max(todayTo, current)) / pages))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.hairline)
                    .frame(height: 4)
                Capsule()
                    .fill(isFinished ? Color.accent : Color.ink)
                    .frame(width: readX, height: 4)
                if !isFinished && toX - readX > 0.5 {
                    Capsule()
                        .fill(Color.accentSoft)
                        .overlay {
                            Capsule().strokeBorder(Color.accent, lineWidth: 1)
                        }
                        .frame(width: max(toX - readX, 6), height: 6)
                        .offset(x: min(readX, max(width - 6, 0)))
                }
                if !isFinished {
                    Capsule()
                        .fill(Color.ribbon)
                        .frame(width: 2, height: 12)
                        .offset(x: min(max(readX - 1, 0), max(width - 2, 0)))
                }
            }
            .frame(width: width, height: 12)
        }
        .frame(height: 12)
        .animation(reduceMotion ? nil : Motion.paper, value: current)
        .animation(reduceMotion ? nil : Motion.paper, value: todayTo)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pages")
        .accessibilityValue(accessibilityText)
    }

    private func fraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private var accessibilityText: String {
        if isFinished { return "Finished, \(total) pages" }
        if todayTo > current { return "Page \(current) of \(total). Today, to page \(todayTo)" }
        return "Page \(current) of \(total)"
    }
}

#Preview("Page span") {
    VStack(spacing: Space.xl) {
        PageSpanBar(current: 142, todayTo: 158, total: 310)
        PageSpanBar(current: 0, todayTo: 24, total: 404)
        PageSpanBar(current: 290, todayTo: 310, total: 310)
        PageSpanBar(current: 310, todayTo: 310, total: 310)
    }
    .padding(Space.margin)
    .paperBackground()
}
