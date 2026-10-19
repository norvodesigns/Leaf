import SwiftUI
import WidgetKit

// The complications' faces, shared so the watch app can draw them in its DEBUG gallery for screenshots. On a watch
// face the system tints them (accented or full colour); `widgetAccentable` marks the part that takes the tint.

enum ComplicationPalette {
    static let accent = Color(red: 0x8D / 255, green: 0xBB / 255, blue: 0x98 / 255)
    static let deep = Color(red: 0x1E / 255, green: 0x33 / 255, blue: 0x26 / 255)
    static let tea = Color(red: 0xC9 / 255, green: 0x9A / 255, blue: 0x6E / 255)
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
            Image(systemName: "book.fill")
        } else if snapshot.isGoalMet {
            Image(systemName: "checkmark")
        } else if snapshot.isRestDay {
            Image(systemName: "cup.and.saucer.fill")
        } else {
            Text("\(Int(snapshot.minutesLeft.rounded(.up)))")
        }
    }
}

/// Corner: the minutes left, with the ring curving along the bezel.
struct ComplicationCorner: View {
    let snapshot: ComplicationSnapshot

    var body: some View {
        Group {
            if snapshot.isGoalMet || snapshot.isRestDay || snapshot.liveSince != nil {
                Image(systemName: snapshot.liveSince != nil ? "book.fill" : "leaf.fill")
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

/// Rectangular (and the Smart Stack): "13 min · p. 143" over the book, with today's ring as a bar. While a session
/// runs, it counts up instead.
struct ComplicationRectangular: View {
    let snapshot: ComplicationSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: snapshot.liveSince != nil ? "book.fill" : "leaf.fill")
                if let since = snapshot.liveSince {
                    Text(since, style: .timer)
                        .monospacedDigit()
                } else {
                    Text(snapshot.line)
                }
            }
            .font(.headline)
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

/// Inline: the line alone, above the time.
struct ComplicationInline: View {
    let snapshot: ComplicationSnapshot

    var body: some View {
        Label(snapshot.liveSince != nil ? "Reading now" : snapshot.line, systemImage: "leaf.fill")
            .accessibilityLabel(snapshot.spoken)
    }
}
