import Foundation

/// The demo library with public-domain books in place of the modern ones, for App Store screenshots
/// (`-LeafPublicDomain YES`): no one else's titles or cover art on the product page. Each book keeps its id and page
/// count, so every scenario, session and circle stays as it is; covers are Leaf's generated ones.
extension DemoData {
    struct Stand: Sendable {
        var title: String
        var author: String
        var year: Int
        var genres: [String]
    }

    /// Demo book id → its public-domain stand-in.
    static let publicDomainStands: [String: Stand] = [
        hobbit.id: Stand(title: "The Wind in the Willows", author: "Kenneth Grahame", year: 1908, genres: ["fantasy", "classics"]),
        circe.id: Stand(title: "Pride and Prejudice", author: "Jane Austen", year: 1813, genres: ["romance", "classics"]),
        hailMary.id: Stand(title: "The War of the Worlds", author: "H. G. Wells", year: 1898, genres: ["science-fiction", "classics"]),
        piranesi.id: Stand(title: "Alice’s Adventures in Wonderland", author: "Lewis Carroll", year: 1865, genres: ["fantasy", "classics"]),
        remains.id: Stand(title: "Persuasion", author: "Jane Austen", year: 1817, genres: ["romance", "classics"]),
        gentleman.id: Stand(title: "Middlemarch", author: "George Eliot", year: 1871, genres: ["literary", "classics"]),
        klara.id: Stand(title: "Frankenstein", author: "Mary Shelley", year: 1818, genres: ["science-fiction", "classics"]),
        midnight.id: Stand(title: "Little Women", author: "Louisa May Alcott", year: 1868, genres: ["fiction", "classics"]),
        educated.id: Stand(title: "Walden", author: "Henry David Thoreau", year: 1854, genres: ["nature", "memoir"]),
        dune.id: Stand(title: "Moby-Dick", author: "Herman Melville", year: 1851, genres: ["adventure", "classics"]),
        nightCircus.id: Stand(title: "The Secret Garden", author: "Frances Hodgson Burnett", year: 1911, genres: ["fiction", "classics"]),
        "demo-station": Stand(title: "The Time Machine", author: "H. G. Wells", year: 1895, genres: ["science-fiction", "classics"]),
        "demo-cerulean": Stand(title: "Anne of Green Gables", author: "L. M. Montgomery", year: 1908, genres: ["fiction", "classics"]),
        "demo-anxious": Stand(title: "Three Men in a Boat", author: "Jerome K. Jerome", year: 1889, genres: ["humor", "classics"]),
        "demo-thursday": Stand(title: "The Hound of the Baskervilles", author: "Arthur Conan Doyle", year: 1902, genres: ["mystery", "classics"]),
        "demo-legends": Stand(title: "The Princess and the Goblin", author: "George MacDonald", year: 1872, genres: ["fantasy", "classics"]),
        "demo-pachinko": Stand(title: "Jane Eyre", author: "Charlotte Brontë", year: 1847, genres: ["literary", "classics"]),
        "demo-braiding": Stand(title: "Steep Trails", author: "John Muir", year: 1918, genres: ["nature", "memoir"]),
    ]

    /// Journal lines that quote or name a modern book, and what the public-domain library says instead.
    static let publicDomainLines: [String: String] = [
        "There is nothing like looking, if you want to find something.":
            "There is nothing—absolute nothing—half so much worth doing as simply messing about in boats.",
        "Bilbo is exactly as stubborn about comfort as I am about tea.":
            "Mole is exactly as stubborn about comfort as I am about tea.",
        "I thought: this is what it is to be alive.":
            "I declare after all there is no enjoyment like reading!",
        "Because survival is insufficient.":
            "Nature never appeals to intelligence until habit and instinct are useless.",
        "Sometimes the family you choose is the one that saves you.":
            "Isn’t it nice to think that tomorrow is a new day with no mistakes in it yet?",
        "Sometimes you have to walk away from one thing to find another.":
            "Seeing is not believing—it is only seeing.",
        "All flourishing is mutual.":
            "In every walk with nature one receives far more than he seeks.",
    ]

    static func publicDomain(_ book: Book) -> Book {
        guard let stand = publicDomainStands[book.id] else { return book }
        var copy = book
        copy.title = stand.title
        copy.author = stand.author
        copy.year = stand.year
        copy.genres = stand.genres
        copy.themes = nil
        copy.coverID = nil
        return copy
    }

    static func publicDomain(_ data: LeafData) -> LeafData {
        var data = data
        for index in data.items.indices { data.items[index].book = publicDomain(data.items[index].book) }
        for index in data.circles.indices { data.circles[index].book = publicDomain(data.circles[index].book) }
        for index in data.journal.indices {
            let entry = data.journal[index]
            if let stand = publicDomainStands[entry.bookID] {
                data.journal[index].bookTitle = stand.title
                data.journal[index].bookAuthor = stand.author
            }
            if let line = publicDomainLines[entry.text] { data.journal[index].text = line }
        }
        return data
    }
}
