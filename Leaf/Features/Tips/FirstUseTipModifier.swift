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
    /// the way along (0 leading, 1 trailing; nil for none).
    ///
    /// In the layout by default, pushing what's below down a little. `floating` lays it over the screen instead, for
    /// screens that can't grow (the reading timer).
    func firstUseTip(
        _ tip: FirstUseTip,
        edge: VerticalEdge = .bottom,
        pointer: CGFloat? = 0.5,
        floating: Bool = false,
        isAvailable: Bool = true
    ) -> some View {
        modifier(FirstUseTipModifier(tip: tip, edge: edge, pointer: pointer, floating: floating, isAvailable: isAvailable))
    }
}

private struct FirstUseTipModifier: ViewModifier {
    let tip: FirstUseTip
    let edge: VerticalEdge
    let pointer: CGFloat?
    let floating: Bool
    let isAvailable: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            let side: VerticalAlignment = edge == .top ? .top : .bottom
            content
                .frame(maxWidth: .infinity)
                .overlay(alignment: Alignment(horizontal: .center, vertical: side)) {
                    if showing {
                        // Lifted clear of the view: its far edge lines up with the view's edge, a gap away.
                        card
                            .fixedSize(horizontal: false, vertical: true)
                            .alignmentGuide(side) { size in
                                edge == .top ? size[.bottom] + gap : size[.top] - gap
                            }
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
            // The pointer faces the view: up from a note below it, down from a note above it.
            pointer: pointer.map { CanopyTipPointer(edge: edge == .top ? .bottom : .top, position: $0) }
        ) {
            tips.finish(tip)
        }
    }
}
