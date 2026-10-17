import SwiftUI

/// Pick the page you reached (DESIGN.md §5): a tick ruler from the start page to the page count,
/// spacing 10, major every 10, labels every 50, with a `ribbon` "est." tag above the predicted page.
/// Draws no readout; show the page in `heroNumeral` above it. VoiceOver adjusts by one page.
struct PageScrubber: View {
    @Binding var page: Int
    let range: ClosedRange<Int>
    var estimate: Int?

    /// - Parameters:
    ///   - range: the session's start page through the book's page count.
    ///   - estimate: the page Leaf predicts from the reader's pace, if any.
    init(page: Binding<Int>, range: ClosedRange<Int>, estimate: Int?) {
        self._page = page
        self.range = range
        self.estimate = estimate
    }

    private var labelled: Set<Int> {
        let first = Int((Double(range.lowerBound) / 50).rounded(.up)) * 50
        guard first <= range.upperBound else { return [] }
        return Set(stride(from: first, through: range.upperBound, by: 50))
    }

    var body: some View {
        TickRuler(
            range: range,
            value: $page,
            spacing: 10,
            majorEvery: 10,
            labels: labelled,
            estimate: estimate,
            rigidAtLabels: false,
            voiceOverLabel: "Page reached",
            adjustStep: 1,
            valueDescription: { [upper = range.upperBound] in "Page \($0) of \(upper)" }
        )
        .accessibilityHint(hint)
    }

    private var hint: String {
        guard let estimate else { return "" }
        return "Leaf estimates page \(estimate)"
    }
}

#Preview("Page scrubber") {
    @Previewable @State var page = 158
    VStack(spacing: Space.l) {
        Text("Where did you stop?").leafStyle(.title)
        Text("\(page)")
            .leafStyle(.heroNumeral)
            .contentTransition(.numericText(value: Double(page)))
            .leafAnimation(Motion.paper, value: page)
        PageScrubber(page: $page, range: 142...310, estimate: 158)
        Text("We guessed p. 158 from your pace.").leafStyle(.caption)
    }
    .frame(maxHeight: .infinity)
    .paperBackground()
}
