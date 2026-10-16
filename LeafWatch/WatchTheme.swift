import SwiftUI
import WatchKit

/// Watch palette: "paper at night" — warm ink on black, one leaf-green accent.
enum WatchTheme {
    static let accent = Color(red: 0x8D / 255, green: 0xBB / 255, blue: 0x98 / 255)
    static let accentDeep = Color(red: 0x2F / 255, green: 0x5A / 255, blue: 0x41 / 255)
    static let paper = Color(red: 0xF1 / 255, green: 0xEA / 255, blue: 0xDC / 255)
    static let inkSecondary = Color(red: 0xB9 / 255, green: 0xB0 / 255, blue: 0x9F / 255)
    static let ribbon = Color(red: 0xD9 / 255, green: 0x6A / 255, blue: 0x4E / 255)
    static let track = Color.white.opacity(0.14)

    /// Generated-cover colours, matching the phone's palette order.
    static let covers: [Color] = [
        Color(red: 0.24, green: 0.35, blue: 0.29), Color(red: 0.55, green: 0.27, blue: 0.20), Color(red: 0.18, green: 0.24, blue: 0.36),
        Color(red: 0.47, green: 0.38, blue: 0.20), Color(red: 0.33, green: 0.22, blue: 0.33), Color(red: 0.20, green: 0.33, blue: 0.36),
        Color(red: 0.42, green: 0.20, blue: 0.24), Color(red: 0.29, green: 0.31, blue: 0.20),
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
