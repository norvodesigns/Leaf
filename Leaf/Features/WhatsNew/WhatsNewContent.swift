import Foundation

/// One release's news: what changed, a line each. Newest first in `WhatsNew.releases`; a future release adds an
/// entry at the top and nothing else.
struct WhatsNewRelease: Identifiable, Hashable {
    struct Item: Hashable {
        var title: String
        var line: String
    }

    /// Stable, and remembered on the device once shown ("2026-10").
    var id: String
    /// The headline at the top of the sheet.
    var title: String
    var items: [Item]
}

enum WhatsNew {
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            id: "2026-10",
            title: "A fuller nook.",
            items: [
                .init(title: "Today, as a nook", line: "The day’s light, your book and a cup that fills as you read. Steep your tea first, or begin straight away."),
                .init(title: "Where are you?", line: "Tell Leaf your page as a number, a percentage, or with a pull of the ribbon."),
                .init(title: "Reading times", line: "As many a day as you like, each with a book of its own."),
                .init(title: "Something to read next", line: "A deck to swipe through and bigger rows to browse, from a quarter of a million books."),
                .init(title: "The forecast", line: "When you’ll finish, as a range, with what-ifs to try."),
                .init(title: "Insights", line: "Your year in books, challenges to join and the stamps you earn."),
                .init(title: "Your reading history", line: "A reading log, each book’s timeline, quote cards to share and a backup you keep."),
                .init(title: "A wall of spines", line: "Every book you’ve finished on a shelf, and in December, your year played back."),
                .init(title: "Sounds, if you want them", line: "Rain, a fire, a kettle, a café or a library. Nothing plays until you choose."),
                .init(title: "On the Lock Screen", line: "A Live Activity for the cup you’re reading, and Shortcuts to start one."),
                .init(title: "iCloud", line: "Your library on every device you sign in to."),
                .init(title: "Apple Watch", line: "A rebuilt watch app, with complications for the day’s reading and your timer in the Smart Stack."),
            ]
        ),
    ]

    static var releaseIDs: [String] { releases.map(\.id) }

    static func release(id: String) -> WhatsNewRelease? { releases.first { $0.id == id } }

    /// The build running now, from Info.plist.
    static var currentBuild: AppBuild {
        let info = Bundle.main.infoDictionary
        return AppBuild(
            version: info?["CFBundleShortVersionString"] as? String ?? "1.0",
            build: info?["CFBundleVersion"] as? String ?? ""
        )
    }

    // MARK: Remembering

    private static let stateKey = "leaf.whatsNew.state"

    static func loadState() -> WhatsNewGate.State? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(WhatsNewGate.State.self, from: data)
    }

    static func saveState(_ state: WhatsNewGate.State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }
}

/// The tour's coach marks, in order. Each id is also the anchor the mark points at.
enum TourSteps {
    static let all: [TourStep] = [
        TourStep(id: "today.nook", area: .today, title: "Your nook", text: "The day’s light, the book on the table, and a cup that fills as the day’s minutes come in."),
        TourStep(id: "today.steep", area: .today, title: "Steep and read", text: "Steep your tea and Leaf counts it down, then a cup of reading. Or begin straight away."),
        TourStep(id: "today.page", area: .today, title: "Your page", text: "Tap the page to tell Leaf where you are, whenever it has drifted."),
        TourStep(id: "today.times", area: .today, title: "Reading times", text: "A few times a day, each with its own book. Leaf plans around them."),
        TourStep(id: "library.shelves", area: .library, title: "Your shelves", text: "Reading, To read and Finished. Finished can also be a wall of spines."),
        TourStep(id: "library.hold", area: .library, title: "Hold to move", text: "Hold a book to move it to another shelf, or to change the order you’ll read in."),
        TourStep(id: "plan.forecast", area: .plan, title: "When you’ll finish", text: "A range, not a promise: the likely day, and how early or late it could be."),
        TourStep(id: "plan.whatif", area: .plan, title: "What if", text: "Try a few more minutes, or another day, and watch the dates move."),
        TourStep(id: "search.rows", area: .search, title: "Rows to browse", text: "Shelves picked for you. Each book says why it’s there, and “Not for me” teaches Leaf what to skip."),
        TourStep(id: "search.deck", area: .search, title: "The deck", text: "One book at a time: keep it, or pass."),
        TourStep(id: "settings.times", area: .settings, title: "Reading times and pace", text: "Your daily minutes, the days you read and your reading times live here.", canFloat: true),
        TourStep(id: "settings.tea", area: .settings, title: "Tea and sound", text: "Your cup length, your teas, and the sounds, all off until you turn them on.", canFloat: true),
        TourStep(id: "settings.cloud", area: .settings, title: "iCloud", text: "Keeps your library the same on every device you use.", canFloat: true),
    ]
}
