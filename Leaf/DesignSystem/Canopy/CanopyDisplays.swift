import SwiftUI

// Progress, numbers, timers and rows (DESIGN_SYSTEM.md §10).

// MARK: - Progress

/// A rounded bar in an accent (Forest unless the job says otherwise) on a separator track.
struct CanopyProgressBar: View {
    var value: Double
    var accent: CanopyAccent = .forest
    var height: CGFloat = 6

    var body: some View {
        let clamped = min(1, max(0, value.isFinite ? value : 0))
        Capsule()
            .fill(Canopy.separator)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(accent.color)
                        .frame(width: max(height, proxy.size.width * clamped))
                        .opacity(clamped > 0 ? 1 : 0)
                }
            }
            .animation(Canopy.Motion.smooth, value: clamped)
            .accessibilityElement()
            .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

/// A progress ring in an accent, with optional content in the middle.
struct CanopyRing<Center: View>: View {
    var value: Double
    var accent: CanopyAccent
    var lineWidth: CGFloat
    @ViewBuilder var center: () -> Center

    init(value: Double, accent: CanopyAccent = .forest, lineWidth: CGFloat = 8, @ViewBuilder center: @escaping () -> Center) {
        self.value = value
        self.accent = accent
        self.lineWidth = lineWidth
        self.center = center
    }

    var body: some View {
        let clamped = min(1, max(0, value.isFinite ? value : 0))
        ZStack {
            Circle()
                .stroke(Canopy.separator, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(accent.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .padding(lineWidth / 2)
        .animation(Canopy.Motion.smooth, value: clamped)
    }
}

extension CanopyRing where Center == EmptyView {
    init(value: Double, accent: CanopyAccent = .forest, lineWidth: CGFloat = 8) {
        self.init(value: value, accent: accent, lineWidth: lineWidth) { EmptyView() }
    }
}

/// A big rounded numeral with its unit and a caption: "12 min · read today".
struct CanopyStat: View {
    let value: String
    var unit: String?
    var caption: String?
    var accent: CanopyAccent?

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Canopy.Space.xs) {
                Text(value)
                    .canopyText(.stat, color: accent?.color)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit).canopyText(.callout, color: Canopy.textSecondary)
                }
            }
            if let caption {
                Text(caption).canopyText(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Timer

/// The timer numeral: rounded, monospaced, rolling digits. It arrives with Focus In when it starts and is never
/// blurred while it runs (there is deliberately no blur parameter).
struct CanopyTimerText: View {
    let seconds: Int
    var countsDown: Bool = false
    var accent: CanopyAccent?
    var isPaused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(Self.clock(seconds))
            .canopyText(.timer, color: isPaused ? Canopy.textSecondary : (accent?.color ?? Canopy.text))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText(countsDown: countsDown))
            .animation(reduceMotion ? nil : Canopy.Motion.snappy, value: seconds)
            .accessibilityLabel(Self.spoken(seconds, countsDown: countsDown))
    }

    /// 4:05, or 1:04:05 past the hour.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let rest = s % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }

    static func spoken(_ seconds: Int, countsDown: Bool) -> String {
        let s = max(0, seconds)
        let minutes = s / 60
        let rest = s % 60
        var parts: [String] = []
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if rest > 0 || minutes == 0 { parts.append(rest == 1 ? "1 second" : "\(rest) seconds") }
        let time = parts.joined(separator: " ")
        return countsDown ? "\(time) left" : time
    }
}

// MARK: - Covers and rows

/// A plain cover swatch for mock-ups and missing art: a generated-cover colour with the title set small.
struct CanopyCoverSwatch: View {
    let title: String
    var paletteIndex: Int
    var width: CGFloat = 44

    var body: some View {
        let palette = CoverPalette.all[((paletteIndex % CoverPalette.all.count) + CoverPalette.all.count) % CoverPalette.all.count]
        RoundedRectangle(cornerRadius: Canopy.Radius.cover, style: .continuous)
            .fill(palette.background)
            .frame(width: width, height: width * 1.5)
            .overlay {
                Text(title)
                    .font(.system(size: max(6, width * 0.16), weight: .semibold, design: .serif))
                    .foregroundStyle(palette.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                    .padding(width * 0.1)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 4, y: 2)
            .accessibilityHidden(true)
    }
}

/// Where a reading time stands today.
enum CanopySlotState {
    case done, next, later
}

/// A reading time: the time on a Dusk chip, the book's cover and title, minutes and pages, and a swap button.
/// "Change the time or swap the book" are each one tap.
struct CanopySlotRow: View {
    let time: String
    var period: String?
    let title: String
    let detail: String
    var paletteIndex: Int?
    var state: CanopySlotState = .later
    var onTime: () -> Void = {}
    var onSwap: () -> Void = {}

    var body: some View {
        HStack(spacing: Canopy.Space.m) {
            VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                CanopyTimeChip(time: time, action: onTime)
                if let period {
                    Text(period)
                        .canopyText(.caption, color: Canopy.textTertiary)
                        .padding(.leading, Canopy.Space.m)
                }
            }
            .frame(minWidth: 92, alignment: .leading)

            if let paletteIndex {
                CanopyCoverSwatch(title: title, paletteIndex: paletteIndex, width: 34)
            } else {
                Image(systemName: "books.vertical")
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Canopy.textSecondary)
                    .frame(width: 34, height: 51)
            }

            VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                HStack(spacing: Canopy.Space.xs) {
                    if state == .done {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(CanopyAccent.forest.color)
                    } else if state == .next {
                        Circle()
                            .fill(CanopyAccent.dusk.color)
                            .frame(width: 7, height: 7)
                    }
                    Text(title)
                        .canopyText(.headline)
                        .lineLimit(1)
                }
                Text(detail)
                    .canopyText(.caption)
                    .lineLimit(1)
            }
            .opacity(state == .done ? 0.6 : 1)

            Spacer(minLength: 0)

            CanopyIconButton("arrow.triangle.2.circlepath", accessibilityLabel: "Swap the book", feel: .select, action: onSwap)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A book on a shelf row: cover, title in New York, author, progress.
struct CanopyBookRow: View {
    let title: String
    let author: String
    var paletteIndex: Int
    var progress: Double?
    var trailing: String?

    var body: some View {
        HStack(spacing: Canopy.Space.m) {
            CanopyCoverSwatch(title: title, paletteIndex: paletteIndex, width: 44)
            VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                Text(title)
                    .font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(Canopy.text)
                    .lineLimit(2)
                Text(author).canopyText(.caption)
                if let progress {
                    CanopyProgressBar(value: progress, height: 4)
                        .frame(maxWidth: 160)
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).canopyText(.caption, color: Canopy.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
