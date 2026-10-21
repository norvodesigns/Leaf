import SwiftUI

// Materials (DESIGN_SYSTEM.md §6) and the Focus In moment (§8).

// MARK: - Backdrop

/// The screen base: `canvas` plus two large, soft, static glows (the screen's accent top-leading, a second
/// one bottom-trailing)
/// so the glass above has light to bend. Plain gradients, no live blur, so it costs nothing.
struct CanopyBackdrop: View {
    var accent: CanopyAccent = .forest

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let dark = colorScheme == .dark
        let scale = reduceTransparency ? 0.5 : 1
        let primary = (dark ? 0.20 : 0.10) * scale
        let secondary = (dark ? 0.10 : 0.06) * scale
        // The second glow: lamplight (Clay) on Forest screens, Forest elsewhere.
        let warmth: CanopyAccent = accent == .forest ? .clay : .forest
        GeometryReader { proxy in
            let size = proxy.size
            let reach = max(size.width, size.height)
            ZStack {
                Canopy.canvas
                RadialGradient(
                    colors: [accent.glow.opacity(primary), accent.glow.opacity(0)],
                    center: UnitPoint(x: 0.1, y: 0.05),
                    startRadius: 0,
                    endRadius: reach * 0.75
                )
                RadialGradient(
                    colors: [warmth.glow.opacity(secondary), warmth.glow.opacity(0)],
                    center: UnitPoint(x: 0.95, y: 0.85),
                    startRadius: 0,
                    endRadius: reach * 0.7
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Puts the Canopy backdrop behind the view, glowing in the screen's accent.
    func canopyBackdrop(_ accent: CanopyAccent = .forest) -> some View {
        background { CanopyBackdrop(accent: accent) }
    }
}

// MARK: - Glass

/// Card glass: every content card. Becomes `surface` with a hairline under Reduce Transparency.
private struct CanopyCardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var tint: CanopyAccent?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let padded = content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        if reduceTransparency {
            padded
                .background(Canopy.surface, in: shape)
                .overlay { shape.strokeBorder(Canopy.separator) }
        } else {
            padded
                .glassEffect(.regular.tint(tint?.soft), in: shape)
        }
    }
}

/// Accent or control glass: smaller interactive things (slot rows, chips, timer housings).
private struct CanopyGlassModifier<S: Shape>: ViewModifier {
    var accent: CanopyAccent?
    var interactive: Bool
    var shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(accent?.soft ?? Canopy.surface, in: shape)
                .overlay { shape.stroke(Canopy.separator, lineWidth: 1) }
        } else {
            content
                .glassEffect(.regular.tint(accent?.soft).interactive(interactive), in: shape)
        }
    }
}

extension View {
    /// A glass card: 20 pt padding, 28 pt continuous corners, full width. `tint` washes it with an accent's soft colour.
    func canopyCard(padding: CGFloat = Canopy.Space.cardPadding, radius: CGFloat = Canopy.Radius.card, tint: CanopyAccent? = nil) -> some View {
        modifier(CanopyCardModifier(padding: padding, radius: radius, tint: tint))
    }

    /// Glass for a control or a small surface, optionally tinted with an accent's job, in a capsule.
    func canopyGlass(_ accent: CanopyAccent? = nil, interactive: Bool = true) -> some View {
        modifier(CanopyGlassModifier(accent: accent, interactive: interactive, shape: Capsule()))
    }

    /// Glass for a control or a small surface in any shape.
    func canopyGlass<S: Shape>(_ accent: CanopyAccent? = nil, interactive: Bool = true, in shape: S) -> some View {
        modifier(CanopyGlassModifier(accent: accent, interactive: interactive, shape: shape))
    }
}

// MARK: - Focus In

/// The signature moment: something arrives soft and resolves to crystal clear. A transition, never a state: at rest
/// the view is always sharp.
struct CanopyFocusInTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .blur(radius: phase.isIdentity ? 0 : Canopy.Motion.focusInBlur)
            .opacity(phase.isIdentity ? 1 : 0)
            .scaleEffect(phase.isIdentity ? 1 : 1.04)
    }
}

extension Transition where Self == CanopyFocusInTransition {
    /// Arrives blurred, resolves to sharp.
    static var canopyFocusIn: CanopyFocusInTransition { CanopyFocusInTransition() }
}

/// Plays Focus In once each time `value` changes, then rests sharp.
private struct CanopyFocusInOnChange<V: Equatable>: ViewModifier {
    let value: V

    @State private var blur: CGFloat = 0
    @State private var opacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .onChange(of: value) { _, _ in
                guard !reduceMotion, !reduceTransparency else { return }
                var start = Transaction()
                start.disablesAnimations = true
                withTransaction(start) {
                    blur = Canopy.Motion.focusInBlur
                    opacity = 0.3
                }
                withAnimation(Canopy.Motion.focusIn) {
                    blur = 0
                    opacity = 1
                }
            }
    }
}

/// Inserts and removes with Focus In, or a crossfade under Reduce Motion or Reduce Transparency.
private struct CanopyFocusInTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.transition(reduceMotion || reduceTransparency ? AnyTransition.opacity : AnyTransition(CanopyFocusInTransition()))
    }
}

extension View {
    /// Resolves from soft to sharp whenever `value` changes. Always comes to rest sharp.
    func canopyFocusIn<V: Equatable>(on value: V) -> some View {
        modifier(CanopyFocusInOnChange(value: value))
    }

    /// Inserts and removes the view with Focus In.
    func canopyFocusInTransition() -> some View {
        modifier(CanopyFocusInTransitionModifier())
    }
}
