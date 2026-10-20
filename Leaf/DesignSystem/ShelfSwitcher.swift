import SwiftUI

/// The Library's shelves as a segmented control: Reading, To read, Finished. A control everyone already knows how to
/// use, rather than a row of serif words that read like a second title. Counts live in the caption under it, so the
/// segments stay short at every text size. Plays `selection()`.
struct ShelfSwitcher: View {
    @Binding var selection: Shelf
    /// The shelves to offer. Paused is not a segment: set-aside books sit at the end of Reading.
    var shelves: [Shelf] = Shelf.main

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Binding<Shelf>, shelves: [Shelf] = Shelf.main) {
        self._selection = selection
        self.shelves = shelves
    }

    /// "Reading", "To read", "Finished".
    static func title(for shelf: Shelf) -> String {
        switch shelf {
        case .reading: "Reading"
        case .toRead: "To read"
        case .finished: "Finished"
        case .paused: "Set aside"
        }
    }

    var body: some View {
        Picker("Shelf", selection: animatedSelection) {
            ForEach(shelves, id: \.self) { shelf in
                Text(Self.title(for: shelf)).tag(shelf)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var animatedSelection: Binding<Shelf> {
        Binding(
            get: { selection },
            set: { shelf in
                guard shelf != selection else { return }
                Haptics.shared.selection()
                withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                    selection = shelf
                }
            }
        )
    }
}

#Preview("Shelf switcher") {
    @Previewable @State var shelf: Shelf = .reading
    VStack(alignment: .leading, spacing: Space.l) {
        ShelfSwitcher(selection: $shelf)
        Text(ShelfSwitcher.title(for: shelf)).leafStyle(.caption)
    }
    .leafMargins()
    .frame(maxHeight: .infinity, alignment: .top)
    .paperBackground()
}
