# Agent 2: fine-tooth-comb review

A correctness, data-safety and crash review of the whole app, area by area, with fixes pushed to `main`. Engine code
in `Shared/` was checked with the Linux tests (827 passing, run in the official Swift Docker image because swift.org
downloads are blocked here); everything else through CI on macOS.

Files owned by the engineers working in parallel (ambience audio, the Today screen, What's New and the walkthrough)
were read where it mattered but not edited.

## Fixed

| Commit | Area | What was wrong | Fix and regression test |
|---|---|---|---|
| 98ae467 | Persistence | **Data loss.** A library file that couldn't be *read* (protected until the first unlock after a restart, with Leaf woken in the background by the watch, a CloudKit push or an intent) was treated as damaged: it was moved aside as `library.damaged-<time>.json`, the backup couldn't be read either, the store started empty, and the next launch showed onboarding with an empty library. | `Persistence.loadLibrary()` tells unreadable from damaged from missing. The store keeps an empty stand-in, writes nothing (`isLoadDeferred`), iCloud starts only once the library is read, and `loadIfDeferred()` reads it on `protectedDataDidBecomeAvailable` and on becoming active. Tests: `aLibraryThatCantBeReadYetIsNeitherSetAsideNorOverwritten`. |
| 98ae467 | Persistence | Saves raced. A detached save of an older snapshot could finish after `flush()` wrote a newer one (and `applyRemote` relies on the flush to stay ahead of the sync engine's position); a save in flight during Reset could write the erased library back. | `LibraryWriter` serialises writes by generation; an erase bumps the generation so late saves are dropped. Test: `savesLandInOrderAndNothingLandsAfterAnErase`. |
| 98ae467 | Persistence | Every save decoded the whole library to decide whether the 6-hourly backup was due. A missing library file never fell back to its backup. | The age check comes first; a missing file uses the backup. Test: `aMissingLibraryFallsBackToItsBackup`. |
| 98ae467 | Model | One entry this build can't read (a newer build's shelf, tea family, tombstone kind or setting, for example after going back a TestFlight build) failed the whole library file, which then went the "damaged" way above. | Opt-in tolerant decoding (`DecodeSkips`, `Shared/TolerantDecoding.swift`) for the library file only: unreadable entries are left out, unreadable settings fall back to defaults, and the original is kept once as `library.partial.json`. Sync records and backups stay strict (they rely on failure). Tests: `theLibraryFileKeepsWhatItCanReadFromANewerLeaf`, `strictDecodingStillFails…`, `aTolerantDecodeOfACleanFileSkipsNothing`, `aLibraryFromANewerLeafKeepsWhatItCanAndTheOriginal`. |
| 12658f1, 1a25857 | Sync merge | A book begun again within a day of finishing it jumped back to its last page after the next iCloud merge: the finishing session was inside the 24-hour slack of the progress repair. | `SyncMerge.countsTowardCurrentRead`: sessions that ended by the finish of the latest kept read-through belong to it. Property tests (commutative, associative, idempotent) still pass. Test: `aBookBegunAgainOnTheDayItWasFinishedStaysAtTheStart`. |
| 12658f1, 1a25857 | Read-throughs | An earlier read-through recovered from sessions came back on the next launch after the reader removed it (recovery ignored tombstones), and everywhere once the 90-day tombstone expired. | Recovery skips tombstoned reads, and `read` tombstones never expire (docs/SYNC.md updated). Tests: `aRemovedRecoveredReadIsNotRecoveredAgain`, `aRemovedReadThroughStaysRemovedPastTheTombstoneLifetime`. |
| 12658f1, 1a25857 | Store | A session with a non-finite number (a damaged watch message, a manual log of infinite minutes) would make every later save fail silently, because JSON can't hold NaN or infinity. | `log` and `logManual` reject non-finite values. |
| 6f99293 | Reading times | `SlotPlanner.next` added minutes since midnight, so on the two days a year the clocks change every reading time after the change was an hour out. | Wall-clock `date(bySettingHour:)`. Test: `nextSlotGoesByTheWallClockOnTheDayTheClocksChange` (fails on the old code). |
| c6542eb | Copy | Straight apostrophes in 23 UI strings (search rows, Library captions, the watch, a notification, complication text, widget name); the watch said "The end!" and "Finished!". | Typographic apostrophes, full stops. |
| e1d7a99 | Reminders | "Skip today" removed only the snooze, so later reading times that day still fired. A snoozed reminder still fired after the goal was met. "Start reading" on a reminder that launched Leaf did nothing (the hook is set when the tabs appear, after the tap arrives). | Skip removes today's pending reading-time reminders; the snooze goes once the goal is met or a session runs; the tap is held until the hook is set. |
| 0f0f5f2 | Watch, reminders | With the deferred load above, the watch would have been sent an empty snapshot, a session logged on the watch would have found no book, and reminders would have been cleared. | The bridge doesn't push the stand-in and holds watch events until the library is read; reminders aren't rescheduled from it. |
| 0f0f5f2 | App Review | The iPhone app's privacy manifest missed two required-reason APIs: file timestamps (the backup's age) and system boot time (`ProcessInfo.systemUptime` in `Scrub.swift`). App Store Connect flags or rejects such uploads (ITMS-91053). | Declared `C617.1` and `35F9.1`. |
| 215fd1d | Tests | Two wall-clock speed tests had budgets a busy machine misses (the insights one took 607 ms against 500 ms while ~800 other tests ran). | Three times the room; still catches a slow algorithm. `scripts/linux_tests.sh` runs itself in Docker when there is no toolchain. |
| 788c27f | Privacy | "Erase all data" left generated greeting lines (which can name a book), the greeting memory, quiet books kept off the plan, a skipped day and a snoozed reminder naming the book. | `LibraryTraces.erase()` clears Leaf's own UserDefaults keys (except the Focus filter's state and the cozy settings, which reset themselves) and the snooze. |
| 1e460e6 | Accessibility | The session screen dims after 20 seconds and lays a layer that takes the first touch only to wake it. With VoiceOver a double tap activates the element under it, so the layer swallowed the next activation. | No dim with VoiceOver on; turning VoiceOver on wakes the screen. |

## Found but not fixed

| Severity | Where | Finding | Why not fixed, and the suggested fix |
|---|---|---|---|
| Medium | `Leaf/Services/CloudSync.swift`, `LibraryStore.resetEverything` | Reset while iCloud can't be reached (offline): `deleteCloudData` fails and returns, but `started` stays true, so the reader's next change (onboarding again) restarts sync, which fetches the old cloud library and merges it into the erased one. The next launch does the same. | A safe retry needs care I can't verify without devices: persist an "erase pending" flag, retry the zone deletion before the engine starts, show it in Settings, and clear the flag on an account change or `notAuthenticated` so a retry can never delete a *different* account's zone. |
| Medium | `CloudSync.handleAccountChange` | On `.switchAccounts` (or a sign-in after a sign-out) the whole local library is uploaded into the new account and merged with it. On a handed-down or shared iPhone, one person's library and journal end up in another person's iCloud. | Product decision. Suggest pausing sync on an account switch and asking ("Keep this library in the new iCloud account?"). |
| Low | `.github/workflows/ios.yml` | `concurrency: cancel-in-progress: true` on `main`: every push cancels the run in progress. With several engineers pushing, full runs (with screenshots, ~45 min) rarely finish. | Owner's call: `cancel-in-progress: false` lets the running build finish and keeps only the newest pending one (GitHub replaces older pending runs), at the cost of waiting. |
| Low | `LibraryStore.log` | Learning the reading speed from a session changes `preferences.wpm` (a synced field) without moving the preferences stamp, so another device's preferences can win a tie and drop the calibration. | Deliberate trade-off (stamping on every session would let a session overwrite a real setting change elsewhere). Documented here; a field-level merge for `wpm` would fix both. |
| Low | `Shared/LeafBackup.swift` | Restoring a backup made by a newer Leaf with any value this build doesn't know reports "not a backup". | Decode the `data` part with `DecodeSkips` and show how many entries were left out in the preview. |
| Low | `LiveActivityController.configure` | A leftover activity adopted at launch gets `startedAt = Date()`, so the 7½-hour renewal clock restarts and an activity started earlier can hit the system's 8-hour end before it is renewed. | Use the activity's content `timerStart` (or store its start in the attributes). |
| Low | `Leaf/Services/AILibrarian.swift` | The timeout relies on cancelling the model call: `withTaskGroup` waits for every child, so if `respond` ignores cancellation the wait isn't bounded by the timeout. | Use an unstructured task for the model call and return on the first result. |
| Low | `LibraryStore.minutesReadToday/streak/week`, `ReadingStats` | These scan every session with `Calendar` calls each time a view reads them, and the plan is recomputed on the main thread on every commit (up to 3,650 simulated days for a long queue). Fine today; slow after years of sessions or a very long To read. | Cache per commit (day buckets of minutes), or move the plan off the main actor. |
| Low | `.github/workflows/catalog.yml` | Each rebuild commits a ~46 MB SQLite file to `main` (the checks allow up to 60 MB, GitHub warns at 50 MB). The repository grows by that much per rebuild. | Git LFS, or a release asset fetched by the build. |
| Low | `Shared/CatalogQuery.swift` | Terms keep characters `CharacterSet.alphanumerics` accepts; if the FTS5 `unicode61` tokenizer splits one, the quoted term becomes a phrase, which `detail=none` refuses, and that search returns nothing (no crash). | Only rare scripts; split terms the way `unicode61` does, or retry a failed query word by word. |
| Low | `Shared/Cozy/TeaSuggester.steepSeconds` | `Int(raw / 5) * 5` overflows for an absurd cabinet steep time (near `Int.max`), only reachable from a hand-made backup or sync payload. | Clamp `tea.steepSeconds` before multiplying. |
| Info | `Book` decoding | `Book` uses the synthesized decoder: `pages: 0` or `words: 0` from a hand-made file decode as is. Every engine path I followed guards the divisions, so no crash; noted for future code. | A tolerant `Book.init(from:)` that clamps like `init` does. |
| Info | Ambience (owned by another engineer) | There is no `audio` background mode, so ambience stops when the screen locks. | Product decision for the ambience owner; adding the mode needs an App Review justification (it qualifies as user-started audio). |
| Info | Watch | `WKBackgroundModes = [mindfulness]` for the reading session is an App Review judgement call, as `PLATFORM.md` notes. | Have a fallback plan (a workout-free short runtime) if review objects. |

## Risks to check on a real device

1. **First unlock after a restart.** Restart the iPhone, don't unlock it, log a session on the watch (it sends to the
   phone), then unlock and open Leaf. Expect: the library is there (no onboarding), the watch session is logged, the
   watch kept showing the library throughout, no `library.damaged-*` file appeared.
2. **Reminders.** "Skip today" from a morning reminder: no evening reminder that day. "Start reading" from a reminder
   while Leaf isn't running: the session starts. Snooze, then read to the goal: no snoozed reminder.
3. **Two devices, rereads.** Finish a book on A, begin it again an hour later, sync with B: page 0 on both. Remove an
   earlier read-through recovered from sessions, relaunch both: it stays gone.
4. **Privacy manifest.** The next TestFlight upload comes back without an ITMS-91053 email.
5. **Erase all data.** With iCloud on and online: other devices keep their copy (as designed). Offline: see the medium
   finding above before shipping widely.
6. **Clock change.** Set the date to a DST change day with a reading time after 03:00: Today's "next" time is right.
7. **VoiceOver session.** Start a session with VoiceOver on, wait a minute: controls answer the first double tap.

## Tests added or changed

- `LeafTests/FoundationTests.swift`: tolerant library decoding (3 tests).
- `LeafTests/LibraryStoreTests.swift` (Xcode): unreadable library, missing library, partial copy, ordered writer.
- `LeafTests/SyncTests.swift`: same-day reread, read tombstones never expire, removed recovered read; the
  invariant and pruning property tests follow the new rules.
- `LeafTests/ReadingSlotsTests.swift`: DST wall clock.
- `LeafTests/InsightsTests.swift`, `ForecastTests.swift`: speed budgets with room.

## Areas covered

Data model and persistence; sync merge, records, diff and the CKSyncEngine transport (read against the API); planner,
forecast, insights, recommender, slots and Today brief (dates, DST, NaN, determinism, performance); the catalog
(SQLite wrapper, FTS escaping, threading, missing database, workflow); voice, tea, challenges and the AI librarian;
app plumbing (startup, reminders, watch bridge, Live Activity, intents, Info.plist, privacy manifests, workflows,
TestFlight script, project checker); UI code (crash patterns, indexing, accessibility of custom gestures, sheets,
search performance, screenshots in light, dark and large type); tests and CI.

## CI

- 1a25857 (run 39548394270): build, every unit test (including the new store tests) and the watch build green; the
  archive was still running when a later push cancelled the run.
- 1e460e6 (run 39549901118, everything on main at the time, including cf66393's ambience work): the app, the embedded
  watch app, the widgets and the tests compiled; every test passed except the ambience test above, so the archive and
  screenshot steps were skipped. My changes are therefore compiled and unit-tested on macOS, but their Release
  archive and their screenshots are not yet verified; the next green run on main covers both.
- Linux: 838 tests, all passing except that same ambience test.
- The ambience engineer fixed that test in 9f9fab6 (the café and the crackles now sound the same at any sample rate).
- **Green:** 8c01e92 (run 39665922123, everything above plus later work by others): build and every unit test,
  the Release archive and packaging check, warnings and screenshots all passed. The screenshots (run 39655925407,
  a63477d, which also holds all of this work) show the copy fixes in place: Library's captions, Search's row
  subtitles and the watch session.
- Note for whoever runs CI from a sandbox: the job-log storage host can be blocked by a proxy, in which case
  `scripts/ci.py errors` prints nothing; the GitHub API's job-logs endpoint (or the GitHub MCP `get_job_logs` tool)
  still works.
