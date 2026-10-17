import SwiftUI

/// One button behind a swiped row.
struct LibrarySwipeAction: Identifiable {
    let id: String
    let title: String
    let accessibilityLabel: String
    let systemImage: String
    let background: Color
    let foreground: Color
    let handler: () -> Void
}

/// A row that slides left to show action buttons on its trailing edge, like list swipe actions, for
/// rows that live in a `LazyVStack` (the To read queue, which needs its own long-press reordering).
///
/// The row keeps a `paper` backing so the buttons stay hidden until the row moves. The swipe is a
/// `simultaneousGesture`, so vertical scrolling is untouched: it only follows drags that start out
/// more horizontal than vertical. Which row is open is owned by the caller (`isOpen` / `setOpen`),
/// so opening one row closes the last.
struct LibrarySwipeReveal<Content: View>: View {
    let actions: [LibrarySwipeAction]
    let height: CGFloat
    let isOpen: Bool
    let isEnabled: Bool
    let setOpen: (Bool) -> Void
    let content: Content

    @State private var drag: CGFloat = 0
    @State private var lockedAxis: Axis?
    @GestureState private var isTouching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let buttonWidth: CGFloat = 76

    init(
        actions: [LibrarySwipeAction],
        height: CGFloat,
        isOpen: Bool,
        isEnabled: Bool,
        setOpen: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.actions = actions
        self.height = height
        self.isOpen = isOpen
        self.isEnabled = isEnabled
        self.setOpen = setOpen
        self.content = content()
    }

    private var openWidth: CGFloat { buttonWidth * CGFloat(actions.count) }

    /// Where the row sits: resting position plus the finger, with resistance past either end.
    private var rowOffset: CGFloat {
        let raw = (isOpen ? -openWidth : 0) + drag
        if raw > 0 { return 0 }
        if raw < -openWidth { return -openWidth + (raw + openWidth) * 0.35 }
        return raw
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            actionStrip
            content
                .background(Color.paper)
                .offset(x: rowOffset)
        }
        .simultaneousGesture(swipe)
        .onChange(of: isTouching) { _, touching in
            // A cancelled drag never reaches `onEnded`; don't leave the row half open or the axis locked.
            guard !touching else { return }
            lockedAxis = nil
            if drag != 0 {
                withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) { drag = 0 }
            }
        }
    }

    private var actionStrip: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    setOpen(false)
                    action.handler()
                } label: {
                    VStack(spacing: Space.xs) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                        Text(action.title)
                            .font(LeafType.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(action.foreground)
                    .frame(width: buttonWidth, height: height)
                    .background(action.background)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.accessibilityLabel)
            }
        }
        // Hidden until the row has moved, so a lifted row's rounded corners never show the strip.
        .opacity(rowOffset < -0.5 ? 1 : 0)
        .accessibilityHidden(!isOpen)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($isTouching) { _, state, _ in
                state = true
            }
            .onChanged { value in
                guard isEnabled else { return }
                if lockedAxis == nil {
                    lockedAxis = abs(value.translation.width) > abs(value.translation.height) ? .horizontal : .vertical
                }
                guard lockedAxis == .horizontal else { return }
                drag = value.translation.width
            }
            .onEnded { value in
                let wasHorizontal = lockedAxis == .horizontal
                lockedAxis = nil
                guard isEnabled, wasHorizontal else {
                    drag = 0
                    return
                }
                let resting: CGFloat = isOpen ? -openWidth : 0
                let projected = resting + value.predictedEndTranslation.width
                let shouldOpen = projected < -openWidth * 0.5
                withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                    drag = 0
                    setOpen(shouldOpen)
                }
            }
    }
}
