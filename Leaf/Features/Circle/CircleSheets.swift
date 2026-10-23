import SwiftUI

// MARK: - New circle

/// Starting a circle: a book from the shelves, a name, when everyone means to finish and how often there's a goal on
/// the way, and the reader's name as friends will see it. The goals below update as the dates change, so the page
/// for each is never a surprise. Friends come next, by invitation.
struct NewCircleSheet: View {
    let onCreated: (UUID) -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CircleNameSheet.storageKey) private var myName = ""

    @State private var bookID: String?
    @State private var name = ""
    @State private var startsOn = Date()
    @State private var finishBy = Calendar.current.date(byAdding: .day, value: 28, to: Date()) ?? Date()
    @State private var everyDays = 7
    @State private var place = ""
    @State private var didPickDefaults = false

    private static let lengths: [(weeks: Int, title: String)] = [(2, "2 weeks"), (4, "4 weeks"), (6, "6 weeks"), (8, "8 weeks")]
    private static let cadences: [(days: Int, title: String)] = [(7, "A goal every week"), (14, "Every two weeks"), (0, "Just the finish")]
    private static let nameSuggestions = ["Book club", "Buddy read", "Tea and chapters", "Long distance"]

    /// Books to read together: what's on the go, then what's waiting, then what's paused.
    private var choices: [LibraryItem] {
        store.reading + store.toRead + store.data.items(on: .paused)
    }

    private var chosen: LibraryItem? { choices.first { $0.id == bookID } }
    private var book: Book? { chosen?.book }

    private var goals: [CircleMeeting] {
        guard let book else { return [] }
        return CirclePlanner.goals(
            pages: book.pages, startsOn: startsOn, finishBy: finishBy, everyDays: everyDays, calendar: .current, now: store.now
        )
    }

    var body: some View {
        Group {
            if choices.isEmpty {
                VStack(alignment: .leading, spacing: Canopy.Space.m) {
                    Text("Pick a book first")
                        .canopyText(.headline)
                    Text("A circle reads one book together. Add it to Reading or Up next, then come back.")
                        .canopyText(.callout, color: Canopy.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CanopyGlassButton("Find a book", systemImage: "magnifyingglass", accent: .forest, compact: true) {
                        dismiss()
                        router.tab = .search
                    }
                }
                .canopyCard()
                .padding(Canopy.Space.margin)
                .frame(maxHeight: .infinity, alignment: .top)
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
            .listRowBackground(Canopy.surface.opacity(0.7))

            Section {
                TextField("Name", text: $name, prompt: Text(book.map { "\($0.title) circle" } ?? "Book club"))
                    .canopyText(.body)
                    .submitLabel(.done)
                chips(Self.nameSuggestions, isSelected: { name == $0 }) { name = $0 }
            } header: {
                header("Name")
            }
            .listRowBackground(Canopy.surface.opacity(0.7))

            Section {
                chips(Self.lengths.map(\.title), isSelected: { title in
                    Self.lengths.first { $0.title == title }.map { finishDate(weeks: $0.weeks) == Calendar.current.startOfDay(for: finishBy) } ?? false
                }) { title in
                    guard let weeks = Self.lengths.first(where: { $0.title == title })?.weeks else { return }
                    finishBy = finishTime(on: finishDate(weeks: weeks))
                }
                DatePicker("Start reading", selection: $startsOn, displayedComponents: .date)
                    .canopyText(.body)
                DatePicker("Finish by", selection: $finishBy, in: (Calendar.current.date(byAdding: .day, value: 1, to: startsOn) ?? startsOn)..., displayedComponents: .date)
                    .canopyText(.body)
                Picker("Goals", selection: $everyDays) {
                    ForEach(Self.cadences, id: \.days) { cadence in
                        Text(cadence.title).tag(cadence.days)
                    }
                }
                .canopyText(.body)
                TextField("Where you’ll talk it over (optional)", text: $place, prompt: Text("Where you’ll talk it over (optional)"))
                    .canopyText(.body)
                    .submitLabel(.done)
            } header: {
                header("Goals")
            } footer: {
                goalsPreview
            }
            .listRowBackground(Canopy.surface.opacity(0.7))

            Section {
                TextField("Your name", text: $myName, prompt: Text("Your name"))
                    .canopyText(.body)
                    .textContentType(.givenName)
                    .submitLabel(.done)
            } header: {
                header("You")
            } footer: {
                Text("What friends see beside your page. Next, you’ll send them an invitation; once they join, their pages move as they read.")
                    .canopyText(.caption)
            }
            .listRowBackground(Canopy.surface.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .tint(CanopyAccent.forest.color)
        .onChange(of: startsOn) { _, start in
            if finishBy <= start { finishBy = finishTime(on: Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start) }
        }
    }

    private func chips(_ titles: [String], isSelected: @escaping (String) -> Bool, pick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Canopy.Space.s) {
                ForEach(titles, id: \.self) { title in
                    CanopyChip(title, accent: .bloom, isSelected: isSelected(title)) {
                        pick(title)
                    }
                    .frame(minHeight: Canopy.Space.hitTarget)
                }
            }
            .padding(.vertical, Canopy.Space.xxs)
        }
        .scrollIndicators(.hidden)
    }

    private var goalsPreview: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.xs) {
            ForEach(Array(goals.prefix(6).enumerated()), id: \.element.id) { _, goal in
                HStack(alignment: .firstTextBaseline, spacing: Canopy.Space.s) {
                    Text("Page \(goal.throughPage)")
                        .font(.system(.footnote, design: .rounded, weight: .medium).monospacedDigit())
                        .foregroundStyle(Canopy.textSecondary)
                    Spacer(minLength: Canopy.Space.s)
                    Text("by \(LeafFormat.relativeDay(goal.date, today: store.now))")
                        .canopyText(.caption, color: CanopyAccent.dusk.color)
                }
                .accessibilityElement(children: .combine)
            }
            if goals.count > 6 {
                Text("and \(goals.count - 6) more")
                    .canopyText(.caption)
            }
            if let minutes = minutesPerDay {
                Text("About \(minutes) minutes a day at your pace.")
                    .canopyText(.caption, color: CanopyAccent.forest.color)
                    .padding(.top, Canopy.Space.xs)
            }
        }
        .padding(.top, Canopy.Space.xs)
    }

    /// What finishing on time asks of the reader each day, at their pace, from where they are now.
    private var minutesPerDay: Int? {
        guard let book, let chosen else { return nil }
        let calendar = Calendar.current
        let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: max(startsOn, store.now)), to: calendar.startOfDay(for: finishBy)).day ?? 1)
        let pages = max(0, book.pages - chosen.currentPage)
        guard pages > 0 else { return nil }
        let minutes = Double(pages) * book.wordsPerPage / max(store.wpm, 1) / Double(days)
        return max(1, Int(minutes.rounded(.up)))
    }

    private func header(_ title: String) -> some View {
        Text(title).canopyText(.label, color: CanopyAccent.bloom.color).textCase(nil)
    }

    private func finishDate(weeks: Int) -> Date {
        let calendar = Calendar.current
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: weeks * 7, to: startsOn) ?? startsOn)
    }

    /// Goals fall in the evening, when people read.
    private func finishTime(on day: Date) -> Date {
        Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: day) ?? day
    }

    private func pickDefaults() {
        guard !didPickDefaults else { return }
        didPickDefaults = true
        startsOn = store.now
        bookID = choices.first?.id
        finishBy = finishTime(on: finishDate(weeks: 4))
    }

    private func create() {
        guard let book else { return }
        var planned = goals
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPlace.isEmpty {
            for index in planned.indices { planned[index].place = trimmedPlace }
        }
        let me = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        let circle = store.circleStore.create(
            name: name, book: book, startsOn: startsOn, meetings: planned, myName: me.isEmpty ? "You" : me, now: store.now
        )
        CanopyFeel.play(.planChanged)
        onCreated(circle.id)
        dismiss()
    }
}

// MARK: - The reader's name

/// What friends see the reader as, asked before the first invitation and remembered for the next circle.
struct CircleNameSheet: View {
    let circleID: UUID
    let onDone: () -> Void

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CircleNameSheet.storageKey) private var savedName = ""
    @State private var name = ""
    @FocusState private var focused: Bool

    static let storageKey = "circles.myName"

    /// The reader's member still says "You", which is what everyone else would see too.
    static func needsName(_ circle: ReadingCircle) -> Bool {
        let name = circle.me?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty || name == "You"
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            Text("What should friends call you?")
                .canopyText(.headline)
            TextField("Your name", text: $name, prompt: Text("Your name"))
                .canopyText(.body)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(save)
                .padding(.horizontal, Canopy.Space.l)
                .frame(minHeight: Canopy.Space.hitTarget)
                .canopyGlass(interactive: false, in: RoundedRectangle(cornerRadius: Canopy.Radius.control, style: .continuous))
            Text("It sits beside your page in the circle. You’ll see yourself as “You”.")
                .canopyText(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Canopy.Space.margin)
        .navigationTitle("Your name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Invite", action: save)
                    .disabled(trimmed.isEmpty)
            }
        }
        .onAppear {
            name = savedName
            focused = true
        }
    }

    private func save() {
        guard !trimmed.isEmpty, let me = store.circleStore.circle(circleID)?.me else { return }
        savedName = trimmed
        store.circleStore.renameMember(me.id, to: trimmed, in: circleID, now: store.now)
        CanopyFeel.play(.saved)
        onDone()
        dismiss()
    }
}

// MARK: - Someone in the circle

/// One person: where they are, what they've read lately and the goals they've met. Friends who joined from an
/// invitation move their own pages, so there is nothing to change here; the reader's own page belongs to the
/// library. Only friends added by name, from before invitations, can still be moved by hand.
struct CircleMemberSheet: View {
    let circleID: UUID
    let memberID: UUID

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CircleNameSheet.storageKey) private var savedName = ""

    @State private var page = 0
    @State private var name = ""
    @State private var didLoad = false
    @State private var confirmsRemove = false

    private var circle: ReadingCircle? { store.circleStore.circle(circleID) }
    private var member: CircleMember? { circle?.members.first { $0.id == memberID } }
    /// A friend from before invitations: a name, moved along by hand.
    private var isByName: Bool { member.map { $0.kind == .friend && $0.remoteID == nil } ?? false }
    private var isMe: Bool { member?.kind == .me }

    var body: some View {
        Group {
            if let circle, let member {
                content(circle, member)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .navigationTitle(member?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isByName || isMe ? "Cancel" : "Done") { dismiss() }
            }
            if isByName || isMe {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Take \(member?.name ?? "them") out of the circle?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                CanopyFeel.play(.warning)
                store.circleStore.removeMember(memberID, from: circleID, now: store.now)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func content(_ circle: ReadingCircle, _ member: CircleMember) -> some View {
        let item = store.circleItem(for: circle)
        let myLog = CircleCheckIn.log(from: store.data.sessions, bookID: item?.id ?? circle.book.id)
        let snapshot = CirclePlanner.snapshot(
            for: circle, myPage: item?.currentPage, myLog: myLog, wpm: store.wpm, now: store.now, calendar: .current
        )
        let progress = snapshot.members.first { $0.id == member.id }
        ScrollView {
            VStack(spacing: Canopy.Space.l) {
                CircleFace(member: member, diameter: 72)
                if isByName {
                    pageEditor(circle, snapshot: snapshot)
                } else if let progress {
                    standing(progress, circle: circle, snapshot: snapshot)
                }

                if isMe {
                    if item != nil { libraryNote(circle) }
                    nameField("Your name in the circle", prompt: "Your name")
                } else if isByName {
                    nameField("Name", prompt: "Their name")
                }

                if isByName {
                    Text("Added by name, before invitations. Invite them from the circle and their page moves as they read.")
                        .canopyText(.caption)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Canopy.Space.margin)
                    Button {
                        CanopyFeel.play(.tap)
                        confirmsRemove = true
                    } label: {
                        Text("Take \(member.name) out of the circle")
                            .canopyText(.callout, color: Canopy.textSecondary)
                            .frame(minHeight: Canopy.Space.hitTarget)
                    }
                    .buttonStyle(.plain)
                } else if !isMe {
                    Text("\(member.shortName)’s page moves as they read, on their own phone.")
                        .canopyText(.caption)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Canopy.Space.margin)
                }
            }
            .padding(.vertical, Canopy.Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The big page, and three numbers: today, this week, goals met.
    private func standing(_ progress: CircleMemberProgress, circle: ReadingCircle, snapshot: CircleSnapshot) -> some View {
        VStack(spacing: Canopy.Space.l) {
            VStack(spacing: Canopy.Space.xxs) {
                Text("p. \(progress.page)")
                    .font(.custom(LeafFontName.regular, size: 72, relativeTo: .largeTitle))
                    .foregroundStyle(Canopy.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(placeLine(progress, snapshot: snapshot, pages: circle.book.pages))
                    .canopyText(.caption)
            }
            .accessibilityElement(children: .combine)
            HStack(alignment: .top, spacing: Canopy.Space.cardGap) {
                CanopyStat(value: "\(progress.pagesToday)", unit: "pp.", caption: "Today", accent: .forest)
                CanopyStat(value: "\(progress.pagesThisWeek)", unit: "pp.", caption: "This week")
                CanopyStat(value: "\(progress.goalsMet)", caption: progress.goalsMet == 1 ? "Goal met" : "Goals met", accent: .forest)
            }
            .frame(maxWidth: .infinity)
            .canopyCard()
            .padding(.horizontal, Canopy.Space.margin)
            if let last = progress.lastRead {
                Text("Last read \(LeafFormat.relativeDay(last, today: store.now).lowercased()) at \(LeafFormat.format(last, template: "jmm"))")
                    .canopyText(.caption)
            }
        }
    }

    private func placeLine(_ progress: CircleMemberProgress, snapshot: CircleSnapshot, pages: Int) -> String {
        var parts = ["of \(pages) pages"]
        if snapshot.members.count > 1 {
            let ordinal = NumberFormatter.localizedString(from: NSNumber(value: progress.rank), number: .ordinal)
            parts.append("\(ordinal) in the circle")
        }
        if let goal = snapshot.nextMeeting {
            parts.append(progress.pagesToGoal == 0 ? "at the goal" : "\(progress.pagesToGoal) to page \(goal.throughPage)")
        }
        return parts.joined(separator: " · ")
    }

    private func pageEditor(_ circle: ReadingCircle, snapshot: CircleSnapshot) -> some View {
        let pages = max(1, circle.book.pages)
        return VStack(spacing: Canopy.Space.l) {
            Text("\(page)")
                .font(.custom(LeafFontName.regular, size: 96, relativeTo: .largeTitle))
                .foregroundStyle(Canopy.text)
                .contentTransition(.numericText(value: Double(page)))
                .animation(Canopy.Motion.snappy, value: page)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityHidden(true)
            Text("of \(pages) pages")
                .canopyText(.caption)
            PageScrubber(page: $page, range: 0...pages, estimate: nil)
            HStack(spacing: Canopy.Space.s) {
                if let next = snapshot.nextMeeting {
                    shortcut("Up to p. \(next.throughPage)", page: next.throughPage)
                }
                shortcut("Finished", page: pages)
            }
            Stepper("Page \(page)", value: $page, in: 0...pages)
                .canopyText(.body)
                .padding(.horizontal, Canopy.Space.margin)
        }
    }

    private func nameField(_ title: String, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: Canopy.Space.xs) {
            Text(title)
                .canopyText(.label, color: CanopyAccent.bloom.color)
            TextField(title, text: $name, prompt: Text(prompt))
                .canopyText(.body)
                .submitLabel(.done)
                .padding(.horizontal, Canopy.Space.l)
                .frame(minHeight: Canopy.Space.hitTarget)
                .canopyGlass(interactive: false, in: RoundedRectangle(cornerRadius: Canopy.Radius.control, style: .continuous))
        }
        .padding(.horizontal, Canopy.Space.margin)
    }

    private func libraryNote(_ circle: ReadingCircle) -> some View {
        VStack(spacing: Canopy.Space.m) {
            Text("Your page in the circle follows \(Text(circle.book.title).italic()) in your library, so it moves as you read.")
                .canopyText(.body, color: Canopy.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Canopy.Space.margin)
            CanopyGlassButton("Change where you are", systemImage: "book.pages", accent: .forest, compact: true) {
                let bookID = store.circleItem(for: circle)?.id ?? circle.book.id
                dismiss()
                // The position sheet opens over the tabs once this one has gone.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    router.askPosition(for: bookID)
                }
            }
            .padding(.horizontal, Canopy.Space.margin)
        }
    }

    private func shortcut(_ title: String, page target: Int) -> some View {
        CanopyChip(title, accent: .forest, isSelected: page == target) {
            page = target
        }
        .frame(minHeight: Canopy.Space.hitTarget)
    }

    private func load() {
        guard !didLoad, let member else { return }
        didLoad = true
        page = member.page
        // The reader's member says "You" until they give a name; offer the one they gave another circle.
        name = member.kind == .me && member.name == "You" ? savedName : member.name
    }

    private func save() {
        guard let member else { return }
        if isByName, page != member.page {
            CanopyFeel.play(.pageLogged)
            store.circleStore.setPage(page, member: memberID, in: circleID, now: store.now)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != member.name {
            store.circleStore.renameMember(memberID, to: trimmed, in: circleID, now: store.now)
            if isMe { savedName = trimmed }
        }
        dismiss()
    }
}

// MARK: - Goals

/// Every goal's page, date and place, editable, plus adding and removing goals.
struct CircleScheduleSheet: View {
    let circleID: UUID

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var meetings: [CircleMeeting] = []
    @State private var didLoad = false

    private var circle: ReadingCircle? { store.circleStore.circle(circleID) }

    var body: some View {
        let pages = max(1, circle?.book.pages ?? 1)
        Form {
            ForEach(meetings) { meeting in
                let binding = self.binding(for: meeting.id, fallback: meeting)
                Section {
                    Stepper(value: binding.throughPage, in: 1...pages, step: 5) {
                        Text("Up to page \(meeting.throughPage)")
                            .canopyText(.body)
                            .monospacedDigit()
                    }
                    DatePicker("By", selection: binding.date, displayedComponents: [.date, .hourAndMinute])
                        .canopyText(.body)
                    TextField("Where", text: placeBinding(binding), prompt: Text("Where you’ll talk it over (optional)"))
                        .canopyText(.body)
                    Button("Remove this goal", role: .destructive) {
                        CanopyFeel.play(.tap)
                        meetings.removeAll { $0.id == meeting.id }
                    }
                } header: {
                    Text(LeafFormat.format(meeting.date, template: "EEEEMMMd")).canopyText(.label, color: CanopyAccent.dusk.color).textCase(nil)
                }
                .listRowBackground(Canopy.surface.opacity(0.7))
            }
            Section {
                Button {
                    CanopyFeel.play(.tap)
                    addGoal(pages: pages)
                } label: {
                    Label("Add a goal", systemImage: "plus")
                        .canopyText(.body, color: CanopyAccent.forest.color)
                }
            } footer: {
                Text("Pages only go forward: a goal can’t be an earlier page than the one before it. Everyone in the circle sees the change.")
                    .canopyText(.caption)
            }
            .listRowBackground(Canopy.surface.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .tint(CanopyAccent.forest.color)
        .navigationTitle("Goals")
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

    /// A binding that survives the goal being removed while the row is still on screen.
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

    /// A week after the last goal, reading on by the same stretch (or to the end of the book).
    private func addGoal(pages: Int) {
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
        CanopyFeel.play(.planChanged)
        store.circleStore.update(circle, now: now)
        dismiss()
    }
}
