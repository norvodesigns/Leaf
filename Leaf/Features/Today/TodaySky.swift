import SwiftUI

/// The colour of the hour behind Today's masthead (docs/design/DESIGN_SYSTEM.md, "Today's sky"): a soft wash that
/// changes with the day, peach at dawn, honey at noon, rose at tea time, dusk blue with a lamp's warmth at night,
/// fading into the cream page before the cards. It scrolls away with the nook; it is never behind text you read
/// for long, and Reduce Transparency keeps it but halves it.
struct TodaySky: View {
    let daypart: Daypart

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
        let tones = tones
        let strength = reduceTransparency ? 0.5 : 1.0
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: tones.top), location: 0),
                    .init(color: Color(hex: tones.middle), location: 0.55),
                    .init(color: Color(hex: tones.middle).opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // A lamp, or the sun, low and to the right: where the book and the cup sit.
            RadialGradient(
                colors: [Color(hex: tones.warmth).opacity(0.75), Color(hex: tones.warmth).opacity(0)],
                center: UnitPoint(x: 0.85, y: 0.62),
                startRadius: 0,
                endRadius: 260
            )
            .blendMode(colorScheme == .dark ? .screen : .multiply)
            .opacity(colorScheme == .dark ? 0.55 : 0.5)
        }
        .opacity(strength)
        .mask(
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
