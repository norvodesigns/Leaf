import SwiftUI

/// What a Plan row needs to know about one book, in running order.
struct PlanRowModel: Identifiable {
    let number: Int
    let planned: PlannedBook
    let book: Book

    var id: String { planned.id }
}

/// One book on the Plan's timeline (DESIGN.md §5 "PlanRow"): `index` numeral, title, leader dots and
/// finish date on the first line; a 6 pt band on the shared time axis on the second. The band column
/// starts `PlanRow.indexWidth` in from the leading edge, so the grid behind the rows lines up with it.
/// The whole row opens the book.
struct PlanRow: View {
    /// Width of the numeral column. The month labels and the grid are inset by the same amount.
    static let indexWidth: CGFloat = 40

    let number: Int
    let book: Book
    let planned: PlannedBook
    let scale: TimelineScale
    /// Used to write the finish date ("3 Dec", or with the year when it isn't this year).
    var today: Date = Date()
    var calendar: Calendar = .current
    /// Days sooner (positive) or later (negative) than before the current adjustment. Nil or 0 shows no chip.
    var daysSooner: Int?
    /// Goes up once an adjustment settles; the date flashes `ribbonSoft` when it changes.
    var flashStamp: Int = 0
    /// The row's position while dates roll in a stagger (a mode switch). Nil rolls them together.
    var staggerIndex: Int?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationLink(value: BookRoute(book: book)) {
            Group {
                if typeSize.isAccessibilitySize {
                    accessibleLayout
                } else {
                    regularLayout
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(.vertical, Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Opens the book")
    }

    // MARK: Layouts

    private var regularLayout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            numeral
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(book.title)
                        .leafStyle(.headline)
                        .lineLimit(1)
                        .layoutPriority(1)
                    LeaderDots()
                    chip
                    dateLabel
                }
                band
            }
        }
    }

    private var accessibleLayout: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                numeral
                Text(book.title)
                    .leafStyle(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.s) {
                dateLabel
                chip
            }
            .padding(.leading, Self.indexWidth)
            band
                .padding(.leading, Self.indexWidth)
        }
    }

    private var numeral: some View {
        IndexNumeral(number)
            .frame(width: Self.indexWidth, alignment: .leading)
    }

    private var band: some View {
        TimelineBand(planned, scale: scale)
            .animation(rowAnimation, value: planned)
            .animation(rowAnimation, value: scale)
    }

    private var dateLabel: some View {
        Text(dateString)
            .leafStyle(.data, color: planned.finish == nil ? Color.inkTertiary : Color.ink)
            .contentTransition(.numericText())
            .animation(rowAnimation, value: dateString)
            .reflowFlash(trigger: flashStamp, delay: Motion.reflowStagger * Double(staggerIndex ?? 0))
            .fixedSize()
    }

    @ViewBuilder
    private var chip: some View {
        if let daysSooner, daysSooner != 0 {
            DeltaChip(daysSooner: daysSooner)
                .transition(Motion.transition(.deltaChip, reduceMotion: reduceMotion))
        }
    }

    // MARK: Text

    private var dateString: String {
        guard let finish = planned.finish else { return "—" }
        return LeafFormat.shortDate(finish, today: today, calendar: calendar)
    }

    /// Rows reflow together while a dial moves; a mode switch rolls them one after another.
    private var rowAnimation: Animation {
        let base = Motion.resolved(Motion.paper, reduceMotion: reduceMotion)
        guard let staggerIndex, !reduceMotion else { return base }
        return base.delay(Motion.reflowStagger * Double(staggerIndex))
    }

    private var spokenLabel: String {
        var parts = ["\(number). \(book.title)", planned.isReading ? "reading now" : "on your to read list"]
        if let finish = planned.finish {
            parts.append("finishes \(LeafFormat.format(finish, template: "EEEEdMMMM", calendar: calendar))")
        } else {
            parts.append("no finish date yet")
        }
        if let daysSooner, daysSooner != 0 {
            parts.append(DeltaChip.text(daysSooner: daysSooner))
        }
        return parts.joined(separator: ", ")
    }
}
