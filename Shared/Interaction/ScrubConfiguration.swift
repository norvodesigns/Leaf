import Foundation

// MARK: - Magnets

/// A value the control likes to rest on: the reader's daily goal, a finish date that changes the book count, a round
/// hour. Inside `radius` the control locks onto `value`; between `radius` and `releaseRadius` it is pulled in smoothly;
/// the snap haptic re-arms only once the position has left `releaseRadius`. That gap is the release hysteresis: a
/// finger wobbling around the edge of the magnet can't make it click again and again. A scrub or flick that ends
/// inside `releaseRadius` comes to rest on the magnet.
///
/// Radii are in the control's own units (minutes, pages, days).
struct ScrubMagnet: Sendable, Equatable {
    var value: Double
    var radius: Double
    var releaseRadius: Double

    /// - Parameter releaseRadius: defaults to twice `radius`.
    init(value: Double, radius: Double, releaseRadius: Double? = nil) {
        self.value = value
        self.radius = radius
        self.releaseRadius = releaseRadius ?? radius * 2
    }
}

// MARK: - Formatting

/// Turns a scrubbed value into text. The control draws the digits; this decides what they say. A hook rather than a
/// fixed format because the same engine drives minutes, pages, hours, steep times and dates.
struct ScrubValueFormat: Sendable {
    let render: @Sendable (Double) -> String

    init(_ render: @escaping @Sendable (Double) -> String) {
        self.render = render
    }

    func callAsFunction(_ value: Double) -> String { render(value) }

    /// "42". Never "-0".
    static let integer = ScrubValueFormat { value in
        String(Int(ScrubValueFormat.safe(value).rounded()))
    }

    /// "4.5" with `places` decimals (0 to 6). Never "-0.0".
    static func decimal(_ places: Int) -> ScrubValueFormat {
        let digits = min(max(places, 0), 6)
        return ScrubValueFormat { value in
            let scale = pow(10.0, Double(digits))
            let rounded = (ScrubValueFormat.safe(value) * scale).rounded() / scale
            return String(format: "%.\(digits)f", rounded == 0 ? 0 : rounded)
        }
    }

    /// Minutes as a duration: "20 min", "1 h 5 min".
    static let minutes = ScrubValueFormat { value in
        LeafFormat.duration(minutes: min(max(ScrubValueFormat.safe(value), 0), 10_000_000))
    }

    /// Minutes in the compact form for tight spaces: "20m", "1h 5m".
    static let compactMinutes = ScrubValueFormat { value in
        LeafFormat.compactDuration(minutes: min(max(ScrubValueFormat.safe(value), 0), 10_000_000))
    }

    /// A page number: "p. 142".
    static let page = ScrubValueFormat { value in
        "p. \(Int(ScrubValueFormat.safe(value).rounded()))"
    }

    /// Any other text for a value.
    static func custom(_ render: @escaping @Sendable (Double) -> String) -> ScrubValueFormat {
        ScrubValueFormat(render)
    }

    /// A finite value limited to a range `Int` can hold.
    fileprivate static func safe(_ value: Double) -> Double {
        InteractionMath.clamp(InteractionMath.finite(value), -1e15, 1e15)
    }
}

// MARK: - Configuration

/// Everything that shapes one scrubbing control: its range and steps, where it clicks, where it sticks, how it feels
/// at the ends and how much feedback it may ask for. Safe to build from any numbers: `sanitized` forces every field
/// into a working range.
struct ScrubConfiguration: Sendable {
    var range: ClosedRange<Double>
    /// The smallest change of value. The value always lands on `range.lowerBound + n * step`, or on a magnet.
    var step: Double = 1
    /// How far the finger travels for one step, in points.
    var pointsPerStep: Double = 8
    /// A light haptic tick every this many steps (1 ticks on every step).
    var detentEvery = 1
    /// A heavier tick every this many detents (0 for none).
    var majorEvery = 5
    var magnets: [ScrubMagnet] = []
    /// How far past a step's midpoint the position must travel before the value changes, as a fraction of a step. This
    /// is the Schmitt-trigger gap that stops a trembling finger from flipping a boundary back and forth.
    var hysteresis = 0.12
    /// How far past the ends the display may stretch, in steps.
    var overscrollSteps = 2.0
    /// How strongly the ends push back at first: 1 is no resistance, near 0 is a brick wall.
    var resistance = 0.55
    /// The haptic budget. Tick and major tick events never come faster than this; snaps and bounds hits, which are rare
    /// by construction, may come at up to twice this rate.
    var maxEventsPerSecond = 30.0
    /// The speed, in steps per second, at which feedback counts as fully "fast".
    var fastStepsPerSecond = 40.0
    /// Motion blur at full speed, in points. Never more than 6.
    var maxBlurRadius = 6.0
    /// How quickly a flick slows down, as a rate per second. Higher stops sooner.
    var friction = 3.0
    var format = ScrubValueFormat.integer

    init(range: ClosedRange<Double>, step: Double = 1) {
        self.range = range
        self.step = step
    }

    /// Hard ceiling for `maxBlurRadius`, from the blur design language (NEXT.md section 7).
    static let blurLimit = 6.0

    /// The same configuration with every number forced into a usable range, magnets that can't overlap, and out-of-range
    /// or non-finite magnets dropped.
    var sanitized: ScrubConfiguration {
        func safe(_ value: Double, _ low: Double, _ high: Double, _ fallback: Double) -> Double {
            InteractionMath.clamp(InteractionMath.finite(value, fallback: fallback), low, high)
        }
        var c = self
        let lower = InteractionMath.finite(range.lowerBound, fallback: 0)
        let upper = max(lower, InteractionMath.finite(range.upperBound, fallback: lower))
        c.range = lower...upper
        let width = upper - lower
        c.step = width > 0 ? safe(step, width / 1_000_000, width, 1) : 1
        c.pointsPerStep = safe(pointsPerStep, 0.01, 1000, 8)
        c.detentEvery = min(max(detentEvery, 1), 1_000_000)
        c.majorEvery = min(max(majorEvery, 0), 1_000_000)
        c.hysteresis = safe(hysteresis, 0, 0.45, 0.12)
        c.overscrollSteps = safe(overscrollSteps, 0.25, 50, 2)
        c.resistance = safe(resistance, 0.1, 1, 0.55)
        c.maxEventsPerSecond = safe(maxEventsPerSecond, 1, 1000, 30)
        c.fastStepsPerSecond = safe(fastStepsPerSecond, 1, 10_000, 40)
        c.maxBlurRadius = safe(maxBlurRadius, 0, ScrubConfiguration.blurLimit, ScrubConfiguration.blurLimit)
        c.friction = safe(friction, 0.5, 20, 3)
        c.magnets = ScrubConfiguration.resolve(magnets, in: lower...upper)
        return c
    }

    /// Keeps magnets inside the range, sorted, and shrinks any whose zones would reach a neighbour's, so a magnet's pull
    /// can never fight another's and the position-to-display mapping stays monotonic.
    static func resolve(_ magnets: [ScrubMagnet], in range: ClosedRange<Double>) -> [ScrubMagnet] {
        var seen = Set<Double>()
        var usable: [ScrubMagnet] = []
        for magnet in magnets {
            guard magnet.value.isFinite, magnet.radius.isFinite, magnet.releaseRadius.isFinite else { continue }
            guard range.contains(magnet.value), seen.insert(magnet.value).inserted else { continue }
            let radius = max(magnet.radius, 0)
            usable.append(ScrubMagnet(value: magnet.value, radius: radius, releaseRadius: max(magnet.releaseRadius, radius)))
        }
        usable.sort { $0.value < $1.value }

        var result: [ScrubMagnet] = []
        for index in usable.indices {
            var magnet = usable[index]
            var room = Double.infinity
            if index > 0 { room = min(room, (magnet.value - usable[index - 1].value) / 2) }
            if index < usable.count - 1 { room = min(room, (usable[index + 1].value - magnet.value) / 2) }
            magnet.releaseRadius = min(magnet.releaseRadius, room)
            magnet.radius = min(magnet.radius, magnet.releaseRadius * 0.6)
            guard magnet.releaseRadius > 1e-12 else { continue }
            result.append(magnet)
        }
        return result
    }
}
