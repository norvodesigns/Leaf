import SwiftUI

// Buttons and controls (DESIGN_SYSTEM.md §6, §10). One Hero per screen; everything else is glass.

// MARK: - Hero

/// The one black action on a screen ("Begin reading"): solid black Liquid Glass with a white label and a specular rim,
/// in light and dark mode alike. Plays its moment (`.start` unless told otherwise) instead of a plain tap.
struct CanopyHeroButton: View {
    let title: String
    var systemImage: String?
    var feel: CanopyFeel?
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = 56
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, systemImage: String? = nil, feel: CanopyFeel? = .start, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.feel = feel
        self.action = action
    }

    var body: some View {
        Button {
            if let feel { CanopyFeel.play(feel) }
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
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.capsule)
        }
        .buttonStyle(.glassProminent)
        .tint(Canopy.hero)
        .frame(height: height)
        .overlay {
            // The specular rim: what makes black read as glass, and what lifts it off a dark canvas.
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.42), Color.white.opacity(0.04), Color.white.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(title)
    }
}

// MARK: - Glass buttons

/// A secondary action: glass, `text`-coloured label, the icon in the action's accent. 56 tall, or 44 when `compact`.
struct CanopyGlassButton: View {
    let title: String
    var systemImage: String?
    var accent: CanopyAccent?
    var compact: Bool
    var feel: CanopyFeel?
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var regularHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .headline) private var compactHeight: CGFloat = 44

    init(_ title: String, systemImage: String? = nil, accent: CanopyAccent? = nil, compact: Bool = false, feel: CanopyFeel? = .tap, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.compact = compact
        self.feel = feel
        self.action = action
    }

    var body: some View {
        Button {
            if let feel { CanopyFeel.play(feel) }
            action()
        } label: {
            HStack(spacing: Canopy.Space.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent?.color ?? Canopy.text)
                }
                Text(title)
                    .foregroundStyle(Canopy.text)
            }
            .font(.system(compact ? .subheadline : .headline, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.capsule)
        }
        .buttonStyle(.glass)
        .frame(height: compact ? compactHeight : regularHeight)
    }
}

/// A round glass icon button, 44 pt.
struct CanopyIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var accent: CanopyAccent?
    var feel: CanopyFeel?
    let action: () -> Void

    init(_ systemImage: String, accessibilityLabel: String, accent: CanopyAccent? = nil, feel: CanopyFeel? = .tap, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.accent = accent
        self.feel = feel
        self.action = action
    }

    var body: some View {
        Button {
            if let feel { CanopyFeel.play(feel) }
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent?.color ?? Canopy.text)
                .frame(width: Canopy.Space.hitTarget, height: Canopy.Space.hitTarget)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .canopyGlass(accent, in: Circle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A glass capsule chip. Selected chips take their accent's tint and colour.
struct CanopyChip: View {
    let title: String
    var systemImage: String?
    var accent: CanopyAccent
    var isSelected: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, accent: CanopyAccent = .forest, isSelected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button {
            CanopyFeel.play(.select)
            action()
        } label: {
            HStack(spacing: Canopy.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title)
            }
            .font(.system(.subheadline, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? accent.color : Canopy.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .canopyGlass(isSelected ? accent : nil)
        .animation(Canopy.Motion.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A time on a glass chip in Dusk, the reading-time accent. Tapping it changes the time.
struct CanopyTimeChip: View {
    let time: String
    let action: () -> Void

    var body: some View {
        Button {
            CanopyFeel.play(.select)
            action()
        } label: {
            Text(time)
                .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(CanopyAccent.dusk.color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .canopyGlass(.dusk)
        .accessibilityLabel("Reading time \(time)")
        .accessibilityHint("Changes the time")
    }
}

// MARK: - Labels

/// A section label: the section's accent, sentence case, with an optional trailing link ("Edit").
struct CanopyLabel: View {
    let title: String
    var accent: CanopyAccent
    var linkTitle: String?
    var link: (() -> Void)?

    init(_ title: String, accent: CanopyAccent = .forest, linkTitle: String? = nil, link: (() -> Void)? = nil) {
        self.title = title
        self.accent = accent
        self.linkTitle = linkTitle
        self.link = link
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .canopyText(.label, color: accent.color)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Canopy.Space.s)
            if let linkTitle, let link {
                Button {
                    CanopyFeel.play(.tap)
                    link()
                } label: {
                    HStack(spacing: 2) {
                        Text(linkTitle)
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Canopy.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
