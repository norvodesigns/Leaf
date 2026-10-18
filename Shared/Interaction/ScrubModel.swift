import Foundation

/// Whether a scrub is being held, flying free, or at rest.
enum ScrubPhase: Sendable, Equatable {
    case idle
    /// A finger is down. Feed `drag(translation:at:)`.
    case dragging
    /// The finger lifted. The value coasts, settles on a step and springs back from the ends. Keep calling
    /// `advance(to:)` every frame until the phase is `.idle`.
    case coasting
}

/// The steps of a scrub range laid out as a grid, with the arithmetic to find cells and their midpoints in constant
/// time. The last cell is shorter when the range isn't a whole number of steps.
struct ScrubGrid: Sendable, Equatable {
    let lower: Double
    let upper: Double
    let step: Double
    /// Index of the last cell; 0 for a range with no width.
    let lastCell: Int

    init(range: ClosedRange<Double>, step: Double) {
        lower = range.lowerBound
        upper = range.upperBound
        self.step = step
        if upper > lower, step > 0 {
            lastCell = max(0, Int(((upper - lower) / step - 1e-9).rounded(.up)))
        } else {
            lastCell = 0
        }
    }

    /// The value at the centre of `cell`; the range's top for the last, possibly partial, cell.
    func position(ofCell cell: Int) -> Double {
        let clamped = min(max(cell, 0), lastCell)
        return min(lower + Double(clamped) * step, upper)
    }

    /// Where cell `k` ends and cell `k + 1` begins.
    func boundary(after cell: Int) -> Double {
        (position(ofCell: cell) + position(ofCell: cell + 1)) / 2
    }

    /// The cell whose region holds `x`: cell `k` covers from its lower midpoint up to its upper midpoint.
    func cell(containing x: Double) -> Int {
        guard lastCell > 0, x.isFinite else { return x > 0 && !x.isNaN ? lastCell : 0 }
        let ratio = InteractionMath.clamp((x - lower) / step + 0.5, -1, Double(lastCell) + 1)
        var cell = min(max(Int(ratio.rounded(.down)), 0), lastCell)
        while cell < lastCell, x >= boundary(after: cell) { cell += 1 }
        while cell > 0, x < boundary(after: cell - 1) { cell -= 1 }
        return cell
    }
}

/// A generic scrubbing control as pure maths: a number you change by dragging, with the detents, magnets, rubber
/// banding, momentum and feedback that make `TickRuler`, `MinutesDial` and `PageScrubber` feel good, so every dial, slider,
/// drum, crown and date scrub in the app can share one tested behaviour. The view draws and plays haptics; this decides.
///
/// Reading it:
/// - `value` is what the control means (snapped to a step, or a magnet's value); `displayValue` is where to draw, which
///   is continuous and can stretch past the ends.
/// - Each call returns a `ScrubFeedback`: at most one haptic event plus the motion blur and digit transition to show.
///
/// Driving it from a drag gesture:
/// 1. `begin(at:)` when the finger lands (optional; `drag` begins implicitly).
/// 2. `drag(translation:at:)` with the gesture's total translation along the axis, in points, and a timestamp in seconds.
/// 3. `end(at:)` when it lifts, then `advance(to:)` every frame while `phase` is `.coasting`.
///
/// Time only ever comes in as an argument, so the same trace of inputs always gives the same outputs, and coasting uses
/// a fixed 1/240 s step so the frame rate doesn't change where a flick lands.
struct ScrubModel: Sendable {
    let configuration: ScrubConfiguration

    private(set) var phase = ScrubPhase.idle
    /// The meaningful value: on the step grid, or exactly a magnet's value while locked onto one.
    private(set) var value: Double
    /// The value to draw. Continuous, pulled toward magnets, and stretched past the ends while overscrolled.
    private(set) var displayValue: Double
    /// How far the display is past an end, in value units: negative below the range, positive above, else 0.
    private(set) var overscroll = 0.0
    /// The smoothed speed of the value in units per second, signed. 0 at rest.
    private(set) var velocity = 0.0

    private let grid: ScrubGrid
    private let hysteresis: Double
    private let overscrollLimit: Double
    private let referenceStep: Double

    private var cell: Int
    private var armed: [Bool]
    private var bypassed: [Bool]
    private var lockedMagnet: Int?
    private var boundsArmed = true
    private var lastPosition: Double

    private var dragOrigin = 0.0
    private var lastSampleTime = 0.0
    private var lastSampleRaw = 0.0

    private var coastPosition = 0.0
    private var coastVelocity = 0.0
    private var coastClock = 0.0
    private var coastAccumulator = 0.0
    private var coastElapsed = 0.0

    private var lastEventTime: Double?
    private var pending: ScrubHapticEvent?

    /// Fixed physics step for coasting.
    private static let coastStep = 1.0 / 240
    /// How long without a drag callback before the finger's smoothed speed starts to fade, and how fast it fades.
    private static let staleAfter = 0.04
    private static let staleFade = 0.06
    /// Velocity smoothing time constant.
    private static let smoothing = 0.05

    /// - Parameter value: the starting value, limited to the range and snapped to a step.
    init(configuration: ScrubConfiguration, value: Double = 0) {
        let c = configuration.sanitized
        self.configuration = c
        let grid = ScrubGrid(range: c.range, step: c.step)
        self.grid = grid
        hysteresis = c.hysteresis * c.step
        overscrollLimit = c.overscrollSteps * c.step
        referenceStep = c.step
        let start = InteractionMath.clamp(InteractionMath.finite(value, fallback: c.range.lowerBound), c.range.lowerBound, c.range.upperBound)
        let startCell = grid.cell(containing: start)
        cell = startCell
        armed = Array(repeating: true, count: c.magnets.count)
        bypassed = Array(repeating: false, count: c.magnets.count)
        let snapped = grid.position(ofCell: startCell)
        self.value = snapped
        displayValue = snapped
        lastPosition = snapped
        rest(at: snapped)
    }

    /// The magnets after sanitising: inside the range, sorted, and kept apart.
    var magnets: [ScrubMagnet] { configuration.magnets }

    /// True while the view should keep calling `advance(to:)`.
    var isActive: Bool { phase != .idle }

    /// `value` as text, through the configuration's format hook.
    var formattedValue: String { configuration.format(value) }

    // MARK: Setting a value directly

    /// Puts the control at `value` without any feedback: a text field edit, a reset, a new book. Ends any gesture in
    /// progress. The value is limited to the range and snapped to a step.
    mutating func jump(to newValue: Double) {
        let target = InteractionMath.clamp(InteractionMath.finite(newValue, fallback: value), grid.lower, grid.upper)
        let newCell = grid.cell(containing: target)
        phase = .idle
        velocity = 0
        coastVelocity = 0
        pending = nil
        let snapped = exactMagnet(near: target).map { magnets[$0].value } ?? grid.position(ofCell: newCell)
        rest(at: snapped)
    }

    /// Moves by whole steps with feedback, for VoiceOver's adjustable action, a hardware keyboard or a watch crown
    /// detent. Past an end it asks for a bounds hit instead. Ends any gesture in progress.
    @discardableResult
    mutating func nudge(steps: Int, at time: Double) -> ScrubFeedback {
        guard time.isFinite else { return .none }
        if phase != .idle { jump(to: value) }
        guard steps != 0, grid.lastCell > 0 else { return finish([], at: time) }

        let wanted = steps > 0 ? min(steps, grid.lastCell - cell) : max(steps, -cell)
        let direction = steps > 0 ? 1 : -1
        let u = 0.2
        guard wanted != 0 else {
            let edge = steps > 0 ? grid.upper : grid.lower
            let hit = ScrubFeel.event(.boundsHit, value: edge, direction: direction, time: time, speedFraction: u)
            return finish([hit], at: time)
        }

        let from = cell
        let to = from + wanted
        var events: [ScrubHapticEvent] = []
        if let detent = detentEvent(from: from, to: to, time: time, speedFraction: u) { events.append(detent) }
        cell = to
        let landed = grid.position(ofCell: to)
        let magnet = exactMagnet(near: landed)
        if let magnet {
            events.append(ScrubFeel.event(.magnetSnap, value: magnets[magnet].value, direction: direction, time: time, speedFraction: u))
        }
        rest(at: magnet.map { magnets[$0].value } ?? landed)
        return finish(events, at: time)
    }

    // MARK: Dragging

    /// A finger lands. Stops any coasting where it is.
    mutating func begin(at time: Double) {
        guard time.isFinite else { return }
        let start: Double
        switch phase {
        case .idle: start = displayValue
        case .dragging: start = lastPosition
        case .coasting: start = coastPosition
        }
        phase = .dragging
        dragOrigin = start
        lastPosition = start
        lastSampleTime = time
        lastSampleRaw = start
        velocity = 0
        coastVelocity = 0
        let outside = start < grid.lower - 1e-9 || start > grid.upper + 1e-9
        boundsArmed = !outside
        settleMagnetStates(at: start)
    }

    /// The finger moved. `translation` is the total movement since the finger landed, in points, along the axis that
    /// increases the value (negate it for an upward drag on a vertical drum). `time` is in seconds, from any steady
    /// clock; the gesture's own timestamps are ideal.
    @discardableResult
    mutating func drag(translation: Double, at time: Double) -> ScrubFeedback {
        guard translation.isFinite, time.isFinite else { return .none }
        if phase != .dragging { begin(at: time) }
        guard grid.lastCell > 0 else { return finish([], at: time) }

        let raw = dragOrigin + translation / configuration.pointsPerStep * referenceStep
        let dt = time - lastSampleTime
        if dt > 1e-4 {
            let limit = referenceStep * 10_000
            let instant = InteractionMath.clamp((raw - lastSampleRaw) / dt, -limit, limit)
            let alpha = 1 - exp(-dt / ScrubModel.smoothing)
            velocity += (instant - velocity) * alpha
            lastSampleTime = time
            lastSampleRaw = raw
        } else if dt < 0 {
            lastSampleTime = time
            lastSampleRaw = raw
        }

        let events = process(position: rubberBand(raw), at: time)
        return finish(events, at: time)
    }

    /// The finger lifted. If it was moving, the value coasts on; otherwise it settles on the nearest step or magnet. An
    /// overscrolled display springs back.
    @discardableResult
    mutating func end(at time: Double) -> ScrubFeedback {
        guard time.isFinite else { return .none }
        guard phase == .dragging else { return finish([], at: time) }
        let position = lastPosition
        let outside = position < grid.lower - 1e-9 || position > grid.upper + 1e-9
        let speed = currentVelocity(at: time)
        let limit = referenceStep * 400
        coastPosition = position
        coastVelocity = outside ? 0 : InteractionMath.clamp(speed, -limit, limit)
        coastClock = time
        coastAccumulator = 0
        coastElapsed = 0
        phase = .coasting
        velocity = coastVelocity
        return finish([], at: time)
    }

    // MARK: Coasting

    /// Runs the coasting physics up to `time` and returns what the view should do. Call it every frame while `phase` is
    /// `.coasting`; elsewhere it only releases a haptic that was held back by the rate limit.
    @discardableResult
    mutating func advance(to time: Double) -> ScrubFeedback {
        guard time.isFinite else { return .none }
        guard phase == .coasting else { return finish([], at: time) }

        let elapsed = min(max(time - coastClock, 0), 1)
        coastClock = max(coastClock, time)
        coastAccumulator += elapsed
        var events: [ScrubHapticEvent] = []
        let h = ScrubModel.coastStep
        while coastAccumulator >= h, phase == .coasting {
            coastAccumulator -= h
            coastElapsed += h
            events.append(contentsOf: coastOnce(step: h, at: time))
        }
        if phase == .coasting { velocity = coastVelocity }
        return finish(events, at: time)
    }

    private mutating func coastOnce(step h: Double, at time: Double) -> [ScrubHapticEvent] {
        let lower = grid.lower
        let upper = grid.upper
        var x = coastPosition
        var v = coastVelocity
        var done = false

        if x < lower || x > upper {
            let bound = x < lower ? lower : upper
            let omega = 22.0
            v += (-omega * omega * (x - bound) - 2 * omega * v) * h
            x += v * h
            if x < lower - overscrollLimit { x = lower - overscrollLimit; v = max(v, 0) }
            if x > upper + overscrollLimit { x = upper + overscrollLimit; v = min(v, 0) }
            // The spring only ever approaches the end, so call it home once it is visually there.
            if abs(x - bound) < 1e-3 * referenceStep, abs(v) < 1e-2 * referenceStep {
                x = bound
                v = 0
            }
        } else if abs(v) > 1.5 * referenceStep, !(abs(v) < 8 * referenceStep && inLockZone(x)) {
            v *= exp(-configuration.friction * h)
            x += v * h
        } else {
            let target = restingValue(near: x)
            let omega = 30.0
            v += (-omega * omega * (x - target) - 2 * omega * v) * h
            x += v * h
            if abs(x - target) < 1e-3 * referenceStep, abs(v) < 1e-2 * referenceStep {
                x = target
                v = 0
                done = true
            }
        }
        if coastElapsed > 10 {
            x = restingValue(near: InteractionMath.clamp(x, lower, upper))
            v = 0
            done = true
        }

        coastPosition = x
        coastVelocity = v
        velocity = v
        let events = process(position: x, at: time)
        if done {
            phase = .idle
            velocity = 0
            coastVelocity = 0
            rest(at: value)
        }
        return events
    }

    // MARK: Core update

    /// Takes the next position of the (rubber-banded) control and works out everything that changed: magnet locks and
    /// snaps, the display value, the step cell with hysteresis, the overscroll and any haptic worth playing.
    private mutating func process(position: Double, at time: Double) -> [ScrubHapticEvent] {
        let previous = lastPosition
        lastPosition = position
        guard grid.lastCell > 0 else {
            value = grid.lower
            displayValue = grid.lower
            overscroll = 0
            return []
        }

        let direction = position >= previous ? 1 : -1
        let u = ScrubFeel.speedFraction(velocity: currentVelocity(at: time), step: referenceStep, fastStepsPerSecond: configuration.fastStepsPerSecond)
        var events: [ScrubHapticEvent] = []

        // Magnets: fire a snap when the path from the last position touches an armed magnet's lock zone.
        let low = min(previous, position)
        let high = max(previous, position)
        var snap: ScrubHapticEvent?
        for index in magnets.indices where armed[index] && !bypassed[index] {
            let magnet = magnets[index]
            guard inRange(low) || inRange(high) else { continue }
            if high >= magnet.value - magnet.radius, low <= magnet.value + magnet.radius {
                armed[index] = false
                snap = ScrubFeel.event(.magnetSnap, value: magnet.value, direction: direction, time: time, speedFraction: u)
            }
        }
        if let snap { events.append(snap) }

        lockedMagnet = nil
        if inRange(position) {
            for index in magnets.indices where !bypassed[index] {
                let magnet = magnets[index]
                if abs(position - magnet.value) <= magnet.radius { lockedMagnet = index }
            }
        }
        let shown = inRange(position) ? warp(position) : position

        // Step cell, with a gap so a trembling finger can't flip a boundary.
        let enteredFrom = cell
        let above = grid.cell(containing: shown - hysteresis)
        let below = grid.cell(containing: shown + hysteresis)
        if above > cell {
            cell = above
        } else if below < cell {
            cell = below
        }
        if cell != enteredFrom, snap == nil,
           let detent = detentEvent(from: enteredFrom, to: cell, time: time, speedFraction: u),
           !isApproachingMagnet(at: detent.value) {
            events.append(detent)
        }

        // The ends.
        let outside = position < grid.lower - 1e-9 || position > grid.upper + 1e-9
        if outside {
            if boundsArmed {
                boundsArmed = false
                let edge = position < grid.lower ? grid.lower : grid.upper
                events.append(ScrubFeel.event(.boundsHit, value: edge, direction: position < grid.lower ? -1 : 1, time: time, speedFraction: u))
            }
        } else if position >= grid.lower + 0.25 * referenceStep, position <= grid.upper - 0.25 * referenceStep {
            boundsArmed = true
        }

        for index in magnets.indices where abs(position - magnets[index].value) >= magnets[index].releaseRadius {
            armed[index] = true
            bypassed[index] = false
        }

        displayValue = shown
        overscroll = position < grid.lower ? position - grid.lower : (position > grid.upper ? position - grid.upper : 0)
        value = lockedMagnet.map { magnets[$0].value } ?? grid.position(ofCell: cell)
        return events
    }

    /// The tick or major tick for the detents entered going from cell `from` to cell `to`. A burst of cells in one update
    /// is one event, a major one if any of the cells was a major detent.
    private func detentEvent(from: Int, to: Int, time: Double, speedFraction u: Double) -> ScrubHapticEvent? {
        guard from != to else { return nil }
        let every = configuration.detentEvery
        let major = configuration.majorEvery > 0 ? every * configuration.majorEvery : 0
        let rising = to > from
        var tick: Int?
        var heavy: Int?
        if rising {
            let lastTick = (to / every) * every
            if lastTick > from { tick = lastTick }
            if major > 0 {
                let lastMajor = (to / major) * major
                if lastMajor > from { heavy = lastMajor }
            }
        } else {
            let firstTick = ((to + every - 1) / every) * every
            if firstTick <= from - 1 { tick = firstTick }
            if major > 0 {
                let firstMajor = ((to + major - 1) / major) * major
                if firstMajor <= from - 1 { heavy = firstMajor }
            }
        }
        let direction = rising ? 1 : -1
        if let heavy {
            return ScrubFeel.event(.majorTick, value: grid.position(ofCell: heavy), direction: direction, time: time, speedFraction: u)
        }
        if let tick {
            return ScrubFeel.event(.tick, value: grid.position(ofCell: tick), direction: direction, time: time, speedFraction: u)
        }
        return nil
    }

    // MARK: Output

    /// Applies the haptic rate limit and attaches the blur and digit levels for the current speed.
    private mutating func finish(_ candidates: [ScrubHapticEvent], at time: Double) -> ScrubFeedback {
        let u = ScrubFeel.speedFraction(velocity: currentVelocity(at: time), step: referenceStep, fastStepsPerSecond: configuration.fastStepsPerSecond)
        return ScrubFeedback(
            events: release(candidates, at: time),
            motionBlurRadius: ScrubFeel.motionBlurRadius(speedFraction: u, maxRadius: configuration.maxBlurRadius),
            digitTransition: ScrubFeel.digitTransition(speedFraction: u)
        )
    }

    /// Picks the most important candidate and lets it through if the budget allows; otherwise holds it for up to a
    /// tenth of a second. Ticks need a full interval since the last event, snaps and bounds hits half of one.
    private mutating func release(_ candidates: [ScrubHapticEvent], at time: Double) -> [ScrubHapticEvent] {
        var best: ScrubHapticEvent?
        for candidate in candidates where best == nil || candidate.kind >= (best?.kind ?? .tick) {
            best = candidate
        }
        if let held = pending {
            if time - held.time > 0.1 {
                pending = nil
            } else if best == nil || held.kind > (best?.kind ?? .tick) {
                best = held
            }
        }
        guard let event = best else { return [] }

        if let last = lastEventTime, time < last { lastEventTime = time }
        let interval = 1 / configuration.maxEventsPerSecond
        let required = event.kind <= .majorTick ? interval : interval / 2
        if let last = lastEventTime, time - last < required - 1e-9 {
            pending = event
            return []
        }
        lastEventTime = time
        pending = nil
        return [event]
    }

    /// The finger's speed now: the smoothed estimate, fading away if the finger has paused without lifting.
    private func currentVelocity(at time: Double) -> Double {
        switch phase {
        case .idle:
            return 0
        case .coasting:
            return coastVelocity
        case .dragging:
            let quiet = max(0, time - lastSampleTime - ScrubModel.staleAfter)
            return velocity * exp(-quiet / ScrubModel.staleFade)
        }
    }

    // MARK: Position maths

    private func inRange(_ x: Double) -> Bool {
        x >= grid.lower && x <= grid.upper
    }

    /// The display position for a control position inside the range: unchanged away from magnets, held still in a
    /// magnet's lock zone, and eased between the two so there is no jump.
    private func warp(_ x: Double) -> Double {
        for index in magnets.indices where !bypassed[index] {
            let magnet = magnets[index]
            let offset = x - magnet.value
            let distance = abs(offset)
            if distance >= magnet.releaseRadius { continue }
            if distance <= magnet.radius { return magnet.value }
            let t = (distance - magnet.radius) / (magnet.releaseRadius - magnet.radius)
            return magnet.value + offset * InteractionMath.smoothstep(0, 1, t)
        }
        return x
    }

    /// Past an end the display stretches like a rubber band: full speed at first, then more and more resistance,
    /// never beyond `overscrollLimit`.
    private func rubberBand(_ raw: Double) -> Double {
        let resistance = configuration.resistance
        if raw < grid.lower {
            return grid.lower - InteractionMath.softLimit((grid.lower - raw) * resistance, limit: overscrollLimit)
        }
        if raw > grid.upper {
            return grid.upper + InteractionMath.softLimit((raw - grid.upper) * resistance, limit: overscrollLimit)
        }
        return raw
    }

    private func exactMagnet(near x: Double) -> Int? {
        let tolerance = referenceStep * 1e-6
        return magnets.indices.first { abs(magnets[$0].value - x) <= tolerance }
    }

    private func inLockZone(_ x: Double) -> Bool {
        for index in magnets.indices where !bypassed[index] && abs(x - magnets[index].value) <= magnets[index].radius {
            return true
        }
        return false
    }

    /// True when `detent` sits on a magnet that is about to snap, so the snap is that moment's haptic, not a tick as well.
    private func isApproachingMagnet(at detent: Double) -> Bool {
        for index in magnets.indices where armed[index] && !bypassed[index] && abs(magnets[index].value - detent) < referenceStep * 0.5 {
            return true
        }
        return false
    }

    /// Where a settling position comes to rest: a magnet whose release radius it is inside, otherwise the nearest step.
    private func restingValue(near x: Double) -> Double {
        let clamped = InteractionMath.clamp(x, grid.lower, grid.upper)
        let step = grid.position(ofCell: grid.cell(containing: clamped))
        for index in magnets.indices where !bypassed[index] {
            let magnet = magnets[index]
            if abs(clamped - magnet.value) < magnet.releaseRadius || abs(step - magnet.value) < magnet.releaseRadius {
                return magnet.value
            }
        }
        return step
    }

    /// Records a resting position and the magnet states that go with it: arms the magnets the position is clear of,
    /// locks onto one it sits exactly on, and bypasses one it merely sits inside, so the display never jumps.
    private mutating func rest(at position: Double) {
        value = position
        displayValue = position
        overscroll = 0
        lastPosition = position
        settleMagnetStates(at: position)
        lockedMagnet = exactMagnet(near: position)
        cell = grid.cell(containing: position)
    }

    private mutating func settleMagnetStates(at position: Double) {
        let tolerance = referenceStep * 1e-6
        for index in magnets.indices {
            let magnet = magnets[index]
            let distance = abs(position - magnet.value)
            armed[index] = distance >= magnet.releaseRadius
            bypassed[index] = distance < magnet.releaseRadius && distance > tolerance
        }
    }
}
