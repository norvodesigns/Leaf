import SwiftUI

// One scrub control for every number in the app (NEXT.md section 9), built on `ScrubModel`: detents and magnets with
// their haptics (`Haptics.scrub`), rubber banding past the ends, momentum after a flick, and digits that blur with
// speed. The model decides; these views only feed it gestures and time and draw what it says. Nothing runs while it's
// still: coasting is a short task that ends when the model comes to rest.

// MARK: - Controller

/// Drives one `ScrubModel` from gestures and the clock, plays its haptics, and publishes what to draw.
@MainActor
@Observable
final class ScrubController {
    private(set) var model: ScrubModel
    /// Motion blur for the ruler, 0...6 pt.
    private(set) var motionBlur: Double = 0
    /// How far the digits are mid-transition, 0...1.
    private(set) var digitBlur: Double = 0

    /// Called when the value changes because of the reader (not when the owner sets it).
    @ObservationIgnored var onChange: ((Double) -> Void)?
    @ObservationIgnored private var coasting: Task<Void, Never>?
    @ObservationIgnored private var isDragging = false
    @ObservationIgnored private var reported: Double

    init(configuration: ScrubConfiguration, value: Double) {
        let model = ScrubModel(configuration: configuration, value: value)
        self.model = model
        self.reported = model.value
    }

    var value: Double { model.value }
    var displayValue: Double { model.displayValue }
    var configuration: ScrubConfiguration { model.configuration }
    var isActive: Bool { model.isActive }

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    /// The finger's total travel along the control's axis, in points; positive raises the value.
    func drag(translation: Double) {
        if !isDragging {
            coasting?.cancel()
            isDragging = true
            model.begin(at: Self.now())
        }
        apply(model.drag(translation: translation, at: Self.now()))
    }

    /// The finger lifted: the value coasts, settles on a step and springs back from the ends.
    func end() {
        guard isDragging else { return }
        isDragging = false
        apply(model.end(at: Self.now()))
        coast()
    }

    /// A step or more at once (VoiceOver's adjustable action, a stepper).
    func nudge(steps: Int) {
        coasting?.cancel()
        apply(model.nudge(steps: steps, at: Self.now()))
    }

    /// The owner changed the value: follow it quietly, unless the reader is mid-scrub.
    func follow(_ newValue: Double) {
        guard !model.isActive, abs(newValue - model.value) > 1e-9 else { return }
        model.jump(to: newValue)
        reported = model.value
    }

    /// A typed value: jump to it and report it.
    func type(_ newValue: Double) {
        coasting?.cancel()
        model.jump(to: newValue)
        report()
    }

    private func coast() {
        coasting?.cancel()
        guard model.phase == .coasting else {
            settleBlur()
            return
        }
        coasting = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled else { return }
                self.apply(self.model.advance(to: Self.now()))
                if self.model.phase == .idle {
                    self.settleBlur()
                    return
                }
            }
        }
    }

    private func settleBlur() {
        withAnimation(.easeOut(duration: 0.2)) {
            motionBlur = 0
            digitBlur = 0
        }
    }

    private func apply(_ feedback: ScrubFeedback) {
        motionBlur = feedback.motionBlurRadius
        digitBlur = feedback.digitTransition
        for event in feedback.events {
            Haptics.shared.scrub(event)
        }
        report()
    }

    private func report() {
        guard model.value != reported else { return }
        reported = model.value
        onChange?(model.value)
    }
}

// MARK: - Ruler

/// The tick ruler under a fixed `ribbon` needle, drawn in one `Canvas` around the model's display value (so a 1,000-page
/// book costs the same as a 100-page one). 1 pt `hairlineStrong` ticks: 12 pt, 22 pt at majors, 34 pt with a label;
/// magnets wear a small `ribbon` dot (with "est." when `estimate` names one). The edges fade; the whole ruler takes the
/// model's motion blur while it moves fast.
struct ScrubRuler: View {
    let controller: ScrubController
    var labels: (Double) -> String? = { _ in nil }
    var estimate: Double?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static let height: CGFloat = 88
    private static let baseline: CGFloat = 62
    private static let needleHeight: CGFloat = 48

    var body: some View {
        let configuration = controller.configuration
        let display = controller.displayValue
        Canvas { context, size in
            drawTicks(in: &context, size: size, configuration: configuration, display: display)
        }
        .frame(height: Self.height)
        .blur(radius: reduceTransparency ? 0 : CGFloat(min(6, controller.motionBlur)) * 0.5)
        .mask { edgeFade }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.ribbon)
                .frame(width: 2, height: Self.needleHeight)
                .offset(y: Self.baseline - Self.needleHeight)
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }

    private func drawTicks(in context: inout GraphicsContext, size: CGSize, configuration: ScrubConfiguration, display: Double) {
        let step = max(configuration.step, 1e-9)
        let spacing = CGFloat(max(configuration.pointsPerStep, 1))
        let lower = configuration.range.lowerBound
        let upper = configuration.range.upperBound
        let center = size.width / 2
        let halfCount = Int((size.width / spacing / 2).rounded(.up)) + 2
        let centerIndex = Int(((display - lower) / step).rounded(.down))
        let majorStride = max(1, configuration.detentEvery) * max(0, configuration.majorEvery)
        let tickColor = Color.hairlineStrong
        let labelColor = Color.inkTertiary

        for index in (centerIndex - halfCount)...(centerIndex + halfCount) {
            let value = lower + Double(index) * step
            guard value >= lower - 1e-9, value <= upper + 1e-9 else { continue }
            let x = center + CGFloat((value - display) / step) * spacing
            let label = labels(value)
            let isMajor = majorStride > 0 && index % majorStride == 0
            let length: CGFloat = label != nil ? 34 : (isMajor ? 22 : 12)
            context.fill(Path(CGRect(x: x - 0.5, y: Self.baseline - length, width: 1, height: length)), with: .color(tickColor))
            if let label {
                let text = Text(label).font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(labelColor)
                context.draw(text, at: CGPoint(x: x, y: Self.baseline + 12), anchor: .center)
            }
        }

        for magnet in configuration.magnets where magnet.value >= lower && magnet.value <= upper {
            let x = center + CGFloat((magnet.value - display) / step) * spacing
            guard x > -20, x < size.width + 20 else { continue }
            context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: Self.baseline + 2, width: 5, height: 5)), with: .color(Color.ribbon))
            if let estimate, abs(estimate - magnet.value) < step / 2 {
                let tag = Text("est.").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ribbon)
                context.draw(tag, at: CGPoint(x: x, y: 2), anchor: .top)
            }
        }
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
}

// MARK: - Gestures

/// A horizontal scrub that shares the screen with vertical scrolling: it locks to whichever axis the finger moves along
/// first, and only a sideways drag reaches the model.
private struct HorizontalScrubGesture: ViewModifier {
    let controller: ScrubController

    @State private var axis: Axis?

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        if axis == nil {
                            axis = abs(value.translation.width) >= abs(value.translation.height) ? .horizontal : .vertical
                        }
                        guard axis == .horizontal else { return }
                        controller.drag(translation: -Double(value.translation.width))
                    }
                    .onEnded { _ in
                        if axis == .horizontal { controller.end() }
                        axis = nil
                    }
            )
    }
}

extension View {
    /// Feeds sideways drags on this view to `controller` (dragging left raises the value, as the ruler slides under
    /// the needle).
    func scrubsHorizontally(_ controller: ScrubController) -> some View {
        modifier(HorizontalScrubGesture(controller: controller))
    }
}

// MARK: - The general control

/// A scrub number (NEXT.md section 9): the value set large, a ruler under it, and the scrub on both. Tap the numeral to
/// type a value instead; VoiceOver adjusts by `adjustSteps`. The digits roll with `numericText` and blur with speed.
struct ScrubNumber: View {
    @Binding var value: Double
    let configuration: ScrubConfiguration
    var caption: String?
    var numeral: LeafTextStyle = .heroNumeral
    var labels: (Double) -> String? = { _ in nil }
    var estimate: Double?
    var accessibilityLabel: String
    var spoken: (Double) -> String
    var adjustSteps: Int = 1
    /// Shown under the caption while scrubbing: the live consequence ("about 37 pages a day").
    var consequence: ((Double) -> String?)?

    @State private var controller: ScrubController
    @State private var isTyping = false
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    init(
        value: Binding<Double>,
        configuration: ScrubConfiguration,
        caption: String? = nil,
        numeral: LeafTextStyle = .heroNumeral,
        labels: @escaping (Double) -> String? = { _ in nil },
        estimate: Double? = nil,
        accessibilityLabel: String,
        spoken: @escaping (Double) -> String,
        adjustSteps: Int = 1,
        consequence: ((Double) -> String?)? = nil
    ) {
        self._value = value
        self.configuration = configuration
        self.caption = caption
        self.numeral = numeral
        self.labels = labels
        self.estimate = estimate
        self.accessibilityLabel = accessibilityLabel
        self.spoken = spoken
        self.adjustSteps = max(1, adjustSteps)
        self.consequence = consequence
        _controller = State(initialValue: ScrubController(configuration: configuration, value: value.wrappedValue))
    }

    var body: some View {
        VStack(spacing: Space.m) {
            VStack(spacing: -6) {
                if isTyping {
                    TextField(configuration.format(controller.value), text: $typed)
                        .keyboardType(.decimalPad)
                        .font(LeafType.statNumeral)
                        .multilineTextAlignment(.center)
                        .focused($fieldFocused)
                        .onSubmit(commitTyped)
                        .frame(maxWidth: 200)
                        .padding(.vertical, Space.s)
                        .background(Color.paperSunken, in: Radius.shape(Radius.tile))
                } else {
                    Text(configuration.format(controller.value))
                        .leafStyle(numeral)
                        .numericBlur(value: controller.value, velocityBlur: CGFloat(controller.digitBlur * 6))
                        .onTapGesture {
                            Haptics.shared.tap()
                            typed = ""
                            isTyping = true
                            fieldFocused = true
                        }
                }
                if let caption {
                    Eyebrow(caption)
                        .padding(.top, Space.s)
                }
            }
            if let line = consequence?(controller.value) {
                Text(line)
                    .leafStyle(.caption)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .blur(radius: CGFloat(controller.motionBlur) * 0.3)
            }
            ScrubRuler(controller: controller, labels: labels, estimate: estimate)
                .scrubsHorizontally(controller)
        }
        .toolbar {
            if isTyping {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done", action: commitTyped)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(spoken(controller.value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: controller.nudge(steps: adjustSteps)
            case .decrement: controller.nudge(steps: -adjustSteps)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Type a value") {
            isTyping = true
            fieldFocused = true
        }
        .onAppear {
            let binding = $value
            controller.onChange = { binding.wrappedValue = $0 }
        }
        .onChange(of: value) { _, newValue in
            controller.follow(newValue)
        }
    }

    private func commitTyped() {
        let cleaned = typed.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        if let number = Double(cleaned) {
            controller.type(number)
        }
        isTyping = false
        fieldFocused = false
    }
}

private extension ScrubConfiguration {
    static var previewMinutes: ScrubConfiguration {
        var configuration = ScrubConfiguration(range: 5...180, step: 1)
        configuration.majorEvery = 5
        configuration.magnets = [ScrubMagnet(value: 30, radius: 0.6)]
        return configuration
    }
}

#Preview("Scrub number") {
    @Previewable @State var value = 25.0
    ScrubNumber(
        value: $value,
        configuration: .previewMinutes,
        caption: "Minutes a day",
        labels: { [15, 30, 45, 60, 90, 120, 180].contains(Int($0)) ? String(Int($0)) : nil },
        accessibilityLabel: "Minutes a day",
        spoken: { "\(Int($0)) minutes" },
        adjustSteps: 5
    )
    .frame(maxHeight: .infinity)
    .paperBackground()
}

#Preview("Scrub number · dark") {
    @Previewable @State var value = 25.0
    ScrubNumber(value: $value, configuration: .previewMinutes, caption: "Minutes a day", accessibilityLabel: "Minutes a day", spoken: { "\(Int($0)) minutes" })
        .frame(maxHeight: .infinity)
        .paperBackground()
        .preferredColorScheme(.dark)
}
