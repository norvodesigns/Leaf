import SwiftUI
import UIKit

/// The reading nook's scenes for the session screen (NEXT.md section 6, "Nook scenes"): a lamp on the page, rain on a
/// window at dusk, firelight from a hearth, out-of-focus shelves. Light only: a scene never makes a sound, and the
/// ambience (`AmbiencePlayer`) is chosen separately. Built from gradients, a few soft shapes and the blur scenes, never
/// photos, so they cost no assets.
enum NookScene: String, CaseIterable, Identifiable {
    case lamp, rain, hearth, library

    /// The device-local choice (`@AppStorage`), like the ambience's volume. Not synced: it's how this phone looks.
    static let storageKey = "leaf.cozy.nookScene"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .lamp: "Lamp"
        case .rain: "Rain"
        case .hearth: "Hearth"
        case .library: "Shelves"
        }
    }

    var blurb: String {
        switch self {
        case .lamp: "A pool of lamplight on the page."
        case .rain: "A window at dusk, rain on the glass."
        case .hearth: "Firelight from below, and the odd ember."
        case .library: "Shelves out of focus, a lamp in the corner."
        }
    }

    var symbol: String {
        switch self {
        case .lamp: "lamp.desk"
        case .rain: "cloud.rain"
        case .hearth: "flame"
        case .library: "books.vertical"
        }
    }
}

// MARK: - Backdrop

/// A nook scene, full bleed, behind the session's ring and controls.
///
/// Cheap by design: everything that doesn't move (the window, the shelves, the walls' light) is drawn once and only
/// composited after that; what moves (rain, the fire's flicker and embers, a few lights, the lamp's drift) runs at
/// about 15 fps and only in a small area. `calm` is the scene's energy (0 holds it still, as a paused session does),
/// and every moving part holds still under Reduce Motion, in Low Power Mode and when the app isn't active, at which
/// point its timeline stops drawing frames. Reduce Transparency drops the blur. A soft pool of paper sits behind the
/// middle of the screen so the timer reads on every scene, light or dark.
struct NookSceneBackdrop: View {
    let scene: NookScene
    var calm: Double = 1
    /// False for a still preview (the picker's cards): no timelines at all.
    var isLive: Bool = true

    var body: some View {
        ZStack {
            Color.paper
            Group {
                switch scene {
                case .lamp: NookLampScene(calm: calm, isLive: isLive)
                case .rain: NookRainScene(calm: calm, isLive: isLive)
                case .hearth: NookHearthScene(calm: calm, isLive: isLive)
                case .library: NookLibraryScene(calm: calm, isLive: isLive)
                }
            }
            .id(scene)
            .transition(.opacity)
            if scene != .lamp {
                NookReadingPool()
            }
        }
        .animation(.easeInOut(duration: 0.6), value: scene)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A still card of a scene, for pickers.
struct NookSceneThumbnail: View {
    let scene: NookScene
    var isSelected = false

    var body: some View {
        NookSceneBackdrop(scene: scene, calm: 0, isLive: false)
            .aspectRatio(0.62, contentMode: .fit)
            .clipShape(Radius.shape(Radius.tile))
            .overlay {
                Radius.shape(Radius.tile)
                    .strokeBorder(isSelected ? Color.accent : Color.hairline, lineWidth: isSelected ? 2 : 1)
            }
    }
}

/// Scene-only colours: the glass of a window at dusk, the wood of its frame, an ember's core. Atmosphere only.
private enum NookColor {
    static let duskHigh = Color(uiColor: UIColor.leafDynamic(light: 0xB7C3CA, dark: 0x141D26))
    static let duskLow = Color(uiColor: UIColor.leafDynamic(light: 0xDCD5C9, dark: 0x262629))
    static let wood = Color(uiColor: UIColor.leafDynamic(light: 0xA88B6A, dark: 0x3B3128))
    static let emberCore = Color(uiColor: UIColor.leafDynamic(light: 0xE59A3F, dark: 0xFFC27A))
}

/// The paper behind the ring and timer, so ink stays legible on any scene.
private struct NookReadingPool: View {
    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [Color.paper.opacity(0.78), Color.paper.opacity(0.5), Color.paper.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.44),
                startRadius: 0,
                endRadius: min(proxy.size.width, proxy.size.height) * 0.64
            )
        }
    }
}

// MARK: - Clock

/// The eased clock lives in a reference so the timeline can advance it while drawing without causing an update.
private final class NookClockBox {
    var clock = AtmosphereClock(calm: 1)
    var lastPhase = 0.0
}

/// A 15 fps phase for the nook's own motion, with `AtmosphereScene`'s rules: the calm eases so nothing jumps, and the
/// timeline stops once a scene is held still, under Reduce Motion, in Low Power Mode or while the app isn't active.
private struct NookTimeline<Content: View>: View {
    var calm: Double
    var isLive: Bool
    /// Where a still scene rests, so previews and Reduce Motion show a pleasant moment rather than phase 0.
    var restingPhase: Double = 7.5
    @ViewBuilder var content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var box = NookClockBox()
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var isHeld = false

    private var mayMove: Bool {
        isLive && !reduceMotion && !lowPower && scenePhase == .active
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !mayMove || isHeld)) { context in
            content(phase(at: context.date))
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: calm) { _, newCalm in
            if newCalm > 0.001 { isHeld = false }
        }
    }

    private func phase(at date: Date) -> Double {
        guard mayMove else { return box.lastPhase == 0 ? restingPhase : box.lastPhase }
        let phase = restingPhase + box.clock.advance(to: date.timeIntervalSinceReferenceDate, calm: calm)
        box.lastPhase = phase
        if calm <= 0.001, box.clock.tempo <= 0.001, !isHeld {
            // Fully still: pause the timeline after this frame.
            DispatchQueue.main.async { isHeld = true }
        }
        return phase
    }
}

// MARK: - Lamp

/// The original session light (DESIGN.md §6): a 3×3 mesh of paper with the lamp at the top centre, drifting a few
/// percent over twelve seconds.
private struct NookLampScene: View {
    var calm: Double
    var isLive: Bool

    var body: some View {
        NookTimeline(calm: calm, isLive: isLive, restingPhase: 0) { phase in
            mesh(at: phase)
        }
    }

    private func mesh(at time: Double) -> some View {
        let phase = time * 2 * Double.pi / 12
        let lampDrift = Float(sin(phase) * 0.03)
        let centreX = Float(0.5 + cos(phase * 0.7) * 0.03)
        let centreY = Float(0.5 + sin(phase * 0.5) * 0.03)
        let points: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5 + lampDrift, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.5), SIMD2<Float>(centreX, centreY), SIMD2<Float>(1, 0.5),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1),
        ]
        let colors: [Color] = [
            Color.paper, Color.lamp, Color.paper,
            Color.paper, Color.paper, Color.paper,
            Color.paper, Color.paper, Color.paper,
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
    }
}

// MARK: - Rain

/// A window at dusk in the upper half of the room: misty glass with a few far lights, a soft wooden frame, rain
/// trickling down (`AtmosphereScene(.rain)`, clipped to the glass so only that area animates), and a lamp low on the
/// left keeping the room warm.
private struct NookRainScene: View {
    var calm: Double
    var isLive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let window = CGRect(x: size.width * 0.1, y: size.height * 0.07, width: size.width * 0.8, height: size.height * 0.5)
            let corner = max(4, size.width * 0.04)
            ZStack(alignment: .topLeading) {
                RadialGradient(
                    colors: [Color.amber.opacity(0.24), Color.amber.opacity(0.08), .clear],
                    center: UnitPoint(x: 0.04, y: 0.86),
                    startRadius: 0,
                    endRadius: size.height * 0.55
                )
                glass(size: window.size)
                    .frame(width: window.width, height: window.height)
                    .clipShape(Radius.shape(corner))
                    .position(x: window.midX, y: window.midY)
                AtmosphereScene(kind: .rain, calm: calm, density: 54, seed: 0x7A1, holdsStill: !isLive)
                    .frame(width: window.width, height: window.height)
                    .clipShape(Radius.shape(corner))
                    .position(x: window.midX, y: window.midY)
                windowFrame(window: window, corner: corner, size: size)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    /// Dusk through misty glass: the sky, three far lights low down, and condensation along the bottom.
    private func glass(size: CGSize) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [NookColor.duskHigh, NookColor.duskLow]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            ))
            let lights: [(x: CGFloat, y: CGFloat, r: CGFloat, color: Color)] = [
                (0.22, 0.80, 0.10, Color.amber), (0.58, 0.86, 0.07, Color.rose), (0.82, 0.76, 0.12, Color.amber),
            ]
            for light in lights {
                let center = CGPoint(x: light.x * size.width, y: light.y * size.height)
                let radius = light.r * size.width
                let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: disc), with: .radialGradient(
                    Gradient(colors: [light.color.opacity(0.42), light.color.opacity(0.18), light.color.opacity(0)]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                ))
            }
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.16)]),
                startPoint: CGPoint(x: size.width / 2, y: size.height * 0.62),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            ))
        }
    }

    /// The frame, the glazing bars and the sill, slightly soft so they sit back behind the ring.
    private func windowFrame(window: CGRect, corner: CGFloat, size: CGSize) -> some View {
        let border = max(2, size.width * 0.022)
        let bar = max(1.5, size.width * 0.011)
        let sill = CGRect(x: window.minX - size.width * 0.03, y: window.maxY, width: window.width + size.width * 0.06, height: max(3, size.height * 0.022))
        return Canvas { context, _ in
            var bars = Path()
            bars.addRect(CGRect(x: window.midX - bar / 2, y: window.minY, width: bar, height: window.height))
            bars.addRect(CGRect(x: window.minX, y: window.minY + window.height * 0.46 - bar / 2, width: window.width, height: bar))
            context.fill(bars, with: .color(NookColor.wood.opacity(0.8)))
            context.stroke(
                Path(roundedRect: window, cornerRadius: corner, style: .continuous),
                with: .color(NookColor.wood.opacity(0.85)),
                lineWidth: border
            )
            context.fill(Path(roundedRect: sill, cornerRadius: sill.height / 3, style: .continuous), with: .color(NookColor.wood))
        }
        .blur(radius: reduceTransparency ? 0 : 1.2)
        .opacity(0.8)
    }
}

// MARK: - Hearth

/// Firelight from below: a warm glow rising from the bottom edge that breathes (`AtmosphereField.flicker`) and a few
/// embers drifting up through the lower half. Only the glow's opacity and a handful of dots change per frame.
private struct NookHearthScene: View {
    var calm: Double
    var isLive: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color.amber.opacity(0), location: 0.3),
                        .init(color: Color.amber.opacity(0.10), location: 0.7),
                        .init(color: Color.rooibos.opacity(0.16), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                NookTimeline(calm: calm, isLive: isLive) { phase in
                    ZStack {
                        glow(size: size)
                            .opacity(AtmosphereField.flicker(seed: 0xF12E, phase: phase))
                        embers(phase: phase)
                    }
                }
            }
        }
    }

    private func glow(size: CGSize) -> some View {
        ZStack {
            RadialGradient(
                colors: [Color.amber.opacity(0.46), Color.rooibos.opacity(0.24), Color.rooibos.opacity(0.06), .clear],
                center: UnitPoint(x: 0.5, y: 1.06),
                startRadius: 0,
                endRadius: size.height * 0.62
            )
            RadialGradient(
                colors: [NookColor.emberCore.opacity(0.42), .clear],
                center: UnitPoint(x: 0.5, y: 1.02),
                startRadius: 0,
                endRadius: size.width * 0.5
            )
        }
    }

    private func embers(phase: Double) -> some View {
        Canvas { context, size in
            let shorter = min(size.width, size.height)
            for ember in AtmosphereField.embers(seed: 0xE3B, phase: phase, count: 9, calm: calm) where ember.opacity > 0.01 {
                let center = CGPoint(x: CGFloat(ember.x) * size.width, y: CGFloat(ember.y) * size.height)
                let core = max(1, CGFloat(ember.radius) * shorter)
                let halo = core * 3.5
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - halo, y: center.y - halo, width: halo * 2, height: halo * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color.amber.opacity(ember.opacity * 0.45), Color.amber.opacity(0)]),
                        center: center,
                        startRadius: 0,
                        endRadius: halo
                    )
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
                    with: .color(NookColor.emberCore.opacity(ember.opacity))
                )
            }
        }
    }
}

// MARK: - Library

/// Shelves out of focus across the upper room (drawn once, blurred once), a lamp in the top corner and a few of its
/// lights drifting (`AtmosphereScene(.bokeh)`, kept small and slow). The shelves fade into paper by the middle.
private struct NookLibraryScene: View {
    var calm: Double
    var isLive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .top) {
                shelves
                    .mask {
                        LinearGradient(
                            stops: [.init(color: .black, location: 0.35), .init(color: .clear, location: 0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                RadialGradient(
                    colors: [Color.amber.opacity(0.30), Color.amber.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.88, y: 0.06),
                    startRadius: 0,
                    endRadius: size.height * 0.5
                )
                AtmosphereScene(kind: .bokeh, calm: calm * 0.6, density: 5, tint: .amber, seed: 0x11B, holdsStill: !isLive)
                    .frame(width: size.width, height: size.height * 0.5)
                    .opacity(0.8)
            }
        }
    }

    /// Four rows of spines on planks, seeded so they never change. Blurred once into the canvas's layer.
    private var shelves: some View {
        Canvas { context, size in
            context.drawLayer { layer in
                if !reduceTransparency {
                    layer.addFilter(.blur(radius: max(1.5, size.width * 0.012)))
                }
                let palette: [Color] = [.chai, .rooibos, .matcha, .steam, .rose, .amber, .ink]
                let rows = 4
                let top = size.height * 0.03
                let rowHeight = size.height * 0.16
                let plank = max(2, size.height * 0.011)
                var roll: UInt64 = 0
                func next() -> Double {
                    roll += 1
                    return InteractionMath.unit(0x5E1F, roll)
                }
                for row in 0..<rows {
                    let floor = top + CGFloat(row + 1) * rowHeight
                    var x = size.width * 0.02
                    while x < size.width * 0.98 {
                        let u = next()
                        if u < 0.07 {
                            // A gap on the shelf.
                            x += size.width * 0.05
                            continue
                        }
                        let width = size.width * CGFloat(0.026 + 0.03 * next())
                        let height = rowHeight * CGFloat(0.6 + 0.3 * next()) - plank
                        let color = palette[min(palette.count - 1, Int(next() * Double(palette.count)))]
                        let spine = CGRect(x: x, y: floor - plank - height, width: width * 0.92, height: height)
                        layer.fill(Path(roundedRect: spine, cornerRadius: min(2, width * 0.2)), with: .color(color.opacity(0.3)))
                        if next() < 0.5 {
                            let band = CGRect(x: spine.minX, y: spine.minY + height * 0.18, width: spine.width, height: max(1, height * 0.06))
                            layer.fill(Path(band), with: .color(Color.paper.opacity(0.35)))
                        }
                        x += width
                    }
                    let board = CGRect(x: 0, y: floor - plank, width: size.width, height: plank)
                    layer.fill(Path(board), with: .color(NookColor.wood.opacity(0.45)))
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Nook scenes") {
    @Previewable @State var scene = NookScene.rain
    ZStack {
        NookSceneBackdrop(scene: scene)
            .ignoresSafeArea()
        Picker("Scene", selection: $scene) {
            ForEach(NookScene.allCases) { Text($0.name).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding()
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

#Preview("Nook scenes · cards, dark") {
    HStack(spacing: 12) {
        ForEach(NookScene.allCases) { NookSceneThumbnail(scene: $0, isSelected: $0 == .hearth) }
    }
    .padding()
    .paperBackground()
    .preferredColorScheme(.dark)
}
