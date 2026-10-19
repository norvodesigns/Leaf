import SwiftUI

/// Step i: the wordmark bleeds in, then "Read on purpose."
struct OnboardingWelcomeView: View {
    @State private var showsTagline = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingPage {
            VStack(spacing: Space.xl) {
                Text("Leaf")
                    .leafStyle(.wordmark)
                    .inkBleed()
                    .accessibilityAddTraits(.isHeader)
                Capsule()
                    .fill(Color.ribbon)
                    .frame(width: 28, height: 2)
                    .opacity(showsTagline ? 1 : 0)
                    .accessibilityHidden(true)
                Text("Read on purpose.")
                    .leafStyle(.masthead)
                    .multilineTextAlignment(.center)
                    .opacity(showsTagline ? 1 : 0)
                    .offset(y: showsTagline || reduceMotion ? 0 : Motion.inkInRise)
            }
        }
        .task {
            // The tagline follows once the wordmark has settled.
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(900))
            }
            if Task.isCancelled { return }
            withAnimation(Motion.resolved(Motion.inkIn, reduceMotion: reduceMotion)) {
                showsTagline = true
            }
        }
    }
}

#Preview("Welcome") {
    OnboardingWelcomeView()
        .paperBackground()
}
