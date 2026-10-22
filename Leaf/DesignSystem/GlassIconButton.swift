import SwiftUI

/// A round vellum-glass symbol: `.glassEffect(.regular.tint(.glassTint).interactive(), in: .circle)`
/// around an `ink` SF Symbol. Use it as a `Menu` label, or through `GlassIconButton`.
/// Not for toolbars: toolbar items already sit on system glass, so use a plain `Button` there.
struct GlassIcon: View {
    let systemImage: String
    var diameter: CGFloat

    init(systemImage: String, diameter: CGFloat = 44) {
        self.systemImage = systemImage
        self.diameter = diameter
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: diameter * 0.38, weight: .semibold))
            .foregroundStyle(.ink)
            .frame(width: diameter, height: diameter)
            .contentShape(.circle)
            .glassEffect(.regular.tint(.glassTint).interactive(), in: .circle)
    }
}

/// An icon-only glass button (the session's `chevron.down`, a row's `plus`). Plays `tap()`.
/// `label` is the VoiceOver label, e.g. "Minimize session".
struct GlassIconButton: View {
    let systemImage: String
    let label: String
    var diameter: CGFloat
    var playsHaptic: Bool
    let action: () -> Void

    init(systemImage: String, label: String, diameter: CGFloat = 44, playsHaptic: Bool = true, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.diameter = diameter
        self.playsHaptic = playsHaptic
        self.action = action
    }

    var body: some View {
        Button {
            if playsHaptic { Haptics.shared.tap() }
            action()
        } label: {
            // Small icons keep a 44 pt hit area without changing the layout.
            let slack = max(0, (Space.hitTarget - diameter) / 2)
            GlassIcon(systemImage: systemImage, diameter: diameter)
                .padding(slack)
                .contentShape(.rect)
                .padding(-slack)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview("Glass icons") {
    HStack(spacing: Space.l) {
        GlassIconButton(systemImage: "chevron.down", label: "Minimize session") {}
        GlassIconButton(systemImage: "plus", label: "Add", diameter: 36) {}
        Menu {
            Button("Start reading") {}
            Button("Add to top of Up next") {}
        } label: {
            GlassIcon(systemImage: "plus", diameter: 36)
        }
        .accessibilityLabel("Add")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperBackground()
}
