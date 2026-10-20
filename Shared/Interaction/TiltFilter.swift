import Foundation

/// Turns raw device-motion gravity into a calm tilt for parallax: how far the phone has moved away from the way it is
/// being held, smoothed, with a dead zone and a limit, and only reported when it changes enough to see.
///
/// - The way the phone is held drifts back to centre over a few seconds (a much slower filter follows the raw
///   gravity), so holding the phone at any angle, or laying it flat, settles to no tilt at all.
/// - A low-pass filter takes out the hand's tremor; a dead zone swallows what is left of the sensor noise.
/// - The output is clamped to `limit` and reported only when it moves by `step` or more, so a phone held still or
///   lying on a table causes no updates.
struct TiltFilter: Sendable {
    /// Share of each new sample let through by the fast filter (at 30 Hz, about a quarter-second time constant).
    var smoothing = 0.12
    /// Share of each new sample the resting pose follows (at 30 Hz, about three seconds).
    var settling = 0.011
    var deadZone = 0.025
    var limit = 0.3
    var step = 0.004

    private(set) var output = RibbonVector.zero
    private var fast: RibbonVector?
    private var rest: RibbonVector?

    init() {}

    /// Feeds one gravity sample; returns the new tilt when it changed by at least `step`, otherwise nil.
    mutating func feed(_ raw: RibbonVector) -> RibbonVector? {
        guard raw.x.isFinite, raw.y.isFinite else { return nil }
        let previousFast = fast ?? raw
        let smoothed = RibbonVector(
            x: previousFast.x + smoothing * (raw.x - previousFast.x),
            y: previousFast.y + smoothing * (raw.y - previousFast.y)
        )
        fast = smoothed
        let previousRest = rest ?? raw
        let held = RibbonVector(
            x: previousRest.x + settling * (smoothed.x - previousRest.x),
            y: previousRest.y + settling * (smoothed.y - previousRest.y)
        )
        rest = held
        let next = RibbonVector(x: shape(smoothed.x - held.x), y: shape(smoothed.y - held.y))
        guard abs(next.x - output.x) >= step || abs(next.y - output.y) >= step || (next == .zero && output != .zero) else {
            return nil
        }
        output = next
        return next
    }

    /// Back to no tilt, as when parallax stops.
    mutating func reset() {
        fast = nil
        rest = nil
        output = .zero
    }

    /// The dead zone taken off (so the tilt grows from zero at its edge rather than jumping), then clamped.
    private func shape(_ value: Double) -> Double {
        let magnitude = abs(value) - deadZone
        guard magnitude > 0 else { return 0 }
        return min(limit, magnitude) * (value < 0 ? -1 : 1)
    }
}
