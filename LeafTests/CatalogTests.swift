import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Fixtures

private func book(_ id: String, _ title: String, _ author: String = "Some Author", pop: Int = 100) -> Book {
    Book(id: id, title: title, author: author, year: 2000, pages: 300, genres: ["fiction"], popularity: pop)
}

private func candidate(_ id: String, _ title: String, _ author: String = "Some Author", pop: Int = 100, bm25: Double = -3) -> CatalogCandidate {
    CatalogCandidate(book: book(id, title, author, pop: pop), bm25: bm25)
}

/// The same table lives in scripts/catalog/tests/test_query.py. Change both together.
private let normalizeCases: [(String, String)] = [
    ("Harry Potter and the Philosopher's Stone", "harry potter and the philosopher s stone"),
    ("  J. R. R.  Tolkien ", "j r r tolkien"),
    ("Brontë", "bronte"),
    ("Gabriel García Márquez", "gabriel garcia marquez"),
    ("ÉMILE ZOLA", "emile zola"),
    ("War-and-Peace", "war and peace"),
    ("C++ & Rust", "c rust"),
    ("1984", "1984"),
    ("", ""),
    ("!!! ???", ""),
]

private let expressionCases: [(String, String?)] = [
    ("Harry Pot", "\"harry\"* \"pot\"*"),
    ("dune", "\"dune\"*"),
    ("J. R. R. Tolkien", "\"j\" \"r\" \"r\" \"tolkien\"*"),
    ("a", "\"a\""),
    ("O'Brien", "\"o\" \"brien\"*"),
    ("Brontë", "\"bronte\"*"),
    ("title:dune", "\"title\"* \"dune\"*"),
    ("\"quoted\" OR NEAR(a b)", "\"quoted\"* \"or\"* \"near\"* \"a\" \"b\""),
    ("one two three four five six seven", "\"one\"* \"two\"* \"three\"* \"four\"* \"five\"* \"six\"*"),
    ("   ", nil),
    ("***", nil),
    ("", nil),
]

// MARK: - Text

struct CatalogQueryTextTests {
    @Test func normalizesLikeTheOldSearchDid() {
        for (input, expected) in normalizeCases {
            #expect(CatalogQuery.normalize(input) == expected, "normalize(\(input))")
        }
    }

    @Test func expressionsMatchTheTable() {
        for (input, expected) in expressionCases {
            #expect(CatalogQuery.ftsExpression(for: input) == expected, "expression(\(input))")
        }
    }

    @Test func overlongWordsAreCut() {
        let long = String(repeating: "a", count: 80)
        let expression = CatalogQuery.ftsExpression(for: long)
        #expect(expression == "\"" + String(repeating: "a", count: CatalogQuery.maxTermLength) + "\"*")
    }

    @Test func nonAsciiFallbackAgreesWithTheFastPath() {
        // The same words, once with an accent (Foundation path) and once without (ASCII path).
        #expect(CatalogQuery.normalize("Zoë Heller") == CatalogQuery.normalize("Zoe Heller"))
        #expect(CatalogQuery.normalize("Ångström") == "angstrom")
    }

    /// Whatever is typed, the expression is nil or a run of quoted words with an optional star, so it can never be an
    /// FTS5 syntax error and typed operators can never change what is asked.
    @Test func expressionsAreAlwaysSafe() {
        let alphabet = Array("abcXYZ019 \t\"'*:()-+^{}[]~|\\&,.;!?éÅßñ中ا\u{0301}")
        var rng = SeededGenerator(seed: 4242)
        for _ in 0..<2_000 {
            let length = Int(rng.next() % 40)
            let text = String((0..<length).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
            guard let expression = CatalogQuery.ftsExpression(for: text) else {
                #expect(CatalogQuery.terms(text).isEmpty)
                continue
            }
            let pieces = expression.split(separator: " ")
            #expect(pieces.count <= CatalogQuery.maxTerms)
            for piece in pieces {
                var body = Substring(piece)
                if body.hasSuffix("*") { body = body.dropLast() }
                #expect(body.hasPrefix("\"") && body.hasSuffix("\"") && body.count >= 3, "piece \(piece) from \(text.debugDescription)")
                let inner = body.dropFirst().dropLast()
                #expect(!inner.isEmpty && inner.allSatisfy { $0.isLetter || $0.isNumber }, "inner \(inner) from \(text.debugDescription)")
            }
        }
    }

    @Test func storedListsDecode() {
        #expect(CatalogQuery.decodeIDs("3 17 204") == [3, 17, 204])
        #expect(CatalogQuery.decodeIDs("") == [])
        #expect(CatalogQuery.decodeIDs(nil) == [])
        #expect(CatalogQuery.decodeIDs("4 x 9") == [4, 9])
        #expect(CatalogQuery.decodeCounts("310,330,366") == [310, 330, 366])
        #expect(CatalogQuery.decodeCounts(nil) == [])
        #expect(CatalogQuery.decodeCounts("") == [])
    }
}

// MARK: - Ranking

struct CatalogRankingTests {
    @Test func exactTitleBeatsPrefixBeatsContains() {
        let found = [
            candidate("c", "The Dune Chronicles", pop: 5_000),
            candidate("b", "Dune Messiah", pop: 5_000),
            candidate("a", "Dune", pop: 50),
        ]
        #expect(CatalogQuery.rank(found, query: "dune", limit: 10).map(\.id) == ["a", "b", "c"])
    }

    @Test func popularityBreaksTiesBetweenEqualMatches() {
        let found = [
            candidate("low", "Emma Stories", pop: 10),
            candidate("high", "Emma Tales", pop: 90_000),
        ]
        #expect(CatalogQuery.rank(found, query: "emma", limit: 10).map(\.id) == ["high", "low"])
    }

    @Test func authorMatchCountsButTitleMatchCountsMore() {
        let found = [
            candidate("byAuthor", "A Study in Scarlet", "Sherlock Press", pop: 100),
            candidate("byTitle", "Sherlock Holmes", "Arthur Doyle", pop: 100),
        ]
        #expect(CatalogQuery.rank(found, query: "sherlock", limit: 10).first?.id == "byTitle")
    }

    @Test func bm25OrdersNearTiesButNeverBeatsAnExactTitle() {
        let near = [
            candidate("weak", "Garden Notes", pop: 100, bm25: -1),
            candidate("strong", "Garden Plans", pop: 100, bm25: -12),
        ]
        #expect(CatalogQuery.rank(near, query: "garden", limit: 10).first?.id == "strong")
        let exact = [
            candidate("exact", "Garden", pop: 1, bm25: 0),
            candidate("other", "Garden Plans", pop: 1_000_000, bm25: -40),
        ]
        #expect(CatalogQuery.rank(exact, query: "garden", limit: 10).first?.id == "exact")
    }

    @Test func limitEmptyQueriesAndEmptyCandidates() {
        let found = (0..<20).map { candidate("id\($0)", "Tea \($0)", pop: $0) }
        #expect(CatalogQuery.rank(found, query: "tea", limit: 5).count == 5)
        #expect(CatalogQuery.rank(found, query: "tea", limit: 0).isEmpty)
        #expect(CatalogQuery.rank(found, query: "  ", limit: 5).isEmpty)
        #expect(CatalogQuery.rank([], query: "tea", limit: 5).isEmpty)
        #expect(CatalogQuery.rank(found, query: "tea", limit: 500).count == 20)
    }

    @Test func rankingIsDeterministicWhateverTheInputOrder() {
        var rng = SeededGenerator(seed: 11)
        let found = (0..<60).map { candidate("id\($0)", "Word \($0 % 7)", pop: Int(rng.next() % 5), bm25: -Double(rng.next() % 10)) }
        let expected = CatalogQuery.rank(found, query: "word", limit: 60).map(\.id)
        for round in 0..<5 {
            var shuffled = found
            var shuffler = SeededGenerator(seed: UInt64(round + 1))
            shuffled.shuffle(using: &shuffler)
            #expect(CatalogQuery.rank(shuffled, query: "word", limit: 60).map(\.id) == expected)
        }
    }

    @Test func accentsAndCaseDoNotMatter() {
        let found = [candidate("a", "Les Misérables", "Victor Hugo"), candidate("b", "Misery", "Stephen King", pop: 9_000)]
        #expect(CatalogQuery.rank(found, query: "MISERABLES", limit: 5).first?.id == "a")
    }

    @Test func hugeAndNegativePopularityDoNotBreakScoring() {
        let found = [candidate("neg", "Odd", pop: -5), candidate("big", "Odd Book", pop: Int.max / 4)]
        #expect(CatalogQuery.rank(found, query: "odd", limit: 5).count == 2)
    }

    @Test func rankingTheCandidateWindowIsFast() {
        let found = (0..<CatalogQuery.candidateLimit).map { candidate("id\($0)", "Some Longer Title Number \($0) of the Series", "Firstname Surname", pop: $0) }
        let start = Date()
        for _ in 0..<20 { _ = CatalogQuery.rank(found, query: "some longer", limit: 40) }
        #expect(Date().timeIntervalSince(start) / 20 < 0.03)
    }
}
