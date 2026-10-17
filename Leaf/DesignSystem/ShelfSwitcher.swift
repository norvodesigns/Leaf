import SwiftUI

/// The Library's shelf tabs on paper (DESIGN.md §5): "Reading² To read⁷ Finished³¹" in `title`
/// with superscript counts. Active: `ink` with a 2 pt `ribbon` underline that slides between
/// tabs. Inactive: `inkTertiary`. Plays `selection()`.
struct ShelfSwitcher: View {
    @Binding var selection: Shelf
    var counts: [Shelf: Int]

    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Binding<Shelf>, counts: [Shelf: Int]) {
        self._selection = selection
        self.counts = counts
    }

    /// "Reading", "To read", "Finished".
    static func title(for shelf: Shelf) -> String {
        switch shelf {
        case .reading: "Reading"
        case .toRead: "To read"
        case .finished: "Finished"
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.xl) {
                ForEach(Shelf.allCases, id: \.self) { shelf in
                    tab(shelf)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollClipDisabled()
    }

    private func tab(_ shelf: Shelf) -> some View {
        let isActive = shelf == selection
        let count = counts[shelf] ?? 0
        let name = ShelfSwitcher.title(for: shelf)
        return Button {
            guard !isActive else { return }
            Haptics.shared.selection()
            withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                selection = shelf
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Text(name).font(LeafType.title))\(Text(String(count)).font(LeafType.caption).baselineOffset(8))")
                    .foregroundStyle(isActive ? Color.ink : Color.inkTertiary)
                    .lineLimit(1)
                    .fixedSize()
                ZStack {
                    if isActive {
                        Capsule()
                            .fill(Color.ribbon)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
                .frame(height: 2)
            }
            .frame(minHeight: Space.hitTarget, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(count) \(count == 1 ? "book" : "books")")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

#Preview("Shelf switcher") {
    @Previewable @State var shelf: Shelf = .reading
    VStack(alignment: .leading, spacing: Space.l) {
        ShelfSwitcher(selection: $shelf, counts: [.reading: 2, .toRead: 7, .finished: 31])
        Text(ShelfSwitcher.title(for: shelf)).leafStyle(.caption)
    }
    .leafMargins()
    .frame(maxHeight: .infinity, alignment: .top)
    .paperBackground()
}
