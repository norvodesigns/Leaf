import SwiftUI

/// A flat paper tone behind a screen, extended under the bars.
struct PaperBackground: View {
    var color: Color

    init(_ color: Color = .paper) {
        self.color = color
    }

    var body: some View {
        color
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

extension View {
    /// The page behind every screen: Canopy's cream with daylight from the top (docs/design/DESIGN_SYSTEM.md §3).
    /// For `Form` and `List`, also add `.scrollContentBackground(.hidden)`.
    func paperBackground() -> some View {
        background {
            CanopyBackdrop()
        }
    }

    /// A specific flat paper tone behind the view, edge to edge.
    func paperBackground(_ color: Color) -> some View {
        background {
            PaperBackground(color)
        }
    }
}
