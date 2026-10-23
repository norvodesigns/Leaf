import Foundation
import Observation

/// The first-use tips on this phone (`FirstUseTip`, docs/design/DESIGN_SYSTEM.md §12): which the reader has seen or
/// closed, kept in UserDefaults, and which is out on screen at each place. Screens show theirs with `.firstUseTip(_:)`;
/// the router finishes a tip when the reader does what it says.
///
/// Screenshot runs keep everything in memory and show only the tips named by `-LeafTips` ("session.nook", a list
/// separated by commas, or "all"), so the other shots stay clean.
@MainActor
@Observable
final class FirstUseTips {
    static let shared = FirstUseTips()

    private(set) var journal: FirstUseJournal
    private var stage = FirstUseStage()
    /// This launch: a tip counts once per launch, however often its screen comes and goes.
    @ObservationIgnored private let launch = UUID().uuidString
    @ObservationIgnored private let persists: Bool

    private static let storageKey = "leaf.firstUseTips"

    private init() {
        let options = LaunchOptions.current
        if options.isScripted {
            persists = false
            journal = .only(Self.staged(options.tips))
        } else {
            persists = true
            journal = Self.load() ?? FirstUseJournal()
        }
    }

    /// Whether `tip` is on screen now.
    func isShowing(_ tip: FirstUseTip) -> Bool {
        stage.isShowing(tip, journal: journal)
    }

    /// A screen holding `tip` came into view: it goes out if it is its place's next and the place is free.
    func arrive(_ tip: FirstUseTip) {
        guard stage.arrive(tip, journal: journal, launch: launch) else { return }
        journal.noteShown(tip, launch: launch)
        save()
    }

    /// The screen holding `tip` left.
    func leave(_ tip: FirstUseTip) {
        stage.leave(tip)
    }

    /// Closed, or the reader did what it says: it never shows again.
    func finish(_ tip: FirstUseTip) {
        guard !journal.isDone(tip) else { return }
        journal.finish(tip)
        save()
    }

    /// "Show tips again" in Settings, and erasing everything: each tip shows again as the reader comes to it.
    func reset() {
        journal = FirstUseJournal()
        stage.clear()
        save()
    }

    /// Nothing seen or closed yet.
    var isFresh: Bool { journal.isFresh }

    // MARK: Saving

    private func save() {
        guard persists, let data = try? JSONEncoder().encode(journal) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func load() -> FirstUseJournal? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(FirstUseJournal.self, from: data)
    }

    private static func staged(_ argument: String?) -> Set<FirstUseTip> {
        guard let argument else { return [] }
        if argument == "all" { return Set(FirstUseTip.allCases) }
        return Set(argument.split(separator: ",").compactMap { FirstUseTip(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }
}
