import SwiftUI

/// The guilt-free week (DESIGN.md §5): seven columns of eyebrow letter over a 10 pt marker.
/// Read: an `accent` dot. Rest: a 10×1.5 `hairlineStrong` dash. No reading on a past reading day:
/// a 1.5 pt `inkFaint` ring. A reading day still ahead: a 4 pt `inkFaint` dot. Today adds a
/// 14×2 `ribbon` underline. The streak caption ("5 reading days in a row") shows from 3 days.
///
/// Feed it `store.week` and `store.streak`. In the session outcome, pass `fillsTodayOnAppear: true`
/// so today's marker fills with `Motion.board` after the sheet appears.
struct WeekStrip: View {
    enum Mark: Hashable, Sendable {
        case read, rest, missed, upcoming
    }

    let days: [DayStat]
    var streak: Int
    var fillsTodayOnAppear: Bool

    @State private var revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(days: [DayStat], streak: Int = 0, fillsTodayOnAppear: Bool = false) {
        self.days = days
        self.streak = streak
        self.fillsTodayOnAppear = fillsTodayOnAppear
        _revealed = State(initialValue: !fillsTodayOnAppear)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: 0) {
                ForEach(days.indices, id: \.self) { index in
                    column(days[index], mark: mark(at: index))
                }
            }
            if streak >= 3 {
                Text("\(streak) reading days in a row")
                    .leafStyle(.caption)
            }
        }
        .onAppear {
            guard !revealed else { return }
            withAnimation(Motion.resolved(Motion.board, reduceMotion: reduceMotion).delay(0.35)) {
                revealed = true
            }
        }
    }

    private func column(_ day: DayStat, mark: Mark) -> some View {
        VStack(spacing: Space.s) {
            Text(WeekStrip.letter(for: day.date))
                .leafStyle(.eyebrow, color: day.isToday ? Color.ink : nil)
            DayMarker(mark: mark)
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

    private func mark(at index: Int) -> Mark {
        let day = days[index]
        if day.isToday && !revealed {
            return day.isReadingDay ? .upcoming : .rest
        }
        if day.minutes >= 1 { return .read }
        if !day.isReadingDay { return .rest }
        return isPast(index) ? .missed : .upcoming
    }

    private func isPast(_ index: Int) -> Bool {
        if let todayIndex { return index < todayIndex }
        return days[index].date < Calendar.current.startOfDay(for: Date())
    }

    private func accessibilityText(_ day: DayStat, mark: Mark) -> String {
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

    static func letter(for date: Date, calendar: Calendar = .current) -> String {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let index = calendar.component(.weekday, from: date) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}

private struct DayMarker: View {
    let mark: WeekStrip.Mark

    var body: some View {
        ZStack {
            switch mark {
            case .read:
                Circle()
                    .fill(Color.accent)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            case .rest:
                Capsule()
                    .fill(Color.hairlineStrong)
                    .frame(width: 10, height: 1.5)
                    .transition(.opacity)
            case .missed:
                Circle()
                    .strokeBorder(Color.inkFaint, lineWidth: 1.5)
                    .transition(.opacity)
            case .upcoming:
                Circle()
                    .fill(Color.inkFaint)
                    .frame(width: 4, height: 4)
                    .transition(.opacity)
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

#Preview("Week strip") {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return VStack(alignment: .leading, spacing: 0) {
        SectionHeader("This week", topSpacing: 0)
        WeekStrip(days: store.week, streak: store.streak)
        SectionHeader("Session logged")
        WeekStrip(days: store.week, fillsTodayOnAppear: true)
    }
    .leafMargins()
    .frame(maxHeight: .infinity, alignment: .top)
    .paperBackground()
    .environment(store)
    .environment(AppRouter())
    .environment(BookCatalog.shared)
}
