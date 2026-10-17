import SwiftUI

/// One book's share of a day, ready to show.
struct PlanDayEntry: Identifiable {
    let book: Book
    let assignment: Assignment

    var id: String { assignment.bookID }
}

/// One day in "Next 7 days": a weekday and date on the left, and what the plan gives that day on the
/// right (each book with its pages and minutes), or a quiet note for a rest day.
struct PlanDayRow: View {
    let day: PlanDay
    let entries: [PlanDayEntry]
    /// The first row, which reads "Today" and carries the `ribbon` mark.
    var isToday: Bool = false
    /// Today's goal is already met, so nothing more is scheduled.
    var isDone: Bool = false
    var calendar: Calendar = .current

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.s) {
                    dateColumn
                    content
                }
            } else {
                HStack(alignment: .top, spacing: Space.l) {
                    dateColumn
                        .frame(width: 56, alignment: .leading)
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }

    // MARK: Date

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(isToday ? "Today" : LeafFormat.format(day.date, template: "EEE", calendar: calendar))
                .leafStyle(.eyebrow, color: isToday ? Color.ink : Color.inkTertiary)
            Text(LeafFormat.format(day.date, template: "d", calendar: calendar))
                .leafStyle(.index, color: day.isReadingDay ? Color.ink : Color.inkTertiary)
            if isToday {
                Capsule()
                    .fill(Color.ribbon)
                    .frame(width: 14, height: 2)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !day.isReadingDay {
            note("A rest day", systemImage: nil)
        } else if entries.isEmpty {
            if isDone {
                note("Done for today", systemImage: "checkmark")
            } else {
                note("Nothing scheduled", systemImage: nil)
            }
        } else {
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(entries) { entry in
                    entryRow(entry)
                }
            }
        }
    }

    private func entryRow(_ entry: PlanDayEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(entry.book.title)
                    .leafStyle(.headline)
                    .lineLimit(2)
                HStack(spacing: Space.s) {
                    Text(LeafFormat.pages(from: entry.assignment.fromPage, to: entry.assignment.toPage))
                        .leafStyle(.caption)
                    if entry.assignment.finishesBook {
                        Chip("Finishes", systemImage: "checkmark", tone: .accent)
                    }
                }
            }
            Spacer(minLength: Space.s)
            Text(LeafFormat.duration(minutes: entry.assignment.minutes))
                .leafStyle(.data)
                .fixedSize()
        }
    }

    /// A rest day or an empty day: a short dash in the WeekStrip's style and a line of `caption`.
    private func note(_ text: String, systemImage: String?) -> some View {
        HStack(spacing: Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accent)
                    .accessibilityHidden(true)
            } else {
                Rectangle()
                    .fill(Color.hairlineStrong)
                    .frame(width: 10, height: 1.5)
                    .accessibilityHidden(true)
            }
            Text(text)
                .leafStyle(.caption)
        }
        .frame(minHeight: 36, alignment: .leading)
    }
}
