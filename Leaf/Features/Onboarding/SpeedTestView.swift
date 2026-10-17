import SwiftUI

/// The reading-speed test on its own: passage, questions, result. Settings presents it for a retake
/// (`router.showSpeedTest`). It picks a different passage from the last test.
///
/// `onComplete` receives the result when the reader taps "Use this pace". The result is saved to the
/// store (`recordSpeedTest`) unless `onComplete` already did, so the pace is never lost and never
/// recorded twice. The view then dismisses itself with `dismiss()`, which is harmless if the host
/// has already closed it. `onCancel` runs when the reader closes the test; without one, it dismisses.
struct SpeedTestView: View {
    var onComplete: (SpeedTestResult) -> Void
    var onCancel: (() -> Void)?

    @Environment(LibraryStore.self) private var store

    init(onComplete: @escaping (SpeedTestResult) -> Void, onCancel: (() -> Void)? = nil) {
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        SpeedTestRetakeHost(
            passage: SpeedTestPassages.passage(after: store.latestSpeedTest?.passageID),
            onComplete: onComplete,
            onCancel: onCancel
        )
    }
}

/// Owns the controller, so it is built once with the passage chosen when the test opens.
private struct SpeedTestRetakeHost: View {
    let onComplete: (SpeedTestResult) -> Void
    let onCancel: (() -> Void)?

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var controller: SpeedTestController

    init(passage: SpeedTestPassage, onComplete: @escaping (SpeedTestResult) -> Void, onCancel: (() -> Void)?) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        _controller = State(initialValue: SpeedTestController(passage: passage))
    }

    var body: some View {
        let actions = controller.actions(resultTitle: "Use this pace", onResult: useResult)
        OnboardingScreen(
            pageKey: AnyHashable(controller.progress.stage),
            leading: leadingControl,
            primary: actions.primary,
            secondary: actions.secondary,
            secondaryColor: .accent
        ) {
            SpeedTestStageBody(controller: controller, isRetake: true)
        }
    }

    private var leadingControl: OnboardingLeadingControl {
        if controller.canStepBack {
            return OnboardingLeadingControl(systemImage: "chevron.left", label: "Back") {
                controller.stepBack()
            }
        }
        return OnboardingLeadingControl(systemImage: "xmark", label: "Close") {
            cancel()
        }
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func useResult() {
        guard let result = controller.result else { return }
        onComplete(result)
        if store.latestSpeedTest != result {
            store.recordSpeedTest(result)
        }
        dismiss()
    }
}

@MainActor
private func speedTestPreviewStore() -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return store
}

#Preview("Retake") {
    SpeedTestView(onComplete: { _ in })
        .environment(speedTestPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
