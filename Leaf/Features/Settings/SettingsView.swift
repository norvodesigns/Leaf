import SwiftUI
import UIKit
import UserNotifications

/// Settings (DESIGN.md §6): a sheet with a `Form` on paper, `paperRaised` rows and eyebrow headers.
/// Pace, schedule, reminders, feel, appearance, the watch, a privacy note and a way to start over.
struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var confirmsErase = false
    @State private var watch = WatchStatus.current()

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
                    aboutSection
                    SettingsLibrarySection()
                        .id("data")
                    dataSection
                    colophonSection
                }
                .scrollContentBackground(.hidden)
                .task {
                    guard let stage = router.settingsStage else { return }
                    router.settingsStage = nil
                    try? await Task.sleep(for: .milliseconds(600))
                    proxy.scrollTo(stage, anchor: .top)
                }
            }
            .paperBackground()
            .foregroundStyle(Color.ink)
            .tint(Color.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.shared.tap()
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
        .presentationBackground(Color.paper)
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
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(wpm)")
                        .leafStyle(.statNumeral)
                        .numericBlur(value: Double(wpm))
                        .leafAnimation(Motion.paper, value: wpm)
                    Text("wpm")
                        .leafStyle(.ui, color: .inkSecondary)
                    Spacer(minLength: Space.s)
                    Chip(ReadingSpeed.descriptor(for: store.wpm), tone: .accent)
                }
                Text(paceDetail)
                    .leafStyle(.caption)
            }
            .padding(.vertical, Space.xs)
            .accessibilityElement(children: .combine)

            Button {
                retakeTest()
            } label: {
                SettingsDisclosureRow("Retake the reading test")
            }
            .buttonStyle(.plain)

            Toggle(isOn: preference(\.learnFromSessions, haptic: false)) {
                Text("Learn from my sessions")
                    .leafStyle(.uiBody)
            }
        } header: {
            header("Your pace")
        } footer: {
            Text("Real sessions nudge your pace up or down. The test is where it starts.")
                .leafStyle(.caption)
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
        Haptics.shared.tap()
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
                    .leafStyle(.uiBody)
            }
            .pickerStyle(.menu)
        } header: {
            header("Your schedule")
        } footer: {
            Text(OnboardingCopy.weeklyTime(minutes: prefs.dailyMinutes, days: prefs.readingDays.count))
                .leafStyle(.caption)
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
                .leafStyle(.caption)
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
                    Haptics.shared.play(.dialDetent)
                } else {
                    Haptics.shared.selection()
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
            Text("Night is paper at night: warm, never pure black.")
                .leafStyle(.caption)
        }
        .settingsRows()
    }

    // MARK: Apple Watch

    private var watchSection: some View {
        Section {
            Label {
                Text(watch.message)
                    .leafStyle(.uiBody)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "applewatch")
                    .foregroundStyle(watch.isInstalled ? Color.accent : Color.inkTertiary)
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
                    .leafStyle(.uiBody)
            }
            SettingsValueRow(title: "Version", value: versionString)
        } header: {
            header("About")
        }
        .settingsRows()
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
                    .leafFont(.uiBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
        } header: {
            header("Data")
        } footer: {
            Text(eraseFooter)
                .leafStyle(.caption)
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
                .leafStyle(.body, color: .inkSecondary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Space.xs)
        } header: {
            header("Colophon")
        }
        .settingsRows()
    }

    /// Closes Settings first, then clears everything once the sheet is gone, so the library is not
    /// seen emptying behind it. Onboarding takes over afterwards.
    private func eraseEverything() {
        Haptics.shared.warning()
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
            store.resetEverything()
        }
    }

    // MARK: Helpers

    private func header(_ title: String) -> some View {
        Text(title)
            .leafStyle(.eyebrow)
    }

    /// A binding to one preference that plays a selection tick when it changes.
    private func preference<Value>(_ keyPath: WritableKeyPath<ReadingPreferences, Value>, haptic: Bool = true) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { newValue in
                if haptic { Haptics.shared.selection() }
                store.updatePreferences { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}

extension View {
    /// `paperRaised` rows with `hairline` separators.
    func settingsRows() -> some View {
        listRowBackground(Color.paperRaised)
            .listRowSeparatorTint(Color.hairline)
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
