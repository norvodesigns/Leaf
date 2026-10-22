import Foundation
import Testing
#if !canImport(LeafCore)
@testable import Leaf

/// The App Store screenshot library (`-LeafPublicDomain YES`) shows no modern title, author, cover or quote.
struct DemoPublicDomainTests {
    private let modern = ["The Hobbit", "Tolkien", "Circe", "Madeline Miller", "Piranesi", "Hail Mary", "Ishiguro", "Bilbo",
                          "Station Eleven", "Cerulean", "Pachinko", "Sweetgrass", "Legends & Lattes", "Thursday Murder"]

    @Test(arguments: DemoData.Scenario.allCases)
    func everyScenarioIsPublicDomain(_ scenario: DemoData.Scenario) throws {
        let data = DemoData.publicDomain(DemoData.make(scenario: scenario))
        let books = data.items.map(\.book) + data.circles.map(\.book)
        for book in books {
            #expect(DemoData.publicDomainStands[book.id] != nil, "\(book.title) has no public-domain stand-in")
            #expect(book.coverID == nil)
        }
        let text = (books.flatMap { [$0.title, $0.author] } + data.journal.flatMap { [$0.bookTitle, $0.bookAuthor, $0.text] })
            .joined(separator: "\n")
        for name in modern { #expect(!text.contains(name), "\(name) is still in the \(scenario) library") }
    }

    @Test func idsAndPagesStay() {
        let original = DemoData.make()
        let swapped = DemoData.publicDomain(original)
        #expect(swapped.items.map(\.id) == original.items.map(\.id))
        #expect(swapped.items.map(\.book.pages) == original.items.map(\.book.pages))
        #expect(swapped.sessions == original.sessions)
    }
}
#endif
