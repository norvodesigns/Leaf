import SwiftUI

/// Today's circle card, right under "Where you left off". With a circle under way: its next goal, a bar for each
/// person on one scale through the book with the goal marked across them, and where the reader stands; a tap opens the
/// circle. With no circle yet: what a circle is and the three steps to one, which the reader can put away for good.
struct TodayCircleCard: View {
    let onOpen: (UUID) -> Void
    let onStart: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TodayCircleCard.tipDismissedKey) private var tipDismissed = false

    /// The suggestion was put away ("Not now" or ×). Today reads it too, to leave the card's place empty.
    static let tipDismissedKey = "today.circleTipDismissed"
    /// Rows on the card: the reader and the people nearest the front.
    static let rowLimit = 4

    /// Circles under way, soonest goal first: the first is the one Today shows.
    @MainActor static func active(in store: LibraryStore) -> [ReadingCircle] {
        store.circleStore.shelf(now: store.now).filter { !$0.isArchived }
    }

    /// Whether the suggestion is due: no circles at all, and not put away.
    @MainActor static func suggests(in store: LibraryStore, dismissed: Bool) -> Bool {
        store.data.circles.isEmpty && !dismissed
    }

    var body: some View {
        if let circle = Self.active(in: store).first {
            progressCard(circle, more: Self.active(in: store).count - 1)
        } else if Self.suggests(in: store, dismissed: tipDismissed) {
            suggestion
        }
    }

    // MARK: A circle under way

    private func progressCard(_ circle: ReadingCircle, more: Int) -> some View {
        let myLog = CircleCheckIn.log(from: store.data.sessions, bookID: circle.book.id)
        let snapshot = CirclePlanner.snapshot(
            for: circle, myPage: store.item(circle.book.id)?.currentPage, myLog: myLog, wpm: store.wpm, now: store.now,
            calendar: store.calendar
        )
        let pages = max(1, circle.book.pages)
        let goalFraction = snapshot.nextMeeting.map { Double($0.throughPage) / Double(pages) }
        return TodayCard("Reading circle", actionTitle: more > 0 ? "All circles" : "Open", action: { onOpen(circle.id) }) {
            Button {
                CanopyFeel.play(.tap)
                onOpen(circle.id)
            } label: {
                VStack(alignment: .leading, spacing: Canopy.Space.m) {
                    HStack(alignment: .center, spacing: Canopy.Space.m) {
                        BookCover(book: circle.book, size: .xs)
                            .clipShape(RoundedRectangle(cornerRadius: Canopy.Radius.cover, style: .continuous))
                        VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                            Text(circle.name)
                                .canopyText(.headline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(goalLine(snapshot))
                                .canopyText(.caption, color: CanopyAccent.dusk.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: Canopy.Space.s) {
                        ForEach(rows(snapshot)) { progress in
                            CircleRaceRow(progress: progress, goalFraction: goalFraction)
                        }
                    }
                    Text(footnote(circle, snapshot: snapshot, more: more))
                        .canopyText(.callout, color: Canopy.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pressable)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(circle, snapshot: snapshot))
            .accessibilityHint("Opens the circle")
            .accessibilityAddTraits(.isButton)
        }
    }

    /// The front of the standings, with the reader always in it.
    private func rows(_ snapshot: CircleSnapshot) -> [CircleMemberProgress] {
        let standings = snapshot.standings
        var rows = Array(standings.prefix(Self.rowLimit))
        if let me = snapshot.me, !rows.contains(where: \.isMe) {
            rows[rows.count - 1] = me
        }
        return rows
    }

    /// "Page 200 by Thursday · 3 days left"
    private func goalLine(_ snapshot: CircleSnapshot) -> String {
        guard let goal = snapshot.nextMeeting, let days = snapshot.daysUntilNext else {
            return snapshot.isComplete ? "Every goal met" : "No goals yet"
        }
        let day = LeafFormat.relativeDay(goal.date, today: store.now, calendar: store.calendar)
        let when = day == "Today" || day == "Tomorrow" ? day.lowercased() : day
        let left = days == 0 ? "today" : days == 1 ? "1 day left" : "\(days) days left"
        return days == 0 ? "Page \(goal.throughPage) by today" : "Page \(goal.throughPage) by \(when) · \(left)"
    }

    private func footnote(_ circle: ReadingCircle, snapshot: CircleSnapshot, more: Int) -> String {
        var line = circle.friends.isEmpty
            ? "Just you so far. Open the circle to invite the people reading with you."
            : (snapshot.standingLine ?? snapshot.statusLine)
        if more > 0 { line += more == 1 ? " One more circle under You." : " \(more) more circles under You." }
        return line
    }

    private func accessibilityText(_ circle: ReadingCircle, snapshot: CircleSnapshot) -> String {
        let people = rows(snapshot).map { "\($0.member.displayName) on page \($0.page)" }.joined(separator: ", ")
        return "Reading circle \(circle.name). \(goalLine(snapshot)). \(people). \(footnote(circle, snapshot: snapshot, more: 0))"
    }

    // MARK: No circle yet

    private var suggestion: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.l) {
            HStack(alignment: .center) {
                CanopyLabel("Reading circles")
                Button(action: putAway) {
                    Image(systemName: "xmark")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(Canopy.textTertiary)
                        .frame(width: Canopy.Space.hitTarget, height: Canopy.Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.vertical, -Canopy.Space.m)
                .padding(.trailing, -Canopy.Space.m)
                .accessibilityLabel("Not now")
                .accessibilityHint("Hides this suggestion")
            }
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                Text("Read with friends, and race to the page")
                    .canopyText(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Start a circle for a book you’re reading together. Everyone’s progress shows up right here, under your book.")
                    .canopyText(.callout, color: Canopy.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CircleRaceSample()
            CircleHowItWorks()
            HStack(spacing: Canopy.Space.l) {
                CanopyGlassButton("Start a circle", systemImage: "plus", accent: .bloom, compact: true, action: onStart)
                Button(action: putAway) {
                    Text("Not now")
                        .canopyText(.callout, color: Canopy.textSecondary)
                        .frame(minHeight: Canopy.Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .canopyCard()
    }

    private func putAway() {
        CanopyFeel.play(.tap)
        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
            tipDismissed = true
        }
    }
}

// MARK: - Race rows

/// One person on Today's card: face, name, a bar through the book in their colour (the reader's in Forest), the
/// goal's page as a Dusk tick that lines up down the rows, and their page.
struct CircleRaceRow: View {
    let progress: CircleMemberProgress
    let goalFraction: Double?

    @ScaledMetric(relativeTo: .footnote) private var nameWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .footnote) private var pageWidth: CGFloat = 48

    var body: some View {
        HStack(spacing: Canopy.Space.s) {
            CircleFace(member: progress.member, diameter: 24)
            Text(progress.member.shortName)
                .font(.system(.footnote, weight: progress.isMe ? .semibold : .regular))
                .foregroundStyle(Canopy.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: nameWidth, alignment: .leading)
            CircleRaceBar(
                fraction: progress.fraction,
                goalFraction: goalFraction,
                tint: progress.isMe ? CanopyAccent.forest.color : CozyColor.color(for: progress.member.paletteToken)
            )
            Text("p. \(progress.page)")
                .font(.system(.footnote, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(progress.isMe ? Canopy.text : Canopy.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: pageWidth, alignment: .trailing)
        }
    }
}

/// A bar through the book on a separator track, with the goal as a tick across it.
struct CircleRaceBar: View {
    let fraction: Double
    let goalFraction: Double?
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let filled = CGFloat(min(1, max(0, fraction.isFinite ? fraction : 0)))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Canopy.separator)
                    .frame(height: 8)
                Capsule()
                    .fill(tint)
                    .frame(width: max(8, width * filled), height: 8)
                    .opacity(filled > 0 ? 1 : 0)
                if let goalFraction {
                    Capsule()
                        .fill(CanopyAccent.dusk.color)
                        .frame(width: 2, height: 16)
                        .offset(x: min(width - 2, max(0, width * CGFloat(goalFraction) - 1)))
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: 16)
        .animation(Canopy.Motion.smooth, value: fraction)
        .accessibilityHidden(true)
    }
}

/// A made-up race for the suggestion: three bars and a goal, so the card shows what a circle looks like.
private struct CircleRaceSample: View {
    var body: some View {
        VStack(spacing: Canopy.Space.s) {
            CircleRaceBar(fraction: 0.62, goalFraction: 0.7, tint: CanopyAccent.forest.color)
            CircleRaceBar(fraction: 0.78, goalFraction: 0.7, tint: CozyColor.chai)
            CircleRaceBar(fraction: 0.44, goalFraction: 0.7, tint: CozyColor.rooibos)
        }
        .padding(.vertical, Canopy.Space.xs)
        .accessibilityHidden(true)
    }
}
