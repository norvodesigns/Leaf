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
    static let nightCircus = book("OL16086747W", "The Night Circus", "Erin Morgenstern", 2011, pages: 512, words: 138_240, cover: 8773134, genres: ["fantasy"])

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
        ]

        // Twelve days of reading with one rest day, and a short session already today.
        let minutes: [Int: Double] = [1: 28, 2: 25, 3: 31, 4: 22, 6: 26, 7: 35, 8: 24, 9: 27, 10: 20, 11: 30, 12: 25]
        var page = 40
        for (days, length) in minutes.sorted(by: { $0.key > $1.key }) {
            let pages = Int(length * 262 / hobbit.wordsPerPage)
            data.sessions.append(ReadingSession(bookID: hobbit.id, startedAt: daysAgo(days), seconds: length * 60, fromPage: page, toPage: page + pages))
            page += pages
        }
        data.sessions.append(ReadingSession(bookID: hobbit.id, startedAt: daysAgo(0, hour: 8), seconds: 12 * 60, fromPage: 133, toPage: 142))
        data.speedTests = [SpeedTestResult(date: daysAgo(30), passageID: "bindery", words: 302, seconds: 69, correct: 3, total: 3)]
        return data
    }
}
