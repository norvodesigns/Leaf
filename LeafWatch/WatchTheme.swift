import SwiftUI
import WatchKit

/// Watch palette: Canopy on black (docs/design/REDESIGN.md §4.11). The Oat palette's dark tokens: cream text, sage
/// green as the ink you act with, Dusk for reading and time, Clay for tea.
enum WatchTheme {
    /// Forest (Oat, dark): progress, done, the action you take.
    static let accent = Color(red: 0xA9 / 255, green: 0xCD / 255, blue: 0xB2 / 255)
    /// A deep sage behind the Today page, fading to black.
    static let accentDeep = Color(red: 0x1F / 255, green: 0x2C / 255, blue: 0x24 / 255)
    /// The label on an accent button: deep green on the sage, about 10:1 (white on it is barely 2:1).
    static let onAccent = Color(red: 0x0E / 255, green: 0x1A / 255, blue: 0x12 / 255)
    /// Text: Oat's cream.
    static let paper = Color(red: 0xF2 / 255, green: 0xEA / 255, blue: 0xDA / 255)
    static let inkSecondary = Color(red: 0xB5 / 255, green: 0xAB / 255, blue: 0x99 / 255)
    /// Dusk: reading and time, "now" (the live dot, the next reading time).
    static let dusk = Color(red: 0xA9 / 255, green: 0xB5 / 255, blue: 0xF2 / 255)
    /// Kept for the places that mark "now"; it is Dusk in Canopy.
    static let ribbon = dusk
    static let track = Color.white.opacity(0.14)
    /// Clay: tea, the cup and the steep timer.
    static let tea = Color(red: 0xEB / 255, green: 0x9C / 255, blue: 0x74 / 255)
    /// Raised rows: Oat's dark surface, warm charcoal rather than black.
    static let warm = Color(red: 0x26 / 255, green: 0x23 / 255, blue: 0x1F / 255)

    /// Generated-cover colours: the ten cover backgrounds from DESIGN.md §2, in the same order as the phone.
    static let covers: [Color] = [
        Color(hex: 0x6B2B26), Color(hex: 0x26375C), Color(hex: 0x2F4A3A), Color(hex: 0x3D4A52), Color(hex: 0x573247),
        Color(hex: 0x2D5D5B), Color(hex: 0x9A4A2C), Color(hex: 0xC48A2C), Color(hex: 0x9CAE94), Color(hex: 0xE9E0CD),
    ]

    static func cover(for seed: Int) -> Color { covers[abs(seed) % covers.count] }

    /// Numerals: rounded, as everywhere in Canopy.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .rounded) }
    /// The greeting and book titles: literary.
    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

enum WatchHaptics {
    static func play(_ type: WKHapticType) { WKInterfaceDevice.current().play(type) }
}

/// A slim ring for today's goal.
struct GoalRing: View {
    var progress: Double
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            // Inset by half the line, so the stroke stays inside the frame and never meets the screen's rounded edge.
            Circle().inset(by: lineWidth / 2).stroke(WatchTheme.track, lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(WatchTheme.accent.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)
        }
    }
}

/// A thin reading-progress bar.
struct ProgressLine: View {
    var progress: Double
    var color: Color = WatchTheme.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WatchTheme.track)
                Capsule().fill(color).frame(width: max(3, proxy.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 4)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
