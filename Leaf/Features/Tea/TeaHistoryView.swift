import SwiftUI

/// What the reader has read with (`TeaHistory`): the tea they read with most, every tea by minutes, the teas each
/// book went with, and their tasting notes.
struct TeaHistoryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router

    private var history: TeaHistory { TeaHistory.build(data: store.data) }

    var body: some View {
        let history = self.history
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if history.isEmpty {
                    empty
                } else {
                    if let first = history.mostReadWith, first.minutes > 0 {
                        mostReadWith(first, history: history)
                    }
                    if !history.teas.isEmpty {
                        teas(history.teas)
                    }
                    if !history.books.isEmpty {
                        books(history.books)
                    }
                    if !history.tastings.isEmpty {
                        tastings(history.tastings)
                    }
                }
            }
            .leafMargins()
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxxl)
        }
        .scrollIndicators(.hidden)
        .paperBackground()
        .navigationTitle("Tea history")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Nothing steeped yet")
                .leafStyle(.title)
            Text("Pour a pot before you read and Leaf keeps the history here: the teas you read with most, the books they went with, and a few words about each cup if you want to write them.")
                .leafStyle(.body, color: .inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Most read with

    private func mostReadWith(_ line: TeaHistory.TeaLine, history: TeaHistory) -> some View {
        let tea = store.tea(id: line.teaID)
        return VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("Most read with")
            HStack(alignment: .center, spacing: Space.l) {
                if let tea {
                    TeaCup(fill: 0.85, liquor: CozyColor.liquor(for: tea), width: 72)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(line.name)
                        .leafStyle(.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(teaDetail(line))
                        .leafStyle(.caption)
                }
            }
            Text(shareLine(history))
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "4 h 10 min over 12 sittings, with 3 books"
    private func teaDetail(_ line: TeaHistory.TeaLine) -> String {
        var parts: [String] = []
        if line.minutes > 0 {
            parts.append("\(LeafFormat.duration(minutes: line.minutes)) over \(line.sessions) \(line.sessions == 1 ? "sitting" : "sittings")")
        }
        if line.books > 0 { parts.append("with \(line.books) \(line.books == 1 ? "book" : "books")") }
        if line.tastings > 0 { parts.append("\(line.tastings) \(line.tastings == 1 ? "note" : "notes")") }
        return parts.joined(separator: ", ")
    }

    private func shareLine(_ history: TeaHistory) -> String {
        let percent = Int((history.teaShare * 100).rounded())
        switch percent {
        case 100: return "Every minute of your reading has had a cup beside it."
        case 0: return "A cup now and then; most of your reading is plain."
        default: return "\(percent)% of your reading has had a cup beside it."
        }
    }

    // MARK: Teas

    private func teas(_ lines: [TeaHistory.TeaLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Your teas", topSpacing: 0)
            ForEach(lines) { line in
                HStack(alignment: .center, spacing: Space.m) {
                    if let tea = store.tea(id: line.teaID) {
                        TeaSwatch(tea: tea, size: 22)
                    } else {
                        Circle().fill(Color.paperSunken).frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(line.name)
                            .leafStyle(.uiBody)
                        Text(teaDetail(line))
                            .leafStyle(.caption)
                    }
                    Spacer(minLength: Space.s)
                    if let average = line.averageRating {
                        TeaLeaves(rating: Int(average.rounded()))
                    }
                }
                .padding(.vertical, Space.s)
                .accessibilityElement(children: .combine)
                if line.id != lines.last?.id {
                    Divider().overlay(Color.hairline)
                }
            }
        }
    }

    // MARK: Books

    private func books(_ lines: [TeaHistory.BookLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Teas per book", topSpacing: 0)
            ForEach(lines.prefix(12)) { line in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(line.title)
                        .leafStyle(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    TeaFlowLayout(spacing: Space.xs) {
                        ForEach(line.teas, id: \.teaID) { share in
                            Chip("\(share.name) · \(LeafFormat.duration(minutes: share.minutes))", tone: share.teaID == line.teas.first?.teaID ? .accent : .neutral)
                        }
                    }
                }
                .padding(.vertical, Space.s)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Tasting notes

    private func tastings(_ notes: [TastingNote]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Tasting notes", topSpacing: 0)
            ForEach(notes.prefix(30)) { note in
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(note.teaName.isEmpty ? "A tea" : note.teaName)
                            .leafStyle(.uiBody)
                        Spacer(minLength: Space.s)
                        Text(LeafFormat.shortDate(note.createdAt, today: store.now, calendar: store.calendar))
                            .leafStyle(.caption)
                    }
                    if !note.summary.isEmpty {
                        Text(note.summary)
                            .leafStyle(.caption)
                    }
                    if let rating = note.rating {
                        TeaLeaves(rating: rating)
                    }
                    if !note.text.isEmpty {
                        Text(note.text)
                            .leafStyle(.body)
                            .italic()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let title = note.bookID.flatMap({ store.item($0)?.book.title }) {
                        Text("With \(title)")
                            .leafStyle(.caption, color: .inkTertiary)
                    }
                }
                .padding(.vertical, Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .contextMenu {
                    Button("Delete note", systemImage: "trash", role: .destructive) {
                        Motion.animate(Motion.paper) { store.deleteTasting(note.id) }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
