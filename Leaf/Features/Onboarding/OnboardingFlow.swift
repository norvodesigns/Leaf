import SwiftUI

enum OnboardingStep: String, CaseIterable {
    case welcome, speedtest, quiz, result, minutes, days, reminder, deck, books
}

/// First-run onboarding (docs/design/REDESIGN.md §4.10): welcome, the daily minutes, the reading days, a reading
/// time and the first books. The speed test is no longer on the way in: Leaf starts from a typical pace and learns
/// from real sessions, and the test stays in Settings. Its steps remain here for `startAt` (screenshots, previews). Everything is saved through `LibraryStore`
/// as the reader goes; `onFinish` runs when they leave the last step.
///
/// `startAt` lands directly on a step with plausible state, for screenshots and previews:
/// `speedtest` is mid-passage with the clock running, `quiz` is on the first question, `result`
/// shows the recorded test or a sample at about 262 words a minute.
struct OnboardingFlow: View {
    var startAt: OnboardingStep
    var onFinish: () -> Void

    @Environment(LibraryStore.self) private var store

    init(startAt: OnboardingStep = .welcome, onFinish: @escaping () -> Void) {
        self.startAt = startAt
        self.onFinish = onFinish
    }

    var body: some View {
        // The flow's own state is seeded once from the store, so it reads the store here.
        OnboardingFlowBody(
            startAt: startAt,
            preferences: store.preferences,
            recordedTest: store.latestSpeedTest,
            onFinish: onFinish
        )
    }
}

/// The running flow. Its state is created once from the values the store held when it opened.
private struct OnboardingFlowBody: View {
    let startAt: OnboardingStep
    let onFinish: () -> Void

    @Environment(LibraryStore.self) private var store

    /// The current step. The three test steps share `.speedtest`; the test's own stage says which
    /// of speedtest, quiz or result is showing (see `displayStep`).
    @State private var step: OnboardingStep
    @State private var test: SpeedTestController
    @State private var minutes: Int
    @State private var days: Set<Int>
    @State private var reminderTime: Date
    @State private var extraTime: OnboardingExtraTime?
    @State private var reminderDeclined = false
    @State private var isRequestingPermission = false
    @State private var picks: [Book] = []
    @State private var recordedResult: SpeedTestResult?

    private struct PageKey: Hashable {
        let step: OnboardingStep
        let stage: SpeedTestProgress.Stage?
    }

    init(startAt: OnboardingStep, preferences: ReadingPreferences, recordedTest: SpeedTestResult?, onFinish: @escaping () -> Void) {
        self.startAt = startAt
        self.onFinish = onFinish

        switch startAt {
        case .speedtest, .quiz, .result:
            _step = State(initialValue: .speedtest)
        default:
            _step = State(initialValue: startAt)
        }

        // Past the test, a staged result is behind the reader so Back has somewhere to go.
        let stage: SpeedTestProgress.Stage
        switch startAt {
        case .welcome: stage = .intro
        case .speedtest: stage = .reading
        case .quiz: stage = .quiz
        default: stage = .result
        }
        let passage = recordedTest
            .flatMap { recorded in SpeedTestPassages.all.first { $0.id == recorded.passageID } }
            ?? SpeedTestPassages.all[0]
        _test = State(initialValue: SpeedTestController(passage: passage, stage: stage, result: recordedTest))

        _minutes = State(initialValue: min(max(preferences.dailyMinutes, MinutesDial.range.lowerBound), MinutesDial.range.upperBound))
        // A first run starts from a working week; the weekend is a rest.
        let isFirstRun = !preferences.hasOnboarded && preferences.readingDays.count == 7
        _days = State(initialValue: isFirstRun ? [2, 3, 4, 5, 6] : preferences.readingDays)
        _reminderTime = State(initialValue: Self.date(hour: preferences.reminderHour, minute: preferences.reminderMinute))
    }

    // MARK: - Where we are

    private var displayStep: OnboardingStep {
        guard step == .speedtest else { return step }
        switch test.progress.stage {
        case .intro, .countdown, .reading: return .speedtest
        case .quiz: return .quiz
        case .result: return .result
        }
    }

    private var pageKey: AnyHashable {
        AnyHashable(PageKey(step: displayStep, stage: step == .speedtest ? test.progress.stage : nil))
    }

    /// The steps a first run walks through; the speed test is off the path.
    private static let path: [OnboardingStep] = [.welcome, .minutes, .days, .reminder, .deck, .books]

    private var folio: Int {
        Self.path.firstIndex(of: displayStep) ?? 0
    }

    // MARK: - Body

    var body: some View {
        OnboardingScreen(
            pageKey: pageKey,
            leading: leadingControl,
            note: note,
            primary: primaryAction,
            secondary: secondaryAction,
            secondaryColor: displayStep == .result ? Color.accent : Color.inkSecondary,
            folio: folio,
            folioCount: Self.path.count
        ) {
            page
        }
    }

    @ViewBuilder
    private var page: some View {
        switch displayStep {
        case .welcome:
            OnboardingWelcomeView()
        case .speedtest, .quiz, .result:
            SpeedTestStageBody(controller: test)
        case .minutes:
            OnboardingMinutesView(minutes: $minutes, wpm: store.wpm, daysPerWeek: days.count)
        case .days:
            OnboardingDaysView(days: $days, minutes: minutes)
        case .reminder:
            OnboardingTimesView(hour: reminderHour, minute: reminderMinute, extra: $extraTime, message: reminderPreview)
        case .deck:
            OnboardingDeckView(picks: $picks)
        case .books:
            OnboardingBooksView(
                picks: $picks,
                wpm: store.wpm,
                existingIDs: Set(store.data.items.map(\.id)),
                stagesPicks: startAt == .books
            )
        }
    }

    // MARK: - Chrome

    private var leadingControl: OnboardingLeadingControl? {
        switch displayStep {
        case .welcome, .result:
            return nil
        default:
            return OnboardingLeadingControl(systemImage: "chevron.left", label: "Back") {
                goBack()
            }
        }
    }

    private var note: Text? {
        switch displayStep {
        case .reminder:
            return reminderDeclined ? Text("No reminders. Leaf will be here when you are.") : nil
        case .books:
            // The optional sync note: only where iCloud is on offer.
            return Text(store.sync?.status.isRunning == true ? stackNote + " Your shelves are kept in your own iCloud too, so they follow you to a new phone." : stackNote)
        default:
            return nil
        }
    }

    private var testActions: (primary: OnboardingAction?, secondary: OnboardingAction?) {
        test.actions(
            resultTitle: "Continue",
            introSecondary: OnboardingAction("Skip the test") { skipTest() },
            onResult: acceptResult
        )
    }

    private var primaryAction: OnboardingAction? {
        switch displayStep {
        case .welcome:
            return OnboardingAction("Get started") { step = .minutes }
        case .speedtest, .quiz, .result:
            return testActions.primary
        case .minutes:
            return OnboardingAction("Continue") { saveMinutes() }
        case .days:
            return OnboardingAction("Continue", isEnabled: !days.isEmpty) { saveDays() }
        case .reminder:
            if reminderDeclined {
                // Keeps a time changed after declining; without reminders it still shapes the plan.
                return OnboardingAction("Continue") { skipReminder() }
            }
            return OnboardingAction("Allow notifications", isLoading: isRequestingPermission) { allowNotifications() }
        case .deck:
            return OnboardingAction(picks.isEmpty ? "Continue" : "Continue with \(picks.count)") { step = .books }
        case .books:
            return OnboardingAction("Make my plan", isEnabled: !picks.isEmpty) { makePlan() }
        }
    }

    private var secondaryAction: OnboardingAction? {
        switch displayStep {
        case .speedtest, .quiz, .result:
            return testActions.secondary
        case .reminder:
            return reminderDeclined ? nil : OnboardingAction("Not now") { skipReminder() }
        case .deck:
            return picks.isEmpty ? OnboardingAction("Skip") { step = .books } : nil
        case .books:
            return OnboardingAction("Skip for now") { onFinish() }
        default:
            return nil
        }
    }

    // MARK: - Moving

    private func goBack() {
        switch displayStep {
        case .welcome, .result:
            break
        case .speedtest, .quiz:
            if test.canStepBack {
                test.stepBack()
            } else {
                step = .welcome
            }
        case .minutes:
            step = .welcome
        case .days:
            step = .minutes
        case .reminder:
            reminderDeclined = false
            step = .days
        case .deck:
            step = .reminder
        case .books:
            step = .deck
        }
    }

    /// "Skip the test": keep whatever pace the store already holds and move on.
    private func skipTest() {
        step = .minutes
    }

    /// "Continue" on the result: the test is saved (once), and the pace feeds the next step.
    private func acceptResult() {
        guard let result = test.result else { return }
        if recordedResult != result {
            store.recordSpeedTest(result)
            recordedResult = result
        }
        step = .minutes
    }

    private func saveMinutes() {
        let chosen = minutes
        store.updatePreferences { $0.dailyMinutes = chosen }
        step = .days
    }

    private func saveDays() {
        let chosen = days
        guard !chosen.isEmpty else { return }
        store.updatePreferences { $0.readingDays = chosen }
        step = .reminder
    }

    // MARK: - Reminder

    private func allowNotifications() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        Task {
            let granted = await Reminders.shared.requestAuthorization()
            isRequestingPermission = false
            saveReminder(enabled: granted)
            if granted {
                Haptics.shared.success()
                step = .deck
            } else {
                reminderDeclined = true
            }
        }
    }

    private func skipReminder() {
        saveReminder(enabled: false)
        step = .deck
    }

    /// Saves the first reading times (and whether they remind), replacing any set earlier in this flow.
    private func saveReminder(enabled: Bool) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let hour = parts.hour ?? 20
        let minute = parts.minute ?? 30
        // No stored label: Today names the slot by its hour, so it stays right if the time moves later.
        var slots = [ReadingSlot(hour: hour, minute: minute)]
        if let extraTime, extraTime.hour * 60 + extraTime.minute != hour * 60 + minute {
            slots.append(ReadingSlot(hour: extraTime.hour, minute: extraTime.minute, label: extraTime.label))
        }
        let ordered = slots.sorted { $0.minuteOfDay < $1.minuteOfDay }
        store.updatePreferences {
            $0.reminderEnabled = enabled
            $0.reminderHour = hour
            $0.reminderMinute = minute
            $0.readingSlots = ordered
        }
    }

    private var reminderHour: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: reminderTime) },
            set: { reminderTime = Self.date(hour: $0, minute: Calendar.current.component(.minute, from: reminderTime)) }
        )
    }

    private var reminderMinute: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: reminderTime) },
            set: { reminderTime = Self.date(hour: Calendar.current.component(.hour, from: reminderTime), minute: $0) }
        )
    }

    /// The real reminder body for the chosen time: today's assignment when there is one, otherwise a
    /// first-book line written from the reader's pace.
    private var reminderPreview: String {
        let hour = Calendar.current.component(.hour, from: reminderTime)
        if let first = store.todayAssignments.first {
            return OnboardingCopy.reminderBody(
                minutes: max(1, Int(first.assignment.minutes.rounded())),
                title: first.item.book.title,
                from: first.assignment.fromPage,
                to: first.assignment.toPage,
                hour: hour
            )
        }
        return OnboardingCopy.reminderBody(minutes: minutes, wpm: store.wpm, hour: hour)
    }

    // MARK: - Books

    /// "Your stack: 3 books · about 6 weeks."
    private var stackNote: String {
        guard !picks.isEmpty else { return "Pick a few and Leaf will plan the pages." }
        let wpm = store.wpm
        let totalMinutes = picks.reduce(0.0) { $0 + $1.minutes(atWPM: wpm) }
        let count = picks.count == 1 ? "1 book" : "\(picks.count) books"
        if let span = OnboardingCopy.stackSpan(minutes: totalMinutes, dailyMinutes: minutes, daysPerWeek: max(1, days.count)) {
            return "Your stack: \(count) · \(span)."
        }
        return "Your stack: \(count)."
    }

    /// The first pick goes to Reading and the rest to To read, in the order they were tapped.
    private func makePlan() {
        for (index, book) in picks.enumerated() {
            store.add(book, to: index == 0 ? .reading : .toRead)
        }
        Haptics.shared.success()
        onFinish()
    }

    // MARK: - Helpers

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: min(max(hour, 0), 23), minute: min(max(minute, 0), 59), second: 0, of: Date()) ?? Date()
    }
}

// MARK: - Previews

@MainActor
private func onboardingPreviewStore(demo: Bool) -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    if demo { store.replaceAll(with: DemoData.make()) }
    return store
}

#Preview("Welcome") {
    OnboardingFlow(startAt: .welcome) {}
        .environment(onboardingPreviewStore(demo: true))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Speed test") {
    OnboardingFlow(startAt: .speedtest) {}
        .environment(onboardingPreviewStore(demo: true))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Quiz") {
    OnboardingFlow(startAt: .quiz) {}
        .environment(onboardingPreviewStore(demo: true))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Result") {
    OnboardingFlow(startAt: .result) {}
        .environment(onboardingPreviewStore(demo: true))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Minutes") {
    OnboardingFlow(startAt: .minutes) {}
        .environment(onboardingPreviewStore(demo: true))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Days") {
    OnboardingFlow(startAt: .days) {}
        .environment(onboardingPreviewStore(demo: true))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Reminder") {
    OnboardingFlow(startAt: .reminder) {}
        .environment(onboardingPreviewStore(demo: true))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Deck") {
    OnboardingFlow(startAt: .deck) {}
        .environment(onboardingPreviewStore(demo: false))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("First books") {
    OnboardingFlow(startAt: .books) {}
        .environment(onboardingPreviewStore(demo: false))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
