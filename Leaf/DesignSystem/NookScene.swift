import SwiftUI

/// The reading nook's scenes behind the session (the owner, 2026-10-22: "crisp photorealistic rain, fireplace and
/// landscape scenes, but also soft ethereal blurred stuff"). They sit outside the app's chrome, so they don't follow
/// Canopy's no-blur, no-glow rules; the session's controls on top still do. Plain is Canopy's own Dusk backdrop and the
/// default. Light only: a scene never makes a sound; the ambience is its own opt-in choice.
enum NookScene: String, CaseIterable, Identifiable {
    case plain
    // Realistic: a filmed loop where the app has one (`NookVideo`; the fireplace and every landscape), otherwise drawn
    // by Metal shaders (`NookShaders.swift`). The raw values are stored, so "landscape" stays the sunrise's.
    case rain, hearth, landscape
    // Landscapes added 2026-10-23 (the owner: "more beautiful nature landscape scenes, like a cloudy forest overview,
    // photorealistic"). Filmed only: without the file they show the plain backdrop.
    case forest, clouds, stars
    // Soft and dreamy, drawn by SwiftUI (`AtmosphereScene`, a drifting mesh).
    case glow, mist, drizzle

    /// The device-local choice (`@AppStorage`). Not synced: it's how this phone looks. A value saved by an earlier
    /// build that no longer exists ("lamp", "library") falls back to plain.
    static let storageKey = "leaf.cozy.nookScene"

    static let realistic: [NookScene] = [.rain, .hearth, .landscape, .forest, .clouds, .stars]
    static let soft: [NookScene] = [.glow, .mist, .drizzle]

    var id: String { rawValue }

    var name: String {
        switch self {
        case .plain: "Plain"
        case .rain: "Rain"
        case .hearth: "Fireplace"
        case .landscape: "Sunrise"
        case .forest: "Forest"
        case .clouds: "Clouds"
        case .stars: "Starlight"
        case .glow: "Glow"
        case .mist: "Mist"
        case .drizzle: "Drizzle"
        }
    }

    var blurb: String {
        switch self {
        case .plain: "Just the page and the timer."
        case .rain: "Rain on the window, the city lit up behind it."
        case .hearth: "A log fire crackling in a brick hearth."
        case .landscape: "The sun coming up over the mountains, mist lying in the valley."
        case .forest: "Morning mist drifting through a pine forest, seen from above."
        case .clouds: "Above a sea of clouds at dusk, a mountain’s shadow on the horizon."
        case .stars: "The Milky Way over a still lake, the far shore lit up."
        case .glow: "Soft lights drifting, out of focus."
        case .mist: "Slow colour, like light through fog."
        case .drizzle: "A soft rain, out of focus, on a blue evening."
        }
    }

    var symbol: String {
        switch self {
        case .plain: "circle.dashed"
        case .rain: "cloud.rain"
        case .hearth: "flame"
        case .landscape: "mountain.2"
        case .forest: "tree"
        case .clouds: "cloud"
        case .stars: "moon.stars"
        case .glow: "sparkles"
        case .mist: "cloud.fog"
        case .drizzle: "cloud.drizzle"
        }
    }

    /// Every scene but plain is an evening scene: the session's text and glass go light on it.
    var isDark: Bool { self != .plain }

    fileprivate var program: NookShaderProgram? {
        switch self {
        case .rain: .rain
        case .hearth: .hearth
        case .landscape: .landscape
        default: nil
        }
    }
}

// MARK: - Backdrop

/// A nook scene, full bleed, behind the session's timer and controls.
///
/// Cheap for a screen that stays awake: the realistic scenes are one shader pass at 2× scale; the soft ones are a
/// few soft shapes at 15 fps. Every one holds still when `calm` reaches 0 (a paused session), under Reduce Motion, in
/// Low Power Mode and while the app isn't active, and then stops drawing frames. A dark scrim behind the timer and the
/// controls keeps the text readable on any scene.
struct NookSceneBackdrop: View {
    let scene: NookScene
    var calm: Double = 1
    /// False for a still card: no timelines at all.
    var isLive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// A filmed loop plays only while the scene may move.
    private var videoPlays: Bool {
        isLive && calm > 0.001 && !reduceMotion && scenePhase == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        ZStack {
            Group {
                if let video = NookVideo.url(for: scene) {
                    ZStack {
                        if let poster = NookVideo.poster(for: scene) {
                            NookPosterView(image: poster)
                        } else {
                            Color.black
                        }
                        if isLive {
                            NookVideoView(url: video, isPlaying: videoPlays)
                        }
                    }
                } else if let program = scene.program {
                    NookShaderView(program: program, calm: calm, isLive: isLive)
                } else {
                    switch scene {
                    case .glow: NookGlowScene(calm: calm, isLive: isLive)
                    case .mist: NookMistScene(calm: calm, isLive: isLive)
                    case .drizzle: NookDrizzleScene(calm: calm, isLive: isLive)
                    default: CanopyBackdrop(accent: .dusk)
                    }
                }
            }
            .id(scene)
            .transition(.opacity)
            if scene.isDark {
                NookScrim()
            }
        }
        .animation(Canopy.Motion.smooth, value: scene)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A card of a scene, for pickers.
struct NookSceneThumbnail: View {
    let scene: NookScene
    var isSelected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Canopy.Radius.control, style: .continuous)
        NookSceneBackdrop(scene: scene, calm: 0, isLive: false)
            .aspectRatio(0.62, contentMode: .fit)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isSelected ? CanopyAccent.forest.color : Canopy.separator, lineWidth: isSelected ? 2.5 : 1)
            }
    }
}

/// Darkens the top half, where the timer's ring sits while a scene is on, and the bottom, where the controls are; the
/// band between is left to the scene.
private struct NookScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.5), location: 0),
                .init(color: Color.black.opacity(0.36), location: 0.2),
                .init(color: Color.black.opacity(0.16), location: 0.44),
                .init(color: Color.black.opacity(0), location: 0.58),
                .init(color: Color.black.opacity(0), location: 0.72),
                .init(color: Color.black.opacity(0.42), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Clock

/// The eased clock lives in a reference so the timeline can advance it while drawing without causing an update.
private final class NookClockBox {
    var clock = AtmosphereClock(calm: 1)
    var lastPhase = 0.0
}

/// A 15 fps phase for the soft scenes' own motion: the calm eases so nothing jumps, and the timeline stops once the
/// scene is held still, under Reduce Motion, in Low Power Mode or while the app isn't active.
private struct NookTimeline<Content: View>: View {
    var calm: Double
    var isLive: Bool
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

// MARK: - Soft scenes

/// Out-of-focus lights drifting over a warm dusk: two layers of bokeh, the far one larger and fainter.
private struct NookGlowScene: View {
    var calm: Double
    var isLive: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x1B1626), Color(hex: 0x2E1F2C), Color(hex: 0x4A2C26)],
                startPoint: .top,
                endPoint: .bottom
            )
            AtmosphereScene(kind: .bokeh, calm: isLive ? calm * 0.7 : 0, density: 8, tint: Color(hex: 0xF2B66B), seed: 0x6E0)
                .blur(radius: 10)
                .blendMode(.plusLighter)
            AtmosphereScene(kind: .bokeh, calm: isLive ? calm : 0, density: 14, tint: Color(hex: 0xFFD08A), seed: 0x6E1)
                .blur(radius: 2)
                .blendMode(.plusLighter)
        }
    }
}

/// Slow colour through fog: a 3×3 mesh in dusk colours whose inner points wander a few percent.
private struct NookMistScene: View {
    var calm: Double
    var isLive: Bool

    var body: some View {
        NookTimeline(calm: calm, isLive: isLive) { phase in
            mesh(at: phase)
        }
    }

    private func mesh(at time: Double) -> some View {
        func wander(_ seed: Double, _ reach: Double) -> Float {
            Float(sin(time * 2 * Double.pi / (17 + seed * 5) + seed * 3.1) * reach)
        }
        let points: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5 + wander(1, 0.08), 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.45 + wander(2, 0.07)), SIMD2<Float>(0.5 + wander(3, 0.1), 0.5 + wander(4, 0.08)), SIMD2<Float>(1, 0.55 + wander(5, 0.07)),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5 + wander(6, 0.08), 1), SIMD2<Float>(1, 1),
        ]
        let colors: [Color] = [
            Color(hex: 0x1C2238), Color(hex: 0x3B3560), Color(hex: 0x203845),
            Color(hex: 0x5C4A78), Color(hex: 0x9A7C9E), Color(hex: 0x3E6A72),
            Color(hex: 0x2A2236), Color(hex: 0x6E4A58), Color(hex: 0x1D2A33),
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors, smoothsColors: true)
    }
}

/// A soft rain on a blue evening: rain on glass (`AtmosphereScene(.rain)`) softened, over a few blurred lights.
private struct NookDrizzleScene: View {
    var calm: Double
    var isLive: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x111A26), Color(hex: 0x1F3040), Color(hex: 0x2D3B44)],
                startPoint: .top,
                endPoint: .bottom
            )
            AtmosphereScene(kind: .bokeh, calm: isLive ? calm * 0.4 : 0, density: 6, tint: Color(hex: 0xE7B27A), seed: 0xD21)
                .blur(radius: 14)
                .opacity(0.7)
            AtmosphereScene(kind: .rain, calm: isLive ? calm : 0, density: 90, tint: .steam, seed: 0xD22)
                .blur(radius: 1.2)
                .environment(\.colorScheme, .dark)
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
        .pickerStyle(.menu)
        .padding()
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

#Preview("Nook scenes · cards") {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
        ForEach(NookScene.allCases) { NookSceneThumbnail(scene: $0, isSelected: $0 == .hearth) }
    }
    .padding()
    .canopyBackdrop(.dusk)
}
