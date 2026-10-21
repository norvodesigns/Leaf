import SwiftUI

// MARK: - Anchors

/// Where each coach-mark target sits, by id, gathered from the screen.
struct CoachMarkAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as what the coach mark `id` points at.
    func coachMarkAnchor(_ id: String) -> some View {
        anchorPreference(key: CoachMarkAnchors.self, value: .bounds) { [id: $0] }
    }
}

// MARK: - A callout

/// A small glass note with an arrow at what it describes (DESIGN.md: vellum glass, ink, a serif-free UI face): a title,
/// a line, "Skip tour" and "Next". Tapping it or swiping it away moves on. It is a real accessibility element, its
/// buttons are buttons, and nothing around it is blocked.
struct CoachMarkCallout: View {
    enum Arrow { case up, down, none }

    let title: String
    let text: String
    /// "2 of 4".
    let position: String
    let isLast: Bool
    let arrow: Arrow
    /// Where the arrow sits, in points from the callout's leading edge.
    let arrowX: CGFloat
    let next: () -> Void
    let skip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if arrow == .up { pointer.rotationEffect(.degrees(180)) }
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).leafStyle(.headline)
                    Spacer(minLength: Space.s)
                    Text(position).leafStyle(.caption, color: .inkTertiary)
                }
                Text(text)
                    .leafStyle(.uiBody, color: .inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Skip tour", action: skip)
                        .font(LeafType.ui)
                        .foregroundStyle(Color.inkTertiary)
                        .frame(minHeight: Space.hitTarget)
                    Spacer()
                    Button(isLast ? "Done" : "Next", action: next)
                        .font(LeafType.ui.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .frame(minHeight: Space.hitTarget)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xs)
            .glassEffect(.regular.tint(Color.glassTint), in: .rect(cornerRadius: Radius.card))
            .shadow(color: Color.coverShadow.opacity(0.18), radius: 14, y: 6)
            if arrow == .down { pointer }
        }
        .contentShape(.rect)
        .onTapGesture(perform: next)
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                if abs(value.translation.width) > 40 || abs(value.translation.height) > 40 { next() }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(text)")
        .accessibilityHint(position)
        .accessibilitySortPriority(10)
    }

    /// The little arrow, pointing down, placed at `arrowX`.
    private var pointer: some View {
        Triangle()
            .fill(Color.glassTint.opacity(0.9))
            .frame(width: 18, height: 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: arrowX - 9)
            .accessibilityHidden(true)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

/// Places a callout beside `target` (in the container's coordinates): under it when there is room, otherwise over it,
/// kept inside the margins; with no target, near the bottom. A soft ring marks the target. Only the callout takes
/// touches.
struct CoachMarkPlacement<Callout: View>: View {
    let target: CGRect?
    let container: CGSize
    /// Room kept clear at the bottom (the tab bar and the session accessory).
    var bottomClearance: CGFloat = 150
    @ViewBuilder let callout: (CoachMarkCallout.Arrow, CGFloat) -> Callout

    var body: some View {
        let width = min(340, container.width - Space.l * 2)
        if let target {
            let x = min(max(target.midX - width / 2, Space.l), container.width - Space.l - width)
            let arrowX = min(max(target.midX - x, 24), width - 24)
            let roomBelow = container.height - bottomClearance - target.maxY
            let below = roomBelow > 190 || roomBelow > target.minY
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .strokeBorder(Color.accent.opacity(0.55), lineWidth: 2)
                    .frame(width: target.width + 12, height: target.height + 12)
                    .offset(x: target.minX - 6, y: target.minY - 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if below {
                    callout(.up, arrowX)
                        .frame(width: width)
                        .frame(width: width, height: max(0, container.height - target.maxY - 10), alignment: .top)
                        .offset(x: x, y: target.maxY + 10)
                } else {
                    callout(.down, arrowX)
                        .frame(width: width)
                        .frame(width: width, height: max(0, target.minY - 10), alignment: .bottom)
                        .offset(x: x)
                }
            }
            .frame(width: container.width, height: container.height, alignment: .topLeading)
        } else {
            callout(.none, width / 2)
                .frame(width: width)
                .frame(width: container.width, height: max(0, container.height - bottomClearance), alignment: .bottom)
        }
    }
}

// MARK: - For VoiceOver

/// The same coach marks read as one ordered list, for VoiceOver, instead of notes floating over the screen.
struct CoachMarkList: View {
    let heading: String
    let steps: [TourStep]
    let done: () -> Void
    let skip: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(step.title).leafStyle(.headline)
                        Text(step.text).leafStyle(.uiBody, color: .inkSecondary)
                    }
                    .padding(.vertical, Space.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(index + 1) of \(steps.count). \(step.title). \(step.text)")
                }
            }
            .scrollContentBackground(.hidden)
            .paperBackground()
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip tour", action: skip)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
