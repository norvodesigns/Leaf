// Prints the Search carousels for a sample reader, so recommender and lexicon changes can be judged without a device.
// Build and run from the repo root (needs only a Swift toolchain, no Xcode):
//   swiftc -O -o /tmp/showrows Shared/*.swift scripts/showrows/main.swift && /tmp/showrows 30
// The optional argument is how many rows to print per reader.
import Foundation

struct Rec: Decodable { let id: String, t: String, a: String; let y: Int?; let p: Int; let w: Int?; let c: Int?; let g: [String]?; let pop: Int?; let th: [String]?
    var book: Book { Book(id: id, title: t, author: a, year: y, pages: p, words: w, coverID: c, genres: g ?? [], popularity: pop ?? 0, themes: th) } }
let catalogURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Leaf/Resources/books.json")
let data = try! Data(contentsOf: catalogURL)
let books = try! JSONDecoder().decode([Rec].self, from: data).map(\.book)
let stats = CatalogStats(books: books)
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 21))!
func find(_ t: String) -> Book { books.first { $0.title == t }! }
func fin(_ b: Book, _ s: Int, _ f: Int, rating: Int? = nil) -> LibraryItem {
    var i = LibraryItem(book: b, shelf: .finished, currentPage: b.pages, order: 0, startedAt: cal.date(byAdding: .day, value: -s, to: now), finishedAt: cal.date(byAdding: .day, value: -f, to: now), rating: rating); i.currentPage = b.pages; return i }

func show(_ name: String, _ ctx: RecommendationContext?) {
    let rows = CollectionBuilder(books: books, stats: stats, wpm: 250, dailyMinutes: 30, now: now, calendar: cal, context: ctx).build()
    print("\n==================== \(name): \(rows.count) rows, \(Set(rows.flatMap { $0.books.map(\.id) }).count) distinct books")
    for (i, r) in rows.prefix(Int(CommandLine.arguments.dropFirst().first ?? "30") ?? 30).enumerated() {
        let titles = r.books.prefix(5).map(\.title).joined(separator: " | ")
        print(String(format: "%2d [%@] %@ (%d) - %@", i + 1, String(r.kind.rawValue.prefix(1)), r.title, r.books.count, titles))
        if r.kind == .personal, let first = r.books.first, let why = r.reasons[first.id] { print("      why: \(why)") }
    }
    if let ctx {
        let p = Recommender(stats: stats, context: ctx).profile
        print("profile: genres \(p.topGenres)  themes \(p.topThemes)  evidence \(String(format: "%.1f", p.evidence))")
    }
}

show("NEW READER", nil)
let reader = RecommendationContext(
    library: [fin(find("The Hobbit"), 20, 8, rating: 5), fin(find("Circe"), 30, 12), fin(find("Piranesi"), 12, 4), fin(find("The Night Circus"), 25, 9),
              fin(find("Klara and the Sun"), 15, 6)],
    sessions: [], dismissed: [find("Atomic Habits")], wpm: 250, dailyMinutes: 30, now: now, calendar: cal)
show("FANTASY + LITERARY READER", reader)
