import SwiftUI

// The blur language (NEXT.md section 7): crisp for what you act on, soft for what you feel. Blur costs in proportion to
// radius and area, so these primitives blur small things for a moment (a numeral, a screen while it changes) and never
// keep a large live blur running. Every one honours Reduce Motion (crossfade instead) and Reduce Transparency (no blur,
// a dimmed tint instead).

// MARK: - Focus pull

/// A rack-focus between two views: the outgoing one blurs and drifts back as the incoming one sharpens into place.
/// 14 pt at the edge of the transition. Use `.focusPull` through `View.focusPullTransition()`, which falls back to a
/// crossfade under Reduce Motion or Reduce Transparency.
struct FocusPullTransition: Transition {
    var radius: CGFloat = 14

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .blur(radius: phase.isIdentity ? 0 : radius)
            .opacity(phase.isIdentity ? 1 : 0)
            .scaleEffect(phase.isIdentity ? 1 : (phase == .willAppear ? 1.03 : 0.97))
    }
}

extension Transition where Self == FocusPullTransition {
    /// Outgoing blurs as incoming sharpens.
    static var focusPull: FocusPullTransition { FocusPullTransition() }

    static func focusPull(radius: CGFloat) -> FocusPullTransition { FocusPullTransition(radius: radius) }
}

/// Keeps a view in or out of focus: out of focus it blurs (up to 6 pt by default, the language's ceiling for content
/// that stays on screen) and quietens, so whatever is in front reads first.
private struct FocusPullModifier: ViewModifier {
    let isFocused: Bool
    let radius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .blur(radius: isFocused || reduceTransparency ? 0 : radius)
            .opacity(isFocused ? 1 : (reduceTransparency ? 0.45 : 0.7))
            .animation(reduceMotion ? Motion.fade : .smooth(duration: 0.45), value: isFocused)
    }
}

/// The transition picked from the environment: a focus pull, or a crossfade when motion or transparency is reduced.
private struct FocusPullTransitionModifier: ViewModifier {
    let radius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.transition(
            reduceMotion || reduceTransparency ? AnyTransition.opacity : AnyTransition(FocusPullTransition(radius: radius))
        )
    }
}

extension View {
    /// Blurs and quietens the view while it is out of focus (a screen behind a sheet, the page behind a zoom).
    func focusPull(isFocused: Bool, radius: CGFloat = 6) -> some View {
        modifier(FocusPullModifier(isFocused: isFocused, radius: radius))
    }

    /// Inserts and removes the view with a focus pull (a crossfade under Reduce Motion or Reduce Transparency).
    func focusPullTransition(radius: CGFloat = 14) -> some View {
        modifier(FocusPullTransitionModifier(radius: radius))
    }
}

// MARK: - Numbers

/// `numericText` plus a short blur-through on every change: the old digits soften as the new ones roll in, then
/// everything is sharp again. With a live `velocity` blur (0...6 pt, from `ScrubFeedback.digitTransition`) the digits
/// smear while scrubbing fast and come back into focus as the finger slows.
private struct NumericBlurModifier: ViewModifier {
    let value: Double
    let velocityBlur: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var pulse: CGFloat = 0

    func body(content: Content) -> some View {
        let blur = reduceTransparency || reduceMotion ? 0 : min(6, max(pulse, velocityBlur))
        return content
            .contentTransition(.numericText(value: value))
            .blur(radius: blur)
            .animation(reduceMotion ? nil : Motion.paper, value: value)
            .onChange(of: value) { _, _ in
                guard !reduceMotion, !reduceTransparency else { return }
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { pulse = 2.5 }
                withAnimation(.easeOut(duration: 0.28)) { pulse = 0 }
            }
    }
}

extension View {
    /// The big numerals' transition: digits roll (`numericText`) with a short blur-through, and `velocityBlur` (in
    /// points, up to 6) smears them while a scrub is moving fast.
    func numericBlur(value: Double, velocityBlur: CGFloat = 0) -> some View {
        modifier(NumericBlurModifier(value: value, velocityBlur: velocityBlur))
    }
}

/// Blurs each glyph by its own amount: a wave of softness that runs across the digits as `progress` goes from 0 to 1
/// and back. The first digit leads, so a countdown appears to tick from left to right. Built on `TextRenderer`, so it
/// only costs anything while `progress` is above 0.
struct DigitBlurRenderer: TextRenderer, Animatable {
    /// 0 is crisp; 1 is the peak of the blur.
    var progress: Double
    var maxRadius: Double = 5

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard progress > 0.001 else {
            for line in layout { context.draw(line) }
            return
        }
        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    var copy = context
                    // Later glyphs trail the first a little, so the wave reads left to right.
                    let lag = min(0.6, Double(index) * 0.12)
                    let local = max(0, min(1, (progress - lag * 0.5) / (1 - lag * 0.5)))
                    let radius = maxRadius * sin(Double.pi * local)
                    if radius > 0.05 { copy.addFilter(.blur(radius: radius)) }
                    copy.opacity = 1 - 0.35 * sin(Double.pi * local)
                    copy.draw(glyph)
                    index += 1
                }
            }
        }
    }
}

/// A text whose glyphs blur through one by one whenever `value` changes (per-digit blur). Falls back to a plain
/// numeric transition under Reduce Motion or Reduce Transparency.
struct PerDigitBlurText: View {
    let text: String
    let value: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var progress = 0.0

    var body: some View {
        if reduceMotion || reduceTransparency {
            Text(text)
                .contentTransition(.numericText(value: value))
        } else {
            Text(text)
                .textRenderer(DigitBlurRenderer(progress: progress))
                .onChange(of: value) { _, _ in
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { progress = 0 }
                    withAnimation(.easeInOut(duration: 0.42)) { progress = 1 }
                }
        }
    }
}

// MARK: - Type-in

/// Types a line in, glyph by glyph: each glyph comes into focus (blur 8 → 0, opacity 0 → 1, settling 3 pt) a beat
/// after the one before, so the words resolve from soft to sharp as they arrive. `elapsed` is the time since the line
/// began; nil is at rest, drawn like plain text. Use it through `.typeIn(from:)`.
struct TypeInRenderer: TextRenderer {
    var elapsed: TimeInterval?
    /// Seconds between one glyph starting and the next.
    var stagger: TimeInterval = TypeInRenderer.defaultStagger
    var blur: CGFloat = 8
    var rise: CGFloat = 3

    static let defaultStagger: TimeInterval = 0.034
    /// How long one glyph takes to come into focus.
    static let settle: TimeInterval = 0.42

    /// How long a line of `characters` takes to type in.
    static func duration(characters: Int, stagger: TimeInterval = TypeInRenderer.defaultStagger) -> TimeInterval {
        Double(max(0, characters - 1)) * stagger + settle
    }

    var displayPadding: EdgeInsets {
        EdgeInsets(top: blur, leading: blur, bottom: blur + rise, trailing: blur)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard let elapsed else {
            for line in layout { context.draw(line) }
            return
        }
        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    let local = (elapsed - Double(index) * stagger) / Self.settle
                    index += 1
                    if local >= 1 {
                        context.draw(glyph)
                        continue
                    }
                    guard local > 0 else { continue }
                    let eased = 1 - pow(1 - local, 3)
                    var copy = context
                    copy.opacity = eased
                    let radius = blur * CGFloat(1 - eased)
                    if radius > 0.05 { copy.addFilter(.blur(radius: radius)) }
                    copy.translateBy(x: 0, y: rise * CGFloat(1 - eased))
                    copy.draw(glyph)
                }
            }
        }
    }
}

/// Plays `TypeInRenderer` from `startedAt` (after `delay`) and comes to rest sharp. Only the moment it is typing costs
/// anything. Reduce Motion skips the typing (the text simply crossfades with the change); Reduce Transparency types
/// without the blur.
private struct TypeInModifier: ViewModifier {
    let startedAt: Date?
    let delay: TimeInterval
    let characters: Int
    let stagger: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// The run that has come to rest, so the timeline can stop.
    @State private var restedRun: Date?

    private var end: TimeInterval { delay + TypeInRenderer.duration(characters: characters, stagger: stagger) }

    func body(content: Content) -> some View {
        let typing = startedAt.map { !reduceMotion && restedRun != $0 && Date().timeIntervalSince($0) < end } ?? false
        return TimelineView(.animation(paused: !typing)) { timeline in
            content.textRenderer(TypeInRenderer(
                elapsed: typing ? startedAt.map { timeline.date.timeIntervalSince($0) - delay } : nil,
                stagger: stagger,
                blur: reduceTransparency ? 0 : 8
            ))
        }
        .task(id: startedAt) {
            guard let startedAt, typing else { return }
            try? await Task.sleep(for: .seconds(max(0, end - Date().timeIntervalSince(startedAt))))
            guard !Task.isCancelled else { return }
            restedRun = startedAt
        }
    }
}

extension View {
    /// Types the text in glyph by glyph from `startedAt` (plus `delay`), each glyph resolving from soft to sharp
    /// (`TypeInRenderer`). A start that is long past, or nil, shows the text at rest. `characters` is the text's length,
    /// for knowing when it is done.
    func typeIn(from startedAt: Date?, after delay: TimeInterval = 0, characters: Int, stagger: TimeInterval = TypeInRenderer.defaultStagger) -> some View {
        modifier(TypeInModifier(startedAt: startedAt, delay: delay, characters: characters, stagger: stagger))
    }
}

// MARK: - Previews

private struct BlurPreview: View {
    @State private var showsFirst = true
    @State private var number = 142
    @State private var focused = true
    @State private var typedAt: Date?

    var body: some View {
        VStack(spacing: Space.xl) {
            ZStack {
                if showsFirst {
                    Text("Good evening.").leafStyle(.display).focusPullTransition()
                } else {
                    Text("Still up?").leafStyle(.display).focusPullTransition()
                }
            }
            .frame(height: 80)
            Text("\(number)")
                .leafStyle(.heroNumeral)
                .numericBlur(value: Double(number))
            PerDigitBlurText(text: "\(number)", value: Double(number))
                .leafStyle(.statNumeral)
            Text("Out of focus behind a sheet")
                .leafStyle(.title)
                .focusPull(isFocused: focused)
            Text("Kettle on, page open.")
                .leafStyle(.display)
                .typeIn(from: typedAt, characters: 21)
            Button("Change") {
                withAnimation(.smooth(duration: 0.5)) { showsFirst.toggle() }
                number += 7
                focused.toggle()
                typedAt = Date()
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
    }
}

#Preview("Blur") {
    BlurPreview()
}

#Preview("Blur · dark") {
    BlurPreview()
        .preferredColorScheme(.dark)
}
