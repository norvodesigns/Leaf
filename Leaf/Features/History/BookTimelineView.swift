import SwiftUI

/// A book's whole story (`BookTimeline`): each read-through as a chapter, every sitting a bead on a line with its
/// pages, minutes and tea, and notes, quotes and tasting notes threaded in between. Earlier read-throughs can be rated
/// or taken off, and a read from before Leaf added.
struct BookTimelineView: View {
    let bookID: String

    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var addsEarlierRead = false
    @State private var readToRemove: ReadThrough?

    private var item: LibraryItem? { store.item(bookID) }

    var body: some View {
        ScrollView {
            if let item {
                let timeline = BookTimeline.build(item: item, data: store.data, calendar: store.calendar)
                VStack(alignment: .leading, spacing: Space.xl) {
                    header(item, timeline: timeline)
                    if timeline.chapters.isEmpty {
                        Text("Nothing here yet. Sittings, notes and finishes line up here as you read.")
                            .leafStyle(.body, color: .inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(timeline.chapters) { chapter in
                        chapterView(chapter, item: item)
                    }
                    TextButton("Add a read from before Leaf", color: .accent) {
                        Haptics.shared.tap()
                        addsEarlierRead = true
                    }
                    .padding(.top, Space.s)
                }
                .leafMargins()
                .padding(.top, Space.l)
                .padding(.bottom, Space.xxxl)
            }
        }
        .scrollIndicators(.hidden)
        .paperBackground()
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addsEarlierRead) {
            EarlierReadSheet(bookID: bookID)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Take this read off?", isPresented: removalBinding, titleVisibility: .visible, presenting: readToRemove) { read in
            Button("Take it off", role: .destructive) {
                withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                    store.removeRead(bookID, readID: read.id)
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: { read in
            Text("The finish on \(LeafFormat.format(read.finishedAt, template: "dMMMyyyy", calendar: store.calendar)) leaves this book’s history and your counts. Sittings stay.")
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { readToRemove != nil }, set: { if !$0 { readToRemove = nil } })
    }

    // MARK: Header

    private func header(_ item: LibraryItem, timeline: BookTimeline) -> some View {
        HStack(alignment: .top, spacing: Space.l) {
            BookCover(book: item.book, size: .s)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(item.book.title)
                    .leafStyle(.title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.book.author)
                    .leafStyle(.author)
                Text(summary(item, timeline: timeline))
                    .leafStyle(.caption)
                    .padding(.top, Space.xxs)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Finished twice · 9 h 12 min over 31 sittings"
    private func summary(_ item: LibraryItem, timeline: BookTimeline) -> String {
        let minutes = timeline.chapters.reduce(0) { $0 + $1.minutes }
        let sittings = timeline.chapters.reduce(0) { $0 + $1.sittings }
        var parts: [String] = []
        switch timeline.timesFinished {
        case 0: break
        case 1: parts.append("Finished once")
        case 2: parts.append("Finished twice")
        default: parts.append("Finished \(timeline.timesFinished) times")
        }
        if sittings > 0 {
            parts.append("\(LeafFormat.duration(minutes: minutes)) over \(sittings) \(sittings == 1 ? "sitting" : "sittings")")
        }
        return parts.isEmpty ? "Not begun yet" : parts.joined(separator: " · ")
    }

    // MARK: Chapters

    private func chapterView(_ chapter: BookTimeline.Chapter, item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(chapter.title)
                    .leafStyle(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s)
                if let read = chapter.read {
                    Menu {
                        Section("Rate this read") {
                            ForEach((1...5).reversed(), id: \.self) { value in
                                Button(value == 1 ? "1 leaf" : "\(value) leaves") {
                                    Haptics.shared.selection()
                                    store.setReadRating(bookID, readID: read.id, rating: value)
                                }
                            }
                        }
                        if item.reads.contains(where: { $0.id == read.id }) {
                            Button("Take this read off", systemImage: "trash", role: .destructive) {
                                readToRemove = read
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.inkSecondary)
                            .frame(minWidth: Space.hitTarget, minHeight: Space.hitTarget)
                    }
                    .accessibilityLabel("\(chapter.title) options")
                }
            }
            Text(chapterLine(chapter))
                .leafStyle(.caption)
                .padding(.bottom, Space.m)
            ForEach(Array(chapter.beads.enumerated()), id: \.element.id) { index, bead in
                BeadRow(bead: bead, isFirst: index == 0, isLast: index == chapter.beads.count - 1, calendar: store.calendar)
            }
        }
        .padding(Space.l)
        .background(Color.paperRaised, in: Radius.shape(Radius.card))
        .overlay {
            Radius.shape(Radius.card).strokeBorder(Color.hairline, lineWidth: 0.5)
        }
    }

    /// "11 Sept 2024 to 2 Oct 2024 · 22 days · 4 h 10 min"
    private func chapterLine(_ chapter: BookTimeline.Chapter) -> String {
        let calendar = store.calendar
        var parts: [String] = []
        let start = chapter.startedAt.map { LeafFormat.format($0, template: "dMMMyyyy", calendar: calendar) }
        let end = chapter.finishedAt.map { LeafFormat.format($0, template: "dMMMyyyy", calendar: calendar) }
        switch (start, end) {
        case let (start?, end?): parts.append("\(start) to \(end)")
        case let (start?, nil): parts.append(chapter.isCurrent ? "Since \(start)" : start)
        case let (nil, end?): parts.append("Finished \(end)")
        case (nil, nil): break
        }
        if let days = chapter.read?.days(calendar: calendar) { parts.append(days == 1 ? "in a day" : "\(days) days") }
        if chapter.minutes > 0 { parts.append(LeafFormat.duration(minutes: chapter.minutes)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - A bead

/// One moment on the line: a dot (bigger for a start or a finish), the line through it, and what happened.
private struct BeadRow: View {
    let bead: BookTimeline.Bead
    let isFirst: Bool
    let isLast: Bool
    let calendar: Calendar

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            line
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(LeafFormat.format(bead.date, template: "EEEdMMM", calendar: calendar))
                    .leafStyle(.caption, color: .inkTertiary)
                content
            }
            .padding(.bottom, isLast ? 0 : Space.m)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var isMilestone: Bool {
        switch bead.kind {
        case .started, .finished, .setAside: return true
        default: return false
        }
    }

    private var dotColor: Color {
        switch bead.kind {
        case .finished: return .accent
        case .setAside: return .inkTertiary
        case .quote, .note: return .ribbon
        case .tasting: return .chai
        default: return .ink
        }
    }

    private var line: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : Color.hairline)
                .frame(width: 1.5, height: 6)
            Circle()
                .fill(dotColor)
                .frame(width: isMilestone ? 12 : 8, height: isMilestone ? 12 : 8)
            Rectangle()
                .fill(isLast ? Color.clear : Color.hairline)
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch bead.kind {
        case .started:
            Text("Began").leafStyle(.uiBody)
        case .sitting(let minutes, let from, let to, let tea, let isTyped):
            Text(sittingLine(minutes: minutes, from: from, to: to))
                .leafStyle(.data)
            if tea != nil || isTyped {
                Text(sittingExtras(tea: tea, isTyped: isTyped))
                    .leafStyle(.caption)
            }
        case .note(let text, let page, _):
            Text(text)
                .leafStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
            if let page { Text("Note · p. \(page)").leafStyle(.caption) }
        case .quote(let text, let page, _):
            Text("“\(text)”")
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
            if let page { Text("p. \(page)").leafStyle(.caption) }
        case .tasting(let teaName, let summary, let rating):
            Text(summary.isEmpty ? teaName : "\(teaName) · \(summary)")
                .leafStyle(.caption, color: .ink)
            if let rating { TeaLeaves(rating: rating) }
        case .finished(let rating, let days):
            Text(days.map { $0 == 1 ? "Finished, in a day" : "Finished, in \($0) days" } ?? "Finished")
                .leafStyle(.uiBody, color: .accent)
            if let rating { TeaLeaves(rating: rating) }
        case .setAside:
            Text("Set aside").leafStyle(.uiBody, color: .inkSecondary)
        }
    }

    /// "With Earl Grey · Typed in"
    private func sittingExtras(tea: String?, isTyped: Bool) -> String {
        var parts: [String] = []
        if let tea { parts.append("With \(tea)") }
        if isTyped { parts.append("Typed in") }
        return parts.joined(separator: " · ")
    }

    private func sittingLine(minutes: Double, from: Int, to: Int) -> String {
        let time = LeafFormat.duration(minutes: minutes)
        guard to > from else { return time }
        return "\(time) · \(LeafFormat.pages(from: from + 1, to: to))"
    }
}

// MARK: - A read from before Leaf

/// "I read this before": when it was finished (and, if remembered, begun), and how it was.
struct EarlierReadSheet: View {
    let bookID: String

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var finished = Date()
    @State private var knowsStart = false
    @State private var started = Date()
    @State private var rating: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Finished", selection: $finished, in: ...Date(), displayedComponents: .date)
                        .leafStyle(.uiBody)
                    Toggle(isOn: $knowsStart) {
                        Text("I remember when I began").leafStyle(.uiBody)
                    }
                    if knowsStart {
                        DatePicker("Began", selection: $started, in: ...finished, displayedComponents: .date)
                            .leafStyle(.uiBody)
                    }
                    HStack {
                        Text("How it was").leafStyle(.uiBody)
                        Spacer(minLength: Space.s)
                        TeaLeafRating(rating: $rating)
                    }
                } footer: {
                    Text("It counts in your year as a finished book and joins this book’s timeline.")
                        .leafStyle(.caption)
                }
                .settingsRows()
            }
            .scrollContentBackground(.hidden)
            .paperBackground()
            .foregroundStyle(Color.ink)
            .tint(Color.accent)
            .navigationTitle("A read from before")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        Haptics.shared.success()
                        let calendar = store.calendar
                        let finishDay = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: finished) ?? finished
                        let startDay = knowsStart ? calendar.date(bySettingHour: 12, minute: 0, second: 0, of: started) : nil
                        store.addEarlierRead(bookID, startedAt: startDay, finishedAt: finishDay, rating: rating)
                        dismiss()
                    }
                }
            }
        }
        .presentationBackground(Color.paper)
    }
}
