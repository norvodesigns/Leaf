import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct LibrarianTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func calendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    /// Cozy books in three sizes, plus thrillers and horror that a cozy ask must never return.
    private func pool() -> [Book] {
        var books: [Book] = []
        let spec: [(String, [String], [String])] = [
            ("cozy", ["fiction"], ["cozy", "tea & cafes", "cats"]),
            ("thriller", ["thriller"], ["psychological suspense", "secrets"]),
            ("horror", ["horror"], ["ghosts", "monsters", "cozy"]),
            ("fantasy", ["fantasy"], ["magic", "dragons"]),
        ]
        for (index, entry) in spec.enumerated() {
            for n in 0..<40 {
                books.append(Book(
                    id: "\(entry.0)-\(n)", title: "\(entry.0.capitalized) Tale \(n)", author: "\(entry.0) author \(n % 15)",
                    year: 1980 + n, pages: 120 + n * 15, genres: entry.1, popularity: 5_000 - n * 40 - index, themes: entry.2
                ))
            }
        }
        return books
    }

    private func librarian(library: [LibraryItem] = []) -> Librarian {
        let books = pool()
        let context = RecommendationContext(library: library, sessions: [], dismissed: [], wpm: 250, dailyMinutes: 30, now: now, calendar: calendar())
        return Librarian(pool: books, stats: CatalogStats(books: books), context: context)
    }

    @Test func everyMoodIsACarouselMood() {
        for mood in LibrarianMood.all {
            #expect(mood.weights != nil, "\(mood.id) has no weights in CollectionBuilder.moods")
        }
    }

    @Test func aCozyAskOnlyReturnsCozyBooks() {
        let answer = librarian().answer(LibrarianAsk(moodID: "cozy"), seed: 3)
        let count = answer.picks.count
        #expect(count >= 4)
        for pick in answer.picks {
            let isCozy = pick.book.id.hasPrefix("cozy-")
            #expect(isCozy, "\(pick.book.id) is not a cozy book")
        }
        #expect(answer.loosened.isEmpty)
    }

    @Test func avoidedThemesNeverMatch() {
        let matches = librarian().matches(for: LibrarianAsk(moodID: "cozy"), in: pool())
        let horror = matches.filter { $0.genres.contains("horror") }
        #expect(horror.isEmpty, "horror is on the cozy mood's avoid list")
    }

    @Test func lengthAndTimeFilter() {
        let lib = librarian()
        let slim = lib.matches(for: LibrarianAsk(length: .slim), in: pool())
        let slimOK = slim.allSatisfy { $0.pages < 250 }
        #expect(!slim.isEmpty && slimOK)
        let tonight = lib.matches(for: LibrarianAsk(time: .tonight), in: pool())
        let tonightOK = tonight.allSatisfy { $0.minutes(atWPM: 250) <= 180 }
        #expect(!tonight.isEmpty && tonightOK)
    }

    @Test func impossibleAsksLoosenInsteadOfComingBackEmpty() {
        // No cozy book is a doorstop (the longest is 705 pages, but only a handful pass 450 and 'tonight' rules them out).
        let answer = librarian().answer(LibrarianAsk(moodID: "cozy", time: .tonight, length: .doorstop), seed: 1)
        let loosened = answer.loosened
        #expect(loosened.first == .length)
        #expect(!answer.picks.isEmpty)
    }

    @Test func ownedAndShownBooksAreSkipped() {
        let books = pool()
        let owned = LibraryItem(book: books[0], shelf: .toRead, order: 0, addedAt: now)
        let lib = librarian(library: [owned])
        let first = lib.answer(LibrarianAsk(moodID: "cozy"), limit: 6, seed: 2)
        let firstIDs = Set(first.picks.map(\.id))
        #expect(!firstIDs.contains(books[0].id))
        let second = lib.answer(LibrarianAsk(moodID: "cozy"), limit: 6, seed: 2, excluding: firstIDs)
        let overlap = firstIDs.intersection(second.picks.map(\.id))
        #expect(overlap.isEmpty, "asking again should show new books")
    }

    @Test func answersAreDeterministic() {
        let a = librarian().answer(LibrarianAsk(moodID: "page-turners", time: .thisWeek), seed: 9).picks.map(\.id)
        let b = librarian().answer(LibrarianAsk(moodID: "page-turners", time: .thisWeek), seed: 9).picks.map(\.id)
        #expect(a == b)
    }

    @Test func whyLinesAreTrue() {
        let lib = librarian()
        let book = pool()[3]
        let line = lib.moodLine(for: book, moodID: "cozy") ?? ""
        #expect(line.hasPrefix("Cozy and tea & cafes"), "got \(line)")
        #expect(line.hasSuffix("for a cozy mood"))
        let fit = lib.fitLine(for: book, time: .tonight)
        #expect(fit.hasSuffix("one evening at your pace"))
    }

    @Test func everyLineFollowsTheVoice() {
        var failures: [String] = []
        for line in LibrarianLines.all where !VoiceTone.violations(in: line, maxWords: VoiceTone.maxSublineWords).isEmpty {
            failures.append(line)
        }
        for mood in LibrarianMood.all where !VoiceTone.violations(in: mood.label, maxWords: 4).isEmpty {
            failures.append(mood.label)
        }
        #expect(failures.isEmpty, "\(failures)")
    }
}
