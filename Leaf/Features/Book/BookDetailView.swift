import SwiftUI

/// A book's page (DESIGN.md §6): a tinted stage with the cover XL, the title and author, three facts,
/// where the book stands on its shelf, what to do next, and its reading sessions. It works whether
/// or not the book is in the library: it reads the live `LibraryItem` when there is one and falls
/// back to the `Book` it was opened with (search results).
struct BookDetailView: View {
    let book: Book

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    /// The cover scan's average colour, once it has loaded.
    @State private var stageColor: Color?
    @State private var showsPageSheet = false
    @State private var showsPagesEditor = false
    @State private var confirmsRemoval = false
    @State private var showsAllSessions = false

    init(book: Book) {
        self.book = book
    }

    // MARK: State

    private var item: LibraryItem? { store.item(book.id) }
    /// The library's copy wins, so an edited page count shows straight away.
    private var shown: Book { item?.book ?? book }
    private var shelf: Shelf? { item?.shelf }
    private var planned: PlannedBook? { store.plan.book(book.id) }
    private var isSessionLive: Bool { store.activeSession != nil }
    private var zoomSourceID: String { "book-\(book.id)" }
    private var coverURL: URL? { BookCover.imageURL(for: shown, size: .xl) }

    /// The minutes still to read: what is left for a book underway, else the whole book.
    private var minutesToRead: Double {
        if let item, item.shelf == .reading { return item.minutesLeft(atWPM: store.wpm) }
        return shown.minutes(atWPM: store.wpm)
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                stage
                VStack(spacing: Space.xl) {
                    header
                    facts
                    status
                    actions
                    sessions
                }
                .leafMargins()
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxxl)
            }
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .task(id: coverURL) {
            await loadStageColor()
        }
        .sheet(isPresented: $showsPageSheet) {
            if let item {
                BookPageSheet(book: item.book, page: item.currentPage) { page in
                    savePage(page)
                }
            }
        }
        .sheet(isPresented: $showsPagesEditor) {
            if let item {
                BookPagesSheet(book: item.book) { pages in
                    store.updateBook(item.id, pages: pages)
                    Haptics.shared.success()
                }
            }
        }
        .confirmationDialog(
            "Remove from Library?",
            isPresented: $confirmsRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                LibraryShelfActions.remove(book.id, store: store)
                dismiss()
            }
        } message: {
            Text("“\(shown.title)” will leave your shelves and your plan.")
        }
    }

    // MARK: Stage

    private var stage: some View {
        BookCover(book: shown, size: .xl, ribbon: shelf == .reading)
            .padding(.bottom, shelf == .reading ? BookCover.Size.xl.ribbonTail : 0)
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .background {
                stageTint
                    .backgroundExtensionEffect()
            }
    }

    /// The cover's colour at 18% over paper (the palette colour while a scan loads, or for a generated cover).
    private var stageTint: some View {
        let wash: Color = stageColor ?? CoverPalette(book: shown).background
        return ZStack {
            Color.paper
            wash.opacity(0.18)
        }
        .animation(Motion.coverFade, value: stageColor)
    }

    private func loadStageColor() async {
        guard let url = coverURL else {
            stageColor = nil
            return
        }
        if let cached = CoverImageCache.shared.cachedImage(for: url) {
            stageColor = BookStageTint.average(of: cached)
            return
        }
        guard let image = await CoverImageCache.shared.image(for: url) else { return }
        stageColor = BookStageTint.average(of: image)
    }

    // MARK: Header and facts

    private var header: some View {
        VStack(spacing: Space.s) {
            if let eyebrow = eyebrowText {
                Eyebrow(eyebrow)
            }
            Text(shown.title)
                .leafStyle(.masthead)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(shown.author)
                .leafStyle(.author)
                .multilineTextAlignment(.center)
            if !shown.genres.isEmpty {
                BookChipFlow {
                    ForEach(Array(shown.genres.prefix(5)), id: \.self) { genre in
                        Chip(Self.prettyGenre(genre))
                    }
                }
                .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "Fiction · 1937"
    private var eyebrowText: String? {
        var parts: [String] = []
        if let genre = shown.genres.first { parts.append(Self.prettyGenre(genre)) }
        if let year = shown.year { parts.append(String(year)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var facts: some View {
        VStack(spacing: Space.m) {
            StatTileRow {
                StatTile(value: LeafFormat.number(shown.pages), label: "Pages")
                StatTile(value: Self.compactCount(shown.words), label: "Words")
                StatTile(value: Self.tileDuration(shown.minutes(atWPM: store.wpm)), label: "At your pace")
            }
            if shelf != .finished {
                Text(paceSentence)
                    .leafStyle(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// "3 h 40 min left at 262 words a minute, about 9 reading days at 25 min a day."
    private var paceSentence: String {
        let hasProgress = shelf == .reading && (item?.currentPage ?? 0) > 0
        let wpm = Int(store.wpm.rounded())
        var text = "\(LeafFormat.duration(minutes: minutesToRead)) \(hasProgress ? "left" : "to read") at \(wpm) words a minute"
        let daily = store.preferences.dailyMinutes
        if daily > 0 {
            let days = max(1, Int((minutesToRead / Double(daily)).rounded(.up)))
            text += ", about \(days) reading \(days == 1 ? "day" : "days") at \(daily) min a day"
        }
        return text + "."
    }

    // MARK: Status by shelf

    @ViewBuilder
    private var status: some View {
        switch shelf {
        case .reading?:
            if let item { readingStatus(item) }
        case .toRead?:
            toReadStatus
        case .finished?:
            if let item { finishedStatus(item) }
        case nil:
            notInLibraryStatus
        }
    }

    private func readingStatus(_ item: LibraryItem) -> some View {
        let todayTo = store.plan.today?.assignments.first { $0.bookID == item.id }?.toPage ?? item.currentPage
        return VStack(alignment: .leading, spacing: Space.m) {
            PageSpanBar(current: item.currentPage, todayTo: todayTo, total: item.book.pages)
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(pageCaption(item))
                    .leafStyle(.caption)
                Spacer(minLength: Space.m)
                TextButton("Update page") {
                    Haptics.shared.tap()
                    showsPageSheet = true
                }
            }
            if let finish = planned?.finish {
                Text("You’ll finish on \(dayLong(finish)).")
                    .leafStyle(.pullQuote)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(noDateSentence)
                    .leafStyle(.pullQuote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toReadStatus: some View {
        Text(toReadSentence)
            .leafStyle(.pullQuote)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private func finishedStatus(_ item: LibraryItem) -> some View {
        VStack(spacing: Space.m) {
            Text(finishedLine(item))
                .leafStyle(.data)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            VStack(spacing: Space.xs) {
                Eyebrow("Your rating")
                ratingRow(current: item.rating)
            }
        }
    }

    private var notInLibraryStatus: some View {
        Text(notInLibrarySentence)
            .leafStyle(.pullQuote)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private func ratingRow(current: Int?) -> some View {
        let rating = current ?? 0
        return HStack(spacing: Space.xs) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    Haptics.shared.selection()
                    store.setRating(book.id, rating: current == value ? nil : value)
                } label: {
                    Image(systemName: rating >= value ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(rating >= value ? Color.ink : Color.inkTertiary)
                        .frame(width: 40, height: Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value == 1 ? "1 star" : "\(value) stars")
                .accessibilityAddTraits(current == value ? .isSelected : [])
            }
        }
    }

    // MARK: Sentences

    private func pageCaption(_ item: LibraryItem) -> String {
        if item.currentPage > 0 {
            return "p. \(LeafFormat.number(item.currentPage)) of \(LeafFormat.number(item.book.pages))"
        }
        return "Not begun · \(LeafFormat.number(item.book.pages)) pages"
    }

    /// "Starts Mon 27 Oct, done by 3 Dec."
    private var toReadSentence: String {
        guard let planned else { return noDateSentence }
        let days = LibraryDates.days(from: store.now, to: planned.start, calendar: store.calendar)
        let starts: String
        switch days {
        case ...0: starts = "Starts today"
        case 1: starts = "Starts tomorrow"
        default: starts = "Starts \(dayShort(planned.start))"
        }
        guard let finish = planned.finish else { return starts + "." }
        return "\(starts), done by \(LibraryDates.day(finish, now: store.now, calendar: store.calendar))."
    }

    /// "If you start today, you’d finish around Sun 26 Oct."
    private var notInLibrarySentence: String {
        guard let finish = estimatedFinish(minutes: minutesToRead) else { return noDateSentence }
        return "If you start today, you’d finish around \(dayShort(finish))."
    }

    private var noDateSentence: String {
        if store.preferences.dailyMinutes <= 0 || store.preferences.readingDays.isEmpty {
            return "Set a daily time in Settings and Leaf will pick the dates."
        }
        return "Too far off for a date yet."
    }

    /// "Finished 15 Oct 2026 · 34 days · 11 sessions"
    private func finishedLine(_ item: LibraryItem) -> String {
        let calendar = store.calendar
        var parts: [String] = []
        if let finished = item.finishedAt {
            parts.append("Finished \(LibraryDates.dayWithYear(finished, calendar: calendar))")
            if let started = item.startedAt {
                let days = max(1, LibraryDates.days(from: started, to: finished, calendar: calendar) + 1)
                parts.append(days == 1 ? "1 day" : "\(days) days")
            }
        } else {
            parts.append("Finished")
        }
        let count = store.sessionCount(for: item.id)
        if count > 0 {
            parts.append(count == 1 ? "1 session" : "\(count) sessions")
        }
        return parts.joined(separator: " · ")
    }

    /// The day the book would be done if it were started today, spending the daily minutes on reading days.
    private func estimatedFinish(minutes: Double) -> Date? {
        let daily = Double(store.preferences.dailyMinutes)
        let readingDays = store.preferences.readingDays
        guard daily > 0, !readingDays.isEmpty else { return nil }
        let calendar = store.calendar
        let start = calendar.startOfDay(for: store.now)
        var remaining = minutes
        for offset in 0..<3650 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            guard readingDays.contains(calendar.component(.weekday, from: day)) else { continue }
            remaining -= daily
            if remaining <= 0 { return day }
        }
        return nil
    }

    private func dayLong(_ date: Date) -> String {
        LeafFormat.format(date, template: "EEEEdMMMM", calendar: store.calendar)
    }

    private func dayShort(_ date: Date) -> String {
        LeafFormat.format(date, template: "EEEdMMM", calendar: store.calendar)
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch shelf {
        case nil:
            GlassEffectContainer(spacing: Space.m) {
                VStack(spacing: Space.m) {
                    PrimaryGlassButton(isSessionLive ? "Return to session" : "Start reading", systemImage: "play.fill") {
                        startReadingNow()
                    }
                    .sessionZoomSource(zoomSourceID)
                    SecondaryGlassButton("Add to To read", systemImage: "plus") {
                        addToQueue()
                    }
                }
            }
        case .toRead?:
            SecondaryGlassButton(isSessionLive ? "Return to session" : "Start reading now", systemImage: "play.fill") {
                startReadingNow()
            }
            .sessionZoomSource(zoomSourceID)
        case .reading?:
            GlassEffectContainer(spacing: Space.m) {
                VStack(spacing: Space.m) {
                    PrimaryGlassButton(isSessionLive ? "Return to session" : "Start reading", systemImage: "play.fill") {
                        startReadingNow()
                    }
                    .sessionZoomSource(zoomSourceID)
                    SecondaryGlassButton("Mark finished", systemImage: "checkmark", compact: true, playsHaptic: false) {
                        markFinished()
                    }
                }
            }
        case .finished?:
            EmptyView()
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        switch shelf {
        case nil:
            Button {
                addToReading()
            } label: {
                Label("Add to Reading", systemImage: "book")
            }
            Button {
                addToQueue()
            } label: {
                Label("Add to To read", systemImage: "bookmark")
            }
            Button {
                markFinished()
            } label: {
                Label("Mark finished", systemImage: "checkmark.circle")
            }
        case .reading?:
            Button {
                markFinished()
            } label: {
                Label("Mark finished", systemImage: "checkmark.circle")
            }
            Button {
                LibraryShelfActions.move(book.id, to: .toRead, store: store)
            } label: {
                Label("Move to To read", systemImage: "bookmark")
            }
        case .toRead?:
            if store.toRead.first?.id != book.id {
                Button {
                    moveToFront()
                } label: {
                    Label("Move to front", systemImage: "arrow.up.to.line")
                }
            }
            Button {
                LibraryShelfActions.move(book.id, to: .reading, store: store)
            } label: {
                Label("Move to Reading", systemImage: "book")
            }
            Button {
                markFinished()
            } label: {
                Label("Mark finished", systemImage: "checkmark.circle")
            }
        case .finished?:
            Button {
                LibraryShelfActions.move(book.id, to: .reading, store: store)
            } label: {
                Label("Read again", systemImage: "book")
            }
            Button {
                LibraryShelfActions.move(book.id, to: .toRead, store: store)
            } label: {
                Label("Move to To read", systemImage: "bookmark")
            }
        }
        if shelf != nil {
            Divider()
            Button {
                showsPagesEditor = true
            } label: {
                Label("Edit page count", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmsRemoval = true
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
    }

    /// "Start reading": adds the book to Reading if needed, then opens the timer.
    private func startReadingNow() {
        if !isSessionLive, item == nil {
            store.add(shown, to: .reading)
        }
        ReadingSessionLauncher.start(bookID: book.id, store: store, router: router, from: zoomSourceID)
    }

    private func addToQueue() {
        Motion.animate(Motion.paper) { store.add(shown, to: .toRead) }
        Haptics.shared.success()
    }

    private func addToReading() {
        Motion.animate(Motion.paper) { store.add(shown, to: .reading) }
        Haptics.shared.success()
    }

    private func moveToFront() {
        Motion.animate(Motion.paper) { store.moveToFront(book.id) }
        Haptics.shared.play(.reorderDrop, heft: Haptics.heft(pages: shown.pages))
    }

    private func markFinished() {
        LibraryShelfActions.markFinished(shown, store: store)
    }

    /// A page set by hand. Reaching the last page finishes the book.
    private func savePage(_ page: Int) {
        guard let item else { return }
        if page >= item.book.pages {
            LibraryShelfActions.markFinished(item.book, store: store)
        } else {
            store.setPage(item.id, page: page)
            Haptics.shared.play(.pageTurn)
        }
    }

    // MARK: Sessions

    private static let collapsedSessionCount = 6

    @ViewBuilder
    private var sessions: some View {
        let all = store.sessions(for: book.id)
        if !all.isEmpty {
            let visible = showsAllSessions ? all : Array(all.prefix(Self.collapsedSessionCount))
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Sessions", topSpacing: Space.s)
                ForEach(visible) { session in
                    Text(sessionLine(session))
                        .leafStyle(.data)
                        .frame(maxWidth: .infinity, minHeight: Space.hitTarget, alignment: .leading)
                        .overlay(alignment: .bottom) { Hairline() }
                }
                if all.count > Self.collapsedSessionCount {
                    TextButton(showsAllSessions ? "Show fewer" : "Show all \(all.count)") {
                        withAnimation(Motion.paper) { showsAllSessions.toggle() }
                    }
                    .padding(.top, Space.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Tue 14 Oct · 23 min · pp. 142–158"
    private func sessionLine(_ session: ReadingSession) -> String {
        var parts = [
            dayShort(session.startedAt),
            LeafFormat.duration(minutes: session.minutes),
        ]
        if session.toPage > session.fromPage {
            parts.append(LeafFormat.pages(from: session.fromPage + 1, to: session.toPage))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Formatting

    /// "science-fiction" becomes "Science fiction".
    private static func prettyGenre(_ genre: String) -> String {
        let spaced = genre.replacingOccurrences(of: "-", with: " ")
        guard let first = spaced.first else { return spaced }
        return String(first).uppercased() + String(spaced.dropFirst())
    }

    /// "95K", "1.3M"
    private static func compactCount(_ value: Int) -> String {
        switch value {
        case ..<1_000:
            return String(value)
        case ..<10_000:
            return (Double(value) / 1_000).formatted(.number.precision(.fractionLength(0...1))) + "K"
        case ..<1_000_000:
            return String(Int((Double(value) / 1_000).rounded())) + "K"
        default:
            return (Double(value) / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "M"
        }
    }

    /// "6 h 22 m", "45 min": the stat tile's numeral.
    private static func tileDuration(_ minutes: Double) -> String {
        let total = max(1, Int(minutes.rounded()))
        if total < 60 { return "\(total) min" }
        let hours = total / 60
        let rest = total % 60
        if hours >= 100 || rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) m"
    }
}

// MARK: - Previews

private struct BookDetailPreview: View {
    let book: Book

    var body: some View {
        NavigationStack {
            BookDetailView(book: book)
        }
    }
}

@MainActor
private func bookPreviewStore() -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return store
}

#Preview("Book · Reading") {
    BookDetailPreview(book: DemoData.hobbit)
        .environment(bookPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Book · To read") {
    BookDetailPreview(book: DemoData.piranesi)
        .environment(bookPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Book · Finished") {
    BookDetailPreview(book: DemoData.klara)
        .environment(bookPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Book · Not in library") {
    let dune = DemoData.book("OL893415W", "Dune", "Frank Herbert", 1965, pages: 612, words: 187_000, cover: nil, genres: ["science-fiction", "classics"])
    return BookDetailPreview(book: dune)
        .environment(bookPreviewStore())
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
