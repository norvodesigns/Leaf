import SwiftUI
import UIKit
import UserNotifications

// MARK: - Section

/// Reading times (several a day, optional weekdays, optional book per time) and the reminders that go with them.
/// One `Form` section, used in Settings and in the sheet Today opens. Each row opens `ReadingSlotEditor`.
///
/// Reminders are one switch over all the times: each reminder names that time's book and pages, and Leaf skips the
/// rest of the day once the reading is done (`Reminders`).
struct ReadingTimesSection: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// The reader tried to turn reminders on and iOS said no.
    @State private var reminderBlocked = false

    private var slots: [ReadingSlot] {
        store.preferences.effectiveReadingSlots.sorted { ($0.minuteOfDay, $0.id.uuidString) < ($1.minuteOfDay, $1.id.uuidString) }
    }

    /// A time is tied to a book, but one-at-a-time plans only one book a day, so the time can't keep its promise.
    private var needsSideBySide: Bool {
        store.preferences.planMode == .focus && store.reading.count > 1
            && slots.contains { slot in slot.isEnabled && slot.bookID != nil && slot.bookID != store.reading.first?.id }
    }

    var body: some View {
        Section {
            ForEach(slots) { slot in
                NavigationLink {
                    ReadingSlotEditor(slot: slot, isNew: false)
                } label: {
                    ReadingSlotRow(slot: slot, bookTitle: slot.bookID.flatMap { store.item($0)?.book.title })
                }
            }
            .onDelete(perform: delete)

            NavigationLink {
                ReadingSlotEditor(slot: Self.suggestedSlot(after: slots), isNew: true) {
                    Task { await askPermissionIfNeeded() }
                }
            } label: {
                Label("Add a reading time", systemImage: "plus")
                    .canopyText(.body, color: CanopyAccent.forest.color)
            }

            if !slots.isEmpty {
                Toggle(isOn: reminderToggle) {
                    Text("Remind me at these times")
                        .canopyText(.body)
                }
                .task { await refreshNotificationStatus() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await refreshNotificationStatus() } }
                }
            }

            if showsDeniedNote {
                VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                    Text("Notifications are turned off for Leaf in iOS Settings, so there’s nothing to remind you with.")
                        .canopyText(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    TextButton("Open Settings") {
                        openSystemSettings()
                    }
                }
            }

            if needsSideBySide {
                VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                    Text("A time kept for one book works best side by side. One at a time plans a single book a day, so that time reads whatever is first.")
                        .canopyText(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    TextButton("Read side by side") {
                        CanopyFeel.play(.select)
                        store.updatePreferences { $0.planMode = .sideBySide }
                    }
                }
            }
        } header: {
            Text("Reading times")
                .settingsHeader(.dusk)
        } footer: {
            Text(footer)
                .canopyText(.caption)
        }
        .listRowBackground(Canopy.surface)
        .listRowSeparatorTint(Canopy.separator)
    }

    private var footer: String {
        if slots.isEmpty {
            return "Add the times you like to read. Leaf shares each day’s pages between them."
        }
        return "Leaf shares each day’s pages between your times. Each reminder names the book and pages, and Leaf skips the rest of today once you’ve read."
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { slots[$0].id }
        CanopyFeel.play(.warning)
        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
            for id in ids { store.removeReadingSlot(id) }
        }
    }

    /// A sensible next time: the first of morning tea, evening and bedtime that isn't taken.
    static func suggestedSlot(after existing: [ReadingSlot]) -> ReadingSlot {
        let taken = Set(existing.map(\.hour))
        let options = [(21, 0), (7, 30), (12, 30), (17, 30), (19, 0)]
        let pick = options.first { !taken.contains($0.0) } ?? (20, 0)
        return ReadingSlot(hour: pick.0, minute: pick.1)
    }

    // MARK: Reminders

    private var showsDeniedNote: Bool {
        notificationStatus == .denied && (store.preferences.reminderEnabled || reminderBlocked) && !slots.isEmpty
    }

    private var reminderToggle: Binding<Bool> {
        Binding(
            get: { store.preferences.reminderEnabled },
            set: { newValue in
                if newValue {
                    Task { await enableReminders() }
                } else {
                    withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
                        reminderBlocked = false
                        store.updatePreferences { $0.reminderEnabled = false }
                    }
                }
            }
        )
    }

    /// Asks for permission the first time, and only switches reminders on once iOS has said yes.
    private func enableReminders() async {
        var status = await Reminders.shared.authorizationStatus()
        if status == .notDetermined {
            _ = await Reminders.shared.requestAuthorization()
            status = await Reminders.shared.authorizationStatus()
        }
        notificationStatus = status
        switch status {
        case .authorized, .provisional, .ephemeral:
            reminderBlocked = false
            withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
                store.updatePreferences { $0.reminderEnabled = true }
            }
        default:
            withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
                reminderBlocked = true
            }
        }
    }

    /// Adding a time switches reminders on; the first time, that's when iOS is asked.
    private func askPermissionIfNeeded() async {
        guard await Reminders.shared.authorizationStatus() == .notDetermined else {
            await refreshNotificationStatus()
            return
        }
        _ = await Reminders.shared.requestAuthorization()
        await refreshNotificationStatus()
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await Reminders.shared.authorizationStatus()
        if notificationStatus != .denied { reminderBlocked = false }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

// MARK: - Row

/// "7:30  Morning tea / Weekdays · Circe".
struct ReadingSlotRow: View {
    let slot: ReadingSlot
    let bookTitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Canopy.Space.m) {
            Text(LeafFormat.time(hour: slot.hour, minute: slot.minute))
                .font(.system(.body, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(slot.isEnabled ? CanopyAccent.dusk.color : Canopy.textTertiary)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                Text(slot.label ?? ReadingSlotText.defaultLabel(hour: slot.hour))
                    .canopyText(.body, color: slot.isEnabled ? Canopy.text : Canopy.textSecondary)
                Text(caption)
                    .canopyText(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Canopy.Space.xxs)
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        var parts = [ReadingSlotText.days(slot.weekdays)]
        parts.append(bookTitle ?? "Whatever’s next")
        if !slot.isEnabled { parts.append("Off") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Editor

/// One reading time: when, what to call it, which days, and which book (or whatever the plan says is next).
struct ReadingSlotEditor: View {
    let isNew: Bool
    var onSaved: (() -> Void)?

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ReadingSlot
    @State private var everyDay: Bool
    @State private var days: Set<Int>
    @State private var confirmsDelete = false

    init(slot: ReadingSlot, isNew: Bool, onSaved: (() -> Void)? = nil) {
        self.isNew = isNew
        self.onSaved = onSaved
        _draft = State(initialValue: slot)
        _everyDay = State(initialValue: slot.weekdays == nil)
        _days = State(initialValue: slot.weekdays ?? [2, 3, 4, 5, 6])
    }

    private static let suggestions = ["Morning tea", "Lunch break", "On the train", "After dinner", "Before bed"]

    private var canSave: Bool { everyDay || !days.isEmpty }

    var body: some View {
        Form {
            Section {
                TimeDrum(hour: $draft.hour, minute: $draft.minute)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Canopy.Space.s)
            } header: {
                header("When")
            } footer: {
                Text(todayShare)
                    .canopyText(.caption)
            }
            .listRowBackground(Canopy.surface)

            Section {
                TextField("Name", text: label, prompt: Text(ReadingSlotText.defaultLabel(hour: draft.hour)))
                    .font(CanopyType.body.font)
                    .submitLabel(.done)
                ScrollView(.horizontal) {
                    HStack(spacing: Canopy.Space.s) {
                        ForEach(Self.suggestions, id: \.self) { suggestion in
                            CanopyChip(suggestion, accent: .dusk, isSelected: draft.label == suggestion) {
                                draft.label = suggestion
                            }
                            .padding(.vertical, Canopy.Space.xs)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } header: {
                header("Name")
            }
            .listRowBackground(Canopy.surface)

            Section {
                Toggle(isOn: $everyDay.animation(Canopy.Motion.smooth)) {
                    Text("Every reading day")
                        .canopyText(.body)
                }
                if !everyDay {
                    WeekdayPicker(selection: $days)
                        .padding(.vertical, Canopy.Space.xs)
                    if days.isEmpty {
                        Text("Pick at least one day.")
                            .canopyText(.caption)
                    }
                }
            } header: {
                header("Days")
            } footer: {
                Text("A time only rings on your reading days.")
                    .canopyText(.caption)
            }
            .listRowBackground(Canopy.surface)

            Section {
                Picker("Book", selection: $draft.bookID) {
                    Text("Whatever’s next in the plan")
                        .tag(String?.none)
                    ForEach(store.reading) { item in
                        Text(item.book.title)
                            .tag(Optional(item.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                header("Book")
            } footer: {
                if draft.bookID != nil && store.preferences.planMode == .focus {
                    VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                        Text("One at a time plans a single book a day, so this time would read whatever is first. Side by side gives each book its own share and keeps this time for this book.")
                            .canopyText(.caption)
                        TextButton("Read side by side") {
                            CanopyFeel.play(.select)
                            store.updatePreferences { $0.planMode = .sideBySide }
                        }
                    }
                } else {
                    Text("Tie a time to a book: mornings for one, evenings for another.")
                        .canopyText(.caption)
                }
            }
            .listRowBackground(Canopy.surface)

            if !isNew {
                Section {
                    Toggle(isOn: $draft.isEnabled) {
                        Text("Use this time")
                            .canopyText(.body)
                    }
                    Button("Delete this time", role: .destructive) {
                        confirmsDelete = true
                    }
                }
                .listRowBackground(Canopy.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .tint(CanopyAccent.forest.color)
        .navigationTitle(isNew ? "New reading time" : "Reading time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") {
                    save()
                }
                .disabled(!canSave)
            }
        }
        .confirmationDialog("Delete this reading time?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                CanopyFeel.play(.warning)
                store.removeReadingSlot(draft.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .settingsHeader(.dusk)
    }

    private var label: Binding<String> {
        Binding(
            get: { draft.label ?? "" },
            set: { draft.label = $0 }
        )
    }

    /// What this time holds today, from the plan.
    private var todayShare: String {
        guard !isNew, let plan = store.slotPlans().first(where: { $0.slot.id == draft.id }), !plan.parts.isEmpty else {
            return "Leaf shares each day’s pages between your reading times."
        }
        let pieces = plan.parts.map { part -> String in
            let title = store.item(part.bookID)?.book.title ?? "Your book"
            return "\(title), \(LeafFormat.pages(from: part.fromPage, to: part.toPage)), \(max(1, Int(part.minutes.rounded()))) min"
        }
        return "Today: " + pieces.joined(separator: "; ") + "."
    }

    private func save() {
        var slot = draft
        slot.weekdays = everyDay ? nil : days
        let trimmed = slot.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        slot.label = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if isNew {
            store.addReadingSlot(hour: slot.hour, minute: slot.minute, bookID: slot.bookID, weekdays: slot.weekdays, label: slot.label)
        } else {
            store.updateReadingSlot(slot)
        }
        CanopyFeel.play(.planChanged)
        onSaved?()
        dismiss()
    }
}

// MARK: - Sheet

/// The reading times on their own, as a sheet from Today.
struct ReadingTimesSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    Text("When do you like to read? Add a time or a few. Leaf shares each day’s pages between them, and a time can belong to one book.")
                        .canopyText(.body, color: Canopy.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: Canopy.Space.s, leading: Canopy.Space.xl, bottom: Canopy.Space.s, trailing: Canopy.Space.xl))
                }
                ReadingTimesSection()
            }
            .scrollContentBackground(.hidden)
            .paperBackground()
            .foregroundStyle(Canopy.text)
            .tint(CanopyAccent.forest.color)
            .navigationTitle("Reading times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        CanopyFeel.play(.tap)
                        router.showReadingTimes = false
                        dismiss()
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let slot = store.preferences.effectiveReadingSlots.first(where: { $0.id == id }) {
                    ReadingSlotEditor(slot: slot, isNew: false)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Canopy.canvas)
        .onAppear {
            if let id = router.readingSlotToEdit {
                router.readingSlotToEdit = nil
                path = [id]
            }
        }
    }
}

// MARK: - Previews

@MainActor
private func readingTimesPreviewStore() -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return store
}

#Preview("Reading times") {
    ReadingTimesSheet()
        .environment(readingTimesPreviewStore())
        .environment(AppRouter())
}

#Preview("Reading time editor · dark") {
    let store = readingTimesPreviewStore()
    return NavigationStack {
        ReadingSlotEditor(slot: store.preferences.readingSlots[0], isNew: false)
    }
    .environment(store)
    .preferredColorScheme(.dark)
}
