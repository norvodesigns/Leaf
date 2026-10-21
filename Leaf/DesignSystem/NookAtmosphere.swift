import SwiftUI

/// The light in the reading nook behind Today's header (NEXT.md sections 4 and 7): morning window light, the
/// afternoon's warm wash, the lamp coming on at dusk, a small pool of lamplight late at night. Built from gradients and
/// a few out-of-focus lights, never photos, and it fades into the paper at the bottom so the cards below sit on plain
/// paper.
///
/// Soft for what you feel: nothing here is interactive. The evening lights drift at about 15 fps and hold still under
/// Reduce Motion, in Low Power Mode and when the app is not active. Reduce Transparency gets a flat tint.
struct NookAtmosphere: View {
    let daypart: Daypart
    var seed: UInt64 = 0x4E00C

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase

    /// Where the light comes from and how strong it is, by time of day.
    struct Light: Equatable {
        /// The wash across the top of the scene.
        var wash: Color
        var washOpacity: Double
        /// The lamp or window glow.
        var glow: Color
        var glowOpacity: Double
        var glowCenter: UnitPoint
        /// 0...1 of the scene's longer side.
        var glowRadius: Double
        /// Out-of-focus lights (fairy lights, a candle), evenings only.
        var bokehCount: Int
        /// Window panes of light falling across the wall, mornings only.
        var showsWindow: Bool
    }

    static func light(for daypart: Daypart, dark: Bool) -> Light {
        switch daypart {
        case .dawn, .morning:
            return Light(wash: CozyColor.amber, washOpacity: dark ? 0.10 : 0.10, glow: CozyColor.steam, glowOpacity: dark ? 0.10 : 0.18,
                         glowCenter: UnitPoint(x: 0.85, y: 0.05), glowRadius: 0.75, bokehCount: 0, showsWindow: true)
        case .lunch, .afternoon:
            return Light(wash: CozyColor.amber, washOpacity: dark ? 0.12 : 0.14, glow: CozyColor.amber, glowOpacity: dark ? 0.16 : 0.18,
                         glowCenter: UnitPoint(x: 0.75, y: 0.0), glowRadius: 0.8, bokehCount: 0, showsWindow: true)
        case .teaTime, .dusk:
            return Light(wash: CozyColor.rooibos, washOpacity: dark ? 0.14 : 0.12, glow: CozyColor.amber, glowOpacity: dark ? 0.28 : 0.26,
                         glowCenter: UnitPoint(x: 0.82, y: 0.12), glowRadius: 0.7, bokehCount: 4, showsWindow: false)
        case .evening:
            return Light(wash: CozyColor.chai, washOpacity: dark ? 0.16 : 0.16, glow: CozyColor.amber, glowOpacity: dark ? 0.34 : 0.30,
                         glowCenter: UnitPoint(x: 0.84, y: 0.16), glowRadius: 0.62, bokehCount: 6, showsWindow: false)
        case .late, .smallHours:
            return Light(wash: Color.ink, washOpacity: dark ? 0.0 : 0.06, glow: CozyColor.amber, glowOpacity: dark ? 0.30 : 0.24,
                         glowCenter: UnitPoint(x: 0.86, y: 0.2), glowRadius: 0.48, bokehCount: 3, showsWindow: false)
        }
    }

    private var light: Light { Self.light(for: daypart, dark: colorScheme == .dark) }

    private var isAnimating: Bool {
        light.bokehCount > 0 && !reduceMotion && !reduceTransparency && scenePhase == .active
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        let light = self.light
        GeometryReader { proxy in
            let longest = max(proxy.size.width, proxy.size.height)
            ZStack {
                Color.paper
                LinearGradient(
                    colors: [light.wash.opacity(light.washOpacity), light.wash.opacity(light.washOpacity * 0.4), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if !reduceTransparency {
                    RadialGradient(
                        colors: [light.glow.opacity(light.glowOpacity), light.glow.opacity(light.glowOpacity * 0.35), .clear],
                        center: light.glowCenter,
                        startRadius: 0,
                        endRadius: longest * CGFloat(light.glowRadius)
                    )
                    if light.showsWindow {
                        windowLight(size: proxy.size)
                    }
                    if light.bokehCount > 0 {
                        bokeh(count: light.bokehCount, color: light.glow)
                    }
                }
                // Into the paper at the bottom, so the cards below sit on plain paper.
                LinearGradient(colors: [.clear, Color.paper], startPoint: UnitPoint(x: 0.5, y: 0.62), endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The colour along the scene's top edge, wash and all: what shows above it when Today is pulled down past the top.
    static func edge(daypart: Daypart) -> some View {
        NookEdge(daypart: daypart)
    }

    /// Four soft panes of light falling across the wall from a window to the right.
    private func windowLight(size: CGSize) -> some View {
        let pane = CGSize(width: size.width * 0.16, height: size.height * 0.22)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.035 : 0.30))
                    .frame(width: pane.width, height: pane.height)
                    .offset(
                        x: size.width * 0.58 + CGFloat(index % 2) * (pane.width + 8),
                        y: size.height * 0.05 + CGFloat(index / 2) * (pane.height + 8)
                    )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .rotationEffect(.degrees(-14), anchor: .topTrailing)
        .blur(radius: 16)
    }

    /// A few out-of-focus lights, drawn as soft discs (radial gradients, no blur filter) so a frame stays cheap.
    private func bokeh(count: Int, color: Color) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isAnimating)) { context in
            let time = isAnimating ? context.date.timeIntervalSinceReferenceDate : 12
            Canvas { canvas, size in
                let lights = AtmosphereField.bokeh(seed: seed, time: time, count: count, calm: 0.55)
                let shorter = min(size.width, size.height)
                for light in lights {
                    // Keep the lights in the upper right, around the lamp.
                    let center = CGPoint(x: size.width * CGFloat(0.45 + light.x * 0.55), y: size.height * CGFloat(light.y * 0.6))
                    let radius: CGFloat = max(6, CGFloat(light.radius) * shorter * 0.9)
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    let alpha: Double = min(0.5, light.opacity * 0.6)
                    let gradient = Gradient(stops: [
                        .init(color: color.opacity(alpha), location: 0),
                        .init(color: color.opacity(alpha * 0.8), location: 0.62),
                        .init(color: color.opacity(0), location: 1),
                    ])
                    canvas.fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius))
                }
            }
        }
    }
}

#Preview("Nook atmospheres") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach([Daypart.morning, .afternoon, .dusk, .evening, .late], id: \.self) { part in
                NookAtmosphere(daypart: part)
                    .frame(height: 220)
                    .overlay(alignment: .topLeading) {
                        Text(part.rawValue).leafStyle(.eyebrow).padding(20)
                    }
            }
        }
    }
    .paperBackground()
}

#Preview("Nook atmospheres · dark") {
    VStack(spacing: 0) {
        NookAtmosphere(daypart: .morning).frame(height: 240)
        NookAtmosphere(daypart: .evening).frame(height: 240)
        NookAtmosphere(daypart: .late).frame(height: 240)
    }
    .paperBackground()
    .preferredColorScheme(.dark)
}

/// The top edge of a nook's light, as a flat colour.
private struct NookEdge: View {
    let daypart: Daypart
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let light = NookAtmosphere.light(for: daypart, dark: colorScheme == .dark)
        ZStack {
            Color.paper
            light.wash.opacity(light.washOpacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
