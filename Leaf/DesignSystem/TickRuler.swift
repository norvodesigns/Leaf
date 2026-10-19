import SwiftUI

/// A horizontal tick ruler under a fixed `ribbon` needle (DESIGN.md §5), now on the shared scrub engine
/// (`ScrubModel` via `ScrubController`): drag it sideways to pick a value, flick it to coast, push past an end to feel
/// the rubber band. The base of `MinutesDial` and `PageScrubber`; use those (or `ScrubNumber`) unless you need another
/// scale.
///
/// Ticks are 1 pt `hairlineStrong`: 12 pt, 22 pt at each major, 34 pt when labelled with a 12 pt `inkTertiary` label
/// 6 pt below. The outer 25% fades out. 88 pt tall, full width. Drawn in one `Canvas`, so a long range costs nothing.
/// Haptics come from the model: a tick per value, a heavier one at majors, a snap at magnets (`estimate`, and the
/// labels when `rigidAtLabels`), a knock at the ends. VoiceOver: an adjustable element stepping by `adjustStep`.
struct TickRuler: View {
    let range: ClosedRange<Int>
    @Binding var value: Int
    var spacing: CGFloat
    var majorEvery: Int
    var labels: Set<Int>
    var estimate: Int?
    var rigidAtLabels: Bool
    var voiceOverLabel: String
    var adjustStep: Int
    var valueDescription: (Int) -> String

    @State private var controller: ScrubController

    static let height: CGFloat = ScrubRuler.height

    /// - Parameters:
    ///   - estimate: a magnet with a `ribbon` "est." tag above that tick.
    ///   - rigidAtLabels: the labelled values become gentle magnets.
    ///   - valueDescription: the VoiceOver value, e.g. `{ "\($0) minutes" }`.
    init(
        range: ClosedRange<Int>,
        value: Binding<Int>,
        spacing: CGFloat = 8,
        majorEvery: Int = 5,
        labels: Set<Int> = [],
        estimate: Int? = nil,
        rigidAtLabels: Bool = false,
        voiceOverLabel: String = "Value",
        adjustStep: Int = 1,
        valueDescription: @escaping (Int) -> String = { "\($0)" }
    ) {
        self.range = range
        self._value = value
        self.spacing = spacing
        self.majorEvery = max(1, majorEvery)
        self.labels = labels
        self.estimate = estimate
        self.rigidAtLabels = rigidAtLabels
        self.voiceOverLabel = voiceOverLabel
        self.adjustStep = max(1, adjustStep)
        self.valueDescription = valueDescription
        let configuration = Self.configuration(range: range, spacing: spacing, majorEvery: majorEvery, labels: labels, estimate: estimate, rigidAtLabels: rigidAtLabels)
        _controller = State(initialValue: ScrubController(configuration: configuration, value: Double(value.wrappedValue)))
    }

    static func configuration(range: ClosedRange<Int>, spacing: CGFloat, majorEvery: Int, labels: Set<Int>, estimate: Int?, rigidAtLabels: Bool) -> ScrubConfiguration {
        let lower = Double(range.lowerBound)
        let upper = Double(max(range.lowerBound, range.upperBound))
        var configuration = ScrubConfiguration(range: lower...upper, step: 1)
        configuration.pointsPerStep = Double(max(2, spacing))
        configuration.majorEvery = max(1, majorEvery)
        var magnets: [ScrubMagnet] = []
        if let estimate { magnets.append(ScrubMagnet(value: Double(estimate), radius: 0.45)) }
        if rigidAtLabels { magnets += labels.sorted().map { ScrubMagnet(value: Double($0), radius: 0.35) } }
        configuration.magnets = magnets
        return configuration
    }

    var body: some View {
        ScrubRuler(
            controller: controller,
            labels: { [labels] tick in
                let whole = Int(tick.rounded())
                return labels.contains(whole) ? String(whole) : nil
            },
            estimate: estimate.map(Double.init)
        )
        .scrubsHorizontally(controller)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityValue(valueDescription(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: controller.nudge(steps: adjustStep)
            case .decrement: controller.nudge(steps: -adjustStep)
            @unknown default: break
            }
        }
        .onAppear(perform: connect)
        .onChange(of: value) { _, newValue in
            controller.follow(Double(newValue))
        }
        .onChange(of: range) { _, newRange in
            let configuration = Self.configuration(range: newRange, spacing: spacing, majorEvery: majorEvery, labels: labels, estimate: estimate, rigidAtLabels: rigidAtLabels)
            controller = ScrubController(configuration: configuration, value: Double(value))
            connect()
        }
    }

    private func connect() {
        let binding = $value
        controller.onChange = { newValue in
            let whole = Int(newValue.rounded())
            if binding.wrappedValue != whole { binding.wrappedValue = whole }
        }
    }
}

#Preview("Tick ruler") {
    @Previewable @State var value = 40
    VStack(spacing: Space.l) {
        Text("\(value)").leafStyle(.statNumeral).numericBlur(value: Double(value))
        TickRuler(range: 0...100, value: $value, spacing: 8, majorEvery: 5, labels: [0, 25, 50, 75, 100], estimate: 60, voiceOverLabel: "Value")
    }
    .frame(maxHeight: .infinity)
    .paperBackground()
}

#Preview("Tick ruler · dark") {
    @Previewable @State var value = 142
    VStack(spacing: Space.l) {
        Text("\(value)").leafStyle(.heroNumeral).numericBlur(value: Double(value))
        PageScrubber(page: $value, range: 0...310, estimate: 158)
    }
    .frame(maxHeight: .infinity)
    .paperBackground()
    .preferredColorScheme(.dark)
}
