import SwiftUI

/// Which small sheet a reading time on Plan has open (docs/design/REDESIGN.md §4.3): its time, or its book.
enum SlotEdit: Identifiable, Hashable {
    case time(UUID)
    case book(UUID)

    var id: String {
        switch self {
        case .time(let id): "time-\(id)"
        case .book(let id): "book-\(id)"
        }
    }

    var slotID: UUID {
        switch self {
        case .time(let id), .book(let id): id
        }
    }
}

/// Hosts whichever slot sheet is open, once the reading time is found.
struct SlotEditSheet: View {
    @Environment(LibraryStore.self) private var store
    let edit: SlotEdit

    var body: some View {
        if let slot = store.preferences.effectiveReadingSlots.first(where: { $0.id == edit.slotID }) {
            switch edit {
            case .time: SlotTimeSheet(slot: slot)
            case .book: SlotBookSheet(slot: slot)
            }
        }
    }
}

/// Change when a reading time is: one wheel and one button.
struct SlotTimeSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let slot: ReadingSlot
    @State private var time: Date

    init(slot: ReadingSlot) {
        self.slot = slot
        let calendar = Calendar.current
        _time = State(initialValue: calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: .now) ?? .now)
    }

    var body: some View {
        VStack(spacing: Canopy.Space.l) {
            VStack(spacing: Canopy.Space.xs) {
                CanopyLabel(slot.label ?? "Reading time", accent: .dusk)
                Text("When would you like to read?")
                    .canopyText(.title)
                    .multilineTextAlignment(.center)
            }
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .onChange(of: time) { CanopyFeel.play(.snap) }
            CanopyHeroButton("Save", systemImage: "checkmark", feel: .planChanged) {
                save()
            }
        }
        .padding(Canopy.Space.margin)
        .padding(.top, Canopy.Space.m)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        var updated = slot
        updated.hour = parts.hour ?? slot.hour
        updated.minute = parts.minute ?? slot.minute
        store.updateReadingSlot(updated)
        dismiss()
    }
}

/// Swap which book a reading time is for: a tap on a book, or back to "whatever's next".
struct SlotBookSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let slot: ReadingSlot

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Canopy.Space.m) {
                    Text("Pick the book for \(LeafFormat.time(hour: slot.hour, minute: slot.minute)).")
                        .canopyText(.callout, color: Canopy.textSecondary)

                    VStack(spacing: 0) {
                        ForEach(store.reading) { item in
                            choice(isSelected: slot.bookID == item.id) {
                                CanopyBookRow(
                                    title: item.book.title,
                                    author: item.book.author,
                                    paletteIndex: CoverPalette.index(for: item.book),
                                    progress: item.progress
                                )
                            } action: {
                                pick(item.id)
                            }
                        }
                        choice(isSelected: slot.bookID == nil) {
                            HStack(spacing: Canopy.Space.m) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(CanopyAccent.dusk.color)
                                    .frame(width: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Whatever’s next").canopyText(.headline)
                                    Text("Leaf picks from the plan.").canopyText(.caption)
                                }
                                Spacer(minLength: 0)
                            }
                        } action: {
                            pick(nil)
                        }
                    }
                    .canopyCard(padding: Canopy.Space.m)

                    if store.preferences.planMode == .focus, store.reading.count > 1 {
                        Text("Picking a book also plans your books side by side, so each gets its own time.")
                            .canopyText(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Canopy.Space.margin)
                .padding(.vertical, Canopy.Space.l)
            }
            .paperBackground()
            .navigationTitle("Swap the book")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func choice<Label: View>(isSelected: Bool, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Canopy.Space.m) {
                label()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? CanopyAccent.forest.color : Canopy.textTertiary)
            }
            .padding(.vertical, Canopy.Space.s)
            .frame(minHeight: Canopy.Space.hitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Ties the time to the book. A time kept for one book only works side by side (one at a time plans a single
    /// book a day), so picking a book switches the plan over when there's more than one on the go.
    private func pick(_ bookID: String?) {
        CanopyFeel.play(.planChanged)
        var updated = slot
        updated.bookID = bookID
        store.updateReadingSlot(updated)
        if bookID != nil, store.preferences.planMode == .focus, store.reading.count > 1 {
            store.updatePreferences { $0.planMode = .sideBySide }
        }
        dismiss()
    }
}
