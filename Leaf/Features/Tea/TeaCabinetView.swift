import SwiftUI

/// The reader's own teas (NEXT.md section 6): tins of catalog teas and teas of their own, what's in and what has
/// run out. The ritual offers what is in, ranked for the hour; a tea the reader is out of stays here for later.
struct TeaCabinetView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var editing: CabinetTea?
    @State private var addsOwn = false
    @State private var browsesCatalog = false

    private var inStock: [CabinetTea] { sorted(store.data.cabinet.filter { !$0.isOutOf }) }
    private var outOf: [CabinetTea] { sorted(store.data.cabinet.filter(\.isOutOf)) }

    private func sorted(_ teas: [CabinetTea]) -> [CabinetTea] {
        teas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Form {
            if store.data.cabinet.isEmpty {
                Section {
                    Text("Add the teas you have and the ritual will offer those, the best for the hour first. Mark one when it runs out, and it waits here until you buy more.")
                        .leafStyle(.body, color: .inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Space.xs)
                } header: {
                    Text("An empty cabinet").leafStyle(.eyebrow)
                }
                .settingsRows()
            } else {
                Section {
                    ForEach(inStock) { tea in
                        row(tea)
                    }
                } header: {
                    Text("In the cabinet").leafStyle(.eyebrow)
                } footer: {
                    Text(inStock.isEmpty ? "Everything has run out, so the ritual offers the catalog’s teas for now." : "The ritual offers these. Swipe a tea when it runs out.")
                        .leafStyle(.caption)
                }
                .settingsRows()
                if !outOf.isEmpty {
                    Section {
                        ForEach(outOf) { tea in
                            row(tea)
                        }
                    } header: {
                        Text("Run out").leafStyle(.eyebrow)
                    } footer: {
                        Text("Kept for when you buy more. Swipe to put one back.")
                            .leafStyle(.caption)
                    }
                    .settingsRows()
                }
            }
            Section {
                Button {
                    Haptics.shared.tap()
                    browsesCatalog = true
                } label: {
                    SettingsDisclosureRow("From Leaf’s teas")
                }
                .buttonStyle(.plain)
                Button {
                    Haptics.shared.tap()
                    addsOwn = true
                } label: {
                    SettingsDisclosureRow("A tea of your own")
                }
                .buttonStyle(.plain)
            } header: {
                Text("Add a tea").leafStyle(.eyebrow)
            }
            .settingsRows()
            Section {
                NavigationLink {
                    TeaHistoryView()
                } label: {
                    Text("Tea history").leafStyle(.uiBody)
                }
            } footer: {
                Text("The teas you read with most, the books they went with, and your tasting notes.")
                    .leafStyle(.caption)
            }
            .settingsRows()
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .foregroundStyle(Color.ink)
        .tint(Color.accent)
        .navigationTitle("Tea cabinet")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { tea in
            NavigationStack {
                TeaFormView(editing: tea)
            }
            .presentationBackground(Color.paper)
        }
        .sheet(isPresented: $addsOwn) {
            NavigationStack {
                TeaFormView(editing: nil)
            }
            .presentationBackground(Color.paper)
        }
        .sheet(isPresented: $browsesCatalog) {
            NavigationStack {
                TeaCatalogPicker()
            }
            .presentationBackground(Color.paper)
        }
        .task {
            applyStage()
        }
    }

    private func row(_ cabinetTea: CabinetTea) -> some View {
        let tea = cabinetTea.tea
        return Button {
            Haptics.shared.tap()
            editing = cabinetTea
        } label: {
            HStack(spacing: Space.m) {
                TeaSwatch(tea: tea)
                    .opacity(cabinetTea.isOutOf ? 0.4 : 1)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(cabinetTea.displayName)
                        .leafStyle(.uiBody, color: cabinetTea.isOutOf ? .inkSecondary : nil)
                    Text("\(cabinetTea.family.title) · \(SteepText.duration(seconds: cabinetTea.steepSeconds))\(cabinetTea.catalogID == nil ? " · your own" : "")")
                        .leafStyle(.caption)
                }
                Spacer(minLength: Space.s)
                if let rating = cabinetTea.rating {
                    TeaLeaves(rating: rating)
                }
            }
            .padding(.vertical, Space.xxs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(cabinetTea.isOutOf ? "Back in" : "Run out") {
                Haptics.shared.selection()
                Motion.animate(Motion.paper) { store.setOutOf(cabinetTea.id, !cabinetTea.isOutOf) }
            }
            .tint(cabinetTea.isOutOf ? Color.accent : Color.inkSecondary)
        }
        .contextMenu {
            Button(cabinetTea.isOutOf ? "Back in the cabinet" : "Run out", systemImage: cabinetTea.isOutOf ? "arrow.uturn.backward" : "tray") {
                Motion.animate(Motion.paper) { store.setOutOf(cabinetTea.id, !cabinetTea.isOutOf) }
            }
            Button("Take out of the cabinet", systemImage: "trash", role: .destructive) {
                Motion.animate(Motion.paper) { store.removeCabinetTea(cabinetTea.id) }
            }
        }
    }

    /// Screenshot staging: "add" opens the form for a tea of your own, "catalog" the list, "edit" the first tea.
    private func applyStage() {
        guard let stage = router.teaStage else { return }
        router.teaStage = nil
        switch stage {
        case "add": addsOwn = true
        case "catalog": browsesCatalog = true
        case "edit": editing = inStock.first ?? outOf.first
        default: break
        }
    }
}

// MARK: - Leaf's teas

/// The catalog by family, to add a tin of any of them in one tap.
struct TeaCatalogPicker: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            ForEach(TeaFamily.allCases, id: \.self) { family in
                let teas = TeaCatalog.all.filter { $0.family == family }
                if !teas.isEmpty {
                    Section {
                        ForEach(teas) { tea in
                            row(tea)
                        }
                    } header: {
                        Text(family.title).leafStyle(.eyebrow)
                    }
                    .settingsRows()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .foregroundStyle(Color.ink)
        .tint(Color.accent)
        .navigationTitle("Leaf’s teas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    Haptics.shared.tap()
                    dismiss()
                }
            }
        }
    }

    private func row(_ tea: Tea) -> some View {
        let isIn = store.hasInStock(tea.id)
        return HStack(spacing: Space.m) {
            TeaSwatch(tea: tea)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(tea.name)
                    .leafStyle(.uiBody)
                Text(tea.blurb)
                    .leafStyle(.caption)
                    .lineLimit(2)
            }
            Spacer(minLength: Space.s)
            if isIn {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accent)
                    .frame(minWidth: Space.hitTarget, minHeight: Space.hitTarget)
                    .accessibilityLabel("In your cabinet")
            } else {
                Button {
                    Haptics.shared.success()
                    Motion.animate(Motion.paper) {
                        _ = store.addCabinetTea(CabinetTea(tin: tea, now: store.now))
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(Color.accent)
                        .frame(minWidth: Space.hitTarget, minHeight: Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(tea.name) to your cabinet")
            }
        }
        .padding(.vertical, Space.xxs)
    }
}

// MARK: - A tea's details

/// Adds a tea of the reader's own, or edits any tea in the cabinet: name, brand, family, steep time, rating, notes
/// and whether it has run out.
struct TeaFormView: View {
    let editing: CabinetTea?

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var brand: String
    @State private var family: TeaFamily
    @State private var steepSeconds: Int
    @State private var rating: Int?
    @State private var notes: String
    @State private var isOutOf: Bool
    @State private var steepTouched: Bool
    @State private var confirmsRemoval = false

    init(editing: CabinetTea?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _brand = State(initialValue: editing?.brand ?? "")
        _family = State(initialValue: editing?.family ?? .black)
        _steepSeconds = State(initialValue: editing?.steepSeconds ?? TeaFamily.black.defaultSteepSeconds)
        _rating = State(initialValue: editing?.rating)
        _notes = State(initialValue: editing?.notes ?? "")
        _isOutOf = State(initialValue: editing?.isOutOf ?? false)
        _steepTouched = State(initialValue: editing != nil)
    }

    private var isTin: Bool { editing?.catalogID != nil }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name, prompt: Text("Lapsang from the market"))
                    .leafStyle(.uiBody)
                    .textInputAutocapitalization(.words)
                TextField("Brand", text: $brand, prompt: Text("Brand or shop (optional)"))
                    .leafStyle(.uiBody)
                    .textInputAutocapitalization(.words)
                if isTin {
                    SettingsValueRow(title: "Family", value: family.title)
                } else {
                    Picker(selection: $family) {
                        ForEach(TeaFamily.allCases, id: \.self) { Text($0.title).tag($0) }
                    } label: {
                        Text("Family").leafStyle(.uiBody)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: family) { _, value in
                        if !steepTouched { steepSeconds = value.defaultSteepSeconds }
                    }
                }
            } header: {
                Text("The tea").leafStyle(.eyebrow)
            }
            .settingsRows()

            Section {
                Stepper(value: steepBinding, in: 30...900, step: 15) {
                    SettingsValueRow(title: "Steep", value: SteepText.duration(seconds: steepSeconds))
                }
                .accessibilityValue(SteepText.spoken(seconds: steepSeconds))
                HStack {
                    Text("Rating").leafStyle(.uiBody)
                    Spacer(minLength: Space.s)
                    TeaLeafRating(rating: $rating)
                }
                TextField("Notes", text: $notes, prompt: Text("How you like it, where it came from"), axis: .vertical)
                    .leafStyle(.uiBody)
                    .lineLimit(2...6)
                if editing != nil {
                    Toggle(isOn: $isOutOf) {
                        Text("Run out for now").leafStyle(.uiBody)
                    }
                }
            } header: {
                Text("How you take it").leafStyle(.eyebrow)
            } footer: {
                Text("A regular cup’s steep. “Light” and “Strong” in the ritual go a little shorter or longer.")
                    .leafStyle(.caption)
            }
            .settingsRows()

            if editing != nil {
                Section {
                    Button("Take out of the cabinet", role: .destructive) {
                        confirmsRemoval = true
                    }
                } footer: {
                    Text("Sittings and tasting notes keep its name.")
                        .leafStyle(.caption)
                }
                .settingsRows()
            }
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .foregroundStyle(Color.ink)
        .tint(Color.accent)
        .navigationTitle(editing == nil ? "A tea of your own" : (trimmedName.isEmpty ? "Your tea" : trimmedName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing == nil ? "Add" : "Save") { save() }
                    .disabled(trimmedName.isEmpty)
            }
        }
        .confirmationDialog("Take it out of the cabinet?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Take it out", role: .destructive) {
                if let editing { store.removeCabinetTea(editing.id) }
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        }
    }

    private var steepBinding: Binding<Int> {
        Binding(
            get: { steepSeconds },
            set: { value in
                Haptics.shared.selection()
                steepTouched = true
                steepSeconds = value
            }
        )
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        Haptics.shared.success()
        if var tea = editing {
            tea.name = trimmedName
            tea.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
            tea.family = family
            tea.steepSeconds = steepSeconds
            tea.rating = rating
            tea.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            tea.isOutOf = isOutOf
            store.updateCabinetTea(tea)
        } else {
            store.addCabinetTea(CabinetTea(
                name: trimmedName,
                brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
                family: family,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                steepSeconds: steepSeconds,
                rating: rating,
                addedAt: store.now
            ))
        }
        dismiss()
    }
}
