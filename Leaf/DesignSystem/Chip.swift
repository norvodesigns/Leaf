import SwiftUI

/// A small capsule label on paper: 22 pt tall, 8 pt padding, `caption` semibold.
/// Tones: `.neutral` (`inkSecondary` on `paperSunken`), `.accent` (`accent` on `accentSoft`),
/// `.ribbon` (`ribbon` on `ribbonSoft`). Never glass.
struct Chip: View {
    enum Tone: Hashable, Sendable {
        case neutral, accent, ribbon
    }

    let text: String
    var systemImage: String?
    var tone: Tone

    init(_ text: String, systemImage: String? = nil, tone: Tone = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
    }

    private var foreground: Color {
        switch tone {
        case .neutral: .inkSecondary
        case .accent: .accent
        case .ribbon: .ribbon
        }
    }

    private var fill: Color {
        switch tone {
        case .neutral: .paperSunken
        case .accent: .accentSoft
        case .ribbon: .ribbonSoft
        }
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(LeafType.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .lineLimit(1)
        .padding(.horizontal, Space.s)
        .frame(minHeight: 22)
        .background(fill, in: .capsule)
    }
}

/// How far a finish date moved after a reorder or mode switch (DESIGN.md §5).
/// "6 days sooner" is `accent` on `accentSoft`; "4 days later" is `inkSecondary` on `paperSunken`.
/// Draws nothing for zero. Show it for `Motion.deltaChipDuration` (2.5 s) with `.transition(.deltaChip)`.
struct DeltaChip: View {
    /// Positive: the book now finishes this many days sooner. Negative: later.
    let daysSooner: Int

    init(daysSooner: Int) {
        self.daysSooner = daysSooner
    }

    /// From two finish dates (new minus old, in whole days).
    init(from oldFinish: Date, to newFinish: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: oldFinish)
        let end = calendar.startOfDay(for: newFinish)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        self.daysSooner = -days
    }

    static func text(daysSooner: Int) -> String {
        let count = abs(daysSooner)
        let unit = count == 1 ? "day" : "days"
        return daysSooner > 0 ? "\(count) \(unit) sooner" : "\(count) \(unit) later"
    }

    var body: some View {
        if daysSooner != 0 {
            Chip(DeltaChip.text(daysSooner: daysSooner), tone: daysSooner > 0 ? .accent : .neutral)
        }
    }
}

extension AnyTransition {
    /// DeltaChip in and out: a small scale and fade.
    static var deltaChip: AnyTransition {
        .scale(scale: 0.85).combined(with: .opacity)
    }
}

#Preview("Chips") {
    VStack(spacing: Space.m) {
        DeltaChip(daysSooner: 6)
        DeltaChip(daysSooner: -4)
        DeltaChip(daysSooner: 1)
        Chip("≈ 6 h at your pace", systemImage: "clock")
        Chip("est.", tone: .ribbon)
        Chip("Done", systemImage: "checkmark", tone: .accent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .paperBackground()
}
