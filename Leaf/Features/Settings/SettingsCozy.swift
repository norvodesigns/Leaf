import SwiftUI

// Settings sections added in UI-5: tea and sound, the plan's kinder options, greetings and the Lock Screen, and
// iCloud. Each is a `Section` for SettingsView's `Form`.

private func sectionHeader(_ title: String, accent: CanopyAccent = .forest) -> some View {
    Text(title).settingsHeader(accent)
}

private func settingsFooter(_ text: String) -> some View {
    Text(text).canopyText(.caption)
}

// MARK: - Tea and sound

/// Favourite tea and how strong, the length of a cup, the ambience and its level, and sound cues. Sound is opt-in:
/// silence and no cues until the reader chooses otherwise.
struct SettingsTeaSection: View {
    @Environment(LibraryStore.self) private var store
    @State private var strength = CozySettings.teaStrength
    @State private var cues = CozySettings.soundCues
    @State private var volume = 0.5
    @AppStorage(NookScene.storageKey) private var nookScene: NookScene = .plain

    private static let cupChoices = [15, 20, 25, 30, 40, 45, 50, 60]

    var body: some View {
        Section {
            NavigationLink {
                TeaCabinetView()
            } label: {
                SettingsValueRow(title: "Tea cabinet", value: cabinetValue)
            }

            NavigationLink {
                TeaRatingsView()
            } label: {
                Text("Rate your teas").canopyText(.body)
            }

            NavigationLink {
                TeaPreferencesView()
            } label: {
                Text("Teas you like").canopyText(.body)
            }

            NavigationLink {
                TeaHistoryView()
            } label: {
                Text("Tea history").canopyText(.body)
            }

            Picker(selection: teaBinding) {
                Text("Suggest one").tag(String?.none)
                ForEach(TeaCatalog.all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { tea in
                    Text(tea.name).tag(Optional(tea.id))
                }
                ForEach(store.data.cabinet.filter { $0.catalogID == nil }) { tea in
                    Text(tea.name).tag(Optional(tea.teaID))
                }
            } label: {
                Text("Favourite tea").canopyText(.body)
            }
            .pickerStyle(.menu)

            Picker(selection: $strength) {
                ForEach(TeaStrength.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Text("Strength").canopyText(.body)
            }
            .pickerStyle(.segmented)
            .onChange(of: strength) { _, value in
                CanopyFeel.play(.select)
                CozySettings.teaStrength = value
            }
            .accessibilityLabel("Tea strength")

            Picker(selection: cupBinding) {
                ForEach(Self.cupChoices, id: \.self) { Text("\($0) min").tag($0) }
            } label: {
                Text("A cup of reading").canopyText(.body)
            }
            .pickerStyle(.menu)
        } header: {
            sectionHeader("Tea", accent: .clay)
        } footer: {
            settingsFooter("The ritual offers the teas in your cabinet, or Leaf’s when it’s empty. A cup is \(store.preferences.cupMinutes) minutes of reading; strength sets how long the tea steeps before it starts.")
        }
        .settingsRows()

        Section {
            Picker(selection: $nookScene) {
                ForEach(NookScene.allCases) { scene in
                    Label(scene.name, systemImage: scene.symbol).tag(scene)
                }
            } label: {
                Text("Scene").canopyText(.body)
            }
            .pickerStyle(.menu)
        } header: {
            sectionHeader("Reading nook")
        } footer: {
            settingsFooter("What sits behind a reading session. \(nookScene.blurb) Scenes are pictures only; sound is its own choice below.")
        }
        .settingsRows()

        Section {
            Picker(selection: ambienceBinding) {
                ForEach(AmbienceCatalog.all) { ambience in
                    Text(ambience.name).tag(ambience.id == AmbienceCatalog.silenceID ? String?.none : Optional(ambience.id))
                }
            } label: {
                Text("Ambience").canopyText(.body)
            }
            .pickerStyle(.menu)

            if store.preferences.ambienceID != nil {
                VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                    Text("Starting volume").canopyText(.body)
                    Slider(value: volumeBinding, in: 0...1) {
                        Text("Starting volume")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill").foregroundStyle(Canopy.textTertiary)
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(Canopy.textTertiary)
                    }
                }
                .padding(.vertical, Canopy.Space.xs)
            }

            Toggle(isOn: $cues) {
                Text("Sound cues").canopyText(.body)
            }
            .onChange(of: cues) { _, isOn in
                CanopyFeel.play(.select)
                CozySettings.soundCues = isOn
            }
        } header: {
            sectionHeader("Sound")
        } footer: {
            settingsFooter("Leaf is silent unless you choose a sound. Your ambience is offered first when you read and only plays once you tap it; cues (the kettle, the pour) follow the silent switch.")
        }
        .settingsRows()
        .onAppear(perform: syncVolume)
        .onChange(of: store.preferences.ambienceID) { _, _ in syncVolume() }
    }

    /// Only the reader's own drag saves a level; showing the sound's default doesn't.
    private var volumeBinding: Binding<Double> {
        Binding(
            get: { volume },
            set: { level in
                volume = level
                CozySettings.ambienceVolume = level
                if AmbiencePlayer.shared.isPlaying { AmbiencePlayer.shared.setVolume(Float(level)) }
            }
        )
    }

    /// The level a chosen ambience will really start at: yours once you've set one, else that sound's own.
    private func syncVolume() {
        volume = CozySettings.ambienceVolume
            ?? AmbienceCatalog.all.first { $0.id == store.preferences.ambienceID }?.defaultVolume
            ?? 0.5
    }

    /// "4 teas", "4 teas · 1 run out", or "Empty".
    private var cabinetValue: String {
        let cabinet = store.data.cabinet
        guard !cabinet.isEmpty else { return "Empty" }
        let out = cabinet.filter(\.isOutOf).count
        let teas = "\(cabinet.count) \(cabinet.count == 1 ? "tea" : "teas")"
        return out == 0 ? teas : "\(teas) · \(out) run out"
    }

    private var teaBinding: Binding<String?> {
        Binding(
            // A favourite that has left the cabinet shows as "Suggest one" rather than as no choice at all.
            get: {
                guard let id = store.preferences.favoriteTeaID else { return nil }
                let ownIDs = store.data.cabinet.filter { $0.catalogID == nil }.map(\.teaID)
                return TeaCatalog.tea(id: id) != nil || ownIDs.contains(id) ? id : nil
            },
            set: { id in
                CanopyFeel.play(.select)
                store.updatePreferences { $0.favoriteTeaID = id }
            }
        )
    }

    private var cupBinding: Binding<Int> {
        Binding(
            get: { Self.cupChoices.contains(store.preferences.cupMinutes) ? store.preferences.cupMinutes : 25 },
            set: { minutes in
                CanopyFeel.play(.select)
                store.updatePreferences { $0.cupMinutes = minutes }
            }
        )
    }

    /// Choosing an ambience here only remembers it; nothing plays until a session does.
    private var ambienceBinding: Binding<String?> {
        Binding(
            get: { store.preferences.ambienceID },
            set: { id in
                CanopyFeel.play(.select)
                store.updatePreferences { $0.ambienceID = id }
                if id == nil { AmbiencePlayer.shared.stop() }
            }
        )
    }
}

// MARK: - Plan extras

/// When days are missed, the year's goal, and the Sunday letter.
struct SettingsPlanSection: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Section {
            Picker(selection: catchUpBinding) {
                Text("Forgive").tag(CatchUpMode.forgive)
                Text("Shift the dates").tag(CatchUpMode.shift)
                Text("Catch up gently").tag(CatchUpMode.compress)
            } label: {
                Text("Missed days").canopyText(.body)
            }
            .pickerStyle(.menu)

            Stepper(value: goalBinding, in: 0...200) {
                HStack {
                    Text("Books this year").canopyText(.body)
                    Spacer()
                    Text(goalText).canopyText(.body, color: Canopy.textSecondary).monospacedDigit()
                }
            }
            .accessibilityValue(store.preferences.yearlyGoal.map { "\($0) books" } ?? "No goal")

            Toggle(isOn: letterBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly letter").canopyText(.body)
                    Text("A short note on Sunday evenings").canopyText(.caption)
                }
            }
        } header: {
            sectionHeader("Plan")
        } footer: {
            settingsFooter(catchUpFooter + " Pages or percent is set per book: open a book and tap its page line.")
        }
        .settingsRows()
    }

    private var goalText: String {
        store.preferences.yearlyGoal.map { "\($0)" } ?? "No goal"
    }

    private var catchUpFooter: String {
        switch store.preferences.catchUp {
        case .forgive: "Missed a day? Leaf moves on. Nothing to make up, and no guilt."
        case .shift: "Missed a day? Leaf tells you how far your finish dates moved."
        case .compress: "Missed a day? Leaf suggests a few extra minutes a day until you’re back on track."
        }
    }

    private var catchUpBinding: Binding<CatchUpMode> {
        Binding(
            get: { store.preferences.catchUp },
            set: { mode in
                CanopyFeel.play(.select)
                store.updatePreferences { $0.catchUp = mode }
            }
        )
    }

    /// 0 means no goal.
    private var goalBinding: Binding<Int> {
        Binding(
            get: { store.preferences.yearlyGoal ?? 0 },
            set: { value in
                CanopyFeel.play(.select)
                store.updatePreferences { $0.yearlyGoal = value > 0 ? value : nil }
            }
        )
    }

    private var letterBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.weeklyLetter },
            set: { isOn in
                CanopyFeel.play(.select)
                store.updatePreferences { $0.weeklyLetter = isOn }
                if isOn { Task { _ = await Reminders.shared.requestAuthorization() } }
            }
        )
    }
}

// MARK: - Greetings and the Lock Screen

/// Apple Intelligence greetings (only where the device has it) and the reading Live Activity.
struct SettingsExtrasSection: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Section {
            Toggle(isOn: aiBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence greetings").canopyText(.body)
                    Text(AILibrarian.isAvailable ? "Written on this iPhone, never sent anywhere" : "Needs a device with Apple Intelligence turned on")
                        .canopyText(.caption)
                }
            }
            .disabled(!AILibrarian.isAvailable)

            Toggle(isOn: liveBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Activity while reading").canopyText(.body)
                    Text("The timer on the Lock Screen and in the Dynamic Island").canopyText(.caption)
                }
            }
        } header: {
            sectionHeader("Greetings and Lock Screen")
        } footer: {
            settingsFooter("Greetings fall back to Leaf’s own when Apple Intelligence is off.")
        }
        .settingsRows()
    }

    private var aiBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.aiGreetings && AILibrarian.isAvailable },
            set: { isOn in
                CanopyFeel.play(.select)
                store.updatePreferences { $0.aiGreetings = isOn }
            }
        )
    }

    private var liveBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.liveActivities },
            set: { isOn in
                CanopyFeel.play(.select)
                store.updatePreferences { $0.liveActivities = isOn }
                LiveActivityController.shared.sync()
            }
        )
    }
}

// MARK: - iCloud

/// Where sync stands, how much is waiting to go up, and a way to sync now.
struct SettingsCloudSection: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Section {
            HStack(spacing: Canopy.Space.m) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).canopyText(.body)
                    if let detail = statusDetail {
                        Text(detail)
                            .canopyText(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if let sync = store.sync, sync.isPausedForNewAccount {
                Button {
                    CanopyFeel.play(.tap)
                    sync.useCurrentAccount()
                } label: {
                    Text("Sync with this account")
                        .font(CanopyType.body.font)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
            } else if let sync = store.sync, sync.status.isRunning {
                Button {
                    CanopyFeel.play(.tap)
                    sync.forceFullSync()
                } label: {
                    Text("Sync now")
                        .font(CanopyType.body.font)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .disabled(sync.status == .syncing)
            }
        } header: {
            sectionHeader("iCloud")
        } footer: {
            settingsFooter(cloudFooter)
        }
        .settingsRows()
    }

    private var status: SyncStatus { store.sync?.status ?? .off }

    private var cloudFooter: String {
        switch status {
        case .noAccount:
            return "Sign in to iCloud on this iPhone and Leaf keeps a copy of your library there, in your own account."
        case .off:
            return "Your library is kept on this iPhone only."
        default:
            return "Your library is kept in your own iCloud, so it survives a new phone and stays the same on your iPad. No account, nothing anywhere else."
        }
    }

    private var statusTitle: String {
        switch status {
        case .off: "Not syncing"
        case .noAccount: "Not signed in to iCloud"
        case .idle(let last): last == nil ? "Getting ready" : "Up to date"
        case .syncing: "Syncing…"
        case .error: "Needs a look"
        }
    }

    private var statusDetail: String? {
        let pending = store.sync?.pendingChanges ?? 0
        switch status {
        case .off: return CloudSync.isAvailable ? "Sync starts when iCloud is available." : "This build doesn’t include iCloud."
        case .noAccount: return "Sign in to iCloud in the Settings app to keep a copy there."
        case .idle(let last):
            var parts: [String] = []
            if let last { parts.append("Last synced \(last.formatted(.relative(presentation: .named)))") }
            if pending > 0 { parts.append("\(pending) \(pending == 1 ? "change" : "changes") waiting") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .syncing: return pending > 0 ? "\(pending) \(pending == 1 ? "change" : "changes") to send" : nil
        case .error(let message): return message
        }
    }

    private var symbol: String {
        switch status {
        case .off, .noAccount: "icloud.slash"
        case .idle: "checkmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .error: "exclamationmark.icloud"
        }
    }

    private var tint: Color {
        switch status {
        case .idle: .accent
        case .error: .ribbon
        default: .inkTertiary
        }
    }
}
