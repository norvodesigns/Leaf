import SwiftUI

/// One book in today's issue: the book on its shelf and the pages the plan gives it today.
struct TodayEntry: Identifiable {
    let item: LibraryItem
    let assignment: Assignment

    var id: String { item.id }

    /// "20 min · pp. 142–158"
    var summary: String {
        let minutes = max(1, Int(assignment.minutes.rounded()))
        return "\(minutes) min · \(LeafFormat.pages(from: assignment.fromPage, to: assignment.toPage))"
    }
}

// MARK: - Hero

/// The heart of Today (DESIGN.md §6): the minutes as a headline numeral, the book it is for, the cover
/// with its ribbon, today's pages, and the one prominent button. With `isDone` the numeral is struck
/// through with a hand-drawn ribbon line and the button gives way to "Read a little more".
struct TodayHero: View {
    let item: LibraryItem
    let numeral: Int
    /// "Min", "Min left" or "Done for today"; uppercased on screen.
    let eyebrow: String
    let spokenMinutes: String
    let isDone: Bool
    let strikeDrawn: Bool
    /// Today's pages, when the plan has any.
    let assignment: Assignment?
    let finish: Date?
    /// A session is already running, so the button returns to it.
    let isLive: Bool
    /// How much of today's minutes are read, once reading has begun (nil hides the meter).
    var goalProgress: Double? = nil
    let onStart: () -> Void
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.l) {
                    textBlock
                    cover
                }
            } else {
                HStack(alignment: .top, spacing: Space.l) {
                    textBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                    cover
                }
            }

            pagesLine

            VStack(alignment: .leading, spacing: Space.s) {
                PageSpanBar(current: item.currentPage, todayTo: assignment?.toPage ?? item.currentPage, total: item.book.pages)
                Text(caption)
                    .leafStyle(.caption)
            }

            startButton
        }
        .padding(.top, Space.xl)
    }

    // MARK: Pieces

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: -14) {
                Text("\(numeral)")
                    .leafStyle(.heroNumeral)
                    .contentTransition(.numericText(value: Double(numeral)))
                    .leafAnimation(Motion.paper, value: numeral)
                    .overlay { strike }
                Eyebrow(eyebrow)
                    .padding(.leading, Space.xs)
                GoalMeter(progress: goalProgress)
                    .padding(.top, Space.m)
                    .padding(.leading, Space.xs)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenMinutes)

            Text("of")
                .leafStyle(.pullQuote)
            Text(item.book.title)
                .leafStyle(.title)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.book.author)
                .leafStyle(.author)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var strike: some View {
        if isDone {
            GoalStrikeShape()
                .trim(from: 0, to: strikeDrawn ? 1 : 0)
                .stroke(Color.ribbon, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .padding(.horizontal, -8)
                .animation(reduceMotion ? nil : Motion.strike, value: strikeDrawn)
                .accessibilityHidden(true)
        }
    }

    private var cover: some View {
        Button(action: onOpen) {
            BookCover(book: item.book, size: .l, ribbon: true, swaysRibbon: true)
                .todayBookZoomSource(item.id)
                .padding(.bottom, BookCover.Size.l.ribbonTail)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens book details")
    }

    @ViewBuilder
    private var pagesLine: some View {
        if isDone {
            Text("Today’s reading is done. Anything more is a gift.")
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
        } else if let assignment {
            Text("about \(LeafFormat.pages(from: assignment.fromPage, to: assignment.toPage))")
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "p. 142 of 310 · done by Sun 26 Oct"
    private var caption: String {
        var parts: [String] = []
        if item.currentPage > 0 {
            parts.append("p. \(item.currentPage) of \(item.book.pages)")
        } else {
            parts.append("\(item.book.pages) pages")
        }
        if let finish {
            parts.append("done by \(LeafFormat.format(finish, template: "EEEdMMM"))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var startButton: some View {
        let title = isLive ? "Return to session" : (isDone ? "Read a little more" : "Start reading")
        if isDone {
            SecondaryGlassButton(title, action: onStart)
                .sessionZoomSource(ReadingSessionLauncher.heroSource)
        } else {
            PrimaryGlassButton(title, action: onStart)
                .sessionZoomSource(ReadingSessionLauncher.heroSource)
        }
    }
}

/// A slightly wobbly pen stroke, left to right, for the goal strike.
struct GoalStrikeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let y = rect.midY + h * 0.04
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: y + h * 0.07))
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.5, y: y - h * 0.01),
            control1: CGPoint(x: rect.minX + w * 0.16, y: y + h * 0.12),
            control2: CGPoint(x: rect.minX + w * 0.32, y: y - h * 0.07)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: y - h * 0.08),
            control1: CGPoint(x: rect.minX + w * 0.68, y: y + h * 0.05),
            control2: CGPoint(x: rect.minX + w * 0.86, y: y - h * 0.13)
        )
        return path
    }
}

/// A short `accent` line under the numeral: how much of today's minutes are read. Hidden until reading
/// has begun, and left out once the day is done.
private struct GoalMeter: View {
    let progress: Double?

    var body: some View {
        if let progress, progress > 0, progress < 1 {
            ProgressBar(progress: progress, tint: Color.accent, height: 2)
                .frame(width: 64)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Side by side

/// Today's issue when the time is split across books: the total as the numeral, then a row per book.
struct TodayIssue: View {
    let entries: [TodayEntry]
    let totalMinutes: Int
    let eyebrow: String
    let spokenMinutes: String
    let isLive: Bool
    var goalProgress: Double? = nil
    let onStart: () -> Void
    let onStartBook: (String) -> Void
    let onOpen: (Book) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .bottom, spacing: Space.l) {
                VStack(alignment: .leading, spacing: -14) {
                    Text("\(totalMinutes)")
                        .leafStyle(.heroNumeral)
                        .contentTransition(.numericText(value: Double(totalMinutes)))
                        .leafAnimation(Motion.paper, value: totalMinutes)
                    Eyebrow(eyebrow)
                        .padding(.leading, Space.xs)
                    GoalMeter(progress: goalProgress)
                        .padding(.top, Space.m)
                        .padding(.leading, Space.xs)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenMinutes)
                Text("across \(entries.count) books")
                    .leafStyle(.pullQuote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Space.s)
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("In today’s issue", topSpacing: Space.s)
                ForEach(entries) { entry in
                    TodayBookLine(
                        item: entry.item,
                        caption: entry.summary,
                        action: LineAction(systemImage: "play.fill", label: "Start reading \(entry.item.book.title)") {
                            onStartBook(entry.item.id)
                        },
                        onOpen: { onOpen(entry.item.book) }
                    )
                    if entry.id != entries.last?.id {
                        Hairline()
                    }
                }
            }

            PrimaryGlassButton(isLive ? "Return to session" : "Start reading", action: onStart)
                .sessionZoomSource(ReadingSessionLauncher.heroSource)
        }
        .padding(.top, Space.xl)
    }
}

// MARK: - Rows

/// A trailing symbol button on a row.
struct LineAction {
    let systemImage: String
    let label: String
    let perform: () -> Void
}

/// A cover S, a title, a caption and optionally a progress line; tap opens the book. Used for
/// "In today's issue", "On your desk" and "Up next". Rows are paper, never glass.
struct TodayBookLine: View {
    let item: LibraryItem
    let caption: String
    var showsProgress: Bool = false
    var action: LineAction? = nil
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Button(action: onOpen) {
                HStack(spacing: Space.m) {
                    BookCover(book: item.book, size: .s)
                        .todayBookZoomSource(item.id)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(item.book.title)
                            .leafStyle(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if showsProgress {
                            ProgressBar(progress: item.progress)
                        }
                        Text(caption)
                            .leafStyle(.caption)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.s)
                .frame(minHeight: 66 + Space.m)
                .contentShape(.rect)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("\(item.book.title), \(caption)")
            .accessibilityHint("Opens book details")

            if let action {
                Button {
                    Haptics.shared.press()
                    action.perform()
                } label: {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: Space.hitTarget, height: Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(action.label)
            }
        }
    }
}
