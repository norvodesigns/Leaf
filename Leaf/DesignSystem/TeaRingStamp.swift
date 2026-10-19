import SwiftUI

/// A tea ring left on the page by a day of reading (NEXT.md section 6, "tea-ring stamps"). The ring grows with the
/// minutes read, up to the full stamp on a day the goal was met, which also leaves a drip. A reading day with no
/// reading leaves only a faint pencil circle, a rest day a short dash, a reading day ahead a dot. Nothing is red.
struct TeaRingStamp: View {
    enum Mark: Hashable, Sendable {
        /// Read, as a share of the day's goal (0...1, more than 1 counts as 1).
        case read(Double)
        case rest
        case missed
        case upcoming
    }

    let mark: Mark
    /// Keeps each day's ring a little different, but the same every time it is drawn.
    var seed: Int = 0
    var diameter: CGFloat = 38

    var body: some View {
        ZStack {
            switch mark {
            case .read(let share):
                ring(share: share)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            case .rest:
                Capsule()
                    .fill(Color.hairlineStrong)
                    .frame(width: 10, height: 1.5)
            case .missed:
                Circle()
                    .strokeBorder(Color.inkFaint, lineWidth: 1.5)
                    .frame(width: diameter * 0.34, height: diameter * 0.34)
            case .upcoming:
                Circle()
                    .fill(Color.inkFaint)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func ring(share: Double) -> some View {
        let clamped = min(1, max(0, share))
        let size = diameter * (0.48 + 0.52 * clamped)
        let angle = Double((seed &* 47) % 360)
        return ZStack {
            Circle()
                .fill(CozyColor.teaRing.opacity(0.08))
            Circle()
                .stroke(CozyColor.teaRing.opacity(0.55), lineWidth: 1.6)
            Circle()
                .stroke(CozyColor.teaRing.opacity(0.22), lineWidth: 1)
                .scaleEffect(0.95)
                .offset(x: 0.8, y: 0.7)
            Circle()
                .trim(from: 0, to: 0.36)
                .stroke(CozyColor.teaRing.opacity(0.32), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(angle))
            if clamped >= 1 {
                Circle()
                    .fill(CozyColor.teaRing.opacity(0.4))
                    .frame(width: 3.5, height: 3.5)
                    .offset(y: -(size / 2 + 4))
                    .rotationEffect(.degrees(angle + 140))
            }
        }
        .frame(width: size, height: size)
    }
}

/// The week as tea rings on the paper: seven columns of eyebrow letter over a stamp, today underlined in `ribbon`.
/// Under it, the real numbers ("2 h 41 min this week · 6 cups") and, from three days, the streak.
struct TeaRingWeek: View {
    let days: [DayStat]
    let goalMinutes: Int
    var streak: Int = 0
    var cupMinutes: Int = 25

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var stampDiameter: CGFloat { typeSize.isAccessibilitySize ? 30 : 38 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: 0) {
                ForEach(days.indices, id: \.self) { index in
                    column(days[index], mark: mark(at: index), seed: index)
                }
            }
            Text(summary)
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func column(_ day: DayStat, mark: TeaRingStamp.Mark, seed: Int) -> some View {
        let dayNumber = Calendar.current.ordinality(of: .day, in: .year, for: day.date) ?? seed
        return VStack(spacing: Space.xs) {
            Text(WeekStrip.letter(for: day.date))
                .leafStyle(.eyebrow, color: day.isToday ? Color.ink : nil)
            TeaRingStamp(mark: mark, seed: dayNumber, diameter: stampDiameter)
                .animation(Motion.resolved(Motion.board, reduceMotion: reduceMotion), value: mark)
            Capsule()
                .fill(Color.ribbon)
                .frame(width: 14, height: 2)
                .opacity(day.isToday ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(day, mark: mark))
    }

    private var todayIndex: Int? { days.firstIndex(where: \.isToday) }

    private func mark(at index: Int) -> TeaRingStamp.Mark {
        let day = days[index]
        if day.minutes >= 1 {
            return .read(goalMinutes > 0 ? day.minutes / Double(goalMinutes) : 1)
        }
        if !day.isReadingDay { return .rest }
        if let todayIndex { return index < todayIndex ? .missed : .upcoming }
        return day.date < Calendar.current.startOfDay(for: Date()) ? .missed : .upcoming
    }

    private var weekMinutes: Double { days.reduce(0) { $0 + $1.minutes } }

    /// "2 h 41 min this week · 6 cups · 5 reading days in a row"
    private var summary: String {
        var parts: [String] = []
        if weekMinutes >= 1 {
            parts.append("\(LeafFormat.duration(minutes: weekMinutes)) this week")
            let cups = Cups.wholeCups(minutes: weekMinutes, cupMinutes: cupMinutes)
            if cups > 0 { parts.append(cups == 1 ? "1 cup" : "\(cups) cups") }
        } else {
            parts.append("A fresh week")
        }
        if streak >= 3 { parts.append("\(streak) reading days in a row") }
        return parts.joined(separator: " · ")
    }

    private func accessibilityText(_ day: DayStat, mark: TeaRingStamp.Mark) -> String {
        let name = LeafFormat.format(day.date, template: "EEEE")
        let state: String
        switch mark {
        case .read: state = "read \(LeafFormat.duration(minutes: day.minutes))"
        case .rest: state = "rest day"
        case .missed: state = "no reading"
        case .upcoming: state = "reading day"
        }
        return day.isToday ? "Today, \(name), \(state)" : "\(name), \(state)"
    }
}

#Preview("Tea-ring week") {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return VStack(alignment: .leading, spacing: 0) {
        SectionHeader("This week", topSpacing: 0)
        TeaRingWeek(days: store.week, goalMinutes: 25, streak: store.streak)
        HStack(spacing: 12) {
            TeaRingStamp(mark: .read(0.2), seed: 3)
            TeaRingStamp(mark: .read(0.6), seed: 9)
            TeaRingStamp(mark: .read(1.2), seed: 14)
            TeaRingStamp(mark: .missed)
            TeaRingStamp(mark: .rest)
            TeaRingStamp(mark: .upcoming)
        }
        .padding(.top, 24)
    }
    .leafMargins()
    .frame(maxHeight: .infinity, alignment: .top)
    .paperBackground()
}

#Preview("Tea-ring week · dark") {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return TeaRingWeek(days: store.week, goalMinutes: 25, streak: store.streak)
        .leafMargins()
        .paperBackground()
        .preferredColorScheme(.dark)
}
