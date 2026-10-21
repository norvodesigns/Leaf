import SwiftUI

/// The soft scenes of the blur language (NEXT.md section 7), drawn from `AtmosphereField` in a `Canvas` at about
/// 15 fps: out-of-focus lights, rain trickling down glass, steam off a cup.
///
/// `calm` is the scene's energy, 0...1: 1 is the normal gentle drift, lower slows everything, 0 holds still (a paused
/// session). An `AtmosphereClock` eases between calms so nothing jumps, and once the scene is fully still the
/// `TimelineView` pauses, so a held scene costs nothing per frame. It also holds still under Reduce Motion, in Low Power
/// Mode and when the app isn't active; Reduce Transparency draws the same shapes without blur.
struct AtmosphereScene: View {
    enum Kind: String, CaseIterable, Identifiable {
        case bokeh, rain, steam

        var id: String { rawValue }
    }

    let kind: Kind
    var calm: Double = 1
    /// How many elements: lights, streaks or wisps.
    var density: Int?
    var tint: Color = .amber
    var seed: UInt64 = 0x5EED
    /// Draws one still frame and never runs a timeline (a picker's preview card).
    var holdsStill = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = ClockBox()
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// True once calm is 0 and the clock has eased to a stop: the timeline pauses.
    @State private var isHeld = false

    /// The clock lives in a reference so the timeline can advance it while drawing without causing an update.
    private final class ClockBox {
        var clock = AtmosphereClock(calm: 1)
        var lastPhase = 0.0
    }

    private var count: Int {
        if let density { return density }
        switch kind {
        case .bokeh: return 9
        case .rain: return 70
        case .steam: return 6
        }
    }

    /// Motion is allowed at all.
    private var mayMove: Bool {
        !holdsStill && !reduceMotion && !lowPower && scenePhase == .active
    }

    /// Paused once the scene is held still and the clock has caught up, so a still scene does no per-frame work.
    private var isPaused: Bool {
        !mayMove || isHeld
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: isPaused)) { context in
            let phase = currentPhase(at: context.date)
            Canvas { canvas, size in
                switch kind {
                case .bokeh: drawBokeh(in: &canvas, size: size, phase: phase)
                case .rain: drawRain(in: &canvas, size: size, phase: phase)
                case .steam: drawSteam(in: &canvas, size: size, phase: phase)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: calm) { _, newCalm in
            if newCalm > 0.001 { isHeld = false }
        }
    }

    /// Advances the eased clock to `date` (only while motion is allowed) and returns the scene phase to draw.
    private func currentPhase(at date: Date) -> Double {
        guard mayMove else { return clock.lastPhase == 0 ? 7.5 : clock.lastPhase }
        let phase = clock.clock.advance(to: date.timeIntervalSinceReferenceDate, calm: calm)
        clock.lastPhase = phase
        if calm <= 0.001, clock.clock.tempo <= 0.001, !isHeld {
            // Fully still: pause the timeline after this frame.
            DispatchQueue.main.async { isHeld = true }
        }
        return phase
    }

    // MARK: Bokeh

    private func drawBokeh(in canvas: inout GraphicsContext, size: CGSize, phase: Double) {
        let lights = AtmosphereField.bokeh(seed: seed, phase: phase, count: count, calm: calm)
        let shorter = min(size.width, size.height)
        for light in lights {
            let center = CGPoint(x: CGFloat(light.x) * size.width, y: CGFloat(light.y) * size.height)
            let radius = max(4, CGFloat(light.radius) * shorter)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let alpha = min(0.6, light.opacity)
            let hue = light.hueOffset
            let color = hue > 0.3 ? Color.rose : (hue < -0.3 ? Color.chai : tint)
            if reduceTransparency {
                canvas.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha * 0.5)))
            } else {
                // A bokeh disc: nearly flat, with a slightly brighter rim, fading out at the very edge.
                let gradient = Gradient(stops: [
                    .init(color: color.opacity(alpha * 0.75), location: 0),
                    .init(color: color.opacity(alpha * 0.85), location: 0.78),
                    .init(color: color.opacity(alpha * 0.4), location: 0.92),
                    .init(color: color.opacity(0), location: 1),
                ])
                canvas.fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))
            }
        }
    }

    // MARK: Rain on glass

    private func drawRain(in canvas: inout GraphicsContext, size: CGSize, phase: Double) {
        let streaks = AtmosphereField.rain(seed: seed, phase: phase, count: count, calm: calm)
        // Far layers first, softer; near layers last, sharper, with a bright refracting edge.
        for layer in 0...2 {
            canvas.drawLayer { context in
                if !reduceTransparency {
                    context.addFilter(.blur(radius: CGFloat(2 - layer) * 1.4 + 0.3))
                }
                for streak in streaks where streak.layer == layer {
                    let x = CGFloat(streak.x) * size.width
                    let head = CGFloat(streak.y) * size.height
                    let length = CGFloat(streak.length) * size.height
                    let width = max(0.8, CGFloat(streak.width) * size.width)
                    // The trail: a thin wet line that fades out behind the drop.
                    let trailWidth = width * (layer == 2 ? 0.5 : 0.75)
                    var trail = Path()
                    trail.move(to: CGPoint(x: x - trailWidth / 2, y: head - width * 0.4))
                    trail.addLine(to: CGPoint(x: x + trailWidth / 2, y: head - width * 0.4))
                    trail.addLine(to: CGPoint(x: x + trailWidth * 0.15, y: head - length))
                    trail.addLine(to: CGPoint(x: x - trailWidth * 0.15, y: head - length))
                    trail.closeSubpath()
                    context.fill(
                        trail,
                        with: .linearGradient(
                            Gradient(colors: [Color.steam.opacity(0), Color.steam.opacity(streak.opacity * 0.75)]),
                            startPoint: CGPoint(x: x, y: head - length),
                            endPoint: CGPoint(x: x, y: head)
                        )
                    )
                    guard layer > 0 else { continue }
                    // The drop: a lens that is lit on one side, rimmed on the other, with a glint.
                    let radius = width * (layer == 2 ? 1.25 : 0.85)
                    let drop = Path(ellipseIn: CGRect(x: x - radius, y: head - radius * 1.3, width: radius * 2, height: radius * 2.3))
                    context.fill(
                        drop,
                        with: .radialGradient(
                            Gradient(colors: [Color.white.opacity(streak.opacity * 0.45), Color.steam.opacity(streak.opacity * 0.2)]),
                            center: CGPoint(x: x - radius * 0.3, y: head - radius * 0.6),
                            startRadius: 0,
                            endRadius: radius * 1.6
                        )
                    )
                    context.stroke(drop, with: .color(Color.black.opacity(streak.opacity * 0.2)), lineWidth: max(0.4, radius * 0.16))
                    if layer == 2 {
                        let glint = CGRect(x: x - radius * 0.55, y: head - radius * 0.9, width: radius * 0.45, height: radius * 0.6)
                        context.fill(Path(ellipseIn: glint), with: .color(Color.white.opacity(streak.opacity * 0.85)))
                    }
                }
            }
        }
    }

    // MARK: Steam

    private func drawSteam(in canvas: inout GraphicsContext, size: CGSize, phase: Double) {
        let wisps = AtmosphereField.steam(seed: seed, phase: phase, count: count, calm: max(0.2, calm))
        canvas.drawLayer { context in
            if !reduceTransparency { context.addFilter(.blur(radius: 3)) }
            for wisp in wisps where wisp.opacity > 0.01 {
                let x = CGFloat(wisp.x) * size.width
                let base = CGFloat(wisp.y) * size.height
                let length = size.height * 0.3
                let sway = size.width * 0.07
                var path = Path()
                path.move(to: CGPoint(x: x, y: base))
                path.addCurve(
                    to: CGPoint(x: x + sway * 0.4, y: base - length),
                    control1: CGPoint(x: x - sway, y: base - length * 0.35),
                    control2: CGPoint(x: x + sway, y: base - length * 0.65)
                )
                let width: CGFloat = max(2, CGFloat(wisp.width) * size.width * 0.6)
                context.stroke(path, with: .color(Color.steam.opacity(min(0.9, wisp.opacity * 2.2))), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }
}

#Preview("Scenes") {
    @Previewable @State var calm = 1.0
    VStack(spacing: 0) {
        AtmosphereScene(kind: .bokeh, calm: calm)
            .frame(height: 220)
            .background(Color.lamp)
        AtmosphereScene(kind: .rain, calm: calm)
            .frame(height: 220)
            .background(LinearGradient(colors: [Color(hex: 0x2B3A4A), Color(hex: 0x14181F)], startPoint: .top, endPoint: .bottom))
        AtmosphereScene(kind: .steam, calm: calm)
            .frame(height: 160)
        Slider(value: $calm, in: 0...1)
            .padding()
    }
    .paperBackground()
}

#Preview("Scenes · dark") {
    VStack(spacing: 0) {
        AtmosphereScene(kind: .bokeh, calm: 0.6)
        AtmosphereScene(kind: .steam)
    }
    .paperBackground()
    .preferredColorScheme(.dark)
}
