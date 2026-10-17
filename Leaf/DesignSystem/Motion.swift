import SwiftUI
import UIKit

/// Every animation in Leaf (DESIGN.md §7). Under Reduce Motion, everything becomes `Motion.fade`
/// (a 0.2 s crossfade) except the zoom transition and the reading-mode dim.
enum Motion {
    /// Layout changes, shelf underline, reflow bands.
    static let paper: Animation = .spring(response: 0.38, dampingFraction: 0.86)
    /// Covers rising, PageEntryPanel, week marker fill.
    static let board: Animation = .spring(response: 0.55, dampingFraction: 0.80)
    /// `glassEffectID` morphs, toggles, weekday underline.
    static let glass: Animation = .spring(response: 0.32, dampingFraction: 0.72)

    /// Screen entrances: opacity 0→1 and y +8→0. Use `.inkIn(index)` on up to six blocks.
    static let inkIn: Animation = .smooth(duration: 0.45)
    static let inkInStagger: TimeInterval = 0.05
    static let inkInRise: CGFloat = 8
    static let inkInMaxItems = 6

    /// Goal strike: animate a `trim` 0→1.
    static let strike: Animation = .easeOut(duration: 0.5)
    /// "The End" rule: `trim` 0→1 after a 0.3 s delay.
    static let ruleDraw: Animation = .easeOut(duration: 0.6).delay(0.3)

    /// WPM count-up length; drive it from a `TimelineView` with `countUpProgress(_:)`.
    static let countUpDuration: TimeInterval = 1.2

    /// Paused timer, live accessory dot. Use `.breathing(_:)`.
    static let breathe: Animation = .easeInOut(duration: 1.2)
    static let breathePhases: [Double] = [1, 0.55]

    /// Welcome wordmark: blur 8→0 and opacity 0→1. Use `.inkBleed()`.
    static let inkBleed: Animation = .easeOut(duration: 1.2)
    static let inkBleedBlur: CGFloat = 8

    /// Plan and To read reflow: dates roll with `numericText` + `paper`, staggered per row.
    static let reflowStagger: TimeInterval = 0.045
    /// The `ribbonSoft` flash behind a changed date. Use `.reflowFlash(trigger:)`.
    static let reflowFlashDuration: TimeInterval = 0.6

    /// "The End": cover `board`, then the title fades in over 0.4 s at +0.3 s, then `ruleDraw`.
    static let theEndTitle: Animation = .easeOut(duration: 0.4).delay(0.3)

    /// Countdown numerals scale from this to 1 as they fade in (`AnyTransition.countdownNumeral`).
    static let countdownScale: CGFloat = 1.15

    /// A real cover image fading in over its generated cover.
    static let coverFade: Animation = .easeOut(duration: 0.3)

    /// How long a DeltaChip stays up.
    static let deltaChipDuration: TimeInterval = 2.5

    /// The Reduce Motion replacement for everything above.
    static let fade: Animation = .easeInOut(duration: 0.2)

    /// `animation`, or `fade` when Reduce Motion is on.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    /// `transition`, or a plain opacity crossfade when Reduce Motion is on.
    static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }

    /// Entrance delay for the `index`th item: 0.05 s apart, capped after six items.
    static func stagger(_ index: Int, step: TimeInterval = Motion.inkInStagger) -> TimeInterval {
        Double(min(max(index, 0), Motion.inkInMaxItems - 1)) * step
    }

    /// Ease-out cubic for the count-up: maps elapsed fraction 0…1 to value fraction 0…1.
    static func countUpProgress(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return 1 - pow(1 - clamped, 3)
    }

    /// `withAnimation` that respects Reduce Motion, for code outside a view's environment.
    @MainActor
    static func animate<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
        try withAnimation(UIAccessibility.isReduceMotionEnabled ? fade : animation, body)
    }
}

// MARK: - Transitions

extension AnyTransition {
    /// Opacity plus an 8 pt rise: the `inkIn` entrance as a transition.
    static var inkIn: AnyTransition {
        .opacity.combined(with: .offset(y: Motion.inkInRise))
    }

    /// Onboarding steps: crossfade with a rise on the way in.
    static func rise(_ distance: CGFloat = 12) -> AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: distance)), removal: .opacity)
    }

    /// Countdown numerals: scale 1.15 → 1 and fade.
    static var countdownNumeral: AnyTransition {
        .asymmetric(insertion: .scale(scale: Motion.countdownScale).combined(with: .opacity), removal: .opacity)
    }
}

// MARK: - Modifiers

/// `.animation(_:value:)` that swaps to `Motion.fade` under Reduce Motion.
struct LeafAnimationModifier<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(animation: Animation, value: Value) {
        self.animation = animation
        self.value = value
    }

    func body(content: Content) -> some View {
        content.animation(Motion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

/// Screen entrance: fades in and rises 8 pt, staggered by `index`.
struct InkInModifier: ViewModifier {
    let index: Int

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(index: Int) {
        self.index = index
    }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : Motion.inkInRise)
            .onAppear {
                guard !isVisible else { return }
                let animation = Motion.resolved(Motion.inkIn, reduceMotion: reduceMotion)
                withAnimation(animation.delay(Motion.stagger(index))) {
                    isVisible = true
                }
            }
    }
}

/// The welcome wordmark's ink bleed: blur 8→0 and opacity 0→1 over 1.2 s.
struct InkBleedModifier: ViewModifier {
    let delay: TimeInterval

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: isVisible || reduceMotion ? 0 : Motion.inkBleedBlur)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                guard !isVisible else { return }
                let animation = Motion.resolved(Motion.inkBleed, reduceMotion: reduceMotion)
                withAnimation(animation.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

/// Opacity pulses 1 → 0.55 while active. Stops under Reduce Motion.
struct BreathingModifier: ViewModifier {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isActive: Bool) {
        self.isActive = isActive
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            content.phaseAnimator(Motion.breathePhases) { view, phase in
                view.opacity(phase)
            } animation: { _ in
                Motion.breathe
            }
        } else {
            content
        }
    }
}

/// Animated value for the ribbon sway keyframes.
struct RibbonSwayValue {
    var angle: Double = 0
}

/// Animated value for the reflow flash keyframes.
struct ReflowFlashValue {
    var opacity: Double = 0
}

/// A 0.6 s `ribbonSoft` flash behind content whenever `trigger` changes.
struct ReflowFlashModifier<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    let delay: TimeInterval

    func body(content: Content) -> some View {
        let hold = max(delay, 0.001)
        let rise = 0.08
        let fall = Motion.reflowFlashDuration - rise
        return content.keyframeAnimator(initialValue: ReflowFlashValue(), trigger: trigger) { view, value in
            view.background {
                Capsule()
                    .fill(Color.ribbonSoft)
                    .padding(.horizontal, -Space.xs)
                    .padding(.vertical, -Space.xxs)
                    .opacity(value.opacity)
            }
        } keyframes: { _ in
            KeyframeTrack(\.opacity) {
                LinearKeyframe(0, duration: hold)
                LinearKeyframe(1, duration: rise)
                LinearKeyframe(0, duration: fall)
            }
        }
    }
}

extension View {
    /// `.animation(animation, value:)`, crossfading instead under Reduce Motion.
    func leafAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(LeafAnimationModifier(animation: animation, value: value))
    }

    /// Screen entrance (`Motion.inkIn`). Put it on up to six top-level blocks, `index` 0, 1, 2…
    /// Not for rows inside lazy lists.
    func inkIn(_ index: Int = 0) -> some View {
        modifier(InkInModifier(index: index))
    }

    /// The welcome wordmark's ink bleed.
    func inkBleed(delay: TimeInterval = 0) -> some View {
        modifier(InkBleedModifier(delay: delay))
    }

    /// Breathes (opacity 1 ↔ 0.55) while `isActive`. Paused timer, live dot.
    func breathing(_ isActive: Bool = true) -> some View {
        modifier(BreathingModifier(isActive: isActive))
    }

    /// Flashes `ribbonSoft` behind the view for 0.6 s when `trigger` changes (a date that moved).
    /// Pass `delay: Motion.reflowStagger * Double(row)` to stagger rows.
    func reflowFlash<Trigger: Equatable>(trigger: Trigger, delay: TimeInterval = 0) -> some View {
        modifier(ReflowFlashModifier(trigger: trigger, delay: delay))
    }

    /// The cover ribbon's sway: rotation about the top edge, 3° → −2° → 1° → 0°. Plays when
    /// `trigger` changes; don't change it under Reduce Motion.
    func ribbonSway<Trigger: Equatable>(trigger: Trigger) -> some View {
        keyframeAnimator(initialValue: RibbonSwayValue(), trigger: trigger) { view, value in
            view.rotationEffect(.degrees(value.angle), anchor: .top)
        } keyframes: { _ in
            KeyframeTrack(\.angle) {
                SpringKeyframe(3, duration: 0.25)
                SpringKeyframe(-2, duration: 0.3)
                SpringKeyframe(1, duration: 0.3)
                SpringKeyframe(0, duration: 0.35)
            }
        }
    }
}
