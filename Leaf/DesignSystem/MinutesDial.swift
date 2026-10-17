import SwiftUI

/// Minutes a day, 5–180 (DESIGN.md §5): a `heroNumeral` readout that rolls with `numericText`,
/// the eyebrow "MINUTES A DAY", and a tick ruler (spacing 8, major every 5, labels at
/// 15, 30, 45, 60, 90, 120, 180). VoiceOver adjusts by 5 minutes.
struct MinutesDial: View {
    @Binding var minutes: Int

    static let range = 5...180
    static let labelled: Set<Int> = [15, 30, 45, 60, 90, 120, 180]

    init(minutes: Binding<Int>) {
        self._minutes = minutes
    }

    var body: some View {
        VStack(spacing: Space.l) {
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .leafStyle(.heroNumeral)
                    .contentTransition(.numericText(value: Double(minutes)))
                    .leafAnimation(Motion.paper, value: minutes)
                Text("Minutes a day")
                    .leafStyle(.eyebrow)
            }
            .accessibilityHidden(true)
            TickRuler(
                range: Self.range,
                value: $minutes,
                spacing: 8,
                majorEvery: 5,
                labels: Self.labelled,
                rigidAtLabels: true,
                voiceOverLabel: "Minutes a day",
                adjustStep: 5,
                valueDescription: { "\($0) minutes" }
            )
        }
        .onAppear {
            let clamped = min(max(minutes, Self.range.lowerBound), Self.range.upperBound)
            if clamped != minutes { minutes = clamped }
        }
    }
}

#Preview("Minutes dial") {
    @Previewable @State var minutes = 25
    VStack {
        MinutesDial(minutes: $minutes)
        Text("About 37 pages a day — a novel every three weeks.")
            .leafStyle(.pullQuote)
            .multilineTextAlignment(.center)
            .leafMargins()
    }
    .frame(maxHeight: .infinity)
    .paperBackground()
}
