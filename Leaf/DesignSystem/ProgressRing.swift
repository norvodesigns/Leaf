import SwiftUI

/// A goal ring: `hairline` track, `accent` fill, round caps, starting at 12 o'clock (DESIGN.md §5).
/// The session ring adds a `ribbon` head dot 1.6 × the line width.
///
/// Sizes: `ProgressRing.accessory(progress:)` 22/2.5, `ProgressRing.session(progress:)` 300/4.
/// Put content (a timer, a checkmark) on top with `.overlay { … }`.
struct ProgressRing: View {
    var progress: Double
    var diameter: CGFloat
    var lineWidth: CGFloat
    var showsHead: Bool
    var tint: Color
    var label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(progress: Double, diameter: CGFloat, lineWidth: CGFloat, showsHead: Bool = false, tint: Color = .accent, label: String = "Today’s reading") {
        self.progress = progress
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.showsHead = showsHead
        self.tint = tint
        self.label = label
    }

    /// 22 pt with a 2.5 pt line, for the session accessory.
    static func accessory(progress: Double, tint: Color = .accent) -> ProgressRing {
        ProgressRing(progress: progress, diameter: 22, lineWidth: 2.5, tint: tint)
    }

    /// 300 pt with a 4 pt line and the ribbon head, around the session timer.
    static func session(progress: Double, tint: Color = .accent) -> ProgressRing {
        ProgressRing(progress: progress, diameter: 300, lineWidth: 4, showsHead: true, tint: tint)
    }

    private var clamped: Double { min(1, max(0, progress.isFinite ? progress : 0)) }

    var body: some View {
        let inset = lineWidth / 2
        let headSize = lineWidth * 1.6
        ZStack {
            Circle()
                .inset(by: inset)
                .stroke(Color.hairline, lineWidth: lineWidth)
            Circle()
                .inset(by: inset)
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsHead {
                Circle()
                    .fill(Color.ribbon)
                    .frame(width: headSize, height: headSize)
                    .offset(y: -(diameter - lineWidth) / 2)
                    .rotationEffect(.degrees(360 * clamped))
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : Motion.paper, value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

#Preview("Rings") {
    VStack(spacing: Space.xxl) {
        HStack(spacing: Space.l) {
            ProgressRing.accessory(progress: 0.3)
            ProgressRing.accessory(progress: 1)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.accent)
                }
        }
        ProgressRing.session(progress: 0.42)
            .overlay {
                Text("14:32").leafStyle(.timer)
            }
    }
    .padding(Space.margin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperBackground()
}
