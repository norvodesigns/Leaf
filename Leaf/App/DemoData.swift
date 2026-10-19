import Foundation

/// A lived-in library for screenshots and previews.
enum DemoData {
    static func book(_ id: String, _ title: String, _ author: String, _ year: Int, pages: Int, words: Int? = nil, cover: Int? = nil, genres: [String] = ["fiction"]) -> Book {
        Book(id: id, title: title, author: author, year: year, pages: pages, words: words, coverID: cover, genres: genres, popularity: 1000)
    }

    static let hobbit = book("OL27482W", "The Hobbit", "J. R. R. Tolkien", 1937, pages: 310, words: 95_000, cover: 14627509, genres: ["fantasy", "classics"])
    static let circe = book("OL18012166W", "Circe", "Madeline Miller", 2018, pages: 404, words: 109_080, cover: 8739376, genres: ["fantasy", "historical"])
    static let hailMary = book("OL21745884W", "Project Hail Mary", "Andy Weir", 2021, pages: 496, words: 133_920, cover: 11200092, genres: ["science-fiction"])
    static let piranesi = book("OL20893680W", "Piranesi", "Susanna Clarke", 2020, pages: 272, words: 73_440, cover: 10226290, genres: ["fantasy"])
    static let remains = book("OL59048W", "The Remains of the Day", "Kazuo Ishiguro", 1989, pages: 254, words: 68_580, cover: 95742, genres: ["literary", "classics"])
    static let gentleman = book("OL17797130W", "A Gentleman in Moscow", "Amor Towles", 2016, pages: 511, words: 137_970, cover: 11326818, genres: ["historical", "literary"])
    static let klara = book("OL20883297W", "Klara and the Sun", "Kazuo Ishiguro", 2021, pages: 334, words: 90_180, cover: 10648686, genres: ["science-fiction", "literary"])
    static let midnight = book("OL20965973W", "The Midnight Library", "Matt Haig", 2020, pages: 304, words: 82_080, cover: 10313767, genres: ["fiction"])
    static let educated = book("OL18139176W", "Educated", "Tara Westover", 2018, pages: 384, words: 103_680, cover: 8314077, genres: ["memoir"])
    static let dune = book("OL893415W", "Dune", "Frank Herbert", 1965, pages: 612, words: 187_000, cover: 12360023, genres: ["science-fiction", "classics"])
    static let nightCircus = book("OL16086747W", "The Night Circus", "Erin Morgenstern", 2011, pages: 512, words: 138_240, cover: 8773134, genres: ["fantasy"])

    /// Variants of the demo library, one per Today state worth a screenshot (`-LeafScenario <name>`).
    enum Scenario: String, CaseIterable {
        /// The lived-in library: two books open, a short session this morning.
        case standard
        /// Today's minutes are already read.
        case goalMet = "goalmet"
        /// Today isn't a reading day.
        case rest
        /// Nothing in Reading or To read: time to pick.
        case between
        /// Onboarded, but no books and no history yet.
        case brandNew = "new"
        /// The last session was two weeks ago.
        case returning
        /// Fourteen pages from the end of *The Hobbit*: the plan finishes it tonight.
        case finishing
        /// *Piranesi* just went on the desk and Leaf doesn't know the page yet.
        case newBook = "newbook"
        /// Side by side, with the morning time kept for *Circe*.
        case sideBySide = "sidebyside"
        /// The standard library with a whole year of reading behind it, for the Plan tab's insights and stamps.
        case year
    }

    static func make(now: Date = Date(), calendar: Calendar = .current, scenario: Scenario) -> LeafData {
        var data = make(now: now, calendar: calendar)
        let day = TimeInterval(86_400)
        switch scenario {
        case .standard:
            break
        case .goalMet:
            let start = calendar.date(bySettingHour: 19, minute: 40, second: 0, of: now) ?? now
            if start < now {
                data.sessions.append(ReadingSession(bookID: hobbit.id, startedAt: start, seconds: 16 * 60, fromPage: 142, toPage: 156, teaID: "rooibos"))
                if let index = data.items.firstIndex(where: { $0.id == hobbit.id }) { data.items[index].currentPage = 156 }
            }
        case .rest:
            data.preferences.readingDays.remove(calendar.component(.weekday, from: now))
        case .between:
            data.items.removeAll { $0.shelf == .toRead || $0.id == circe.id }
            if let index = data.items.firstIndex(where: { $0.id == hobbit.id }) {
                data.items[index].shelf = .finished
                data.items[index].currentPage = hobbit.pages
                data.items[index].finishedAt = now.addingTimeInterval(-day)
                data.items[index].rating = 5
            }
            data.journal.removeAll { $0.bookID == circe.id }
        case .brandNew:
            var fresh = LeafData()
            fresh.preferences.wpm = 262
            fresh.preferences.dailyMinutes = 25
            fresh.preferences.hasOnboarded = true
            fresh.preferences.onboardedAt = now
            return fresh
        case .returning:
            let today = calendar.startOfDay(for: now)
            data.sessions = data.sessions
                .filter { $0.startedAt < today }
                .map { session in
                    var moved = session
                    moved.startedAt = session.startedAt.addingTimeInterval(-14 * day)
                    return moved
                }
            if let index = data.items.firstIndex(where: { $0.id == hobbit.id }) { data.items[index].currentPage = 133 }
        case .finishing:
            let today = calendar.startOfDay(for: now)
            data.sessions.removeAll { $0.startedAt >= today }
            if let index = data.items.firstIndex(where: { $0.id == hobbit.id }) { data.items[index].currentPage = 296 }
        case .newBook:
            data.items.removeAll { $0.id == piranesi.id }
            data.items.append(LibraryItem(book: piranesi, shelf: .reading, order: -1, addedAt: now.addingTimeInterval(-3600)))
        case .sideBySide:
            data.preferences.planMode = .sideBySide
            if !data.preferences.readingSlots.isEmpty { data.preferences.readingSlots[0].bookID = circe.id }
        case .year:
            addYearOfReading(to: &data, now: now, calendar: calendar)
        }
        return data
    }

    /// Books finished earlier in the year (generated covers; the ids are not Open Library's).
    static let yearBooks: [Book] = [
        book("demo-station", "Station Eleven", "Emily St. John Mandel", 2014, pages: 333, words: 89_910, genres: ["science-fiction", "literary"]),
        book("demo-cerulean", "The House in the Cerulean Sea", "TJ Klune", 2020, pages: 394, words: 106_380, genres: ["fantasy"]),
        book("demo-anxious", "Anxious People", "Fredrik Backman", 2019, pages: 341, words: 92_070, genres: ["fiction", "humor"]),
        book("demo-thursday", "The Thursday Murder Club", "Richard Osman", 2020, pages: 382, words: 103_140, genres: ["mystery"]),
        book("demo-legends", "Legends & Lattes", "Travis Baldree", 2022, pages: 296, words: 79_920, genres: ["fantasy"]),
        book("demo-pachinko", "Pachinko", "Min Jin Lee", 2017, pages: 490, words: 132_300, genres: ["historical", "literary"]),
        book("demo-braiding", "Braiding Sweetgrass", "Robin Wall Kimmerer", 2013, pages: 391, words: 105_570, genres: ["nature", "memoir"]),
    ]

    /// Fills the year before the standard library's last twelve days: the books above finished from January on, and
    /// sittings for every finished book between its start and finish. Mostly evenings, some weekday mornings, long
    /// weekend afternoons, a few rest days, a pace that creeps up over the year, and a rotation of teas. Deterministic.
    private static func addYearOfReading(to data: inout LeafData, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: now)
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 3)) else { return }
        func dayIndex(_ date: Date) -> Int { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0 }
        func noise(_ day: Int, _ salt: Int) -> Int { (((day &* 2_654_435_761) ^ (salt &* 40_503)) & 0x7FFF_FFFF) % 1_000 }
        let teas = ["earl-grey", "sencha", "english-breakfast", "milk-oolong", "jasmine-green", "darjeeling", "matcha", "genmaicha"]
        let totalDays = -dayIndex(yearStart)

        // The finished books of the standard library keep their dates; the new ones fill the months before.
        let firstStandardStart = data.items.filter { $0.shelf == .finished }.compactMap(\.startedAt).min() ?? today
        let earlySpan = max(30, -dayIndex(yearStart) + dayIndex(firstStandardStart))
        let share = earlySpan / max(1, yearBooks.count)
        var finished: [(book: Book, start: Int, end: Int)] = []
        for (index, book) in yearBooks.enumerated() {
            let start = -totalDays + index * share
            let end = start + share - 1 - (index % 3)
            finished.append((book, start, end))
            data.items.append(LibraryItem(
                book: book, shelf: .finished, currentPage: book.pages, order: Double(10 + index),
                addedAt: calendar.date(byAdding: .day, value: start - 6, to: today) ?? today,
                startedAt: calendar.date(byAdding: .day, value: start, to: today),
                finishedAt: calendar.date(byAdding: .day, value: end, to: today),
                rating: 3 + noise(index, 7) % 3
            ))
        }
        for item in data.items where item.shelf == .finished && !yearBooks.contains(where: { $0.id == item.id }) {
            guard let started = item.startedAt, let ended = item.finishedAt else { continue }
            finished.append((item.book, dayIndex(started), dayIndex(ended)))
        }

        for entry in finished {
            let days = (entry.start...max(entry.start, entry.end)).filter { day in
                guard let date = calendar.date(byAdding: .day, value: day, to: today) else { return false }
                let weekend = calendar.isDateInWeekend(date)
                return day == entry.end || noise(day, 1) < (weekend ? 880 : 690)
            }
            guard !days.isEmpty else { continue }
            let perSitting = Int((Double(entry.book.pages) / Double(days.count)).rounded(.up))
            var page = 0
            for day in days where page < entry.book.pages {
                guard let date = calendar.date(byAdding: .day, value: day, to: today) else { continue }
                let weekend = calendar.isDateInWeekend(date)
                let morning = !weekend && noise(day, 3) % 4 == 0
                let hour = weekend ? 15 : (morning ? 7 : 21)
                let minute = noise(day, 5) % 50
                let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
                let pages = min(perSitting + (weekend ? perSitting / 2 : 0), entry.book.pages - page)
                // Faster as the year goes on: about 240 wpm in January to about 275 by autumn.
                let progress = Double(totalDays + day) / Double(max(1, totalDays))
                let wpm = (240 + 35 * progress) * (0.9 + Double(noise(day, 9) % 200) / 1_000)
                let seconds = Double(pages) * entry.book.wordsPerPage / wpm * 60
                data.sessions.append(ReadingSession(
                    bookID: entry.book.id, startedAt: start, seconds: seconds, fromPage: page, toPage: page + pages,
                    teaID: noise(day, 11) % 3 == 0 ? nil : teas[noise(day, 13) % teas.count]
                ))
                page += pages
            }
        }

        let quotes: [(Book, String, Int, Int)] = [
            (yearBooks[0], "Because survival is insufficient.", 58, -280),
            (yearBooks[1], "Sometimes the family you choose is the one that saves you.", 211, -250),
            (yearBooks[4], "Sometimes you have to walk away from one thing to find another.", 140, -190),
            (yearBooks[6], "All flourishing is mutual.", 166, -160),
        ]
        for (book, text, page, day) in quotes {
            data.journal.append(JournalEntry(
                bookID: book.id, bookTitle: book.title, bookAuthor: book.author, kind: .quote, text: text, page: page,
                createdAt: calendar.date(byAdding: .day, value: max(day, -totalDays + 1), to: today) ?? today
            ))
        }
        data.challenges.append(ChallengeEnrollment(id: "cozy-bingo", joinedAt: yearStart, year: year))
        data.challenges.append(ChallengeEnrollment(id: "tea-tasting", joinedAt: yearStart, year: nil))
        data.preferences.onboardedAt = yearStart
    }

    static func make(now: Date = Date(), calendar: Calendar = .current) -> LeafData {
        func daysAgo(_ days: Int, hour: Int = 21) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: 10, second: 0, of: day) ?? day
        }

        var data = LeafData()
        data.preferences.wpm = 262
        data.preferences.dailyMinutes = 25
        data.preferences.reminderEnabled = true
        data.preferences.reminderHour = 21
        data.preferences.reminderMinute = 0
        data.preferences.hasOnboarded = true
        data.preferences.onboardedAt = daysAgo(41)
        data.preferences.yearlyGoal = 24
        data.preferences.favoriteTeaID = "earl-grey"
        data.preferences.ambienceID = "rain"
        data.preferences.weeklyLetter = true
        data.preferences.readingSlots = [
            ReadingSlot(hour: 7, minute: 30, weekdays: [2, 3, 4, 5, 6], label: "Morning tea"),
            ReadingSlot(hour: 21, minute: 0, label: "Before bed"),
        ]

        data.items = [
            LibraryItem(book: hobbit, shelf: .reading, currentPage: 142, order: 0, addedAt: daysAgo(30), startedAt: daysAgo(12)),
            LibraryItem(book: circe, shelf: .reading, currentPage: 88, order: 1, addedAt: daysAgo(40), startedAt: daysAgo(20)),
            LibraryItem(book: piranesi, shelf: .toRead, order: 0, addedAt: daysAgo(25)),
            LibraryItem(book: hailMary, shelf: .toRead, order: 1, addedAt: daysAgo(22)),
            LibraryItem(book: remains, shelf: .toRead, order: 2, addedAt: daysAgo(18)),
            LibraryItem(book: gentleman, shelf: .toRead, order: 3, addedAt: daysAgo(9)),
            LibraryItem(book: klara, shelf: .finished, currentPage: klara.pages, order: 0, addedAt: daysAgo(60), startedAt: daysAgo(35), finishedAt: daysAgo(14), rating: 5),
            LibraryItem(book: midnight, shelf: .finished, currentPage: midnight.pages, order: 1, addedAt: daysAgo(90), startedAt: daysAgo(55), finishedAt: daysAgo(38), rating: 4),
            LibraryItem(book: educated, shelf: .finished, currentPage: educated.pages, order: 2, addedAt: daysAgo(120), startedAt: daysAgo(95), finishedAt: daysAgo(70), rating: 5),
            LibraryItem(book: nightCircus, shelf: .finished, currentPage: nightCircus.pages, order: 3, addedAt: daysAgo(160), startedAt: daysAgo(140), finishedAt: daysAgo(110), rating: 4),
            // Set aside a while ago, far enough in that coming back to it is easy.
            LibraryItem(book: dune, shelf: .paused, currentPage: 188, order: 0, addedAt: daysAgo(75), startedAt: daysAgo(66), pausedAt: daysAgo(31), updatedAt: daysAgo(31)),
        ]

        // Twelve days of reading with one rest day, and a short session already today.
        let minutes: [Int: Double] = [1: 28, 2: 25, 3: 31, 4: 22, 6: 26, 7: 35, 8: 24, 9: 27, 10: 20, 11: 30, 12: 25]
        var page = 40
        for (days, length) in minutes.sorted(by: { $0.key > $1.key }) {
            let pages = Int(length * 262 / hobbit.wordsPerPage)
            let tea = days % 3 == 0 ? "sencha" : (days % 2 == 0 ? "earl-grey" : nil)
            data.sessions.append(ReadingSession(bookID: hobbit.id, startedAt: daysAgo(days), seconds: length * 60, fromPage: page, toPage: page + pages, teaID: tea, ambienceID: tea == nil ? nil : "rain"))
            page += pages
        }
        // This morning's short session, once the morning has happened (screenshots can stage an earlier hour).
        let thisMorning = daysAgo(0, hour: 8)
        if thisMorning.addingTimeInterval(12 * 60) <= now {
            data.sessions.append(ReadingSession(bookID: hobbit.id, startedAt: thisMorning, seconds: 12 * 60, fromPage: 133, toPage: 142))
        }
        data.journal = [
            JournalEntry(bookID: hobbit.id, bookTitle: hobbit.title, bookAuthor: hobbit.author, kind: .thought, text: "Bilbo is exactly as stubborn about comfort as I am about tea.", page: 61, isFavorite: true, createdAt: daysAgo(6)),
            JournalEntry(bookID: circe.id, bookTitle: circe.title, bookAuthor: circe.author, kind: .quote, text: "I thought: this is what it is to be alive.", page: 74, createdAt: daysAgo(9)),
            JournalEntry(bookID: klara.id, bookTitle: klara.title, bookAuthor: klara.author, kind: .thought, text: "Finished at 1am and sat there a while. Worth every page.", page: klara.pages, createdAt: daysAgo(14)),
        ]
        data.challenges = [
            ChallengeEnrollment(id: "yearly-goal", joinedAt: daysAgo(41), year: calendar.component(.year, from: now)),
            ChallengeEnrollment(id: "spooky-season", joinedAt: daysAgo(10), year: calendar.component(.year, from: now)),
        ]
        data.speedTests = [SpeedTestResult(date: daysAgo(30), passageID: "bindery", words: 302, seconds: 69, correct: 3, total: 3)]
        return data
    }
}
