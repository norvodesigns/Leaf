import Foundation

// MARK: - Elements

/// One out-of-focus light (candle, fairy lights) for the session screen. Positions and radii are in the scene's unit
/// space: x and y from 0 to 1 across and down, radius as a share of the scene's shorter side.
struct AtmosphereBokeh: Sendable, Equatable {
    var x: Double
    var y: Double
    var radius: Double
    /// -1...1: how far to shift the base warm hue, for variety among the lights.
    var hueOffset: Double
    var opacity: Double
}

/// One trickle of rain on the glass. `y` is the head (the lower end); the streak runs up from it by `length`. It enters
/// above the top and leaves below the bottom entirely out of sight, so its wrap-around never shows.
struct AtmosphereRainStreak: Sendable, Equatable {
    var x: Double
    var y: Double
    /// Share of the scene height.
    var length: Double
    /// Share of the scene width.
    var width: Double
    /// Scene heights per second of phase (multiply by the clock's tempo for real seconds).
    var speed: Double
    /// 0 far and blurry, 1 near and sharp.
    var depth: Double
    /// 0 far, 1 middle, 2 near. For drawing in three passes with different blur.
    var layer: Int
    var opacity: Double
}

/// One curl of steam from the cup. It fades in at the rim, widens and sways as it rises, and has faded out by the top,
/// so its restart never shows.
struct AtmosphereSteamWisp: Sendable, Equatable {
    var x: Double
    var y: Double
    /// 0 at the rim, 1 where it has gone.
    var progress: Double
    /// Share of the scene width.
    var width: Double
    /// Scene heights per second of phase.
    var riseSpeed: Double
    var opacity: Double
}

/// One ember lifting off the hearth. It fades in at the bottom, drifts up and sideways, and has gone dark before it
/// restarts, so the loop never shows.
struct AtmosphereEmber: Sendable, Equatable {
    var x: Double
    var y: Double
    /// Share of the scene's shorter side.
    var radius: Double
    /// 0 at the hearth, 1 where it has gone.
    var progress: Double
    var opacity: Double
}

// MARK: - Generators

/// Seeded, time-parameterised generators for the blur scenes (NEXT.md section 7): bokeh, rain on glass and steam.
///
/// Why pure functions: the view samples them from a `TimelineView` at about 15 fps and draws what comes back. There is
/// no state to step, no random source, and the same seed, time and settings give the same scene on any device, so a
/// scene is easy to test and costs almost nothing to compute. Everything moves smoothly with time, so low frame rates
/// look slow, not jumpy.
///
/// `calm` is the scene's energy from 0 to 1. 1 is the normal gentle drift; lower values slow everything down and soften
/// the sway; 0 freezes it, which is what a paused session wants. When calm changes while the scene is on screen, use an
/// `AtmosphereClock` and the `phase:` variants, so nothing jumps as the pace changes. The `time:` variants are for a
/// calm that stays fixed.
enum AtmosphereField {
    static let maxBokeh = 40
    static let maxRain = 120
    static let maxSteam = 24
    static let maxEmbers = 24

    /// How fast the scene's clock runs at a calm level: the calm itself, limited to 0...1.
    static func tempo(forCalm calm: Double) -> Double {
        InteractionMath.clamp(InteractionMath.finite(calm, fallback: 1), 0, 1)
    }

    /// How wide sway and drift are at a calm level: a little less when calm is low, so a slowed scene also loosens.
    static func amplitude(forCalm calm: Double) -> Double {
        InteractionMath.lerp(0.55, 1, tempo(forCalm: calm))
    }

    private static func phase(forTime time: Double, calm: Double) -> Double {
        InteractionMath.finite(time) * tempo(forCalm: calm)
    }

    private static func stream(_ seed: UInt64, _ salt: UInt64, _ index: Int) -> SeededGenerator {
        SeededGenerator(seed: InteractionMath.mix(seed, salt &+ UInt64(index)))
    }

    private static func wave(_ cycles: Double) -> Double {
        sin(2 * Double.pi * cycles)
    }

    // MARK: Bokeh

    /// Slowly drifting soft circles. Drift speeds are between one cycle a minute and a half and one every forty
    /// seconds, a few percent of the scene across, so even at 15 fps nothing visibly steps.
    static func bokeh(seed: UInt64, time: Double, count: Int, calm: Double) -> [AtmosphereBokeh] {
        bokeh(seed: seed, phase: phase(forTime: time, calm: calm), count: count, calm: calm)
    }

    static func bokeh(seed: UInt64, phase: Double, count: Int, calm: Double) -> [AtmosphereBokeh] {
        let n = min(max(count, 0), maxBokeh)
        let p = InteractionMath.finite(phase)
        let reach = amplitude(forCalm: calm)
        var lights: [AtmosphereBokeh] = []
        lights.reserveCapacity(n)
        for index in 0..<n {
            var g = stream(seed, 0xB0_0000, index)
            let baseX = 0.06 + 0.88 * g.unit()
            let baseY = 0.06 + 0.88 * g.unit()
            let sizeRoll = g.unit()
            let baseRadius = 0.06 + 0.2 * sizeRoll * sizeRoll
            let hue = g.unit() * 2 - 1
            let baseOpacity = 0.10 + 0.25 * g.unit()
            let driftX = 1.0 / 90 + g.unit() * (1.0 / 40 - 1.0 / 90)
            let driftY = 1.0 / 90 + g.unit() * (1.0 / 40 - 1.0 / 90)
            let glow = 1.0 / 45 + g.unit() * (1.0 / 20 - 1.0 / 45)
            let swell = 1.0 / 60 + g.unit() * (1.0 / 30 - 1.0 / 60)
            let reachX = (0.015 + 0.04 * g.unit()) * reach
            let reachY = (0.015 + 0.04 * g.unit()) * reach
            let phaseX = g.unit(), phaseY = g.unit(), phaseGlow = g.unit(), phaseSwell = g.unit()

            let brightness = 0.7 + 0.3 * (0.5 + 0.5 * wave(glow * p + phaseGlow))
            lights.append(AtmosphereBokeh(
                x: baseX + reachX * wave(driftX * p + phaseX),
                y: baseY + reachY * wave(driftY * p + phaseY + 0.2),
                radius: baseRadius * (1 + 0.05 * wave(swell * p + phaseSwell)),
                hueOffset: hue,
                opacity: baseOpacity * brightness
            ))
        }
        return lights
    }

    // MARK: Rain

    /// Rain trickling down glass: three depth layers, slow stop-and-go surges, a faint sideways wander. Far streaks are
    /// short, thin, faint and slow; near ones are long, wide and quicker.
    static func rain(seed: UInt64, time: Double, count: Int, calm: Double) -> [AtmosphereRainStreak] {
        rain(seed: seed, phase: phase(forTime: time, calm: calm), count: count, calm: calm)
    }

    static func rain(seed: UInt64, phase: Double, count: Int, calm: Double) -> [AtmosphereRainStreak] {
        let n = min(max(count, 0), maxRain)
        let p = InteractionMath.finite(phase)
        let reach = amplitude(forCalm: calm)
        let lane = InteractionMath.unit(seed, 0x51)
        var streaks: [AtmosphereRainStreak] = []
        streaks.reserveCapacity(n)
        for index in 0..<n {
            var g = stream(seed, 0xA1_0000, index)
            let roll = g.unit()
            let layer = roll < 0.5 ? 0 : (roll < 0.82 ? 1 : 2)
            let depth = (Double(layer) + min(g.unit(), 0.999)) / 3
            let jitter = (g.unit() - 0.5) * 0.3 / Double(max(n, 1))
            let x0 = InteractionMath.fract(lane + Double(index) * 0.618_033_988_75 + jitter)
            let length = InteractionMath.lerp(0.05, 0.22, depth) * (0.8 + 0.4 * g.unit())
            let width = InteractionMath.lerp(0.0025, 0.009, depth)
            let baseSpeed = InteractionMath.lerp(0.035, 0.11, depth) * (0.8 + 0.4 * g.unit())
            let startY = g.unit()
            let surgePeriod = 6 + 5 * g.unit()
            let surgePhase = g.unit()
            let wanderPeriod = 9 + 8 * g.unit()
            let wanderPhase = g.unit()
            let shimmerPhase = g.unit()

            // Time as the streak feels it: steady, with a slow surge on top. The surge never runs backwards because
            // its slope (0.35 * 2 pi / 6) stays well below 1.
            let surge = 0.35 * wave(p / surgePeriod + surgePhase)
            let local = p + surge
            let slope = 1 + 0.35 * (2 * Double.pi / surgePeriod) * cos(2 * Double.pi * (p / surgePeriod + surgePhase))

            let span = 1 + 2 * length
            let head = -length + InteractionMath.fract(startY + baseSpeed * local) * span
            let wander = 0.012 * (depth + 0.3) * reach * wave(local / wanderPeriod + wanderPhase)
            let shimmer = 0.85 + 0.15 * wave(local / 7 + shimmerPhase)
            streaks.append(AtmosphereRainStreak(
                x: x0 + wander,
                y: head,
                length: length,
                width: width,
                speed: baseSpeed * span * slope,
                depth: depth,
                layer: layer,
                opacity: InteractionMath.lerp(0.18, 0.55, depth) * shimmer
            ))
        }
        return streaks
    }

    // MARK: Steam

    /// Wisps rising from the cup, each on its own six-to-eleven-second loop, so the plume never repeats in step.
    static func steam(seed: UInt64, time: Double, count: Int, calm: Double) -> [AtmosphereSteamWisp] {
        steam(seed: seed, phase: phase(forTime: time, calm: calm), count: count, calm: calm)
    }

    static func steam(seed: UInt64, phase: Double, count: Int, calm: Double) -> [AtmosphereSteamWisp] {
        let n = min(max(count, 0), maxSteam)
        let p = InteractionMath.finite(phase)
        let reach = amplitude(forCalm: calm)
        let thinning = InteractionMath.lerp(0.6, 1, tempo(forCalm: calm))
        var wisps: [AtmosphereSteamWisp] = []
        wisps.reserveCapacity(n)
        for index in 0..<n {
            var g = stream(seed, 0x57_0000, index)
            let baseX = 0.5 + (g.unit() - 0.5) * 0.36
            let period = 6.5 + 5 * g.unit()
            let offset = g.unit()
            let rise = 0.45 + 0.35 * g.unit()
            let swayReach = (0.02 + 0.04 * g.unit()) * reach
            let swayCycles = 1.2 + 0.8 * g.unit()
            let swayPhase = g.unit()
            let baseWidth = 0.06 + 0.04 * g.unit()
            let peak = 0.25 + 0.2 * g.unit()

            let u = InteractionMath.fract(p / period + offset)
            let fade = sin(Double.pi * u)
            wisps.append(AtmosphereSteamWisp(
                x: baseX + swayReach * wave(swayCycles * u + swayPhase) * (0.4 + 0.6 * u),
                y: 1 - rise * u,
                progress: u,
                width: baseWidth * (0.6 + 0.8 * u),
                riseSpeed: rise / period,
                opacity: peak * fade * sqrt(max(fade, 0)) * thinning
            ))
        }
        return wisps
    }
    // MARK: Hearth

    /// The firelight's brightness, about 0.7 to 1: two layers of smooth noise, a slow swell and a quicker shiver, so
    /// it breathes like a fire without the mechanical beat of a sine. Continuous in `phase`, so 15 fps looks calm.
    static func flicker(seed: UInt64, phase: Double) -> Double {
        let p = InteractionMath.finite(phase)
        let swell = InteractionMath.smoothNoise(seed: InteractionMath.mix(seed, 0xF1), at: p * 0.55)
        let shiver = InteractionMath.smoothNoise(seed: InteractionMath.mix(seed, 0xF2), at: p * 1.9)
        return InteractionMath.clamp(0.84 + 0.10 * swell + 0.05 * shiver, 0, 1)
    }

    /// A few embers rising from the hearth, each on its own seven-to-thirteen-second loop, lower half of the scene only.
    static func embers(seed: UInt64, time: Double, count: Int, calm: Double) -> [AtmosphereEmber] {
        embers(seed: seed, phase: phase(forTime: time, calm: calm), count: count, calm: calm)
    }

    static func embers(seed: UInt64, phase: Double, count: Int, calm: Double) -> [AtmosphereEmber] {
        let n = min(max(count, 0), maxEmbers)
        let p = InteractionMath.finite(phase)
        let reach = amplitude(forCalm: calm)
        var embers: [AtmosphereEmber] = []
        embers.reserveCapacity(n)
        for index in 0..<n {
            var g = stream(seed, 0xE3_0000, index)
            let baseX = 0.5 + (g.unit() - 0.5) * 0.6
            let period = 7 + 6 * g.unit()
            let offset = g.unit()
            let rise = 0.22 + 0.26 * g.unit()
            let driftReach = (0.02 + 0.05 * g.unit()) * reach
            let driftCycles = 0.8 + 0.8 * g.unit()
            let driftPhase = g.unit()
            let baseRadius = 0.003 + 0.004 * g.unit()
            let peak = 0.35 + 0.4 * g.unit()

            let u = InteractionMath.fract(p / period + offset)
            let fade = sin(Double.pi * u)
            embers.append(AtmosphereEmber(
                x: baseX + driftReach * wave(driftCycles * u + driftPhase) * u,
                y: 1 - rise * u,
                radius: baseRadius * (1 - 0.5 * u),
                progress: u,
                opacity: peak * fade * fade
            ))
        }
        return embers
    }
}

// MARK: - Clock

/// Keeps a scene's phase continuous while its calm changes. Pause the session and the calm eases to 0 over about a
/// second, the phase stops advancing, and nothing jumps; resume and it eases back. Feed `phase` to the `phase:`
/// variants of `AtmosphereField`.
///
/// The phase is the exact integral of the eased calm over the time given, so it comes out the same however the frames
/// are cut (15 fps, 60 fps, one big frame), and a gap longer than a second (the app was in the background) is counted
/// as a second, not replayed.
struct AtmosphereClock: Sendable, Equatable {
    /// Scene seconds so far: wall time weighted by calm.
    private(set) var phase = 0.0
    /// The eased calm, 0...1.
    private(set) var calm: Double
    /// Seconds for the calm to close about two thirds of the way to its target.
    let response: Double
    private var lastTime: Double?

    static let longestFrame = 1.0

    init(calm: Double = 1, response: Double = 0.8) {
        self.calm = AtmosphereField.tempo(forCalm: calm)
        self.response = InteractionMath.clamp(InteractionMath.finite(response, fallback: 0.8), 0.05, 10)
    }

    /// How fast the scene's clock is running right now.
    var tempo: Double { AtmosphereField.tempo(forCalm: calm) }

    /// Moves the clock to wall time `time` (any steady clock, in seconds) aiming for `target` calm, and returns the new
    /// phase. A time earlier than the last one does nothing.
    @discardableResult
    mutating func advance(to time: Double, calm target: Double) -> Double {
        guard time.isFinite else { return phase }
        guard let last = lastTime else {
            lastTime = time
            return phase
        }
        let elapsed = min(max(time - last, 0), AtmosphereClock.longestFrame)
        lastTime = max(last, time)
        guard elapsed > 0 else { return phase }

        let goal = AtmosphereField.tempo(forCalm: target)
        let decay = exp(-elapsed / response)
        phase += goal * elapsed + (calm - goal) * response * (1 - decay)
        calm = goal + (calm - goal) * decay
        return phase
    }
}
