import SwiftUI

/// A fact on a raised paper tile: `statNumeral` over an `eyebrow` (DESIGN.md §5). `paperRaised`,
/// 1 px `hairline` stroke, `Radius.tile`, 14 pt padding, at least 84 pt tall.
/// Lay several out with `StatTileRow`.
struct StatTile: View {
    let value: String
    let label: String

    @Environment(\.statTileFillsHeight) private var fillsHeight
    @Environment(\.displayScale) private var displayScale

    /// - Parameters:
    ///   - value: the numeral, e.g. "310" or "6 h 22 m".
    ///   - label: sentence case, e.g. "Pages"; shown as an eyebrow.
    init(value: String, label: String) {
        self.value = value
        self.label = label
    }

    init(_ value: String, label: String) {
        self.init(value: value, label: label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(value)
                .leafStyle(.statNumeral)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .leafStyle(.eyebrow)
                .lineLimit(2)
        }
        .padding(14)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 84, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .background(Color.paperRaised, in: Radius.shape(Radius.tile))
        .overlay {
            Radius.shape(Radius.tile)
                .strokeBorder(Color.hairline, lineWidth: 1 / max(displayScale, 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Three tiles to a row with 8 pt gaps and equal heights; stacked at accessibility sizes.
struct StatTileRow<Content: View>: View {
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Space.s))
        layout {
            content
        }
        .environment(\.statTileFillsHeight, true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StatTileFillsHeightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set by `StatTileRow` so its tiles share one height.
    var statTileFillsHeight: Bool {
        get { self[StatTileFillsHeightKey.self] }
        set { self[StatTileFillsHeightKey.self] = newValue }
    }
}

#Preview("Stat tiles") {
    VStack(spacing: Space.l) {
        StatTileRow {
            StatTile(value: "310", label: "Pages")
            StatTile(value: "95K", label: "Words")
            StatTile(value: "6 h 22 m", label: "At your pace")
        }
        StatTile(value: "248", label: "Words a minute")
    }
    .leafMargins()
    .frame(maxHeight: .infinity)
    .paperBackground()
}
