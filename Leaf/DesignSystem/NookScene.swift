import SwiftUI

/// The reading nook's scenes for the session screen, on Canopy (docs/design/DESIGN_SYSTEM.md): the plain Dusk
/// backdrop by default, or a quiet drawing behind the timer: a window with rain, a reading lamp, a wall of shelves.
/// Crisp fine lines on cream, never blurred, no glow or bokeh, in the neutrals with a little Dusk (the session's
/// accent). Light only: a scene never makes a sound; the ambience is its own opt-in choice.
enum NookScene: String, CaseIterable, Identifiable {
    // Raw values keep a choice saved before Canopy ("rain", "lamp", "library"); anything else falls back to plain.
    case plain
    case window = "rain"
    case lamp
    case shelves = "library"

    /// The device-local choice (`@AppStorage`). Not synced: it's how this phone looks.
    static let storageKey = "leaf.cozy.nookScene"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .plain: "Plain"
        case .window: "Rain"
        case .lamp: "Lamp"
        case .shelves: "Shelves"
        }
    }

    var blurb: String {
        switch self {
        case .plain: "Just the page and the timer."
        case .window: "Rain running down a window."
        case .lamp: "A reading lamp and its pool of light."
        case .shelves: "A wall of books behind you."
        }
    }

    var symbol: String {
        switch self {
        case .plain: "circle.dashed"
        case .window: "cloud.rain"
        case .lamp: "lamp.floor"
        case .shelves: "books.vertical"
        }
    }
}

// MARK: - Backdrop

/// A nook scene, full bleed, behind the session's timer and controls.
///
/// Cheap: the drawings are static and render once; only the window's rain moves, at 15 fps inside the glass, and it
/// holds still when `calm` reaches 0 (a paused session), under Reduce Motion, in Low Power Mode and while the app is
/// in the background, at which point its timeline stops drawing frames.
struct NookSceneBackdrop: View {
    let scene: NookScene
    var calm: Double = 1
    /// False for a still card in a picker: no timeline at all.
    var isLive: Bool = true

    var body: some View {
        ZStack {
            CanopyBackdrop(accent: .dusk)
            Group {
                switch scene {
                case .plain: Color.clear
                case .window: NookWindowScene(calm: calm, isLive: isLive)
                case .lamp: NookLampScene()
                case .shelves: NookShelvesScene()
                }
            }
            .id(scene)
            .transition(.opacity)
        }
        .animation(Canopy.Motion.smooth, value: scene)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A still card of a scene, for pickers.
struct NookSceneThumbnail: View {
    let scene: NookScene
    var isSelected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Canopy.Radius.control, style: .continuous)
        NookSceneBackdrop(scene: scene, calm: 0, isLive: false)
            .aspectRatio(0.62, contentMode: .fit)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isSelected ? CanopyAccent.forest.color : Canopy.separator, lineWidth: isSelected ? 2 : 1)
            }
    }
}

/// The scenes' ink: fine lines a little darker than a hairline, so they read as a drawing and stay behind the timer.
private enum NookInk {
    static var line: Color { Canopy.textTertiary.opacity(0.45) }
    static var faint: Color { Canopy.separator }
    static var glass: Color { CanopyAccent.dusk.soft }
    static var rain: Color { CanopyAccent.dusk.color }

    /// A hairline that stays visible on small cards.
    static func width(_ size: CGSize, _ share: CGFloat = 0.004) -> CGFloat {
        max(0.75, min(size.width, size.height) * share)
    }
}

// MARK: - Clock

/// The eased clock lives in a reference so the timeline can advance it while drawing without causing an update.
private final class NookClockBox {
    var clock = AtmosphereClock(calm: 1)
    var lastPhase = 0.0
}

/// A 15 fps phase for the rain: the calm eases so nothing jumps, and the timeline stops once the scene is held still,
/// under Reduce Motion, in Low Power Mode or while the app isn't active.
private struct NookTimeline<Content: View>: View {
    var calm: Double
    var isLive: Bool
    /// Where a still scene rests, so cards and Reduce Motion show a pleasant moment rather than phase 0.
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

// MARK: - Rain

/// A tall window in the upper half: a Dusk-tinted pane, a fine frame with glazing bars and a sill, and rain as crisp
/// fine lines running down the glass (`AtmosphereField.rain`). Only the rain redraws, and only inside the pane.
private struct NookWindowScene: View {
    var calm: Double
    var isLive: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let pane = CGRect(x: size.width * 0.14, y: size.height * 0.08, width: size.width * 0.72, height: size.height * 0.42)
            let corner = max(4, size.width * 0.05)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(NookInk.glass)
                    .frame(width: pane.width, height: pane.height)
                    .position(x: pane.midX, y: pane.midY)
                NookTimeline(calm: calm, isLive: isLive) { phase in
                    rain(phase: phase)
                }
                .frame(width: pane.width, height: pane.height)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .position(x: pane.midX, y: pane.midY)
                windowFrame(pane: pane, corner: corner, size: size)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    private func rain(phase: Double) -> some View {
        Canvas { context, size in
            let line = NookInk.width(size, 0.006)
            for streak in AtmosphereField.rain(seed: 0x7A1, phase: phase, count: 34, calm: calm) {
                let x = CGFloat(streak.x) * size.width
                let head = CGFloat(streak.y) * size.height
                let length = CGFloat(streak.length) * size.height * 0.7
                var path = Path()
                path.move(to: CGPoint(x: x, y: head - length))
                path.addLine(to: CGPoint(x: x, y: head))
                context.stroke(
                    path,
                    with: .color(NookInk.rain.opacity(0.18 + streak.depth * 0.3)),
                    style: StrokeStyle(lineWidth: line * CGFloat(0.7 + streak.depth * 0.6), lineCap: .round)
                )
            }
        }
    }

    /// The frame, the glazing bars and the sill, in fine lines.
    private func windowFrame(pane: CGRect, corner: CGFloat, size: CGSize) -> some View {
        Canvas { context, _ in
            let line = NookInk.width(size)
            context.stroke(Path(roundedRect: pane, cornerRadius: corner, style: .continuous), with: .color(NookInk.line), lineWidth: line * 1.5)
            var bars = Path()
            bars.move(to: CGPoint(x: pane.midX, y: pane.minY))
            bars.addLine(to: CGPoint(x: pane.midX, y: pane.maxY))
            bars.move(to: CGPoint(x: pane.minX, y: pane.minY + pane.height * 0.46))
            bars.addLine(to: CGPoint(x: pane.maxX, y: pane.minY + pane.height * 0.46))
            context.stroke(bars, with: .color(NookInk.line), lineWidth: line)
            let sill = CGRect(x: pane.minX - size.width * 0.04, y: pane.maxY + line * 2, width: pane.width + size.width * 0.08, height: max(2, size.height * 0.01))
            context.stroke(Path(roundedRect: sill, cornerRadius: sill.height / 2, style: .continuous), with: .color(NookInk.line), lineWidth: line)
        }
    }
}

// MARK: - Lamp

/// A floor lamp drawn in fine lines at the right, its arm reaching over the timer, and the light it pours: a cone of
/// brighter cream (white on cream by day, a faint lift at night), sharp-edged and still.
private struct NookLampScene: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let line = NookInk.width(size)
            let shadeTop = CGPoint(x: w * 0.58, y: h * 0.16)
            let shade = Path { path in
                path.move(to: CGPoint(x: shadeTop.x - w * 0.06, y: shadeTop.y))
                path.addLine(to: CGPoint(x: shadeTop.x + w * 0.06, y: shadeTop.y))
                path.addLine(to: CGPoint(x: shadeTop.x + w * 0.11, y: shadeTop.y + h * 0.06))
                path.addLine(to: CGPoint(x: shadeTop.x - w * 0.11, y: shadeTop.y + h * 0.06))
                path.closeSubpath()
            }
            // The light: a soft-edged cone from the shade down past the timer.
            let mouth = shadeTop.y + h * 0.06
            let cone = Path { path in
                path.move(to: CGPoint(x: shadeTop.x - w * 0.11, y: mouth))
                path.addLine(to: CGPoint(x: shadeTop.x + w * 0.11, y: mouth))
                path.addLine(to: CGPoint(x: shadeTop.x + w * 0.42, y: h * 0.7))
                path.addLine(to: CGPoint(x: shadeTop.x - w * 0.52, y: h * 0.7))
                path.closeSubpath()
            }
            let light = colorScheme == .dark ? Canopy.text.opacity(0.06) : Color.white.opacity(0.7)
            context.fill(cone, with: .linearGradient(
                Gradient(colors: [light, light.opacity(0)]),
                startPoint: CGPoint(x: shadeTop.x, y: mouth),
                endPoint: CGPoint(x: shadeTop.x, y: h * 0.7)
            ))
            context.fill(shade, with: .color(CanopyAccent.dusk.soft))
            context.stroke(shade, with: .color(NookInk.line), lineWidth: line * 1.5)
            // The stand: an arm arcing from the pole to the shade, the pole, and a round foot.
            let poleX = w * 0.9
            var stand = Path()
            stand.move(to: CGPoint(x: shadeTop.x, y: shadeTop.y))
            stand.addQuadCurve(to: CGPoint(x: poleX, y: h * 0.2), control: CGPoint(x: shadeTop.x + w * 0.1, y: h * 0.06))
            stand.addLine(to: CGPoint(x: poleX, y: h * 0.86))
            context.stroke(stand, with: .color(NookInk.line), style: StrokeStyle(lineWidth: line * 1.5, lineCap: .round))
            let foot = CGRect(x: poleX - w * 0.07, y: h * 0.86 - h * 0.006, width: w * 0.14, height: h * 0.012)
            context.stroke(Path(ellipseIn: foot), with: .color(NookInk.line), lineWidth: line)
        }
    }
}

// MARK: - Shelves

/// A wall of shelves in the upper room, drawn once: books as outlined spines of seeded widths and heights, some filled
/// with a hairline tone, one leaning; the shelves fade out above the timer.
private struct NookShelvesScene: View {
    var body: some View {
        Canvas { context, size in
            let line = NookInk.width(size)
            let rowHeight = size.height * 0.135
            let top = size.height * 0.04
            var roll: UInt64 = 0
            func next() -> Double {
                roll += 1
                return InteractionMath.unit(0x5E1F, roll)
            }
            for row in 0..<3 {
                let floor = top + CGFloat(row + 1) * rowHeight
                var x = size.width * 0.06
                while x < size.width * 0.9 {
                    if next() < 0.08 {
                        x += size.width * 0.06
                        continue
                    }
                    let width = size.width * CGFloat(0.03 + 0.028 * next())
                    let height = rowHeight * CGFloat(0.58 + 0.3 * next())
                    let spine = CGRect(x: x, y: floor - height, width: width * 0.9, height: height)
                    let shape = Path(roundedRect: spine, cornerRadius: min(2, width * 0.15))
                    if next() < 0.35 { context.fill(shape, with: .color(NookInk.faint)) }
                    context.stroke(shape, with: .color(NookInk.line), lineWidth: line)
                    x += width
                }
                var shelf = Path()
                shelf.move(to: CGPoint(x: size.width * 0.03, y: floor))
                shelf.addLine(to: CGPoint(x: size.width * 0.97, y: floor))
                context.stroke(shelf, with: .color(NookInk.line), style: StrokeStyle(lineWidth: line * 1.5, lineCap: .round))
            }
        }
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0.3), .init(color: .clear, location: 0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Previews

#Preview("Nook scenes") {
    @Previewable @State var scene = NookScene.window
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
        ForEach(NookScene.allCases) { NookSceneThumbnail(scene: $0, isSelected: $0 == .lamp) }
    }
    .padding()
    .canopyBackdrop(.dusk)
    .preferredColorScheme(.dark)
}
