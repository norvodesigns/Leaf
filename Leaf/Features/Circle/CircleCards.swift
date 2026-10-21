import SwiftUI

// MARK: - Club shelf

/// Every circle as a cover on a shelf, the chosen one underlined in ribbon like the Plan switcher, with a blank
/// spine at the end for a new one.
struct CircleShelf: View {
    let circles: [ReadingCircle]
    let selectedID: UUID?
    let now: Date
    let onSelect: (UUID) -> Void
    let onNew: () -> Void

    @Namespace private var underline

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Space.l) {
                ForEach(circles) { circle in
                    tile(circle)
                }
                newTile
            }
            .padding(.vertical, Space.xs)
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
            VStack(alignment: .leading, spacing: Space.s) {
                BookCover(book: circle.book, size: .m)
                    .coverShadow(.m)
                    .opacity(circle.isArchived ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(circle.name)
                        .leafStyle(.ui, color: isSelected ? Color.ink : Color.inkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(when(circle))
                        .leafStyle(.caption, color: .inkTertiary)
                        .lineLimit(1)
                }
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.ribbon)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
                .frame(height: 2)
            }
            .frame(width: 96, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(circle.name), reading \(circle.book.title). \(when(circle))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var newTile: some View {
        Button(action: onNew) {
            VStack(alignment: .leading, spacing: Space.s) {
                RoundedRectangle(cornerRadius: Radius.cover, style: .continuous)
                    .strokeBorder(Color.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 96, height: 144)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Color.inkSecondary)
                    }
                Text("New circle")
                    .leafStyle(.ui, color: .inkSecondary)
            }
            .frame(width: 96, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
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

/// The chosen circle's headline: the book, the next meeting, the reader's way there, and one way to start reading.
struct CircleMeetingCard: View {
    let circle: ReadingCircle
    let snapshot: CircleSnapshot
    let item: LibraryItem?
    let now: Date
    let onRead: () -> Void
    let onAdd: () -> Void

    var body: some View {
        TodayCard(eyebrow) {
            HStack(alignment: .top, spacing: Space.m) {
                BookCover(book: circle.book, size: .s)
                    .coverShadow(.s)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(circle.name)
                        .leafStyle(.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Text(circle.book.title).italic()) by \(circle.book.author)")
                        .leafStyle(.author)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if snapshot.isComplete {
                    StampSeal(rings: 3, token: CozyPalette.matcha, diameter: 48, symbol: "person.2")
                        .accessibilityLabel("Read together stamp")
                }
            }
            .accessibilityElement(children: .combine)

            Text(snapshot.statusLine)
                .leafStyle(.body, color: .inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let me = snapshot.me {
                VStack(alignment: .leading, spacing: Space.xs) {
                    PageSpanBar(current: me.page, todayTo: max(me.page, snapshot.sectionEnd), total: circle.book.pages)
                        .accessibilityHidden(true)
                    Text(pagesLine(me.page))
                        .leafStyle(.caption)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }

            if let place = snapshot.nextMeeting?.place, !place.isEmpty {
                Label(place, systemImage: "mappin.and.ellipse")
                    .leafStyle(.caption, color: .inkSecondary)
            }

            action
        }
    }

    @ViewBuilder
    private var action: some View {
        if let item {
            if item.shelf != .finished, snapshot.myPagesToGo > 0, let next = snapshot.nextMeeting {
                SecondaryGlassButton("Read towards page \(next.throughPage)", systemImage: "book", compact: true, playsHaptic: false, action: onRead)
            }
        } else if !snapshot.isComplete {
            SecondaryGlassButton("Add to Reading", systemImage: "plus", compact: true, playsHaptic: false, action: onAdd)
                .accessibilityHint("Your page in the circle then follows your library.")
        }
    }

    private var eyebrow: String {
        if circle.isArchived { return "Put away" }
        guard let next = snapshot.nextMeeting, let index = snapshot.nextMeetingIndex else {
            return snapshot.isComplete ? "All met" : "No meetings yet"
        }
        let day = LeafFormat.relativeDay(next.date, today: now)
        let count = circle.meetings.count
        return count > 1 ? "Meeting \(index + 1) of \(count) · \(day)" : "Meeting · \(day)"
    }

    private func pagesLine(_ page: Int) -> String {
        let of = "p. \(page) of \(circle.book.pages)"
        guard let next = snapshot.nextMeeting else { return of }
        return "\(of) · meeting reads to p. \(next.throughPage)"
    }
}

// MARK: - Members

/// A ring for everyone in the circle, filled to their page in the book, with where they stand against the next
/// meeting underneath. Tap a ring to move someone along.
struct CircleMemberGrid: View {
    let snapshot: CircleSnapshot
    let pages: Int
    let onEdit: (CircleMember) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var diameter: CGFloat { dynamicTypeSize.isAccessibilitySize ? 76 : 60 }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: diameter + 24), spacing: Space.m, alignment: .top)], spacing: Space.l) {
            ForEach(snapshot.members) { progress in
                Button {
                    Haptics.shared.tap()
                    onEdit(progress.member)
                } label: {
                    cell(progress)
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(progress))
                .accessibilityHint(progress.member.kind == .me ? "Shows where you are" : "Updates their page")
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func cell(_ progress: CircleMemberProgress) -> some View {
        VStack(spacing: Space.xs) {
            ProgressRing(
                progress: progress.fraction, diameter: diameter, lineWidth: 5,
                tint: CozyColor.color(for: progress.member.paletteToken), label: progress.member.name
            )
            .overlay {
                if progress.pace == .finished {
                    Image(systemName: "checkmark")
                        .font(.system(size: diameter * 0.28, weight: .medium))
                        .foregroundStyle(Color.accent)
                } else {
                    Text(progress.member.initials)
                        .font(.system(size: diameter * 0.3, weight: .regular, design: .serif))
                        .foregroundStyle(Color.ink)
                }
            }
            Text(progress.member.name)
                .leafStyle(.ui)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("p. \(progress.page)")
                .leafStyle(.caption)
                .monospacedDigit()
            Text(paceWord(progress.pace))
                .leafStyle(.caption, color: progress.pace == .ready || progress.pace == .finished ? Color.accent : Color.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: Space.hitTarget)
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

/// Questions for the next meeting as paper cards to swipe through, with another set a tap away and a way to send
/// the lot to the circle (as text, through the share sheet).
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
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(header, actionTitle: "Other questions") {
                Haptics.shared.play(.pageTurn)
                withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                    shuffle += 1
                }
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Space.m) {
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
            .focusPullTransition(radius: 8)

            ShareLink(item: shareText(set)) {
                Label("Send to the circle", systemImage: "square.and.arrow.up")
                    .leafStyle(.ui, color: .accent)
                    .frame(minHeight: Space.hitTarget)
            }
            .padding(.top, Space.s)
        }
    }

    private var header: String {
        guard let next = snapshot.nextMeeting else { return "Questions" }
        let day = LeafFormat.relativeDay(next.date, today: now)
        return "Questions for \(day == "Today" ? "today" : day == "Tomorrow" ? "tomorrow" : day)"
    }

    private func card(_ prompt: CirclePrompt, number: Int, of count: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow(kindTitle(prompt.kind))
            Text(prompt.text)
                .leafStyle(.title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("\(number) of \(count)")
                .leafStyle(.caption, color: .inkTertiary)
                .monospacedDigit()
        }
        .padding(Space.l)
        .frame(width: 264, alignment: .topLeading)
        .frame(minHeight: 176, alignment: .topLeading)
        .background(Color.paperRaised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
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

/// The meetings in order: the ones that have been, ticked; the next, marked in ribbon; the rest, waiting.
struct CircleScheduleList: View {
    let circle: ReadingCircle
    let snapshot: CircleSnapshot
    let now: Date

    var body: some View {
        let meetings = CirclePlanner.normalized(circle.meetings, pages: circle.book.pages)
        if meetings.isEmpty {
            Text("No meetings yet. Add a date and everyone gets a page to aim for.")
                .leafStyle(.body, color: .inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                    row(meeting, index: index, previousPage: index > 0 ? meetings[index - 1].throughPage : 0)
                    if index < meetings.count - 1 {
                        Hairline()
                    }
                }
            }
        }
    }

    private func row(_ meeting: CircleMeeting, index: Int, previousPage: Int) -> some View {
        let rowState = state(index)
        return HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            marker(rowState)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(LeafFormat.relativeDay(meeting.date, today: now))
                        .leafStyle(.ui, color: rowState == .past ? Color.inkTertiary : Color.ink)
                    LeaderDots()
                    Text(LeafFormat.pages(from: previousPage + 1, to: meeting.throughPage))
                        .leafStyle(.caption, color: rowState == .past ? Color.inkTertiary : Color.inkSecondary)
                        .monospacedDigit()
                }
                if let place = meeting.place, !place.isEmpty {
                    Text(place)
                        .leafStyle(.caption, color: .inkTertiary)
                }
            }
        }
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(meeting, state: rowState, previousPage: previousPage))
    }

    private enum RowState { case past, next, later }

    private func state(_ index: Int) -> RowState {
        guard let next = snapshot.nextMeetingIndex else { return .past }
        if index < next { return .past }
        return index == next ? .next : .later
    }

    @ViewBuilder
    private func marker(_ state: RowState) -> some View {
        switch state {
        case .past:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.accent)
        case .next:
            Circle()
                .fill(Color.ribbon)
                .frame(width: 9, height: 9)
                .frame(width: 13)
        case .later:
            Circle()
                .strokeBorder(Color.inkFaint, lineWidth: 1)
                .frame(width: 9, height: 9)
                .frame(width: 13)
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
