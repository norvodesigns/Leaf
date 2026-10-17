import SwiftUI

/// The wrap-up after a session is saved (DESIGN.md §6): minutes, pages, the week, and a pace note.
/// Finishing a book plays "The End" instead. No ratings.
struct SessionOutcomeView: View {
    let outcome: SessionOutcome

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var detent: PresentationDetent
    @State private var coverRisen = false
    @State private var titleShown = false
    @State private var ruleDrawn = false
    @State private var detailsShown = false

    init(outcome: SessionOutcome) {
        self.outcome = outcome
        _detent = State(initialValue: outcome.finishedBook ? PresentationDetent.large : PresentationDetent.medium)
    }

    private var book: Book? { store.item(outcome.bookID)?.book }

    var body: some View {
        ScrollView {
            Group {
                if outcome.finishedBook, let book {
                    finishedContent(book: book)
                } else {
                    normalContent
                }
            }
            .leafMargins()
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            PrimaryGlassButton("Done") {
                dismiss()
            }
            .leafMargins()
            .padding(.vertical, Space.m)
        }
        .paperBackground()
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
        .task { await playMoment() }
    }

    // MARK: Normal wrap-up

    private var normalContent: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("Session logged")
            Text(summary)
                .leafStyle(.title)
                .accessibilityAddTraits(.isHeader)
            if let paceLine {
                Text(paceLine)
                    .leafStyle(.pullQuote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(goalLine)
                .leafStyle(.caption)
            SectionHeader("This week", topSpacing: Space.l)
            WeekStrip(days: store.week, streak: store.streak, fillsTodayOnAppear: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "16 pages · 22 min"
    private var summary: String {
        let pages = outcome.session.pagesRead
        let time = LeafFormat.duration(minutes: outcome.session.minutes)
        guard pages > 0 else { return time }
        return "\(pages) \(pages == 1 ? "page" : "pages") · \(time)"
    }

    /// Only when the pace moved by 3% or more.
    private var paceLine: String? {
        guard outcome.oldWPM > 0 else { return nil }
        let change = (outcome.newWPM - outcome.oldWPM) / outcome.oldWPM
        guard abs(change) >= 0.03 else { return nil }
        let wpm = Int(outcome.newWPM.rounded())
        if change > 0 {
            return "You’re reading a little faster: \(wpm) words a minute."
        }
        return "Your pace has settled at \(wpm) words a minute."
    }

    private var goalLine: String {
        let goal = store.preferences.dailyMinutes
        let today = Int(outcome.minutesToday.rounded())
        if outcome.reachedGoalNow {
            return "That’s today’s \(goal) minutes. Anything more is a gift."
        }
        if goal > 0 && today < goal {
            return "\(today) of \(goal) min today"
        }
        return "\(today) min today"
    }

    // MARK: The End

    private func finishedContent(book: Book) -> some View {
        VStack(spacing: Space.l) {
            BookCover(book: book, size: .l)
                .offset(y: coverRisen ? 0 : 36)
                .opacity(coverRisen ? 1 : 0)

            Text("The End")
                .font(.custom(LeafFontName.italic, fixedSize: 72))
                .tracking(-1)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .opacity(titleShown ? 1 : 0)
                .accessibilityLabel("The End. You finished \(book.title).")
                .accessibilityAddTraits(.isHeader)

            EndRule()
                .trim(from: 0, to: ruleDrawn ? 1 : 0)
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 120, height: 2)
                .accessibilityHidden(true)

            VStack(spacing: Space.xl) {
                Text(colophon)
                    .leafStyle(.caption)
                    .multilineTextAlignment(.center)
                nextInOrder
            }
            .opacity(detailsShown ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// "Begun 11 Sept · Finished 16 Oct · 36 days · 11 sessions · 310 pages"
    private var colophon: String {
        let item = store.item(outcome.bookID)
        let calendar = store.calendar
        let begin = item?.startedAt ?? outcome.session.startedAt
        let end = item?.finishedAt ?? outcome.session.startedAt.addingTimeInterval(outcome.session.seconds)
        let span = calendar.dateComponents([.day], from: calendar.startOfDay(for: begin), to: calendar.startOfDay(for: end)).day ?? 0
        let days = max(1, span + 1)
        let sessions = max(1, store.sessionCount(for: outcome.bookID))
        let pages = book?.pages ?? outcome.session.toPage
        let began = LeafFormat.shortDate(begin, today: store.now, calendar: calendar)
        let finished = LeafFormat.shortDate(end, today: store.now, calendar: calendar)
        return "Begun \(began) · Finished \(finished) · \(days) \(days == 1 ? "day" : "days") · \(sessions) \(sessions == 1 ? "session" : "sessions") · \(LeafFormat.number(pages)) pages"
    }

    @ViewBuilder
    private var nextInOrder: some View {
        if let next = store.toRead.first {
            VStack(spacing: Space.s) {
                Eyebrow("Next in the running order")
                HStack(spacing: Space.m) {
                    BookCover(book: next.book, size: .s)
                    Text("\(Text(next.book.title).italic()) \(beginsPhrase(for: next))")
                        .leafStyle(.body)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("That’s the whole stack. Find your next book in Search.")
                .leafStyle(.body, color: .inkSecondary)
                .multilineTextAlignment(.center)
        }
    }

    /// "begins tomorrow."
    private func beginsPhrase(for item: LibraryItem) -> String {
        guard let start = store.plan.book(item.id)?.start else { return "is next." }
        let calendar = store.calendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: store.now), to: calendar.startOfDay(for: start)).day ?? 0
        switch days {
        case ...0: return "begins today."
        case 1: return "begins tomorrow."
        case 2..<7: return "begins \(LeafFormat.format(start, template: "EEEE"))."
        default: return "begins \(LeafFormat.shortDate(start, today: store.now, calendar: calendar))."
        }
    }

    // MARK: Motion and haptics

    /// `theEnd`: the cover rises, the title fades in, the rule draws, `bookFinished` plays, and
    /// `success` follows a second in. Under Reduce Motion everything is simply there.
    private func playMoment() async {
        guard outcome.finishedBook, let book else { return }
        Haptics.shared.play(.bookFinished, heft: Haptics.heft(pages: book.pages))
        if reduceMotion {
            coverRisen = true
            titleShown = true
            ruleDrawn = true
        } else {
            withAnimation(Motion.board) { coverRisen = true }
            withAnimation(Motion.theEndTitle) { titleShown = true }
        }
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        if !reduceMotion {
            withAnimation(Motion.ruleDraw) { ruleDrawn = true }
        }
        try? await Task.sleep(for: .milliseconds(600))
        if Task.isCancelled { return }
        Haptics.shared.success()
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            detailsShown = true
        }
    }
}

/// A straight horizontal line, so `trim` can draw it.
private struct EndRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Previews

private func outcomePreviewStore() -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return store
}

#Preview("Outcome") {
    let session = ReadingSession(
        bookID: DemoData.hobbit.id,
        startedAt: Date().addingTimeInterval(-26 * 60),
        seconds: 26 * 60,
        fromPage: 142,
        toPage: 165
    )
    let outcome = SessionOutcome(
        session: session,
        bookID: DemoData.hobbit.id,
        finishedBook: false,
        reachedGoalNow: true,
        minutesToday: 38,
        oldWPM: 250,
        newWPM: 262
    )
    return Color.paper
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            SessionOutcomeView(outcome: outcome)
        }
        .environment(outcomePreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Outcome · The End") {
    let store = outcomePreviewStore()
    store.move(DemoData.hobbit.id, to: .finished)
    let session = ReadingSession(
        bookID: DemoData.hobbit.id,
        startedAt: Date().addingTimeInterval(-24 * 60),
        seconds: 24 * 60,
        fromPage: 290,
        toPage: 310
    )
    let outcome = SessionOutcome(
        session: session,
        bookID: DemoData.hobbit.id,
        finishedBook: true,
        reachedGoalNow: false,
        minutesToday: 36,
        oldWPM: 262,
        newWPM: 262
    )
    return Color.paper
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            SessionOutcomeView(outcome: outcome)
        }
        .environment(store)
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
