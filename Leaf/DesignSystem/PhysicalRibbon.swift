import CoreMotion
import SwiftUI

// MARK: - Tilt

/// The phone's tilt for every ribbon on screen (NEXT.md section 8): device-motion gravity at 30 Hz, shared, running
/// only while at least one ribbon wants it. `gravity` changes only when the direction moves by more than about half a
/// degree, so a phone lying still causes no updates at all.
@MainActor
@Observable
final class RibbonTilt {
    static let shared = RibbonTilt()

    /// The in-screen part of gravity, x to the right and y down: about (0, 1) when the phone is held upright.
    private(set) var gravity = RibbonVector(x: 0, y: 1)

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0

    private init() {}

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            let next = RibbonVector(x: g.x, y: -g.y)
            if abs(next.x - self.gravity.x) + abs(next.y - self.gravity.y) > 0.012 {
                self.gravity = next
            }
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0, manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }
}

// MARK: - Ribbon

/// A satin bookmark ribbon that behaves like cloth (NEXT.md section 8). `RibbonSimulation` does the physics; this only
/// feeds it (tilt, a flick on appear, a drag) and draws its pose: a Catmull-Rom curve through the chain, a strip that
/// tapers toward a swallowtail notch, a satin highlight that slides with the curvature, and a soft shadow.
///
/// It sleeps: the `TimelineView` stops as soon as the ribbon has settled, and only an input wakes it. Reduce Motion
/// draws the simulation's fixed resting curve and takes no input.
struct PhysicalRibbon: View {
    /// Anchor to tail at rest, in points.
    var length: CGFloat
    /// The strip's width at the anchor.
    var width: CGFloat
    var color: Color = .ribbon
    var seed: UInt64 = 1
    /// Breathes for a few seconds after waking instead of falling still at once (a hero cover).
    var breathes = false
    /// A small flick each time it appears.
    var swaysOnAppear = false
    /// Slides up out of sight (behind the cover it hangs from), for a finished book.
    var isTucked = false
    /// Where a finger may take hold, in points below the anchor (the part not hidden by the cover).
    var grabFrom: CGFloat = 0
    var isInteractive = true
    var followsTilt = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var box: SimulationBox
    @State private var isAwake = false
    @State private var tuck: CGFloat

    /// The simulation lives in a reference so the timeline can step it while drawing without causing an update.
    private final class SimulationBox {
        var simulation: RibbonSimulation
        var lastTime: Double?
        var isHeld = false

        init(seed: UInt64, breathes: Bool) {
            var configuration = RibbonConfiguration.standard
            configuration.idle = breathes ? .breathesThenSleeps : .still
            simulation = RibbonSimulation(seed: seed, configuration: configuration)
        }
    }

    /// Room on each side of the anchor for the ribbon to swing, as a multiple of its width.
    static let swingRoom: CGFloat = 3

    init(
        length: CGFloat, width: CGFloat, color: Color = .ribbon, seed: UInt64 = 1, breathes: Bool = false,
        swaysOnAppear: Bool = false, isTucked: Bool = false, grabFrom: CGFloat = 0, isInteractive: Bool = true,
        followsTilt: Bool = true
    ) {
        self.length = length
        self.width = width
        self.color = color
        self.seed = seed
        self.breathes = breathes
        self.swaysOnAppear = swaysOnAppear
        self.isTucked = isTucked
        self.grabFrom = grabFrom
        self.isInteractive = isInteractive
        self.followsTilt = followsTilt
        _box = State(initialValue: SimulationBox(seed: seed, breathes: breathes))
        _tuck = State(initialValue: isTucked ? 1 : 0)
    }

    /// The frame the ribbon draws in: wide enough to swing, a little longer than the ribbon for the notch.
    static func canvasSize(length: CGFloat, width: CGFloat) -> CGSize {
        CGSize(width: width * (1 + 2 * swingRoom), height: length + width * 1.2)
    }

    private var isStill: Bool { reduceMotion }

    var body: some View {
        let size = Self.canvasSize(length: length, width: width)
        Group {
            if isStill {
                Canvas { context, canvasSize in
                    draw(RibbonSimulation.reducedMotionPose(pointCount: box.simulation.points.count), in: &context, size: canvasSize)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isAwake || scenePhase != .active)) { timeline in
                    let pose = step(to: timeline.date)
                    Canvas { context, canvasSize in
                        draw(pose, in: &context, size: canvasSize)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(y: -tuck * length * 0.85)
        .clipped()
        .contentShape(grabShape(in: size))
        .gesture(dragGesture, including: isInteractive && !isStill ? .all : .none)
        .accessibilityHidden(true)
        .onAppear(perform: appear)
        .onDisappear {
            if followsTilt && !isStill { RibbonTilt.shared.stop() }
        }
        .onChange(of: RibbonTilt.shared.gravity) { _, gravity in
            guard followsTilt, !isStill else { return }
            box.simulation.setTilt(gravity)
            if !box.simulation.isSettled { wake() }
        }
        .onChange(of: isTucked) { _, tucked in
            withAnimation(reduceMotion ? Motion.fade : Motion.board) { tuck = tucked ? 1 : 0 }
            guard !isStill else { return }
            box.simulation.flutter(strength: 0.6)
            wake()
        }
    }

    // MARK: Stepping

    private func appear() {
        guard !isStill else { return }
        if followsTilt {
            RibbonTilt.shared.start()
            box.simulation.setTilt(RibbonTilt.shared.gravity)
        }
        if swaysOnAppear {
            box.simulation.tap(atDepth: 1, direction: 1, strength: 0.7)
        }
        if !box.simulation.isSettled { wake() }
    }

    private func wake() {
        box.lastTime = nil
        if !isAwake { isAwake = true }
    }

    /// Advances the simulation to `date` and returns the pose to draw. Puts the timeline to sleep once settled.
    private func step(to date: Date) -> RibbonPose {
        let now = date.timeIntervalSinceReferenceDate
        let dt = box.lastTime.map { now - $0 } ?? 1.0 / 60.0
        box.lastTime = now
        box.simulation.advance(by: min(max(dt, 0), 0.1))
        let pose = box.simulation.pose
        if pose.isSettled && !box.isHeld && isAwake {
            DispatchQueue.main.async { isAwake = false }
        }
        return pose
    }

    // MARK: Dragging

    private func grabShape(in size: CGSize) -> Path {
        let reach = width * Self.swingRoom
        return Path(CGRect(x: size.width / 2 - reach, y: grabFrom, width: reach * 2, height: max(0, size.height - grabFrom)))
    }

    private func unitPoint(_ location: CGPoint) -> RibbonVector {
        let size = Self.canvasSize(length: length, width: width)
        return RibbonVector(x: Double((location.x - size.width / 2) / length), y: Double(location.y / length))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let target = unitPoint(value.location)
                if !box.isHeld {
                    box.isHeld = true
                    let depth = min(1, max(0.3, Double(value.startLocation.y / length)))
                    box.simulation.beginDrag(atDepth: depth, to: target)
                    Haptics.shared.beginStretch()
                } else {
                    box.simulation.updateDrag(to: target)
                }
                Haptics.shared.updateStretch(box.simulation.stretch)
                wake()
            }
            .onEnded { _ in
                box.isHeld = false
                box.simulation.endDrag()
                Haptics.shared.endStretch()
                wake()
            }
    }

    // MARK: Drawing

    private func draw(_ pose: RibbonPose, in context: inout GraphicsContext, size: CGSize) {
        let anchor = CGPoint(x: size.width / 2, y: 0)
        let points = pose.points.map { CGPoint(x: anchor.x + CGFloat($0.x) * length, y: anchor.y + CGFloat($0.y) * length) }
        guard points.count >= 2 else { return }
        let spine = Self.catmullRom(points, perSegment: 6)
        let outline = Self.outline(spine: spine, width: width, tailAngle: pose.tailAngle)

        // Soft shadow, then the satin, then its highlight.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.6))
            layer.translateBy(x: 1.2, y: 1.8)
            layer.fill(outline, with: .color(Color.coverShadow.opacity(0.22)))
        }
        context.fill(outline, with: .color(color))
        context.stroke(outline, with: .color(Color.black.opacity(0.12)), lineWidth: 0.5)

        let highlight = Self.highlight(spine: spine, width: width, curvature: pose.curvature)
        context.stroke(highlight.path, with: .color(Color.white.opacity(highlight.opacity)), style: StrokeStyle(lineWidth: width * 0.16, lineCap: .round))
    }

    /// A Catmull-Rom spline through `points`, sampled `perSegment` times per segment.
    static func catmullRom(_ points: [CGPoint], perSegment: Int) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result: [CGPoint] = []
        let n = points.count
        for i in 0..<(n - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, n - 1)]
            for s in 0..<perSegment {
                let t = CGFloat(s) / CGFloat(perSegment)
                let t2 = t * t
                let t3 = t2 * t
                let x = 0.5 * ((2 * p1.x) + (p2.x - p0.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (3 * p1.x - p0.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) + (p2.y - p0.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (3 * p1.y - p0.y - 3 * p2.y + p3.y) * t3)
                result.append(CGPoint(x: x, y: y))
            }
        }
        result.append(points[n - 1])
        return result
    }

    /// The unit normal at sample `index` of `spine`.
    private static func normal(_ spine: [CGPoint], at index: Int) -> CGPoint {
        let previous = spine[max(0, index - 1)]
        let next = spine[min(spine.count - 1, index + 1)]
        let dx = next.x - previous.x
        let dy = next.y - previous.y
        let length = max(0.0001, (dx * dx + dy * dy).squareRoot())
        return CGPoint(x: -dy / length, y: dx / length)
    }

    /// The strip around the spine, tapering a little, ending in a swallowtail notch that follows `tailAngle`.
    static func outline(spine: [CGPoint], width: CGFloat, tailAngle: Double) -> Path {
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        let last = max(1, spine.count - 1)
        for index in spine.indices {
            let n = normal(spine, at: index)
            let t = CGFloat(index) / CGFloat(last)
            let half = width * (0.5 - 0.06 * t)
            left.append(CGPoint(x: spine[index].x + n.x * half, y: spine[index].y + n.y * half))
            right.append(CGPoint(x: spine[index].x - n.x * half, y: spine[index].y - n.y * half))
        }
        // The cut end: corners reach past the spine's end along the tail's direction, the notch sits at the end.
        let end = spine[spine.count - 1]
        let direction = CGPoint(x: CGFloat(sin(tailAngle)), y: CGFloat(cos(tailAngle)))
        let side = CGPoint(x: -direction.y, y: direction.x)
        let half = width * 0.44
        let reach = width * 0.6
        let leftCorner = CGPoint(x: end.x + direction.x * reach + side.x * half, y: end.y + direction.y * reach + side.y * half)
        let rightCorner = CGPoint(x: end.x + direction.x * reach - side.x * half, y: end.y + direction.y * reach - side.y * half)

        var path = Path()
        path.move(to: left[0])
        for point in left.dropFirst() { path.addLine(to: point) }
        path.addLine(to: leftCorner)
        path.addLine(to: end)
        path.addLine(to: rightCorner)
        for point in right.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    /// A thin sheen that rides toward the outside of each bend; brighter where the ribbon curves more.
    static func highlight(spine: [CGPoint], width: CGFloat, curvature: [Double]) -> (path: Path, opacity: Double) {
        var path = Path()
        var strongest = 0.0
        let last = max(1, spine.count - 1)
        for index in spine.indices {
            let t = Double(index) / Double(last)
            let sample = curvature.isEmpty ? 0 : curvature[min(curvature.count - 1, Int((t * Double(curvature.count - 1)).rounded()))]
            strongest = max(strongest, abs(sample))
            let n = normal(spine, at: index)
            let offset = width * CGFloat(0.18 + 0.22 * sample)
            let point = CGPoint(x: spine[index].x + n.x * offset, y: spine[index].y + n.y * offset)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return (path, 0.16 + 0.22 * min(1, strongest))
    }
}

// MARK: - Previews

private struct RibbonPreview: View {
    @State private var tucked = false

    var body: some View {
        VStack(spacing: Space.xxl) {
            HStack(alignment: .top, spacing: Space.xxl) {
                BookCover(book: DemoData.hobbit, size: .l, ribbon: true, swaysRibbon: true)
                BookCover(book: DemoData.circe, size: .m, ribbon: true, ribbonTucked: tucked)
            }
            PhysicalRibbon(length: 220, width: 18, breathes: true, swaysOnAppear: true, isTucked: tucked)
                .frame(height: 260)
            Button(tucked ? "Untuck" : "Tuck away") { tucked.toggle() }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
    }
}

#Preview("Ribbon") {
    RibbonPreview()
}

#Preview("Ribbon · dark") {
    RibbonPreview()
        .preferredColorScheme(.dark)
}
