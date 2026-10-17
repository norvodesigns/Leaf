import SwiftUI

/// The thin row progress line: 2 pt `ink` on a `hairline` track (DESIGN.md §5).
struct ProgressBar: View {
    var progress: Double
    var tint: Color
    var height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(progress: Double, tint: Color = .ink, height: CGFloat = 2) {
        self.progress = progress
        self.tint = tint
        self.height = height
    }

    init(_ progress: Double, tint: Color = .ink, height: CGFloat = 2) {
        self.init(progress: progress, tint: tint, height: height)
    }

    private var clamped: Double { min(1, max(0, progress.isFinite ? progress : 0)) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hairline)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(clamped))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : Motion.paper, value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

#Preview("Progress bar") {
    VStack(spacing: Space.l) {
        ProgressBar(progress: 0.21)
        ProgressBar(progress: 0.66)
        ProgressBar(progress: 1, tint: .accent)
    }
    .padding(Space.margin)
    .paperBackground()
}
