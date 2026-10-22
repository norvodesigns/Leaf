import MetalKit
import QuartzCore
import SwiftUI

/// The realistic nook scenes, drawn by Metal fragment shaders: rain beading and running down a window over a city at
/// dusk, a fire burning in a stone fireplace, misty mountains at dawn. Everything is computed, so the app ships no
/// photos or video, and the shaders are compiled from source at run time (`MTLDevice.makeLibrary(source:)`), so the
/// build needs no Metal toolchain.
///
/// Cost: one full-screen triangle per frame at 2× scale (not the screen's 3×), 30 fps for rain and fire, 15 for the
/// landscape. The view stops drawing (its display link pauses) when the session is paused, under Reduce Motion, in Low
/// Power Mode and while the app isn't active; it then holds its last frame.
enum NookShaderProgram: String, CaseIterable {
    case rain, hearth, landscape

    var function: String { "nook_\(rawValue)" }
    var framesPerSecond: Int { self == .landscape ? 15 : 30 }
}

struct NookShaderView: UIViewRepresentable {
    let program: NookShaderProgram
    var calm: Double = 1
    /// False for a still card: one frame, no display link.
    var isLive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var mayMove: Bool {
        isLive && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled && scenePhase == .active
    }

    func makeCoordinator() -> NookShaderRenderer {
        NookShaderRenderer(program: program)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: NookShaderRenderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        view.contentScaleFactor = 2
        view.autoResizeDrawable = true
        view.delegate = context.coordinator
        view.isUserInteractionEnabled = false
        apply(to: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        apply(to: view, coordinator: context.coordinator)
    }

    private func apply(to view: MTKView, coordinator: NookShaderRenderer) {
        coordinator.program = program
        coordinator.calm = calm
        coordinator.isLive = mayMove
        view.preferredFramesPerSecond = program.framesPerSecond
        let moving = mayMove && (calm > 0.001 || coordinator.tempo > 0.001)
        if moving {
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        } else {
            // Hold still: draw once more (the eased clock settles), then only on request.
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            view.setNeedsDisplay()
        }
    }

    static func dismantleUIView(_ view: MTKView, coordinator: NookShaderRenderer) {
        view.isPaused = true
        view.delegate = nil
    }
}

/// Draws one program. The library and pipelines are built once per process and shared by every view.
final class NookShaderRenderer: NSObject, MTKViewDelegate {
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    private static let queue: MTLCommandQueue? = device?.makeCommandQueue()
    private static var pipelines: [NookShaderProgram: MTLRenderPipelineState] = [:]
    private static let library: MTLLibrary? = {
        guard let device else { return nil }
        let options = MTLCompileOptions()
        options.mathMode = .fast
        do {
            return try device.makeLibrary(source: NookShaderSource.text, options: options)
        } catch {
            #if DEBUG
            print("Nook shaders failed to compile: \(error)")
            #endif
            return nil
        }
    }()

    var program: NookShaderProgram
    var calm = 1.0
    var isLive = true
    private var clock = AtmosphereClock(calm: 1)
    /// Where a still scene rests, so a card or Reduce Motion shows a good moment.
    private let restingPhase = 23.0

    var tempo: Double { clock.tempo }

    init(program: NookShaderProgram) {
        self.program = program
    }

    private static func pipeline(for program: NookShaderProgram, format: MTLPixelFormat) -> MTLRenderPipelineState? {
        if let cached = pipelines[program] { return cached }
        guard let device, let library,
              let vertex = library.makeFunction(name: "nook_vertex"),
              let fragment = library.makeFunction(name: program.function) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = format
        guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        pipelines[program] = state
        return state
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        guard let queue = Self.queue,
              let pipeline = Self.pipeline(for: program, format: view.colorPixelFormat),
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let phase: Double
        if isLive {
            phase = restingPhase + clock.advance(to: CACurrentMediaTime(), calm: calm)
        } else {
            phase = restingPhase + clock.phase
        }
        var uniforms = NookShaderUniforms(
            resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: Float(phase.truncatingRemainder(dividingBy: 3600)),
            padding: 0
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NookShaderUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
        // Once a paused scene has eased to a stop, stop the display link.
        if calm <= 0.001, clock.tempo <= 0.001, !view.isPaused {
            DispatchQueue.main.async {
                view.isPaused = true
                view.enableSetNeedsDisplay = true
            }
        }
    }
}

/// Matches `NookUniforms` in the shader source: 16 bytes.
struct NookShaderUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var padding: Float
}

/// The Metal source. Every function is original to Leaf (no third-party shader code).
enum NookShaderSource {
    static let text = """
    #include <metal_stdlib>
    using namespace metal;

    struct NookUniforms {
        float2 resolution;
        float time;
        float padding;
    };

    struct NookVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    // A full-screen triangle; uv runs 0...1 across and 0 (top) ... 1 (bottom) down.
    vertex NookVertexOut nook_vertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        NookVertexOut out;
        out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        out.uv = float2(p.x, 1.0 - p.y);
        return out;
    }

    // MARK: Noise

    static float hash21(float2 p) {
        p = fract(p * float2(233.34, 851.73));
        p += dot(p, p + 23.45);
        return fract(p.x * p.y);
    }

    static float2 hash22(float2 p) {
        float n = hash21(p);
        return float2(n, hash21(p + n + 17.1));
    }

    static float noise2(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + float2(1.0, 0.0));
        float c = hash21(i + float2(0.0, 1.0));
        float d = hash21(i + float2(1.0, 1.0));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    static float fbm(float2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int i = 0; i < 5; i++) {
            v += a * noise2(p);
            p = p * 2.03 + float2(1.7, 9.2);
            a *= 0.5;
        }
        return v;
    }

    static float3 tonemap(float3 c) {
        return 1.0 - exp(-max(c, 0.0) * 1.25);
    }

    static float vignette(float2 uv) {
        float2 d = uv - 0.5;
        return 1.0 - dot(d, d) * 0.9;
    }

    // MARK: Rain on a window

    // The city at dusk behind the glass. blur 1 is out of focus (big soft discs with a brighter rim, like a lens);
    // blur near 0 is what a drop shows: the same lights as small sharp points.
    static float3 city(float2 uv, float aspect, float blur, float t) {
        float3 col = mix(float3(0.025, 0.035, 0.075), float3(0.10, 0.075, 0.15), smoothstep(0.0, 0.55, uv.y));
        col = mix(col, float3(0.30, 0.15, 0.10), smoothstep(0.5, 1.0, uv.y));
        float2 q = float2(uv.x * aspect, uv.y);
        for (int layer = 0; layer < 3; layer++) {
            float fl = float(layer);
            float scale = 6.0 + fl * 5.0;
            float2 g = q * scale;
            float drift = (layer == 1 ? -1.0 : 1.0) * t * (0.04 + 0.05 * fl);
            g.x += drift;
            float2 id = floor(g);
            float2 f = fract(g);
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    float2 cell = id + float2(float(dx), float(dy));
                    float h = hash21(cell + fl * 31.7);
                    float cellY = (cell.y + 0.5) / scale;
                    float presence = step(0.5, h) * smoothstep(0.32, 0.62, cellY);
                    if (presence <= 0.0) { continue; }
                    float2 center = float2(float(dx), float(dy)) + 0.2 + 0.6 * hash22(cell * 1.31 + fl);
                    float d = length(f - center);
                    float radius = mix(0.05, 0.42, blur) * (0.6 + 0.6 * fract(h * 7.3));
                    float edge = mix(0.015, radius * 0.22, blur);
                    float disc = 1.0 - smoothstep(radius - edge, radius, d);
                    float pick = fract(h * 13.1);
                    float3 tint = pick < 0.55 ? float3(1.0, 0.6, 0.26)
                        : (pick < 0.75 ? float3(1.0, 0.9, 0.78)
                        : (pick < 0.9 ? float3(1.0, 0.24, 0.16) : float3(0.4, 0.85, 0.95)));
                    float bright = (0.25 + 0.5 * fract(h * 3.7)) * mix(2.2, 0.5, blur);
                    float rim = smoothstep(radius * 0.55, radius, d) * 0.4 * blur;
                    col += tint * disc * bright * (1.0 + rim) * (1.0 - fl * 0.18);
                }
            }
        }
        return col;
    }

    struct NookDrop {
        float cover;
        float2 offset;
        float2 normal;
    };

    // Keeps the strongest drop over the point: a lens of radius r around c.
    static void lens(float2 p, float2 c, float2 r, float strength, thread NookDrop &drop) {
        float2 d = (p - c) / r;
        float l = length(d);
        if (l >= 1.0) { return; }
        float a = smoothstep(1.0, 0.82, l) * strength;
        if (a > drop.cover) {
            drop.cover = a;
            drop.offset = -d * r * 2.4;
            drop.normal = d;
        }
    }

    // Beads sitting on the glass: each appears, rests a while, and dries away.
    static void beads(float2 p, float t, thread NookDrop &drop) {
        float scale = 26.0;
        float2 id = floor(p * scale);
        float h = hash21(id + 4.1);
        if (h < 0.3) { return; }
        float life = fract(t * (0.015 + 0.03 * h) + h * 9.1);
        float alive = smoothstep(0.0, 0.06, life) * smoothstep(1.0, 0.9, life);
        float r = (0.1 + 0.24 * fract(h * 17.3)) * alive / scale;
        if (r < 0.0005) { return; }
        float2 c = (id + 0.5 + (hash22(id) - 0.5) * 0.5) / scale;
        lens(p, c, float2(r, r * 1.08), 1.0, drop);
    }

    // Drops running down: one per column at a time, moving in stick-and-slip bursts, wobbling, leaving a wet trail
    // with a few beads in it.
    static void runners(float2 p, float aspect, float t, thread NookDrop &drop) {
        float columns = 7.0;
        float col = floor(p.x / aspect * columns);
        float hc = hash21(float2(col, 7.7));
        float speed = 0.05 + 0.07 * hc;
        float s = t * speed + hc * 5.0;
        float cycle = floor(s);
        float hk = hash21(float2(col, cycle + 3.3));
        if (hk < 0.25) { return; }
        float progress = fract(s);
        float slip = progress + 0.07 * sin(progress * 6.28318 * 3.0);
        float headY = -0.1 + 1.25 * clamp(slip, 0.0, 1.0);
        float baseX = (col + 0.3 + 0.4 * hk) / columns * aspect;
        float r = (0.011 + 0.008 * hk);
        float wobble = 0.004 * sin(headY * 38.0 + hk * 10.0);
        lens(p, float2(baseX + wobble, headY), float2(r, r * 1.25), 1.0, drop);
        // The trail above it.
        float above = headY - p.y;
        float trailLength = 0.18 + 0.2 * hk;
        if (above > r && above < trailLength) {
            float x = baseX + 0.004 * sin(p.y * 38.0 + hk * 10.0);
            float fade = 1.0 - above / trailLength;
            float w = r * 0.32 * fade;
            float dx = (p.x - x) / max(w, 0.0001);
            if (abs(dx) < 1.0) {
                float a = 0.55 * fade * smoothstep(1.0, 0.6, abs(dx));
                if (a > drop.cover) {
                    drop.cover = a;
                    drop.offset = float2(-dx * w * 1.5, 0.0);
                    drop.normal = float2(dx, 0.0);
                }
            }
            // Beads left behind in the trail.
            float spacing = 0.03;
            float k = floor(p.y / spacing);
            float hb = hash21(float2(col * 13.0 + k, cycle));
            if (hb > 0.45) {
                float by = (k + 0.5) * spacing;
                float bx = baseX + 0.004 * sin(by * 38.0 + hk * 10.0);
                float br = r * (0.25 + 0.3 * hb) * fade;
                if (headY - by > r) {
                    lens(p, float2(bx, by), float2(br, br), 1.0, drop);
                }
            }
        }
    }

    fragment float4 nook_rain(NookVertexOut in [[stage_in]], constant NookUniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float t = u.time;
        float2 p = float2(uv.x * aspect, uv.y);
        NookDrop drop;
        drop.cover = 0.0;
        drop.offset = float2(0.0);
        drop.normal = float2(0.0);
        beads(p, t, drop);
        runners(p, aspect, t, drop);
        float3 behind = city(uv, aspect, 1.0, t);
        // A faint mist on the glass.
        behind = mix(behind, float3(0.12, 0.13, 0.17), 0.1);
        float3 col = behind;
        if (drop.cover > 0.0) {
            float2 ruv = uv + float2(drop.offset.x / aspect, drop.offset.y);
            float3 through = city(ruv, aspect, 0.1, t) * 1.1;
            float l = length(drop.normal);
            through *= 1.0 - smoothstep(0.55, 1.0, l) * 0.6;
            float spec = smoothstep(0.28, 0.0, length(drop.normal - float2(-0.35, -0.45)));
            through += float3(0.9, 0.92, 1.0) * spec * 0.55;
            col = mix(behind, through, drop.cover);
        }
        col = tonemap(col) * vignette(uv);
        return float4(col, 1.0);
    }

    // MARK: Fireplace

    static float roundedBox(float2 p, float2 halfSize, float radius) {
        float2 q = abs(p) - halfSize + radius;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    }

    static float3 fireRamp(float heat) {
        float3 c = float3(0.0);
        c += float3(1.0, 0.28, 0.04) * smoothstep(0.05, 0.4, heat);
        c += float3(0.0, 0.42, 0.14) * smoothstep(0.35, 0.72, heat);
        c += float3(0.0, 0.25, 0.45) * smoothstep(0.72, 1.0, heat);
        return c;
    }

    fragment float4 nook_hearth(NookVertexOut in [[stage_in]], constant NookUniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float t = u.time;
        // Room space: x centred, in screen heights; y up from the fire's base.
        float2 q = float2((uv.x - 0.5) * aspect, 0.86 - uv.y);
        float flicker = 0.82 + 0.12 * noise2(float2(t * 2.1, 0.5)) + 0.06 * noise2(float2(t * 6.3, 4.1));

        // The room: dark plaster lit warm from the fire, falling off with distance.
        float distFire = length(q - float2(0.0, 0.12));
        float3 col = float3(0.03, 0.022, 0.018) + float3(0.42, 0.19, 0.07) * flicker * exp(-distFire * 3.0);
        col *= 0.85 + 0.15 * fbm(uv * float2(aspect, 1.0) * 9.0);

        // The surround: a stone frame around the opening, a mantel shelf above, the hearth slab below.
        float halfWidth = min(0.42 * aspect, 0.3);
        float2 openingCentre = float2(0.0, 0.14);
        float2 openingHalf = float2(halfWidth * 0.8, 0.18);
        float opening = roundedBox(q - openingCentre, openingHalf, 0.06);
        float surround = roundedBox(q - openingCentre, openingHalf + 0.05, 0.08);
        if (surround < 0.0 && opening >= 0.0) {
            float stone = 0.6 + 0.4 * fbm(q * 22.0);
            float joints = smoothstep(0.0, 0.004, abs(fract(q.y * 14.0) - 0.5) - 0.47);
            col = float3(0.16, 0.13, 0.11) * stone * (1.0 - joints * 0.5);
            col += float3(0.5, 0.22, 0.08) * flicker * exp(-max(opening, 0.0) * 18.0) * 0.6;
        }
        float mantelTop = openingCentre.y + openingHalf.y + 0.08;
        if (q.y > mantelTop && q.y < mantelTop + 0.03 && abs(q.x) < halfWidth + 0.09) {
            float grain = 0.75 + 0.25 * noise2(float2(q.x * 60.0, q.y * 600.0));
            col = float3(0.2, 0.11, 0.06) * grain;
            col += float3(0.25, 0.12, 0.05) * flicker * smoothstep(mantelTop + 0.03, mantelTop, q.y) * 0.5;
        }
        if (q.y < -0.04 && q.y > -0.1 && abs(q.x) < halfWidth + 0.12) {
            col = float3(0.13, 0.11, 0.1) * (0.7 + 0.3 * fbm(q * 18.0)) + float3(0.35, 0.15, 0.05) * flicker * 0.5;
        }

        // Inside the opening: soot-dark firebrick lit from below, the flames, and two logs.
        if (opening < 0.0) {
            float2 b = q * float2(16.0, 32.0);
            b.x += step(1.0, fmod(floor(b.y), 2.0)) * 0.5;
            float2 bf = fract(b);
            float mortar = 1.0 - smoothstep(0.0, 0.06, min(min(bf.x, 1.0 - bf.x), min(bf.y, 1.0 - bf.y)) * 2.0);
            float3 brick = float3(0.12, 0.05, 0.03) * (0.7 + 0.3 * hash21(floor(b))) * (1.0 - mortar * 0.6);
            float glow = exp(-max(q.y, 0.0) * 5.0) * flicker;
            col = brick * (0.35 + 1.6 * glow);

            float h = q.y / 0.34;
            float side = abs(q.x) / (halfWidth * 0.62 * (1.0 - 0.5 * clamp(h, 0.0, 1.0)) + 0.0001);
            float turb = fbm(float2(q.x * 7.0, q.y * 5.0 - t * 2.4)) + 0.5 * fbm(float2(q.x * 15.0 + 5.0, q.y * 11.0 - t * 3.8));
            float heat = 1.3 - h * 1.15 - side * side * 0.85 + (turb - 0.75) * 1.25;
            heat = clamp(heat, 0.0, 1.0) * smoothstep(-0.02, 0.02, q.y);
            col += fireRamp(heat) * 1.7;

            // Logs, crossed low in the fire, with embers glowing in their cracks.
            for (int i = 0; i < 2; i++) {
                float s = i == 0 ? 1.0 : -1.0;
                float angle = s * 0.2;
                float2 lp = q - float2(-s * halfWidth * 0.18, 0.015 + 0.02 * float(i));
                float2 rp = float2(lp.x * cos(angle) + lp.y * sin(angle), -lp.x * sin(angle) + lp.y * cos(angle));
                float logShape = roundedBox(rp, float2(halfWidth * 0.5, 0.022), 0.02);
                if (logShape < 0.0) {
                    float bark = 0.5 + 0.5 * fbm(rp * float2(30.0, 120.0));
                    float cracks = pow(saturate(noise2(rp * float2(40.0, 70.0) + t * 0.3) * 1.3 - 0.35), 3.0);
                    float3 logColour = float3(0.07, 0.04, 0.025) * bark;
                    logColour += float3(1.0, 0.35, 0.06) * cracks * 3.0 * flicker * smoothstep(0.02, -0.02, rp.y);
                    col = mix(col, logColour, smoothstep(0.0, -0.004, logShape));
                }
            }
            // The ember bed.
            float bed = smoothstep(0.03, 0.0, abs(q.y - 0.0)) * smoothstep(halfWidth * 0.7, halfWidth * 0.3, abs(q.x));
            col += float3(1.0, 0.3, 0.05) * bed * (0.4 + 0.6 * noise2(float2(q.x * 50.0, t * 1.5))) * 0.8;
        }

        col = tonemap(col) * vignette(uv);
        return float4(col, 1.0);
    }

    // MARK: Mountains at dawn

    static float ridge(float x, float seed, float freq) {
        float v = 0.0;
        float a = 0.5;
        float f = freq;
        for (int i = 0; i < 5; i++) {
            v += a * (noise2(float2(x * f + seed, seed * 3.1)) * 2.0 - 1.0);
            f *= 2.1;
            a *= 0.48;
        }
        return v;
    }

    static float3 sky(float2 uv, float aspect, float t) {
        float3 col = mix(float3(0.16, 0.22, 0.38), float3(0.62, 0.5, 0.6), smoothstep(0.0, 0.42, uv.y));
        col = mix(col, float3(1.0, 0.72, 0.5), smoothstep(0.3, 0.56, uv.y));
        float2 sun = float2(0.7, 0.5);
        float2 d = float2((uv.x - sun.x) * aspect, uv.y - sun.y);
        float r = length(d);
        col += float3(1.0, 0.75, 0.5) * exp(-r * 6.0) * 0.6;
        col += float3(1.0, 0.92, 0.8) * smoothstep(0.03, 0.026, r);
        // Thin clouds catching the light, drifting.
        float2 cp = float2(uv.x * aspect * 2.0 + t * 0.006, uv.y * 7.0);
        float clouds = smoothstep(0.5, 0.78, fbm(cp)) * smoothstep(0.05, 0.25, uv.y) * smoothstep(0.48, 0.3, uv.y);
        col = mix(col, float3(1.0, 0.7, 0.62), clouds * 0.55);
        return col;
    }

    static float3 mountains(float2 uv, float aspect, float t) {
        float3 col = sky(uv, aspect, t);
        float3 haze = float3(0.95, 0.72, 0.62);
        for (int i = 0; i < 5; i++) {
            float fi = float(i);
            float base = 0.47 + fi * 0.06;
            float height = 0.13 - fi * 0.012;
            float y = base - height * (0.55 + 0.5 * ridge(uv.x * aspect, 11.0 + fi * 7.3, 1.3 + fi * 0.5));
            float depth = fi / 4.0;
            float3 rock = mix(float3(0.42, 0.36, 0.5), float3(0.07, 0.09, 0.11), depth);
            float3 layer = mix(rock, haze, (1.0 - depth) * 0.45);
            // Light on the faces toward the sun.
            float slope = ridge(uv.x * aspect + 0.01, 11.0 + fi * 7.3, 1.3 + fi * 0.5) - ridge(uv.x * aspect, 11.0 + fi * 7.3, 1.3 + fi * 0.5);
            layer += float3(0.3, 0.16, 0.08) * saturate(-slope * 60.0) * (1.0 - depth) * 0.6;
            float inside = smoothstep(y - 0.0015, y + 0.0015, uv.y);
            col = mix(col, layer, inside);
            // Mist pooling in the valley below each ridge, drifting slowly.
            float mist = fbm(float2(uv.x * aspect * 3.0 + t * 0.01 * (1.0 + fi), uv.y * 9.0 + fi * 4.0));
            float band = smoothstep(base + 0.06, base, uv.y) * smoothstep(base - 0.05, base + 0.02, uv.y);
            col = mix(col, haze * (1.05 - depth * 0.3), band * mist * 0.55 * (1.0 - depth * 0.5));
        }
        return col;
    }

    fragment float4 nook_landscape(NookVertexOut in [[stage_in]], constant NookUniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float t = u.time;
        float water = 0.8;
        float3 col;
        if (uv.y < water) {
            col = mountains(uv, aspect, t);
        } else {
            // A still lake: the scene mirrored, broken by slow ripples, darker and cooler.
            float depth = (uv.y - water) / (1.0 - water);
            float ripple = (noise2(float2(uv.x * aspect * 40.0, uv.y * 180.0 - t * 0.6)) - 0.5) * 0.006 * (0.3 + depth);
            float2 m = float2(uv.x + ripple, water - (uv.y - water) * 1.4);
            col = mountains(m, aspect, t) * float3(0.62, 0.66, 0.72);
            col = mix(col, float3(0.05, 0.07, 0.1), depth * 0.6);
        }
        col = tonemap(col * 1.1) * vignette(uv);
        return float4(col, 1.0);
    }
    """
}
