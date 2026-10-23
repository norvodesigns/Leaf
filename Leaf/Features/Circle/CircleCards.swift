import SwiftUI

// MARK: - Club shelf

/// Every circle as a cover on a shelf, the chosen one underlined in Bloom, with a glass spine at the end for a new one.
struct CircleShelf: View {
    let circles: [ReadingCircle]
    let selectedID: UUID?
    let now: Date
    let onSelect: (UUID) -> Void
    let onNew: () -> Void

    @Namespace private var underline
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The cover stays 96 wide; at accessibility sizes the tile widens so names wrap at word breaks, not mid-word.
    private var tileWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 168 : 96 }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Canopy.Space.l) {
                ForEach(circles) { circle in
                    tile(circle)
                }
                newTile
            }
            .padding(.vertical, Canopy.Space.xs)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .scrollTargetBehavior(.viewAligned)
    }

    private func tile(_ circle: ReadingCircle) -> some View {
        let isSelected = circle.id == selectedID
        return Button {
            onSelect(circle.id)
        } label: {
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                BookCover(book: circle.book, size: .m)
                    .clipShape(RoundedRectangle(cornerRadius: Canopy.Radius.cover, style: .continuous))
                    .coverShadow(.m)
                    .opacity(circle.isArchived ? 0.55 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        CircleFaces(members: circle.members, diameter: 22, limit: 3)
                            .padding(Canopy.Space.xs)
                            .opacity(circle.isArchived ? 0.55 : 1)
                    }
                VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                    Text(circle.name)
                        .canopyText(.callout, color: isSelected ? Canopy.text : Canopy.textSecondary)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(when(circle))
                        .canopyText(.caption, color: circle.isArchived ? Canopy.textSecondary : CanopyAccent.dusk.color)
                        .lineLimit(1)
                }
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(CanopyAccent.bloom.color)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
                .frame(height: 3)
            }
            .frame(width: tileWidth, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(circle.name), reading \(circle.book.title), \(circle.members.count == 1 ? "just you" : "\(circle.members.count) people"). \(when(circle))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var newTile: some View {
        Button {
            CanopyFeel.play(.tap)
            onNew()
        } label: {
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                Image(systemName: "plus")
                    .font(.system(.title2, weight: .medium))
                    .foregroundStyle(CanopyAccent.bloom.color)
                    .frame(width: 96, height: 144)
                    .canopyGlass(.bloom, in: RoundedRectangle(cornerRadius: Canopy.Radius.control, style: .continuous))
                Text("New circle")
                    .canopyText(.callout, color: Canopy.textSecondary)
            }
            .frame(width: tileWidth, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start a new circle")
    }

    private func when(_ circle: ReadingCircle) -> String {
        if circle.isArchived { return "Put away" }
        let today = Calendar.current.startOfDay(for: now)
        guard let next = circle.meetings.filter({ Calendar.current.startOfDay(for: $0.date) >= today }).min(by: { $0.date < $1.date }) else {
            return circle.meetings.isEmpty ? "No goals yet" : "All goals met"
        }
        return "p. \(next.throughPage) · \(LeafFormat.relativeDay(next.date, today: now))"
    }
}

// MARK: - Faces

/// Someone in a circle as a small round face: their initials on their tea colour. The reader wears Forest.
struct CircleFace: View {
    let member: CircleMember
    var diameter: CGFloat = 32

    private var tint: Color { member.kind == .me ? CanopyAccent.forest.color : CozyColor.color(for: member.paletteToken) }

    var body: some View {
        ZStack {
            Circle()
                .fill(member.kind == .me ? CanopyAccent.forest.soft : tint.opacity(0.32))
            Circle()
                .strokeBorder(tint, lineWidth: member.kind == .me ? 2 : 1.5)
            Text(member.initials)
                .font(.system(size: max(9, diameter * 0.38), weight: .semibold, design: .rounded))
                .foregroundStyle(Canopy.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(2)
        }
        .frame(width: diameter, height: diameter)
        .background(Circle().fill(Canopy.surface))
        .accessibilityHidden(true)
    }
}

/// A few faces overlapping, for a shelf tile or a goal that people reached.
struct CircleFaces: View {
    let members: [CircleMember]
    var diameter: CGFloat = 24
    var limit: Int = 4

    var body: some View {
        HStack(spacing: -diameter * 0.32) {
            ForEach(members.prefix(limit)) { member in
                CircleFace(member: member, diameter: diameter)
            }
            if members.count > limit {
                Text("+\(members.count - limit)")
                    .font(.system(size: max(9, diameter * 0.36), weight: .semibold, design: .rounded))
                    .foregroundStyle(Canopy.textSecondary)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(Canopy.surface))
                    .overlay(Circle().strokeBorder(Canopy.separator, lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }
}

extension CircleMember {
    /// "You" for the reader, their name for everyone else.
    var displayName: String { kind == .me ? "You" : (name.isEmpty ? "A friend" : name) }
    /// The first word of `displayName`, for tight rows.
    var shortName: String { kind == .me ? "You" : (displayName.split(separator: " ").first.map(String.init) ?? displayName) }
}

// MARK: - The goal

/// The chosen circle's headline, like a Fitness competition's: the book, the goal to reach and when (Dusk), the race
/// to it (everyone on one track through the book), and one way to start reading. A glass card; the black Hero stays
/// on Today.
struct CircleGoalCard: View {
    let circle: ReadingCircle
    let snapshot: CircleSnapshot
    let item: LibraryItem?
    let now: Date
    let onRead: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text(eyebrow)
                    .canopyText(.label, color: CanopyAccent.dusk.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Canopy.Space.s)
                if snapshot.isComplete {
                    Image(systemName: "rosette")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(CanopyAccent.bloom.color)
                        .accessibilityLabel("Read together")
                } else if let days = snapshot.daysUntilNext, !circle.isArchived {
                    Text(countdown(days))
                        .font(.system(.footnote, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CanopyAccent.dusk.color)
                        .padding(.horizontal, Canopy.Space.s)
                        .padding(.vertical, Canopy.Space.xxs)
                        .background(Capsule().fill(CanopyAccent.dusk.soft))
                }
            }

            HStack(alignment: .top, spacing: Canopy.Space.m) {
                BookCover(book: circle.book, size: .s)
                    .clipShape(RoundedRectangle(cornerRadius: Canopy.Radius.cover, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                    Text(circle.name)
                        .canopyText(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(circle.book.title)
                        .font(.system(.body, design: .serif, weight: .semibold))
                        .foregroundStyle(Canopy.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(circle.book.author)
                        .canopyText(.caption)
                }
            }
            .accessibilityElement(children: .combine)

            if let goal = snapshot.nextMeeting {
                VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                    Text("Page \(goal.throughPage)")
                        .font(.custom(LeafFontName.regular, size: 40, relativeTo: .largeTitle))
                        .foregroundStyle(Canopy.text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(goal.throughPage >= circle.book.pages ? "The end of the book, by \(goalDay(goal))" : "Everyone’s goal, by \(goalDay(goal))")
                        .canopyText(.callout, color: Canopy.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            CircleTrack(circle: circle, snapshot: snapshot)

            Text(snapshot.statusLine)
                .canopyText(.body, color: Canopy.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let place = snapshot.nextMeeting?.place, !place.isEmpty {
                Label("Talking it over at \(place)", systemImage: "mappin.and.ellipse")
                    .symbolRenderingMode(.hierarchical)
                    .canopyText(.caption)
            }

            action
        }
        .canopyCard()
    }

    @ViewBuilder
    private var action: some View {
        if let item {
            if item.shelf != .finished, snapshot.myPagesToGo > 0, let next = snapshot.nextMeeting {
                CanopyGlassButton("Read to page \(next.throughPage)", systemImage: "book.pages", accent: .forest, compact: true, feel: nil, action: onRead)
            }
        } else if !snapshot.isComplete {
            VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                CanopyGlassButton("Add to Reading", systemImage: "plus", accent: .forest, compact: true, feel: .keep, action: onAdd)
                Text("Then your page in the circle moves as you read.")
                    .canopyText(.caption)
            }
        }
    }

    private var eyebrow: String {
        if circle.isArchived { return "Put away" }
        guard snapshot.nextMeeting != nil, let index = snapshot.nextMeetingIndex else {
            return snapshot.isComplete ? "Every goal met" : "No goals yet"
        }
        let count = circle.meetings.count
        return count > 1 ? "Goal \(index + 1) of \(count)" : "The goal"
    }

    private func goalDay(_ goal: CircleMeeting) -> String {
        let day = LeafFormat.relativeDay(goal.date, today: now)
        return day == "Today" || day == "Tomorrow" ? day.lowercased() : day
    }

    private func countdown(_ days: Int) -> String {
        switch days {
        case 0: "Today"
        case 1: "1 day left"
        default: "\(days) days left"
        }
    }
}

// MARK: - The track

/// The race through the book: one line from the first page to the last, a tick at each goal (the next one flagged in
/// Dusk with its page underneath), and everyone's face where they've read to. Faces that would sit on top of each
/// other step up a row; the reader is drawn last, on top.
struct CircleTrack: View {
    let circle: ReadingCircle
    let snapshot: CircleSnapshot

    @ScaledMetric(relativeTo: .body) private var face: CGFloat = 28

    private var pages: Int { max(1, circle.book.pages) }

    var body: some View {
        let goals = CirclePlanner.normalized(circle.meetings, pages: pages)
        let rowHeight = face + 4
        GeometryReader { proxy in
            let width = proxy.size.width
            let inset = face / 2
            let usable = max(1, width - face)
            let lineY = rowHeight * 2 - face / 2
            let placed = placements(width: usable)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Canopy.separator)
                    .frame(width: usable, height: 4)
                    .position(x: inset + usable / 2, y: lineY)
                if let me = snapshot.me {
                    Capsule()
                        .fill(CanopyAccent.forest.color.opacity(0.55))
                        .frame(width: max(4, usable * CGFloat(me.fraction)), height: 4)
                        .position(x: inset + usable * CGFloat(me.fraction) / 2, y: lineY)
                }
                ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                    let x = inset + usable * CGFloat(goal.throughPage) / CGFloat(pages)
                    let isNext = index == snapshot.nextMeetingIndex
                    Capsule()
                        .fill(isNext ? CanopyAccent.dusk.color : Canopy.textTertiary.opacity(0.6))
                        .frame(width: isNext ? 3 : 2, height: isNext ? 16 : 10)
                        .position(x: x, y: lineY)
                    if isNext {
                        Text("p. \(goal.throughPage)")
                            .font(.system(.caption2, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(CanopyAccent.dusk.color)
                            .fixedSize()
                            .position(x: min(max(x, 24), width - 24), y: lineY + face / 2 + 10)
                    }
                }
                ForEach(placed, id: \.progress.id) { spot in
                    CircleFace(member: spot.progress.member, diameter: face)
                        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        .position(x: inset + spot.x, y: lineY - CGFloat(spot.row) * (face * 0.8))
                }
            }
        }
        .frame(height: rowHeight * 2 + 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private struct Spot {
        var progress: CircleMemberProgress
        var x: CGFloat
        var row: Int
    }

    /// Left to right, each face on the lowest row (of three) where it clears the face before it; the reader last.
    private func placements(width: CGFloat) -> [Spot] {
        let ordered = snapshot.members.sorted { $0.page != $1.page ? $0.page < $1.page : !$0.isMe && $1.isMe }
        var lastX: [CGFloat] = [-.infinity, -.infinity, -.infinity]
        var spots: [Spot] = []
        for progress in ordered {
            let x = width * CGFloat(progress.fraction)
            let row = lastX.firstIndex { x - $0 >= face * 0.9 } ?? (lastX.indices.min { lastX[$0] < lastX[$1] } ?? 0)
            lastX[row] = x
            spots.append(Spot(progress: progress, x: x, row: row))
        }
        // The reader on top of anyone sharing their spot.
        return spots.filter { !$0.progress.isMe } + spots.filter(\.progress.isMe)
    }

    private var accessibilityText: String {
        let people = snapshot.standings.map { "\($0.member.displayName), page \($0.page)" }.joined(separator: "; ")
        guard let goal = snapshot.nextMeeting else { return people }
        return "\(people). The goal is page \(goal.throughPage) of \(pages)."
    }
}

// MARK: - Standings

/// Who's where, furthest first, as in a Fitness competition: place, face, name, page, a bar to the goal, and what
/// they've read lately. Above it, where the reader stands. Tap someone for more.
struct CircleStandings: View {
    let snapshot: CircleSnapshot
    let pages: Int
    let now: Date
    let onSelect: (CircleMember) -> Void

    @ScaledMetric(relativeTo: .body) private var face: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            if let line = snapshot.standingLine {
                Text(line)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Canopy.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                let rows = snapshot.standings
                ForEach(rows) { progress in
                    Button {
                        CanopyFeel.play(.tap)
                        onSelect(progress.member)
                    } label: {
                        row(progress)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(progress))
                    .accessibilityHint(progress.isMe ? "Shows where you are" : "Shows how they’re doing")
                    .accessibilityAddTraits(.isButton)
                    if progress.id != rows.last?.id {
                        Rectangle()
                            .fill(Canopy.separator)
                            .frame(height: 1)
                    }
                }
            }
        }
        .canopyCard()
    }

    private func row(_ progress: CircleMemberProgress) -> some View {
        HStack(alignment: .center, spacing: Canopy.Space.m) {
            place(progress)
                .frame(width: 22)
            CircleFace(member: progress.member, diameter: face)
            VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(progress.member.displayName)
                        .canopyText(.body)
                        .fontWeight(progress.isMe ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer(minLength: Canopy.Space.s)
                    Text("p. \(progress.page)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Canopy.text)
                }
                CanopyProgressBar(value: barValue(progress), accent: progress.pace == .catchingUp ? .dusk : .forest, height: 5)
                HStack(spacing: Canopy.Space.xs) {
                    Text(paceWord(progress))
                        .canopyText(.caption, color: progress.pace == .ready || progress.pace == .finished ? CanopyAccent.forest.color : Canopy.textSecondary)
                    if let lately = lately(progress) {
                        Text("·").canopyText(.caption)
                        Text(lately).canopyText(.caption)
                    }
                    Spacer(minLength: 0)
                    if progress.goalsMet > 0 {
                        Label("\(progress.goalsMet)", systemImage: "leaf.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(.caption, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(CanopyAccent.forest.color)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
        }
        .padding(.vertical, Canopy.Space.m)
        .frame(minHeight: Canopy.Space.hitTarget)
        .contentShape(.rect)
    }

    @ViewBuilder
    private func place(_ progress: CircleMemberProgress) -> some View {
        if progress.rank == 1, snapshot.members.count > 1 {
            Image(systemName: "crown.fill")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(CanopyAccent.clay.color)
        } else {
            Text("\(progress.rank)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                .foregroundStyle(Canopy.textTertiary)
        }
    }

    /// To the next goal's page, or through the book once every goal has passed.
    private func barValue(_ progress: CircleMemberProgress) -> Double {
        guard let goal = snapshot.nextMeeting else { return progress.fraction }
        return Double(progress.page) / Double(max(1, goal.throughPage))
    }

    private func paceWord(_ progress: CircleMemberProgress) -> String {
        switch progress.pace {
        case .finished: "Finished"
        case .ready: snapshot.nextMeeting == nil ? "Done" : "Goal met"
        case .onPace: "\(progress.pagesToGoal) to go"
        case .catchingUp: "Catching up"
        }
    }

    /// "+12 today", "30 this week", "last read Monday". Nothing for friends added by name, whose pages don't move.
    private func lately(_ progress: CircleMemberProgress) -> String? {
        if progress.pagesToday > 0 { return "+\(progress.pagesToday) today" }
        if progress.pagesThisWeek > 0 { return "\(progress.pagesThisWeek) this week" }
        guard let last = progress.lastRead else { return nil }
        return "last read \(LeafFormat.relativeDay(last, today: now).lowercased())"
    }

    private func label(_ progress: CircleMemberProgress) -> String {
        var parts = ["\(progress.member.displayName), place \(progress.rank), page \(progress.page) of \(pages)", paceWord(progress)]
        if let lately = lately(progress) { parts.append(lately) }
        if progress.goalsMet > 0 { parts.append(progress.goalsMet == 1 ? "1 goal met" : "\(progress.goalsMet) goals met") }
        return parts.joined(separator: ". ") + "."
    }
}

// MARK: - Lately

/// What the circle has been up to, newest first: sittings, goals reached, finishes, people joining.
struct CircleActivityList: View {
    let circle: ReadingCircle
    let activity: [CircleActivity]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(activity) { event in
                if let member = circle.members.first(where: { $0.id == event.memberID }) {
                    HStack(alignment: .center, spacing: Canopy.Space.m) {
                        CircleFace(member: member, diameter: 30)
                        Text(sentence(event, member: member))
                            .canopyText(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Canopy.Space.s)
                        Text(time(event.date))
                            .canopyText(.caption)
                            .lineLimit(1)
                    }
                    .padding(.vertical, Canopy.Space.s)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(sentence(event, member: member)), \(time(event.date))")
                }
            }
        }
        .canopyCard()
    }

    private func sentence(_ event: CircleActivity, member: CircleMember) -> String {
        let who = member.shortName
        switch event.kind {
        case .read(let pages):
            return "\(who) read \(pages == 1 ? "a page" : "\(pages) pages")"
        case .reachedGoal(let page, let date):
            let day = LeafFormat.relativeDay(date, today: now)
            return "\(who) reached page \(page), \(day == "Today" ? "today’s" : day == "Tomorrow" ? "tomorrow’s" : "\(day)’s") goal"
        case .finished:
            return "\(who) finished the book"
        case .joined(let page):
            return page > 0 ? "\(who) joined at page \(page)" : "\(who) joined"
        }
    }

    /// "8:12 AM" today, then "Yesterday", "Monday", "Oct 9".
    private func time(_ date: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? LeafFormat.format(date, template: "jmm")
            : LeafFormat.relativeDay(date, today: now)
    }
}

// MARK: - Inviting

/// A circle that is only the reader so far: what an invitation does, and the button that sends one.
struct CircleInviteCard: View {
    let circle: ReadingCircle
    let isPreparing: Bool
    let onInvite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            Image(systemName: "person.2.wave.2")
                .font(.system(.title2, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CanopyAccent.bloom.color)
                .accessibilityHidden(true)
            Text("Invite your circle")
                .canopyText(.headline)
            Text("Send a link to whoever’s reading \(Text(circle.book.title).italic()) with you. Once they join, their pages move as they read, and everyone sees who’s where.")
                .canopyText(.callout, color: Canopy.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            CanopyGlassButton(isPreparing ? "Getting the invitation ready…" : "Invite friends", systemImage: "paperplane", accent: .bloom, compact: true, action: onInvite)
                .disabled(isPreparing)
                .padding(.top, Canopy.Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .canopyCard(tint: .bloom)
    }
}

// MARK: - Questions

/// Questions for the next goal as Bloom-washed glass cards to swipe through, another set a tap away, and a way to
/// send them to the circle (as text, through the share sheet). A new set arrives with Focus In.
struct CirclePromptDeck: View {
    let circle: ReadingCircle
    let snapshot: CircleSnapshot
    @Binding var shuffle: Int
    let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var prompts: [CirclePrompt] {
        CirclePrompts.prompts(for: circle, meetingIndex: snapshot.nextMeetingIndex ?? 0, count: 3, shuffle: shuffle)
    }

    var body: some View {
        let set = prompts
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel(header, accent: .bloom, linkTitle: "Other questions") {
                withAnimation(Canopy.Motion.resolved(Canopy.Motion.focusIn, reduceMotion: reduceMotion)) {
                    shuffle += 1
                }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Canopy.Space.m) {
                    ForEach(Array(set.enumerated()), id: \.element.id) { index, prompt in
                        card(prompt, number: index + 1, of: set.count)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollTargetBehavior(.viewAligned)
            .id(shuffle)
            .canopyFocusInTransition()

            ShareLink(item: shareText(set)) {
                Label("Send to the circle", systemImage: "square.and.arrow.up")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Canopy.text)
                    .padding(.horizontal, Canopy.Space.l)
                    .frame(minHeight: Canopy.Space.hitTarget)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .canopyGlass()
            .simultaneousGesture(TapGesture().onEnded { CanopyFeel.play(.tap) })
        }
    }

    private var header: String {
        guard let next = snapshot.nextMeeting else { return "Questions to talk over" }
        let day = LeafFormat.relativeDay(next.date, today: now)
        return "To talk over by \(day == "Today" ? "today" : day == "Tomorrow" ? "tomorrow" : day)"
    }

    private func card(_ prompt: CirclePrompt, number: Int, of count: Int) -> some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            Text(kindTitle(prompt.kind))
                .canopyText(.label, color: CanopyAccent.bloom.color)
            Text(prompt.text)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Canopy.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("\(number) of \(count)")
                .font(.system(.footnote, design: .rounded, weight: .medium).monospacedDigit())
                .foregroundStyle(Canopy.textSecondary)
        }
        .frame(width: 224, alignment: .topLeading)
        .frame(minHeight: 150, alignment: .topLeading)
        .canopyCard(tint: .bloom)
        .frame(width: 264)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(number) of \(count). \(prompt.text)")
    }

    private func kindTitle(_ kind: CirclePrompt.Kind) -> String {
        switch kind {
        case .opening: "To open with"
        case .middle: "Along the way"
        case .closing: "For the ending"
        case .genre: circle.book.genres.first.map { $0.replacingOccurrences(of: "-", with: " ").capitalized } ?? "This book"
        }
    }

    /// Plain text for Messages or Mail: the goal, and the questions.
    private func shareText(_ prompts: [CirclePrompt]) -> String {
        var lines = ["\(circle.name) · \(circle.book.title)"]
        if let next = snapshot.nextMeeting {
            let date = LeafFormat.format(next.date, template: "EEEEMMMd")
            var goal = "Up to page \(next.throughPage) by \(date)"
            if let place = next.place, !place.isEmpty { goal += ", then \(place)" }
            lines.append(goal)
        }
        lines.append("")
        lines.append(contentsOf: prompts.enumerated().map { "\($0.offset + 1). \($0.element.text)" })
        return lines.joined(separator: "\n")
    }
}

// MARK: - Goals

/// The goals in order on one glass card: the ones that have passed, ticked in Forest with the faces of who made it;
/// the next, its date in Dusk; the rest, waiting.
struct CircleGoalList: View {
    let circle: ReadingCircle
    let snapshot: CircleSnapshot
    /// Each member's log, the reader's from their sittings, to tell who made which goal.
    let log: (CircleMember) -> [CircleCheckIn]
    let now: Date

    var body: some View {
        let goals = CirclePlanner.normalized(circle.meetings, pages: circle.book.pages)
        Group {
            if goals.isEmpty {
                Text("No goals yet. Pick a page and a day, and everyone has something to aim for.")
                    .canopyText(.callout, color: Canopy.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                        row(goal, index: index, previousPage: index > 0 ? goals[index - 1].throughPage : 0)
                        if index < goals.count - 1 {
                            Rectangle()
                                .fill(Canopy.separator)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .canopyCard()
    }

    private func row(_ goal: CircleMeeting, index: Int, previousPage: Int) -> some View {
        let rowState = state(index)
        let made = madeIt(goal)
        return HStack(alignment: .center, spacing: Canopy.Space.m) {
            marker(rowState)
            VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                Text("Page \(goal.throughPage) by \(LeafFormat.relativeDay(goal.date, today: now))")
                    .canopyText(.body, color: dateColor(rowState))
                    .fontWeight(rowState == .next ? .semibold : .regular)
                if let place = goal.place, !place.isEmpty {
                    Text(place)
                        .canopyText(.caption)
                }
            }
            Spacer(minLength: Canopy.Space.s)
            if !made.isEmpty {
                CircleFaces(members: made, diameter: 22, limit: 3)
            } else {
                Text(LeafFormat.pages(from: previousPage + 1, to: goal.throughPage))
                    .font(.system(.subheadline, design: .rounded, weight: .medium).monospacedDigit())
                    .foregroundStyle(rowState == .past ? Canopy.textTertiary : Canopy.textSecondary)
            }
        }
        .padding(.vertical, Canopy.Space.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(goal, state: rowState, previousPage: previousPage, made: made))
    }

    /// Who reached this goal by its day.
    private func madeIt(_ goal: CircleMeeting) -> [CircleMember] {
        circle.members.filter { member in
            let page = snapshot.members.first { $0.id == member.id }?.page ?? member.page
            return CirclePlanner.goalsMet([goal], page: page, log: log(member), updatedAt: member.updatedAt, now: now, calendar: .current) == 1
        }
    }

    private enum RowState { case past, next, later }

    private func state(_ index: Int) -> RowState {
        guard let next = snapshot.nextMeetingIndex else { return .past }
        if index < next { return .past }
        return index == next ? .next : .later
    }

    private func dateColor(_ state: RowState) -> Color {
        switch state {
        case .past: Canopy.textSecondary
        case .next: CanopyAccent.dusk.color
        case .later: Canopy.text
        }
    }

    @ViewBuilder
    private func marker(_ state: RowState) -> some View {
        switch state {
        case .past:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CanopyAccent.forest.color)
        case .next:
            Image(systemName: "flag.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CanopyAccent.dusk.color)
        case .later:
            Image(systemName: "circle")
                .foregroundStyle(Canopy.textTertiary)
        }
    }

    private func accessibilityText(_ goal: CircleMeeting, state: RowState, previousPage: Int, made: [CircleMember]) -> String {
        let day = LeafFormat.format(goal.date, template: "EEEEMMMMd")
        let prefix: String
        switch state {
        case .past: prefix = "Passed goal"
        case .next: prefix = "Next goal"
        case .later: prefix = "Goal"
        }
        let place = goal.place.map { $0.isEmpty ? "" : ", talking it over at \($0)" } ?? ""
        let who = made.isEmpty ? "" : ". Reached by \(made.map(\.displayName).joined(separator: ", "))"
        return "\(prefix), page \(goal.throughPage) by \(day)\(place)\(who)"
    }
}
