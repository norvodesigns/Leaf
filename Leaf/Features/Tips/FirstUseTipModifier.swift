import SwiftUI

extension FirstUseTip {
    /// The note's accent: Dusk for the timer and reading times, Forest otherwise.
    var accent: CanopyAccent {
        switch place {
        case .session, .plan: return .dusk
        default: return .forest
        }
    }
}

extension View {
    /// Shows `tip` beside this view the first few times the reader gets here, until they close it or do what it says
    /// (docs/design/DESIGN_SYSTEM.md §12). It sits on `edge` of the view with its pointer facing the view, `pointer` of
    /// the way along (0 leading, 1 trailing; nil for none). `pointerEdge` points it elsewhere (Library's note points up
    /// at `plus` in the bar).
    ///
    /// In the layout by default, pushing what's below down a little. `floating` lays it over the screen instead, for
    /// screens that can't grow (the reading timer).
    func firstUseTip(
        _ tip: FirstUseTip,
        edge: VerticalEdge = .bottom,
        pointer: CGFloat? = 0.5,
        pointerEdge: CanopyTipPointer.Side? = nil,
        floating: Bool = false,
        isAvailable: Bool = true
    ) -> some View {
        modifier(FirstUseTipModifier(tip: tip, edge: edge, pointer: pointer, pointerEdge: pointerEdge, floating: floating, isAvailable: isAvailable))
    }
}

private struct FirstUseTipModifier: ViewModifier {
    let tip: FirstUseTip
    let edge: VerticalEdge
    let pointer: CGFloat?
    let pointerEdge: CanopyTipPointer.Side?
    let floating: Bool
    let isAvailable: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A floating note's height, to lift it clear of the view it sits on.
    @State private var height: CGFloat = 0

    init(tip: FirstUseTip, edge: VerticalEdge, pointer: CGFloat?, pointerEdge: CanopyTipPointer.Side?, floating: Bool, isAvailable: Bool) {
        self.tip = tip
        self.edge = edge
        self.pointer = pointer
        self.pointerEdge = pointerEdge
        self.floating = floating
        self.isAvailable = isAvailable
    }

    private var tips: FirstUseTips { .shared }
    private var gap: CGFloat { Canopy.Space.m }

    func body(content: Content) -> some View {
        let showing = isAvailable && tips.isShowing(tip)
        placed(content, showing: showing)
            .animation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion), value: showing)
            // The screen first, then the note: a beat after it settles. Again whenever the screen comes back.
            .task(id: isAvailable) {
                guard isAvailable else { return }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                tips.arrive(tip)
            }
            .onDisappear { tips.leave(tip) }
    }

    @ViewBuilder
    private func placed(_ content: Content, showing: Bool) -> some View {
        if floating {
            content
                .frame(maxWidth: .infinity)
                .overlay(alignment: edge == .top ? .top : .bottom) {
                    if showing {
                        // Lifted clear of the view by its own height and a gap, so it never covers what it's about.
                        card
                            // Over a fixed screen it stays a note, not a page: past the largest standard size it
                            // stops growing.
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { value in
                                height = value
                            }
                            .offset(y: edge == .top ? -(height + gap) : height + gap)
                            .canopyFocusInTransition()
                    }
                }
                // Over whatever comes next on the screen, not under it.
                .zIndex(1)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if showing && edge == .top {
                    card
                        .padding(.bottom, gap)
                        .canopyFocusInTransition()
                }
                content
                if showing && edge == .bottom {
                    card
                        .padding(.top, gap)
                        .canopyFocusInTransition()
                }
            }
        }
    }

    private var card: some View {
        CanopyTip(
            title: tip.title,
            message: tip.message,
            systemImage: tip.symbol,
            accent: tip.accent,
            // The pointer faces the view unless told otherwise: up from a note below it, down from a note above it.
            pointer: pointer.map { CanopyTipPointer(edge: pointerEdge ?? (edge == .top ? .bottom : .top), position: $0) }
        ) {
            tips.finish(tip)
        }
    }
}
