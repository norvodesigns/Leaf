import Foundation

/// The reader's reading circles, as the circle screens see them.
///
/// Circles live in the library (`LeafData.circles`), so they are in the library file and its rolling backup, in
/// exported backups, and in iCloud sync when that is on (as `LeafCircle` records). This is a thin view over
/// `LibraryStore` that keeps the circle rules (normalised schedules, who can be removed, palette tokens) in one place;
/// each change is stamped here and saved through the store, which records the deletions other devices need.
///
/// Before 2026-10-22 circles had their own `circles.json` beside the library. `importLegacyFile(into:)` moves such a
/// file in once, with the sync merge rules, and keeps the old file renamed until "Erase all data".
@MainActor
struct CircleStore {
    let library: LibraryStore

    init(library: LibraryStore) {
        self.library = library
    }

    var circles: [ReadingCircle] { library.data.circles }

    /// Finishes moving an old circles.json in if the first try came before the phone was unlocked.
    func loadIfDeferred() {
        Self.importLegacyFile(into: library)
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
        let circle = ReadingCircle(
            name: trimmed.isEmpty ? "\(book.title) circle" : trimmed,
            book: book,
            startsOn: startsOn,
            meetings: CirclePlanner.normalized(meetings, pages: book.pages),
            members: [me] + others,
            createdAt: now
        )
        library.saveCircle(circle)
        return circle
    }

    func update(_ circle: ReadingCircle, now: Date = Date()) {
        guard self.circle(circle.id) != nil else { return }
        var circle = circle
        circle.meetings = CirclePlanner.normalized(circle.meetings, pages: circle.book.pages)
        circle.updatedAt = now
        library.saveCircle(circle)
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
        library.deleteCircle(circleID)
    }

    // MARK: The old circles.json

    /// Where circles lived before they joined the library.
    nonisolated static var legacyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Leaf", isDirectory: true)
            .appendingPathComponent("circles.json")
    }

    /// The old file once its circles are in the library. Kept for recovery until "Erase all data".
    nonisolated static var importedURL: URL {
        legacyURL.deletingLastPathComponent().appendingPathComponent("circles.imported.json")
    }

    /// Moves the circles of an old circles.json into the library, once. Does nothing while the library itself is
    /// not readable yet (its stand-in would be saved over it), or while the file can't be read before the first
    /// unlock; call again later. A file this version can't decode is set aside, never deleted.
    static func importLegacyFile(into library: LibraryStore, from url: URL = legacyURL, importedTo done: URL = importedURL) {
        guard !library.isLoadDeferred, FileManager.default.fileExists(atPath: url.path) else { return }
        guard let bytes = try? Data(contentsOf: url) else { return }
        guard let saved = try? JSONDecoder().decode([ReadingCircle].self, from: bytes) else {
            let stamp = Int(Date().timeIntervalSince1970)
            try? FileManager.default.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("damaged-\(stamp).json"))
            return
        }
        library.mergeCircles(saved)
        library.flush()
        try? FileManager.default.removeItem(at: done)
        try? FileManager.default.moveItem(at: url, to: done)
    }

    /// Erase everything (Settings › Erase all data). The circles themselves go with the library; this removes the old
    /// file and its imported copy.
    static func eraseLegacyFiles() {
        try? FileManager.default.removeItem(at: legacyURL)
        try? FileManager.default.removeItem(at: importedURL)
    }

    // MARK: Internals

    /// Friends' rings, in the order they're handed out. The reader is always matcha, Leaf's own green.
    static let friendTokens = [CozyPalette.chai, CozyPalette.rooibos, CozyPalette.steam, CozyPalette.amber, CozyPalette.rose]

    private func edit(_ circleID: UUID, now: Date, _ change: (inout ReadingCircle) -> Void) {
        guard var circle = circle(circleID) else { return }
        change(&circle)
        circle.updatedAt = now
        library.saveCircle(circle)
    }
}

extension LibraryStore {
    /// The reader's reading circles and the changes the circle screens make.
    var circleStore: CircleStore { CircleStore(library: self) }
}
