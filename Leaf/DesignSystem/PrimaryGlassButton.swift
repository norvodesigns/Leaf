import SwiftUI

/// The one prominent action on a screen (DESIGN.md §5): `.glassProminent` tinted `ink`, a semibold
/// `paper` label, 54 pt tall (scaled with Dynamic Type) and full width. Plays `press()` on tap.
/// Disabled draws at 40%; `isLoading` swaps the label for a spinner and ignores taps.
/// Use at most one per screen.
struct PrimaryGlassButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool
    var playsHaptic: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = 54

    /// - Parameter playsHaptic: pass false when the action plays its own signature haptic.
    init(_ title: String, systemImage: String? = nil, isLoading: Bool = false, playsHaptic: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.playsHaptic = playsHaptic
        self.action = action
    }

    init(title: String, systemImage: String? = nil, isLoading: Bool = false, playsHaptic: Bool = true, action: @escaping () -> Void) {
        self.init(title, systemImage: systemImage, isLoading: isLoading, playsHaptic: playsHaptic, action: action)
    }

    var body: some View {
        Button {
            guard !isLoading else { return }
            if playsHaptic { Haptics.shared.press() }
            action()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(.paper)
                } else if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.system(.headline, weight: .semibold))
            .foregroundStyle(.paper)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.capsule)
        }
        .buttonStyle(.glassProminent)
        .tint(.ink)
        .frame(height: height)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? Text("Loading") : Text(""))
    }
}

/// The quieter action (DESIGN.md §5): `.buttonStyle(.glass)` with an `ink` label, 54 pt tall
/// (44 when `compact`), full width. Plays `tap()`.
struct SecondaryGlassButton: View {
    let title: String
    var systemImage: String?
    var compact: Bool
    var playsHaptic: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var regularHeight: CGFloat = 54
    @ScaledMetric(relativeTo: .headline) private var compactHeight: CGFloat = 44

    init(_ title: String, systemImage: String? = nil, compact: Bool = false, playsHaptic: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.compact = compact
        self.playsHaptic = playsHaptic
        self.action = action
    }

    init(title: String, systemImage: String? = nil, compact: Bool = false, playsHaptic: Bool = true, action: @escaping () -> Void) {
        self.init(title, systemImage: systemImage, compact: compact, playsHaptic: playsHaptic, action: action)
    }

    var body: some View {
        Button {
            if playsHaptic { Haptics.shared.tap() }
            action()
        } label: {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.system(.headline, weight: .semibold))
            .foregroundStyle(.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.capsule)
        }
        .buttonStyle(.glass)
        .frame(height: compact ? compactHeight : regularHeight)
    }
}

#Preview("Buttons") {
    @Previewable @State var loading = false
    VStack(spacing: Space.m) {
        PrimaryGlassButton("Start reading", systemImage: "play.fill", isLoading: loading) {
            loading.toggle()
        }
        PrimaryGlassButton("Make my plan") {}
            .disabled(true)
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                SecondaryGlassButton("Pause", systemImage: "pause.fill") {}
                SecondaryGlassButton("Read anyway") {}
            }
        }
        SecondaryGlassButton("Keep reading", compact: true) {}
    }
    .leafMargins()
    .frame(maxHeight: .infinity)
    .paperBackground()
}
