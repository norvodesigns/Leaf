import SwiftUI

/// Minutes a day, on its own page: the MinutesDial with a live sentence about what the pace adds up to.
struct SettingsMinutesPage: View {
    @Environment(LibraryStore.self) private var store

    private var minutes: Binding<Int> {
        Binding(
            get: {
                min(max(store.preferences.dailyMinutes, MinutesDial.range.lowerBound), MinutesDial.range.upperBound)
            },
            set: { newValue in
                store.updatePreferences { $0.dailyMinutes = newValue }
            }
        )
    }

    var body: some View {
        let preview = OnboardingCopy.minutesPreview(
            minutes: minutes.wrappedValue,
            wpm: store.wpm,
            daysPerWeek: store.preferences.readingDays.count
        )
        return VStack(spacing: Space.xl) {
            MinutesDial(minutes: minutes)
            VStack(spacing: Space.s) {
                Text(preview.quote)
                    .leafStyle(.pullQuote)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(preview.caption)
                    .leafStyle(.caption)
                    .multilineTextAlignment(.center)
            }
            .leafMargins()
            Spacer(minLength: 0)
        }
        .padding(.top, Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
        .navigationTitle("Minutes a day")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Reading days, on their own page: the WeekdayPicker with a sentence that says what it adds up to.
/// At least one day always stays on, because a plan with no reading days has no dates.
struct SettingsDaysPage: View {
    @Environment(LibraryStore.self) private var store

    @State private var triedToClear = false

    private var days: Binding<Set<Int>> {
        Binding(
            get: { store.preferences.readingDays },
            set: { newValue in
                guard !newValue.isEmpty else {
                    triedToClear = true
                    Haptics.shared.warning()
                    return
                }
                triedToClear = false
                store.updatePreferences { $0.readingDays = newValue }
            }
        )
    }

    var body: some View {
        let selected = store.preferences.readingDays
        let summary = triedToClear ? "Pick at least one day." : OnboardingCopy.weekSummary(selected)
        return VStack(spacing: Space.xl) {
            WeekdayPicker(selection: days)
                .leafMargins()
            VStack(spacing: Space.s) {
                Text(summary)
                    .leafStyle(.pullQuote)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !selected.isEmpty {
                    Text(OnboardingCopy.weeklyTime(minutes: store.preferences.dailyMinutes, days: selected.count))
                        .leafStyle(.caption)
                        .multilineTextAlignment(.center)
                }
                Text("Rest days are part of the plan.")
                    .leafStyle(.caption)
                    .multilineTextAlignment(.center)
            }
            .leafMargins()
            Spacer(minLength: 0)
        }
        .padding(.top, Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paperBackground()
        .navigationTitle("Reading days")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What Leaf keeps and where it goes, in plain words. Mirrors `docs/PRIVACY.md`.
struct PrivacyNoteView: View {
    private let contactAddress = "norvodesigns@gmail.com"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("Your reading stays yours.")
                    .leafStyle(.masthead)
                    .accessibilityAddTraits(.isHeader)
                note("No accounts", "Leaf has no accounts, no analytics and no ads, and no servers of its own.")
                note(
                    "What Leaf keeps",
                    "Your library, your reading sessions, your reading speed and your settings. All of it stays on this iPhone. A summary of today’s plan syncs straight to your paired Apple Watch. Nothing is uploaded anywhere else."
                )
                note(
                    "Book search",
                    "When you search for a book that isn’t in Leaf’s built-in catalog, what you typed is sent to Open Library, a free, non-profit catalog run by the Internet Archive, and cover images are loaded from it. The request carries only the search text, never who you are or what’s in your library."
                )
                note("Reminders", "Daily reminders are scheduled on your phone. They aren’t push notifications from a server.")
                note("Deleting your data", "Settings, then Erase all data, removes everything at once. Deleting the app does the same.")
                contact
            }
            .leafMargins()
            .padding(.vertical, Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .paperBackground()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .leafStyle(.eyebrow)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .leafStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var contact: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Questions")
                .leafStyle(.eyebrow)
                .accessibilityAddTraits(.isHeader)
            if let url = URL(string: "mailto:\(contactAddress)") {
                Link(destination: url) {
                    Text(contactAddress)
                        .leafStyle(.body, color: .accent)
                }
            } else {
                Text(contactAddress)
                    .leafStyle(.body)
            }
        }
    }
}

#Preview("Privacy") {
    NavigationStack {
        PrivacyNoteView()
    }
}
