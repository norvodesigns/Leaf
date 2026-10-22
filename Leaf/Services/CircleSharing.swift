import Foundation
import Observation
#if canImport(CloudKit)
import CloudKit
import SwiftUI
import UIKit

/// Shares reading circles with other people over iCloud (CKShare), so friends move their own pages instead of the
/// reader moving them by hand.
///
/// Off unless the build has iCloud (`CloudSync.isAvailable`, the `LEAF_CLOUDKIT_ENABLED` flag) and the reader has
/// iCloud on in Settings. TestFlight builds without the flag never touch any of this, and the Invite button does not
/// show.
///
/// How it works:
/// - Each shared circle gets its own zone in the owner's private database (`Circle-<uuid>`), holding one `LeafCircle`
///   record (the same payload as the private sync record), and the zone is shared as a whole.
/// - Everyone's copy also stays in their own library (`LeafData.circles`), so it shows offline, is in backups and
///   syncs to their other devices as usual. This class only moves the shared copy in and out.
/// - Each person moves only their own member: their page comes from their library (`CircleShareRules.withMyPage`).
///   Fetched copies go through `CircleShareRules.localized` (who is "me" here) and `LibraryStore.mergeCircles` (the
///   sync merge: newest circle, then newest copy of each member), so two people reading at once both keep their pages.
/// - Deleting a shared circle deletes the owner's zone, which ends the share; a participant deleting it leaves.
///
/// Untested on devices: it needs two iCloud accounts. docs/SYNC.md lists what to check.
@MainActor
@Observable
final class CircleSharing {
    static let shared = CircleSharing()

    /// Where a shared circle lives.
    struct Link: Codable, Hashable, Sendable {
        var circleID: UUID
        var zoneName: String
        /// The zone owner's user record name; `CKCurrentUserDefaultName` for circles this reader shared.
        var ownerName: String
        var isOwner: Bool
    }

    enum Failure: LocalizedError {
        case unavailable
        case noCircle

        var errorDescription: String? {
            switch self {
            case .unavailable: "Sharing needs iCloud. Turn it on in Settings › iCloud."
            case .noCircle: "That circle isn’t on this phone any more."
            }
        }
    }

    /// Circles shared with or by this reader, by circle id.
    private(set) var links: [UUID: Link] = [:]
    /// The last thing that went wrong, for the circle page.
    private(set) var lastError: String?

    @ObservationIgnored private weak var library: LibraryStore?
    /// The copy last sent or fetched per circle, so an unchanged circle is not sent again.
    @ObservationIgnored private var inStep: [UUID: ReadingCircle] = [:]
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var myName: String?
    /// Names to join with, from invitations accepted before their circle was fetched, by zone name.
    @ObservationIgnored private var joinNames: [String: String] = [:]
    @ObservationIgnored private let linksURL: URL

    init(linksURL: URL = CircleSharing.defaultLinksURL) {
        self.linksURL = linksURL
        loadLinks()
    }

    nonisolated static var defaultLinksURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Leaf", isDirectory: true)
            .appendingPathComponent("circle-shares.json")
    }

    /// Whether this build can share at all (the iCloud flag). The reader's own switch is `isOn(for:)`.
    static var isAvailable: Bool { CloudSync.isAvailable }

    /// Off too while sync waits on a new iCloud account, so nothing goes out under it before the reader agrees.
    func isOn(for library: LibraryStore) -> Bool {
        Self.isAvailable && library.preferences.syncEnabled && library.sync?.isPausedForNewAccount != true
    }

    func isShared(_ circleID: UUID) -> Bool { links[circleID] != nil }

    private var container: CKContainer { CKContainer(identifier: CloudSync.containerIdentifier) }

    // MARK: - Lifecycle

    /// Call once at launch with the library, and again whenever the app comes to the front (it fetches).
    func connect(_ library: LibraryStore) {
        self.library = library
        guard isOn(for: library) else { return }
        Task { await refresh() }
    }

    /// The library changed: send any shared circle whose copy moved on, a moment later so a burst of edits goes once.
    func libraryChanged() {
        guard let library, isOn(for: library), !links.isEmpty else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.pushChanges()
        }
    }

    // MARK: - Sharing a circle

    /// The share for a circle, made on first use: the circle's zone, its record and a zone-wide CKShare. Present it
    /// with `CircleShareSheet`.
    func share(for circleID: UUID) async throws -> CKShare {
        guard let library, isOn(for: library) else { throw Failure.unavailable }
        guard let found = library.data.circles.first(where: { $0.id == circleID }) else { throw Failure.noCircle }
        let me = try await currentUserName()
        let circle = CircleShareRules.claimingMe(found, me: me, now: Date())
        if circle != found { library.saveCircle(circle) }

        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: CircleShareRules.zoneName(for: circleID), ownerName: CKCurrentUserDefaultName)
        if let existing = try? await database.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)) as? CKShare {
            remember(Link(circleID: circleID, zoneName: zoneID.zoneName, ownerName: CKCurrentUserDefaultName, isOwner: true))
            return existing
        }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        let record = try makeRecord(circle, id: recordID(circleID, zoneID: zoneID), base: nil)
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = circle.name as CKRecordValue
        share.publicPermission = .none
        let (saved, _) = try await database.modifyRecords(saving: [record, share], deleting: [], savePolicy: .allKeys)
        var made: CKShare?
        for (_, result) in saved {
            let value = try result.get()
            if let value = value as? CKShare { made = value }
        }
        remember(Link(circleID: circleID, zoneName: zoneID.zoneName, ownerName: CKCurrentUserDefaultName, isOwner: true))
        inStep[circleID] = circle
        return made ?? share
    }

    /// The owner stopped sharing (from the share sheet): the zone goes, the circle stays in the library.
    func stoppedSharing(_ circleID: UUID) {
        guard let link = links[circleID] else { return }
        forget(circleID)
        Task { try? await database(for: link).modifyRecordZones(saving: [], deleting: [zoneID(for: link)]) }
    }

    // MARK: - Accepting an invitation

    /// An invitation the reader tapped. The circle arrives with the next fetch, which this starts.
    func accept(_ metadata: CKShare.Metadata) async {
        guard let library, isOn(for: library) else {
            lastError = Failure.unavailable.errorDescription
            return
        }
        do {
            _ = try await container.accept(metadata)
            let zoneID = metadata.share.recordID.zoneID
            guard let circleID = CircleShareRules.circleID(inZone: zoneID.zoneName) else { return }
            if let components = metadata.share.currentUserParticipant?.userIdentity.nameComponents {
                joinNames[zoneID.zoneName] = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            }
            remember(Link(circleID: circleID, zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, isOwner: false))
            await refresh()
        } catch {
            lastError = "Couldn’t join that circle. \(error.localizedDescription)"
        }
    }

    // MARK: - Fetching

    /// Fetches every shared circle (and finds circles shared with this reader on another device), merges them into
    /// the library, then sends anything this side had newer.
    func refresh() async {
        guard let library, isOn(for: library) else { return }
        guard let me = try? await currentUserName() else { return }
        if let zones = try? await container.sharedCloudDatabase.allRecordZones() {
            for zone in zones {
                guard let circleID = CircleShareRules.circleID(inZone: zone.zoneID.zoneName), links[circleID] == nil else { continue }
                remember(Link(circleID: circleID, zoneName: zone.zoneID.zoneName, ownerName: zone.zoneID.ownerName, isOwner: false))
            }
        }
        for link in links.values {
            do {
                let record = try await database(for: link).record(for: recordID(link.circleID, zoneID: zoneID(for: link)))
                guard var circle = self.circle(from: record) else { continue }
                circle = CircleShareRules.localized(circle, me: me)
                if !link.isOwner, !circle.members.contains(where: { $0.remoteID == me }) {
                    let token = CircleStore.friendTokens[circle.members.count % CircleStore.friendTokens.count]
                    circle = CircleShareRules.joining(circle, me: me, name: joinNames[link.zoneName] ?? "", paletteToken: token, now: Date())
                    joinNames[link.zoneName] = nil
                }
                library.mergeCircles([circle])
                inStep[link.circleID] = library.data.circles.first { $0.id == link.circleID }
            } catch let error as CKError where Self.isGone(error) {
                // The owner deleted the circle or stopped sharing: the reader keeps their copy, now a local circle.
                forget(link.circleID)
            } catch {
                lastError = error.localizedDescription
            }
        }
        await pushChanges()
    }

    // MARK: - Sending

    private func pushChanges() async {
        guard let library, isOn(for: library), let me = try? await currentUserName() else { return }
        for link in links.values {
            guard var circle = library.data.circles.first(where: { $0.id == link.circleID }) else {
                // Deleted here: the owner ends the share, a participant leaves it.
                forget(link.circleID)
                try? await database(for: link).modifyRecordZones(saving: [], deleting: [zoneID(for: link)])
                continue
            }
            circle = CircleShareRules.localized(circle, me: me)
            let page = library.item(circle.book.id).map(\.currentPage)
            let moved = CircleShareRules.withMyPage(circle, page: page, now: Date())
            if moved != circle {
                library.saveCircle(moved)
                circle = moved
            }
            guard inStep[link.circleID] != circle else { continue }
            await save(circle, link: link, me: me, retries: 2)
        }
    }

    /// Saves the circle's record, merging in the server's copy first so nobody's page is lost.
    private func save(_ circle: ReadingCircle, link: Link, me: String, retries: Int) async {
        guard let library else { return }
        let database = database(for: link)
        let id = recordID(link.circleID, zoneID: zoneID(for: link))
        do {
            var merged = circle
            var base: CKRecord?
            do {
                let server = try await database.record(for: id)
                base = server
                if let theirs = self.circle(from: server) {
                    library.mergeCircles([CircleShareRules.localized(theirs, me: me)])
                    merged = library.data.circles.first { $0.id == circle.id } ?? circle
                }
            } catch let error as CKError where error.code == .unknownItem {
                base = nil
            }
            let record = try makeRecord(merged, id: id, base: base)
            let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged)
            for (_, result) in saved { _ = try result.get() }
            inStep[link.circleID] = merged
            lastError = nil
        } catch let error as CKError where error.code == .serverRecordChanged && retries > 0 {
            await save(circle, link: link, me: me, retries: retries - 1)
        } catch let error as CKError where Self.isGone(error) {
            forget(link.circleID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Records

    private func makeRecord(_ circle: ReadingCircle, id: CKRecord.ID, base: CKRecord?) throws -> CKRecord {
        guard let plain = SyncRecordMapper.record(for: .circle(circle)) else { throw Failure.noCircle }
        let record = base ?? CKRecord(recordType: SyncRecordType.circle.rawValue, recordID: id)
        if let payload = plain.payload { record.encryptedValues[SyncRecord.payloadField] = payload as NSData }
        if let updated = plain.updatedAt { record[SyncRecord.updatedAtField] = updated as NSDate }
        if let schema = plain.schema { record[SyncRecord.schemaField] = NSNumber(value: schema) }
        return record
    }

    private func circle(from record: CKRecord) -> ReadingCircle? {
        guard record.recordType == SyncRecordType.circle.rawValue,
              let payload = record.encryptedValues[SyncRecord.payloadField] as? Data else { return nil }
        let plain = SyncRecord(name: record.recordID.recordName, type: .circle, fields: [SyncRecord.payloadField: .data(payload)])
        guard case .circle(let circle)? = SyncRecordMapper.entity(from: plain) else { return nil }
        return circle
    }

    private func recordID(_ circleID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: SyncRecordName.circle(circleID).string, zoneID: zoneID)
    }

    private func zoneID(for link: Link) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: link.zoneName, ownerName: link.ownerName)
    }

    private func database(for link: Link) -> CKDatabase {
        link.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    private func currentUserName() async throws -> String {
        if let myName { return myName }
        let name = try await container.userRecordID().recordName
        myName = name
        return name
    }

    private static func isGone(_ error: CKError) -> Bool {
        let gone: [CKError.Code] = [.zoneNotFound, .userDeletedZone, .unknownItem]
        return gone.contains(error.code)
    }

    // MARK: - Links on disk

    private func remember(_ link: Link) {
        guard links[link.circleID] != link else { return }
        links[link.circleID] = link
        saveLinks()
    }

    private func forget(_ circleID: UUID) {
        guard links[circleID] != nil else { return }
        links[circleID] = nil
        inStep[circleID] = nil
        saveLinks()
    }

    private func loadLinks() {
        guard let bytes = try? Data(contentsOf: linksURL), let saved = try? JSONDecoder().decode([Link].self, from: bytes) else { return }
        links = Dictionary(saved.map { ($0.circleID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func saveLinks() {
        do {
            try FileManager.default.createDirectory(at: linksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = try JSONEncoder().encode(links.values.sorted { $0.circleID.uuidString < $1.circleID.uuidString })
            try bytes.write(to: linksURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Kept in memory; the next change writes again.
        }
    }

    /// Erase everything: forgets which circles were shared. Zones on the server are left for iCloud's own reset.
    func eraseLinks() {
        links = [:]
        inStep = [:]
        try? FileManager.default.removeItem(at: linksURL)
    }
}

// MARK: - The share sheet

/// The system's iCloud sharing sheet for a circle: invite people, see who joined, stop sharing.
struct CircleShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let circleID: UUID
    let title: String

    func makeCoordinator() -> Coordinator { Coordinator(circleID: circleID, title: title) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: CloudSync.containerIdentifier))
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let circleID: UUID
        let title: String

        init(circleID: UUID, title: String) {
            self.circleID = circleID
            self.title = title
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            let id = circleID
            Task { @MainActor in CircleSharing.shared.stoppedSharing(id) }
        }
    }
}

// MARK: - Invitations from outside

/// Hands iCloud invitations to `CircleSharing`. Installed only in builds with iCloud (see `LeafAppDelegate`).
@MainActor
final class LeafSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        Task { @MainActor in await CircleSharing.shared.accept(metadata) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in await CircleSharing.shared.accept(metadata) }
    }
}

@MainActor
final class LeafAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        // Without iCloud the scene stays exactly SwiftUI's own.
        if CircleSharing.isAvailable, connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = LeafSceneDelegate.self
        }
        return configuration
    }
}
#endif
