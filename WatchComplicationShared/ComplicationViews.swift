import SwiftUI
import WidgetKit

// The complications' faces, shared so the watch app can draw them in its DEBUG gallery for screenshots. On a watch
// face the system tints them (accented or full colour); `widgetAccentable` marks the part that takes the tint.

enum ComplicationPalette {
    /// Canopy on black (Oat, dark): Forest for the goal, Dusk for reading and time, Clay for tea.
    static let accent = Color(red: 0xA9 / 255, green: 0xCD / 255, blue: 0xB2 / 255)
    static let deep = Color(red: 0x1F / 255, green: 0x2C / 255, blue: 0x24 / 255)
    static let dusk = Color(red: 0xA9 / 255, green: 0xB5 / 255, blue: 0xF2 / 255)
    static let tea = Color(red: 0xEB / 255, green: 0x9C / 255, blue: 0x74 / 255)
}

extension ComplicationSnapshot {
    /// The next of today's reading times still to come at `date` (a quarter of an hour's grace after it starts), as
    /// a date. Nil when none is left today.
    func nextSlot(at date: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: date)
        return slotMinutes.sorted().lazy
            .compactMap { calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: start) }
            .first { $0.addingTimeInterval(15 * 60) > date }
    }
}

/// Circular: today's ring, with the minutes left inside (a check once done, a book while reading).
struct ComplicationCircular: View {
    let snapshot: ComplicationSnapshot

    var body: some View {
        Gauge(value: snapshot.goalProgress) {
            Image(systemName: "leaf.fill")
        } currentValueLabel: {
            centre
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(ComplicationPalette.accent)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.spoken)
    }

    @ViewBuilder private var centre: some View {
        if snapshot.liveSince != nil {
            Image(systemName: "book.pages")
        } else if snapshot.isGoalMet {
            Image(systemName: "checkmark")
        } else if snapshot.isRestDay {
            Image(systemName: "leaf")
        } else {
            Text("\(Int(snapshot.minutesLeft.rounded(.up)))")
                .font(.system(.body, design: .rounded).weight(.semibold))
        }
    }
}

/// Corner: the minutes left, with the ring curving along the bezel.
struct ComplicationCorner: View {
    let snapshot: ComplicationSnapshot

    var body: some View {
        Group {
            if snapshot.isGoalMet || snapshot.isRestDay || snapshot.liveSince != nil {
                Image(systemName: snapshot.liveSince != nil ? "book.pages" : "leaf.fill")
                    .font(.title3)
            } else {
                Text("\(Int(snapshot.minutesLeft.rounded(.up)))")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
            }
        }
        .widgetCurvesContent()
        .widgetAccentable()
        .widgetLabel {
            Gauge(value: snapshot.goalProgress) {
                Text("min")
            }
            .tint(ComplicationPalette.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.spoken)
    }
}

/// Rectangular (and the Smart Stack): "8:30 PM · The Hobbit" in Dusk when a reading time is coming, else
/// "13 min · p. 143", over the book with today's ring as a bar. While a session runs, it counts up instead.
struct ComplicationRectangular: View {
    let snapshot: ComplicationSnapshot
    var now: Date = Date()

    var body: some View {
        let next = snapshot.liveSince == nil && !snapshot.isGoalMet && !snapshot.isRestDay ? snapshot.nextSlot(at: now) : nil
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: snapshot.liveSince != nil ? "book.pages" : (next != nil ? "clock" : "leaf.fill"))
                if let since = snapshot.liveSince {
                    Text(since, style: .timer)
                        .monospacedDigit()
                } else if let next {
                    Text(next, format: .dateTime.hour().minute())
                } else {
                    Text(snapshot.line)
                }
            }
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(next != nil || snapshot.liveSince != nil ? ComplicationPalette.dusk : ComplicationPalette.accent)
            .widgetAccentable()
            Text(snapshot.title ?? "Open Leaf on your iPhone")
                .font(.system(.body, design: .serif))
                .lineLimit(1)
            Gauge(value: snapshot.goalProgress) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(ComplicationPalette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.spoken)
    }
}

/// Inline: "13 min · The Hobbit" above the time, as on the iPhone's Lock Screen.
struct ComplicationInline: View {
    let snapshot: ComplicationSnapshot

    var body: some View {
        Label(text, systemImage: snapshot.liveSince != nil ? "book.pages" : "leaf.fill")
            .accessibilityLabel(snapshot.spoken)
    }

    private var text: String {
        if snapshot.liveSince != nil { return "Reading now" }
        guard let title = snapshot.title else { return snapshot.line }
        if snapshot.isRestDay { return "Rest day · \(title)" }
        if snapshot.isGoalMet { return "Goal met · \(title)" }
        return "\(Int(snapshot.minutesLeft.rounded(.up))) min · \(title)"
    }
}
