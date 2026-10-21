import SwiftUI

// MARK: - New circle

/// Starting a circle: a book from the shelves, a name, when to meet and how often, and who's in it. The schedule
/// below updates as the dates change, so the pages for each meeting are never a surprise.
struct NewCircleSheet: View {
    let onCreated: (UUID) -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var bookID: String?
    @State private var name = ""
    @State private var startsOn = Date()
    @State private var firstMeeting = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var everyDays = 7
    @State private var count = 4
    @State private var friends: [String] = [""]
    @State private var place = ""
    @State private var didPickDefaults = false

    private static let intervals: [(days: Int, title: String)] = [
        (7, "Every week"), (14, "Every two weeks"), (21, "Every three weeks"), (28, "Every four weeks"),
    ]
    private static let nameSuggestions = ["Book club", "Buddy read", "Tea and chapters", "Long distance"]

    /// Books to read together: what's on the go, then what's waiting, then what's paused.
    private var choices: [LibraryItem] {
        store.reading + store.toRead + store.data.items(on: .paused)
    }

    private var book: Book? { choices.first { $0.id == bookID }?.book }

    private var meetings: [CircleMeeting] {
        guard let book else { return [] }
        return CirclePlanner.schedule(
            pages: book.pages, firstMeeting: firstMeeting, everyDays: everyDays, count: count, calendar: .current, now: store.now
        )
    }

    var body: some View {
        Group {
            if choices.isEmpty {
                EmptyState(
                    title: "Pick a book first.",
                    message: "A circle reads one book together. Add it to Reading or To read, then come back.",
                    actionTitle: "Find a book"
                ) {
                    dismiss()
                    router.tab = .search
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .paperBackground()
            } else {
                form
            }
        }
        .navigationTitle("New circle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") { create() }
                    .disabled(book == nil)
            }
        }
        .onAppear(perform: pickDefaults)
    }

    private var form: some View {
        Form {
            Section {
                Picker("Book", selection: $bookID) {
                    ForEach(choices) { item in
                        Text(item.book.title)
                            .tag(Optional(item.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                header("Book")
            }
            .listRowBackground(Color.paperRaised)

            Section {
                TextField("Name", text: $name, prompt: Text(book.map { "\($0.title) circle" } ?? "Book club"))
                    .font(LeafType.uiBody)
                    .submitLabel(.done)
                ScrollView(.horizontal) {
                    HStack(spacing: Space.s) {
                        ForEach(Self.nameSuggestions, id: \.self) { suggestion in
                            Button {
                                Haptics.shared.selection()
                                name = suggestion
                            } label: {
                                Chip(suggestion, tone: name == suggestion ? .accent : .neutral)
                                    .frame(minHeight: Space.hitTarget)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } header: {
                header("Name")
            }
            .listRowBackground(Color.paperRaised)

            Section {
                DatePicker("Start reading", selection: $startsOn, displayedComponents: .date)
                    .font(LeafType.uiBody)
                DatePicker("First meeting", selection: $firstMeeting, in: startsOn..., displayedComponents: [.date, .hourAndMinute])
                    .font(LeafType.uiBody)
                Stepper(value: $count, in: 1...12) {
                    Text(count == 1 ? "One meeting, at the end" : "\(count) meetings")
                        .leafStyle(.uiBody)
                }
                if count > 1 {
                    Picker("How often", selection: $everyDays) {
                        ForEach(Self.intervals, id: \.days) { interval in
                            Text(interval.title).tag(interval.days)
                        }
                    }
                    .font(LeafType.uiBody)
                }
                TextField("Where (optional)", text: $place, prompt: Text("Where (optional)"))
                    .font(LeafType.uiBody)
                    .submitLabel(.done)
            } header: {
                header("Meetings")
            } footer: {
                schedulePreview
            }
            .listRowBackground(Color.paperRaised)

            Section {
                ForEach(friends.indices, id: \.self) { index in
                    TextField("Name", text: friendBinding(index), prompt: Text(index == 0 ? "A friend’s name" : "Another name"))
                        .font(LeafType.uiBody)
                        .textContentType(.name)
                        .submitLabel(.next)
                        .onSubmit(addRowIfFull)
                }
                Button {
                    Haptics.shared.tap()
                    friends.append("")
                } label: {
                    Label("Add someone", systemImage: "plus")
                        .leafStyle(.uiBody, color: .accent)
                }
            } header: {
                header("Who’s reading")
            } footer: {
                Text("Friends are kept on this iPhone by name. You move their pages along when they tell you.")
                    .leafStyle(.caption)
            }
            .listRowBackground(Color.paperRaised)
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .tint(Color.accent)
        .onChange(of: bookID) { _, _ in suggestCount() }
    }

    private var schedulePreview: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(Array(meetings.prefix(6).enumerated()), id: \.element.id) { index, meeting in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(LeafFormat.relativeDay(meeting.date, today: store.now))
                        .leafStyle(.caption, color: .ink)
                    LeaderDots()
                    Text("to p. \(meeting.throughPage)")
                        .leafStyle(.caption)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
            if meetings.count > 6 {
                Text("and \(meetings.count - 6) more")
                    .leafStyle(.caption, color: .inkTertiary)
            }
            if let minutes = minutesPerDay {
                Text("About \(minutes) minutes a day at your pace.")
                    .leafStyle(.caption)
                    .padding(.top, Space.xs)
            }
        }
        .padding(.top, Space.xs)
    }

    /// What the first stretch asks of the reader, at their pace.
    private var minutesPerDay: Int? {
        guard let book, let first = meetings.first else { return nil }
        let days = max(1, (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startsOn), to: Calendar.current.startOfDay(for: first.date)).day ?? 0))
        let current = choices.first { $0.id == bookID }?.currentPage ?? 0
        let pages = max(0, first.throughPage - current)
        guard pages > 0 else { return nil }
        let minutes = Double(pages) * book.wordsPerPage / max(store.wpm, 1) / Double(days)
        return max(1, Int(minutes.rounded(.up)))
    }

    private func header(_ title: String) -> some View {
        Text(title).leafStyle(.eyebrow)
    }

    private func friendBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { friends.indices.contains(index) ? friends[index] : "" },
            set: { if friends.indices.contains(index) { friends[index] = $0 } }
        )
    }

    private func addRowIfFull() {
        if friends.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { friends.append("") }
    }

    private func pickDefaults() {
        guard !didPickDefaults else { return }
        didPickDefaults = true
        startsOn = store.now
        let evening = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: store.now) ?? store.now
        firstMeeting = Calendar.current.date(byAdding: .day, value: 7, to: evening) ?? evening
        bookID = choices.first?.id
        suggestCount()
    }

    /// About a hundred pages a meeting, between two and six meetings.
    private func suggestCount() {
        guard let book else { return }
        count = min(6, max(2, Int((Double(book.pages) / 100).rounded())))
    }

    private func create() {
        guard let book else { return }
        var planned = meetings
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPlace.isEmpty {
            for index in planned.indices { planned[index].place = trimmedPlace }
        }
        let circle = CircleStore.shared.create(
            name: name, book: book, startsOn: startsOn, meetings: planned, friends: friends, now: store.now
        )
        Haptics.shared.play(.pageTurn)
        onCreated(circle.id)
        dismiss()
    }
}

// MARK: - A member's page

/// Moving someone along: the page as a big numeral over the page ruler, with shortcuts for the meeting's page and
/// the end. The reader's own page belongs to the library, so for them this points to "Where are you?" instead.
struct CircleMemberSheet: View {
    let circleID: UUID
    let memberID: UUID

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    @State private var name = ""
    @State private var didLoad = false
    @State private var confirmsRemove = false

    private var circle: ReadingCircle? { CircleStore.shared.circle(circleID) }
    private var member: CircleMember? { circle?.members.first { $0.id == memberID } }
    private var followsLibrary: Bool { member?.kind == .me && store.item(circle?.book.id ?? "") != nil }

    var body: some View {
        Group {
            if let circle, let member {
                content(circle, member)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .navigationTitle(member?.kind == .me ? "You" : (member?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            if !followsLibrary {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Take \(member?.name ?? "them") out of the circle?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Haptics.shared.warning()
                CircleStore.shared.removeMember(memberID, from: circleID, now: store.now)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func content(_ circle: ReadingCircle, _ member: CircleMember) -> some View {
        let pages = max(1, circle.book.pages)
        let snapshot = CirclePlanner.snapshot(
            for: circle, myPage: store.item(circle.book.id)?.currentPage, wpm: store.wpm, now: store.now, calendar: .current
        )
        ScrollView {
            VStack(spacing: Space.l) {
                if followsLibrary {
                    libraryNote(circle)
                } else {
                    Text("\(page)")
                        .leafStyle(.heroNumeral)
                        .numericBlur(value: Double(page))
                        .accessibilityHidden(true)
                    Text("of \(pages) pages")
                        .leafStyle(.caption)
                    PageScrubber(page: $page, range: 0...pages, estimate: nil)
                    HStack(spacing: Space.s) {
                        if let next = snapshot.nextMeeting {
                            shortcut("Up to p. \(next.throughPage)", page: next.throughPage)
                        }
                        shortcut("Finished", page: pages)
                    }
                    Stepper("Page \(page)", value: $page, in: 0...pages)
                        .font(LeafType.uiBody)
                        .padding(.horizontal, Space.margin)
                }

                if member.kind != .me || !followsLibrary {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow("Name")
                        TextField("Name", text: $name)
                            .font(LeafType.uiBody)
                            .submitLabel(.done)
                            .padding(Space.m)
                            .background(Color.paperSunken, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    }
                    .padding(.horizontal, Space.margin)
                }

                if member.kind != .me {
                    TextButton("Take \(member.name) out of the circle", color: .inkSecondary) {
                        confirmsRemove = true
                    }
                }
            }
            .padding(.vertical, Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .paperBackground()
    }

    private func libraryNote(_ circle: ReadingCircle) -> some View {
        let page = store.item(circle.book.id)?.currentPage ?? 0
        return VStack(spacing: Space.m) {
            Text("p. \(page)")
                .leafStyle(.heroNumeral)
            Text("Your page in the circle follows \(Text(circle.book.title).italic()) in your library, so it moves as you read.")
                .leafStyle(.body, color: .inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.margin)
            SecondaryGlassButton("Change where you are", systemImage: "bookmark", compact: true) {
                let bookID = circle.book.id
                dismiss()
                // The position sheet opens over the tabs once this one has gone.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    router.askPosition(for: bookID)
                }
            }
            .padding(.horizontal, Space.margin)
        }
    }

    private func shortcut(_ title: String, page target: Int) -> some View {
        Button {
            Haptics.shared.selection()
            page = target
        } label: {
            Chip(title, tone: page == target ? .accent : .neutral)
                .frame(minHeight: Space.hitTarget)
        }
        .buttonStyle(.pressable)
    }

    private func load() {
        guard !didLoad, let member else { return }
        didLoad = true
        page = member.page
        name = member.name
    }

    private func save() {
        guard let member else { return }
        if page != member.page {
            Haptics.shared.play(.pageTurn)
            CircleStore.shared.setPage(page, member: memberID, in: circleID, now: store.now)
        }
        if name != member.name {
            CircleStore.shared.renameMember(memberID, to: name, in: circleID, now: store.now)
        }
        dismiss()
    }
}

// MARK: - Adding someone

struct CircleAddFriendSheet: View {
    let circleID: UUID

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Who else is reading?")
                .leafStyle(.title)
            TextField("Name", text: $name, prompt: Text("Their name"))
                .font(LeafType.uiBody)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(add)
                .padding(Space.m)
                .background(Color.paperSunken, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            Text("They start at the beginning. Tap their ring to move them along.")
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.margin)
        .paperBackground()
        .navigationTitle("Add someone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: add)
                    .disabled(trimmed.isEmpty)
            }
        }
        .onAppear { focused = true }
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        Haptics.shared.play(.pageTurn)
        CircleStore.shared.addFriend(trimmed, to: circleID, now: store.now)
        dismiss()
    }
}

// MARK: - Schedule

/// Every meeting's date, page and place, editable, plus adding and removing meetings.
struct CircleScheduleSheet: View {
    let circleID: UUID

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var meetings: [CircleMeeting] = []
    @State private var didLoad = false

    private var circle: ReadingCircle? { CircleStore.shared.circle(circleID) }

    var body: some View {
        let pages = max(1, circle?.book.pages ?? 1)
        Form {
            ForEach(meetings) { meeting in
                let binding = self.binding(for: meeting.id, fallback: meeting)
                Section {
                    DatePicker("Date", selection: binding.date, displayedComponents: [.date, .hourAndMinute])
                        .font(LeafType.uiBody)
                    Stepper(value: binding.throughPage, in: 1...pages, step: 5) {
                        Text("Up to page \(meeting.throughPage)")
                            .leafStyle(.uiBody)
                            .monospacedDigit()
                    }
                    TextField("Where", text: placeBinding(binding), prompt: Text("Where (optional)"))
                        .font(LeafType.uiBody)
                    Button("Remove this meeting", role: .destructive) {
                        Haptics.shared.tap()
                        meetings.removeAll { $0.id == meeting.id }
                    }
                } header: {
                    Text(LeafFormat.format(meeting.date, template: "EEEEMMMd")).leafStyle(.eyebrow)
                }
                .listRowBackground(Color.paperRaised)
            }
            Section {
                Button {
                    Haptics.shared.tap()
                    addMeeting(pages: pages)
                } label: {
                    Label("Add a meeting", systemImage: "plus")
                        .leafStyle(.uiBody, color: .accent)
                }
            } footer: {
                Text("Pages only go forward: a meeting can’t read to an earlier page than the one before it.")
                    .leafStyle(.caption)
            }
            .listRowBackground(Color.paperRaised)
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .tint(Color.accent)
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .onAppear {
            guard !didLoad, let circle else { return }
            didLoad = true
            meetings = CirclePlanner.normalized(circle.meetings, pages: circle.book.pages)
        }
    }

    /// A binding that survives the meeting being removed while the row is still on screen.
    private func binding(for id: UUID, fallback: CircleMeeting) -> Binding<CircleMeeting> {
        Binding(
            get: { meetings.first { $0.id == id } ?? fallback },
            set: { value in
                guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
                meetings[index] = value
            }
        )
    }

    private func placeBinding(_ meeting: Binding<CircleMeeting>) -> Binding<String> {
        Binding(
            get: { meeting.wrappedValue.place ?? "" },
            set: { meeting.wrappedValue.place = $0.isEmpty ? nil : $0 }
        )
    }

    /// A week after the last meeting, reading on by the same stretch (or to the end of the book).
    private func addMeeting(pages: Int) {
        let last = meetings.last
        let date = last.flatMap { Calendar.current.date(byAdding: .day, value: 7, to: $0.date) }
            ?? Calendar.current.date(byAdding: .day, value: 7, to: store.now) ?? store.now
        let stretch = meetings.count > 1 ? (meetings[meetings.count - 1].throughPage - meetings[meetings.count - 2].throughPage) : pages
        let page = min(pages, (last?.throughPage ?? 0) + max(1, stretch))
        meetings.append(CircleMeeting(date: date, throughPage: page, place: last?.place, updatedAt: store.now))
    }

    private func save() {
        guard var circle = circle else { return }
        let now = store.now
        circle.meetings = meetings.map { meeting in
            var meeting = meeting
            if circle.meetings.first(where: { $0.id == meeting.id }) != meeting { meeting.updatedAt = now }
            return meeting
        }
        Haptics.shared.play(.pageTurn)
        CircleStore.shared.update(circle, now: now)
        dismiss()
    }
}
