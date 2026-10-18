import Foundation

/// The kinds of haptic a scrubbing control asks for, from lightest to heaviest in priority.
enum ScrubHapticKind: Int, Sendable, Comparable {
    /// A plain detent.
    case tick = 0
    /// A detent that marks a round number (every fifth, say).
    case majorTick = 1
    /// The control locking onto a magnet.
    case magnetSnap = 2
    /// The control pushing against its end.
    case boundsHit = 3

    static func < (lhs: ScrubHapticKind, rhs: ScrubHapticKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One haptic the view should play. `intensity` and `sharpness` are 0...1, the two knobs of a Core Haptics transient.
struct ScrubHapticEvent: Sendable, Equatable {
    var kind: ScrubHapticKind
    /// The value the control arrived at (the magnet's value for a snap).
    var value: Double
    var intensity: Double
    var sharpness: Double
    /// +1 when the value was rising, -1 when falling.
    var direction: Int
    /// The caller's timestamp for the update that produced it.
    var time: Double
}

/// What one update of the model asks the view to do. `events` is empty most of the time and has at most one entry,
/// because a burst of detents in one frame is one tap, not a buzz.
struct ScrubFeedback: Sendable, Equatable {
    var events: [ScrubHapticEvent]
    /// Horizontal or vertical motion blur for the digits and ticks, in points. 0...6.
    var motionBlurRadius: Double
    /// How far the digits should be mid-transition, 0 (crisp) to 1 (a full blur-through). Feeds the numeric text
    /// transition's blur and opacity.
    var digitTransition: Double

    static let none = ScrubFeedback(events: [], motionBlurRadius: 0, digitTransition: 0)
}

/// The mapping from finger speed to feel. The rule from NEXT.md section 9: faster scrubs get a lighter, denser haptic
/// pattern and more blur; slow ones get crisp detents; major ticks hit harder. "Denser" comes for free from more
/// detents per second; this turns speed into the intensity, sharpness and blur.
enum ScrubFeel {
    /// How fast the control is moving, 0 (still) to 1 (as fast as it ever counts). Infinity is 1 and NaN is 0, so a
    /// bad velocity can't push blur or intensity out of range.
    static func speedFraction(velocity: Double, step: Double, fastStepsPerSecond: Double) -> Double {
        guard !velocity.isNaN, step > 0, fastStepsPerSecond > 0 else { return 0 }
        let stepsPerSecond = abs(velocity) / step
        return InteractionMath.clamp(stepsPerSecond / fastStepsPerSecond, 0, 1)
    }

    /// Motion blur in points: nothing for a slow drag, rising smoothly to `maxRadius` (never above 6) at full speed.
    static func motionBlurRadius(speedFraction: Double, maxRadius: Double) -> Double {
        let cap = InteractionMath.clamp(maxRadius, 0, ScrubConfiguration.blurLimit)
        return min(cap * InteractionMath.smoothstep(0.08, 0.9, speedFraction), ScrubConfiguration.blurLimit)
    }

    /// The digits start to blur a little earlier than the whole control does.
    static func digitTransition(speedFraction: Double) -> Double {
        InteractionMath.smoothstep(0.04, 0.6, speedFraction)
    }

    /// Intensity and sharpness for a haptic of `kind` at the given speed. Ticks, major ticks and snaps get lighter and
    /// softer as the finger speeds up. A bounds hit is the opposite: a harder knock for a harder impact, always dull.
    static func character(of kind: ScrubHapticKind, speedFraction: Double) -> (intensity: Double, sharpness: Double) {
        let s = InteractionMath.smoothstep(0, 1, speedFraction)
        switch kind {
        case .tick:
            return (InteractionMath.lerp(0.8, 0.3, s), InteractionMath.lerp(0.7, 0.45, s))
        case .majorTick:
            return (InteractionMath.lerp(1.0, 0.6, s), InteractionMath.lerp(0.85, 0.6, s))
        case .magnetSnap:
            return (InteractionMath.lerp(0.95, 0.65, s), InteractionMath.lerp(0.9, 0.7, s))
        case .boundsHit:
            return (InteractionMath.lerp(0.45, 1.0, s), 0.25)
        }
    }

    static func event(_ kind: ScrubHapticKind, value: Double, direction: Int, time: Double, speedFraction: Double) -> ScrubHapticEvent {
        let feel = character(of: kind, speedFraction: speedFraction)
        return ScrubHapticEvent(
            kind: kind,
            value: value,
            intensity: feel.intensity,
            sharpness: feel.sharpness,
            direction: direction >= 0 ? 1 : -1,
            time: time
        )
    }
}
