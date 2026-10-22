import SwiftUI

/// The one prominent action on a screen: the Canopy hero (docs/design/DESIGN_SYSTEM.md), `.glassProminent` tinted
/// black in both modes with a white label, 54 pt tall (scaled with Dynamic Type) and full width. Plays `press()` on tap.
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
                        .tint(.white)
                } else if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.system(.headline, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.capsule)
        }
        .buttonStyle(.glassProminent)
        .tint(Canopy.hero)
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

/// A solid ink capsule (near black on light paper, cream on dark) with a `paper` label, the height of the glass
/// buttons. It is the plain partner beside a glass button when two actions are a deliberate pair, as Today's
/// "Steep and read" and "Begin reading" are. `outline` draws it as a ring of ink instead, for a quieter day.
struct InkButton: View {
    let title: String
    var systemImage: String?
    var isOutline: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = 54

    init(_ title: String, systemImage: String? = nil, outline: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        isOutline = outline
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.shared.tap()
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
            .foregroundStyle(isOutline ? Color.ink : Color.paper)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, Space.l)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                if isOutline {
                    Capsule().strokeBorder(Color.ink, lineWidth: 1.5)
                } else {
                    Capsule().fill(Color.ink)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(title)
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
