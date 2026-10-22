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
