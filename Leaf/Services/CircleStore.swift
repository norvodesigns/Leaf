import Foundation
import Observation

/// The reader's reading circles, in their own small file beside the library.
///
/// Circles are local for now: friends are added by name and moved along by hand, and nothing here talks to iCloud.
/// They live outside `LeafData` on purpose, so the library's sync and backup formats don't change until a shared
/// version is designed. The model (`ReadingCircle`) already carries stable ids, `updatedAt` stamps and a `remoteID`
/// per member, so that version can take these circles over without the screens changing.
@MainActor
@Observable
final class CircleStore {
    private(set) var circles: [ReadingCircle] = []

    @ObservationIgnored private let url: URL?

    static let shared: CircleStore = {
        let options = LaunchOptions.current
        if options.isScripted {
            let store = CircleStore(url: nil)
            if options.demo, options.scenario != "new" { store.circles = DemoData.circles(now: options.now()) }
            return store
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Leaf", isDirectory: true)
        return CircleStore(url: base.appendingPathComponent("circles.json"))
    }()

    /// The file is there but couldn't be read yet (a launch before the first unlock). Nothing is written over it
    /// until it has been read.
    @ObservationIgnored private var isLoadDeferred = false

    /// `url` nil keeps everything in memory (previews and screenshot runs).
    init(url: URL?, circles: [ReadingCircle] = []) {
        self.url = url
        self.circles = circles
        if url != nil, circles.isEmpty { load() }
    }

    /// Reads the file again if the first try came before the phone was unlocked.
    func loadIfDeferred() {
        if isLoadDeferred { load() }
    }

    private func load() {
        guard let url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            isLoadDeferred = false
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            isLoadDeferred = true
            return
        }
        isLoadDeferred = false
        if let saved = try? JSONDecoder().decode([ReadingCircle].self, from: data) {
            circles = saved
        } else {
            // Keep a file this version can't read for recovery, rather than saving an empty list over it.
            let stamp = Int(Date().timeIntervalSince1970)
            try? FileManager.default.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("damaged-\(stamp).json"))
        }
    }

    // MARK: Reading

    func circle(_ id: UUID) -> ReadingCircle? { circles.first { $0.id == id } }

    /// The club shelf: circles under way, soonest meeting first, then the ones put away, most recent first.
    func shelf(now: Date) -> [ReadingCircle] {
        let open = circles.filter { !$0.isArchived }.sorted { lhs, rhs in
            let a = lhs.meetings.map(\.date).filter { $0 >= Calendar.current.startOfDay(for: now) }.min() ?? .distantFuture
            let b = rhs.meetings.map(\.date).filter { $0 >= Calendar.current.startOfDay(for: now) }.min() ?? .distantFuture
            return a == b ? lhs.createdAt < rhs.createdAt : a < b
        }
        let away = circles.filter(\.isArchived).sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
        return open + away
    }

    // MARK: Changes

    @discardableResult
    func create(name: String, book: Book, startsOn: Date, meetings: [CircleMeeting], friends: [String], myName: String = "You", now: Date = Date()) -> ReadingCircle {
        let me = CircleMember(name: myName, kind: .me, paletteToken: CozyPalette.matcha, updatedAt: now)
        let tokens = Self.friendTokens
        let others = friends
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { CircleMember(name: $1, paletteToken: tokens[$0 % tokens.count], updatedAt: now) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        loadIfDeferred()
        let circle = ReadingCircle(
            name: trimmed.isEmpty ? "\(book.title) circle" : trimmed,
            book: book,
            startsOn: startsOn,
            meetings: CirclePlanner.normalized(meetings, pages: book.pages),
            members: [me] + others,
            createdAt: now
        )
        circles.append(circle)
        save()
        return circle
    }

    func update(_ circle: ReadingCircle, now: Date = Date()) {
        loadIfDeferred()
        guard let index = circles.firstIndex(where: { $0.id == circle.id }) else { return }
        var circle = circle
        circle.meetings = CirclePlanner.normalized(circle.meetings, pages: circle.book.pages)
        circle.updatedAt = now
        circles[index] = circle
        save()
    }

    func setPage(_ page: Int, member memberID: UUID, in circleID: UUID, now: Date = Date()) {
        edit(circleID, now: now) { circle in
            guard let index = circle.members.firstIndex(where: { $0.id == memberID }) else { return }
            circle.members[index].page = min(max(0, page), circle.book.pages)
            circle.members[index].updatedAt = now
        }
    }

    func renameMember(_ memberID: UUID, to name: String, in circleID: UUID, now: Date = Date()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        edit(circleID, now: now) { circle in
            guard let index = circle.members.firstIndex(where: { $0.id == memberID }) else { return }
            circle.members[index].name = trimmed
            circle.members[index].updatedAt = now
        }
    }

    func addFriend(_ name: String, to circleID: UUID, now: Date = Date()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        edit(circleID, now: now) { circle in
            let token = Self.friendTokens[circle.friends.count % Self.friendTokens.count]
            circle.members.append(CircleMember(name: trimmed, paletteToken: token, updatedAt: now))
        }
    }

    func removeMember(_ memberID: UUID, from circleID: UUID, now: Date = Date()) {
        edit(circleID, now: now) { circle in
            circle.members.removeAll { $0.id == memberID && $0.kind != .me }
        }
    }

    func setArchived(_ archived: Bool, _ circleID: UUID, now: Date = Date()) {
        edit(circleID, now: now) { $0.archivedAt = archived ? now : nil }
    }

    func delete(_ circleID: UUID) {
        loadIfDeferred()
        circles.removeAll { $0.id == circleID }
        save()
    }

    /// Erase everything (Settings › Erase all data).
    func eraseAll() {
        circles = []
        isLoadDeferred = false
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Internals

    /// Friends' rings, in the order they're handed out. The reader is always matcha, Leaf's own green.
    static let friendTokens = [CozyPalette.chai, CozyPalette.rooibos, CozyPalette.steam, CozyPalette.amber, CozyPalette.rose]

    private func edit(_ circleID: UUID, now: Date, _ change: (inout ReadingCircle) -> Void) {
        loadIfDeferred()
        guard let index = circles.firstIndex(where: { $0.id == circleID }) else { return }
        change(&circles[index])
        circles[index].updatedAt = now
        save()
    }

    private func save() {
        guard let url, !isLoadDeferred else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(circles)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // A failed write keeps the circles in memory; the next change tries again.
        }
    }
}
