import SwiftUI
import UIKit
import UserNotifications

/// Settings (REDESIGN §4.9): an inset-grouped list on the Canopy backdrop, cream rows, section labels in their job's
/// accent. Reading (pace, schedule, reading times, the plan), tea and the nook, feel, appearance, greetings, the
/// watch, iCloud, your library and data, then about.
struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confirmsErase = false
    @State private var watch = WatchStatus.current()
    /// Seven taps on the version number reveal the Sound lab outside debug builds.
    @AppStorage("settings.soundLab") private var soundLabUnlocked = false
    @State private var versionTaps = 0
    @State private var showsSoundLab = false
    @State private var showsWhatsNew = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    paceSection
                    scheduleSection
                    ReadingTimesSection()
                    SettingsPlanSection()
                        .id("plan")
                    SettingsTeaSection()
                        .id("tea")
                    feelSection
                    appearanceSection
                    SettingsExtrasSection()
                    if watch.isSupported {
                        watchSection
                    }
                    SettingsCloudSection()
                        .id("cloud")
                    SettingsLibrarySection()
                        .id("data")
                    dataSection
                    aboutSection
                    colophonSection
                }
                .scrollContentBackground(.hidden)
                .task {
                    guard let stage = router.settingsStage else { return }
                    router.settingsStage = nil
                    if stage == "soundlab" {
                        showsSoundLab = true
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(600))
                    proxy.scrollTo(stage, anchor: .top)
                }
                .navigationDestination(isPresented: $showsSoundLab) {
                    SoundLabView()
                }
                .sheet(isPresented: $showsWhatsNew) {
                    WhatsNewView(releases: WhatsNew.releases, build: WhatsNew.currentBuild)
                }
            }
            .canopyBackdrop()
            .foregroundStyle(Canopy.text)
            .tint(CanopyAccent.forest.color)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        CanopyFeel.play(.tap)
                        router.showSettings = false
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Erase all data?", isPresented: $confirmsErase, titleVisibility: .visible) {
                Button("Erase all data", role: .destructive) {
                    eraseEverything()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(eraseMessage)
            }
        }
        .presentationBackground(Canopy.canvas)
        .onAppear {
            watch = WatchStatus.current()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                watch = WatchStatus.current()
            }
        }
    }

    // MARK: Your pace

    private var paceSection: some View {
        let wpm = Int(store.wpm.rounded())
        return Section {
            HStack(alignment: .firstTextBaseline, spacing: Canopy.Space.s) {
                CanopyStat(value: "\(wpm)", unit: "wpm", caption: paceDetail)
                    .animation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion), value: wpm)
                Spacer(minLength: Canopy.Space.s)
                Text(ReadingSpeed.descriptor(for: store.wpm))
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(CanopyAccent.forest.color)
                    .padding(.horizontal, Canopy.Space.m)
                    .padding(.vertical, Canopy.Space.xs)
                    .background(CanopyAccent.forest.soft, in: .capsule)
            }
            .padding(.vertical, Canopy.Space.xs)
            .accessibilityElement(children: .combine)

            Button {
                retakeTest()
            } label: {
                SettingsDisclosureRow("Retake the reading test")
            }
            .buttonStyle(.plain)

            Toggle(isOn: preference(\.learnFromSessions, haptic: false)) {
                Text("Learn from my sessions")
                    .canopyText(.body)
            }
        } header: {
            header("Your pace", accent: .dusk)
        } footer: {
            Text("Real sessions nudge your pace up or down. The test is where it starts.")
                .canopyText(.caption)
        }
        .settingsRows()
    }

    /// "Refined from 14 sessions.", or where the number came from when sessions aren't teaching it.
    private var paceDetail: String {
        let sessions = store.data.sessions.count
        if store.preferences.learnFromSessions && sessions > 0 {
            return "Refined from \(sessions) \(sessions == 1 ? "session" : "sessions")."
        }
        if let test = store.latestSpeedTest {
            return "From your reading test on \(LeafFormat.shortDate(test.date, today: store.now, calendar: store.calendar))."
        }
        return "A typical adult pace, until you take the test."
    }

    private func retakeTest() {
        CanopyFeel.play(.tap)
        // The shell presents the test over this sheet, so you land back here with the new pace.
        router.showSpeedTest = true
    }

    // MARK: Your schedule

    private var scheduleSection: some View {
        let prefs = store.preferences
        return Section {
            NavigationLink {
                SettingsMinutesPage()
            } label: {
                SettingsValueRow(title: "Minutes a day", value: "\(prefs.dailyMinutes) min")
            }

            NavigationLink {
                SettingsDaysPage()
            } label: {
                SettingsValueRow(title: "Reading days", value: daysValue(prefs.readingDays.count))
            }

            Picker(selection: preference(\.planMode)) {
                Text("One at a time").tag(PlanMode.focus)
                Text("Side by side").tag(PlanMode.sideBySide)
            } label: {
                Text("Plan style")
                    .canopyText(.body)
            }
            .pickerStyle(.menu)
        } header: {
            header("Your schedule", accent: .dusk)
        } footer: {
            Text(OnboardingCopy.weeklyTime(minutes: prefs.dailyMinutes, days: prefs.readingDays.count))
                .canopyText(.caption)
        }
        .settingsRows()
    }

    private func daysValue(_ count: Int) -> String {
        switch count {
        case 7: return "Every day"
        case 1: return "1 day"
        default: return "\(count) days"
        }
    }

    // MARK: Feel and appearance

    private var feelSection: some View {
        Section {
            Picker(selection: hapticsBinding) {
                Text("Full").tag(HapticsLevel.full)
                Text("Subtle").tag(HapticsLevel.subtle)
                Text("Off").tag(HapticsLevel.off)
            } label: {
                Text("Haptics")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            header("Feel")
        } footer: {
            Text(hapticsFooter)
                .canopyText(.caption)
        }
        .settingsRows()
    }

    private var hapticsFooter: String {
        switch store.preferences.hapticsLevel {
        case .full: return "Signature taps for turning a page, finishing a book and the dials."
        case .subtle: return "Subtle keeps to the system’s lighter taps."
        case .off: return "Leaf stays still."
        }
    }

    private var hapticsBinding: Binding<HapticsLevel> {
        Binding(
            get: { store.preferences.hapticsLevel },
            set: { newValue in
                store.updatePreferences { $0.hapticsLevel = newValue }
                // Let the new level introduce itself.
                if newValue == .full {
                    CanopyFeel.play(.snap)
                } else {
                    CanopyFeel.play(.select)
                }
            }
        )
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: preference(\.appearance)) {
                Text("System").tag(AppearancePreference.system)
                Text("Day").tag(AppearancePreference.day)
                Text("Night").tag(AppearancePreference.night)
            } label: {
                Text("Appearance")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            header("Appearance")
        } footer: {
            Text("Night is a warm charcoal with cream text, never pure black.")
                .canopyText(.caption)
        }
        .settingsRows()
    }

    // MARK: Apple Watch

    private var watchSection: some View {
        Section {
            Label {
                Text(watch.message)
                    .canopyText(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "applewatch")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(watch.isInstalled ? CanopyAccent.forest.color : Canopy.textTertiary)
            }
        } header: {
            header("Apple Watch")
        }
        .settingsRows()
    }

    // MARK: About, data, colophon

    private var aboutSection: some View {
        Section {
            NavigationLink {
                PrivacyNoteView()
            } label: {
                Text("Privacy")
                    .canopyText(.body)
            }
            settingsLink("What’s new") {
                showsWhatsNew = true
            }
            SettingsValueRow(title: "Version", value: versionString)
                .contentShape(.rect)
                .onTapGesture {
                    versionTaps += 1
                    if versionTaps >= 7 && !soundLabUnlocked {
                        soundLabUnlocked = true
                        CanopyFeel.play(.saved)
                    }
                }
            if showsSoundLabRow {
                Button {
                    CanopyFeel.play(.tap)
                    showsSoundLab = true
                } label: {
                    HStack {
                        Text("Sound lab").canopyText(.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Canopy.textTertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } header: {
            header("About")
        }
        .settingsRows()
    }

    /// A plain row that does something, with a chevron.
    private func settingsLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            CanopyFeel.play(.tap)
            action()
        } label: {
            HStack {
                Text(title).canopyText(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Canopy.textTertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var showsSoundLabRow: Bool {
        #if DEBUG
        return true
        #else
        return soundLabUnlocked
        #endif
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                confirmsErase = true
            } label: {
                Text("Erase all data")
                    .font(CanopyType.body.font)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
        } header: {
            header("Data")
        } footer: {
            Text(eraseFooter)
                .canopyText(.caption)
        }
        .settingsRows()
    }

    /// Reset is per device (docs/SYNC.md): the iCloud copy is cleared, and other devices keep theirs.
    private var syncsToCloud: Bool { store.sync?.status.isRunning == true }

    private var eraseMessage: String {
        syncsToCloud
            ? "Your books, sessions and settings will be removed from this phone and from iCloud. Your other devices keep their own copy, and while iCloud is on they will sync it back here too; to start fresh everywhere, erase each device. This can’t be undone."
            : "Your books, sessions and settings will be removed from this phone. This can’t be undone."
    }

    private var eraseFooter: String {
        syncsToCloud
            ? "Removes your books, sessions and settings from this phone and its iCloud copy. Other devices keep theirs."
            : "Removes your books, sessions and settings from this phone."
    }

    private var colophonSection: some View {
        Section {
            Text("Set in Instrument Serif, New York and SF Pro. Book data and covers from Open Library, a project of the Internet Archive. Printed on your phone, read by you.")
                .canopyText(.body, color: Canopy.textSecondary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Canopy.Space.xs)
        } header: {
            header("Colophon")
        }
        .settingsRows()
    }

    /// Closes Settings first, then clears everything once the sheet is gone, so the library is not
    /// seen emptying behind it. Onboarding takes over afterwards.
    private func eraseEverything() {
        CanopyFeel.play(.warning)
        // Silence first: nothing keeps playing for a library that is gone.
        AmbiencePlayer.shared.stop(fadeOut: 0)
        CozySounds.shared.cancelPending()
        router.showSettings = false
        let store = store
        let router = router
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            router.showSpeedTest = false
            router.showSession = false
            router.lastOutcome = nil
            router.popToRoot()
            router.tab = .today
            router.ritual = nil
            TeaSteepState.save(nil)
            CozySettings.reset()
            LibraryTraces.erase()
            CircleStore.eraseLegacyFiles()
            CircleSharing.shared.eraseLinks()
            store.resetEverything()
        }
    }

    // MARK: Helpers

    private func header(_ title: String, accent: CanopyAccent = .forest) -> some View {
        Text(title)
            .settingsHeader(accent)
    }

    /// A binding to one preference that plays a selection tick when it changes.
    private func preference<Value>(_ keyPath: WritableKeyPath<ReadingPreferences, Value>, haptic: Bool = true) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { newValue in
                if haptic { CanopyFeel.play(.select) }
                store.updatePreferences { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}

extension View {
    /// Cream `surface` rows with `separator` hairlines.
    func settingsRows() -> some View {
        listRowBackground(Canopy.surface)
            .listRowSeparatorTint(Canopy.separator)
    }
}

// MARK: - Previews

@MainActor
private func settingsPreviewStore() -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return store
}

#Preview("Settings") {
    SettingsView()
        .environment(settingsPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Settings · dark") {
    SettingsView()
        .environment(settingsPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
        .preferredColorScheme(.dark)
}
