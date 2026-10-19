import SwiftUI

/// Today's reading as a cup of tea (NEXT.md section 4, "cup progress"): the cup fills as the day's minutes come in,
/// and steam rises when it is full or while a pot is steeping. Drawn in ink like an illustration on the page, so it
/// sits on paper without a shadow. Always show the real minutes beside it.
///
/// `fill` is 0...1. Steam drifts at about 15 fps from `AtmosphereField`; it holds still under Reduce Motion, in
/// Low Power Mode and when the app is not active, and loses its blur under Reduce Transparency.
struct TeaCup: View {
    var fill: Double
    var liquor: Color
    var steams: Bool = false
    /// The cup's width; the drawing is `width` × `height(for:)`, with the steam above it.
    var width: CGFloat = 96

    static func height(for width: CGFloat) -> CGFloat { width * 0.78 }

    /// Room above the rim for the steam.
    static func steamHeight(for width: CGFloat) -> CGFloat { width * 0.62 }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let height = Self.height(for: width)
        VStack(spacing: 0) {
            SteamWisps(isActive: steams)
                .frame(width: width * 0.62, height: Self.steamHeight(for: width))
                .offset(x: -width * 0.06)
                .opacity(steams ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: steams)
            ZStack {
                CupSaucer()
                    .stroke(Color.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                CupHandle()
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                CupBody()
                    .fill(Color.paperRaised)
                CupLiquid(level: fill)
                    .fill(liquor)
                    .clipShape(CupBody())
                    .animation(reduceMotion ? nil : Motion.board, value: fill)
                CupLiquidSurface(level: fill)
                    .stroke(Color.white.opacity(fill > 0.02 ? 0.35 : 0), lineWidth: 1)
                    .clipShape(CupBody())
                    .animation(reduceMotion ? nil : Motion.board, value: fill)
                CupBody()
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            .frame(width: width, height: height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shapes (unit drawing in the cup's frame)

/// The bowl of the cup, rim to foot.
struct CupBody: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.06, y: y + h * 0.18))
        path.addLine(to: CGPoint(x: x + w * 0.76, y: y + h * 0.18))
        path.addCurve(
            to: CGPoint(x: x + w * 0.56, y: y + h * 0.84),
            control1: CGPoint(x: x + w * 0.77, y: y + h * 0.58),
            control2: CGPoint(x: x + w * 0.68, y: y + h * 0.80)
        )
        path.addLine(to: CGPoint(x: x + w * 0.26, y: y + h * 0.84))
        path.addCurve(
            to: CGPoint(x: x + w * 0.06, y: y + h * 0.18),
            control1: CGPoint(x: x + w * 0.14, y: y + h * 0.80),
            control2: CGPoint(x: x + w * 0.05, y: y + h * 0.58)
        )
        path.closeSubpath()
        return path
    }
}

/// A loop of a handle on the right.
struct CupHandle: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.745, y: rect.minY + h * 0.30))
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.70, y: rect.minY + h * 0.62),
            control1: CGPoint(x: rect.minX + w * 0.98, y: rect.minY + h * 0.24),
            control2: CGPoint(x: rect.minX + w * 0.96, y: rect.minY + h * 0.62)
        )
        return path
    }
}

/// The saucer: a shallow curve under the foot.
struct CupSaucer: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.0, y: rect.minY + h * 0.86))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.86, y: rect.minY + h * 0.86),
            control: CGPoint(x: rect.minX + w * 0.43, y: rect.minY + h * 1.0)
        )
        return path
    }
}

/// The tea, from the foot up to `level` (0 empty, 1 a full cup just under the rim).
struct CupLiquid: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let top = Self.surfaceY(level: level, in: rect)
        return Path(CGRect(x: rect.minX, y: top, width: rect.width, height: max(0, rect.maxY - top)))
    }

    static func surfaceY(level: Double, in rect: CGRect) -> CGFloat {
        let clamped = min(1, max(0, level))
        let foot = rect.minY + rect.height * 0.84
        let brim = rect.minY + rect.height * 0.25
        return foot - CGFloat(clamped) * (foot - brim)
    }
}

/// A thin highlight where the tea meets the air.
struct CupLiquidSurface: Shape {
    var level: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let y = CupLiquid.surfaceY(level: level, in: rect)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: y + 0.5))
        path.addLine(to: CGPoint(x: rect.maxX, y: y + 0.5))
        return path
    }
}

// MARK: - Steam

/// Soft wisps rising from a cup, sampled from `AtmosphereField.steam` in a small `Canvas` at about 15 fps.
struct SteamWisps: View {
    var isActive: Bool
    var seed: UInt64 = 0x7EA

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    private var isAnimating: Bool {
        isActive && !reduceMotion && scenePhase == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isAnimating)) { context in
            let time = isAnimating ? context.date.timeIntervalSinceReferenceDate : 4.2
            Canvas { canvas, size in
                let wisps = AtmosphereField.steam(seed: seed, time: time, count: 5, calm: 1)
                for wisp in wisps where wisp.opacity > 0.01 {
                    var path = Path()
                    let x = wisp.x * size.width
                    let base = wisp.y * size.height
                    let length = size.height * 0.34
                    let sway = size.width * 0.08
                    path.move(to: CGPoint(x: x, y: base))
                    path.addCurve(
                        to: CGPoint(x: x + sway * 0.4, y: base - length),
                        control1: CGPoint(x: x - sway, y: base - length * 0.35),
                        control2: CGPoint(x: x + sway, y: base - length * 0.65)
                    )
                    let opacity = min(0.9, wisp.opacity * 2.2)
                    canvas.stroke(
                        path,
                        with: .color(CozyColor.steam.opacity(opacity)),
                        style: StrokeStyle(lineWidth: max(1.5, wisp.width * size.width * 0.5), lineCap: .round)
                    )
                }
            }
            .blur(radius: reduceTransparency ? 0 : 2.5)
        }
        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }
}

#Preview("Tea cup") {
    HStack(alignment: .bottom, spacing: 24) {
        TeaCup(fill: 0, liquor: CozyColor.liquor(for: TeaCatalog.earlGrey))
        TeaCup(fill: 0.48, liquor: CozyColor.liquor(for: TeaCatalog.earlGrey))
        TeaCup(fill: 1, liquor: CozyColor.liquor(for: TeaCatalog.earlGrey), steams: true)
    }
    .padding(24)
    .paperBackground()
}

#Preview("Tea cup · dark") {
    TeaCup(fill: 0.7, liquor: Color(hex: 0x8AA24C), steams: true, width: 140)
        .padding(24)
        .paperBackground()
        .preferredColorScheme(.dark)
}
