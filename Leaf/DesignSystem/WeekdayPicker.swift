import SwiftUI

/// Reading days (DESIGN.md §5): seven columns in the locale's order (`Calendar.current.firstWeekday`),
/// very short weekday letters in `masthead`. Selected: `ink` with a 20×2 `ribbon` underline 6 pt
/// below. Unselected: `inkTertiary`. Each column is a 44×64 toggle ("Monday, reading day").
/// `selection` holds Calendar weekdays: 1 = Sunday … 7 = Saturday.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Binding<Set<Int>>) {
        self._selection = selection
    }

    /// Weekday numbers in display order for the current locale.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WeekdayPicker.orderedWeekdays(), id: \.self) { weekday in
                column(weekday)
            }
        }
    }

    private func column(_ weekday: Int) -> some View {
        let isOn = selection.contains(weekday)
        return Button {
            Haptics.shared.selection()
            withAnimation(Motion.resolved(Motion.glass, reduceMotion: reduceMotion)) {
                if isOn {
                    selection.remove(weekday)
                } else {
                    selection.insert(weekday)
                }
            }
        } label: {
            VStack(spacing: 6) {
                Text(symbol(weekday, short: true))
                    .leafStyle(.masthead, color: isOn ? Color.ink : Color.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Capsule()
                    .fill(Color.ribbon)
                    .frame(width: 20, height: 2)
                    .scaleEffect(x: isOn ? 1 : 0.01, y: 1)
                    .opacity(isOn ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(minWidth: Space.hitTarget)
        .accessibilityLabel("\(symbol(weekday, short: false)), \(isOn ? "reading day" : "rest day")")
        .accessibilityAddTraits(isOn ? AccessibilityTraits([.isToggle, .isSelected]) : AccessibilityTraits.isToggle)
    }

    private func symbol(_ weekday: Int, short: Bool) -> String {
        let calendar = Calendar.current
        let symbols = short ? calendar.veryShortStandaloneWeekdaySymbols : calendar.standaloneWeekdaySymbols
        let index = weekday - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}

#Preview("Weekday picker") {
    @Previewable @State var days: Set<Int> = [2, 3, 4, 5, 6]
    VStack(spacing: Space.l) {
        WeekdayPicker(selection: $days)
        Text(days.isEmpty ? "Pick at least one day." : "\(days.count) days a week.")
            .leafStyle(.pullQuote)
    }
    .leafMargins()
    .frame(maxHeight: .infinity)
    .paperBackground()
}
