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
        .accessibilityLabel("\(circle.name), reading \(circle.book.title). \(when(circle))")
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
            return circle.meetings.isEmpty ? "No date yet" : "All met"
        }
        return LeafFormat.relativeDay(next.date, today: now)
    }
}

// MARK: - Next meeting

/// The chosen circle's headline: the book, the next meeting (Dusk), the reader's way there (Forest), and one way to
/// start reading. A glass card; the one black Hero stays on Today.
struct CircleMeetingCard: View {
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

            Text(snapshot.statusLine)
                .canopyText(.body, color: Canopy.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let me = snapshot.me, let next = snapshot.nextMeeting {
                VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                    CanopyProgressBar(value: Double(me.page) / Double(max(1, next.throughPage)))
                    Text("p. \(me.page) of \(next.throughPage) for this meeting · \(circle.book.pages) in the book")
                        .canopyText(.caption)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("You’re on page \(me.page). This meeting reads to page \(next.throughPage).")
            }

            if let place = snapshot.nextMeeting?.place, !place.isEmpty {
                Label(place, systemImage: "mappin.and.ellipse")
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
            CanopyGlassButton("Add to Reading", systemImage: "plus", accent: .forest, compact: true, feel: .keep, action: onAdd)
                .accessibilityHint("Your page in the circle then follows your library.")
        }
    }

    private var eyebrow: String {
        if circle.isArchived { return "Put away" }
        guard let next = snapshot.nextMeeting, let index = snapshot.nextMeetingIndex else {
            return snapshot.isComplete ? "All met" : "No meetings yet"
        }
        let day = LeafFormat.relativeDay(next.date, today: now)
        let time = LeafFormat.format(next.date, template: "jmm")
        let count = circle.meetings.count
        return count > 1 ? "Meeting \(index + 1) of \(count) · \(day), \(time)" : "Meeting · \(day), \(time)"
    }
}

// MARK: - Members

/// A Forest ring for everyone in the circle, filled to their page in the book, with where they stand against the next
/// meeting underneath. Tap a ring to move someone along.
struct CircleMemberGrid: View {
    let snapshot: CircleSnapshot
    let pages: Int
    let onEdit: (CircleMember) -> Void

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 60

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: diameter + 24), spacing: Canopy.Space.m, alignment: .top)], spacing: Canopy.Space.l) {
            ForEach(snapshot.members) { progress in
                Button {
                    CanopyFeel.play(.tap)
                    onEdit(progress.member)
                } label: {
                    cell(progress)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(progress))
                .accessibilityHint(progress.member.kind == .me ? "Shows where you are" : "Updates their page")
                .accessibilityAddTraits(.isButton)
            }
        }
        .canopyCard()
    }

    private func cell(_ progress: CircleMemberProgress) -> some View {
        VStack(spacing: Canopy.Space.xs) {
            CanopyRing(value: progress.fraction, accent: .forest, lineWidth: 5) {
                if progress.pace == .finished {
                    Image(systemName: "checkmark")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(CanopyAccent.forest.color)
                } else {
                    Text(progress.member.initials)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Canopy.text)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: diameter, height: diameter)
            Text(progress.member.kind == .me ? "You" : progress.member.name)
                .canopyText(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("p. \(progress.page)")
                .font(.system(.footnote, design: .rounded, weight: .medium).monospacedDigit())
                .foregroundStyle(Canopy.textSecondary)
            Text(paceWord(progress.pace))
                .canopyText(.caption, color: progress.pace == .ready || progress.pace == .finished ? CanopyAccent.forest.color : Canopy.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: Canopy.Space.hitTarget)
        .contentShape(.rect)
    }

    private func paceWord(_ pace: CirclePace) -> String {
        switch pace {
        case .finished: "Finished"
        case .ready: "Ready"
        case .onPace: "On pace"
        case .catchingUp: "Catching up"
        }
    }

    private func label(_ progress: CircleMemberProgress) -> String {
        let who = progress.member.kind == .me ? "You" : progress.member.name
        return "\(who), page \(progress.page) of \(pages). \(paceWord(progress.pace))."
    }
}

// MARK: - Questions

/// Questions for the next meeting as Bloom-washed glass cards to swipe through, another set a tap away, and a way to
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
        guard let next = snapshot.nextMeeting else { return "Questions" }
        let day = LeafFormat.relativeDay(next.date, today: now)
        return "Questions for \(day == "Today" ? "today" : day == "Tomorrow" ? "tomorrow" : day)"
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
        case .closing: "For the last meeting"
        case .genre: circle.book.genres.first.map { $0.replacingOccurrences(of: "-", with: " ").capitalized } ?? "This book"
        }
    }

    /// Plain text for Messages or Mail: the meeting, the pages, and the questions.
    private func shareText(_ prompts: [CirclePrompt]) -> String {
        var lines = ["\(circle.name) · \(circle.book.title)"]
        if let next = snapshot.nextMeeting {
            let date = LeafFormat.format(next.date, template: "EEEEMMMd")
            var meeting = "\(date): up to page \(next.throughPage)"
            if let place = next.place, !place.isEmpty { meeting += ", \(place)" }
            lines.append(meeting)
        }
        lines.append("")
        lines.append(contentsOf: prompts.enumerated().map { "\($0.offset + 1). \($0.element.text)" })
        return lines.joined(separator: "\n")
    }
}

// MARK: - Schedule

/// The meetings in order on one glass card: the ones that have been, ticked in Forest; the next, its date in Dusk; the
/// rest, waiting.
struct CircleScheduleList: View {
    let circle: ReadingCircle
    let snapshot: CircleSnapshot
    let now: Date

    var body: some View {
        let meetings = CirclePlanner.normalized(circle.meetings, pages: circle.book.pages)
        Group {
            if meetings.isEmpty {
                Text("No meetings yet. Add a date and everyone gets a page to aim for.")
                    .canopyText(.callout, color: Canopy.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                        row(meeting, index: index, previousPage: index > 0 ? meetings[index - 1].throughPage : 0)
                        if index < meetings.count - 1 {
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

    private func row(_ meeting: CircleMeeting, index: Int, previousPage: Int) -> some View {
        let rowState = state(index)
        return HStack(alignment: .firstTextBaseline, spacing: Canopy.Space.m) {
            marker(rowState)
            VStack(alignment: .leading, spacing: Canopy.Space.xxs) {
                Text(LeafFormat.relativeDay(meeting.date, today: now))
                    .canopyText(.body, color: dateColor(rowState))
                    .fontWeight(rowState == .next ? .semibold : .regular)
                if let place = meeting.place, !place.isEmpty {
                    Text(place)
                        .canopyText(.caption)
                }
            }
            Spacer(minLength: Canopy.Space.s)
            Text(LeafFormat.pages(from: previousPage + 1, to: meeting.throughPage))
                .font(.system(.subheadline, design: .rounded, weight: .medium).monospacedDigit())
                .foregroundStyle(rowState == .past ? Canopy.textTertiary : Canopy.textSecondary)
        }
        .padding(.vertical, Canopy.Space.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(meeting, state: rowState, previousPage: previousPage))
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
            Image(systemName: "clock")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CanopyAccent.dusk.color)
        case .later:
            Image(systemName: "circle")
                .foregroundStyle(Canopy.textTertiary)
        }
    }

    private func accessibilityText(_ meeting: CircleMeeting, state: RowState, previousPage: Int) -> String {
        let day = LeafFormat.format(meeting.date, template: "EEEEMMMMd")
        let prefix: String
        switch state {
        case .past: prefix = "Met"
        case .next: prefix = "Next meeting"
        case .later: prefix = "Meeting"
        }
        let place = meeting.place.map { $0.isEmpty ? "" : ", \($0)" } ?? ""
        return "\(prefix), \(day), pages \(previousPage + 1) to \(meeting.throughPage)\(place)"
    }
}
