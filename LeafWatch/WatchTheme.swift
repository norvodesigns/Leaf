import SwiftUI
import WatchKit

/// Watch palette: "paper at night" — warm ink on black, one leaf-green accent.
enum WatchTheme {
    static let accent = Color(red: 0x8D / 255, green: 0xBB / 255, blue: 0x98 / 255)
    static let accentDeep = Color(red: 0x1E / 255, green: 0x33 / 255, blue: 0x26 / 255)
    static let paper = Color(red: 0xF1 / 255, green: 0xEA / 255, blue: 0xDC / 255)
    static let inkSecondary = Color(red: 0xB9 / 255, green: 0xB0 / 255, blue: 0x9F / 255)
    static let ribbon = Color(red: 0xE0 / 255, green: 0x69 / 255, blue: 0x4F / 255)
    static let track = Color.white.opacity(0.14)

    /// Generated-cover colours: the ten cover backgrounds from DESIGN.md §2, in the same order as the phone.
    static let covers: [Color] = [
        Color(hex: 0x6B2B26), Color(hex: 0x26375C), Color(hex: 0x2F4A3A), Color(hex: 0x3D4A52), Color(hex: 0x573247),
        Color(hex: 0x2D5D5B), Color(hex: 0x9A4A2C), Color(hex: 0xC48A2C), Color(hex: 0x9CAE94), Color(hex: 0xE9E0CD),
    ]

    static func cover(for seed: Int) -> Color { covers[abs(seed) % covers.count] }

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
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
            Circle().stroke(WatchTheme.track, lineWidth: lineWidth)
            Circle()
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
