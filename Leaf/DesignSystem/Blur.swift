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

// MARK: - Previews

private struct BlurPreview: View {
    @State private var showsFirst = true
    @State private var number = 142
    @State private var focused = true

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
            Button("Change") {
                withAnimation(.smooth(duration: 0.5)) { showsFirst.toggle() }
                number += 7
                focused.toggle()
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
