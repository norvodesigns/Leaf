import SwiftUI

/// The colour of the hour behind Today's masthead (docs/design/DESIGN_SYSTEM.md §8, "Today's sky"): a soft wash that
/// changes with the day, peach at dawn, honey at noon, rose at tea time, dusk blue with a lamp's warmth at night,
/// fading into the cream page before the cards. It scrolls away with the nook; it is never behind text you read
/// for long, and Reduce Transparency keeps it but halves it.
///
/// While you look at it, the sky drifts: the soft band where the hour's colour meets the page rolls in a slow wave, a
/// warm blush wanders along it, and the lamp's light sways a little. The periods (13 to 31 seconds) never line up, so
/// it never visibly loops. Reduce Motion holds it still, and it stops drawing while it can't be seen.
struct TodaySky: View {
    let daypart: Daypart
    /// False while the sky can't be seen (scrolled away, another tab, the session over it), so it stops moving.
    var isAwake = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The sky's top, its middle, and the warm light low in the corner.
    private struct Tones {
        var top: UInt32
        var middle: UInt32
        var warmth: UInt32
    }

    private var tones: Tones {
        let dark = colorScheme == .dark
        switch daypart {
        case .dawn, .morning:
            return dark ? Tones(top: 0x3A3140, middle: 0x2B2A2E, warmth: 0x6B4A3A)
                        : Tones(top: 0xF4D8C6, middle: 0xF3E6D6, warmth: 0xF2C9A5)
        case .lunch, .afternoon:
            return dark ? Tones(top: 0x3B3528, middle: 0x2A2722, warmth: 0x5E4A2C)
                        : Tones(top: 0xF1E0BF, middle: 0xF4EADA, warmth: 0xEFD3A0)
        case .teaTime, .dusk:
            return dark ? Tones(top: 0x43303A, middle: 0x2C2528, warmth: 0x6E3F33)
                        : Tones(top: 0xEFCFC3, middle: 0xF2E3D8, warmth: 0xEDB99C)
        case .evening, .late, .smallHours:
            return dark ? Tones(top: 0x262C45, middle: 0x211F27, warmth: 0x5A3A2A)
                        : Tones(top: 0xD9D9EA, middle: 0xEDE6E2, warmth: 0xEFC6A4)
        }
    }

    var body: some View {
        let paused = reduceMotion || !isAwake || scenePhase != .active
        // Thirty frames a second is plenty for something this slow; Low Power Mode gets a third of that.
        let interval: Double = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 / 10 : 1 / 30
        TimelineView(.animation(minimumInterval: interval, paused: paused)) { timeline in
            sky(Drift(time: timeline.date.timeIntervalSinceReferenceDate, amount: reduceMotion ? 0 : 1))
        }
        .opacity(reduceTransparency ? 0.5 : 1)
        .mask(
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sky(_ drift: Drift) -> some View {
        let tones = tones
        let top = RGB(tones.top)
        let middle = RGB(tones.middle)
        let warmth = RGB(tones.warmth)
        let band = top.mixed(with: middle, 0.5)

        // Four columns by four rows: the top edge, the band where the colour meets the page, the page, then the page
        // fading out. The inner points roll in a wave that travels left to right; the edges stay on the edges.
        let columns: [Float] = [0, 1 / 3, 2 / 3, 1]
        let rows: [Float] = [0, 0.3, 0.58, 1]
        var points: [SIMD2<Float>] = []
        var colors: [Color] = []
        for (row, y) in rows.enumerated() {
            for (column, x) in columns.enumerated() {
                let c = Double(column)
                let r = Double(row)
                let innerColumn = column > 0 && column < columns.count - 1
                let innerRow = row > 0 && row < rows.count - 1
                var point = SIMD2<Float>(x, y)
                if innerColumn, row < rows.count - 1 {
                    point.x += Float(0.05 * drift.wave(period: 19, phase: c * 0.8 + r * 1.7))
                }
                if innerRow {
                    let lift = row == 1 ? 0.055 : 0.04
                    point.y += Float(lift * drift.wave(period: 13, phase: r * 0.6 - c * 1.1))
                }
                points.append(point)

                // A warm blush that wanders along the band, fainter at the top edge.
                let blush = drift.level(period: 23, phase: c * 1.9 + r * 0.7)
                switch row {
                case 0: colors.append(top.mixed(with: warmth, 0.2 * blush).color())
                case 1: colors.append(band.mixed(with: warmth, 0.35 * blush).color())
                case 2: colors.append(middle.mixed(with: warmth, 0.12 * blush).color())
                default: colors.append(middle.color(opacity: 0))
                }
            }
        }

        return ZStack {
            MeshGradient(width: columns.count, height: rows.count, points: points, colors: colors)
            // A lamp, or the sun, low and to the right: where the book and the cup sit. It sways a little.
            RadialGradient(
                colors: [warmth.color(opacity: 0.75), warmth.color(opacity: 0)],
                center: UnitPoint(x: CGFloat(0.85 + 0.04 * drift.wave(period: 29, phase: 0.4)), y: CGFloat(0.62 + 0.03 * drift.wave(period: 17, phase: 2.1))),
                startRadius: 0,
                endRadius: CGFloat(260 + 24 * drift.wave(period: 31, phase: 1.3))
            )
            .blendMode(colorScheme == .dark ? .screen : .multiply)
            .opacity(colorScheme == .dark ? 0.55 : 0.5)
        }
    }

    /// Where the sky is in its drift. With `amount` 0 every wave sits at rest, which is the still sky.
    private struct Drift {
        var time: Double
        var amount: Double

        /// -1...1, slowly, scaled by `amount`.
        func wave(period: Double, phase: Double) -> Double {
            amount * sin(2 * .pi * time / period + phase)
        }

        /// 0...1, resting at one half.
        func level(period: Double, phase: Double) -> Double {
            0.5 + 0.5 * wave(period: period, phase: phase)
        }
    }

    /// A tone as plain sRGB numbers, so two tones can be mixed.
    private struct RGB {
        var red: Double
        var green: Double
        var blue: Double

        init(_ hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }

        private init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        func mixed(with other: RGB, _ amount: Double) -> RGB {
            let t = min(1, max(0, amount))
            return RGB(red: red + (other.red - red) * t, green: green + (other.green - green) * t, blue: blue + (other.blue - blue) * t)
        }

        func color(opacity: Double = 1) -> Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
        }
    }
}

#Preview("Today's sky") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach([Daypart.morning, .afternoon, .teaTime, .evening], id: \.self) { part in
                TodaySky(daypart: part).frame(height: 300)
            }
        }
    }
    .background(Canopy.canvas)
}
