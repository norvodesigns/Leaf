import Foundation

/// Where iCloud sync stands, for Settings to show. Plain data, so the transport and the screens agree on it
/// and the watch target can carry it too.
enum SyncStatus: Equatable, Sendable {
    /// Sync is switched off, or this build has no iCloud.
    case off
    /// Sync is on, but nobody is signed in to iCloud on this device.
    case noAccount
    /// Everything is up to date. `lastSynced` is nil until the first sync has finished.
    case idle(lastSynced: Date?)
    case syncing
    /// Something needs attention. The text is a short, kind sentence the reader can be shown as it is.
    case error(String)

    /// True while the engine is running (idle, syncing or reporting a problem it will retry).
    var isRunning: Bool {
        switch self {
        case .off, .noAccount: return false
        case .idle, .syncing, .error: return true
        }
    }

    var lastSynced: Date? {
        if case .idle(let date) = self { return date }
        return nil
    }

    /// Whether Settings should draw the reader's eye to it.
    var needsAttention: Bool {
        switch self {
        case .noAccount, .error: return true
        case .off, .idle, .syncing: return false
        }
    }
}

/// Numbers and limits the sync layer agrees on. One place, so the merge, the mapping and the transport cannot drift.
enum SyncPolicy {
    /// How long a deletion is remembered. Past this a tombstone is dropped and stops having any effect, so a
    /// device that was off for longer than this can bring a deleted item back (the documented trade-off).
    static let tombstoneLifetime: TimeInterval = 90 * 24 * 60 * 60

    /// The largest payload put into one CloudKit record. The hard limit is 1 MB for the whole record.
    static let maxPayloadBytes = 900_000

    /// CloudKit allows 255 ASCII characters in a record name.
    static let maxRecordNameLength = 255

    /// Version of the record layout, stored on every record so a future layout can be told apart.
    static let recordSchema = 1

    /// Which record types, tombstone kinds and synced fields this build understands. Raise it whenever one is added.
    /// An older build skips records it can't read, and its sync position moves past them; a device whose saved sync
    /// state is from a lower layout therefore fetches the whole zone once (2: the tea cabinet and tasting notes;
    /// 3: earlier read-throughs on books, and their tombstones).
    static let syncLayout = 3

    /// Whether sync state saved under `layout` (nil for state saved before layouts were recorded) must be dropped
    /// for one full fetch.
    static func needsFullFetch(savedLayout layout: Int?) -> Bool {
        (layout ?? 1) < syncLayout
    }

    /// When a book restarts (a reread), sessions from before the restart should not drag its page back. A session
    /// counts towards a book's page only if it ended no earlier than this long before the book's `startedAt`.
    /// A day is enough for sessions typed in afterwards ("read without the timer") for a book added today.
    static let readThroughSlack: TimeInterval = 24 * 60 * 60
}
