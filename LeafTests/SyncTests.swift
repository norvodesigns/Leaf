import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Fixtures

/// Everything the sync tests share, in one namespace so nothing collides with other test files.
private enum SyncFixtures {
    static let origin = Date(timeIntervalSince1970: 1_800_000_000)
    static func at(_ seconds: Double) -> Date { origin.addingTimeInterval(seconds) }
    /// A `now` far enough from `origin` that nothing is pruned by accident, but close enough that 90 days is clear.
    static let now = at(10_000)

    static func book(_ id: String, pages: Int = 300) -> Book {
        Book(id: id, title: id.uppercased(), author: "Author", pages: pages, words: pages * 270)
    }

    static func item(
        _ id: String,
        shelf: Shelf = .reading,
        page: Int = 0,
        pages: Int = 300,
        order: Double = 1,
        updated: Double = 0,
        started: Double? = -5_000
    ) -> LibraryItem {
        LibraryItem(
            book: book(id, pages: pages), shelf: shelf, currentPage: page, order: order,
            addedAt: at(-6_000), startedAt: shelf == .toRead ? nil : started.map(at), updatedAt: at(updated)
        )
    }

    static func session(
        _ book: String,
        id: UUID = UUID(),
        start: Double = 0,
        seconds: Double = 600,
        from: Int = 0,
        to: Int
    ) -> ReadingSession {
        ReadingSession(id: id, bookID: book, startedAt: at(start), seconds: seconds, fromPage: from, toPage: to)
    }

    static func data(
        items: [LibraryItem] = [],
        sessions: [ReadingSession] = [],
        journal: [JournalEntry] = [],
        dismissed: [String] = [],
        challenges: [ChallengeEnrollment] = [],
        tombstones: [Tombstone] = [],
        speedTests: [SpeedTestResult] = [],
        prefs: ReadingPreferences = ReadingPreferences()
    ) -> LeafData {
        var d = LeafData()
        d.items = items
        d.sessions = sessions
        d.journal = journal
        d.dismissed = dismissed
        d.challenges = challenges
        d.tombstones = tombstones
        d.speedTests = speedTests
        d.preferences = prefs
        return d
    }

    static func tomb(_ kind: Tombstone.Kind, _ key: String, _ seconds: Double) -> Tombstone {
        Tombstone(kind: kind, key: key, deletedAt: at(seconds))
    }

    /// Two states are "the same" to the cloud when everything that syncs matches. The live session and the device's
    /// own settings are the two things that legitimately differ between replicas.
    /// `settled` puts the arrays in the canonical order first. A device that has not merged anything lately still
    /// holds its own insertion order, which is the same content in a different order.
    static func canon(_ data: LeafData, ignoringPreferenceStamp: Bool = false, settled: Bool = false) throws -> String {
        var copy = settled ? data.merged(with: LeafData(), now: now) : data
        copy.activeSession = nil
        copy.preferences = copy.preferences.syncNormalized
        if ignoringPreferenceStamp { copy.preferences.updatedAt = .distantPast }
        // A Set encodes in iteration order, which is not stable, so the days are compared sorted.
        let days = copy.preferences.readingDays.sorted()
        copy.preferences.readingDays = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(copy), as: UTF8.self) + "|days:\(days)"
    }

    static func uuid(_ rng: inout SeededGenerator) -> UUID {
        func hex(_ value: UInt64) -> String {
            let text = String(value, radix: 16, uppercase: true)
            return String(repeating: "0", count: 16 - text.count) + text
        }
        let a = hex(rng.next())
        let b = hex(rng.next())
        let all = Array(a + b)
        let text = String(all[0..<8]) + "-" + String(all[8..<12]) + "-" + String(all[12..<16]) + "-" + String(all[16..<20]) + "-" + String(all[20..<32])
        return UUID(uuidString: text) ?? UUID()
    }
}

// MARK: - Random replicas

/// A small stand-in for `LibraryStore`: random edits that stamp, delete and re-add the way the store does, so the
/// property tests exercise realistic histories without needing the app target.
private struct SyncReplica {
    var data: LeafData
    var rng: SeededGenerator
    var clock: Double
    /// What `LibraryStore.updatePreferences` does today: every preference edit moves the stamp, even haptics. The
    /// recommended behaviour (the default here) leaves the stamp alone for edits only this device cares about.
    var stampsDeviceOnlyEdits = false
    static let catalog: [Book] = [20, 60, 120, 200, 300, 400, 90, 250].enumerated().map { SyncFixtures.book("b\($0.offset)", pages: $0.element) }

    init(data: LeafData, seed: UInt64, clock: Double = 0) {
        self.data = data
        self.rng = SeededGenerator(seed: seed)
        self.clock = clock
    }

    private mutating func pick(_ count: Int) -> Int { count <= 0 ? 0 : Int(rng.next() % UInt64(count)) }

    /// Time moves forward by zero to two seconds, so replicas often stamp at exactly the same moment.
    private mutating func stamp() -> Date {
        clock += Double(rng.next() % 3)
        return SyncFixtures.at(clock)
    }

    private func nextOrder(on shelf: Shelf) -> Double { (data.items.filter { $0.shelf == shelf }.map(\.order).max() ?? 0) + 1 }

    mutating func step() {
        switch pick(22) {
        case 0, 1: addBook()
        case 2: moveBook()
        case 3: setPage()
        case 4: rate()
        case 5: removeBook()
        case 6, 7, 8: logSession()
        case 9: addJournal()
        case 10: editJournal()
        case 11: deleteJournal()
        case 12: dismiss()
        case 13: undismiss()
        case 14: challenge()
        case 15: speedTest()
        case 16: preferences()
        case 18: cabinetTea()
        case 19: tasting()
        case 20: deleteTeaOrTasting()
        case 21: removeRead()
        default: touchBook()
        }
    }

    private mutating func addBook() {
        let book = SyncReplica.catalog[pick(SyncReplica.catalog.count)]
        let shelf: Shelf = [.reading, .toRead, .finished, .paused][pick(4)]
        let now = stamp()
        if let index = data.items.firstIndex(where: { $0.id == book.id }) {
            data.items[index].updatedAt = now
            return
        }
        var item = LibraryItem(book: book, shelf: shelf, order: nextOrder(on: shelf), addedAt: now)
        if shelf == .reading || shelf == .paused { item.startedAt = now }
        if shelf == .paused { item.pausedAt = now }
        if shelf == .finished {
            item.finishedAt = now
            item.currentPage = book.pages
        }
        item.updatedAt = now
        data.tombstones.removeAll { $0.kind == .item && $0.key == book.id }
        data.items.append(item)
    }

    private mutating func moveBook() {
        guard !data.items.isEmpty else { return }
        let index = pick(data.items.count)
        let shelf: Shelf = [.reading, .toRead, .finished, .paused][pick(4)]
        guard data.items[index].shelf != shelf else { return }
        let now = stamp()
        // As the store does: leaving Finished keeps the finish as a read-through.
        data.items[index] = data.items[index].keepingCurrentRead(now: now)
        data.items[index].shelf = shelf
        data.items[index].order = nextOrder(on: shelf)
        data.items[index].updatedAt = now
        data.items[index].pausedAt = shelf == .paused ? now : nil
        switch shelf {
        case .reading:
            if data.items[index].startedAt == nil { data.items[index].startedAt = now }
            data.items[index].finishedAt = nil
            if data.items[index].currentPage >= data.items[index].book.pages { data.items[index].currentPage = 0 }
        case .toRead:
            data.items[index].finishedAt = nil
        case .finished:
            data.items[index].finishedAt = now
            data.items[index].currentPage = data.items[index].book.pages
            data.items[index].positionConfirmed = true
        case .paused:
            data.items[index].finishedAt = nil
        }
        if data.activeSession?.bookID == data.items[index].id, shelf == .paused { data.activeSession = nil }
    }

    private mutating func setPage() {
        guard !data.items.isEmpty else { return }
        let index = pick(data.items.count)
        data.items[index].currentPage = pick(data.items[index].book.pages + 1)
        data.items[index].positionConfirmed = true
        data.items[index].updatedAt = stamp()
    }

    private mutating func rate() {
        guard !data.items.isEmpty else { return }
        let index = pick(data.items.count)
        data.items[index].rating = 1 + pick(5)
        data.items[index].updatedAt = stamp()
    }

    private mutating func touchBook() {
        guard !data.items.isEmpty else { return }
        let index = pick(data.items.count)
        data.items[index].order = Double(pick(6))
        data.items[index].updatedAt = stamp()
    }

    private mutating func removeBook() {
        guard !data.items.isEmpty else { return }
        let index = pick(data.items.count)
        let id = data.items[index].id
        let now = stamp()
        data.items.remove(at: index)
        if data.activeSession?.bookID == id { data.activeSession = nil }
        data.tombstones.removeAll { $0.kind == .item && $0.key == id }
        data.tombstones.append(Tombstone(kind: .item, key: id, deletedAt: now))
    }

    private mutating func logSession() {
        guard !data.items.isEmpty else { return }
        let index = pick(data.items.count)
        let now = stamp()
        let seconds = Double(20 + pick(40))
        let from = data.items[index].currentPage
        let pages = data.items[index].book.pages
        let to = min(pages, from + 1 + pick(60))
        let session = ReadingSession(
            id: SyncFixtures.uuid(&rng), bookID: data.items[index].id, startedAt: now.addingTimeInterval(-seconds),
            seconds: seconds, fromPage: from, toPage: to
        )
        data.sessions.append(session)
        data.items[index].currentPage = max(from, to)
        data.items[index].positionConfirmed = true
        data.items[index].updatedAt = now
        if data.items[index].shelf == .toRead || data.items[index].shelf == .paused {
            data.items[index].shelf = .reading
            data.items[index].pausedAt = nil
            data.items[index].order = nextOrder(on: .reading)
        }
        if data.items[index].startedAt == nil { data.items[index].startedAt = session.startedAt }
        if to >= pages {
            data.items[index].shelf = .finished
            data.items[index].finishedAt = now
        }
    }

    private mutating func addJournal() {
        let book = SyncReplica.catalog[pick(SyncReplica.catalog.count)]
        let now = stamp()
        data.journal.append(JournalEntry(
            id: SyncFixtures.uuid(&rng), bookID: book.id, bookTitle: book.title, bookAuthor: book.author,
            kind: pick(2) == 0 ? .thought : .quote, text: "note \(pick(1000))", createdAt: now
        ))
    }

    private mutating func editJournal() {
        guard !data.journal.isEmpty else { return }
        let index = pick(data.journal.count)
        data.journal[index].text = "edited \(pick(1000))"
        data.journal[index].isFavorite = pick(2) == 0
        data.journal[index].updatedAt = stamp()
    }

    private mutating func deleteJournal() {
        guard !data.journal.isEmpty else { return }
        let index = pick(data.journal.count)
        let id = data.journal[index].id
        let now = stamp()
        data.journal.remove(at: index)
        data.tombstones.removeAll { $0.kind == .journal && $0.key == id.uuidString }
        data.tombstones.append(Tombstone(kind: .journal, key: id.uuidString, deletedAt: now))
    }

    /// Adds a tin or edits one (stock, rating), the way the cabinet does.
    private mutating func cabinetTea() {
        let now = stamp()
        if !data.cabinet.isEmpty, pick(2) == 0 {
            let index = pick(data.cabinet.count)
            data.cabinet[index].isOutOf.toggle()
            data.cabinet[index].rating = 1 + pick(5)
            data.cabinet[index].updatedAt = now
            return
        }
        let tea = TeaCatalog.all[pick(TeaCatalog.all.count)]
        data.cabinet.append(CabinetTea(id: SyncFixtures.uuid(&rng), catalogID: pick(3) == 0 ? nil : tea.id, name: tea.name, family: tea.family, steepSeconds: tea.steepSeconds, addedAt: now))
    }

    private mutating func tasting() {
        let now = stamp()
        if !data.tastings.isEmpty, pick(2) == 0 {
            let index = pick(data.tastings.count)
            data.tastings[index].rating = 1 + pick(5)
            data.tastings[index].aromas = [TastingAroma.all[pick(TastingAroma.all.count)]]
            data.tastings[index].updatedAt = now
            return
        }
        let tea = TeaCatalog.all[pick(TeaCatalog.all.count)]
        data.tastings.append(TastingNote(id: SyncFixtures.uuid(&rng), teaID: tea.id, teaName: tea.name, family: tea.family, strength: .justRight, createdAt: now))
    }

    private mutating func deleteTeaOrTasting() {
        let now = stamp()
        if pick(2) == 0, !data.cabinet.isEmpty {
            let id = data.cabinet.remove(at: pick(data.cabinet.count)).id.uuidString
            data.tombstones.removeAll { $0.kind == .cabinetTea && $0.key == id }
            data.tombstones.append(Tombstone(kind: .cabinetTea, key: id, deletedAt: now))
        } else if !data.tastings.isEmpty {
            let id = data.tastings.remove(at: pick(data.tastings.count)).id.uuidString
            data.tombstones.removeAll { $0.kind == .tasting && $0.key == id }
            data.tombstones.append(Tombstone(kind: .tasting, key: id, deletedAt: now))
        }
    }

    /// Takes an earlier read-through off a book, with a tombstone, as the store does.
    private mutating func removeRead() {
        guard let index = data.items.indices.first(where: { !data.items[$0].reads.isEmpty }) else { return }
        let read = data.items[index].reads[pick(data.items[index].reads.count)]
        let now = stamp()
        data.items[index].reads.removeAll { $0.id == read.id }
        data.items[index].updatedAt = now
        data.tombstones.removeAll { $0.kind == .read && $0.key == read.id.uuidString }
        data.tombstones.append(Tombstone(kind: .read, key: read.id.uuidString, deletedAt: now))
    }

    private mutating func dismiss() {
        let id = SyncReplica.catalog[pick(SyncReplica.catalog.count)].id
        guard !data.dismissed.contains(id) else { return }
        data.dismissed.append(id)
        data.tombstones.removeAll { $0.kind == .dismissal && $0.key == id }
    }

    private mutating func undismiss() {
        guard !data.dismissed.isEmpty else { return }
        let id = data.dismissed[pick(data.dismissed.count)]
        let now = stamp()
        data.dismissed.removeAll { $0 == id }
        data.tombstones.removeAll { $0.kind == .dismissal && $0.key == id }
        data.tombstones.append(Tombstone(kind: .dismissal, key: id, deletedAt: now))
    }

    private mutating func challenge() {
        let id = ["autumn", "spring"][pick(2)]
        let year: Int? = [nil, 2026][pick(2)]
        let now = stamp()
        // The tombstone names the year, so leaving 2026 never touches 2025 (the store should key it this way too).
        let key = SyncKey.challengeTombstoneKey(id: id, year: year)
        if data.challenges.contains(where: { $0.id == id && $0.year == year }) {
            data.challenges.removeAll { $0.id == id && $0.year == year }
            data.tombstones.removeAll { $0.kind == .challenge && $0.key == key }
            data.tombstones.append(Tombstone(kind: .challenge, key: key, deletedAt: now))
        } else {
            data.challenges.append(ChallengeEnrollment(id: id, joinedAt: now, year: year))
            data.tombstones.removeAll { $0.kind == .challenge && $0.key == key }
        }
    }

    private mutating func speedTest() {
        let now = stamp()
        let passage = "p\(pick(3))"
        // The store never records two tests of one passage in the same moment.
        guard !data.speedTests.contains(where: { $0.passageID == passage && $0.date == now }) else { return }
        data.speedTests.append(SpeedTestResult(date: now, passageID: passage, words: 200 + pick(50), seconds: 40 + Double(pick(30)), correct: 3, total: 4))
    }

    private mutating func preferences() {
        let now = stamp()
        let before = data.preferences
        switch pick(6) {
        case 0: data.preferences.wpm = Double(150 + pick(300))
        case 1: data.preferences.dailyMinutes = 5 + pick(60)
        case 2: data.preferences.hapticsLevel = [.full, .subtle, .off][pick(3)]
        case 3: data.preferences.appearance = [.system, .day, .night][pick(3)]
        case 4: data.preferences.syncEnabled = pick(2) == 0
        default:
            data.preferences.hasOnboarded = true
            data.preferences.onboardedAt = data.preferences.onboardedAt ?? now
        }
        if stampsDeviceOnlyEdits || !before.hasSameSyncedFields(as: data.preferences) { data.preferences.updatedAt = now }
    }
}

/// A pretend CloudKit zone plus the two or three devices talking to it, using only the pure sync code. It follows
/// the transport's design: a queue of names (not a recomputed diff), the merged state adopted as it is, and a
/// save-back only for what the server is behind on.
private struct SyncSimulation {
    struct Device {
        var replica: SyncReplica
        var pendingSaves = Set<String>()
        var pendingDeletes = Set<String>()
        var lastSeen: [String: SyncRecord] = [:]

        /// Runs `steps` random edits, queueing what each one changed (the transport's `localDataChanged`).
        mutating func edit(steps: Int) {
            for _ in 0..<steps {
                let before = replica.data
                replica.step()
                let changes = SyncDiff.changes(from: before, to: replica.data)
                for name in changes.saves { pendingSaves.insert(name); pendingDeletes.remove(name) }
                for name in changes.deletes { pendingDeletes.insert(name); pendingSaves.remove(name) }
            }
        }

        /// Adopts fetched records the way the transport does.
        mutating func receive(_ records: [SyncRecord], removed: [String], now: Date) {
            let removedTombstones: [SyncTombstoneKey] = removed.compactMap { text in
                if case .tombstone(let kind, let key)? = SyncRecordName(text) { return SyncTombstoneKey(kind: kind, key: key) }
                return nil
            }
            let base = replica.data.removingTombstones(removedTombstones)
            let delta = SyncRecordMapper.delta(from: records, basedOn: base)
            let merged = base.merged(with: delta, now: now)
            let behind = Set(SyncDiff.behind(fetched: records.map(\.name), remote: delta, merged: merged))
            replica.data = merged
            for name in SyncDiff.restorable(deleted: removed, in: merged) {
                pendingSaves.insert(name)
                pendingDeletes.remove(name)
            }
            for record in records {
                if behind.contains(record.name) {
                    pendingSaves.insert(record.name)
                    pendingDeletes.remove(record.name)
                } else {
                    pendingSaves.remove(record.name)
                }
            }
        }

        mutating func push(to server: inout [String: SyncRecord], now: Date) {
            for name in pendingDeletes.sorted() {
                server[name] = nil
                lastSeen[name] = nil
            }
            pendingDeletes = []
            var rounds = 0
            while !pendingSaves.isEmpty, rounds < 50 {
                rounds += 1
                let names = pendingSaves.sorted()
                pendingSaves = []
                let snapshot = SyncSnapshot(replica.data)
                for name in names {
                    guard let entity = snapshot[name], let record = SyncRecordMapper.record(for: entity) else { continue }
                    if let current = server[name], current != lastSeen[name] {
                        // The server moved on since this device last saw the record: serverRecordChanged.
                        lastSeen[name] = current
                        receive([current], removed: [], now: now)
                    } else {
                        server[name] = record
                        lastSeen[name] = record
                    }
                }
            }
        }

        mutating func fetch(from server: [String: SyncRecord], now: Date) {
            let modified = server.filter { lastSeen[$0.key] != $0.value }.map(\.value).sorted { $0.name < $1.name }
            let removed = lastSeen.keys.filter { server[$0] == nil }.sorted()
            for record in modified { lastSeen[record.name] = record }
            for name in removed { lastSeen[name] = nil }
            if !modified.isEmpty || !removed.isEmpty { receive(modified, removed: removed, now: now) }
        }
    }

    var server: [String: SyncRecord] = [:]
    var devices: [Device]

    init(base: LeafData, seeds: [UInt64], clock: Double = 0, stampsDeviceOnlyEdits: Bool = false) {
        var records: [String: SyncRecord] = [:]
        for record in SyncRecordMapper.records(from: base) { records[record.name] = record }
        server = records
        devices = seeds.map { seed in
            var replica = SyncReplica(data: base, seed: seed, clock: clock)
            replica.stampsDeviceOnlyEdits = stampsDeviceOnlyEdits
            var device = Device(replica: replica)
            device.lastSeen = records
            return device
        }
    }

    /// Lets the devices push and fetch until nothing moves. Returns the number of rounds used.
    mutating func settle(now: Date) -> Int {
        for round in 1...12 {
            for index in devices.indices { devices[index].push(to: &server, now: now) }
            for index in devices.indices { devices[index].fetch(from: server, now: now) }
            let quiet = devices.allSatisfy { $0.pendingSaves.isEmpty && $0.pendingDeletes.isEmpty && $0.lastSeen == server }
            if quiet { return round }
        }
        return 12
    }
}

// MARK: - Record names

struct SyncRecordNameTests {
    private let names: [SyncRecordName] = [
        .item("OL123W"), .item("custom-3F2504E0-4F89-11D3-9A0C-0305E82C3301"), .item(""), .item("a.b%c d/é"),
        .session(UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID()),
        .journal(UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8") ?? UUID()),
        .preferences,
        .speedTest(SyncKey.speedTestKey(date: SyncFixtures.origin, passageID: "passage 1/é")),
        .dismissal("OL9.W"), .dismissal("ünï"),
        .challenge(id: "autumn-2026", year: 2026), .challenge(id: "cozy.winter", year: nil), .challenge(id: "x", year: -1),
        .tombstone(.item, "OL123W"), .tombstone(.journal, "3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
        .tombstone(.dismissal, "a.b"), .tombstone(.challenge, SyncKey.challengeTombstoneKey(id: "autumn", year: 2026)),
    ]

    @Test func everyNameReadsBackAsItself() {
        for name in names {
            #expect(SyncRecordName(name.string) == name, "\(name.string)")
        }
    }

    @Test func namesAreAsciiAndShortEnoughForCloudKit() {
        for name in names {
            #expect(name.string.utf8.allSatisfy { $0 < 0x80 && $0 > 0x20 }, "\(name.string)")
            #expect(name.isValid)
            #expect(!name.string.hasPrefix("_"))
        }
    }

    @Test func plainIdsKeepTheDocumentedShape() {
        #expect(SyncRecordName.item("OL123W").string == "item.OL123W")
        #expect(SyncRecordName.preferences.string == "prefs")
        #expect(SyncRecordName.dismissal("OL9W").string == "dismissal.OL9W")
        #expect(SyncRecordName.tombstone(.item, "OL123W").string == "tombstone.item.OL123W")
        #expect(SyncRecordName.challenge(id: "autumn", year: 2026).string == "challenge.autumn.2026")
        #expect(SyncRecordName.challenge(id: "autumn", year: nil).string == "challenge.autumn.none")
        let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID()
        #expect(SyncRecordName.session(id).string == "session.3F2504E0-4F89-11D3-9A0C-0305E82C3301")
    }

    @Test func escapingNeverProducesADotOrNonAscii() {
        var rng = SeededGenerator(seed: 7)
        let alphabet = Array("abcXYZ019 .%/_-é日本\u{0}\u{1F4DA}~#?&")
        for _ in 0..<300 {
            let length = Int(rng.next() % 12)
            let text = String((0..<length).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
            let escaped = SyncKey.escape(text)
            #expect(!escaped.contains("."))
            #expect(escaped.utf8.allSatisfy { $0 < 0x80 })
            #expect(SyncKey.unescape(escaped) == text, "\(text)")
        }
    }

    @Test func malformedEscapesAreRejected() {
        #expect(SyncKey.unescape("%") == nil)
        #expect(SyncKey.unescape("%4") == nil)
        #expect(SyncKey.unescape("%ZZ") == nil)
        #expect(SyncKey.unescape("%FF") == nil, "a lone 0xFF is not valid UTF-8")
        #expect(SyncKey.unescape("plain-text_1") == "plain-text_1")
    }

    @Test func namesThisVersionDidNotWriteAreNil() {
        for text in ["", "foo", "item", "session.not-a-uuid", "journal.", "challenge.x.abc", "challenge.noyear",
                     "tombstone.bogus.x", "tombstone.item", "dismissal.%", "item.%G1", "prefs.extra"] {
            #expect(SyncRecordName(text) == nil, "\(text)")
        }
    }

    @Test func overlongNamesAreInvalidAndNeverQueued() {
        let long = String(repeating: "x", count: 300)
        #expect(!SyncRecordName.item(long).isValid)
        var data = LeafData()
        data.items = [SyncFixtures.item(long), SyncFixtures.item("ok")]
        let snapshot = SyncSnapshot(data)
        #expect(snapshot.names.contains("item.ok"))
        #expect(!snapshot.names.contains(SyncRecordName.item(long).string))
        let entity = SyncEntity.item(SyncFixtures.item(long))
        #expect(SyncRecordMapper.record(for: entity) == nil)
    }

    @Test func speedTestKeysAreStableAndSurviveOddDates() {
        let date = SyncFixtures.at(5)
        #expect(SyncKey.speedTestKey(date: date, passageID: "p1") == SyncKey.speedTestKey(date: date.addingTimeInterval(0.0002), passageID: "p1"))
        #expect(SyncKey.speedTestKey(date: date, passageID: "p1") != SyncKey.speedTestKey(date: date, passageID: "p2"))
        #expect(SyncKey.speedTestKey(date: date, passageID: "p1") != SyncKey.speedTestKey(date: date.addingTimeInterval(1), passageID: "p1"))
        // Nothing here may trap.
        _ = SyncKey.speedTestKey(date: .distantFuture, passageID: "")
        _ = SyncKey.speedTestKey(date: .distantPast, passageID: "")
        _ = SyncKey.speedTestKey(date: Date(timeIntervalSince1970: .nan), passageID: "")
        _ = SyncKey.speedTestKey(date: Date(timeIntervalSince1970: .infinity), passageID: "")
    }
}

// MARK: - Record mapping

struct SyncRecordMappingTests {
    private func everyEntity() -> [SyncEntity] {
        var item = SyncFixtures.item("OL1", shelf: .paused, page: 42, updated: 30)
        item.rating = 4
        item.pausedAt = SyncFixtures.at(25)
        item.startPage = 10
        item.progressMode = .percent
        var session = SyncFixtures.session("OL1", to: 42)
        session.teaID = "sencha"
        session.ambienceID = "rain"
        session.device = .watch
        session.kind = .manual
        var prefs = ReadingPreferences()
        prefs.wpm = 312
        prefs.readingDays = [2, 3, 4]
        prefs.hasOnboarded = true
        prefs.onboardedAt = SyncFixtures.at(-100)
        prefs.updatedAt = SyncFixtures.at(50)
        prefs.yearlyGoal = 24
        prefs.favoriteTeaID = "earl-grey"
        prefs.catchUp = .compress
        prefs.nookScene = "fireplace"
        return [
            .item(item),
            .session(session),
            .journal(JournalEntry(bookID: "OL1", bookTitle: "T", bookAuthor: "A", kind: .quote, text: "A line “worth” keeping — with a dash", page: 12, sessionID: session.id, isFavorite: true, createdAt: SyncFixtures.at(5), updatedAt: SyncFixtures.at(9))),
            .preferences(prefs),
            .speedTest(SpeedTestResult(date: SyncFixtures.at(3), passageID: "p1", words: 230, seconds: 55.5, correct: 3, total: 4)),
            .dismissal("OL7"),
            .challenge(ChallengeEnrollment(id: "autumn", joinedAt: SyncFixtures.at(2), year: 2026)),
            .challenge(ChallengeEnrollment(id: "cozy", joinedAt: SyncFixtures.at(2), year: nil)),
            .tombstone(SyncFixtures.tomb(.item, "OL2", 20)),
            .cabinetTea(CabinetTea(catalogID: "earl-grey", name: "Earl Grey", brand: "Twinings", family: .black, notes: "With a slice of lemon", steepSeconds: 200, rating: 4, isOutOf: true, addedAt: SyncFixtures.at(4), updatedAt: SyncFixtures.at(8))),
            .cabinetTea(CabinetTea(name: "Grandma’s blend", family: .herbal, steepSeconds: 420, addedAt: SyncFixtures.at(6))),
            .tasting(TastingNote(teaID: "sencha", teaName: "Sencha", family: .green, bookID: "OL1", sessionID: session.id, strength: .strong, aromas: ["grassy", "citrus"], rating: 5, text: "Bright", createdAt: SyncFixtures.at(7), updatedAt: SyncFixtures.at(11))),
            .tombstone(SyncFixtures.tomb(.tasting, UUID().uuidString, 21)),
        ]
    }

    @Test func everyEntityRoundTripsThroughARecord() throws {
        for entity in everyEntity() {
            let record = try #require(SyncRecordMapper.record(for: entity))
            #expect(record.name == entity.recordName)
            #expect(record.type == entity.type)
            #expect(SyncRecordMapper.entity(from: record) == entity, "\(record.name)")
        }
    }

    @Test func everyRecordCarriesPayloadStampAndSchema() throws {
        for entity in everyEntity() {
            let record = try #require(SyncRecordMapper.record(for: entity))
            #expect(record.payload?.isEmpty == false)
            #expect(record.updatedAt != nil)
            #expect(record.schema == SyncPolicy.recordSchema)
            #expect(Set(record.fields.keys) == [SyncRecord.payloadField, SyncRecord.updatedAtField, SyncRecord.schemaField])
        }
    }

    @Test func theSameEntityAlwaysGivesTheSameBytes() throws {
        for entity in everyEntity() {
            let a = try #require(SyncRecordMapper.record(for: entity))
            let b = try #require(SyncRecordMapper.record(for: entity))
            #expect(a == b)
        }
    }

    @Test func stampsBeforeTheEpochAreClampedButThePayloadKeepsTheExactValue() throws {
        var prefs = ReadingPreferences()
        prefs.wpm = 301
        let record = try #require(SyncRecordMapper.record(for: .preferences(prefs)))
        #expect(prefs.updatedAt == .distantPast)
        #expect(try #require(record.updatedAt) >= Date(timeIntervalSince1970: 0))
        guard case .preferences(let back)? = SyncRecordMapper.entity(from: record) else {
            Issue.record("not preferences")
            return
        }
        #expect(back.updatedAt == .distantPast)
        #expect(back.wpm == 301)
    }

    @Test func legacyPayloadsFromOlderVersionsStillDecode() throws {
        let legacyItem = Data(#"{"book":{"id":"OL5","title":"Old","author":"A","pages":200,"words":54000,"genres":[],"popularity":0},"shelf":"reading","currentPage":50,"order":2,"addedAt":700000000}"#.utf8)
        let itemRecord = SyncRecord(name: "item.OL5", type: .item, fields: [SyncRecord.payloadField: .data(legacyItem)])
        guard case .item(let item)? = SyncRecordMapper.entity(from: itemRecord) else {
            Issue.record("legacy item did not decode")
            return
        }
        #expect(item.id == "OL5" && item.currentPage == 50)
        #expect(item.progressMode == .pages && item.startPage == 0)
        #expect(item.positionConfirmed, "anyone who already had the book on a shelf has confirmed it")
        #expect(item.updatedAt == item.addedAt, "the stamp falls back to the newest known date")

        let legacySession = Data(#"{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","bookID":"OL5","startedAt":700000000,"seconds":600,"fromPage":0,"toPage":30}"#.utf8)
        let sessionRecord = SyncRecord(name: "session.x", type: .session, fields: [SyncRecord.payloadField: .data(legacySession)])
        guard case .session(let session)? = SyncRecordMapper.entity(from: sessionRecord) else {
            Issue.record("legacy session did not decode")
            return
        }
        #expect(session.kind == .timed && session.teaID == nil && session.device == nil)

        let legacyPrefs = Data(#"{"wpm":280,"dailyMinutes":15}"#.utf8)
        let prefsRecord = SyncRecord(name: "prefs", type: .preferences, fields: [SyncRecord.payloadField: .data(legacyPrefs)])
        guard case .preferences(let prefs)? = SyncRecordMapper.entity(from: prefsRecord) else {
            Issue.record("legacy preferences did not decode")
            return
        }
        #expect(prefs.wpm == 280 && prefs.dailyMinutes == 15 && prefs.cupMinutes == 25 && prefs.syncEnabled)
        #expect(prefs.updatedAt == .distantPast)
    }

    @Test func unknownFieldsFromANewerVersionAreIgnored() {
        let newer = Data(#"{"id":"OL8","joinedAt":700000000,"year":2027,"badge":"gold","extra":{"a":1}}"#.utf8)
        let record = SyncRecord(name: "challenge.OL8.2027", type: .challenge, fields: [SyncRecord.payloadField: .data(newer)])
        guard case .challenge(let enrollment)? = SyncRecordMapper.entity(from: record) else {
            Issue.record("newer challenge did not decode")
            return
        }
        #expect(enrollment.id == "OL8" && enrollment.year == 2027)
    }

    @Test func unreadableRecordsAreNilNotCrashes() {
        #expect(SyncRecordMapper.entity(from: SyncRecord(name: "item.x", type: .item, fields: [:])) == nil)
        #expect(SyncRecordMapper.entity(from: SyncRecord(name: "item.x", type: .item, fields: [SyncRecord.payloadField: .data(Data("not json".utf8))])) == nil)
        #expect(SyncRecordMapper.entity(from: SyncRecord(name: "item.x", type: .item, fields: [SyncRecord.payloadField: .string("text")])) == nil)
        // A session payload filed under the item type does not decode as an item.
        let sessionBytes = Data(#"{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","bookID":"b","startedAt":1,"seconds":1,"fromPage":0,"toPage":1}"#.utf8)
        #expect(SyncRecordMapper.entity(from: SyncRecord(name: "item.x", type: .item, fields: [SyncRecord.payloadField: .data(sessionBytes)])) == nil)
        #expect(SyncRecordMapper.entity(from: SyncRecord(name: "dismissal.x", type: .dismissal, fields: [SyncRecord.payloadField: .data(Data("{}".utf8))])) == nil)
    }

    @Test func aRecordTooBigForCloudKitIsNeverBuilt() {
        let huge = JournalEntry(bookID: "b", text: String(repeating: "word ", count: 250_000), createdAt: SyncFixtures.at(1))
        #expect(SyncRecordMapper.record(for: .journal(huge)) == nil)
        let fine = JournalEntry(bookID: "b", text: String(repeating: "word ", count: 1_000), createdAt: SyncFixtures.at(1))
        #expect(SyncRecordMapper.record(for: .journal(fine)) != nil)
    }

    @Test func recordsFromALibraryAreSortedAndLeaveTheLiveSessionBehind() {
        var data = SyncFixtures.data(
            items: [SyncFixtures.item("b"), SyncFixtures.item("a")],
            sessions: [SyncFixtures.session("a", to: 10)],
            dismissed: ["z"],
            challenges: [ChallengeEnrollment(id: "c", joinedAt: SyncFixtures.at(1), year: 2026)],
            tombstones: [SyncFixtures.tomb(.item, "gone", 5)]
        )
        data.activeSession = ActiveSession(bookID: "a", startedAt: SyncFixtures.at(0), startPage: 0, origin: .phone)
        let records = SyncRecordMapper.records(from: data)
        #expect(records.map(\.name) == records.map(\.name).sorted())
        #expect(records.count == 2 + 1 + 1 + 1 + 1 + 1, "two items, a session, a dismissal, a challenge, a tombstone and the preferences")
        #expect(!records.contains { $0.name.hasPrefix("active") })
        #expect(records.contains { $0.name == "prefs" })
    }

    @Test func aFetchedBatchWithoutPreferencesNeverResetsThem() {
        var local = SyncFixtures.data(items: [SyncFixtures.item("a")])
        local.preferences.wpm = 410
        local.preferences.updatedAt = SyncFixtures.at(10)
        local.version = 2
        let record = SyncRecordMapper.record(for: .item(SyncFixtures.item("b")))
        let delta = SyncRecordMapper.delta(from: record.map { [$0] } ?? [], basedOn: local)
        #expect(delta.preferences == local.preferences)
        #expect(delta.items.map(\.id) == ["b"])
        let merged = local.merged(with: delta, now: SyncFixtures.now)
        #expect(merged.preferences.wpm == 410)
        #expect(merged.items.map(\.id) == ["a", "b"])
    }

    @Test func aFetchedPreferencesRecordIsUsed() throws {
        var remote = ReadingPreferences()
        remote.wpm = 333
        remote.updatedAt = SyncFixtures.at(99)
        let record = try #require(SyncRecordMapper.record(for: .preferences(remote)))
        let delta = SyncRecordMapper.delta(from: [record], basedOn: LeafData())
        #expect(delta.preferences.wpm == 333)
    }

    @Test func aWholeLibraryRoundTripsThroughRecords() throws {
        var rng = SeededGenerator(seed: 99)
        var replica = SyncReplica(data: LeafData(), seed: 5)
        for _ in 0..<80 { replica.step() }
        _ = rng.next()
        let original = replica.data
        let rebuilt = SyncRecordMapper.delta(from: SyncRecordMapper.records(from: original), basedOn: original)
        let a = try SyncFixtures.canon(original.merged(with: LeafData(), now: SyncFixtures.now))
        let b = try SyncFixtures.canon(rebuilt.merged(with: LeafData(), now: SyncFixtures.now))
        #expect(a == b)
    }
}

// MARK: - Diff

struct SyncDiffTests {
    private func base() -> LeafData {
        SyncFixtures.data(
            items: [SyncFixtures.item("a", page: 10, updated: 5), SyncFixtures.item("b", shelf: .toRead, updated: 6)],
            sessions: [SyncFixtures.session("a", id: UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID(), to: 10)],
            journal: [JournalEntry(id: UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8") ?? UUID(), bookID: "a", text: "hi", createdAt: SyncFixtures.at(2))],
            dismissed: ["x"],
            challenges: [ChallengeEnrollment(id: "c", joinedAt: SyncFixtures.at(1), year: 2026)]
        )
    }

    @Test func noChangeQueuesNothing() {
        let d = base()
        let changes = SyncDiff.changes(from: d, to: d)
        #expect(changes.saves.isEmpty && changes.deletes.isEmpty)
    }

    @Test func addingAndEditingAnItemSavesOnlyThatItem() {
        var new = base()
        new.items.append(SyncFixtures.item("c", updated: 9))
        #expect(SyncDiff.changes(from: base(), to: new).saves == ["item.c"])
        var edited = base()
        edited.items[0].rating = 5
        edited.items[0].updatedAt = SyncFixtures.at(50)
        let changes = SyncDiff.changes(from: base(), to: edited)
        #expect(changes.saves == ["item.a"] && changes.deletes.isEmpty)
    }

    @Test func removingAnItemDeletesItsRecordAndSavesTheTombstone() {
        var new = base()
        new.items.removeAll { $0.id == "a" }
        new.tombstones.append(SyncFixtures.tomb(.item, "a", 20))
        let changes = SyncDiff.changes(from: base(), to: new)
        #expect(changes.deletes == ["item.a"])
        #expect(changes.saves == ["tombstone.item.a"])
    }

    @Test func reAddingAfterADeleteSavesTheItemAndDeletesTheTombstone() {
        var gone = base()
        gone.items.removeAll { $0.id == "a" }
        gone.tombstones.append(SyncFixtures.tomb(.item, "a", 20))
        var back = gone
        back.items.append(SyncFixtures.item("a", updated: 30))
        back.tombstones.removeAll()
        let changes = SyncDiff.changes(from: gone, to: back)
        #expect(changes.saves == ["item.a"])
        #expect(changes.deletes == ["tombstone.item.a"])
    }

    @Test func aNewSessionSavesOnlyThatSession() {
        var new = base()
        let session = SyncFixtures.session("a", start: 100, to: 20)
        new.sessions.append(session)
        #expect(SyncDiff.changes(from: base(), to: new).saves == ["session.\(session.id.uuidString)"])
    }

    @Test func theLiveSessionNeverQueuesAnything() {
        var new = base()
        new.activeSession = ActiveSession(bookID: "a", startedAt: SyncFixtures.at(0), startPage: 0, origin: .watch)
        var paused = new
        paused.activeSession?.pause(at: SyncFixtures.at(60))
        let a = SyncDiff.changes(from: base(), to: new)
        let b = SyncDiff.changes(from: new, to: paused)
        #expect(a.saves.isEmpty && a.deletes.isEmpty && b.saves.isEmpty && b.deletes.isEmpty)
    }

    @Test func theDevicesOwnSettingsQueueNothingButRealSettingsDo() {
        var new = base()
        new.preferences.hapticsLevel = .off
        new.preferences.appearance = .night
        new.preferences.syncEnabled = false
        new.preferences.updatedAt = SyncFixtures.at(500)
        let local = SyncDiff.changes(from: base(), to: new)
        #expect(local.saves.isEmpty && local.deletes.isEmpty)
        var real = base()
        real.preferences.wpm = 321
        real.preferences.updatedAt = SyncFixtures.at(501)
        #expect(SyncDiff.changes(from: base(), to: real).saves == ["prefs"])
    }

    @Test func journalDismissalsAndChallengesTravelBothWays() {
        let journalID = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8") ?? UUID()
        var edited = base()
        edited.journal[0].text = "changed"
        edited.journal[0].updatedAt = SyncFixtures.at(40)
        #expect(SyncDiff.changes(from: base(), to: edited).saves == ["journal.\(journalID.uuidString)"])

        var deleted = base()
        deleted.journal.removeAll()
        deleted.tombstones.append(SyncFixtures.tomb(.journal, journalID.uuidString, 41))
        let dj = SyncDiff.changes(from: base(), to: deleted)
        #expect(dj.deletes == ["journal.\(journalID.uuidString)"])
        #expect(dj.saves == ["tombstone.journal.\(journalID.uuidString)"])

        var undismissed = base()
        undismissed.dismissed = []
        undismissed.tombstones.append(SyncFixtures.tomb(.dismissal, "x", 42))
        let du = SyncDiff.changes(from: base(), to: undismissed)
        #expect(du.deletes == ["dismissal.x"] && du.saves == ["tombstone.dismissal.x"])

        var dismissed = base()
        dismissed.dismissed.append("y")
        #expect(SyncDiff.changes(from: base(), to: dismissed).saves == ["dismissal.y"])

        var left = base()
        left.challenges = []
        left.tombstones.append(SyncFixtures.tomb(.challenge, "c", 43))
        let dc = SyncDiff.changes(from: base(), to: left)
        #expect(dc.deletes == ["challenge.c.2026"] && dc.saves == ["tombstone.challenge.c"])
    }

    @Test func resultsAreSortedAndNeverOverlap() {
        var new = base()
        new.items.removeAll()
        new.sessions = []
        new.dismissed = ["q", "p"]
        new.tombstones = [SyncFixtures.tomb(.item, "b", 7), SyncFixtures.tomb(.item, "a", 7)]
        let changes = SyncDiff.changes(from: base(), to: new)
        #expect(changes.saves == changes.saves.sorted() && changes.deletes == changes.deletes.sorted())
        #expect(Set(changes.saves).isDisjoint(with: changes.deletes))
    }

    @Test func fromNothingEverythingIsASave() {
        let d = base()
        let changes = SyncDiff.changes(from: LeafData(), to: d)
        #expect(changes.deletes.isEmpty)
        #expect(changes.saves == SyncRecordMapper.records(from: d).map(\.name).filter { $0 != "prefs" })
    }

    @Test func catchUpPicksTheRecentOnesAndOnlyAsksForUndatedOnesOnRequest() {
        var d = base()
        d.sessions.append(SyncFixtures.session("a", start: 1_000, seconds: 60, to: 30))
        d.tombstones.append(SyncFixtures.tomb(.item, "old", -500))
        d.speedTests.append(SpeedTestResult(date: SyncFixtures.at(1_100), passageID: "p", words: 200, seconds: 50, correct: 3, total: 4))
        d.items[0].updatedAt = SyncFixtures.at(1_200)
        let since = SyncFixtures.at(900)
        let dated = SyncDiff.recordNames(in: d, changedSince: since, includeUndated: false)
        #expect(dated.contains("item.a") && !dated.contains("item.b"))
        #expect(dated.contains { $0.hasPrefix("session.") } && dated.contains { $0.hasPrefix("speedtest.") })
        #expect(!dated.contains("tombstone.item.old"))
        #expect(!dated.contains("prefs") && !dated.contains("dismissal.x"))
        let withUndated = SyncDiff.recordNames(in: d, changedSince: since, includeUndated: true)
        #expect(withUndated.contains("prefs") && withUndated.contains("dismissal.x") && withUndated.contains("challenge.c.2026"))
        let everything = SyncDiff.recordNames(in: d, changedSince: nil, includeUndated: false)
        #expect(everything == SyncRecordMapper.records(from: d).map(\.name))
    }

    @Test func behindListsOnlyWhatTheServerLacks() throws {
        let server = SyncFixtures.item("a", page: 10, updated: 5)
        var local = SyncFixtures.item("a", page: 30, updated: 9)
        local.rating = 5
        let sameThere = SyncFixtures.item("b", shelf: .toRead, updated: 6)
        let remote = SyncFixtures.data(items: [server, sameThere])
        let merged = SyncFixtures.data(items: [local, sameThere]).merged(with: remote, now: SyncFixtures.now)
        let behind = SyncDiff.behind(fetched: ["item.a", "item.b", "item.gone"], remote: remote, merged: merged)
        #expect(behind == ["item.a"])
    }

    @Test func differsSeesPageRepairsAndLiveSessionButNotDeviceSettings() {
        let a = base()
        var settings = base()
        settings.preferences.hapticsLevel = .off
        #expect(!SyncDiff.differs(a, settings))
        var live = base()
        live.activeSession = ActiveSession(bookID: "a", startedAt: SyncFixtures.at(0), startPage: 0, origin: .phone)
        #expect(SyncDiff.differs(a, live))
        var page = base()
        page.items[0].currentPage = 99
        #expect(SyncDiff.differs(a, page))
    }
}

// MARK: - Merge rules

struct SyncMergeTests {
    private let now = SyncFixtures.now

    private func merge(_ a: LeafData, _ b: LeafData) -> LeafData { a.merged(with: b, now: now) }

    // Library items

    @Test func theNewestCopyOfABookWinsAsAWholeWhicheverSideItIsOn() {
        let older = SyncFixtures.item("a", shelf: .reading, page: 40, updated: 10)
        var newer = SyncFixtures.item("a", shelf: .finished, page: 300, updated: 20)
        newer.rating = 5
        let a = SyncFixtures.data(items: [older])
        let b = SyncFixtures.data(items: [newer])
        #expect(merge(a, b).items == [newer])
        #expect(merge(b, a).items == [newer])
    }

    @Test func booksOnlyOneSideHasAreKept() {
        let a = SyncFixtures.data(items: [SyncFixtures.item("a", order: 1)])
        let b = SyncFixtures.data(items: [SyncFixtures.item("b", order: 2)])
        #expect(merge(a, b).items.map(\.id) == ["a", "b"])
        #expect(merge(b, a).items.map(\.id) == ["a", "b"])
    }

    @Test func aTieOnTheStampIsBrokenTheSameWayOnBothSides() throws {
        var x = SyncFixtures.item("a", updated: 10)
        x.rating = 2
        var y = SyncFixtures.item("a", updated: 10)
        y.rating = 4
        let ab = merge(SyncFixtures.data(items: [x]), SyncFixtures.data(items: [y]))
        let ba = merge(SyncFixtures.data(items: [y]), SyncFixtures.data(items: [x]))
        #expect(ab.items == ba.items)
        #expect(ab.items.count == 1)
    }

    @Test func aTombstoneRemovesABookOnlyIfItIsStrictlyLater() {
        let item = SyncFixtures.item("a", updated: 10)
        let later = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.item, "a", 11)])
        let equal = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.item, "a", 10)])
        let earlier = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.item, "a", 9)])
        let local = SyncFixtures.data(items: [item])
        #expect(merge(local, later).items.isEmpty)
        #expect(merge(later, local).items.isEmpty)
        #expect(merge(local, equal).items.count == 1, "an equal stamp keeps the book: when in doubt, keep")
        #expect(merge(local, earlier).items.count == 1)
        #expect(merge(local, later).tombstones.map(\.key) == ["a"], "the tombstone stays so other devices hear of it")
    }

    @Test func reAddingAfterADeleteWinsBecauseItsStampIsNewer() {
        let readded = SyncFixtures.item("a", shelf: .toRead, updated: 30)
        let stale = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.item, "a", 20)])
        let fresh = SyncFixtures.data(items: [readded])
        #expect(merge(fresh, stale).items == [readded])
        #expect(merge(stale, fresh).items == [readded])
    }

    @Test func aDeletionBeatsAnOlderCopyOnAnotherDevice() {
        let oldCopy = SyncFixtures.item("a", updated: 10)
        let deleted = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.item, "a", 50)])
        let merged = merge(SyncFixtures.data(items: [oldCopy]), deleted)
        #expect(merged.items.isEmpty)
    }

    @Test func tombstonesOlderThanNinetyDaysAreDroppedAndStopMattering() {
        let day: Double = 24 * 60 * 60
        let old = SyncFixtures.tomb(.item, "a", -91 * day)
        let recent = SyncFixtures.tomb(.item, "b", -89 * day)
        let local = SyncFixtures.data(
            items: [SyncFixtures.item("a", updated: -100 * day), SyncFixtures.item("b", updated: -100 * day)],
            tombstones: [old, recent]
        )
        let merged = SyncFixtures.data().merged(with: local, now: SyncFixtures.origin)
        #expect(merged.tombstones.map(\.key) == ["b"])
        #expect(merged.items.map(\.id) == ["a"], "an expired tombstone no longer removes anything; the recent one still does")
    }

    @Test func theNinetyDayEdgeIsInclusive() {
        let day: Double = 24 * 60 * 60
        let exactly = SyncFixtures.tomb(.item, "a", -90 * day)
        let merged = SyncFixtures.data(tombstones: [exactly]).merged(with: LeafData(), now: SyncFixtures.origin)
        #expect(merged.tombstones.count == 1)
    }

    @Test func theLatestOfTwoTombstonesForTheSameThingIsKept() {
        let a = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.item, "a", 10)])
        let b = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.item, "a", 30), SyncFixtures.tomb(.journal, "a", 5)])
        let merged = merge(a, b)
        #expect(merged.tombstones.count == 2)
        #expect(merged.tombstones.first { $0.kind == .item }?.deletedAt == SyncFixtures.at(30))
    }

    // Progress follows sessions

    @Test func aBookBeingReadIsRaisedToTheFurthestSessionAndClampedToItsPages() {
        let stale = SyncFixtures.item("a", shelf: .reading, page: 100, pages: 300, updated: 50)
        let sessions = [SyncFixtures.session("a", start: 10, to: 120), SyncFixtures.session("a", start: 20, to: 90)]
        let merged = merge(SyncFixtures.data(items: [stale]), SyncFixtures.data(sessions: sessions))
        #expect(merged.items[0].currentPage == 120)
        #expect(merged.items[0].updatedAt == stale.updatedAt, "a repair is not an edit")
        #expect(merged.items[0].positionConfirmed)

        let beyond = SyncFixtures.session("a", start: 30, to: 999)
        let clamped = merge(SyncFixtures.data(items: [stale]), SyncFixtures.data(sessions: [beyond]))
        #expect(clamped.items[0].currentPage == 300)
    }

    @Test func aPageIsNeverLoweredByTheRepair() {
        let ahead = SyncFixtures.item("a", shelf: .reading, page: 250, updated: 50)
        let merged = merge(SyncFixtures.data(items: [ahead]), SyncFixtures.data(sessions: [SyncFixtures.session("a", to: 100)]))
        #expect(merged.items[0].currentPage == 250)
    }

    @Test func pausedBooksKeepUpWithTheirSessionsButOtherShelvesAreLeftAlone() {
        let sessions = [SyncFixtures.session("p", to: 80), SyncFixtures.session("q", to: 80), SyncFixtures.session("f", to: 80)]
        let items = [
            SyncFixtures.item("p", shelf: .paused, page: 10, updated: 5),
            SyncFixtures.item("q", shelf: .toRead, page: 10, updated: 5),
            SyncFixtures.item("f", shelf: .finished, page: 300, updated: 5),
        ]
        let merged = merge(SyncFixtures.data(items: items), SyncFixtures.data(sessions: sessions))
        let pages = Dictionary(uniqueKeysWithValues: merged.items.map { ($0.id, $0.currentPage) })
        #expect(pages["p"] == 80)
        #expect(pages["q"] == 10)
        #expect(pages["f"] == 300)
    }

    @Test func aBookWithNoSessionsIsNotTouched() {
        let item = SyncFixtures.item("a", shelf: .reading, page: 0, updated: 5)
        let merged = merge(SyncFixtures.data(items: [item]), LeafData())
        #expect(merged.items == [item])
    }

    @Test func aRestartedBookIsNotDraggedBackByTheLastReadThrough() {
        let day: Double = 24 * 60 * 60
        // Read through in the past, then restarted today: the store resets the page and `startedAt`.
        let oldRead = SyncFixtures.session("a", start: -40 * day, to: 300)
        var restarted = SyncFixtures.item("a", shelf: .reading, page: 0, updated: 5, started: 0)
        restarted.positionConfirmed = true
        let merged = merge(SyncFixtures.data(items: [restarted]), SyncFixtures.data(sessions: [oldRead]))
        #expect(merged.items[0].currentPage == 0)
        // A session typed in for yesterday still counts for a book started today.
        let yesterday = SyncFixtures.session("a", start: -day + 600, seconds: 600, to: 40)
        let counted = merge(SyncFixtures.data(items: [restarted]), SyncFixtures.data(sessions: [oldRead, yesterday]))
        #expect(counted.items[0].currentPage == 40)
    }

    @Test func sessionsOfADeletedBookStayForTheStatistics() {
        let sessions = [SyncFixtures.session("gone", to: 50)]
        let merged = merge(
            SyncFixtures.data(items: [SyncFixtures.item("gone", updated: 5)], sessions: sessions),
            SyncFixtures.data(tombstones: [SyncFixtures.tomb(.item, "gone", 50)])
        )
        #expect(merged.items.isEmpty)
        #expect(merged.sessions.count == 1)
    }

    // Sessions

    @Test func sessionsAreAUnionByIdAndSortedByStart() {
        let id = UUID()
        let shared = SyncFixtures.session("a", id: id, start: 50, to: 10)
        let onlyA = SyncFixtures.session("a", start: 100, to: 20)
        let onlyB = SyncFixtures.session("a", start: 10, to: 5)
        let merged = merge(SyncFixtures.data(sessions: [shared, onlyA]), SyncFixtures.data(sessions: [shared, onlyB]))
        #expect(merged.sessions.count == 3)
        #expect(merged.sessions.map(\.startedAt) == merged.sessions.map(\.startedAt).sorted())
    }

    @Test func twoDifferentSessionsWithTheSameIdKeepTheSameOneOnBothSides() {
        let id = UUID()
        var x = SyncFixtures.session("a", id: id, start: 50, to: 10)
        x.teaID = "sencha"
        let y = SyncFixtures.session("a", id: id, start: 50, to: 10)
        let ab = merge(SyncFixtures.data(sessions: [x]), SyncFixtures.data(sessions: [y]))
        let ba = merge(SyncFixtures.data(sessions: [y]), SyncFixtures.data(sessions: [x]))
        #expect(ab.sessions == ba.sessions && ab.sessions.count == 1)
    }

    // Journal

    @Test func journalEntriesTakeTheNewestEditAndHonourDeletes() {
        let id = UUID()
        let old = JournalEntry(id: id, bookID: "a", text: "first", createdAt: SyncFixtures.at(1), updatedAt: SyncFixtures.at(1))
        var edited = old
        edited.text = "second"
        edited.updatedAt = SyncFixtures.at(9)
        let merged = merge(SyncFixtures.data(journal: [old]), SyncFixtures.data(journal: [edited]))
        #expect(merged.journal.map(\.text) == ["second"])

        let deleted = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.journal, id.uuidString, 20)])
        #expect(merge(SyncFixtures.data(journal: [edited]), deleted).journal.isEmpty)
        // Editing after the delete was made brings it back.
        var revived = edited
        revived.updatedAt = SyncFixtures.at(30)
        #expect(merge(SyncFixtures.data(journal: [revived]), deleted).journal.count == 1)
    }

    // Dismissals

    @Test func dismissalsUniteAndATombstoneOnEitherSideRemovesOne() {
        let a = SyncFixtures.data(dismissed: ["x", "y"])
        let b = SyncFixtures.data(dismissed: ["y", "z"])
        #expect(merge(a, b).dismissed == ["x", "y", "z"])
        let taken = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.dismissal, "y", 5)])
        #expect(merge(a, taken).dismissed == ["x"])
        #expect(merge(taken, a).dismissed == ["x"])
    }

    @Test func theDocumentedDismissalAmbiguityResolvesTheSameOnBothSides() {
        // One device took "not for me" back; another dismissed the same book again without hearing of it.
        let undone = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.dismissal, "x", 5)])
        let again = SyncFixtures.data(dismissed: ["x"])
        #expect(merge(undone, again).dismissed.isEmpty)
        #expect(merge(again, undone).dismissed.isEmpty)
    }

    // Challenges

    @Test func challengesUniteByIdAndYearAndTheLaterJoinWins() {
        let early = ChallengeEnrollment(id: "autumn", joinedAt: SyncFixtures.at(1), year: 2026)
        let late = ChallengeEnrollment(id: "autumn", joinedAt: SyncFixtures.at(9), year: 2026)
        let otherYear = ChallengeEnrollment(id: "autumn", joinedAt: SyncFixtures.at(2), year: 2025)
        let merged = merge(SyncFixtures.data(challenges: [early, otherYear]), SyncFixtures.data(challenges: [late]))
        #expect(merged.challenges.count == 2)
        #expect(merged.challenges.contains(late) && merged.challenges.contains(otherYear))
    }

    @Test func leavingAChallengeRemovesItButReJoiningAfterwardsDoesNot() {
        let joined = ChallengeEnrollment(id: "autumn", joinedAt: SyncFixtures.at(1), year: nil)
        let left = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.challenge, "autumn", 10)])
        #expect(merge(SyncFixtures.data(challenges: [joined]), left).challenges.isEmpty)
        let rejoined = ChallengeEnrollment(id: "autumn", joinedAt: SyncFixtures.at(20), year: nil)
        #expect(merge(SyncFixtures.data(challenges: [joined, rejoined]), left).challenges == [rejoined])
    }

    @Test func aTombstoneKeyedByTheBareIdOnlyRemovesEnrollmentsJoinedBeforeIt() {
        // The store keys challenge tombstones by challenge id alone, while enrollments are (id, year).
        let before25 = ChallengeEnrollment(id: "read", joinedAt: SyncFixtures.at(1), year: 2025)
        let before26 = ChallengeEnrollment(id: "read", joinedAt: SyncFixtures.at(2), year: 2026)
        let after27 = ChallengeEnrollment(id: "read", joinedAt: SyncFixtures.at(30), year: 2027)
        let other = ChallengeEnrollment(id: "cozy", joinedAt: SyncFixtures.at(1), year: nil)
        let left = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.challenge, "read", 10)])
        let merged = merge(SyncFixtures.data(challenges: [before25, before26, after27, other]), left)
        #expect(merged.challenges == [other, after27].sorted { $0.joinedAt < $1.joinedAt })
        #expect(merge(left, SyncFixtures.data(challenges: [before25, before26, after27, other])).challenges == merged.challenges)
    }

    @Test func aPerYearTombstoneRemovesOnlyThatYear() {
        let y25 = ChallengeEnrollment(id: "read", joinedAt: SyncFixtures.at(1), year: 2025)
        let y26 = ChallengeEnrollment(id: "read", joinedAt: SyncFixtures.at(2), year: 2026)
        let left = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.challenge, SyncKey.challengeTombstoneKey(id: "read", year: 2026), 10)])
        #expect(merge(SyncFixtures.data(challenges: [y25, y26]), left).challenges == [y25])
    }

    // Speed tests

    @Test func speedTestsUniteByDateAndPassageAndTheLatestComesLast() {
        let first = SpeedTestResult(date: SyncFixtures.at(10), passageID: "p1", words: 200, seconds: 50, correct: 3, total: 4)
        let second = SpeedTestResult(date: SyncFixtures.at(20), passageID: "p2", words: 220, seconds: 50, correct: 4, total: 4)
        let samePassageLater = SpeedTestResult(date: SyncFixtures.at(30), passageID: "p1", words: 200, seconds: 45, correct: 4, total: 4)
        let merged = merge(SyncFixtures.data(speedTests: [second, first]), SyncFixtures.data(speedTests: [first, samePassageLater]))
        #expect(merged.speedTests == [first, second, samePassageLater])
    }

    // Preferences

    @Test func theNewestPreferencesWinAsAWholeButTheDevicesOwnSettingsStay() {
        var local = ReadingPreferences()
        local.wpm = 250
        local.hapticsLevel = .off
        local.appearance = .night
        local.syncEnabled = false
        local.updatedAt = SyncFixtures.at(10)
        var remote = ReadingPreferences()
        remote.wpm = 400
        remote.dailyMinutes = 45
        remote.hapticsLevel = .full
        remote.appearance = .day
        remote.syncEnabled = true
        remote.updatedAt = SyncFixtures.at(20)
        let merged = merge(SyncFixtures.data(prefs: local), SyncFixtures.data(prefs: remote)).preferences
        #expect(merged.wpm == 400 && merged.dailyMinutes == 45)
        #expect(merged.hapticsLevel == .off && merged.appearance == .night)
        #expect(!merged.syncEnabled, "turning iCloud off here must not turn it off on the iPad")
        #expect(merged.updatedAt == SyncFixtures.at(20))
        let flipped = merge(SyncFixtures.data(prefs: remote), SyncFixtures.data(prefs: local)).preferences
        #expect(flipped.wpm == 400 && flipped.hapticsLevel == .full && flipped.appearance == .day && flipped.syncEnabled)
    }

    @Test func onboardingIsRememberedFromEitherSideAndTheEarliestDateIsKept() {
        var a = ReadingPreferences()
        a.hasOnboarded = true
        a.onboardedAt = SyncFixtures.at(500)
        a.updatedAt = SyncFixtures.at(500)
        var b = ReadingPreferences()
        b.wpm = 333
        b.updatedAt = SyncFixtures.at(900)
        let merged = merge(SyncFixtures.data(prefs: a), SyncFixtures.data(prefs: b)).preferences
        #expect(merged.wpm == 333, "the newer copy still wins the rest")
        #expect(merged.hasOnboarded)
        #expect(merged.onboardedAt == SyncFixtures.at(500))
        var c = a
        c.onboardedAt = SyncFixtures.at(100)
        c.updatedAt = SyncFixtures.at(10)
        #expect(merge(SyncFixtures.data(prefs: a), SyncFixtures.data(prefs: c)).preferences.onboardedAt == SyncFixtures.at(100))
    }

    @Test func legacyPreferencesWithNoStampLoseToAnythingStamped() {
        var legacy = ReadingPreferences()
        legacy.wpm = 300
        var stamped = ReadingPreferences()
        stamped.wpm = 220
        stamped.updatedAt = SyncFixtures.at(1)
        #expect(legacy.updatedAt == .distantPast)
        #expect(merge(SyncFixtures.data(prefs: legacy), SyncFixtures.data(prefs: stamped)).preferences.wpm == 220)
        #expect(merge(SyncFixtures.data(prefs: stamped), SyncFixtures.data(prefs: legacy)).preferences.wpm == 220)
    }

    @Test func aTieInPreferenceStampsPicksTheSameWinnerOnBothSides() {
        var a = ReadingPreferences()
        a.wpm = 200
        a.updatedAt = SyncFixtures.at(5)
        var b = ReadingPreferences()
        b.wpm = 300
        b.updatedAt = SyncFixtures.at(5)
        let ab = merge(SyncFixtures.data(prefs: a), SyncFixtures.data(prefs: b)).preferences
        let ba = merge(SyncFixtures.data(prefs: b), SyncFixtures.data(prefs: a)).preferences
        #expect(ab.wpm == ba.wpm)
    }

    // Live session, version, legacy, size

    @Test func theLiveSessionStaysLocalAndNeverComesFromTheOtherSide() {
        let live = ActiveSession(bookID: "a", startedAt: SyncFixtures.at(0), startPage: 3, origin: .phone)
        var local = SyncFixtures.data(items: [SyncFixtures.item("a", updated: 5)])
        local.activeSession = live
        var remote = SyncFixtures.data(items: [SyncFixtures.item("a", updated: 5)])
        remote.activeSession = ActiveSession(bookID: "a", startedAt: SyncFixtures.at(9), startPage: 9, origin: .watch)
        #expect(merge(local, remote).activeSession == live)
        #expect(merge(SyncFixtures.data(items: [SyncFixtures.item("a", updated: 5)]), remote).activeSession == nil)
    }

    @Test func aLiveSessionForABookDeletedElsewhereIsDropped() {
        var local = SyncFixtures.data(items: [SyncFixtures.item("a", updated: 5)])
        local.activeSession = ActiveSession(bookID: "a", startedAt: SyncFixtures.at(0), startPage: 0, origin: .phone)
        let deleted = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.item, "a", 50)])
        let merged = merge(local, deleted)
        #expect(merged.items.isEmpty && merged.activeSession == nil)
    }

    @Test func theVersionIsTheHigherOne() {
        var old = LeafData()
        old.version = 1
        var new = LeafData()
        new.version = 2
        #expect(merge(old, new).version == 2 && merge(new, old).version == 2)
    }

    @Test func oldVersionOneDataMergesCleanly() throws {
        let legacy = Data(#"{"items":[{"book":{"id":"a","title":"A","author":"X","pages":100,"words":27000,"genres":[],"popularity":0},"shelf":"reading","currentPage":10,"order":1,"addedAt":700000000}],"sessions":[],"speedTests":[],"preferences":{"wpm":250},"dismissed":["z"]}"#.utf8)
        let old = try JSONDecoder().decode(LeafData.self, from: legacy)
        #expect(old.version == 1 && old.tombstones.isEmpty)
        let merged = merge(old, SyncFixtures.data(items: [SyncFixtures.item("b", updated: 1)]))
        #expect(merged.version == 2)
        #expect(merged.items.map(\.id) == ["a", "b"])
        #expect(merged.dismissed == ["z"])
        #expect(merged.preferences.wpm == 250)
    }

    @Test func emptyDataMergesToEmptyData() throws {
        let merged = merge(LeafData(), LeafData())
        #expect(merged.items.isEmpty && merged.sessions.isEmpty && merged.journal.isEmpty && merged.tombstones.isEmpty)
        #expect(try SyncFixtures.canon(merged) == SyncFixtures.canon(LeafData()))
    }

    @Test func outputOrderIsDeterministic() {
        let items = [
            SyncFixtures.item("c", order: 2), SyncFixtures.item("a", order: 2), SyncFixtures.item("b", order: 1),
        ]
        let forward = merge(SyncFixtures.data(items: items), LeafData())
        let backward = merge(SyncFixtures.data(items: items.reversed()), LeafData())
        #expect(forward.items.map(\.id) == ["b", "a", "c"])
        #expect(backward.items.map(\.id) == forward.items.map(\.id))
    }

    @Test func removingTombstonesTakesOnlyTheNamedOnes() {
        let d = SyncFixtures.data(tombstones: [SyncFixtures.tomb(.item, "a", 1), SyncFixtures.tomb(.dismissal, "a", 2), SyncFixtures.tomb(.item, "b", 3)])
        let trimmed = d.removingTombstones([SyncTombstoneKey(kind: .item, key: "a")])
        #expect(trimmed.tombstones.map(\.key) == ["a", "b"] && trimmed.tombstones.first?.kind == .dismissal)
        #expect(d.removingTombstones([]).tombstones == d.tombstones)
    }

    @Test func aBigLibraryMergesQuickly() {
        var local = LeafData()
        var remote = LeafData()
        for index in 0..<600 {
            local.items.append(SyncFixtures.item("book\(index)", shelf: .reading, page: 5, order: Double(index), updated: Double(index)))
            if index % 2 == 0 { remote.items.append(SyncFixtures.item("book\(index)", shelf: .reading, page: 9, order: Double(index), updated: Double(index + 1))) }
        }
        for index in 0..<6_000 {
            let s = SyncFixtures.session("book\(index % 600)", start: Double(index), seconds: 30, to: index % 50)
            if index % 3 == 0 { local.sessions.append(s) } else { remote.sessions.append(s) }
        }
        let start = Date()
        let merged = local.merged(with: remote, now: SyncFixtures.now)
        #expect(merged.items.count == 600 && merged.sessions.count == 6_000)
        #expect(Date().timeIntervalSince(start) < 2.0)
    }
}

// MARK: - Properties over random histories

struct SyncPropertyTests {
    private let now = SyncFixtures.now

    /// Two or three replicas that start from the same small library and then edit on their own.
    private func replicas(seed: UInt64, count: Int, baseSteps: Int = 12, steps: Int = 18) -> [LeafData] {
        var shared = SyncReplica(data: LeafData(), seed: seed &* 7919 &+ 1)
        for _ in 0..<baseSteps { shared.step() }
        return (0..<count).map { index in
            var replica = SyncReplica(data: shared.data, seed: seed &* 104_729 &+ UInt64(index) &+ 3, clock: shared.clock)
            for _ in 0..<steps { replica.step() }
            return replica.data
        }
    }

    @Test func mergingIsCommutative() throws {
        for seed in 1...150 {
            let r = replicas(seed: UInt64(seed), count: 2)
            let ab = try SyncFixtures.canon(r[0].merged(with: r[1], now: now))
            let ba = try SyncFixtures.canon(r[1].merged(with: r[0], now: now))
            #expect(ab == ba, "seed \(seed)")
        }
    }

    @Test func mergingIsIdempotent() throws {
        for seed in 1...150 {
            let r = replicas(seed: UInt64(seed), count: 2)
            let m = r[0].merged(with: r[1], now: now)
            let canon = try SyncFixtures.canon(m)
            #expect(try SyncFixtures.canon(m.merged(with: r[1], now: now)) == canon, "again with the same remote, seed \(seed)")
            #expect(try SyncFixtures.canon(m.merged(with: r[0], now: now)) == canon, "again with the local, seed \(seed)")
            #expect(try SyncFixtures.canon(m.merged(with: m, now: now)) == canon, "with itself, seed \(seed)")
        }
    }

    @Test func mergingIsAssociativeInEveryGrouping() throws {
        for seed in 1...150 {
            let r = replicas(seed: UInt64(seed), count: 3)
            let (a, b, c) = (r[0], r[1], r[2])
            let left = try SyncFixtures.canon(a.merged(with: b, now: now).merged(with: c, now: now))
            let right = try SyncFixtures.canon(a.merged(with: b.merged(with: c, now: now), now: now))
            let other = try SyncFixtures.canon(c.merged(with: a, now: now).merged(with: b, now: now))
            let last = try SyncFixtures.canon(b.merged(with: c.merged(with: a, now: now), now: now))
            #expect(left == right, "seed \(seed)")
            #expect(left == other, "seed \(seed)")
            #expect(left == last, "seed \(seed)")
        }
    }

    @Test func twoDevicesThatExchangeEverythingEndUpIdentical() throws {
        for seed in 1...150 {
            let r = replicas(seed: UInt64(seed), count: 2)
            let a = r[0].merged(with: r[1], now: now)
            let b = r[1].merged(with: r[0], now: now)
            #expect(try SyncFixtures.canon(a) == SyncFixtures.canon(b), "seed \(seed)")
            // Hearing the same news again changes nothing.
            #expect(try SyncFixtures.canon(a.merged(with: b, now: now)) == SyncFixtures.canon(a), "seed \(seed)")
        }
    }

    @Test func nothingIsLostInAMerge() {
        for seed in 1...150 {
            let r = replicas(seed: UInt64(seed), count: 2)
            let merged = r[0].merged(with: r[1], now: now)
            let sessionIDs = Set(merged.sessions.map(\.id))
            for session in r[0].sessions + r[1].sessions { #expect(sessionIDs.contains(session.id), "session, seed \(seed)") }
            let tombstones = Dictionary(merged.tombstones.map { (SyncTombstoneKey(kind: $0.kind, key: $0.key), $0.deletedAt) }, uniquingKeysWith: max)
            let present = Set(merged.items.map(\.id))
            for item in r[0].items + r[1].items where !present.contains(item.id) {
                let newest = (r[0].items + r[1].items).filter { $0.id == item.id }.map(\.updatedAt).max() ?? item.updatedAt
                let deleted = tombstones[SyncTombstoneKey(kind: .item, key: item.id)]
                #expect(deleted.map { $0 > newest } == true, "item \(item.id) vanished without a later tombstone, seed \(seed)")
            }
            let entries = Set(merged.journal.map(\.id))
            for entry in r[0].journal + r[1].journal where !entries.contains(entry.id) {
                let newest = (r[0].journal + r[1].journal).filter { $0.id == entry.id }.map(\.updatedAt).max() ?? entry.updatedAt
                let deleted = tombstones[SyncTombstoneKey(kind: .journal, key: entry.id.uuidString)]
                #expect(deleted.map { $0 > newest } == true, "journal entry vanished, seed \(seed)")
            }
            for test in r[0].speedTests + r[1].speedTests {
                #expect(merged.speedTests.contains { SyncKey.speedTestKey(date: $0.date, passageID: $0.passageID) == SyncKey.speedTestKey(date: test.date, passageID: test.passageID) }, "speed test, seed \(seed)")
            }
        }
    }

    @Test func aMergedLibraryAlwaysKeepsItsInvariants() {
        for seed in 1...150 {
            let r = replicas(seed: UInt64(seed), count: 2)
            let merged = r[0].merged(with: r[1], now: now)
            #expect(Set(merged.items.map(\.id)).count == merged.items.count, "duplicate books, seed \(seed)")
            #expect(Set(merged.sessions.map(\.id)).count == merged.sessions.count, "duplicate sessions, seed \(seed)")
            #expect(Set(merged.journal.map(\.id)).count == merged.journal.count, "duplicate entries, seed \(seed)")
            #expect(merged.speedTests.map(\.date) == merged.speedTests.map(\.date).sorted(), "speed tests out of order, seed \(seed)")
            for item in merged.items {
                #expect(item.currentPage >= 0 && item.currentPage <= item.book.pages, "page out of range, seed \(seed)")
                guard item.shelf == .reading || item.shelf == .paused else { continue }
                let earliest = item.startedAt.map { $0.addingTimeInterval(-SyncPolicy.readThroughSlack) }
                let reached = merged.sessions
                    .filter { session in
                        guard session.bookID == item.id else { return false }
                        guard let earliest else { return true }
                        return session.startedAt.addingTimeInterval(session.seconds) >= earliest
                    }
                    .map(\.toPage).max() ?? 0
                #expect(item.currentPage >= min(reached, item.book.pages), "\(item.id) is behind its sessions, seed \(seed)")
            }
            // A dismissal tombstone always wins over the dismissal.
            for tombstone in merged.tombstones where tombstone.kind == .dismissal {
                #expect(!merged.dismissed.contains(tombstone.key), "seed \(seed)")
            }
            #expect(merged.activeSession == nil)
        }
    }

    @Test func theDevicesOwnSettingsAlwaysSurviveAMerge() {
        for seed in 1...100 {
            let r = replicas(seed: UInt64(seed), count: 2)
            let merged = r[0].merged(with: r[1], now: now)
            #expect(merged.preferences.hapticsLevel == r[0].preferences.hapticsLevel, "seed \(seed)")
            #expect(merged.preferences.appearance == r[0].preferences.appearance, "seed \(seed)")
            #expect(merged.preferences.syncEnabled == r[0].preferences.syncEnabled, "seed \(seed)")
            #expect(merged.preferences.hasOnboarded == (r[0].preferences.hasOnboarded || r[1].preferences.hasOnboarded), "seed \(seed)")
        }
    }

    @Test func prunedTombstonesAreTheOnlyThingTheClockChanges() throws {
        for seed in 1...60 {
            let r = replicas(seed: UInt64(seed), count: 2)
            let soon = r[0].merged(with: r[1], now: now)
            let later = soon.merged(with: r[1], now: now.addingTimeInterval(200 * 24 * 60 * 60))
            #expect(later.tombstones.isEmpty, "every tombstone is older than 90 days by then, seed \(seed)")
            #expect(Set(later.sessions.map(\.id)) == Set(soon.sessions.map(\.id)))
            #expect(Set(later.journal.map(\.id)).isSuperset(of: Set(soon.journal.map(\.id))))
        }
    }

    // The whole pipeline: edits become queued names, names become records on a pretend server, other devices fetch
    // records and merge. It has to land on the same place as merging the two libraries directly would.

    @Test func devicesTalkingOnlyThroughRecordsConvergeOnTheSameLibrary() throws {
        for seed in 1...120 {
            var shared = SyncReplica(data: LeafData(), seed: UInt64(seed) &* 31 &+ 5)
            for _ in 0..<10 { shared.step() }
            var simulation = SyncSimulation(base: shared.data, seeds: [UInt64(seed) &* 17 &+ 1, UInt64(seed) &* 17 &+ 2], clock: shared.clock)
            for index in simulation.devices.indices { simulation.devices[index].edit(steps: 16) }
            let rounds = simulation.settle(now: now)
            #expect(rounds < 12, "never went quiet, seed \(seed)")
            // Equal settings can carry different stamps (a device that already agreed does not save back), which
            // changes nothing anyone can see, so the stamp is left out of the comparison.
            let a = try SyncFixtures.canon(simulation.devices[0].replica.data, ignoringPreferenceStamp: true, settled: true)
            let b = try SyncFixtures.canon(simulation.devices[1].replica.data, ignoringPreferenceStamp: true, settled: true)
            #expect(a == b, "seed \(seed)")
        }
    }

    @Test func devicesConvergeOnWhatSyncsEvenIfTheStoreStampsDeviceOnlyEdits() throws {
        // Today's store moves the preference stamp on every edit. The synced fields must still agree everywhere.
        for seed in 1...120 {
            var shared = SyncReplica(data: LeafData(), seed: UInt64(seed) &* 37 &+ 5)
            for _ in 0..<10 { shared.step() }
            var simulation = SyncSimulation(base: shared.data, seeds: [UInt64(seed) &* 19 &+ 1, UInt64(seed) &* 19 &+ 2], clock: shared.clock, stampsDeviceOnlyEdits: true)
            for index in simulation.devices.indices { simulation.devices[index].edit(steps: 16) }
            _ = simulation.settle(now: now)
            let a = try SyncFixtures.canon(simulation.devices[0].replica.data, ignoringPreferenceStamp: true, settled: true)
            let b = try SyncFixtures.canon(simulation.devices[1].replica.data, ignoringPreferenceStamp: true, settled: true)
            #expect(a == b, "seed \(seed)")
        }
    }

    @Test func threeDevicesAlsoConvergeThroughRecords() throws {
        for seed in 1...60 {
            var shared = SyncReplica(data: LeafData(), seed: UInt64(seed) &* 53 &+ 9)
            for _ in 0..<8 { shared.step() }
            var simulation = SyncSimulation(base: shared.data, seeds: [UInt64(seed) &* 11 &+ 1, UInt64(seed) &* 11 &+ 2, UInt64(seed) &* 11 &+ 3], clock: shared.clock)
            for index in simulation.devices.indices { simulation.devices[index].edit(steps: 12) }
            _ = simulation.settle(now: now)
            let canons = try simulation.devices.map { try SyncFixtures.canon($0.replica.data, ignoringPreferenceStamp: true, settled: true) }
            #expect(Set(canons).count == 1, "seed \(seed)")
        }
    }

    @Test func aNewDeviceRestoresEverythingFromTheRecordsAlone() throws {
        for seed in 1...60 {
            var source = SyncReplica(data: LeafData(), seed: UInt64(seed) &* 13 &+ 4)
            for _ in 0..<40 { source.step() }
            var server: [String: SyncRecord] = [:]
            for record in SyncRecordMapper.records(from: source.data) { server[record.name] = record }
            var fresh = SyncSimulation.Device(replica: SyncReplica(data: LeafData(), seed: 1))
            fresh.fetch(from: server, now: now)
            let restored = try SyncFixtures.canon(fresh.replica.data)
            let expected = try SyncFixtures.canon(source.data.merged(with: LeafData(), now: now))
            #expect(restored == expected, "seed \(seed)")
        }
    }
}
