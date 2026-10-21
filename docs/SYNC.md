# iCloud sync and backup

Leaf syncs and backs up through the reader's own private CloudKit database. There is no account and no server, and
nothing leaves the reader's iCloud, so the App Privacy answer stays "Data Not Collected".

The local library file (`library.json`) is always the master. iCloud is a replica: it can be switched off, cleared or
lost without the reader losing anything on their devices. Every rule below leans the same way: **when in doubt, keep
the data.**

## Pieces

| Piece | Where | Compiles on |
|---|---|---|
| Merge | `Shared/Sync/LeafDataMerge.swift` | iPhone, watch, Linux |
| Record names, entities, mapping | `Shared/Sync/SyncRecordName.swift`, `SyncEntity.swift`, `SyncRecord.swift`, `SyncRecordMapper.swift` | iPhone, watch, Linux |
| What changed | `Shared/Sync/SyncDiff.swift` | iPhone, watch, Linux |
| Status and limits | `Shared/Sync/SyncStatus.swift` | iPhone, watch, Linux |
| Transport | `Leaf/Services/CloudSync.swift` (`CKSyncEngine`) | iPhone only |
| Tests | `LeafTests/SyncTests.swift` | Linux (and Xcode) |

Everything that decides anything is pure and tested on Linux. The transport only moves records.

## What is stored

One CloudKit record per thing, in the custom zone `LeafZone` of the private database of container
`iCloud.com.norvodesigns.leaf`. Each record has the same three fields:

- `payload`: the entity as JSON, the same format as the library file (an **encrypted** field, so journal text is
  end-to-end encrypted even without Advanced Data Protection). Older payloads decode through the models' tolerant
  decoders, and unknown fields from a newer Leaf are ignored.
- `updatedAt`: the entity's own stamp, for the CloudKit console. Merging reads the payload, never this.
- `schema`: the layout version (1).

| Record name | Record type | Entity |
|---|---|---|
| `item.<bookID>` | `LeafItem` | `LibraryItem` |
| `session.<uuid>` | `LeafSession` | `ReadingSession` |
| `journal.<uuid>` | `LeafJournal` | `JournalEntry` |
| `prefs` | `LeafPreferences` | `ReadingPreferences` |
| `speedtest.<ms>-<passage>` | `LeafSpeedTest` | `SpeedTestResult` |
| `dismissal.<bookID>` | `LeafDismissal` | a "not for me" |
| `challenge.<id>.<year or none>` | `LeafChallenge` | `ChallengeEnrollment` |
| `tombstone.<kind>.<key>` | `LeafTombstone` | `Tombstone` |
| `tea.<uuid>` | `LeafTea` | `CabinetTea` (a tea in the reader's cabinet) |
| `tasting.<uuid>` | `LeafTasting` | `TastingNote` |

Record names must be ASCII and at most 255 characters, so ids are escaped (`%XX` for anything but letters, digits,
`-` and `_`, which also frees the dot to separate parts). A name that would still be too long, or a payload over
900 KB, is never queued; that one item simply stays local.

**Never synced:** the live `ActiveSession` (the watch bridge owns it), and these device settings, which always keep
the local value: `hapticsLevel`, `appearance`, `syncEnabled` (switching iCloud off on the phone must not switch it off
on the iPad).

## Merge rules

`LeafData.merged(with:now:)` is a pure function. For a fixed `now` it is commutative, associative and idempotent
(property-tested over thousands of random edit histories, including exact timestamp ties). The only differences by side
are the live session and the device's own settings, which stay local. Output is in a canonical order.

| Data | Rule |
|---|---|
| Library items | Per book id, the newest `updatedAt` wins **as a whole**. A tie goes to the larger JSON, so both sides pick the same copy. |
| Deleting an item | A tombstone removes an item only if `deletedAt` is **strictly later** than the item's `updatedAt`. Equal keeps the item. Re-adding after a delete wins because its stamp is newer. |
| Progress | After merging, a book on the Reading or Paused shelf is raised to the furthest page any of its sessions reached (clamped to its page count). Never lowered; `updatedAt` is not touched. Sessions that ended more than a day before the book's `startedAt` are ignored, and so are sessions that ended by the finish of the latest read-through kept on the book, so a restarted (re-read) book is not dragged back, even when it is begun again on the day it was finished. |
| Sessions | Union by id, append-only. Sessions of a deleted book stay for the statistics. |
| Journal | Newest `updatedAt` per id, plus tombstones, same rule as items. |
| Read-throughs (`LibraryItem.reads`) | Merged one by one whichever copy of the book wins: newest `updatedAt` per read-through, a `read` tombstone removes one only if strictly later. A read-through's id comes from the book and its finish (to the second), so two devices that keep the same finish keep one. Earlier read-throughs from before reads were kept are recovered from sessions on load, unstamped, on every device alike. |
| Tea cabinet, tasting notes | Newest `updatedAt` per id wins as a whole (a tie goes to the larger JSON); a `cabinetTea` / `tasting` tombstone removes one only if strictly later. Cabinet in `addedAt` order, notes in `createdAt` order. A book's pinned tea (`LibraryItem.pairedTeaID`) travels with the item. Sessions save a catalog id, or `custom.<uuid>` for a tea of the reader's own, so a session outlives the tea it names. |
| Dismissed ids | Union, minus any id with a dismissal tombstone on either side. Rare ambiguity: a dismissal has no timestamp, so if one device takes "not for me" back while another dismisses the same book again before hearing of it, the tombstone wins. Devices still agree, and the worst case is a book that can be suggested again. |
| Challenges | Union by (id, year); if both sides joined, the later join counts. A tombstone removes an enrollment only if it is later than that enrollment's `joinedAt`. A tombstone keyed by the bare challenge id (what the store writes today) covers every year joined before it; `SyncKey.challengeTombstoneKey(id:year:)` targets one year. |
| Speed tests | Union keyed by date (to the millisecond) and passage. Kept oldest first so `speedTests.last` is the latest. |
| Preferences | Newest `updatedAt` wins as a whole, except: device settings stay local; `hasOnboarded` is true if either side is; `onboardedAt` is the earliest known. On an equal stamp, settings the reader changed beat untouched defaults (so a new device cannot wipe an old one's choices), then the larger JSON wins. |
| `version` | The higher. |
| Tombstones | Union (latest `deletedAt` per key). Dropped when older than **90 days**, before they are applied. After that a device that was off for longer can bring a deleted item back. A removed read-through's tombstone (`read`) never expires: every device recovers old read-throughs from sessions on load, and the tombstone is what keeps a removed one off. |
| Live session | Kept from the local side; dropped if its book was deleted elsewhere. |

Because whole preferences are last-writer-wins, two devices changing different settings at nearly the same time
keep only the newer device's settings. That is the cost of the simple rule. `LibraryStore.updatePreferences` should
move the stamp only when a synced field changed (see integration), otherwise toggling haptics could hide a real change
made elsewhere.

## How records travel

1. The store calls `localDataChanged(old:new:)` on every commit. `SyncDiff.changes` lists the records to save and to
   delete (the live session, haptics and the like queue nothing). Removing a book deletes `item.<id>` and saves
   `tombstone.item.<id>`; re-adding does the reverse.
2. `CKSyncEngine` sends batches of at most 200. The `CKRecord` is built at send time from the current mirror, so a
   change never sends stale data. Anything deleted since it was queued is dropped from the queue.
3. Fetched records are merged into the mirror (`merged(with:)`) and handed to the store through `onRemoteData`.
   Records that merge to exactly what the server holds are not sent back; records the server is *behind* on (this
   device had something newer) are queued to be saved.
4. A removed tombstone record means its device took the deletion back, so the tombstone goes from the others too. Any
   other record the server reports deleted is **put back** if this device still holds it after merging: a delete can
   destroy a newer edit made elsewhere at the same moment, and without this the two devices would disagree for good.
5. The engine's state is saved to `Application Support/Leaf/sync-state.bin` (with the time of the last finished
   sync), so a restart resumes where it left off. On start it also queues anything newer than the last sync, which
   catches changes made while sync was off or just before a crash.

## Failure modes

| What happens | What Leaf does |
|---|---|
| Offline, rate limited, zone busy, service unavailable | The engine retries by itself. Status stays `.syncing`. |
| Two devices save the same record | `serverRecordChanged`: the server's copy is merged in; ours is saved again only if it still has more. |
| Zone missing (`zoneNotFound`) | Recreates `LeafZone` and re-queues the save. |
| Record gone on the server (`unknownItem`) | Saves it again as new. |
| iCloud storage full | Status `.error("Your iCloud storage is full, ...")`. Nothing local is lost; changes upload once space is free (or on **Sync now**). |
| Signed out of iCloud | Status `.noAccount`. Local data is untouched. |
| Signed in, or switched accounts | The whole library is queued for the new account and merged with whatever it already holds. |
| Cloud copy deleted (Settings, another device's Reset, purge) | This device keeps its data and puts it back. See Reset below. |
| A record this version cannot read (newer Leaf, damage) | Skipped and left alone on the server; never deleted. The sync position still moves past it, so the saved state records `SyncPolicy.syncLayout`; a build with a higher layout drops an older state once and fetches the whole zone (merging is idempotent), which picks up everything the older build skipped. Raise `syncLayout` with every new record type, tombstone kind or synced field. |
| Another Leaf version edits an item | Fields it does not know are dropped from its copy. Newer Leaf versions should keep `Codable` additions optional. |
| CloudKit not available in this build (no entitlement, test host) | `CloudSync.isAvailable` is false and the whole thing stays off. CloudKit aborts a process that lacks the entitlement, so this is an explicit opt-in (see below). |

## First launch with existing data on both sides

Say the phone has a library and the iPad has a different one, and iCloud is empty.

1. The phone starts first. There is no saved engine state, so it queues the zone and every record, and uploads them.
2. The iPad starts. It fetches the phone's records and merges them with its own: books and sessions from both appear;
   a book on both is resolved by the newest stamp; preferences are resolved by the newest stamp; dismissals and
   challenges are united.
3. The iPad then uploads what the server lacks. Records the phone already uploaded and that merge to the same thing are
   not sent again.
4. The phone fetches the iPad's additions. Both end identical.

Nothing is deleted in this process, because deletions only come from tombstones the store wrote when a reader deleted
something. A device that has never synced has no tombstones the other side could misread.

A brand-new device (empty library, default preferences) restores everything from iCloud, including having
`hasOnboarded` set, so a reader who reinstalls Leaf does not have to onboard again.

## Reset everything

`CloudSync.deleteCloudData()` deletes `LeafZone` (which removes every record) and the saved engine state. The store
should then clear its own data and call `start(initial:)` with the empty library.

Reset is per device. Other devices that still hold data will see the zone deleted, **keep their data, and upload it
again**, so a library can come back from another device. This is deliberate: a cleared cloud copy (the reader freed
space in Settings, the system purged it) must never wipe a device. To remove a library everywhere, reset each device
(the Reset confirmation should say so). Turning sync off and on is different: switching off stops syncing and
deletes nothing, switching on catches up.

## CloudKit setup (once)

- Entitlements (already in `Leaf/Leaf.entitlements`): container `iCloud.com.norvodesigns.leaf`, service `CloudKit`,
  `aps-environment`. Info.plist already has `UIBackgroundModes: remote-notification`, which silent change
  notifications need.
- `Info.plist` key `LeafCloudKitEnabled` must be true for CloudKit to start. Make it `$(LEAF_CLOUDKIT_ENABLED)` with the
  build setting defaulting to `NO`, and set it to `YES` for signed builds. Unsigned CI builds, and runs with
  `-LeafDisableCloudKit`, leave sync off.
- **Deploy the schema to Production** in the CloudKit console before any TestFlight or App Store build. In
  Development the record types appear on first save; Production does not create them. Types: `LeafItem`,
  `LeafSession`, `LeafJournal`, `LeafPreferences`, `LeafSpeedTest`, `LeafDismissal`, `LeafChallenge`,
  `LeafTombstone`, `LeafTea`, `LeafTasting` (the last two new with books and tea), each with `payload` (encrypted bytes), `updatedAt` (date/time) and `schema` (int64).

## Testing it on two devices

1. Sign two simulators (or a simulator and a phone) into the same iCloud account. Use a signed Debug build with
   `LEAF_CLOUDKIT_ENABLED = YES`. The simulator needs Settings, then iCloud, signed in.
2. Add a book on A. Within seconds it appears on B (silent pushes do not reach simulators reliably; foreground B or
   use **Sync now** / `forceFullSync()`).
3. Conflicts: turn on Airplane Mode on both, change the same book on each (rating on A, shelf on B), turn the network
   back on. The newer change wins as a whole on both.
4. Deletes: delete a book on A while B is offline and edits it; reconnect. If B's edit is newer, the book survives
   on both; if A's delete is newer, it is gone on both.
5. Sessions: log a session offline on each; both appear on both, and the book's page is the furthest of the two.
6. Look at the records in the CloudKit console (Development): each has `payload`, `updatedAt`, `schema`.
7. Logic, with no CloudKit: `scripts/linux_tests.sh --filter Sync`.
