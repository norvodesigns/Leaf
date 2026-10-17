import SwiftUI

/// The warm paper behind every screen, extended under the bars.
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
    /// Puts `paper` (or another paper tone) behind the view, edge to edge.
    /// For `Form` and `List`, also add `.scrollContentBackground(.hidden)`.
    func paperBackground(_ color: Color = .paper) -> some View {
        background {
            PaperBackground(color)
        }
    }
}
