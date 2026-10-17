import SwiftUI

/// "YOUR PACE": the words-a-minute numeral counting up, a ruler that places the reader against most
/// adults, and what that pace means for a real book.
struct SpeedTestResultView: View {
    let controller: SpeedTestController

    var body: some View {
        if let result = controller.progress.result {
            SpeedTestResultContent(
                result: result,
                animates: !controller.progress.hasRevealedResult,
                onRevealStarted: { controller.markResultRevealed() }
            )
        } else {
            Color.clear
        }
    }
}

private struct SpeedTestResultContent: View {
    let result: SpeedTestResult
    let onRevealStarted: () -> Void

    /// The number on screen right now; it climbs to `target` when the result is new.
    @State private var shown: Int
    private let animates: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(result: SpeedTestResult, animates: Bool, onRevealStarted: @escaping () -> Void) {
        self.result = result
        self.animates = animates
        self.onRevealStarted = onRevealStarted
        _shown = State(initialValue: animates ? 0 : Int(result.effectiveWPM.rounded()))
    }

    private var target: Int { Int(result.effectiveWPM.rounded()) }

    private var caption: String {
        if result.total <= 0 || result.correct >= result.total {
            return "words a minute · \(result.correct) of \(result.total) understood"
        }
        return "\(result.correct) of \(result.total) understood, so we eased it to \(target) to keep your plan honest."
    }

    private var translation: (quote: String, detail: String) {
        let minutes = OnboardingCopy.referenceMinutes(wpm: result.effectiveWPM)
        return (
            "At this pace, \(OnboardingCopy.referenceTitle) takes \(OnboardingCopy.aboutDuration(minutes: minutes)).",
            "That’s \(OnboardingCopy.referenceTitle) in \(LeafFormat.duration(minutes: minutes)), cover to cover."
        )
    }

    var body: some View {
        OnboardingPage {
            VStack(spacing: Space.xl) {
                VStack(spacing: Space.xs) {
                    Eyebrow("Your pace")
                    // The final number sits invisibly underneath so the line never changes width.
                    ZStack {
                        Text(verbatim: "\(target)")
                            .opacity(0)
                            .accessibilityHidden(true)
                        Text(verbatim: "\(shown)")
                    }
                    .leafStyle(.heroNumeral)
                    Text(caption)
                        .leafStyle(.caption)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 320)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your pace: \(target) words a minute")
                .accessibilityValue(caption)

                SpeedTestPaceRuler(wpm: Double(shown))
                    .accessibilityHidden(true)

                VStack(spacing: Space.m) {
                    Text(OnboardingCopy.standing(wpm: result.effectiveWPM))
                        .leafStyle(.ui, color: .inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(translation.quote)
                        .leafStyle(.pullQuote)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(translation.detail)
                        .leafStyle(.caption)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 340)
            }
        }
        .task {
            await countUp()
        }
    }

    /// 0 to `target` over 1.2 s, ease-out. A `dialDetent` every 25 words a minute and `sessionEnd`
    /// on landing. Under Reduce Motion the number is already final and only the haptics play.
    private func countUp() async {
        guard animates else { return }
        onRevealStarted()
        let finalValue = target
        if reduceMotion { shown = finalValue }
        // Let the page finish fading in before the numeral starts to climb.
        try? await Task.sleep(for: .milliseconds(250))
        if Task.isCancelled { return }
        let start = Date()
        var detents = 0
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(start) / Motion.countUpDuration
            let value = Int((Double(finalValue) * Motion.countUpProgress(elapsed)).rounded())
            if !reduceMotion, value != shown { shown = value }
            let reached = value / 25
            if reached > detents {
                detents = reached
                Haptics.shared.play(.dialDetent)
            }
            if elapsed >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
        guard !Task.isCancelled else { return }
        shown = finalValue
        Haptics.shared.play(.sessionEnd)
    }
}

/// A 100–500 ruler. A `ribbon` tick marks the reader and a faint tick marks most adults (238).
private struct SpeedTestPaceRuler: View {
    let wpm: Double

    private let lower = 100.0
    private let upper = 500.0
    private let baseline: CGFloat = 60

    private func xPosition(of value: Double, in width: CGFloat) -> CGFloat {
        let clamped = min(upper, max(lower, value))
        return width * CGFloat((clamped - lower) / (upper - lower))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let adults = ReadingSpeed.typicalAdultWPM
            ZStack(alignment: .topLeading) {
                ForEach(Array(stride(from: 100, through: 500, by: 25)), id: \.self) { value in
                    let isMajor = value % 100 == 0
                    let length: CGFloat = isMajor ? 22 : 12
                    Rectangle()
                        .fill(Color.hairlineStrong)
                        .frame(width: 1, height: length)
                        .position(x: xPosition(of: Double(value), in: width), y: baseline - length / 2)
                }
                ForEach([100, 200, 300, 400, 500], id: \.self) { value in
                    Text(verbatim: "\(value)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.inkTertiary)
                        .position(x: xPosition(of: Double(value), in: width), y: baseline + 14)
                }
                Rectangle()
                    .fill(Color.inkFaint)
                    .frame(width: 1.5, height: 32)
                    .position(x: xPosition(of: adults, in: width), y: baseline - 16)
                Text("Most adults · \(Int(adults.rounded()))")
                    .font(.caption)
                    .foregroundStyle(Color.inkTertiary)
                    .fixedSize()
                    .position(x: xPosition(of: adults, in: width), y: baseline + 38)
                Capsule()
                    .fill(Color.ribbon)
                    .frame(width: 2, height: 44)
                    .position(x: xPosition(of: wpm, in: width), y: baseline - 22)
                Text("You")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .fixedSize()
                    .position(x: xPosition(of: wpm, in: width), y: 8)
            }
        }
        .frame(height: 110)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

#Preview("Ruler") {
    VStack(spacing: Space.xxl) {
        SpeedTestPaceRuler(wpm: 262)
        SpeedTestPaceRuler(wpm: 148)
    }
    .leafMargins()
    .frame(maxHeight: .infinity)
    .paperBackground()
}
