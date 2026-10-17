import SwiftUI

/// The two-layer cover shadow (DESIGN.md §4). Only books cast shadows.
struct CoverShadowModifier: ViewModifier {
    let size: BookCover.Size

    @Environment(\.colorScheme) private var colorScheme

    init(size: BookCover.Size) {
        self.size = size
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let ambientOpacity = colorScheme == .dark ? 0.5 : 0.14
        let ambient = size.ambientShadow
        content
            .shadow(color: Color.coverShadow.opacity(0.22), radius: 0.5, x: 0, y: 0.5)
            .shadow(color: Color.coverShadow.opacity(ambientOpacity), radius: ambient.radius, x: 0, y: ambient.y)
    }
}

/// A row picked up for reordering: scale 1.03 on `paperRaised` with the lifted shadow.
struct LiftedRowModifier: ViewModifier {
    let isLifted: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                Radius.shape(cornerRadius)
                    .fill(Color.paperRaised)
                    .shadow(color: Color.coverShadow.opacity(0.18), radius: 16, x: 0, y: 10)
                    .opacity(isLifted ? 1 : 0)
            }
            .scaleEffect(isLifted ? 1.03 : 1)
            .zIndex(isLifted ? 1 : 0)
    }
}

extension View {
    /// The contact + ambient shadow for a cover of `size`. `BookCover` applies this itself.
    func coverShadow(_ size: BookCover.Size) -> some View {
        modifier(CoverShadowModifier(size: size))
    }

    /// Lifts a row while it's being dragged. Animate the change with `Motion.paper`.
    func liftedRow(_ isLifted: Bool, cornerRadius: CGFloat = Radius.tile) -> some View {
        modifier(LiftedRowModifier(isLifted: isLifted, cornerRadius: cornerRadius))
    }
}
