import SwiftUI

/// Spacing scale (DESIGN.md §4).
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let xxxl: CGFloat = 40
    static let section: CGFloat = 56

    /// Screen side margin.
    static let margin: CGFloat = 20
    /// Gap between sections.
    static let sectionGap: CGFloat = 40
    /// Minimum row height and hit target.
    static let hitTarget: CGFloat = 44
}

/// Corner radii (DESIGN.md §4). Always continuous: `Radius.shape(Radius.tile)` or
/// `.rect(cornerRadius: Radius.tile, style: .continuous)`. Buttons, chips and the accessory are capsules.
enum Radius {
    /// XS and S covers.
    static let coverSmall: CGFloat = 2
    /// M, L and XL covers.
    static let cover: CGFloat = 3
    static let tile: CGFloat = 16
    static let card: CGFloat = 22
    static let panel: CGFloat = 32

    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

/// A 1 px rule (`1 / displayScale`), horizontal by default.
struct Hairline: View {
    var color: Color
    var axis: Axis

    @Environment(\.displayScale) private var displayScale

    init(color: Color = .hairline, axis: Axis = .horizontal) {
        self.color = color
        self.axis = axis
    }

    var body: some View {
        let pixel = 1 / max(displayScale, 1)
        Rectangle()
            .fill(color)
            .frame(width: axis == .vertical ? pixel : nil, height: axis == .horizontal ? pixel : nil)
            .accessibilityHidden(true)
    }
}

/// The double rule: 1 pt `hairlineStrong`, a 2 pt gap, then a 1 px `hairline`.
struct DoubleRule: View {
    init() {}

    var body: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(Color.hairlineStrong)
                .frame(height: 1)
            Hairline()
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// The 20 pt screen side margin.
    func leafMargins() -> some View {
        padding(.horizontal, Space.margin)
    }
}

#Preview("Rules") {
    VStack(alignment: .leading, spacing: Space.l) {
        Text("Thursday 16 October").leafStyle(.eyebrow)
        DoubleRule()
        Hairline()
        Hairline(color: .hairlineStrong)
        HStack(spacing: Space.l) {
            Text("Left").leafStyle(.ui)
            Hairline(axis: .vertical).frame(height: 20)
            Text("Right").leafStyle(.ui)
        }
    }
    .leafMargins()
    .frame(maxHeight: .infinity)
    .paperBackground()
}
