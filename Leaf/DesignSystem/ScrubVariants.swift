import SwiftUI

// The scrub number's variants (NEXT.md section 9): tea steep time, a finish-by date with the minutes it would take,
// and a rolling drum for times. Minutes and pages keep their names (`MinutesDial`, `PageScrubber`) and now run on
// the same engine through `TickRuler`.

// MARK: - Steep time

/// How long the tea steeps, 30 s to 10 min in 15 s steps, with a magnet at the tea's own time.
struct SteepTimeScrub: View {
    @Binding var seconds: Int
    /// The tea's recommended steep, if any: a magnet.
    var suggested: Int?

    var body: some View {
        ScrubNumber(
            value: Binding(get: { Double(seconds) }, set: { seconds = Int($0.rounded()) }),
            configuration: Self.configuration(suggested: suggested),
            caption: "Steep",
            numeral: .display,
            labels: { value in
                let whole = Int(value.rounded())
                return whole % 60 == 0 ? "\(whole / 60) min" : nil
            },
            estimate: suggested.map(Double.init),
            accessibilityLabel: "Steep time",
            spoken: { SteepText.spoken(seconds: Int($0.rounded())) }
        )
    }

    static func configuration(suggested: Int?) -> ScrubConfiguration {
        var configuration = ScrubConfiguration(range: 30...600, step: 15)
        configuration.pointsPerStep = 12
        configuration.majorEvery = 4
        configuration.magnets = suggested.map { [ScrubMagnet(value: Double($0), radius: 0.5)] } ?? []
        configuration.format = ScrubValueFormat.custom { value in
            let total = Int(value.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        return configuration
    }
}

// MARK: - Finish by

/// "Finish by": scrub a date along a timeline and see the minutes a day it would take (`DateScrub`). Magnets sit on
/// the dates that matter, such as when the current pace finishes.
struct FinishByScrub: View {
    let scrub: DateScrub
    /// Days after today.
    @Binding var offset: Int
    var magnetOffsets: [Int] = []

    var body: some View {
        ScrubNumber(
            value: Binding(get: { Double(offset) }, set: { offset = Int($0.rounded()) }),
            configuration: scrub.scrubConfiguration(magnetOffsets: magnetOffsets, pointsPerDay: 6),
            caption: "Finish by",
            numeral: .masthead,
            labels: { value in
                let day = Int(value.rounded())
                guard day % 7 == 0 else { return nil }
                return LeafFormat.format(scrub.date(forOffset: day), template: "MMMd", calendar: scrub.calendar)
            },
            accessibilityLabel: "Finish by",
            spoken: { value in
                let result = scrub.result(forValue: value)
                let date = LeafFormat.format(result.date, template: "EEEEdMMMM", calendar: scrub.calendar)
                return result.minutesPerDay.map { "\(date), about \(Int($0.rounded(.up))) minutes a day" } ?? date
            },
            adjustSteps: 1,
            consequence: { value in
                guard let minutes = scrub.result(forValue: value).minutesPerDay else { return "Can’t tell from your pace yet" }
                return "About \(LeafFormat.duration(minutes: minutes.rounded(.up))) a day"
            }
        )
    }
}

// MARK: - Time drum

/// A rolling drum for a time of day: an hour wheel and a minute wheel (5-minute steps), each a vertical scrub with the
/// same detents, flick and haptics. 12- or 24-hour follows the reader's locale.
struct TimeDrum: View {
    @Binding var hour: Int
    @Binding var minute: Int
    var minuteStep = 5

    var body: some View {
        HStack(spacing: Space.s) {
            DrumWheel(
                value: $hour, range: 0...23, step: 1, label: "Hour",
                text: { TimeDrum.hourText($0) },
                spoken: { "\(TimeDrum.hourText($0)) hour" }
            )
            Text(":")
                .leafStyle(.statNumeral)
                .accessibilityHidden(true)
            DrumWheel(
                value: $minute, range: 0...(60 - minuteStep), step: minuteStep, label: "Minute",
                text: { String(format: "%02d", $0) },
                spoken: { "\($0) minutes" }
            )
        }
        .frame(maxWidth: 260)
    }

    /// "9 PM" or "21", by the locale's clock.
    static func hourText(_ hour: Int) -> String {
        let uses12 = (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
        guard uses12 else { return String(format: "%02d", hour) }
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve) \(hour < 12 ? "AM" : "PM")"
    }
}

/// One wheel of the drum: the values roll past a fixed band, the nearest ones fading and shrinking as they turn away.
struct DrumWheel: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let label: String
    let text: (Int) -> String
    let spoken: (Int) -> String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var controller: ScrubController

    static let rowHeight: CGFloat = 40
    static let visibleRows = 5

    init(value: Binding<Int>, range: ClosedRange<Int>, step: Int, label: String, text: @escaping (Int) -> String, spoken: @escaping (Int) -> String) {
        self._value = value
        self.range = range
        self.step = max(1, step)
        self.label = label
        self.text = text
        self.spoken = spoken
        var configuration = ScrubConfiguration(range: Double(range.lowerBound)...Double(range.upperBound), step: Double(max(1, step)))
        configuration.pointsPerStep = Double(Self.rowHeight)
        configuration.majorEvery = step == 1 ? 6 : 3
        configuration.overscrollSteps = 1
        _controller = State(initialValue: ScrubController(configuration: configuration, value: Double(value.wrappedValue)))
    }

    var body: some View {
        let display = controller.displayValue
        let blur = reduceTransparency ? 0 : controller.motionBlur * 0.4
        Canvas { context, size in
            let center = size.height / 2
            let stepValue = Double(step)
            let nearest = Int((display / stepValue).rounded()) * step
            for offset in -3...3 {
                let rowValue = nearest + offset * step
                guard rowValue >= range.lowerBound, rowValue <= range.upperBound else { continue }
                let distance = (Double(rowValue) - display) / stepValue
                let y = center + CGFloat(distance) * Self.rowHeight
                let fade = max(0, 1 - abs(distance) / 2.6)
                let scale = 1 - min(0.35, abs(distance) * 0.12)
                var row = context
                row.opacity = fade
                row.translateBy(x: size.width / 2, y: y)
                row.scaleBy(x: scale, y: scale)
                let resolved = Text(text(rowValue))
                    .font(.system(size: 26, weight: .regular, design: .serif).monospacedDigit())
                    .foregroundStyle(Color.ink)
                row.draw(resolved, at: .zero, anchor: .center)
            }
        }
        .frame(height: Self.rowHeight * CGFloat(Self.visibleRows))
        .blur(radius: CGFloat(blur))
        .overlay {
            VStack(spacing: Self.rowHeight) {
                Hairline(color: .hairlineStrong)
                Hairline(color: .hairlineStrong)
            }
            .allowsHitTesting(false)
        }
        .mask {
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { drag in controller.drag(translation: -Double(drag.translation.height)) }
                .onEnded { _ in controller.end() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: controller.nudge(steps: 1)
            case .decrement: controller.nudge(steps: -1)
            @unknown default: break
            }
        }
        .onAppear {
            let binding = $value
            controller.onChange = { newValue in binding.wrappedValue = Int(newValue.rounded()) }
        }
        .onChange(of: value) { _, newValue in controller.follow(Double(newValue)) }
    }
}

// MARK: - Previews

private struct ScrubVariantsPreview: View {
    @State private var steep = 240
    @State private var offset = 12
    @State private var hour = 21
    @State private var minute = 30

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xxl) {
                SteepTimeScrub(seconds: $steep, suggested: 240)
                FinishByScrub(
                    scrub: DateScrub(start: Date(), calendar: .current, earliestDay: 1, latestDay: 120) { _, days in
                        4_000.0 / Double(max(days, 1))
                    },
                    offset: $offset,
                    magnetOffsets: [9]
                )
                TimeDrum(hour: $hour, minute: $minute)
            }
            .padding(Space.xl)
        }
        .paperBackground()
    }
}

#Preview("Scrub variants") {
    ScrubVariantsPreview()
}

#Preview("Scrub variants · dark") {
    ScrubVariantsPreview()
        .preferredColorScheme(.dark)
}
