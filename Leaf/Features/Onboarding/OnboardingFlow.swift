import SwiftUI

enum OnboardingStep: String, CaseIterable {
    case welcome, speedtest, quiz, result, minutes, days, reminder, books
}

/// Placeholder until the onboarding screens land.
struct OnboardingFlow: View {
    var startAt: OnboardingStep = .welcome
    var onFinish: () -> Void

    var body: some View {
        Button("Start", action: onFinish)
    }
}
