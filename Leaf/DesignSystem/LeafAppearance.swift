import UIKit

/// App-wide UIKit appearance. `LeafApp.init` calls `configure()` once.
@MainActor
enum LeafAppearance {
    static func configure() {
        let largeTitle = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: UIFont(name: LeafFontName.regular, size: 40) ?? .systemFont(ofSize: 34, weight: .bold),
            maximumPointSize: 64
        )
        let inlineTitle = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: newYork(size: 17, weight: .semibold),
            maximumPointSize: 28
        )

        let largeAttributes: [NSAttributedString.Key: Any] = [
            .font: largeTitle,
            .foregroundColor: LeafUIColor.ink,
            .kern: -0.5,
        ]
        let inlineAttributes: [NSAttributedString.Key: Any] = [
            .font: inlineTitle,
            .foregroundColor: LeafUIColor.ink,
        ]

        // Keep the system's iOS 26 bar backgrounds (Liquid Glass + scroll edge effect); only set type and colour.
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.largeTitleTextAttributes = largeAttributes
        standard.titleTextAttributes = inlineAttributes

        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.largeTitleTextAttributes = largeAttributes
        edge.titleTextAttributes = inlineAttributes

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
        bar.compactScrollEdgeAppearance = edge
    }

    /// New York (the system serif) at a fixed size and weight.
    static func newYork(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        guard let serif = system.fontDescriptor.withDesign(.serif) else { return system }
        return UIFont(descriptor: serif, size: size)
    }
}
