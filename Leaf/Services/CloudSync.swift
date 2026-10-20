import Foundation
import Observation
#if canImport(CloudKit)
import CloudKit

/// Backs up and syncs the library through the reader's own private iCloud database. No accounts, no server.
///
/// All the decisions (what a record looks like, what changed, how two copies merge) live in `Shared/Sync` and are
/// tested on Linux; this class only moves records. It keeps a mirror of the local data: `localDataChanged` queues
/// what the store changed, fetched records are merged into the mirror and handed back through `onRemoteData`.
/// docs/SYNC.md explains the design and how to test it on two devices.
@MainActor
@Observable
final class CloudSync {
    /// The one CloudKit container Leaf uses. It must match the entitlements.
    static let containerIdentifier = "iCloud.com.norvodesigns.leaf"
    static let zoneName = "LeafZone"

    /// Records per send. CloudKit allows 400 operations in a request; this stays well inside it.
    private static let batchSize = 200
    /// When catching up after a restart, look back this far before the last finished sync.
    private static let catchUpSlack: TimeInterval = 3600

    private(set) var status: SyncStatus = .off
    /// Changes waiting to be sent, for a "syncing 12 changes" line.
    private(set) var pendingChanges = 0

    /// Called on the main actor with the merged library whenever iCloud brought something new. The store should
    /// adopt it as it is (keeping its own live session and device settings, which the merge already preserves).
    @ObservationIgnored var onRemoteData: ((LeafData) -> Void)?
    /// Wall-clock time for tombstone expiry and "last synced", injectable for tests.
    @ObservationIgnored var clock: () -> Date = { Date() }

    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var proxy: SyncDelegateProxy?
    @ObservationIgnored private var mirror = LeafData()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastError: String?
    @ObservationIgnored private var lastSynced: Date?
    @ObservationIgnored private var latestSerialization: CKSyncEngine.State.Serialization?
    /// The server's bookkeeping for each record (change tag), so a save is accepted without a conflict first.
    @ObservationIgnored private var systemFields: [String: Data] = [:]
    @ObservationIgnored private let stateURL: URL

    init(stateURL: URL = CloudSync.defaultStateURL) {
        self.stateURL = stateURL
    }

    nonisolated static var defaultStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Leaf", isDirectory: true)
            .appendingPathComponent("sync-state.bin")
    }

    /// Whether this build may touch CloudKit at all. CloudKit aborts the process when the app lacks the iCloud
    /// entitlement (unsigned CI builds, test hosts), so it is opt-in: the Info.plist key `LeafCloudKitEnabled`
    /// must be true, and neither a test run nor `-LeafDisableCloudKit` may be in effect.
    static var isAvailable: Bool {
        let info = ProcessInfo.processInfo
        if info.arguments.contains("-LeafDisableCloudKit") { return false }
        if info.environment["XCTestConfigurationFilePath"] != nil { return false }
        let flag = Bundle.main.object(forInfoDictionaryKey: "LeafCloudKitEnabled")
        if let enabled = flag as? Bool { return enabled }
        if let text = flag as? String { return ["yes", "true", "1"].contains(text.lowercased()) }
        return false
    }

    private var container: CKContainer { CKContainer(identifier: CloudSync.containerIdentifier) }
    private var zone: CKRecordZone { CKRecordZone(zoneName: CloudSync.zoneName) }
    private var zoneID: CKRecordZone.ID { zone.zoneID }

    private func recordID(_ name: String) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: zoneID) }

    // MARK: - Lifecycle

    /// Starts syncing with the library as it is now. Call once at launch, early, so background pushes find an
    /// engine waiting. Does nothing (status `.off`) when the reader turned sync off or this build has no iCloud.
    func start(initial: LeafData) {
        started = true
        mirror = initial
        guard initial.preferences.syncEnabled, CloudSync.isAvailable else {
            if engine != nil { detachEngine(markStopped: true) }
            status = .off
            return
        }
        guard engine == nil else { return }

        var saved = loadState()
        // Saved by a build that understood fewer record types: forget the sync position (not the local data, nor
        // the pending catch-up below) so everything that build skipped is fetched again.
        let outdated = saved?.engine != nil && SyncPolicy.needsFullFetch(savedLayout: saved?.layout)
        if outdated { saved?.engine = nil }
        lastSynced = saved?.lastSynced
        latestSerialization = saved?.engine
        let proxy = SyncDelegateProxy()
        proxy.owner = self
        self.proxy = proxy
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: saved?.engine,
            delegate: proxy
        )
        engine = CKSyncEngine(configuration)
        status = .syncing

        if saved?.engine == nil && !outdated {
            seedEverything()
        } else {
            // The engine kept its own queue. Add anything that changed while it was not looking: sync switched off,
            // or the app stopped before the queue was saved. After an outdated layout the old queue is gone too, so
            // the undated records (dismissals, challenges, preferences) go again as well.
            let since = saved?.lastSynced.map { $0.addingTimeInterval(-CloudSync.catchUpSlack) }
            let undated = outdated || (saved?.stoppedByUser ?? true)
            queueSaves(SyncDiff.recordNames(in: mirror, changedSince: since, includeUndated: undated))
        }
        Task { await refreshAccountStatus() }
    }

    /// Stops syncing (the reader switched it off). Local data is untouched and nothing is deleted from iCloud.
    func stop() {
        if engine != nil { detachEngine(markStopped: true) }
        status = .off
        pendingChanges = 0
    }

    /// Throws away the engine's saved state and starts over: fetch everything, send everything. The merge keeps
    /// whichever copy is newer, so this is safe to offer as a "Sync now" repair.
    func forceFullSync() {
        guard started else { return }
        let data = mirror
        detachEngine(markStopped: false)
        removeStateFile()
        latestSerialization = nil
        systemFields = [:]
        start(initial: data)
    }

    /// Removes the cloud copy (used by "Reset everything"). Local data is the caller's to clear. Afterwards call
    /// `start(initial:)` with the new, empty library to begin a fresh cloud copy. Other devices keep their own data
    /// and will put it back; see docs/SYNC.md.
    @discardableResult
    func deleteCloudData() async -> Bool {
        detachEngine(markStopped: true)
        removeStateFile()
        latestSerialization = nil
        systemFields = [:]
        pendingChanges = 0
        status = .off
        guard CloudSync.isAvailable else { return true }
        do {
            let result = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
            if case .failure(let error)? = result.deleteResults[zoneID] { return deletionFinished(with: error) }
            return true
        } catch {
            return deletionFinished(with: error)
        }
    }

    private func deletionFinished(with error: Error) -> Bool {
        if (error as? CKError)?.code == .zoneNotFound { return true }
        status = .error("Leaf couldn’t clear its iCloud copy. Check your connection and try again.")
        return false
    }

    private func detachEngine(markStopped: Bool) {
        let old = engine
        proxy?.owner = nil
        proxy = nil
        engine = nil
        if markStopped { saveState(stoppedByUser: true) }
        Task { await old?.cancelOperations() }
    }

    // MARK: - Local changes

    /// Tells the sync layer the library changed. Call it from the store's `commit()` with the data before and after
    /// (not after merging remote data, which the mirror already holds).
    func localDataChanged(old: LeafData, new: LeafData) {
        mirror = new
        guard started else { return }
        guard new.preferences.syncEnabled else {
            if engine != nil { stop() }
            return
        }
        guard engine != nil else {
            start(initial: new)
            return
        }
        let changes = SyncDiff.changes(from: old, to: new)
        queueDeletes(changes.deletes)
        queueSaves(changes.saves)
    }

    private func seedEverything() {
        engine?.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        queueSaves(SyncDiff.recordNames(in: mirror, changedSince: nil, includeUndated: true))
    }

    private func queueSaves(_ names: [String]) {
        guard let engine, !names.isEmpty else { return }
        let ids = names.map(recordID)
        engine.state.remove(pendingRecordZoneChanges: ids.map { .deleteRecord($0) })
        engine.state.add(pendingRecordZoneChanges: ids.map { .saveRecord($0) })
        refreshPending()
    }

    private func queueDeletes(_ names: [String]) {
        guard let engine, !names.isEmpty else { return }
        let ids = names.map(recordID)
        engine.state.remove(pendingRecordZoneChanges: ids.map { .saveRecord($0) })
        engine.state.add(pendingRecordZoneChanges: ids.map { .deleteRecord($0) })
        refreshPending()
    }

    private func refreshPending() {
        pendingChanges = engine?.state.pendingRecordZoneChanges.count ?? 0
    }

    // MARK: - Events

    fileprivate func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            latestSerialization = update.stateSerialization
            saveState(stoppedByUser: false)
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedDatabaseChanges(let changes):
            handleDatabaseChanges(changes)
        case .fetchedRecordZoneChanges(let changes):
            handleFetched(changes)
        case .sentDatabaseChanges(let sent):
            if !sent.failedZoneSaves.isEmpty { lastError = "Leaf couldn’t set up its space in iCloud. It will try again." }
        case .sentRecordZoneChanges(let sent):
            handleSent(sent)
        case .willFetchChanges, .willSendChanges:
            lastError = nil
            if status != .noAccount { status = .syncing }
        case .didFetchChanges:
            settle(afterSend: false)
        case .didSendChanges:
            settle(afterSend: true)
        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    private func settle(afterSend: Bool) {
        refreshPending()
        if let message = lastError {
            status = .error(message)
            return
        }
        guard status != .noAccount else { return }
        if afterSend || pendingChanges == 0 {
            lastSynced = clock()
            status = .idle(lastSynced: lastSynced)
            saveState(stoppedByUser: false)
        } else {
            status = .syncing
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn, .switchAccounts:
            // A different (or newly available) account has none of our records yet. The local library stays; it is
            // sent up, and merged with whatever that account already holds.
            systemFields = [:]
            status = .syncing
            seedEverything()
        case .signOut:
            systemFields = [:]
            latestSerialization = nil
            removeStateFile()
            status = .noAccount
        @unknown default:
            break
        }
    }

    private func handleDatabaseChanges(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges) {
        // Our zone was deleted: the reader cleared the iCloud copy, another device was reset, or the system purged it.
        // The data on this device is the master, so keep it and put it back.
        guard changes.deletions.contains(where: { $0.zoneID == zoneID }) else { return }
        systemFields = [:]
        seedEverything()
    }

    private func handleFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        var records: [SyncRecord] = []
        for modification in changes.modifications {
            let record = modification.record
            systemFields[record.recordID.recordName] = archive(record)
            if let plain = syncRecord(from: record) { records.append(plain) }
        }
        var removed: [String] = []
        for deletion in changes.deletions {
            let name = deletion.recordID.recordName
            systemFields[name] = nil
            removed.append(name)
        }
        receive(records: records, removed: removed)
    }

    /// Merges fetched records into the mirror and tells the store. A tombstone record that was removed means its
    /// device took the deletion back, so the tombstone goes too. Whatever the server turns out to be behind on is
    /// queued to be saved back; whatever matches it is not sent again.
    private func receive(records: [SyncRecord], removed: [String]) {
        let removedTombstones: [SyncTombstoneKey] = removed.compactMap { name in
            if case .tombstone(let kind, let key)? = SyncRecordName(name) { return SyncTombstoneKey(kind: kind, key: key) }
            return nil
        }
        let before = mirror
        let base = before.removingTombstones(removedTombstones)
        let delta = SyncRecordMapper.delta(from: records, basedOn: base)
        let merged = base.merged(with: delta, now: clock())
        let behind = Set(SyncDiff.behind(fetched: records.map(\.name), remote: delta, merged: merged))
        let restore = SyncDiff.restorable(deleted: removed, in: merged)
        mirror = merged

        if let engine {
            let pending = Set(engine.state.pendingRecordZoneChanges)
            let settled = records.map(\.name)
                .filter { !behind.contains($0) && pending.contains(.saveRecord(recordID($0))) }
                .map { CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID($0)) }
            if !settled.isEmpty { engine.state.remove(pendingRecordZoneChanges: settled) }
        }
        queueSaves(Array(behind) + restore)
        if SyncDiff.differs(before, merged) { onRemoteData?(merged) }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        for record in sent.savedRecords { systemFields[record.recordID.recordName] = archive(record) }
        var resave: [String] = []
        for failure in sent.failedRecordSaves {
            let name = failure.record.recordID.recordName
            switch failure.error.code {
            case .serverRecordChanged:
                // Someone saved this record first. Merge theirs in; if ours still has more, it is queued again.
                if let server = failure.error.serverRecord {
                    systemFields[name] = archive(server)
                    if let plain = syncRecord(from: server) { receive(records: [plain], removed: []) }
                }
            case .zoneNotFound:
                engine?.state.add(pendingDatabaseChanges: [.saveZone(zone)])
                resave.append(name)
            case .unknownItem:
                systemFields[name] = nil
                resave.append(name)
            case .quotaExceeded:
                lastError = "Your iCloud storage is full, so Leaf can’t back up new changes."
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .requestRateLimited,
                 .operationCancelled, .limitExceeded, .notAuthenticated:
                // The engine retries these on its own.
                break
            default:
                lastError = "Leaf couldn’t reach iCloud just now. It will keep trying."
            }
        }
        queueSaves(resave)
    }

    // MARK: - Sending

    fileprivate func nextBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let slice = Array(pending.prefix(CloudSync.batchSize))
        guard !slice.isEmpty else { return nil }

        let snapshot = SyncSnapshot(mirror)
        var built: [CKRecord.ID: CKRecord] = [:]
        var unsendable: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in slice {
            guard case .saveRecord(let id) = change else { continue }
            if let entity = snapshot[id.recordName], let plain = SyncRecordMapper.record(for: entity) {
                built[id] = ckRecord(from: plain, id: id)
            } else {
                // The thing was deleted since it was queued, or cannot be stored. Nothing to send.
                unsendable.append(change)
            }
        }
        if !unsendable.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: unsendable) }
        let sendable = slice.filter { !unsendable.contains($0) }
        guard !sendable.isEmpty else { return nil }
        let records = built
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: sendable) { id in records[id] }
    }

    // MARK: - Records

    /// A CloudKit record for a plain one. The payload goes in an encrypted field, so the contents of the reader's
    /// journal are end-to-end encrypted even without Advanced Data Protection.
    private func ckRecord(from plain: SyncRecord, id: CKRecord.ID) -> CKRecord {
        let record: CKRecord
        if let archived = systemFields[plain.name], let restored = unarchive(archived) {
            record = restored
        } else {
            record = CKRecord(recordType: plain.type.rawValue, recordID: id)
        }
        if let payload = plain.payload { record.encryptedValues[SyncRecord.payloadField] = payload as NSData }
        if let updated = plain.updatedAt { record[SyncRecord.updatedAtField] = updated as NSDate }
        if let schema = plain.schema { record[SyncRecord.schemaField] = NSNumber(value: schema) }
        return record
    }

    private func syncRecord(from record: CKRecord) -> SyncRecord? {
        guard let type = SyncRecordType(rawValue: record.recordType) else { return nil }
        var fields: [String: SyncValue] = [:]
        if let payload = record.encryptedValues[SyncRecord.payloadField] as? Data { fields[SyncRecord.payloadField] = .data(payload) }
        if let updated = record[SyncRecord.updatedAtField] as? Date { fields[SyncRecord.updatedAtField] = .date(updated) }
        if let schema = record[SyncRecord.schemaField] as? NSNumber { fields[SyncRecord.schemaField] = .int(schema.int64Value) }
        return SyncRecord(name: record.recordID.recordName, type: type, fields: fields)
    }

    private func archive(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private func unarchive(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }

    // MARK: - Account and saved state

    private func refreshAccountStatus() async {
        guard let account = try? await container.accountStatus() else { return }
        switch account {
        case .noAccount, .restricted:
            status = .noAccount
        case .available:
            if status == .noAccount { status = .syncing }
        case .couldNotDetermine, .temporarilyUnavailable:
            break
        @unknown default:
            break
        }
    }

    private struct SavedState: Codable {
        var engine: CKSyncEngine.State.Serialization?
        var lastSynced: Date?
        /// True when sync was switched off (or reset) last time, so changes with no timestamp may have been missed.
        var stoppedByUser: Bool
        /// `SyncPolicy.syncLayout` when this was saved; nil before layouts were recorded.
        var layout: Int?
    }

    private func loadState() -> SavedState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: data)
    }

    private func saveState(stoppedByUser: Bool) {
        let state = SavedState(engine: latestSerialization, lastSynced: lastSynced, stoppedByUser: stoppedByUser, layout: SyncPolicy.syncLayout)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func removeStateFile() {
        try? FileManager.default.removeItem(at: stateURL)
    }
}

/// CKSyncEngine calls its delegate from its own queues. This small object forwards every call to the main-actor
/// `CloudSync`, and is cut loose (`owner = nil`) when an engine is replaced so a stale engine cannot touch the new one.
private final class SyncDelegateProxy: CKSyncEngineDelegate, @unchecked Sendable {
    weak var owner: CloudSync?

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await owner?.handle(event)
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await owner?.nextBatch(context, syncEngine: syncEngine)
    }
}
#endif
