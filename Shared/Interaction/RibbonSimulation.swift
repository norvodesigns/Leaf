import Foundation

// MARK: - Geometry

/// A point or velocity in the ribbon's unit space: x to the right, y down, the anchor at the origin, and the ribbon's
/// resting length equal to 1. The view multiplies by the length it draws, so the same simulation serves a cover
/// bookmark and a big bookmark beside the page block.
struct RibbonVector: Hashable, Sendable {
    var x: Double
    var y: Double

    static let zero = RibbonVector(x: 0, y: 0)

    var length: Double { (x * x + y * y).squareRoot() }
    var isFinite: Bool { x.isFinite && y.isFinite }

    static func + (lhs: RibbonVector, rhs: RibbonVector) -> RibbonVector {
        RibbonVector(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: RibbonVector, rhs: RibbonVector) -> RibbonVector {
        RibbonVector(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: RibbonVector, rhs: Double) -> RibbonVector {
        RibbonVector(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}

// MARK: - Configuration

/// What the ribbon does when nobody is touching it.
enum RibbonIdleStyle: Sendable {
    /// Perfectly still: the simulation sleeps as soon as it settles.
    case still
    /// A faint breathing for a few seconds after anything wakes it, then it settles and sleeps. The default: the
    /// bookmark looks alive when a cover appears, and costs nothing a moment later.
    case breathesThenSleeps
    /// Breathes forever and never sleeps. For a hero bookmark on a screen that is already redrawing.
    case alwaysBreathing
}

/// Every tunable of the ribbon. The defaults are a soft satin ribbon about the size of a bookmark; the lengths are in
/// ribbon-lengths and the times in seconds.
struct RibbonConfiguration: Sendable, Equatable {
    /// Points in the chain, anchor included. Limited to 6...8: fewer looks like a hinge, more costs without showing.
    var pointCount = 7
    /// Physics step. Rendering rate never changes behaviour because frames are cut into steps of this size.
    var fixedStep = 1.0 / 120.0
    /// Longest frame the simulation will catch up on. A longer pause (backgrounding) is dropped, not replayed.
    var maxFrameTime = 0.25
    /// Rounds of distance constraints per step (each round sweeps down and back up the chain).
    var constraintIterations = 6
    /// Gravity in ribbon-lengths per second squared.
    var gravity = 12.0
    /// Velocity lost per second, as a rate. Higher settles faster.
    var damping = 3.2
    /// How hard each bend tries to straighten (0 limp ... 0.5 stiff).
    var bendStiffness = 0.06
    /// How hard the clamped top end holds the ribbon vertical, which gives the gentle cantilever curve under tilt.
    var rootStiffness = 0.35
    /// No point ever moves faster than this, whatever impulse arrives.
    var maxSpeed = 12.0
    /// The most the ribbon will swing from straight down, in radians, however far the phone tilts.
    var maxTilt = 70.0 * Double.pi / 180
    /// Below this top speed the ribbon counts as calm.
    var sleepSpeed = 0.02
    /// How long it must stay calm before it sleeps.
    var sleepDelay = 0.4
    var idle: RibbonIdleStyle = .breathesThenSleeps
    /// Peak sideways acceleration of the idle breathing.
    var breathingForce = 0.35
    /// How fast the breathing noise wanders, in cycles per second.
    var breathingFrequency = 0.3
    /// How long breathing lasts after a wake, for `.breathesThenSleeps`.
    var breathingLinger = 5.0
    /// How far past its length a dragged ribbon can stretch, as a fraction of its length, at the very most.
    var stretchLimit = 0.22
    /// How quickly the grabbed point chases the finger, per second.
    var followRate = 30.0
    /// How quickly stretch snaps back after a release, per second.
    var releaseRate = 12.0

    static let standard = RibbonConfiguration()

    /// The same settings forced into ranges where the simulation is stable, so a bad value is a soft ribbon, not a crash.
    var sanitized: RibbonConfiguration {
        func safe(_ value: Double, _ low: Double, _ high: Double, _ fallback: Double) -> Double {
            InteractionMath.clamp(InteractionMath.finite(value, fallback: fallback), low, high)
        }
        var c = self
        c.pointCount = min(max(pointCount, 6), 8)
        c.fixedStep = safe(fixedStep, 1.0 / 480, 1.0 / 30, 1.0 / 120)
        c.maxFrameTime = safe(maxFrameTime, 1.0 / 60, 1, 0.25)
        c.constraintIterations = min(max(constraintIterations, 1), 24)
        c.gravity = safe(gravity, 0, 60, 12)
        c.damping = safe(damping, 0, 30, 3.2)
        c.bendStiffness = safe(bendStiffness, 0, 0.5, 0.06)
        c.rootStiffness = safe(rootStiffness, 0, 0.9, 0.35)
        c.maxSpeed = safe(maxSpeed, 0.5, 40, 12)
        c.maxTilt = safe(maxTilt, 0, 1.5, 70.0 * Double.pi / 180)
        c.sleepSpeed = safe(sleepSpeed, 0.0005, 1, 0.02)
        c.sleepDelay = safe(sleepDelay, 0.05, 5, 0.4)
        c.breathingForce = safe(breathingForce, 0, 3, 0.35)
        c.breathingFrequency = safe(breathingFrequency, 0.02, 3, 0.3)
        c.breathingLinger = safe(breathingLinger, 0, 60, 5)
        c.stretchLimit = safe(stretchLimit, 0.01, 1, 0.22)
        c.followRate = safe(followRate, 1, 200, 30)
        c.releaseRate = safe(releaseRate, 0.5, 100, 12)
        return c
    }
}

// MARK: - Output

/// Everything the view needs to draw one frame of the ribbon, in unit space.
struct RibbonPose: Sendable, Equatable {
    /// Chain points from the anchor (index 0) to the tail.
    var points: [RibbonVector]
    /// One angle per segment, in radians from straight down. Positive leans toward +x, so a ribbon at rest is all zeros.
    var segmentAngles: [Double]
    /// The swallowtail's angle. It follows the last segment and leads it slightly through the last bend, so the notch
    /// flicks a little beyond the chain like a real cut end.
    var tailAngle: Double
    /// Signed bend at each point, -1...1, positive when the ribbon turns toward +x going down. Slide the satin
    /// highlight with it. Straight is 0.
    var curvature: [Double]
    /// The fastest point, in ribbon-lengths per second. 0 when asleep.
    var speed: Double
    /// How far a dragged ribbon is stretched, 0...1. Drive a continuous haptic's intensity with it.
    var stretch: Double
    /// True once the ribbon has settled and slept. Stop the `TimelineView` when this is true; any input wakes it.
    var isSettled: Bool
    var isDragging: Bool
}

// MARK: - Simulation

/// A cloth-like bookmark ribbon: a verlet chain pinned at the top, with distance constraints, a little bending
/// stiffness, damping and gravity that follows the phone's tilt.
///
/// Why a value type with a fixed step: the view only draws. It feeds inputs (tilt, scroll, taps, a drag), calls
/// `advance(by:)` with each frame's elapsed time and reads `pose`. Frames are cut into fixed 1/120 s steps with an
/// accumulator, so 15, 60 and 120 fps give the same ribbon, and tests are exact. There is no clock, no random source and
/// no platform code: breathing and impulse directions come from a seeded hash.
///
/// Sleeping: once the top speed stays under `sleepSpeed` for `sleepDelay` (and nothing is breathing or being held),
/// `isSettled` turns true and `advance(by:)` returns immediately. Any input calls `wake()`.
struct RibbonSimulation: Sendable {
    let configuration: RibbonConfiguration
    let seed: UInt64

    private(set) var points: [RibbonVector]
    private var previous: [RibbonVector]
    /// Simulated seconds so far. Only the noise reads it.
    private(set) var time = 0.0
    private(set) var isSettled: Bool
    /// The fastest point in ribbon-lengths per second, as of the last step.
    private(set) var speed = 0.0

    private var accumulator = 0.0
    private var gravityDirection = RibbonVector(x: 0, y: 1)
    private var calmTime = 0.0
    private var breathingUntil: Double
    private var grab: Grab?
    private var stretchLevel = 0.0
    private var stretchReach = 1.0
    /// How much longer than its rest length each segment currently is allowed to be (1 or more). Follows the held
    /// point's real reach, not the finger's, so the held point and the anchor are never farther apart than the chain.
    private var stretchScale = 1.0
    private var scrollTarget = 0.0
    private var scrollSmoothed = 0.0
    private var scrollAge = 0.0
    private var impulseCount: UInt64 = 0

    /// The point under the finger, where the finger is, and where the rubber band lets the point go.
    private struct Grab: Sendable {
        var index: Int
        var target: RibbonVector
        var effective: RibbonVector
    }

    init(seed: UInt64 = 1, configuration: RibbonConfiguration = .standard) {
        let c = configuration.sanitized
        self.configuration = c
        self.seed = seed
        let segment = 1 / Double(c.pointCount - 1)
        let rest = (0..<c.pointCount).map { RibbonVector(x: 0, y: Double($0) * segment) }
        points = rest
        previous = rest
        isSettled = c.idle == .still
        breathingUntil = c.idle == .still ? 0 : c.breathingLinger
    }

    // MARK: Reading state

    /// Resting length of one segment.
    var restSegment: Double { 1 / Double(points.count - 1) }

    /// Length the constraints want right now: the rest length, stretched while a drag (or its snap-back) is on.
    var segmentLength: Double { restSegment * stretchScale }

    var isDragging: Bool { grab != nil }

    /// 0...1, rising with how far the finger is past what the ribbon can reach. 0 while the finger is within reach.
    var stretch: Double { stretchLevel }

    /// The worst segment, as a fraction of its wanted length, that is too long or too short. Near 0 when the
    /// constraints hold; a diagnostic for tests.
    var maxConstraintError: Double {
        let wanted = segmentLength
        var worst = 0.0
        for index in 1..<points.count {
            let length = (points[index] - points[index - 1]).length
            worst = max(worst, abs(length - wanted) / wanted)
        }
        return worst
    }

    /// The frame to draw.
    var pose: RibbonPose {
        RibbonSimulation.makePose(
            points: points,
            speed: isSettled ? 0 : speed,
            stretch: stretchLevel,
            isSettled: isSettled,
            isDragging: grab != nil
        )
    }

    // MARK: Inputs

    /// Wakes the simulation and, for the default idle style, restarts the breathing so a woken ribbon looks alive.
    mutating func wake() {
        isSettled = false
        calmTime = 0
        if configuration.idle == .breathesThenSleeps {
            breathingUntil = max(breathingUntil, time + configuration.breathingLinger)
        }
    }

    /// Straightens the ribbon and puts it to sleep (or back to its idle style). For a reused view.
    mutating func reset() {
        self = RibbonSimulation(seed: seed, configuration: configuration)
    }

    /// Feeds the phone's tilt: the in-screen part of the gravity vector (x to the right, y down), about 1 in length when
    /// the phone is upright. A small or zero vector (phone lying flat) blends back to straight down, and the swing is
    /// limited to `maxTilt`, so the ribbon never floats or points at the ceiling. Wakes the ribbon only when the
    /// direction moved enough to matter (about a quarter degree), so sensor noise at 30 Hz doesn't keep it awake.
    mutating func setTilt(_ gravity: RibbonVector) {
        guard gravity.isFinite else { return }
        let magnitude = gravity.length
        let trust = InteractionMath.smoothstep(0.12, 0.45, magnitude)
        let measured = magnitude > 1e-9 ? gravity * (1 / magnitude) : RibbonVector(x: 0, y: 1)
        var blended = RibbonVector(x: measured.x * trust, y: measured.y * trust + (1 - trust))
        let length = blended.length
        blended = length > 1e-9 ? blended * (1 / length) : RibbonVector(x: 0, y: 1)

        var angle = atan2(blended.x, blended.y)
        angle = InteractionMath.clamp(angle, -configuration.maxTilt, configuration.maxTilt)
        let next = RibbonVector(x: sin(angle), y: cos(angle))
        if (next - gravityDirection).length > 0.004 {
            gravityDirection = next
            wake()
        }
    }

    /// Feeds the scroll velocity of whatever carries the ribbon, in ribbon-lengths per second (positive when the content
    /// moves down the screen). Call it on every scroll update; a gap of about a tenth of a second counts as stopped.
    /// The ribbon lags the content, so a hard scroll makes it lift and waft sideways, and stopping makes it bob.
    mutating func scroll(velocity: Double) {
        guard velocity.isFinite else { return }
        let clamped = InteractionMath.clamp(velocity, -20, 20)
        scrollTarget = clamped
        scrollAge = 0
        if abs(clamped) > 1e-4 || abs(scrollSmoothed) > 1e-4 { wake() }
    }

    /// A sideways flick at `depth` (0 the top, 1 the tail), falling off along the chain. `direction` is -1 (left),
    /// 1 (right) or 0 to alternate sides deterministically from the seed. `strength` 1 is a firm tap.
    mutating func tap(atDepth depth: Double = 1, direction: Double = 0, strength: Double = 1) {
        guard strength.isFinite, depth.isFinite, direction.isFinite else { return }
        let power = InteractionMath.clamp(strength, 0, 3)
        let centre = InteractionMath.clamp(depth, 0, 1)
        let side = direction == 0 ? nextSide() : (direction > 0 ? 1.0 : -1.0)
        let sideways = sidewaysAxis()
        let last = Double(points.count - 1)
        for index in 1..<points.count {
            let distance = Double(index) / last - centre
            let falloff = exp(-(distance * distance) / (2 * 0.22 * 0.22))
            addVelocity(at: index, sideways * (side * power * 1.4 * falloff))
        }
        wake()
    }

    /// A ripple down the whole ribbon, for a page turn. `strength` 1 is a clear flutter.
    mutating func flutter(strength: Double = 1) {
        guard strength.isFinite else { return }
        let power = InteractionMath.clamp(strength, 0, 3)
        let phase = InteractionMath.unit(seed, 0xF1_0000 &+ impulseCount) * 2 * Double.pi
        impulseCount &+= 1
        let sideways = sidewaysAxis()
        let last = Double(points.count - 1)
        for index in 1..<points.count {
            let along = Double(index) / last
            let weight = pow(along, 1.2)
            addVelocity(at: index, sideways * (power * 1.1 * weight * sin(Double(index) * 1.3 + phase)))
        }
        wake()
    }

    /// A velocity kick, in ribbon-lengths per second, to the point nearest `depth`. The general form of `tap`.
    mutating func impulse(_ velocity: RibbonVector, atDepth depth: Double = 1) {
        guard velocity.isFinite, depth.isFinite else { return }
        let length = velocity.length
        let capped = length > configuration.maxSpeed ? velocity * (configuration.maxSpeed / length) : velocity
        let index = nearestIndex(forDepth: depth)
        addVelocity(at: index, capped)
        wake()
    }

    // MARK: Dragging

    /// Starts holding the ribbon at `depth` (1 is the tail) with the finger at `target`, in unit space. The point
    /// follows the finger; past the ribbon's reach the finger pulls against a rubber band.
    mutating func beginDrag(atDepth depth: Double = 1, to target: RibbonVector) {
        guard target.isFinite else { return }
        let last = points.count - 1
        let index = min(max(nearestIndex(forDepth: InteractionMath.finite(depth, fallback: 1)), 1), last)
        grab = Grab(index: index, target: .zero, effective: .zero)
        stretchReach = Double(index) * restSegment
        retarget(target)
        wake()
    }

    /// Moves the finger. Ignored when no drag is on or the position isn't a number.
    mutating func updateDrag(to target: RibbonVector) {
        guard grab != nil, target.isFinite else { return }
        retarget(target)
        isSettled = false
        calmTime = 0
    }

    /// Lets go. The point keeps the speed it had, so the ribbon flicks, and the stretch snaps back over a moment.
    mutating func endDrag() {
        guard grab != nil else { return }
        grab = nil
        wake()
    }

    // MARK: Stepping

    /// Advances the simulation by `dt` seconds of wall time. Non-positive or non-finite values do nothing; a frame
    /// longer than `maxFrameTime` is cut to it.
    mutating func advance(by dt: Double) {
        guard dt.isFinite, dt > 0 else { return }
        if isSettled {
            accumulator = 0
            return
        }
        accumulator += min(dt, configuration.maxFrameTime)
        let h = configuration.fixedStep
        while accumulator + 1e-9 >= h {
            accumulator -= h
            step()
            if isSettled {
                accumulator = 0
                break
            }
        }
        accumulator = max(accumulator, 0)
    }

    private mutating func step() {
        let c = configuration
        let h = c.fixedStep
        let count = points.count
        time += h

        let scrollForce = updateScroll(step: h)
        let envelope = breathingEnvelope
        let keep = exp(-c.damping * h)
        let maxMove = c.maxSpeed * h
        let gravityPull = gravityDirection * c.gravity
        let sideways = sidewaysAxis()
        let last = Double(count - 1)
        let held = grab?.index

        for index in 1..<count where index != held {
            var velocity = (points[index] - previous[index]) * keep
            let moved = velocity.length
            if moved > maxMove { velocity = velocity * (maxMove / moved) }

            let along = Double(index) / last
            var acceleration = gravityPull
            acceleration.y += scrollForce.lift
            if scrollForce.waft != 0 {
                acceleration = acceleration + sideways * (scrollForce.waft * pow(along, 1.2))
            }
            if envelope > 0 {
                let noise = InteractionMath.smoothNoise(
                    seed: InteractionMath.mix(seed, UInt64(index)),
                    at: time * c.breathingFrequency + Double(index) * 0.37
                )
                acceleration = acceleration + sideways * (c.breathingForce * envelope * pow(along, 1.5) * noise)
            }

            previous[index] = points[index]
            points[index] = points[index] + velocity + acceleration * (h * h)
        }

        followFinger(step: h)
        if grab == nil {
            let relax = exp(-c.releaseRate * h)
            if stretchLevel > 0 {
                stretchLevel *= relax
                if stretchLevel < 1e-4 { stretchLevel = 0 }
            }
            if stretchScale > 1 {
                stretchScale = 1 + (stretchScale - 1) * relax
                if stretchScale < 1 + 1e-5 { stretchScale = 1 }
            }
        }

        let wanted = segmentLength
        applyBending(segment: wanted)
        solveDistances(segment: wanted)

        if !isHealthy {
            reset()
            return
        }
        trackCalm(step: h)
    }

    /// Smooths the scroll velocity and turns its change into forces on the ribbon: the content accelerating away
    /// drags the ribbon the other way (`lift`), and fast scrolling stirs the air sideways (`waft`).
    private mutating func updateScroll(step h: Double) -> (lift: Double, waft: Double) {
        scrollAge += h
        if scrollAge > 0.12 { scrollTarget = 0 }
        let before = scrollSmoothed
        scrollSmoothed += (scrollTarget - scrollSmoothed) * (1 - exp(-h / 0.06))
        if abs(scrollSmoothed) < 1e-4, scrollTarget == 0 { scrollSmoothed = 0 }
        guard scrollSmoothed != 0 || before != 0 else { return (0, 0) }
        let lift = InteractionMath.clamp(-(scrollSmoothed - before) / h * 0.25, -30, 30)
        let stir = InteractionMath.smoothNoise(seed: InteractionMath.mix(seed, 0x5C), at: time * 1.7)
        let waft = InteractionMath.clamp(scrollSmoothed * 0.5 * stir, -6, 6)
        return (lift, waft)
    }

    /// Moves the grabbed point toward where the rubber band allows it, limited per step so a teleporting finger can't
    /// tear the chain.
    private mutating func followFinger(step h: Double) {
        guard let grab else { return }
        let current = points[grab.index]
        let blend = 1 - exp(-configuration.followRate * h)
        var move = (grab.effective - current) * blend
        let limit = segmentLength * 0.6
        let moved = move.length
        if moved > limit { move = move * (limit / moved) }
        previous[grab.index] = current
        let arrived = current + move
        points[grab.index] = arrived
        stretchScale = max(1, arrived.length / max(stretchReach, 1e-6))
    }

    /// A soft push that keeps each bend from folding: points two apart want to be two segments apart. The first push
    /// uses a virtual point above the anchor, which clamps the ribbon's top end the way stitching would.
    private mutating func applyBending(segment: Double) {
        let c = configuration
        let held = grab?.index
        if c.rootStiffness > 0, held != 1 {
            let virtual = RibbonVector(x: points[0].x, y: points[0].y - segment)
            let delta = points[1] - virtual
            let distance = delta.length
            let target = 2 * segment
            if distance > 1e-9, distance < target {
                points[1] = points[1] + delta * ((target - distance) / distance * c.rootStiffness)
            }
        }
        guard c.bendStiffness > 0 else { return }
        for index in 0..<(points.count - 2) {
            let far = index + 2
            let weightNear = index == 0 || index == held ? 0.0 : 1.0
            let weightFar = far == held ? 0.0 : 1.0
            let total = weightNear + weightFar
            guard total > 0 else { continue }
            let delta = points[far] - points[index]
            let distance = delta.length
            let target = 2 * segment
            guard distance > 1e-9, distance < target else { continue }
            let push = delta * ((target - distance) / distance * c.bendStiffness)
            points[index] = points[index] - push * (weightNear / total)
            points[far] = points[far] + push * (weightFar / total)
        }
    }

    /// Keeps every segment at its length. A free ribbon uses Gauss-Seidel rounds of pairwise constraints, sweeping down and
    /// back up so error doesn't pile up at the tail. A held ribbon is pinned at both ends, which that method converges on
    /// slowly (a nearly taut chain is its worst case), so the part between the anchor and the held point is solved by
    /// reaching back from the finger and forward from the anchor instead (FABRIK): lengths come out exact and only the
    /// held point may slip a hair from the finger.
    private mutating func solveDistances(segment: Double) {
        let count = points.count
        let rounds = configuration.constraintIterations
        guard let held = grab?.index else {
            for _ in 0..<rounds {
                for index in 1..<count {
                    satisfy(index - 1, index, segment: segment, held: nil)
                }
                for index in stride(from: count - 1, to: 0, by: -1) {
                    satisfy(index - 1, index, segment: segment, held: nil)
                }
            }
            return
        }

        reachChain(upTo: held, segment: segment, rounds: rounds * 2)
        guard held < count - 1 else { return }
        // Past the held point the tail swings free. Gauss-Seidel keeps its motion natural; one last pass where each point
        // follows the one before it at exactly one segment makes the lengths exact even under violent drags.
        for _ in 0..<rounds {
            for index in (held + 1)..<count {
                satisfy(index - 1, index, segment: segment, held: held)
            }
            for index in stride(from: count - 1, to: held, by: -1) {
                satisfy(index - 1, index, segment: segment, held: held)
            }
        }
        for index in (held + 1)..<count {
            points[index] = reached(from: points[index - 1], toward: points[index], length: segment)
        }
    }

    private mutating func reachChain(upTo held: Int, segment: Double, rounds: Int) {
        let anchor = points[0]
        let end = points[held]
        for _ in 0..<rounds {
            points[held] = end
            for index in stride(from: held - 1, through: 0, by: -1) {
                points[index] = reached(from: points[index + 1], toward: points[index], length: segment)
            }
            points[0] = anchor
            for index in 1...held {
                points[index] = reached(from: points[index - 1], toward: points[index], length: segment)
            }
        }
    }

    /// The point `length` away from `origin` in the direction of `point`.
    private func reached(from origin: RibbonVector, toward point: RibbonVector, length: Double) -> RibbonVector {
        var direction = point - origin
        var distance = direction.length
        if distance < 1e-9 {
            direction = gravityDirection
            distance = 1
        }
        return origin + direction * (length / distance)
    }

    private mutating func satisfy(_ a: Int, _ b: Int, segment: Double, held: Int?) {
        var delta = points[b] - points[a]
        var distance = delta.length
        if distance < 1e-9 {
            delta = gravityDirection * 1e-6
            distance = 1e-6
        }
        let weightA = a == 0 || a == held ? 0.0 : 1.0
        let weightB = b == held ? 0.0 : 1.0
        let total = weightA + weightB
        guard total > 0 else { return }
        let correction = delta * ((distance - segment) / distance)
        points[a] = points[a] + correction * (weightA / total)
        points[b] = points[b] - correction * (weightB / total)
    }

    private mutating func trackCalm(step h: Double) {
        var fastest = 0.0
        for index in 1..<points.count {
            fastest = max(fastest, (points[index] - previous[index]).length)
        }
        speed = fastest / h

        let idle = grab == nil && speed < configuration.sleepSpeed
        calmTime = idle ? calmTime + h : 0

        let quiet = grab == nil && stretchLevel == 0 && stretchScale == 1 && scrollSmoothed == 0 && scrollTarget == 0
        if quiet, calmTime >= configuration.sleepDelay, breathingEnvelope == 0, configuration.idle != .alwaysBreathing {
            previous = points
            speed = 0
            isSettled = true
        }
    }

    /// False if anything went non-finite or flew far outside the possible reach. Should never happen; the check
    /// exists so one freak input can't poison the ribbon.
    private var isHealthy: Bool {
        for point in points where !point.isFinite || abs(point.x) > 20 || abs(point.y) > 20 { return false }
        return true
    }

    // MARK: Helpers

    private var breathingEnvelope: Double {
        switch configuration.idle {
        case .still:
            return 0
        case .alwaysBreathing:
            return 1
        case .breathesThenSleeps:
            let fade = min(2, configuration.breathingLinger)
            guard fade > 0 else { return 0 }
            return InteractionMath.smoothstep(0, 1, (breathingUntil - time) / fade)
        }
    }

    /// The direction across the hanging ribbon, perpendicular to gravity (so +x when gravity points straight down).
    private func sidewaysAxis() -> RibbonVector {
        RibbonVector(x: gravityDirection.y, y: -gravityDirection.x)
    }

    private mutating func nextSide() -> Double {
        let roll = InteractionMath.unit(seed, 0x7A_0000 &+ impulseCount)
        impulseCount &+= 1
        return roll < 0.5 ? -1 : 1
    }

    private func nearestIndex(forDepth depth: Double) -> Int {
        let clamped = InteractionMath.clamp(InteractionMath.finite(depth, fallback: 1), 0, 1)
        return min(max(Int((clamped * Double(points.count - 1)).rounded()), 0), points.count - 1)
    }

    /// Adds a velocity to a free point. In verlet form velocity is the gap between the last two positions.
    private mutating func addVelocity(at index: Int, _ velocity: RibbonVector) {
        guard index > 0, index < points.count, index != grab?.index, velocity.isFinite else { return }
        let h = configuration.fixedStep
        let length = velocity.length
        let capped = length > configuration.maxSpeed ? velocity * (configuration.maxSpeed / length) : velocity
        previous[index] = previous[index] - capped * h
    }

    /// Sets the finger target, the rubber-banded point the grabbed point may reach, and the stretch amount.
    private mutating func retarget(_ rawTarget: RibbonVector) {
        guard var current = grab else { return }
        let target = RibbonVector(
            x: InteractionMath.clamp(rawTarget.x, -6, 6),
            y: InteractionMath.clamp(rawTarget.y, -6, 6)
        )
        let reachable = Double(current.index) * restSegment
        let distance = target.length
        let limit = configuration.stretchLimit
        if distance > reachable, distance > 0 {
            let level = 1 - exp(-(distance - reachable) / limit)
            let allowed = reachable + limit * level
            current.effective = target * (allowed / distance)
            stretchLevel = level
        } else {
            current.effective = target
            stretchLevel = 0
        }
        current.target = target
        grab = current
    }

    // MARK: Poses

    /// One fixed, gentle resting curve for Reduce Motion: a soft lean to the right that straightens toward the tail.
    /// Segment lengths are exactly the rest length, so it drops into the same drawing code as a live pose.
    static func reducedMotionPose(pointCount: Int = 7) -> RibbonPose {
        let count = min(max(pointCount, 6), 8)
        let segment = 1 / Double(count - 1)
        var points = [RibbonVector.zero]
        for index in 0..<(count - 1) {
            let along = (Double(index) + 0.5) / Double(count - 1)
            let angle = 0.12 * sin(Double.pi * 0.9 * along)
            let last = points[index]
            points.append(RibbonVector(x: last.x + segment * sin(angle), y: last.y + segment * cos(angle)))
        }
        return makePose(points: points, speed: 0, stretch: 0, isSettled: true, isDragging: false)
    }

    fileprivate static func makePose(points: [RibbonVector], speed: Double, stretch: Double, isSettled: Bool, isDragging: Bool) -> RibbonPose {
        let count = points.count
        var angles: [Double] = []
        angles.reserveCapacity(max(count - 1, 0))
        for index in 1..<max(count, 1) {
            let delta = points[index] - points[index - 1]
            angles.append(delta.x == 0 && delta.y == 0 ? 0 : atan2(delta.x, delta.y))
        }

        let segment = count > 1 ? 1 / Double(count - 1) : 1
        var turns: [Double] = []
        turns.reserveCapacity(count)
        for index in 0..<count {
            switch index {
            case 0:
                turns.append(angles.first ?? 0)
            case count - 1:
                turns.append(turns.last ?? 0)
            default:
                turns.append(InteractionMath.angleDifference(angles[index], angles[index - 1]))
            }
        }
        let curvature = turns.map { tanh(($0 / segment) / 6) }

        var tail = angles.last ?? 0
        if angles.count >= 2 {
            let bend = InteractionMath.angleDifference(angles[angles.count - 1], angles[angles.count - 2])
            tail += 0.35 * bend
        }

        return RibbonPose(
            points: points,
            segmentAngles: angles,
            tailAngle: tail,
            curvature: curvature,
            speed: speed,
            stretch: stretch,
            isSettled: isSettled,
            isDragging: isDragging
        )
    }
}
