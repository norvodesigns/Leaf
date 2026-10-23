import SwiftUI

// A first-use note (DESIGN_SYSTEM.md §12). Not a coach mark: it sits beside what it's about, never dims the screen,
// and goes with one tap.

/// Where a tip's pointer sits: on its top or bottom edge, and how far along it (0 leading, 1 trailing).
struct CanopyTipPointer: Equatable, Sendable {
    enum Side: Sendable { case top, bottom }

    var edge: Side
    var position: CGFloat = 0.5
}

/// A short glass note in its job's accent: a symbol, a title and a line, a close button, and a small pointer toward
/// the thing it's about. Arrives with Focus In wherever it's shown (`.firstUseTip(_:)`).
struct CanopyTip: View {
    let title: String
    let message: String
    var systemImage: String
    var accent: CanopyAccent = .forest
    var pointer: CanopyTipPointer?
    let onClose: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var badge: CGFloat = 32

    init(title: String, message: String, systemImage: String, accent: CanopyAccent = .forest, pointer: CanopyTipPointer? = nil, onClose: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.accent = accent
        self.pointer = pointer
        self.onClose = onClose
    }

    var body: some View {
        HStack(alignment: .top, spacing: Canopy.Space.m) {
            Image(systemName: systemImage)
                .font(.system(.subheadline, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent.color)
                .frame(width: badge, height: badge)
                .background(accent.soft, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                Text(title)
                    .canopyText(.headline)
                Text(message)
                    .canopyText(.callout, color: Canopy.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tip. \(title). \(message)")
            Button {
                CanopyFeel.play(.tap)
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Canopy.textSecondary)
                    .frame(width: Canopy.Space.hitTarget, height: Canopy.Space.hitTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The target reaches into the padding, so the cross sits near the corner without a 44 pt gap.
            .padding(.top, -Canopy.Space.m)
            .padding(.trailing, -Canopy.Space.m)
            .accessibilityLabel("Close tip")
        }
        .padding(Canopy.Space.l)
        .padding(pointer?.edge == .top ? .top : .bottom, pointer == nil ? 0 : CanopyTipShape.pointerSize.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .canopyGlass(accent, interactive: false, in: CanopyTipShape(pointer: pointer))
        .accessibilityElement(children: .contain)
    }
}

/// A rounded card with a small soft pointer on one edge, as one shape so the glass covers both.
struct CanopyTipShape: Shape {
    var radius: CGFloat = 22
    var pointer: CanopyTipPointer?

    static let pointerSize = CGSize(width: 20, height: 9)

    func path(in rect: CGRect) -> Path {
        let size = Self.pointerSize
        var body = rect
        if let pointer {
            body.size.height -= size.height
            if pointer.edge == .top { body.origin.y += size.height }
        }
        let card = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        guard let pointer else { return card }

        // Kept clear of the corners.
        let inset = radius + size.width / 2
        let x = min(max(rect.minX + rect.width * pointer.position, rect.minX + inset), rect.maxX - inset)
        let half = size.width / 2
        let (base, tip) = pointer.edge == .top ? (body.minY + 1, rect.minY) : (body.maxY - 1, rect.maxY)
        // Two points just short of the tip, joined by a curve, so the pointer is soft rather than sharp.
        let shoulder = pointer.edge == .top ? tip + 2 : tip - 2
        var notch = Path()
        notch.move(to: CGPoint(x: x - half, y: base))
        notch.addLine(to: CGPoint(x: x - 2.5, y: shoulder))
        notch.addQuadCurve(to: CGPoint(x: x + 2.5, y: shoulder), control: CGPoint(x: x, y: tip))
        notch.addLine(to: CGPoint(x: x + half, y: base))
        notch.closeSubpath()
        return card.union(notch)
    }
}

#Preview("Tip") {
    VStack(spacing: Canopy.Space.xl) {
        CanopyTip(
            title: "Make it your nook",
            message: "Change the scene behind your timer here, and pick a sound to read by beside it.",
            systemImage: "sparkles",
            accent: .dusk,
            pointer: CanopyTipPointer(edge: .bottom)
        ) {}
        CanopyTip(
            title: "Add a book",
            message: "Tap + up top to find a book. Touch and hold it to scan a barcode or type one in.",
            systemImage: "plus",
            pointer: CanopyTipPointer(edge: .top, position: 0.94)
        ) {}
        CanopyTip(
            title: "Make Leaf yours",
            message: "How your reading is going, at a glance. Further down: the teas you like, your tea cabinet and settings.",
            systemImage: "heart"
        ) {}
    }
    .padding(Canopy.Space.margin)
    .canopyBackdrop()
}
