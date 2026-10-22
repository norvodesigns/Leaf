import Foundation
import Testing
#if !canImport(LeafCore)
@testable import Leaf

/// The live search's erotica rule, which matches the catalog build's `is_adult` (app-only: OpenLibrary is in the app).
struct OpenLibraryTests {
    @Test func eroticaIsLeftOutOfSearch() {
        #expect(OpenLibrary.isAdult(subjects: ["Fiction, erotica", "Erotic fiction", "Romance"] + Array(repeating: "Fiction", count: 10)))
        #expect(OpenLibrary.isAdult(subjects: ["Erotica", "Fiction"]))
        #expect(OpenLibrary.isAdult(subjects: ["BDSM", "Fiction"]))
    }

    @Test func aStrayEroticismOnAClassicStays() {
        #expect(!OpenLibrary.isAdult(subjects: ["Eroticism", "Psychological fiction"] + Array(repeating: "Fiction", count: 10)))
        #expect(!OpenLibrary.isAdult(subjects: ["Heroic fantasy", "Heroes"]))
        #expect(!OpenLibrary.isAdult(subjects: []))
    }

    @Test func theUserAgentCarriesAContact() {
        #expect(OpenLibrary.userAgent.hasPrefix("Leaf/"))
        #expect(OpenLibrary.userAgent.contains("@"))
    }
}
#endif
