import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Ribbon simulation

struct RibbonSimulationTests {
    private let upright = RibbonVector(x: 0, y: 1)

    private func isFinite(_ pose: RibbonPose) -> Bool {
        pose.points.allSatisfy(\.isFinite)
            && pose.segmentAngles.allSatisfy(\.isFinite)
            && pose.curvature.allSatisfy(\.isFinite)
            && pose.tailAngle.isFinite && pose.speed.isFinite && pose.stretch.isFinite
    }

    /// Runs frames until the simulation sleeps or `seconds` pass. Returns the seconds it took.
    @discardableResult
    private func settle(_ sim: inout RibbonSimulation, seconds: Double = 15, dt: Double = 1.0 / 60) -> Double {
        var elapsed = 0.0
        while elapsed < seconds, !sim.isSettled {
            sim.advance(by: dt)
            elapsed += dt
        }
        return elapsed
    }

    private func still(seed: UInt64 = 1) -> RibbonSimulation {
        var configuration = RibbonConfiguration.standard
        configuration.idle = .still
        return RibbonSimulation(seed: seed, configuration: configuration)
    }

    private func distance(_ a: RibbonSimulation, _ b: RibbonSimulation) -> Double {
        zip(a.points, b.points).map { ($0 - $1).length }.max() ?? 0
    }

    // MARK: Rest, settling, sleeping

    @Test func aStillRibbonStartsStraightAndAsleep() {
        let sim = still()
        let pose = sim.pose
        #expect(pose.isSettled)
        #expect(pose.speed == 0)
        #expect(pose.points.count == 7)
        #expect(pose.points.first == RibbonVector.zero)
        #expect(pose.segmentAngles.allSatisfy { $0 == 0 })
        #expect(pose.curvature.allSatisfy { abs($0) < 1e-12 })
        #expect(abs(pose.tailAngle) < 1e-12)
        #expect(abs((pose.points.last ?? .zero).y - 1) < 1e-12)
    }

    @Test func settlesAfterAFlutterAndSleeps() {
        var sim = still()
        sim.flutter(strength: 2)
        #expect(!sim.isSettled)
        let seconds = settle(&sim)
        #expect(sim.isSettled, "should sleep within 15 s, took \(seconds)")
        #expect(seconds < 8)
        #expect(sim.pose.speed == 0)
        #expect(sim.points.allSatisfy { abs($0.x) < 0.03 }, "hangs straight again")
        #expect(sim.maxConstraintError < 0.01)
    }

    @Test func aSleepingRibbonIgnoresTime() {
        var sim = still()
        sim.tap()
        settle(&sim)
        let before = sim.points
        sim.advance(by: 5)
        sim.advance(by: 0.016)
        #expect(sim.points == before)
        #expect(sim.isSettled)
    }

    @Test func theDefaultRibbonBreathesFaintlyThenSleeps() {
        var sim = RibbonSimulation(seed: 11)
        #expect(!sim.isSettled, "a fresh ribbon is alive")
        var widest = 0.0
        var elapsed = 0.0
        while elapsed < 20, !sim.isSettled {
            sim.advance(by: 1.0 / 30)
            elapsed += 1.0 / 30
            widest = max(widest, sim.points.map { abs($0.x) }.max() ?? 0)
        }
        #expect(sim.isSettled)
        #expect(widest > 1e-4, "it should visibly breathe")
        #expect(widest < 0.08, "but only faintly, was \(widest)")
        #expect(elapsed > 3, "breathing lasts a few seconds")
    }

    @Test func anAlwaysBreathingRibbonNeverSleeps() {
        var configuration = RibbonConfiguration.standard
        configuration.idle = .alwaysBreathing
        var sim = RibbonSimulation(seed: 5, configuration: configuration)
        var widest = 0.0
        for _ in 0..<(60 * 40) {
            sim.advance(by: 1.0 / 60)
            widest = max(widest, sim.points.map { abs($0.x) }.max() ?? 0)
        }
        #expect(!sim.isSettled)
        #expect(widest > 1e-3)
        #expect(widest < 0.1)
        #expect(sim.maxConstraintError < 0.02)
    }

    @Test(arguments: ["tap", "flutter", "scroll", "tilt", "impulse", "drag", "wake"])
    func anyInputWakesASleepingRibbon(input: String) {
        var sim = still()
        #expect(sim.isSettled)
        switch input {
        case "tap": sim.tap()
        case "flutter": sim.flutter()
        case "scroll": sim.scroll(velocity: 3)
        case "tilt": sim.setTilt(RibbonVector(x: 0.6, y: 0.8))
        case "impulse": sim.impulse(RibbonVector(x: 1, y: 0))
        case "drag": sim.beginDrag(to: RibbonVector(x: 0.2, y: 0.8))
        default: sim.wake()
        }
        #expect(!sim.isSettled, "\(input) should wake the ribbon")
        sim.advance(by: 0.05)
        #expect(!sim.isSettled)
    }

    @Test func sensorNoiseInTheTiltDoesNotKeepItAwake() {
        var sim = still()
        sim.setTilt(RibbonVector(x: 0.3, y: 0.95))
        settle(&sim)
        #expect(sim.isSettled)
        // Wobbles of a tenth of a degree, like a phone resting on a table.
        for index in 0..<30 {
            let wobble = 0.0015 * (index % 2 == 0 ? 1 : -1)
            sim.setTilt(RibbonVector(x: 0.3 + wobble, y: 0.95))
        }
        #expect(sim.isSettled)
    }

    // MARK: Tilt

    @Test func tiltBendsTowardTheGravitySide() {
        var right = still()
        right.setTilt(RibbonVector(x: 0.5, y: 0.85))
        settle(&right)
        var left = still()
        left.setTilt(RibbonVector(x: -0.5, y: 0.85))
        settle(&left)

        let rightTail = right.points.last ?? .zero
        let leftTail = left.points.last ?? .zero
        #expect(rightTail.x > 0.15, "tail swings right, was \(rightTail.x)")
        #expect(leftTail.x < -0.15, "tail swings left, was \(leftTail.x)")
        #expect(right.points.allSatisfy { $0.x >= -1e-9 })
        #expect(left.points.allSatisfy { $0.x <= 1e-9 })
        #expect(right.pose.tailAngle > 0.2)
        #expect(left.pose.tailAngle < -0.2)
        #expect(right.pose.curvature.contains { $0 > 0.02 }, "bends, not just leans")
    }

    @Test func tiltIsAMirrorImage() {
        var right = still()
        right.setTilt(RibbonVector(x: 0.6, y: 0.7))
        right.flutter(strength: 0)
        var left = still()
        left.setTilt(RibbonVector(x: -0.6, y: 0.7))
        for _ in 0..<240 {
            right.advance(by: 1.0 / 60)
            left.advance(by: 1.0 / 60)
        }
        for (a, b) in zip(right.points, left.points) {
            #expect(abs(a.x + b.x) < 1e-9)
            #expect(abs(a.y - b.y) < 1e-9)
        }
    }

    @Test func moreTiltMeansMoreLean() {
        var tails: [Double] = []
        for tilt in [0.15, 0.35, 0.6, 0.85] {
            var sim = still()
            sim.setTilt(RibbonVector(x: tilt, y: (1 - tilt * tilt).squareRoot()))
            settle(&sim)
            tails.append((sim.points.last ?? .zero).x)
        }
        #expect(tails == tails.sorted())
        #expect(Set(tails).count == tails.count)
    }

    @Test func aFlatPhoneLetsTheRibbonHangStraight() {
        var sim = still()
        sim.setTilt(RibbonVector(x: 0.6, y: 0.7))
        settle(&sim)
        sim.setTilt(RibbonVector(x: 0.001, y: -0.002))
        settle(&sim)
        #expect(sim.points.allSatisfy { abs($0.x) < 0.03 })
    }

    @Test func theSwingNeverPassesTheTiltLimit() {
        var sim = still()
        sim.setTilt(RibbonVector(x: 1, y: -0.2))
        settle(&sim)
        let tail = sim.points.last ?? .zero
        let angle = atan2(tail.x, tail.y)
        #expect(angle <= sim.configuration.maxTilt + 0.05)
        #expect(tail.y > 0.2, "still hangs below the anchor")
    }

    // MARK: Constraints and robustness

    @Test(arguments: [1.0, 0.6, 0.3])
    func constraintsHoldThroughViolentDragsAndHugeFrames(grabDepth: Double) {
        var rng = SeededGenerator(seed: 7)
        var sim = RibbonSimulation(seed: 3)
        sim.beginDrag(atDepth: grabDepth, to: RibbonVector(x: 0, y: 1))
        var worst = 0.0
        for frame in 0..<900 {
            let target = RibbonVector(x: (rng.unit() - 0.5) * 14, y: (rng.unit() - 0.5) * 14)
            sim.updateDrag(to: target)
            let dt = frame % 9 == 0 ? 0.6 : rng.unit() * 0.05
            sim.advance(by: dt)
            worst = max(worst, sim.maxConstraintError)
            #expect(isFinite(sim.pose))
        }
        #expect(worst < 1e-6, "worst segment error \(worst) grabbing at depth \(grabDepth)")
    }

    @Test func constraintsHoldAfterHugeImpulsesAndReleaseSnapsBack() {
        var sim = RibbonSimulation(seed: 9)
        for index in 0..<20 {
            sim.impulse(RibbonVector(x: 1e9 * (index.isMultiple(of: 2) ? 1 : -1), y: -1e9), atDepth: Double(index % 5) / 4)
            sim.tap(strength: 1e6)
            sim.flutter(strength: 1e12)
            sim.scroll(velocity: 1e12)
            sim.advance(by: 0.03)
            #expect(isFinite(sim.pose))
        }
        var worst = 0.0
        for _ in 0..<600 {
            sim.advance(by: 1.0 / 60)
            worst = max(worst, sim.maxConstraintError)
            #expect(sim.points.allSatisfy { $0.length <= 1.01 }, "no point can be farther than the ribbon is long")
        }
        #expect(worst < 0.05, "worst segment error \(worst)")
    }

    @Test func noNaNOrInfinityForAnyInput() {
        let nasty: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300, 0, -0.0, 1e-300, Double.greatestFiniteMagnitude]
        var sim = RibbonSimulation(seed: 2)
        for value in nasty {
            sim.advance(by: value)
            sim.scroll(velocity: value)
            sim.tap(atDepth: value, direction: value, strength: value)
            sim.flutter(strength: value)
            sim.impulse(RibbonVector(x: value, y: value), atDepth: value)
            sim.setTilt(RibbonVector(x: value, y: value))
            sim.beginDrag(atDepth: value, to: RibbonVector(x: value, y: -value))
            sim.updateDrag(to: RibbonVector(x: -value, y: value))
            sim.advance(by: 0.1)
            #expect(isFinite(sim.pose), "after \(value)")
            sim.endDrag()
            sim.advance(by: 0.1)
            #expect(isFinite(sim.pose), "after releasing \(value)")
        }
        #expect(sim.maxConstraintError.isFinite)
        settle(&sim, seconds: 30)
        #expect(isFinite(sim.pose))
    }

    @Test func zeroAndNegativeFramesChangeNothing() {
        var sim = RibbonSimulation(seed: 4)
        sim.tap()
        sim.advance(by: 0.2)
        let before = sim.points
        let clock = sim.time
        sim.advance(by: 0)
        sim.advance(by: -1)
        sim.advance(by: .nan)
        sim.advance(by: .infinity)
        #expect(sim.points == before)
        #expect(sim.time == clock)
    }

    @Test func absurdConfigurationIsTamed() {
        var configuration = RibbonConfiguration.standard
        configuration.pointCount = 400
        configuration.fixedStep = -3
        configuration.gravity = .nan
        configuration.damping = .infinity
        configuration.constraintIterations = -9
        configuration.stretchLimit = 0
        var sim = RibbonSimulation(seed: 1, configuration: configuration)
        #expect(sim.points.count == 8)
        sim.flutter()
        for _ in 0..<300 { sim.advance(by: 0.016) }
        #expect(isFinite(sim.pose))

        configuration.pointCount = 1
        #expect(RibbonSimulation(seed: 1, configuration: configuration).points.count == 6)
    }

    // MARK: Frame rate and determinism

    @Test func renderingRateDoesNotChangeBehaviour() {
        func run(fps: Double) -> RibbonSimulation {
            var sim = still(seed: 8)
            sim.setTilt(RibbonVector(x: 0.4, y: 0.9))
            sim.tap(atDepth: 0.8, direction: 1, strength: 1.5)
            sim.flutter()
            let frames = Int(fps * 3)
            for _ in 0..<frames { sim.advance(by: 1 / fps) }
            return sim
        }
        let at60 = run(fps: 60)
        let at120 = run(fps: 120)
        let at30 = run(fps: 30)
        let at15 = run(fps: 15)
        #expect(distance(at60, at120) < 2e-3, "60 vs 120: \(distance(at60, at120))")
        #expect(distance(at60, at30) < 2e-3, "60 vs 30: \(distance(at60, at30))")
        #expect(distance(at60, at15) < 2e-3, "60 vs 15: \(distance(at60, at15))")
    }

    @Test func sameSeedSameRibbonDifferentSeedDifferentBreathing() {
        func run(seed: UInt64) -> RibbonSimulation {
            var sim = RibbonSimulation(seed: seed)
            for _ in 0..<(60 * 2) { sim.advance(by: 1.0 / 60) }
            return sim
        }
        let a = run(seed: 21)
        let b = run(seed: 21)
        let c = run(seed: 22)
        #expect(a.points == b.points)
        #expect(a.pose == b.pose)
        #expect(distance(a, c) > 1e-5, "seeds should breathe differently")

        var left = RibbonSimulation(seed: 21)
        var right = RibbonSimulation(seed: 21)
        left.tap(); right.tap()
        for _ in 0..<100 { left.advance(by: 0.02); right.advance(by: 0.02) }
        #expect(left.points == right.points, "alternating tap sides come from the seed")
    }

    // MARK: Dragging

    @Test func dragStretchGrowsWithDistance() {
        var sim = RibbonSimulation(seed: 1)
        sim.beginDrag(to: RibbonVector(x: 0, y: 0.5))
        var previous = -1.0
        var strictlyRising = 0
        for distance in stride(from: 0.0, through: 6.0, by: 0.05) {
            sim.updateDrag(to: RibbonVector(x: 0, y: distance))
            let stretch = sim.stretch
            #expect(stretch >= previous, "stretch fell at distance \(distance)")
            #expect(stretch >= 0 && stretch <= 1)
            if distance <= 1 { #expect(stretch == 0, "no stretch within reach at \(distance)") }
            if stretch > previous && distance > 1 { strictlyRising += 1 }
            previous = stretch
        }
        #expect(strictlyRising > 60)
        #expect(previous > 0.99)
        #expect(sim.pose.stretch == sim.stretch)
    }

    @Test func dragStretchIsTheSameInAnyDirection() {
        var a = RibbonSimulation(seed: 1)
        var b = RibbonSimulation(seed: 1)
        a.beginDrag(to: RibbonVector(x: 0, y: 1.4))
        b.beginDrag(to: RibbonVector(x: 1.4 * 0.6, y: 1.4 * 0.8))
        #expect(abs(a.stretch - b.stretch) < 1e-12)
        #expect(a.stretch > 0)
    }

    @Test func theTailFollowsAFingerWithinReach() {
        var sim = RibbonSimulation(seed: 1)
        let target = RibbonVector(x: 0.3, y: 0.8)
        sim.beginDrag(to: target)
        #expect(sim.isDragging)
        #expect(sim.stretch == 0)
        for _ in 0..<60 { sim.advance(by: 1.0 / 60) }
        let tail = sim.points.last ?? .zero
        #expect((tail - target).length < 0.02, "tail at \(tail)")
        #expect(!sim.isSettled, "never sleeps while held")
    }

    @Test func aStretchedRibbonReachesOnlyALittlePastItsLength() {
        var sim = RibbonSimulation(seed: 1)
        sim.beginDrag(to: RibbonVector(x: 0, y: 5))
        for _ in 0..<120 { sim.advance(by: 1.0 / 60) }
        let tail = sim.points.last ?? .zero
        let limit = 1 + sim.configuration.stretchLimit
        #expect(tail.length > 1.1, "it does stretch: \(tail.length)")
        #expect(tail.length <= limit + 0.02, "but only to the rubber band's limit: \(tail.length)")
        #expect(sim.maxConstraintError < 0.03)
    }

    @Test func releasingSnapsBackAndSettles() {
        var sim = RibbonSimulation(seed: 6)
        sim.beginDrag(to: RibbonVector(x: 0.2, y: 3))
        for _ in 0..<60 { sim.advance(by: 1.0 / 60) }
        #expect(sim.stretch > 0.5)
        sim.endDrag()
        #expect(!sim.isDragging)
        for _ in 0..<60 { sim.advance(by: 1.0 / 60) }
        #expect(sim.stretch < 0.01)
        #expect(sim.maxConstraintError < 0.03)
        settle(&sim, seconds: 20)
        #expect(sim.isSettled)
        #expect(sim.stretch == 0)
    }

    @Test func draggingAMiddlePointLeavesTheTailFree() {
        var sim = still()
        sim.beginDrag(atDepth: 0.5, to: RibbonVector(x: 0.4, y: 0.4))
        for _ in 0..<120 { sim.advance(by: 1.0 / 60) }
        let held = sim.points[3]
        #expect((held - RibbonVector(x: 0.4, y: 0.4)).length < 0.02)
        #expect(sim.points.last?.y ?? 0 > 0.4)
    }

    @Test func updatingWithoutADragIsIgnored() {
        var sim = still()
        sim.updateDrag(to: RibbonVector(x: 1, y: 1))
        sim.endDrag()
        #expect(sim.isSettled)
        #expect(!sim.isDragging)
    }

    // MARK: Scroll

    @Test func scrollingMakesItLiftAndWaftThenItSettles() {
        var sim = still(seed: 3)
        var widest = 0.0
        var lowest = 1.0
        for _ in 0..<60 {
            sim.scroll(velocity: 6)
            sim.advance(by: 1.0 / 60)
            widest = max(widest, sim.points.map { abs($0.x) }.max() ?? 0)
            lowest = min(lowest, sim.points.last?.y ?? 1)
        }
        #expect(widest > 1e-3 || lowest < 0.999, "the scroll should disturb the ribbon")
        settle(&sim)
        #expect(sim.isSettled)
    }

    // MARK: Pose

    @Test func reducedMotionIsOneFixedGentlePose() {
        let pose = RibbonSimulation.reducedMotionPose()
        #expect(pose == RibbonSimulation.reducedMotionPose())
        #expect(pose.isSettled && !pose.isDragging)
        #expect(pose.speed == 0 && pose.stretch == 0)
        #expect(pose.points.count == 7)
        #expect(isFinite(pose))
        let segment = 1.0 / 6
        for index in 1..<pose.points.count {
            #expect(abs((pose.points[index] - pose.points[index - 1]).length - segment) < 1e-9)
        }
        #expect(pose.segmentAngles.allSatisfy { abs($0) < 0.2 }, "gentle")
        #expect(pose.segmentAngles.contains { abs($0) > 0.01 }, "but not dead straight")
        #expect(RibbonSimulation.reducedMotionPose(pointCount: 3).points.count == 6)
        #expect(RibbonSimulation.reducedMotionPose(pointCount: 30).points.count == 8)
    }

    @Test func poseAnglesCurvatureAndTailAreConsistent() {
        var sim = still()
        sim.setTilt(RibbonVector(x: 0.7, y: 0.7))
        settle(&sim)
        let pose = sim.pose
        #expect(pose.segmentAngles.count == pose.points.count - 1)
        #expect(pose.curvature.count == pose.points.count)
        for (index, angle) in pose.segmentAngles.enumerated() {
            let delta = pose.points[index + 1] - pose.points[index]
            #expect(abs(angle - atan2(delta.x, delta.y)) < 1e-12)
        }
        #expect(pose.curvature.allSatisfy { $0 >= -1 && $0 <= 1 })
        // The swallowtail leans at least as far as the last segment when the ribbon is still curling that way.
        #expect(abs(pose.tailAngle - (pose.segmentAngles.last ?? 0)) < 0.3)

        let straight = still().pose
        #expect(straight.curvature.allSatisfy { $0 == 0 })
    }

    @Test func curvatureSignFollowsTheBend() {
        var right = still()
        right.setTilt(RibbonVector(x: 0.7, y: 0.7))
        settle(&right)
        var left = still()
        left.setTilt(RibbonVector(x: -0.7, y: 0.7))
        settle(&left)
        #expect(right.pose.curvature.reduce(0, +) > 0)
        #expect(left.pose.curvature.reduce(0, +) < 0)
    }

    @Test func resetReturnsToTheStart() {
        var sim = RibbonSimulation(seed: 5)
        sim.beginDrag(to: RibbonVector(x: 1, y: 1))
        sim.advance(by: 0.5)
        sim.reset()
        #expect(sim.points == RibbonSimulation(seed: 5).points)
        #expect(!sim.isDragging)
        #expect(sim.stretch == 0)
    }
}

// MARK: - Depth mapping

struct RibbonDepthMappingTests {
    private let books = [1, 2, 7, 10, 96, 180, 250, 312, 640, 1000, 1488, 5000]
    private let curves: [RibbonDepthCurve] = [.linear, .expanded(strength: 0), .expanded(strength: 0.5), .expanded(strength: 1), .automatic, .expanded(strength: .nan)]

    @Test func everyPageRoundTripsThroughDepth() {
        for pages in books {
            for curve in curves {
                let map = RibbonDepthMapping(pages: pages, curve: curve)
                for page in 0...pages {
                    let depth = map.depth(forPage: page)
                    #expect(depth >= 0 && depth <= 1)
                    #expect(map.page(forDepth: depth) == page, "\(pages) pages, \(curve), page \(page)")
                }
            }
        }
    }

    @Test func depthToPageIsMonotonicAndBounded() {
        for pages in books {
            for curve in curves {
                let map = RibbonDepthMapping(pages: pages, curve: curve)
                var previous = -1
                for step in 0...2000 {
                    let page = map.page(forDepth: Double(step) / 2000)
                    #expect(page >= previous)
                    #expect(page >= 0 && page <= pages)
                    previous = page
                }
                #expect(map.page(forDepth: 0) == 0)
                #expect(map.page(forDepth: 1) == pages)
            }
        }
    }

    @Test func pageToDepthIsMonotonic() {
        let map = RibbonDepthMapping(pages: 900)
        var previous = -1.0
        for page in 0...900 {
            let depth = map.depth(forPage: page)
            #expect(depth >= previous)
            previous = depth
        }
    }

    @Test func outOfRangeInputsAreClamped() {
        let map = RibbonDepthMapping(pages: 400)
        #expect(map.page(forDepth: -3) == 0)
        #expect(map.page(forDepth: 7) == 400)
        #expect(map.page(forDepth: .infinity) == 400)
        #expect(map.page(forDepth: -.infinity) == 0)
        #expect(map.page(forDepth: .nan) == 0)
        #expect(map.depth(forPage: -10) == 0)
        #expect(map.depth(forPage: 99_999) == 1)
        #expect(map.depth(forPage: Int.max) == 1)
        #expect(map.depth(forPage: Int.min) == 0)
    }

    @Test func anUnknownLengthMapsToTheTop() {
        for pages in [0, -5] {
            let map = RibbonDepthMapping(pages: pages)
            #expect(map.pages == 0)
            #expect(map.page(forDepth: 0.7) == 0)
            #expect(map.depth(forPage: 12) == 0)
            #expect(map.pagesPerDepth(at: 0.5) == 0)
            #expect(map.snappedPage(forDepth: 0.5, depthVelocity: 3) == 0)
            #expect(map.markerDepths(everyPages: 50).isEmpty)
        }
    }

    @Test func longBooksGiveTheFirstPagesMoreRoom() {
        let linear = RibbonDepthMapping(pages: 1000, curve: .linear)
        let automatic = RibbonDepthMapping(pages: 1000, curve: .automatic)
        #expect(linear.depth(forPage: 30) < 0.031)
        #expect(automatic.depth(forPage: 30) > linear.depth(forPage: 30) * 2.5)
        #expect(automatic.exponent > 1.3)
        // Still reaches the same ends.
        #expect(automatic.depth(forPage: 0) == 0)
        #expect(automatic.depth(forPage: 1000) == 1)
    }

    @Test func shortBooksStayLinearOnAutomatic() {
        let map = RibbonDepthMapping(pages: 220)
        #expect(map.exponent == 1)
        #expect(abs(map.depth(forPage: 110) - 0.5) < 1e-12)
    }

    @Test func strongerExpansionGivesTheTopMoreRoom() {
        let weak = RibbonDepthMapping(pages: 800, curve: .expanded(strength: 0.2))
        let strong = RibbonDepthMapping(pages: 800, curve: .expanded(strength: 1))
        #expect(strong.depth(forPage: 40) > weak.depth(forPage: 40))
        #expect(strong.exponent <= 1.9 + 1e-12)
        #expect(RibbonDepthMapping(pages: 800, curve: .expanded(strength: 50)).exponent <= 1.9 + 1e-12)
        #expect(RibbonDepthMapping(pages: 800, curve: .expanded(strength: -50)).exponent == 1)
    }

    @Test func localSlopeMatchesTheCurve() {
        let map = RibbonDepthMapping(pages: 1200, curve: .expanded(strength: 1))
        // Pages per block of depth grows toward the bottom of an expanded block.
        #expect(map.pagesPerDepth(at: 0.1) < map.pagesPerDepth(at: 0.5))
        #expect(map.pagesPerDepth(at: 0.5) < map.pagesPerDepth(at: 1))
        let linear = RibbonDepthMapping(pages: 300, curve: .linear)
        #expect(abs(linear.pagesPerDepth(at: 0.4) - 300) < 1e-9)
    }

    // MARK: Snapping

    @Test func snapStepFollowsDragSpeed() {
        let steps = [0, 10, 19.9, 20, 50, 79, 80, 150, 199, 200, 400, 499, 500, 5000].map {
            RibbonPageSnap.step(forPagesPerSecond: $0, pages: 2000)
        }
        #expect(steps == [1, 1, 1, 5, 5, 5, 10, 10, 10, 25, 25, 25, 50, 50])
        #expect(steps == steps.sorted())
        #expect(RibbonPageSnap.step(forPagesPerSecond: .nan, pages: 500) == 1)
        #expect(RibbonPageSnap.step(forPagesPerSecond: -3, pages: 500) == 1)
        #expect(RibbonPageSnap.step(forPagesPerSecond: .infinity, pages: 5000) == 50)
    }

    @Test func shortBooksNeverSnapCoarsely() {
        #expect(RibbonPageSnap.step(forPagesPerSecond: 9999, pages: 120) == 10)
        #expect(RibbonPageSnap.step(forPagesPerSecond: 9999, pages: 60) == 5)
        #expect(RibbonPageSnap.step(forPagesPerSecond: 9999, pages: 12) == 1)
        #expect(RibbonPageSnap.step(forPagesPerSecond: 9999, pages: 0) == 1)
    }

    @Test func snappingLandsOnMultiplesOrTheEnds() {
        for pages in [37, 120, 312, 999] {
            for step in RibbonPageSnap.steps {
                var previous = -1
                for page in 0...pages {
                    let snapped = RibbonPageSnap.snap(page, step: step, pages: pages)
                    #expect(snapped >= 0 && snapped <= pages)
                    #expect(snapped % step == 0 || snapped == pages, "\(page) -> \(snapped) step \(step)")
                    #expect(abs(snapped - page) <= step, "never moves more than a step")
                    #expect(snapped >= previous, "monotonic")
                    previous = snapped
                }
                #expect(RibbonPageSnap.snap(0, step: step, pages: pages) == 0)
                #expect(RibbonPageSnap.snap(pages, step: step, pages: pages) == pages)
            }
        }
    }

    @Test func theLastPageIsAlwaysReachableWhenFlicking() {
        // 312 pages, 25 at a time: 300 is a multiple, but page 311 is closer to the end.
        #expect(RibbonPageSnap.snap(311, step: 25, pages: 312) == 312)
        #expect(RibbonPageSnap.snap(305, step: 25, pages: 312) == 300)
        #expect(RibbonPageSnap.snap(4, step: 25, pages: 312) == 0)
        #expect(RibbonPageSnap.snap(-40, step: 25, pages: 312) == 0)
        #expect(RibbonPageSnap.snap(9000, step: 25, pages: 312) == 312)
        #expect(RibbonPageSnap.snap(10, step: 1, pages: 312) == 10)
        #expect(RibbonPageSnap.snap(10, step: 0, pages: 312) == 10)
    }

    @Test func slowDragsLandOnSinglePagesAndFastOnesRound() {
        let map = RibbonDepthMapping(pages: 1000, curve: .linear)
        let slow = map.snappedPage(forDepth: 0.4137, depthVelocity: 0.001)
        #expect(slow == map.page(forDepth: 0.4137))
        let fast = map.snappedPage(forDepth: 0.4137, depthVelocity: 2)
        #expect(fast % 50 == 0 || fast == 1000)
        let medium = map.snappedPage(forDepth: 0.4137, depthVelocity: 0.15)
        #expect(medium % 5 == 0 || medium % 10 == 0 || medium % 25 == 0)
        #expect(map.snappedPage(forDepth: 0.4137, depthVelocity: -2) == fast, "speed, not direction")
        #expect(map.snappedPage(forDepth: 0.4137, depthVelocity: .nan) == slow)
    }

    // MARK: The stylised edge

    @Test func pageBlockThicknessGrowsWithPagesAndIsBounded() {
        var previous = -1.0
        for pages in [0, 1, 40, 120, 300, 600, 1000, 1500, 3000, 100_000] {
            let thickness = RibbonDepthMapping.pageBlockThickness(forPages: pages)
            #expect(thickness >= 0 && thickness <= 1)
            #expect(thickness >= previous)
            previous = thickness
        }
        #expect(RibbonDepthMapping.pageBlockThickness(forPages: 0) == 0)
        #expect(RibbonDepthMapping.pageBlockThickness(forPages: -50) == 0)
        #expect(RibbonDepthMapping.pageBlockThickness(forPages: 1500) > 0.999)
        let thin = RibbonDepthMapping.pageBlockThickness(forPages: 150, from: 6, to: 40)
        let thick = RibbonDepthMapping.pageBlockThickness(forPages: 1100, from: 6, to: 40)
        #expect(thin >= 6 && thick <= 40 && thin < thick)
        #expect(RibbonDepthMapping.pageBlockThickness(forPages: 1100) < 4 * RibbonDepthMapping.pageBlockThickness(forPages: 300),
                "a 1,100-page book is not four times as thick")
    }

    @Test func edgeLinesAndMarkersStayTidy() {
        for pages in [0, 20, 200, 600, 1500, 9000] {
            let lines = RibbonDepthMapping.edgeLineCount(forPages: pages)
            #expect(lines >= 3 && lines <= 12)
        }
        #expect(RibbonDepthMapping.edgeLineCount(forPages: 100) <= RibbonDepthMapping.edgeLineCount(forPages: 1000))

        for pages in [30, 180, 312, 800, 2400, 20_000] {
            let map = RibbonDepthMapping(pages: pages)
            let step = RibbonDepthMapping.markerStep(forPages: pages)
            let depths = map.markerDepths(everyPages: step)
            #expect(depths == depths.sorted())
            #expect(depths.allSatisfy { $0 > 0 && $0 < 1 })
            #expect(depths.count <= 40)
            #expect(pages / step <= 12 || step == 1000)
        }
        let dense = RibbonDepthMapping(pages: 5000).markerDepths(everyPages: 1, limit: 40)
        #expect(dense.count <= 40 && !dense.isEmpty)
        #expect(RibbonDepthMapping(pages: 5000).markerDepths(everyPages: 0).isEmpty)
        #expect(RibbonDepthMapping(pages: 50).markerDepths(everyPages: 100).isEmpty)
    }
}

// MARK: - Scrub model

struct ScrubModelTests {
    /// A model with the haptic rate limit effectively off, so a test about crossings sees every crossing.
    private func model(range: ClosedRange<Double> = 0...100, step: Double = 1, value: Double = 0, configure: (inout ScrubConfiguration) -> Void = { _ in }) -> ScrubModel {
        var configuration = ScrubConfiguration(range: range, step: step)
        configuration.maxEventsPerSecond = 1000
        configure(&configuration)
        return ScrubModel(configuration: configuration, value: value)
    }

    /// Drags between two translations in small increments (default a sixteenth of a step) and returns every event.
    private func sweep(_ model: inout ScrubModel, from start: Double, to end: Double, increment: Double = 0.5, interval: Double = 0.016, clock: inout Double) -> [ScrubHapticEvent] {
        var events: [ScrubHapticEvent] = []
        let count = max(1, Int(((end - start) / increment).magnitude.rounded(.up)))
        let rising = end >= start
        for index in 1...count {
            clock += interval
            let travelled = Double(index) * increment
            let translation = rising ? min(start + travelled, end) : max(start - travelled, end)
            events += model.drag(translation: translation, at: clock).events
        }
        return events
    }

    private func values(_ events: [ScrubHapticEvent], _ kinds: Set<ScrubHapticKind>) -> [Double] {
        events.filter { kinds.contains($0.kind) }.map(\.value)
    }

    // MARK: Detents

    @Test func detentsFireExactlyOncePerCrossingInBothDirections() {
        var scrub = model { $0.majorEvery = 10 }
        var clock = 0.0
        scrub.begin(at: clock)
        let up = sweep(&scrub, from: 0, to: 800, clock: &clock)
        #expect(up.map(\.value) == (1...100).map(Double.init))
        #expect(up.allSatisfy { $0.direction == 1 })
        #expect(values(up, [.majorTick]) == stride(from: 10.0, through: 100, by: 10).map { $0 })
        #expect(up.filter { $0.kind == .tick }.count == 90)
        #expect(scrub.value == 100)

        let down = sweep(&scrub, from: 800, to: 0, clock: &clock)
        #expect(down.map(\.value) == (0...99).reversed().map(Double.init))
        #expect(down.allSatisfy { $0.direction == -1 })
        #expect(values(down, [.majorTick]) == stride(from: 90.0, through: 0, by: -10).map { $0 })
        #expect(scrub.value == 0)
    }

    @Test func detentsEveryNStepsAndMajorsEveryMDetents() {
        var scrub = model { $0.detentEvery = 5; $0.majorEvery = 2 }
        var clock = 0.0
        let up = sweep(&scrub, from: 0, to: 800, clock: &clock)
        #expect(up.map(\.value) == stride(from: 5.0, through: 100, by: 5).map { $0 })
        #expect(values(up, [.majorTick]) == stride(from: 10.0, through: 100, by: 10).map { $0 })
        #expect(values(up, [.tick]) == stride(from: 5.0, through: 95, by: 10).map { $0 })
        #expect(scrub.value == 100, "the value still moves by single steps")
    }

    @Test func noMajorTicksWhenMajorEveryIsZero() {
        var scrub = model { $0.majorEvery = 0 }
        var clock = 0.0
        let up = sweep(&scrub, from: 0, to: 400, clock: &clock)
        #expect(up.allSatisfy { $0.kind == .tick })
        #expect(up.count == 50)
    }

    @Test func majorTicksHitHarderThanTicks() {
        var scrub = model { $0.majorEvery = 5 }
        var clock = 0.0
        let up = sweep(&scrub, from: 0, to: 120, clock: &clock)
        let major = up.first { $0.kind == .majorTick }
        let tick = up.first { $0.kind == .tick }
        #expect((major?.intensity ?? 0) > (tick?.intensity ?? 1))
    }

    @Test func aTremblingFingerOnABoundaryMakesNoEvents() {
        func chatter(hysteresis: Double) -> Int {
            var scrub = model { $0.hysteresis = hysteresis }
            var clock = 0.0
            scrub.begin(at: clock)
            _ = sweep(&scrub, from: 0, to: 84, clock: &clock)   // 10.5 steps: exactly on the boundary
            var count = 0
            for index in 0..<200 {
                clock += 0.016
                let wobble = (index.isMultiple(of: 2) ? 1.0 : -1.0) * 0.1 * 8
                count += scrub.drag(translation: 84 + wobble, at: clock).events.count
            }
            return count
        }
        #expect(chatter(hysteresis: 0.12) == 0)
        #expect(chatter(hysteresis: 0) > 100, "without the gap it would buzz")
    }

    @Test func valueSnapsToTheStepGridWithTheRangeOffset() {
        var scrub = model(range: 7...47, step: 2.5)
        var clock = 0.0
        scrub.begin(at: clock)
        var seen = Set<Double>()
        for index in 1...200 {
            clock += 0.016
            scrub.drag(translation: Double(index) * 1.3, at: clock)
            seen.insert(scrub.value)
            #expect(scrub.value >= 7 && scrub.value <= 47)
            let steps = (scrub.value - 7) / 2.5
            #expect(abs(steps - steps.rounded()) < 1e-9, "\(scrub.value) is off the grid")
        }
        #expect(seen.count > 10)
    }

    @Test func aRangeThatIsNotAWholeNumberOfStepsStillReachesItsTop() {
        var scrub = model(range: 0...10.3, step: 1)
        var clock = 0.0
        scrub.begin(at: clock)
        _ = sweep(&scrub, from: 0, to: 82.4, clock: &clock)
        #expect(scrub.value == 10.3)
        #expect(abs(scrub.displayValue - 10.3) < 1e-6)
    }

    // MARK: Magnets

    @Test func aMagnetSnapsOnceAndHoldsTheValueStill() {
        var scrub = model(range: 0...60) { $0.magnets = [ScrubMagnet(value: 30, radius: 0.5)] }
        var clock = 0.0
        scrub.begin(at: clock)
        var events: [ScrubHapticEvent] = []
        var shown: [Double] = []
        for translation in stride(from: 0.0, through: 8 * 45, by: 0.5) {
            clock += 0.016
            events += scrub.drag(translation: translation, at: clock).events
            shown.append(scrub.displayValue)
            if abs(translation / 8 - 30) <= 0.5 {
                #expect(scrub.displayValue == 30, "locked at \(translation / 8)")
                #expect(scrub.value == 30)
            }
        }
        #expect(events.filter { $0.kind == .magnetSnap }.count == 1)
        #expect(events.first { $0.kind == .magnetSnap }?.value == 30)
        #expect(values(events, [.tick, .majorTick]).filter { $0 == 30 }.isEmpty, "the snap is that moment's haptic")
        #expect(Set(values(events, [.tick, .majorTick])) == Set((1...45).map(Double.init)).subtracting([30]))
        #expect(shown == shown.sorted(), "the pull never runs backwards")
        // Leaving a magnet the display catches up on the finger, at up to about three times its speed, but never jumps.
        for (a, b) in zip(shown, shown.dropFirst()) { #expect(b - a <= 0.0625 * 3 + 1e-9, "no jump into or out of the magnet") }
    }

    @Test func aMagnetSnapsAgainComingBackDown() {
        var scrub = model(range: 0...60) { $0.magnets = [ScrubMagnet(value: 30, radius: 0.5)] }
        var clock = 0.0
        scrub.begin(at: clock)
        let up = sweep(&scrub, from: 0, to: 8 * 45, clock: &clock)
        let down = sweep(&scrub, from: 8 * 45, to: 0, clock: &clock)
        #expect(up.filter { $0.kind == .magnetSnap }.count == 1)
        let snaps = down.filter { $0.kind == .magnetSnap }
        #expect(snaps.count == 1)
        #expect(snaps.first?.direction == -1)
        #expect(Set(values(down, [.tick, .majorTick])) == Set((0...44).map(Double.init)).subtracting([30]))
    }

    @Test func releaseHysteresisStopsTheSnapChattering() {
        var scrub = model(range: 0...60) { $0.magnets = [ScrubMagnet(value: 30, radius: 0.5, releaseRadius: 1.0)] }
        var clock = 0.0
        scrub.begin(at: clock)
        _ = sweep(&scrub, from: 0, to: 8 * 30.3, clock: &clock)
        #expect(scrub.value == 30)

        // Wander between 29.1 and 30.9: out of the lock zone, inside the release radius.
        var wander: [ScrubHapticEvent] = []
        for index in 0..<120 {
            clock += 0.016
            let raw = 30 + 0.9 * sin(Double(index) * 0.7)
            wander += scrub.drag(translation: raw * 8, at: clock).events
        }
        #expect(wander.filter { $0.kind == .magnetSnap }.isEmpty)

        // Leave the release radius altogether, come back: one snap.
        var again: [ScrubHapticEvent] = []
        clock += 0.016
        again += scrub.drag(translation: 31.6 * 8, at: clock).events
        again += sweep(&scrub, from: 31.6 * 8, to: 30.2 * 8, clock: &clock)
        #expect(again.filter { $0.kind == .magnetSnap }.count == 1)
        #expect(scrub.value == 30)
    }

    @Test func startingOnAMagnetDoesNotSnapUntilYouHaveLeftAndReturned() {
        var scrub = model(range: 0...60, value: 30) { $0.magnets = [ScrubMagnet(value: 30, radius: 0.5, releaseRadius: 1.0)] }
        #expect(scrub.value == 30)
        var clock = 0.0
        scrub.begin(at: clock)
        var events = sweep(&scrub, from: 0, to: 8 * 0.4, clock: &clock)
        #expect(events.isEmpty)
        events = sweep(&scrub, from: 8 * 0.4, to: 8 * 1.5, clock: &clock)
        #expect(events.filter { $0.kind == .magnetSnap }.isEmpty)
        #expect(scrub.value != 30)
        events = sweep(&scrub, from: 8 * 1.5, to: 8 * 0.2, clock: &clock)
        #expect(events.filter { $0.kind == .magnetSnap }.count == 1)
        #expect(scrub.value == 30)
    }

    @Test func aFastPassStillGetsItsSnap() {
        var scrub = model(range: 0...60) { $0.magnets = [ScrubMagnet(value: 30, radius: 0.4)] }
        scrub.begin(at: 0)
        scrub.drag(translation: 8 * 20, at: 0.016)
        let jump = scrub.drag(translation: 8 * 40, at: 0.032)
        #expect(jump.events.map(\.kind) == [.magnetSnap], "one frame crossed the whole magnet")
    }

    @Test func magnetsAreKeptApartInsideTheRange() {
        let scrub = model(range: 0...100) {
            $0.magnets = [
                ScrubMagnet(value: 10, radius: 5), ScrubMagnet(value: 12, radius: 5),
                ScrubMagnet(value: 12, radius: 1), ScrubMagnet(value: 500, radius: 1),
                ScrubMagnet(value: .nan, radius: 1), ScrubMagnet(value: 50, radius: .infinity),
                ScrubMagnet(value: 70, radius: -3, releaseRadius: 2),
            ]
        }
        let magnets = scrub.magnets
        #expect(magnets.map(\.value) == [10, 12, 70])
        for (a, b) in zip(magnets, magnets.dropFirst()) {
            #expect(a.value + a.releaseRadius <= b.value - b.releaseRadius + 1e-9, "zones must not overlap")
        }
        #expect(magnets.allSatisfy { $0.radius <= $0.releaseRadius && $0.radius >= 0 })
    }

    // MARK: Event storms and feel

    @Test func fastScrubbingNeverStormsTheHaptics() {
        var scrub = model(range: 0...1_000_000) { $0.maxEventsPerSecond = 30 }
        var events: [ScrubHapticEvent] = []
        scrub.begin(at: 0)
        for frame in 1...360 {
            let clock = Double(frame) / 120
            let feedback = scrub.drag(translation: Double(frame) * 3333, at: clock)
            #expect(feedback.events.count <= 1)
            events += feedback.events
        }
        #expect(events.count <= 91, "30 a second for 3 s, got \(events.count)")
        #expect(events.count > 60, "but it should still be buzzing, got \(events.count)")
        let times = events.map(\.time)
        for (index, start) in times.enumerated() {
            #expect(times[index...].prefix { $0 < start + 1 - 1e-6 }.count <= 30)
        }
    }

    @Test func oneHugeJumpIsOneEvent() {
        var scrub = model(range: 0...1_000_000)
        scrub.begin(at: 0)
        let feedback = scrub.drag(translation: 8 * 500_000, at: 0.016)
        #expect(feedback.events.count == 1)
        #expect(feedback.events.first?.kind == .majorTick)
    }

    @Test func fasterScrubbingIsDenserAndLighter() {
        func run(stepsPerSecond: Double) -> (count: Int, intensity: Double) {
            var scrub = model(range: 0...10_000) { $0.maxEventsPerSecond = 60 }
            var events: [ScrubHapticEvent] = []
            scrub.begin(at: 0)
            for frame in 1...240 {
                let clock = Double(frame) / 60
                events += scrub.drag(translation: stepsPerSecond * 8 * clock, at: clock).events
            }
            let ticks = events.filter { $0.kind == .tick }
            let average = ticks.map(\.intensity).reduce(0, +) / Double(max(ticks.count, 1))
            return (events.count, average)
        }
        let slow = run(stepsPerSecond: 4)
        let medium = run(stepsPerSecond: 12)
        let fast = run(stepsPerSecond: 30)
        #expect(slow.count < medium.count && medium.count < fast.count)
        #expect(slow.intensity > medium.intensity && medium.intensity > fast.intensity)
    }

    @Test func hapticCharacterFollowsSpeed() {
        var previous: [ScrubHapticKind: (Double, Double)] = [:]
        for index in 0...20 {
            let speed = Double(index) / 20
            for kind in [ScrubHapticKind.tick, .majorTick, .magnetSnap, .boundsHit] {
                let feel = ScrubFeel.character(of: kind, speedFraction: speed)
                #expect(feel.intensity >= 0 && feel.intensity <= 1)
                #expect(feel.sharpness >= 0 && feel.sharpness <= 1)
                if let before = previous[kind] {
                    if kind == .boundsHit {
                        #expect(feel.intensity >= before.0, "a harder hit for a faster impact")
                    } else {
                        #expect(feel.intensity <= before.0, "\(kind) gets lighter with speed")
                        #expect(feel.sharpness <= before.1)
                    }
                }
                previous[kind] = (feel.intensity, feel.sharpness)
            }
        }
        #expect(ScrubFeel.character(of: .tick, speedFraction: 0).intensity < ScrubFeel.character(of: .majorTick, speedFraction: 0).intensity)
    }

    @Test func motionBlurIsClampedToSixPointsForAnyVelocity() {
        var previous = -1.0
        for velocity in [0, 0.5, 1, 5, 20, 40, 100, 1e3, 1e6, 1e12, Double.infinity] {
            let fraction = ScrubFeel.speedFraction(velocity: velocity, step: 1, fastStepsPerSecond: 40)
            let blur = ScrubFeel.motionBlurRadius(speedFraction: fraction, maxRadius: 100)
            #expect(blur >= 0 && blur <= 6, "\(velocity) -> \(blur)")
            #expect(blur >= previous, "blur never falls as speed rises")
            let digits = ScrubFeel.digitTransition(speedFraction: fraction)
            #expect(digits >= 0 && digits <= 1)
            previous = blur
        }
        for velocity in [-Double.infinity, -1e9, -3, .nan] {
            let fraction = ScrubFeel.speedFraction(velocity: velocity, step: 1, fastStepsPerSecond: 40)
            let blur = ScrubFeel.motionBlurRadius(speedFraction: fraction, maxRadius: 6)
            #expect(blur >= 0 && blur <= 6)
        }
        #expect(ScrubFeel.motionBlurRadius(speedFraction: 1, maxRadius: 6) == 6)
        #expect(ScrubFeel.motionBlurRadius(speedFraction: 0, maxRadius: 6) == 0)
        #expect(ScrubFeel.motionBlurRadius(speedFraction: 1, maxRadius: 2) == 2)
        #expect(ScrubFeel.motionBlurRadius(speedFraction: 1, maxRadius: -2) == 0)
        #expect(ScrubFeel.speedFraction(velocity: .nan, step: 1, fastStepsPerSecond: 40) == 0)
        #expect(ScrubFeel.speedFraction(velocity: .infinity, step: 1, fastStepsPerSecond: 40) == 1)
    }

    @Test func slowDragsAreCrispAndFastDragsAreBlurred() {
        func blur(stepsPerSecond: Double) -> (blur: Double, digits: Double) {
            var scrub = model(range: 0...100_000) { $0.maxBlurRadius = 100 }
            scrub.begin(at: 0)
            var last = ScrubFeedback.none
            for frame in 1...90 {
                let clock = Double(frame) / 60
                last = scrub.drag(translation: stepsPerSecond * 8 * clock, at: clock)
            }
            return (last.motionBlurRadius, last.digitTransition)
        }
        let slow = blur(stepsPerSecond: 1)
        let fast = blur(stepsPerSecond: 400)
        #expect(slow.blur == 0)
        #expect(fast.blur == 6)
        #expect(slow.digits < fast.digits)
        #expect(fast.digits == 1)
    }

    @Test func aPausedFingerFadesTheBlurAway() {
        var scrub = model(range: 0...100_000)
        scrub.begin(at: 0)
        var last = ScrubFeedback.none
        for frame in 1...60 {
            let clock = Double(frame) / 60
            last = scrub.drag(translation: 8 * 300 * clock, at: clock)
        }
        #expect(last.motionBlurRadius > 5)
        let later = scrub.advance(to: 2)
        #expect(later.motionBlurRadius < 0.01)
    }

    // MARK: Ends

    @Test func pullingPastAnEndStretchesLikeARubberBand() {
        var scrub = model()
        var clock = 0.0
        scrub.begin(at: clock)
        var events = sweep(&scrub, from: 0, to: 800, clock: &clock)
        #expect(scrub.overscroll == 0)
        events = []
        var stretches: [Double] = []
        for translation in stride(from: 800.0, through: 1200, by: 8) {
            clock += 0.016
            events += scrub.drag(translation: translation, at: clock).events
            stretches.append(scrub.overscroll)
        }
        #expect(stretches == stretches.sorted(), "the further you pull the more it stretches")
        #expect(stretches.last ?? 0 > 1.2)
        #expect(stretches.last ?? 99 <= 2 + 1e-9, "never past the limit")
        #expect((stretches.last ?? 0) < 50 * 0.55, "and much less than the finger travelled")
        #expect(scrub.value == 100, "the value stays at the end")
        #expect(scrub.displayValue > 100)
        #expect(events.filter { $0.kind == .boundsHit }.count == 1)
        #expect(events.first { $0.kind == .boundsHit }?.value == 100)
        #expect(events.first { $0.kind == .boundsHit }?.direction == 1)
    }

    @Test func theLowerEndStretchesToo() {
        var scrub = model(value: 0)
        scrub.begin(at: 0)
        let feedback = scrub.drag(translation: -8 * 30, at: 0.016)
        #expect(feedback.events.map(\.kind) == [.boundsHit])
        #expect(feedback.events.first?.direction == -1)
        #expect(scrub.overscroll < 0 && scrub.overscroll >= -2 - 1e-9)
        #expect(scrub.value == 0)
        #expect(scrub.displayValue < 0)
    }

    @Test func aHugeDragStaysFiniteAndWithinTheLimit() {
        var scrub = model()
        scrub.begin(at: 0)
        for translation in [1e9, -1e12, 1e300, -1e300, 8e8] {
            let feedback = scrub.drag(translation: translation, at: 0.1)
            #expect(scrub.overscroll.isFinite && abs(scrub.overscroll) <= 2 + 1e-9)
            #expect(scrub.displayValue.isFinite && scrub.value.isFinite)
            #expect(feedback.motionBlurRadius <= 6)
            #expect(feedback.events.count <= 1)
        }
    }

    @Test func theEndHitsOnceUntilYouComeBackInside() {
        var scrub = model()
        var clock = 0.0
        scrub.begin(at: clock)
        _ = sweep(&scrub, from: 0, to: 800, clock: &clock)
        let first = sweep(&scrub, from: 800, to: 900, clock: &clock)
        let wobble = sweep(&scrub, from: 900, to: 840, clock: &clock)
        #expect(first.filter { $0.kind == .boundsHit }.count == 1)
        #expect(wobble.filter { $0.kind == .boundsHit }.isEmpty)
        _ = sweep(&scrub, from: 840, to: 780, clock: &clock)
        let second = sweep(&scrub, from: 780, to: 900, clock: &clock)
        #expect(second.filter { $0.kind == .boundsHit }.count == 1)
    }

    @Test func releasingPastAnEndSpringsBackWithoutOvershoot() {
        var scrub = model()
        var clock = 0.0
        scrub.begin(at: clock)
        _ = sweep(&scrub, from: 0, to: 1000, clock: &clock)
        let stretched = scrub.overscroll
        #expect(stretched > 1)
        scrub.end(at: clock)
        #expect(scrub.phase == .coasting)
        var previous = stretched
        var frames = 0
        while scrub.phase == .coasting, frames < 600 {
            frames += 1
            clock += 1.0 / 60
            scrub.advance(to: clock)
            #expect(scrub.overscroll <= previous + 1e-9, "returns monotonically")
            #expect(scrub.overscroll >= -1e-9, "never crosses to the other side")
            previous = scrub.overscroll
        }
        #expect(scrub.phase == .idle)
        #expect(Double(frames) / 60 < 2)
        #expect(scrub.value == 100 && scrub.displayValue == 100 && scrub.overscroll == 0)
    }

    @Test func aHardFlingIntoAnEndBouncesOnceAndStopsThere() {
        var scrub = model(range: 0...50)
        var clock = 0.0
        scrub.begin(at: clock)
        for frame in 1...20 {
            clock = Double(frame) / 60
            scrub.drag(translation: 8 * 400 * clock, at: clock)
            if scrub.overscroll > 0 { break }
        }
        scrub.end(at: clock)
        var events: [ScrubHapticEvent] = []
        var furthest = 0.0
        var frames = 0
        while scrub.phase == .coasting, frames < 900 {
            frames += 1
            clock += 1.0 / 60
            events += scrub.advance(to: clock).events
            furthest = max(furthest, scrub.overscroll)
        }
        #expect(scrub.phase == .idle)
        #expect(furthest <= 2 + 1e-9)
        #expect(scrub.value == 50 && scrub.overscroll == 0)
        #expect(events.filter { $0.kind == .boundsHit }.count <= 1)
    }

    // MARK: Momentum

    private func flick(range: ClosedRange<Double> = 0...1000, stepsPerSecond: Double = 30, frames: Int = 30, configure: (inout ScrubConfiguration) -> Void = { _ in }) -> (model: ScrubModel, clock: Double) {
        var scrub = model(range: range, configure: configure)
        var clock = 0.0
        scrub.begin(at: clock)
        for frame in 1...frames {
            clock = Double(frame) / 60
            scrub.drag(translation: stepsPerSecond * 8 * clock, at: clock)
        }
        return (scrub, clock)
    }

    @Test func aFlickCoastsDeceleratesAndSettlesOnAStep() {
        var (scrub, clock) = flick()
        let released = scrub.value
        scrub.end(at: clock)
        #expect(scrub.phase == .coasting)
        #expect(scrub.isActive)

        var travel: [Double] = []
        var last = scrub.displayValue
        let began = clock
        while scrub.phase == .coasting, clock - began < 10 {
            clock += 1.0 / 60
            scrub.advance(to: clock)
            travel.append(scrub.displayValue - last)
            last = scrub.displayValue
        }
        #expect(scrub.phase == .idle)
        #expect(clock - began < 6, "stops in \(clock - began) s")
        #expect(scrub.value > released + 5, "it carried on: \(released) -> \(scrub.value)")
        #expect(scrub.value == scrub.value.rounded())
        #expect(scrub.displayValue == scrub.value)
        #expect(scrub.velocity == 0)

        let window = max(travel.count / 4, 1)
        let sums = (0..<4).map { travel[($0 * window)..<min(($0 + 1) * window, travel.count)].reduce(0, +) }
        #expect(sums[0] > sums[1] && sums[1] > sums[2], "slows down: \(sums)")
    }

    @Test func aFlickInTheOtherDirectionGoesTheOtherWay() {
        var (scrub, clock) = flick(stepsPerSecond: -30)
        let released = scrub.displayValue
        #expect(released < 0 + 1e-9 || released >= 0)
        var forward = model(range: -500...500)
        forward.begin(at: 0)
        for frame in 1...30 {
            let t = Double(frame) / 60
            forward.drag(translation: -8 * 30 * t, at: t)
        }
        let before = forward.displayValue
        forward.end(at: 0.5)
        var t = 0.5
        for _ in 0..<600 where forward.phase == .coasting { t += 1.0 / 60; forward.advance(to: t) }
        #expect(forward.value < before - 5)
        _ = (scrub.value, clock)
        scrub.end(at: clock)
    }

    @Test func coastingDoesNotDependOnTheFrameRate() {
        func coast(fps: Double) -> (final: Double, mid: Double) {
            var (scrub, clock) = flick()
            scrub.end(at: clock)
            let start = clock
            var mid = 0.0
            let frames = Int(fps * 6)
            for frame in 1...frames {
                let time = start + Double(frame) / fps
                scrub.advance(to: time)
                if frame == Int(fps * 0.6) { mid = scrub.displayValue }
            }
            return (scrub.value, mid)
        }
        let at60 = coast(fps: 60)
        let at120 = coast(fps: 120)
        let at30 = coast(fps: 30)
        #expect(at60.final == at120.final && at60.final == at30.final)
        #expect(abs(at60.mid - at120.mid) < 0.05)
        #expect(abs(at60.mid - at30.mid) < 0.05)
    }

    @Test func releasingWithoutSpeedSettlesOnTheNearestStep() {
        func rest(at raw: Double, expect expected: Double) {
            var scrub = model()
            scrub.begin(at: 0)
            var clock = 0.0
            for translation in stride(from: 0.0, through: raw * 8, by: 0.5) {
                clock += 0.01
                scrub.drag(translation: translation, at: clock)
            }
            clock += 0.6
            scrub.end(at: clock)
            #expect(scrub.phase == .coasting)
            var frames = 0
            while scrub.phase == .coasting, frames < 600 {
                frames += 1
                clock += 1.0 / 60
                scrub.advance(to: clock)
            }
            #expect(scrub.phase == .idle)
            #expect(scrub.value == expected, "released at \(raw)")
            #expect(scrub.displayValue == expected)
        }
        rest(at: 10.4, expect: 10)
        rest(at: 10.6, expect: 11)
        rest(at: 99.9, expect: 100)
    }

    @Test func aSlowFlickDyingNearAMagnetRestsOnIt() {
        var scrub = model(range: 0...100) { $0.magnets = [ScrubMagnet(value: 50, radius: 0.5, releaseRadius: 1.0)] }
        scrub.begin(at: 0)
        var clock = 0.0
        for translation in stride(from: 0.0, through: 49.2 * 8, by: 1.0) {
            clock += 0.005
            scrub.drag(translation: translation, at: clock)
        }
        clock += 0.5
        scrub.end(at: clock)
        var events: [ScrubHapticEvent] = []
        var frames = 0
        while scrub.phase == .coasting, frames < 600 {
            frames += 1
            clock += 1.0 / 60
            events += scrub.advance(to: clock).events
        }
        #expect(scrub.value == 50)
        #expect(scrub.displayValue == 50)
        #expect(events.contains { $0.kind == .magnetSnap })
    }

    @Test func touchingACoastingScrubTakesOverFromWhereItIs() {
        var (scrub, clock) = flick()
        scrub.end(at: clock)
        for _ in 0..<20 { clock += 1.0 / 60; scrub.advance(to: clock) }
        let there = scrub.displayValue
        scrub.begin(at: clock)
        #expect(scrub.phase == .dragging)
        #expect(scrub.velocity == 0)
        clock += 0.016
        scrub.drag(translation: 0, at: clock)
        #expect(abs(scrub.displayValue - there) < 0.5, "no jump when a finger lands on a moving dial")
    }

    // MARK: Determinism and robustness

    @Test func theSameInputsGiveTheSameFeedback() {
        func run() -> [ScrubFeedback] {
            var scrub = model(range: 0...300) {
                $0.maxEventsPerSecond = 30
                $0.magnets = [ScrubMagnet(value: 120, radius: 1), ScrubMagnet(value: 200, radius: 0.5)]
            }
            var outputs: [ScrubFeedback] = []
            var rng = SeededGenerator(seed: 99)
            var clock = 0.0
            scrub.begin(at: clock)
            for _ in 0..<300 {
                clock += 0.004 + rng.unit() * 0.02
                outputs.append(scrub.drag(translation: (rng.unit() - 0.2) * 2400, at: clock))
            }
            outputs.append(scrub.end(at: clock))
            for _ in 0..<400 {
                clock += 1.0 / 60
                outputs.append(scrub.advance(to: clock))
            }
            return outputs + [ScrubFeedback(events: [], motionBlurRadius: scrub.value, digitTransition: scrub.displayValue)]
        }
        #expect(run() == run())
        #expect(run().contains { !$0.events.isEmpty })
    }

    @Test func randomGesturesNeverBreakTheInvariants() {
        var scrub = model(range: 10...90, step: 0.5) {
            $0.maxEventsPerSecond = 40
            $0.majorEvery = 4
            $0.magnets = [ScrubMagnet(value: 30, radius: 0.3), ScrubMagnet(value: 60, radius: 0.6, releaseRadius: 2)]
        }
        var rng = SeededGenerator(seed: 5)
        var clock = 0.0
        let limit = 2.0 * 0.5
        for round in 0..<3000 {
            clock += rng.unit() * 0.03 - (round % 97 == 0 ? 0.05 : 0)
            let pick = rng.unit()
            let feedback: ScrubFeedback
            switch pick {
            case ..<0.55: feedback = scrub.drag(translation: (rng.unit() - 0.5) * 900, at: clock)
            case ..<0.65: feedback = scrub.drag(translation: [Double.nan, .infinity, -.infinity, 1e300][Int(rng.next() % 4)], at: clock)
            case ..<0.75: feedback = scrub.end(at: clock)
            case ..<0.9: feedback = scrub.advance(to: clock + rng.unit() * 2)
            case ..<0.95: feedback = scrub.nudge(steps: Int(rng.next() % 9) - 4, at: clock)
            default:
                scrub.begin(at: clock)
                feedback = .none
            }
            #expect(scrub.value.isFinite && scrub.displayValue.isFinite && scrub.velocity.isFinite && scrub.overscroll.isFinite)
            #expect(scrub.value >= 10 && scrub.value <= 90)
            #expect(scrub.displayValue >= 10 - limit - 1e-9 && scrub.displayValue <= 90 + limit + 1e-9)
            #expect(feedback.events.count <= 1)
            #expect(feedback.motionBlurRadius >= 0 && feedback.motionBlurRadius <= 6)
            #expect(feedback.digitTransition >= 0 && feedback.digitTransition <= 1)
            for event in feedback.events {
                #expect(event.intensity >= 0 && event.intensity <= 1 && event.sharpness >= 0 && event.sharpness <= 1)
                #expect(event.value.isFinite)
            }
            if scrub.phase != .dragging, rng.unit() < 0.3 { clock += 3 }
        }
    }

    @Test func badTimesAndTranslationsAreIgnored() {
        var scrub = model()
        scrub.begin(at: 0)
        scrub.drag(translation: 40, at: 0.1)
        let value = scrub.value
        #expect(scrub.drag(translation: .nan, at: 0.2) == .none)
        #expect(scrub.drag(translation: 100, at: .nan) == .none)
        #expect(scrub.advance(to: .infinity) == .none)
        #expect(scrub.end(at: .nan) == .none)
        #expect(scrub.value == value)
        #expect(scrub.phase == .dragging)
    }

    @Test func eventsStillComeIfTheClockStepsBackwards() {
        var scrub = model { $0.maxEventsPerSecond = 10 }
        scrub.begin(at: 100)
        scrub.drag(translation: 8, at: 100.1)
        let later = scrub.drag(translation: 16, at: 5)
        #expect(later.events.count <= 1)
        let again = scrub.drag(translation: 40, at: 5.5)
        #expect(again.events.count == 1)
    }

    @Test func sanitizingTamesAbsurdConfigurations() {
        var configuration = ScrubConfiguration(range: 0...10, step: 0)
        configuration.pointsPerStep = .nan
        configuration.detentEvery = -3
        configuration.majorEvery = -3
        configuration.hysteresis = 9
        configuration.overscrollSteps = .infinity
        configuration.resistance = 0
        configuration.maxEventsPerSecond = .nan
        configuration.fastStepsPerSecond = -1
        configuration.maxBlurRadius = 1e9
        configuration.friction = .infinity
        let clean = configuration.sanitized
        #expect(clean.step > 0 && clean.step <= 10)
        #expect(clean.pointsPerStep == 8)
        #expect(clean.detentEvery == 1 && clean.majorEvery == 0)
        #expect(clean.hysteresis <= 0.45)
        #expect(clean.overscrollSteps <= 50)
        #expect(clean.resistance >= 0.1)
        #expect(clean.maxEventsPerSecond == 30)
        #expect(clean.maxBlurRadius == 6)
        var scrub = ScrubModel(configuration: configuration, value: 5)
        scrub.begin(at: 0)
        for index in 1...50 { scrub.drag(translation: Double(index), at: Double(index) * 0.016) }
        #expect(scrub.value.isFinite)

        var bad = ScrubConfiguration(range: 0...Double.infinity, step: .nan)
        bad.maxEventsPerSecond = 0
        let flat = ScrubModel(configuration: bad, value: .nan)
        #expect(flat.value == 0)
    }

    @Test func aRangeWithNoWidthDoesNothing() {
        var scrub = model(range: 5...5, value: 99)
        #expect(scrub.value == 5)
        scrub.begin(at: 0)
        for index in 1...20 {
            let feedback = scrub.drag(translation: Double(index) * 30, at: Double(index) * 0.016)
            #expect(feedback.events.isEmpty)
            #expect(scrub.value == 5 && scrub.displayValue == 5)
        }
        scrub.end(at: 1)
        var clock = 1.0
        for _ in 0..<30 { clock += 0.05; scrub.advance(to: clock) }
        #expect(scrub.phase == .idle)
        #expect(scrub.value == 5)
        #expect(scrub.nudge(steps: 3, at: clock + 1).events.isEmpty)
    }

    // MARK: Setting values directly

    @Test func jumpSetsTheValueSilently() {
        var scrub = model()
        scrub.jump(to: 37.4)
        #expect(scrub.value == 37 && scrub.displayValue == 37)
        scrub.jump(to: 1e9)
        #expect(scrub.value == 100)
        scrub.jump(to: -50)
        #expect(scrub.value == 0)
        scrub.jump(to: .nan)
        #expect(scrub.value == 0)
        scrub.begin(at: 0)
        scrub.drag(translation: 100, at: 0.1)
        scrub.jump(to: 20)
        #expect(scrub.phase == .idle && scrub.value == 20 && scrub.velocity == 0)
    }

    @Test func jumpingOntoAMagnetValueLocksIt() {
        var scrub = model { $0.magnets = [ScrubMagnet(value: 30.5, radius: 0.4)] }
        scrub.jump(to: 30.5)
        #expect(scrub.value == 30.5)
        scrub.jump(to: 31)
        #expect(scrub.value == 31, "inside the pull but not on the magnet: set exactly, no surprise move")
        scrub.begin(at: 0)
        let feedback = scrub.drag(translation: 0, at: 0.016)
        #expect(feedback.events.isEmpty)
        #expect(scrub.value == 31, "a new gesture starts from where the value is")
    }

    @Test func nudgeMovesByStepsWithFeedbackAndStopsAtTheEnds() {
        var scrub = model(value: 10) { $0.majorEvery = 5 }
        let three = scrub.nudge(steps: 3, at: 1)
        #expect(scrub.value == 13)
        #expect(three.events.map(\.kind) == [.tick] && three.events.first?.value == 13)
        let five = scrub.nudge(steps: 5, at: 2)
        #expect(scrub.value == 18)
        #expect(five.events.map(\.kind) == [.majorTick] && five.events.first?.value == 15)
        let back = scrub.nudge(steps: -2, at: 3)
        #expect(scrub.value == 16 && back.events.first?.direction == -1)

        let far = scrub.nudge(steps: 10_000, at: 4)
        #expect(scrub.value == 100)
        #expect(far.events.count == 1)
        let wall = scrub.nudge(steps: 1, at: 5)
        #expect(wall.events.map(\.kind) == [.boundsHit])
        #expect(scrub.nudge(steps: Int.max, at: 6).events.map(\.kind) == [.boundsHit])
        #expect(scrub.nudge(steps: Int.min, at: 7).events.count == 1)
        #expect(scrub.value == 0)
        #expect(scrub.nudge(steps: 0, at: 8).events.isEmpty)
    }

    @Test func nudgingOntoAMagnetValueSnaps() {
        var scrub = model(value: 28) { $0.magnets = [ScrubMagnet(value: 30, radius: 0.4)] }
        let feedback = scrub.nudge(steps: 2, at: 1)
        #expect(feedback.events.map(\.kind) == [.magnetSnap])
        #expect(scrub.value == 30)
    }

    // MARK: Formatting and the grid

    @Test func formatHooksPrintValues() {
        var configuration = ScrubConfiguration(range: 0...600, step: 5)
        configuration.format = .minutes
        let scrub = ScrubModel(configuration: configuration, value: 95)
        #expect(scrub.formattedValue == "1 h 35 min")
        #expect(ScrubValueFormat.integer(-0.4) == "0")
        #expect(ScrubValueFormat.integer(41.6) == "42")
        #expect(ScrubValueFormat.decimal(1)(-0.04) == "0.0")
        #expect(ScrubValueFormat.decimal(2)(3.14159) == "3.14")
        #expect(ScrubValueFormat.decimal(0)(2.5) == "3" || ScrubValueFormat.decimal(0)(2.5) == "2")
        #expect(ScrubValueFormat.compactMinutes(75) == "1h 15m")
        #expect(ScrubValueFormat.page(142) == "p. 142")
        #expect(ScrubValueFormat.custom { "\(Int($0)) pages left" }(12) == "12 pages left")
        for hostile in [Double.nan, .infinity, -.infinity, 1e300, -1e300] {
            _ = ScrubValueFormat.integer(hostile)
            _ = ScrubValueFormat.decimal(3)(hostile)
            _ = ScrubValueFormat.minutes(hostile)
            _ = ScrubValueFormat.compactMinutes(hostile)
            _ = ScrubValueFormat.page(hostile)
        }
    }

    @Test func theGridFindsTheNearestCell() {
        let grid = ScrubGrid(range: 2...12.3, step: 1)
        #expect(grid.lastCell == 11)
        #expect(grid.position(ofCell: 0) == 2 && grid.position(ofCell: 11) == 12.3)
        #expect(grid.position(ofCell: -4) == 2 && grid.position(ofCell: 999) == 12.3)
        var rng = SeededGenerator(seed: 3)
        for _ in 0..<2000 {
            let x = rng.unit() * 20 - 4
            let cell = grid.cell(containing: x)
            let best = (0...grid.lastCell).min { abs(grid.position(ofCell: $0) - x) < abs(grid.position(ofCell: $1) - x) } ?? 0
            #expect(abs(grid.position(ofCell: cell) - x) <= abs(grid.position(ofCell: best) - x) + 1e-9, "x \(x) cell \(cell) best \(best)")
        }
        #expect(grid.cell(containing: .nan) == 0)
        #expect(grid.cell(containing: .infinity) == 11)
        #expect(grid.cell(containing: -.infinity) == 0)
        #expect(ScrubGrid(range: 4...4, step: 1).lastCell == 0)
    }
}

// MARK: - Date scrub

struct DateScrubTests {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .current
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func scrub(zone: String = "UTC", earliest: Int = 1, latest: Int = 365) -> DateScrub {
        // 600 minutes of book left: more days, fewer minutes a day.
        DateScrub(start: now, calendar: calendar(zone), earliestDay: earliest, latestDay: latest) { _, days in
            days > 0 ? 600.0 / Double(days) : nil
        }
    }

    @Test func offsetsAndDatesRoundTrip() {
        let scrub = scrub()
        for offset in [1, 2, 30, 100, 365] {
            let date = scrub.date(forOffset: offset)
            #expect(scrub.offset(of: date) == offset)
            #expect(scrub.calendar.component(.hour, from: date) == 0, "start of day")
        }
        #expect(scrub.offset(of: now.addingTimeInterval(-86_400 * 50)) == 1, "clamped to the timeline")
        #expect(scrub.offset(of: now.addingTimeInterval(86_400 * 9000)) == 365)
    }

    @Test func daysStayWholeAcrossDaylightSavingChanges() {
        // US clocks went forward on 14 March 2027: the day is 23 hours long.
        var local = calendar("America/New_York")
        local.locale = Locale(identifier: "en_US")
        let start = local.date(from: DateComponents(year: 2027, month: 3, day: 12, hour: 15)) ?? now
        let scrub = DateScrub(start: start, calendar: local, earliestDay: 1, latestDay: 30) { _, _ in 10 }
        for offset in 1...30 {
            let date = scrub.date(forOffset: offset)
            let parts = local.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let expected = local.date(byAdding: .day, value: offset, to: local.startOfDay(for: start)) ?? start
            #expect(date == expected)
            #expect(parts.hour == 0 && parts.minute == 0, "midnight on day \(offset)")
            #expect(scrub.offset(of: date) == offset)
        }
        #expect(scrub.date(forOffset: 3) != scrub.date(forOffset: 2).addingTimeInterval(86_400 * 2))
    }

    @Test func resultsCarryTheCallersMinutesPerDay() {
        let scrub = scrub()
        let week = scrub.result(forOffset: 7)
        #expect(week.dayOffset == 7)
        #expect(week.date == scrub.date(forOffset: 7))
        #expect(abs((week.minutesPerDay ?? 0) - 600.0 / 7) < 1e-9)
        #expect(!week.isEarliest && !week.isLatest)

        var previous = Double.infinity
        for offset in 1...365 {
            let minutes = scrub.result(forOffset: offset).minutesPerDay ?? .nan
            #expect(minutes <= previous, "later means fewer minutes a day")
            previous = minutes
        }
    }

    @Test func theClosureSeesTheDateAndTheDayCount() {
        let seen = DateScrub(start: now, calendar: calendar(), earliestDay: 1, latestDay: 100) { date, days in
            Double(days) + date.timeIntervalSince(Calendar(identifier: .gregorian).startOfDay(for: date)) * 0
        }
        #expect(seen.result(forOffset: 42).minutesPerDay == 42)
        let start = calendar().startOfDay(for: now)
        let capture = DateScrub(start: now, calendar: calendar(), earliestDay: 1, latestDay: 100) { date, days in
            date == (Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: start)) ? 1 : 0
        }
        #expect(capture.result(forOffset: 9).minutesPerDay == 1)
    }

    @Test func fractionsAndDragsMapToDays() {
        let scrub = scrub(earliest: 1, latest: 101)
        #expect(scrub.spanDays == 100)
        #expect(scrub.result(forFraction: 0).dayOffset == 1 && scrub.result(forFraction: 0).isEarliest)
        #expect(scrub.result(forFraction: 1).dayOffset == 101 && scrub.result(forFraction: 1).isLatest)
        #expect(scrub.result(forFraction: 0.5).dayOffset == 51)
        #expect(scrub.result(forFraction: -4).dayOffset == 1)
        #expect(scrub.result(forFraction: 9).dayOffset == 101)
        #expect(scrub.result(forFraction: .nan).dayOffset == 1)
        #expect(abs(scrub.result(forOffset: 26).fraction - 0.25) < 1e-12)

        #expect(scrub.result(forX: 150, inWidth: 300).dayOffset == 51)
        #expect(scrub.result(forX: -20, inWidth: 300).dayOffset == 1)
        #expect(scrub.result(forX: 20, inWidth: 0).dayOffset == 1)

        #expect(scrub.result(forTranslation: 60, from: 10, pointsPerDay: 6).dayOffset == 20)
        #expect(scrub.result(forTranslation: -30, from: 10, pointsPerDay: 6).dayOffset == 5)
        #expect(scrub.result(forTranslation: 1e12, from: 10, pointsPerDay: 6).dayOffset == 101)
        #expect(scrub.result(forTranslation: .nan, from: 10, pointsPerDay: 6).dayOffset == 10)
        #expect(scrub.result(forTranslation: 10, from: 10, pointsPerDay: 0).dayOffset == 10)

        var offsets: [Int] = []
        for x in stride(from: 0.0, through: 300, by: 3) { offsets.append(scrub.result(forX: x, inWidth: 300).dayOffset) }
        #expect(offsets == offsets.sorted())
    }

    @Test func unusableMinutesBecomeNil() {
        for answer in [Double.nan, .infinity, -1, 5000, 1441] as [Double] {
            let scrub = DateScrub(start: now, calendar: calendar()) { _, _ in answer }
            #expect(scrub.result(forOffset: 5).minutesPerDay == nil, "\(answer)")
        }
        let none = DateScrub(start: now, calendar: calendar()) { _, _ in nil }
        #expect(none.result(forOffset: 5).minutesPerDay == nil)
        let edge = DateScrub(start: now, calendar: calendar()) { _, _ in 1440 }
        #expect(edge.result(forOffset: 5).minutesPerDay == 1440)
        let zero = DateScrub(start: now, calendar: calendar()) { _, _ in 0 }
        #expect(zero.result(forOffset: 5).minutesPerDay == 0)
    }

    @Test func timelineBoundsAreSanitized() {
        let odd = DateScrub(start: now, calendar: calendar(), earliestDay: 50, latestDay: 10) { _, _ in 1 }
        #expect(odd.earliestOffset == 50 && odd.latestOffset == 50)
        #expect(odd.spanDays == 0)
        #expect(odd.result(forFraction: 0.7).dayOffset == 50)
        #expect(odd.result(forFraction: 0.7).fraction == 0)
        let negative = DateScrub(start: now, calendar: calendar(), earliestDay: -9, latestDay: -2) { _, _ in 1 }
        #expect(negative.earliestOffset == 0)
        let huge = DateScrub(start: now, calendar: calendar(), earliestDay: 1, latestDay: Int.max) { _, _ in 1 }
        #expect(huge.latestOffset == 36_500)
        #expect(huge.result(forOffset: Int.max).date.timeIntervalSince(now) > 0)
    }

    @Test func driveAScrubModelOverTheTimeline() {
        let timeline = scrub(earliest: 1, latest: 120)
        var configuration = timeline.scrubConfiguration(magnetOffsets: [30, 60, 900], magnetRadius: 0.45)
        configuration.maxEventsPerSecond = 1000
        var model = ScrubModel(configuration: configuration, value: 10)
        #expect(model.configuration.step == 1)
        #expect(model.configuration.majorEvery == 7)
        #expect(model.magnets.map(\.value) == [30, 60], "a magnet beyond the timeline is dropped")
        #expect(model.value == 10)

        model.begin(at: 0)
        var clock = 0.0
        var snaps: [Double] = []
        for step in 1...600 {
            clock += 0.016
            let feedback = model.drag(translation: Double(step) * 0.5, at: clock)
            snaps += feedback.events.filter { $0.kind == .magnetSnap }.map(\.value)
            let result = timeline.result(forValue: model.value)
            #expect(result.dayOffset == Int(model.value))
            #expect(result.fraction >= 0 && result.fraction <= 1)
        }
        #expect(snaps == [30, 60])

        let text = model.formattedValue
        #expect(text == LeafFormat.shortDate(timeline.date(forOffset: Int(model.value)), today: now, calendar: timeline.calendar))
        #expect(timeline.result(forValue: .nan).dayOffset == 1)
        #expect(timeline.result(forValue: 1e9).dayOffset == 120)
    }
}

// MARK: - Atmosphere

struct AtmosphereFieldTests {
    private let seed: UInt64 = 20_261_018

    // MARK: Determinism and counts

    @Test func sameInputsSameScene() {
        for time in [0.0, 3.7, 1234.5] {
            #expect(AtmosphereField.bokeh(seed: seed, time: time, count: 9, calm: 1) == AtmosphereField.bokeh(seed: seed, time: time, count: 9, calm: 1))
            #expect(AtmosphereField.rain(seed: seed, time: time, count: 40, calm: 0.7) == AtmosphereField.rain(seed: seed, time: time, count: 40, calm: 0.7))
            #expect(AtmosphereField.steam(seed: seed, time: time, count: 6, calm: 0.4) == AtmosphereField.steam(seed: seed, time: time, count: 6, calm: 0.4))
        }
    }

    @Test func differentSeedsMakeDifferentScenes() {
        #expect(AtmosphereField.bokeh(seed: 1, time: 5, count: 9, calm: 1) != AtmosphereField.bokeh(seed: 2, time: 5, count: 9, calm: 1))
        #expect(AtmosphereField.rain(seed: 1, time: 5, count: 30, calm: 1) != AtmosphereField.rain(seed: 2, time: 5, count: 30, calm: 1))
        #expect(AtmosphereField.steam(seed: 1, time: 5, count: 5, calm: 1) != AtmosphereField.steam(seed: 2, time: 5, count: 5, calm: 1))
    }

    @Test func elementsDoNotShuffleWhenTheCountGrows() {
        let few = AtmosphereField.bokeh(seed: seed, time: 8, count: 4, calm: 1)
        let many = AtmosphereField.bokeh(seed: seed, time: 8, count: 12, calm: 1)
        #expect(Array(many.prefix(4)) == few)
        let rainFew = AtmosphereField.rain(seed: seed, time: 8, count: 10, calm: 1)
        let rainMany = AtmosphereField.rain(seed: seed, time: 8, count: 60, calm: 1)
        #expect(rainFew.map(\.layer) == rainMany.prefix(10).map(\.layer))
        #expect(rainFew.map(\.length) == rainMany.prefix(10).map(\.length))
    }

    @Test func countsAreClamped() {
        #expect(AtmosphereField.bokeh(seed: seed, time: 1, count: 0, calm: 1).isEmpty)
        #expect(AtmosphereField.bokeh(seed: seed, time: 1, count: -5, calm: 1).isEmpty)
        #expect(AtmosphereField.rain(seed: seed, time: 1, count: -1, calm: 1).isEmpty)
        #expect(AtmosphereField.steam(seed: seed, time: 1, count: Int.min, calm: 1).isEmpty)
        #expect(AtmosphereField.bokeh(seed: seed, time: 1, count: 10_000, calm: 1).count == AtmosphereField.maxBokeh)
        #expect(AtmosphereField.rain(seed: seed, time: 1, count: Int.max, calm: 1).count == AtmosphereField.maxRain)
        #expect(AtmosphereField.steam(seed: seed, time: 1, count: 999, calm: 1).count == AtmosphereField.maxSteam)
    }

    // MARK: Bounds

    @Test func everythingStaysInBounds() {
        for calm in [0.0, 0.3, 1] {
            for time in stride(from: 0.0, through: 3600, by: 41.3) {
                for light in AtmosphereField.bokeh(seed: seed, time: time, count: 40, calm: calm) {
                    #expect(light.x > -0.1 && light.x < 1.1 && light.y > -0.1 && light.y < 1.1)
                    #expect(light.radius > 0.04 && light.radius < 0.3)
                    #expect(light.opacity > 0.05 && light.opacity <= 0.36)
                    #expect(light.hueOffset >= -1 && light.hueOffset <= 1)
                }
                for streak in AtmosphereField.rain(seed: seed, time: time, count: 120, calm: calm) {
                    #expect(streak.x > -0.05 && streak.x < 1.05)
                    #expect(streak.y >= -streak.length - 1e-9 && streak.y <= 1 + streak.length + 1e-9)
                    #expect(streak.length > 0.03 && streak.length < 0.3)
                    #expect(streak.width > 0 && streak.width < 0.02)
                    #expect(streak.speed > 0 && streak.speed < 0.6)
                    #expect(streak.depth >= 0 && streak.depth < 1)
                    #expect((0...2).contains(streak.layer) && streak.layer == Int(streak.depth * 3))
                    #expect(streak.opacity > 0.05 && streak.opacity <= 0.56)
                }
                for wisp in AtmosphereField.steam(seed: seed, time: time, count: 24, calm: calm) {
                    #expect(wisp.x > 0.1 && wisp.x < 0.9)
                    #expect(wisp.y > 0 && wisp.y <= 1)
                    #expect(wisp.progress >= 0 && wisp.progress < 1)
                    #expect(wisp.width > 0.03 && wisp.width < 0.2)
                    #expect(wisp.opacity >= 0 && wisp.opacity < 0.5)
                    #expect(wisp.riseSpeed > 0 && wisp.riseSpeed < 0.2)
                }
            }
        }
    }

    @Test func rainFillsAllThreeLayers() {
        let streaks = AtmosphereField.rain(seed: seed, time: 10, count: 90, calm: 1)
        for layer in 0...2 { #expect(streaks.contains { $0.layer == layer }) }
        let far = streaks.filter { $0.layer == 0 }
        let near = streaks.filter { $0.layer == 2 }
        let farLongest: Double = far.map(\.length).max() ?? 1
        let nearLongest: Double = near.map(\.length).max() ?? 0
        #expect(farLongest < nearLongest)
        let farOpacity: Double = far.map(\.opacity).reduce(0, +)
        let nearOpacity: Double = near.map(\.opacity).reduce(0, +)
        let farAverage: Double = farOpacity / Double(max(far.count, 1))
        let nearAverage: Double = nearOpacity / Double(max(near.count, 1))
        #expect(farAverage < nearAverage)
        let lanes = Set(streaks.map { Int($0.x * 30) })
        #expect(lanes.count > 20, "spread across the glass")
    }

    @Test func hostileInputsStayFinite() {
        for value in [Double.nan, .infinity, -.infinity, 1e300, -1e300, -5] {
            for calm in [Double.nan, .infinity, -3, 7, value] {
                for light in AtmosphereField.bokeh(seed: 0, time: value, count: 8, calm: calm) {
                    #expect(light.x.isFinite && light.y.isFinite && light.radius.isFinite && light.opacity.isFinite)
                }
                for streak in AtmosphereField.rain(seed: .max, time: value, count: 8, calm: calm) {
                    #expect(streak.x.isFinite && streak.y.isFinite && streak.speed.isFinite && streak.opacity.isFinite)
                }
                for wisp in AtmosphereField.steam(seed: 1, time: value, count: 8, calm: calm) {
                    #expect(wisp.x.isFinite && wisp.y.isFinite && wisp.opacity.isFinite)
                }
            }
        }
    }

    // MARK: Continuity

    @Test func bokehDriftsSmoothlyAtLowFrameRates() {
        let frame = 1.0 / 15
        var time = 0.0
        var previous = AtmosphereField.bokeh(seed: seed, time: time, count: 12, calm: 1)
        for _ in 0..<(15 * 120) {
            time += frame
            let now = AtmosphereField.bokeh(seed: seed, time: time, count: 12, calm: 1)
            for (a, b) in zip(previous, now) {
                #expect(abs(a.x - b.x) < 0.003 && abs(a.y - b.y) < 0.003, "drift is very slow")
                #expect(abs(a.radius - b.radius) < 0.002)
                #expect(abs(a.opacity - b.opacity) < 0.004)
                #expect(a.hueOffset == b.hueOffset)
            }
            previous = now
        }
    }

    @Test func rainRunsDownAndOnlyWrapsOutOfSight() {
        let frame = 1.0 / 15
        var time = 0.0
        var previous = AtmosphereField.rain(seed: seed, time: time, count: 60, calm: 1)
        var wraps = 0
        for _ in 0..<(15 * 240) {
            time += frame
            let now = AtmosphereField.rain(seed: seed, time: time, count: 60, calm: 1)
            for (a, b) in zip(previous, now) {
                let moved = b.y - a.y
                if moved < 0 {
                    wraps += 1
                    #expect(a.y - a.length >= 1 - 0.02, "it had left the bottom (within a frame) before it wrapped")
                    #expect(b.y <= 1e-9, "and came back entirely above the top")
                } else {
                    #expect(moved < 0.02, "no jump: moved \(moved)")
                    #expect(abs(a.x - b.x) < 0.002)
                    #expect(abs(a.opacity - b.opacity) < 0.02)
                }
                #expect(a.length == b.length && a.layer == b.layer)
            }
            previous = now
        }
        #expect(wraps > 10, "over four minutes streaks do loop")
    }

    @Test func steamIsInvisibleWhenItRestarts() {
        let frame = 1.0 / 15
        var time = 0.0
        var previous = AtmosphereField.steam(seed: seed, time: time, count: 8, calm: 1)
        var restarts = 0
        for _ in 0..<(15 * 200) {
            time += frame
            let now = AtmosphereField.steam(seed: seed, time: time, count: 8, calm: 1)
            for (a, b) in zip(previous, now) {
                if b.progress < a.progress {
                    restarts += 1
                    #expect(a.opacity < 0.03 && b.opacity < 0.03, "faded out before it restarted")
                } else {
                    #expect(abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.02, "no jump")
                    #expect(abs(a.opacity - b.opacity) < 0.05)
                    #expect(abs(a.width - b.width) < 0.01)
                }
            }
            previous = now
        }
        #expect(restarts > 8)
    }

    @Test func steamRisesAndFadesInAndOut() {
        let wisps = AtmosphereField.steam(seed: seed, time: 0, count: 1, calm: 1)
        guard let first = wisps.first else {
            Issue.record("expected a wisp")
            return
        }
        var samples: [AtmosphereSteamWisp] = []
        for tenth in 0..<150 {
            if let wisp = AtmosphereField.steam(seed: seed, time: Double(tenth) / 10, count: 1, calm: 1).first { samples.append(wisp) }
        }
        let peak = samples.map(\.opacity).max() ?? 0
        #expect(peak > 0.2)
        let highest = samples.filter { $0.opacity > 0.9 * peak }
        #expect(highest.allSatisfy { $0.progress > 0.25 && $0.progress < 0.75 }, "brightest in the middle of its rise")
        #expect(first.riseSpeed > 0)
    }

    // MARK: Calm

    @Test func calmZeroFreezesEverything() {
        let frozen = AtmosphereField.bokeh(seed: seed, time: 0, count: 10, calm: 0)
        let rain = AtmosphereField.rain(seed: seed, time: 0, count: 40, calm: 0)
        let steam = AtmosphereField.steam(seed: seed, time: 0, count: 8, calm: 0)
        for time in [0.1, 1, 17.5, 600, 86_400, 1e7] {
            #expect(AtmosphereField.bokeh(seed: seed, time: time, count: 10, calm: 0) == frozen)
            #expect(AtmosphereField.rain(seed: seed, time: time, count: 40, calm: 0) == rain)
            #expect(AtmosphereField.steam(seed: seed, time: time, count: 8, calm: 0) == steam)
        }
        #expect(AtmosphereField.bokeh(seed: seed, time: 600, count: 10, calm: 1) != frozen, "calm 1 does move")
        #expect(AtmosphereField.rain(seed: seed, time: 10, count: 40, calm: 1) != rain)
        #expect(AtmosphereField.steam(seed: seed, time: 3, count: 8, calm: 1) != steam)
    }

    @Test func lowerCalmMeansSlowerMotion() {
        func travelled(calm: Double) -> Double {
            var total = 0.0
            var previous = AtmosphereField.rain(seed: seed, time: 100, count: 30, calm: calm)
            for tick in 1...30 {
                let now = AtmosphereField.rain(seed: seed, time: 100 + Double(tick) / 15, count: 30, calm: calm)
                for (a, b) in zip(previous, now) where b.y >= a.y { total += b.y - a.y }
                previous = now
            }
            return total
        }
        let full = travelled(calm: 1)
        let half = travelled(calm: 0.5)
        let low = travelled(calm: 0.1)
        #expect(full > half && half > low && low > 0)
        #expect(abs(half / full - 0.5) < 0.1)
    }

    @Test func tempoAndAmplitudeFollowCalm() {
        #expect(AtmosphereField.tempo(forCalm: 0) == 0 && AtmosphereField.tempo(forCalm: 1) == 1)
        #expect(AtmosphereField.tempo(forCalm: 7) == 1 && AtmosphereField.tempo(forCalm: -2) == 0)
        #expect(AtmosphereField.tempo(forCalm: .nan) == 1)
        #expect(AtmosphereField.amplitude(forCalm: 0) < AtmosphereField.amplitude(forCalm: 1))
        #expect(AtmosphereField.amplitude(forCalm: 1) == 1)
    }

    // MARK: The clock

    @Test func theClockKeepsTheSceneContinuousThroughAPause() {
        var clock = AtmosphereClock(calm: 1)
        let frame = 1.0 / 15
        var time = 0.0
        clock.advance(to: time, calm: 1)
        var previous = AtmosphereField.rain(seed: seed, phase: clock.phase, count: 40, calm: clock.calm)
        var previousSteam = AtmosphereField.steam(seed: seed, phase: clock.phase, count: 6, calm: clock.calm)
        var largest = 0.0
        var motionAfterPause = 0.0
        for tick in 1...(15 * 60) {
            time += frame
            let target = time >= 20 && time < 40 ? 0.0 : 1.0
            clock.advance(to: time, calm: target)
            let now = AtmosphereField.rain(seed: seed, phase: clock.phase, count: 40, calm: clock.calm)
            let steam = AtmosphereField.steam(seed: seed, phase: clock.phase, count: 6, calm: clock.calm)
            for (a, b) in zip(previous, now) where b.y >= a.y {
                largest = max(largest, b.y - a.y)
                if time > 30 && time < 40 { motionAfterPause += b.y - a.y }
            }
            for (a, b) in zip(previousSteam, steam) where b.progress >= a.progress {
                #expect(abs(a.x - b.x) < 0.02 && abs(a.y - b.y) < 0.03, "steam jumped at tick \(tick)")
            }
            previous = now
            previousSteam = steam
        }
        #expect(largest < 0.02, "no jump when the pace changed: \(largest)")
        #expect(motionAfterPause < 1e-3, "ten seconds into the pause nothing moves: \(motionAfterPause)")
        #expect(clock.calm > 0.99, "and it comes back")
    }

    @Test func theClockDoesNotDependOnTheFrameRate() {
        func run(fps: Double) -> AtmosphereClock {
            var clock = AtmosphereClock(calm: 1)
            let frames = Int(fps * 12)
            for frame in 0...frames {
                clock.advance(to: Double(frame) / fps, calm: 0.1)
            }
            return clock
        }
        let at15 = run(fps: 15)
        let at60 = run(fps: 60)
        let at30 = run(fps: 30)
        #expect(abs(at15.phase - at60.phase) < 1e-9)
        #expect(abs(at15.phase - at30.phase) < 1e-9)
        #expect(abs(at15.calm - at60.calm) < 1e-9)
    }

    @Test func theClockCountsABackgroundedGapAsOneSecond() {
        var clock = AtmosphereClock(calm: 1)
        clock.advance(to: 0, calm: 1)
        clock.advance(to: 5_000, calm: 1)
        #expect(abs(clock.phase - AtmosphereClock.longestFrame) < 1e-9)
        clock.advance(to: 4_000, calm: 1)
        #expect(abs(clock.phase - AtmosphereClock.longestFrame) < 1e-9, "time running backwards does nothing")
        clock.advance(to: .nan, calm: .nan)
        #expect(clock.phase.isFinite && clock.calm.isFinite)
    }

    @Test func theClockEasesCalmInsteadOfSnapping() {
        var clock = AtmosphereClock(calm: 1, response: 0.8)
        clock.advance(to: 0, calm: 0)
        clock.advance(to: 0.1, calm: 0)
        #expect(clock.calm < 1 && clock.calm > 0.8)
        var time = 0.1
        var calms: [Double] = []
        for _ in 0..<120 { time += 0.05; clock.advance(to: time, calm: 0); calms.append(clock.calm) }
        #expect(calms == calms.sorted(by: >))
        #expect(calms.last ?? 1 < 0.01)
        #expect(clock.tempo == clock.calm)
        #expect(AtmosphereClock(calm: 9).calm == 1)
        #expect(AtmosphereClock(calm: -9).calm == 0)
    }
}

// MARK: - Hearth (nook scenes)

struct HearthFieldTests {
    private let seed: UInt64 = 20_261_021

    @Test func embersAreDeterministicAndClamped() {
        let a = AtmosphereField.embers(seed: seed, time: 12.5, count: 10, calm: 1)
        let b = AtmosphereField.embers(seed: seed, time: 12.5, count: 10, calm: 1)
        #expect(a == b)
        let none = AtmosphereField.embers(seed: seed, time: 1, count: -3, calm: 1)
        #expect(none.isEmpty)
        let many = AtmosphereField.embers(seed: seed, time: 1, count: 10_000, calm: 1)
        #expect(many.count == AtmosphereField.maxEmbers)
    }

    @Test func embersStayInTheLowerSceneAndInBounds() {
        for tenth in 0..<600 {
            let time = Double(tenth) / 10
            for ember in AtmosphereField.embers(seed: seed, time: time, count: 16, calm: 1) {
                let inX: Bool = ember.x >= 0 && ember.x <= 1
                let inY: Bool = ember.y >= 0.45 && ember.y <= 1
                let visible: Bool = ember.opacity >= 0 && ember.opacity <= 1
                #expect(inX && inY && visible)
                #expect(ember.radius > 0)
            }
        }
    }

    @Test func embersAreDarkWhenTheyRestart() {
        let frame = 1.0 / 15
        var time = 0.0
        var previous = AtmosphereField.embers(seed: seed, time: time, count: 8, calm: 1)
        var restarts = 0
        for _ in 0..<(15 * 120) {
            time += frame
            let now = AtmosphereField.embers(seed: seed, time: time, count: 8, calm: 1)
            for (a, b) in zip(previous, now) {
                if b.progress < a.progress {
                    restarts += 1
                    let faded: Bool = a.opacity < 0.03 && b.opacity < 0.03
                    #expect(faded, "dark before it restarted")
                } else {
                    let step: Double = abs(a.y - b.y)
                    #expect(step < 0.01, "no jump")
                }
            }
            previous = now
        }
        #expect(restarts > 4)
    }

    @Test func flickerStaysWarmAndSmooth() {
        var previous = AtmosphereField.flicker(seed: seed, phase: 0)
        for frame in 1..<(15 * 60) {
            let level = AtmosphereField.flicker(seed: seed, phase: Double(frame) / 15)
            let inRange: Bool = level >= 0.65 && level <= 1
            #expect(inRange)
            let step: Double = abs(level - previous)
            #expect(step < 0.05, "no visible jump between frames")
            previous = level
        }
    }

    @Test func hostileInputsStayFinite() {
        for value in [Double.nan, .infinity, -.infinity, 1e300, -1e300] {
            let level = AtmosphereField.flicker(seed: .max, phase: value)
            #expect(level.isFinite)
            for ember in AtmosphereField.embers(seed: 0, time: value, count: 6, calm: value) {
                let finite: Bool = ember.x.isFinite && ember.y.isFinite && ember.opacity.isFinite && ember.radius.isFinite
                #expect(finite)
            }
        }
    }
}
