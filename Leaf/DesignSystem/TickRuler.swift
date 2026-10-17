import SwiftUI

/// A horizontal tick ruler under a fixed `ribbon` needle (DESIGN.md §5). Scroll it to pick a value.
/// The base of `MinutesDial` and `PageScrubber`; use those unless you need another scale.
///
/// Ticks are 1 pt `hairlineStrong`: 12 pt, 22 pt at each major, 34 pt when labelled with a 12 pt
/// `inkTertiary` label 6 pt below. The outer 25% fades out. 88 pt tall, full width.
/// Haptics: `selection()` per value, `dialDetent` per major, `rigid(0.8)` on labels when `rigidAtLabels`.
/// VoiceOver: an adjustable element stepping by `adjustStep`.
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

    @State private var scrolledID: Int?

    static let height: CGFloat = 88
    /// Ticks stand on this line.
    private static let baseline: CGFloat = 62
    private static let needleHeight: CGFloat = 48

    /// - Parameters:
    ///   - estimate: draws a `ribbon` "est." tag above that tick.
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
        let start = min(max(value.wrappedValue, range.lowerBound), range.upperBound)
        self._scrolledID = State(initialValue: start)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    ForEach(range, id: \.self) { tick in
                        tickMark(tick)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition(id: $scrolledID)
            .safeAreaPadding(.horizontal, proxy.size.width / 2)
            .mask { edgeFade }
            .overlay(alignment: .top) { needle }
        }
        .frame(height: Self.height)
        .onAppear {
            let start = clamp(value)
            if scrolledID != start { scrolledID = start }
        }
        .onChange(of: scrolledID) { _, newID in
            guard let newID, newID != value else { return }
            let old = value
            value = newID
            playHaptic(from: old, to: newID)
        }
        .onChange(of: value) { _, newValue in
            let target = clamp(newValue)
            if scrolledID != target {
                withAnimation(Motion.paper) { scrolledID = target }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
        .accessibilityValue(valueDescription(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = clamp(value + adjustStep)
            case .decrement: value = clamp(value - adjustStep)
            @unknown default: break
            }
        }
    }

    /// One zero-width cell: the tick is centred on the cell, so view-aligned snapping lands it on the needle.
    private func tickMark(_ tick: Int) -> some View {
        let isLabelled = labels.contains(tick)
        let isMajor = tick % majorEvery == 0
        let length: CGFloat = isLabelled ? 34 : (isMajor ? 22 : 12)
        return ZStack(alignment: .top) {
            if tick == estimate {
                Text("est.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.ribbon)
                    .fixedSize()
            }
            Rectangle()
                .fill(Color.hairlineStrong)
                .frame(width: 1, height: length)
                .offset(y: Self.baseline - length)
            if isLabelled {
                Text(String(tick))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.inkTertiary)
                    .fixedSize()
                    .offset(y: Self.baseline + 6)
            }
        }
        .frame(width: 0, height: Self.height, alignment: .top)
    }

    private var needle: some View {
        Capsule()
            .fill(Color.ribbon)
            .frame(width: 2, height: Self.needleHeight)
            .offset(y: Self.baseline - Self.needleHeight)
            .allowsHitTesting(false)
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.25),
                .init(color: .black, location: 0.75),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func clamp(_ candidate: Int) -> Int {
        min(max(candidate, range.lowerBound), range.upperBound)
    }

    /// The strongest mark crossed between `old` (exclusive) and `new` (inclusive) decides the feel.
    private func playHaptic(from old: Int, to new: Int) {
        guard old != new else { return }
        let step = new > old ? 1 : -1
        var crossedLabel = false
        var crossedMajor = false
        var tick = old
        var guardCount = 0
        while tick != new && guardCount < 400 {
            tick += step
            guardCount += 1
            if labels.contains(tick) { crossedLabel = true }
            if tick % majorEvery == 0 { crossedMajor = true }
        }
        if rigidAtLabels && crossedLabel {
            Haptics.shared.rigid(0.8)
        } else if crossedMajor {
            Haptics.shared.play(.dialDetent)
        } else {
            Haptics.shared.selection()
        }
    }
}

#Preview("Tick ruler") {
    @Previewable @State var value = 40
    VStack(spacing: Space.l) {
        Text("\(value)").leafStyle(.statNumeral)
        TickRuler(range: 0...100, value: $value, spacing: 8, majorEvery: 5, labels: [0, 25, 50, 75, 100], estimate: 60, voiceOverLabel: "Value")
    }
    .frame(maxHeight: .infinity)
    .paperBackground()
}
