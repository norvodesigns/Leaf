import SwiftUI

// MARK: - Year in Books

/// The year, wrapped and cozy (NEXT.md section 10): books, pages, hours and cups, the longest streak and the favourite
/// hour, the months as a collage of tea rings, the highlights, and every book finished. Shares as an image.
struct YearInBooksView: View {
    let summary: YearInBooks

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var poster: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("\(String(summary.year)) in books")
                    Text(YearInBooksText.title(summary))
                        .leafStyle(.display)
                        .padding(.top, Space.s)
                    Text(YearInBooksText.headline(summary))
                        .leafStyle(.pullQuote)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.s)
                        .accessibilityLabel(YearInBooksText.summary(summary))

                    SectionHeader("The year in rings")
                    MonthRingCollage(months: summary.months, ringSize: 50, showsLabels: true)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(YearInBooksText.monthsSentence(summary, calendar: store.calendar))
                        .accessibilityValue(YearInBooksText.monthByMonth(summary, calendar: store.calendar))

                    SectionHeader("Habits")
                    StatTileRow {
                        StatTile(value: "\(summary.longestStreak)", label: summary.longestStreak == 1 ? "Day streak" : "Days in a row")
                        StatTile(value: "\(summary.daysRead)", label: "Days read")
                        StatTile(value: summary.favouriteHour.map { BestTimeOfDay.hourLabel($0) } ?? "—", label: "Favourite hour")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(YearInBooksText.habitsSentence(summary))

                    highlights

                    if !summary.finishedBooks.isEmpty {
                        SectionHeader("Finished")
                        VStack(spacing: 0) {
                            ForEach(summary.finishedBooks) { book in
                                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                                    Text(book.title)
                                        .leafStyle(.headline)
                                        .lineLimit(1)
                                    LeaderDots()
                                    Text(LeafFormat.format(book.finishedAt, template: "MMMd", calendar: store.calendar))
                                        .leafStyle(.data)
                                }
                                .padding(.vertical, Space.xs)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(book.title) by \(book.author), finished \(LeafFormat.format(book.finishedAt, template: "MMMMd", calendar: store.calendar))")
                            }
                        }
                    }

                    if summary.quotesSaved + summary.notesSaved > 0 {
                        Text(YearInBooksText.journalSentence(summary))
                            .leafStyle(.caption)
                            .padding(.top, Space.xl)
                    }
                }
                .leafMargins()
                .padding(.top, Space.m)
                .padding(.bottom, Space.section)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let poster {
                        ShareLink(
                            item: Image(uiImage: poster),
                            preview: SharePreview("\(String(summary.year)) in books", image: Image(uiImage: poster))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share your year")
                    }
                }
            }
        }
        .task(id: summary) {
            poster = SharePoster.render(YearInBooksPoster(summary: summary, calendar: store.calendar), size: YearInBooksPoster.size)
        }
    }

    @ViewBuilder
    private var highlights: some View {
        let rows = YearInBooksText.highlights(summary)
        if !rows.isEmpty {
            SectionHeader("Highlights")
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(rows, id: \.label) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(row.label)
                        Text(row.value)
                            .leafStyle(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = row.detail {
                            Text(detail).leafStyle(.caption)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// The months as tea rings, four to a row, each sized by how much was read (`MonthRing.ring`), with a gold drop per
/// book finished.
struct MonthRingCollage: View {
    let months: [YearInBooks.MonthRing]
    var ringSize: CGFloat = 40
    var showsLabels = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 4), spacing: showsLabels ? Space.m : Space.xs) {
            ForEach(months) { month in
                VStack(spacing: Space.xs) {
                    ring(month)
                        .frame(width: ringSize, height: ringSize)
                    if showsLabels {
                        Text(Self.initial(month.month))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.inkTertiary)
                    }
                }
            }
        }
    }

    private func ring(_ month: YearInBooks.MonthRing) -> some View {
        let scale = month.minutes > 0 ? max(0.3, min(1, month.ring)) : 0.12
        return ZStack {
            Circle()
                .fill(Color.chai.opacity(month.minutes > 0 ? 0.12 + 0.2 * min(1, month.ring) : 0))
            Circle()
                .strokeBorder(month.minutes > 0 ? Color.chai.opacity(0.8) : Color.inkFaint, lineWidth: month.ring >= 1 ? 1.6 : 1)
            if month.booksFinished > 0 {
                HStack(spacing: 2) {
                    ForEach(0..<min(month.booksFinished, 4), id: \.self) { _ in
                        Circle().fill(Color.amber).frame(width: 4, height: 4)
                    }
                }
            }
        }
        .scaleEffect(scale)
    }

    static func initial(_ month: Int) -> String {
        let symbols = Calendar.current.veryShortMonthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : ""
    }
}

/// The words for the Year in Books, shared by the screen, its card and its poster.
enum YearInBooksText {
    struct Highlight {
        let label: String
        let value: String
        let detail: String?
    }

    /// "14 books.", "One book.", or, before the first finish, "Still reading."
    static func title(_ summary: YearInBooks) -> String {
        switch summary.booksFinished {
        case 0: "Still reading."
        case 1: "One book."
        default: "\(summary.booksFinished) books."
        }
    }

    /// "4,210 pages, 98 hours, 235 cups."
    static func headline(_ summary: YearInBooks) -> String {
        "\(LeafFormat.number(summary.pages)) pages, \(LeafFormat.duration(minutes: summary.minutes)), \(summary.cups) \(summary.cups == 1 ? "cup" : "cups")."
    }

    static func summary(_ summary: YearInBooks) -> String {
        let books = summary.booksFinished == 1 ? "1 book" : "\(summary.booksFinished) books"
        return "In \(String(summary.year)): \(books), \(LeafFormat.number(summary.pages)) pages and \(LeafFormat.duration(minutes: summary.minutes)) of reading, about \(summary.cups) \(summary.cups == 1 ? "cup" : "cups") of \(summary.cupMinutes) minutes."
    }

    static func monthsSentence(_ summary: YearInBooks, calendar: Calendar) -> String {
        guard let busiest = summary.busiestMonth, let date = calendar.date(from: DateComponents(year: summary.year, month: busiest, day: 1)) else {
            return "No reading logged yet this year."
        }
        let name = LeafFormat.format(date, template: "MMMM", calendar: calendar)
        let read = summary.months.filter { $0.minutes > 0 }.count
        return "You read in \(read) \(read == 1 ? "month" : "months") of the year; \(name) was the busiest."
    }

    /// "January: 9 hours, 2 books. February: …", for the months with any reading.
    static func monthByMonth(_ summary: YearInBooks, calendar: Calendar) -> String {
        summary.months.filter { $0.minutes > 0 }.compactMap { month in
            guard let date = calendar.date(from: DateComponents(year: summary.year, month: month.month, day: 1)) else { return nil }
            let name = LeafFormat.format(date, template: "MMMM", calendar: calendar)
            let books = month.booksFinished == 0 ? "" : ", \(month.booksFinished) \(month.booksFinished == 1 ? "book" : "books") finished"
            return "\(name): \(LeafFormat.duration(minutes: month.minutes))\(books)."
        }
        .joined(separator: " ")
    }

    static func habitsSentence(_ summary: YearInBooks) -> String {
        var parts = ["Longest streak \(summary.longestStreak) \(summary.longestStreak == 1 ? "day" : "days")", "\(summary.daysRead) days read"]
        if let hour = summary.favouriteHour { parts.append("favourite hour \(BestTimeOfDay.hourLabel(hour))") }
        return parts.joined(separator: ", ") + "."
    }

    static func journalSentence(_ summary: YearInBooks) -> String {
        let quotes = summary.quotesSaved == 1 ? "1 quote" : "\(summary.quotesSaved) quotes"
        let notes = summary.notesSaved == 1 ? "1 note" : "\(summary.notesSaved) notes"
        return "Kept in your journal: \(quotes) and \(notes)."
    }

    static func highlights(_ summary: YearInBooks) -> [Highlight] {
        var rows: [Highlight] = []
        if let genre = summary.topGenre {
            rows.append(Highlight(label: "Most read", value: genre.name, detail: "\(genre.books) \(genre.books == 1 ? "book" : "books"), \(Int((genre.share * 100).rounded())) percent"))
        }
        if let author = summary.topAuthor, author.books > 1 {
            rows.append(Highlight(label: "Favourite author", value: author.name, detail: "\(author.books) books, \(LeafFormat.number(author.pages)) pages"))
        }
        if let longest = summary.longestBook {
            rows.append(Highlight(label: "Longest", value: longest.title, detail: "\(LeafFormat.number(longest.pages)) pages"))
        }
        if let fastest = summary.fastestBook, let perDay = fastest.pagesPerDay {
            rows.append(Highlight(label: "Couldn’t put it down", value: fastest.title, detail: "about \(Int(perDay.rounded())) pages a day"))
        }
        if let rating = summary.averageRating, summary.ratedBooks > 0 {
            rows.append(Highlight(label: "Average rating", value: String(format: "%.1f stars", rating), detail: "from \(summary.ratedBooks) rated"))
        }
        return rows
    }
}

/// The Year in Books as a shareable image: a tall card of paper.
struct YearInBooksPoster: View {
    let summary: YearInBooks
    let calendar: Calendar

    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("My \(String(summary.year)) in books")
            Text(YearInBooksText.title(summary))
                .leafStyle(.display)
            Text(YearInBooksText.headline(summary))
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
            MonthRingCollage(months: summary.months, ringSize: 46, showsLabels: true)
                .padding(.vertical, Space.s)
            Text(YearInBooksText.habitsSentence(summary))
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if let genre = summary.topGenre {
                Text("Mostly \(genre.name.lowercased()).")
                    .leafStyle(.caption)
            }
            Spacer(minLength: 0)
            HStack {
                Text(summary.finishedBooks.suffix(3).map(\.title).joined(separator: " · "))
                    .leafStyle(.caption, color: .inkTertiary)
                    .lineLimit(2)
                Spacer(minLength: Space.m)
                Text("Leaf").leafStyle(.wordmark)
            }
        }
        .padding(Space.xxl)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.paper)
    }
}

#if DEBUG
/// The two share images side by side at half size, drawn from the library on screen, for screenshots
/// (`-LeafScreen gallery.posters`). Debug builds only.
struct SharePosterStage: View {
    @Environment(LibraryStore.self) private var store

    private let scale: CGFloat = 0.52

    var body: some View {
        let engine = InsightsEngine(data: store.data, now: store.now, calendar: store.calendar)
        VStack(alignment: .leading, spacing: Space.l) {
            Eyebrow("Share images")
            HStack(alignment: .top, spacing: Space.m) {
                poster(YearInBooksPoster(summary: engine.yearInBooks(year: engine.currentYear), calendar: store.calendar), size: YearInBooksPoster.size)
                poster(PersonalityPoster(personality: engine.personality()), size: SharePoster.size)
            }
        }
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, Space.section)
        .background(Color.paperSunken)
    }

    private func poster<Content: View>(_ content: Content, size: CGSize) -> some View {
        content
            .environment(\.colorScheme, .light)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
#endif

// MARK: - Weekly letter

/// The Sunday letter (opened from its notification): a few warm sentences from `WeeklyLetterText` about the week, then
/// the plain numbers they came from.
struct WeeklyLetterView: View {
    let letter: WeeklyLetterData

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// The words for a week: the engine's numbers, put to `WeeklyLetterText` with a seed that stays put for the week.
    static func copy(for letter: WeeklyLetterData, calendar: Calendar) -> WeeklyLetterCopy {
        let week = letter.week
        let input = WeeklyLetterInput(
            minutes: week.minutes,
            cups: week.cups,
            pages: week.pages,
            booksFinished: week.booksFinished,
            finishedTitles: letter.finishedBooks.map(\.title),
            daysRead: week.daysRead,
            bestDayWeekday: letter.bestDay.map { calendar.component(.weekday, from: $0.date) },
            bestDayMinutes: letter.bestDay?.minutes,
            streak: letter.streak,
            lastWeekMinutes: letter.previous.minutes
        )
        let seed = UInt64(max(0, Int(calendar.startOfDay(for: week.start).timeIntervalSince1970 / 86_400)))
        return WeeklyLetterText.compose(input, seed: seed)
    }

    var body: some View {
        let copy = Self.copy(for: letter, calendar: store.calendar)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Eyebrow(weekLine)
                    Text(copy.title)
                        .leafStyle(.masthead)
                        .fixedSize(horizontal: false, vertical: true)
                    // The opening line on its own, then the rest as one paragraph, as a letter would be.
                    VStack(alignment: .leading, spacing: Space.m) {
                        if let opening = copy.sentences.first {
                            Text(opening)
                                .leafStyle(.pullQuote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(copy.sentences.dropFirst().joined(separator: " "))
                            .leafStyle(.passage)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("From your nook")
                        .leafStyle(.pullQuote, color: .inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Hairline()
                    StatTileRow {
                        StatTile(value: LeafFormat.compactDuration(minutes: letter.week.minutes), label: "Read")
                        StatTile(value: "\(letter.week.pages)", label: "Pages")
                        StatTile(value: "\(letter.week.daysRead)", label: letter.week.daysRead == 1 ? "Day" : "Days")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(numbersSentence)
                    Text("\(letter.week.cups) \(letter.week.cups == 1 ? "cup" : "cups") of \(store.preferences.cupMinutes) minutes · \(letter.week.sessions) \(letter.week.sessions == 1 ? "sitting" : "sittings")")
                        .leafStyle(.caption)
                }
                .leafMargins()
                .padding(.top, Space.l)
                .padding(.bottom, Space.section)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .paperBackground(.paperRaised)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// "13 – 19 October".
    private var weekLine: String {
        let calendar = store.calendar
        let sameMonth = calendar.component(.month, from: letter.week.start) == calendar.component(.month, from: letter.week.end)
        let start = LeafFormat.format(letter.week.start, template: sameMonth ? "d" : "dMMMM", calendar: calendar)
        let end = LeafFormat.format(letter.week.end, template: "dMMMM", calendar: calendar)
        return "\(start) – \(end)"
    }

    private var numbersSentence: String {
        let week = letter.week
        return "This week: \(LeafFormat.duration(minutes: week.minutes)) of reading, \(week.pages) pages, on \(week.daysRead) \(week.daysRead == 1 ? "day" : "days")."
    }
}
