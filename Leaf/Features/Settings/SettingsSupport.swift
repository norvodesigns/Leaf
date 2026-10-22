import SwiftUI
import WatchConnectivity

extension View {
    /// A Settings section header in Canopy: the section's accent, sentence case (REDESIGN §4.9).
    func settingsHeader(_ accent: CanopyAccent = .forest) -> some View {
        canopyText(.label, color: accent.color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A Form row with a title and a quieter value on the right ("Minutes a day · 25 min").
struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Canopy.Space.s) {
            Text(title)
                .canopyText(.body)
            Spacer(minLength: Canopy.Space.s)
            Text(value)
                .canopyText(.body, color: Canopy.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A tappable Form row that ends in a chevron, for actions that open something ("Retake the reading test").
struct SettingsDisclosureRow: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: Canopy.Space.s) {
            Text(title)
                .canopyText(.body)
            Spacer(minLength: Canopy.Space.s)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Canopy.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// Where the paired Apple Watch stands, in one calm sentence.
struct WatchStatus: Equatable {
    var isSupported: Bool
    var isInstalled: Bool
    var message: String

    /// Reads the current WatchConnectivity state. The app activates the session at launch, so by the time
    /// Settings opens the answer is known.
    static func current() -> WatchStatus {
        guard WCSession.isSupported() else {
            return WatchStatus(isSupported: false, isInstalled: false, message: "")
        }
        let session = WCSession.default
        if session.activationState != .activated {
            return WatchStatus(isSupported: true, isInstalled: false, message: "Looking for your Apple Watch…")
        }
        if !session.isPaired {
            return WatchStatus(isSupported: true, isInstalled: false, message: "No Apple Watch is paired with this iPhone.")
        }
        if !session.isWatchAppInstalled {
            return WatchStatus(
                isSupported: true,
                isInstalled: false,
                message: "Leaf isn’t on your watch yet. Add it from the Watch app on this iPhone."
            )
        }
        return WatchStatus(isSupported: true, isInstalled: true, message: "Leaf is on your Apple Watch. Today’s plan syncs on its own.")
    }
}
