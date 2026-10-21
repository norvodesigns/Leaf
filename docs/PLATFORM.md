# Leaf: platform plumbing

What each Xcode target, entitlement and Info.plist key is for, how the hand-edited project is organised, and what to
check in your Apple Developer account. The engineering rules are in [`ENGINEERING.md`](ENGINEERING.md), the feature
plans in [`NEXT.md`](NEXT.md) (sections 11 and 16), and the upload steps in [`TESTFLIGHT.md`](TESTFLIGHT.md).

## Targets

| Target | Product | Bundle id | Folders it compiles | Entitlements |
| --- | --- | --- | --- | --- |
| `Leaf` | `Leaf.app` (iPhone, iOS 26) | `com.norvodesigns.leaf` | `Shared/`, `Leaf/`, `LiveActivityShared/` | `Leaf/Leaf.entitlements` |
| `LeafWatch` | `LeafWatch.app` (watchOS 26), embedded in `Leaf` | `com.norvodesigns.leaf.watchkitapp` | `Shared/`, `LeafWatch/`, `WatchComplicationShared/` | `Config/LeafWatch.entitlements` |
| `LeafWatchWidgets` | `LeafWatchWidgets.appex` (watch complications, watchOS 26), embedded in `LeafWatch` | `com.norvodesigns.leaf.watchkitapp.widgets` | `LeafWatchWidgets/`, `WatchComplicationShared/` | `Config/LeafWatchWidgets.entitlements` |
| `LeafWidgets` | `LeafWidgets.appex` (widget extension, iOS 26), embedded in `Leaf` | `com.norvodesigns.leaf.widgets` | `LeafWidgets/`, `LiveActivityShared/` | `LeafWidgets/LeafWidgets.entitlements` |
| `LeafTests` | `LeafTests.xctest`, hosted by `Leaf` | `com.norvodesigns.leafTests` | `LeafTests/` | none |

Every target builds in Swift 5 language mode. Version and build number are set once at the project level, so the app,
the watch app and the extension always match (Apple expects an embedded extension to carry its host's version and
build number). The extension's bundle id must start with the app's bundle id, which is why it is `.widgets` and not something
unrelated.

`DEVELOPMENT_TEAM` is empty in the project on purpose, like it was before the extension existed. Pick your team once in
Xcode (Signing & Capabilities, for each of `Leaf`, `LeafWatch`, `LeafWidgets`, `LeafWatchWidgets`), or let `scripts/testflight.sh` pass
`DEVELOPMENT_TEAM=$TEAM_ID` on the command line.

## Folders and what goes where

The project uses synchronized folders: a file you add under one of these folders joins every target that lists the
folder, with no project edit.

- `Shared/`: Foundation-only logic. Compiled into the phone and the watch (and into the Linux tests). Not into the
  extension.
- `Leaf/`: the iPhone app. `Leaf/Leaf.entitlements` lives here but is excluded from the target's membership, so it is
  used for signing and never copied into the app as a resource.
- `LeafWatch/`: the watch app. Its Info.plist (`Config/LeafWatch-Info.plist`) adds `WKBackgroundModes = [mindfulness]`
  for the reading session's `WKExtendedRuntimeSession` (`LeafWatch/WatchRuntime.swift`).
- `LeafWatchWidgets/`: the watch complications and Smart Stack card (a watchOS widget extension), with its privacy
  manifest.
- `WatchComplicationShared/`: compiled into the watch app and its complications: `ComplicationSnapshot`, the few
  numbers a face shows, which the watch app writes to the App Group container after each change, and the complication
  views (so the app can draw them in a DEBUG gallery). Foundation, SwiftUI and WidgetKit only; no `Shared/`.
- `LeafWidgets/`: sources only the widget extension compiles (the widget bundle, the Live Activity, the Today widget
  and the Control Center controls), its entitlements and privacy manifest.
- `LiveActivityShared/`: compiled into both the app and the extension, and nothing else. This is for types both sides
  must agree on: the Live Activity attributes now, and the App Intents the Live Activity buttons run later (an
  interactive Live Activity button runs its intent in the app's process, but the extension has to see the type). Keep it
  to Foundation, ActivityKit, AppIntents and WidgetKit. It cannot use anything from `Shared/`, because the extension
  does not compile `Shared/`. If the extension ever needs `Shared/` (for `LeafFormat`, say), add the `Shared` folder to
  the `LeafWidgets` target's synchronized folders in the project file and re-run the checker.
- `Config/`: `Info.plist` (merged with the generated Info.plist keys) for the app, `LeafWidgets-Info.plist` for the
  extension, `LeafWatch-Info.plist` for the watch app, and the watch app's and watch extension's Info.plist and
  entitlements (the App Group, the watch's own copy of it). These sit outside any synchronized folder so they can never be bundled as resources by accident.
- `LeafTests/`: unit tests. They reach the app and the shared Live Activity types with `@testable import Leaf`.

A Swift file name can only appear once per target, even across folders (Swift reports "filename used twice"). The
checker looks for that, because several people add files to `Shared/` and `Leaf/` at the same time.

## Entitlements

`Leaf/Leaf.entitlements` (the app):

| Key | Value | Why |
| --- | --- | --- |
| `com.apple.developer.icloud-container-identifiers` | `iCloud.com.norvodesigns.leaf` | The private CloudKit container for sync and backup (NEXT.md section 16). |
| `com.apple.developer.icloud-services` | `CloudKit` | Turns on CloudKit for that container. No iCloud Documents or key-value store. |
| `com.apple.security.application-groups` | `group.com.norvodesigns.leaf` | The shared folder the app, the extension and later the widgets read: the pre-rendered blurred cover, the widget snapshot. |
| `aps-environment` | `development` | Push entitlement, needed by CloudKit so other devices wake when data changes. Xcode swaps it to `production` when it signs for the App Store or TestFlight; do not edit it by hand. |

`LeafWidgets/LeafWidgets.entitlements` (the extension) has only the same App Group. The extension does not talk to
iCloud: it reads what the app wrote into the group container.

No entitlement is needed for Live Activities, App Intents, WatchConnectivity or local notifications.

## Info.plist keys (`Config/Info.plist`, the app)

The project uses `GENERATE_INFOPLIST_FILE = YES` plus `INFOPLIST_FILE = Config/Info.plist`: Xcode merges the file with
its generated keys. New keys go in the file.

| Key | Value | Why |
| --- | --- | --- |
| `NSSupportsLiveActivities` | `YES` | Lets the app start a Live Activity. Without it `Activity.request` fails. |
| `NSSupportsLiveActivitiesFrequentUpdates` | `NO` | We update only on state changes (start, pause, resume, goal, page), never in a loop. The timer digits advance by themselves. |
| `UIBackgroundModes` | `remote-notification` | CloudKit delivers changes as silent pushes; this lets the app wake to merge them. |

The extension's `Config/LeafWidgets-Info.plist` declares `NSExtension` with
`NSExtensionPointIdentifier = com.apple.widgetkit-extension`. That is what makes the system treat the `.appex` as a
widget extension.

## The Live Activity pieces

- `LiveActivityShared/ReadingActivityAttributes.swift`: `ReadingActivityAttributes` (book id, title, author, total
  pages, cover file name: fixed for the life of the activity) and `ReadingActivityContent`, its `ContentState`
  (tiny: a timer start date, a paused flag, the seconds elapsed at the pause, an optional goal in seconds, the current
  page, and a state of reading, paused, goal reached or finishing). The value types are plain Foundation and compile on
  Linux; only the `ActivityAttributes` struct is behind `#if canImport(ActivityKit)`.
- How the timer stays live without updates: `timerStart` is the real start moved forward by every pause, so
  `Text(timerInterval:)` shows reading time only. While paused, `pauseDate` freezes the digits. `timerRange`,
  `countsDown` and `pauseDate` hand the view exactly the arguments it needs and can never produce a range that ends
  before it starts (SwiftUI traps on that).
- `LeafWidgets/LeafWidgetsBundle.swift`: the `@main` widget bundle.
- `LeafWidgets/ReadingLiveActivity.swift`: a deliberately plain Lock Screen view and compact, expanded and minimal
  Dynamic Island regions. The visual design replaces it.

Built in UI-2 (not yet verified by CI or on a device):

- `LiveActivityShared/ReadingActivityViews.swift`: the Lock Screen, compact, minimal and expanded views, shared so
  the app can stage them (`-LeafScreen liveactivity.reading|paused|goal|cup`). `LeafWidgets/ReadingLiveActivity.swift`
  only wires them to ActivityKit.
- `LiveActivityShared/ReadingIntents.swift`: `PauseReadingIntent`, `ResumeReadingIntent`, `LogPagesIntent`
  (`LiveActivityIntent`, compiled into both targets); they reach the app through `ReadingIntentBridge`.
- `Leaf/Services/LiveActivityController.swift`: starts the activity in the foreground, updates it on state changes,
  sets the stale date to the goal so it turns to "goal met" without an update, renews it after 7½ hours, and ends it.
  `LiveActivityCover` writes a small cover and a blurred copy to `group.com.norvodesigns.leaf/LiveActivity/`.
- `Leaf/Services/ReadingAppIntents.swift`: `StartReadingIntent`, the `LeafShortcuts` App Shortcuts, and the
  `ReadingFocusFilter` Focus filter (holds Leaf's reminders while a Reading Focus is on).
- `NSCameraUsageDescription` in `Config/Info.plist`, for Live Text quote scanning in the session (text only).

Still to do: the CloudKit sync itself. A Live Activity can only be started while the app is in the foreground, lasts up
to 8 hours, and can sit on the Lock Screen for about 4 more (NEXT.md section 11).

## Widgets and Control Center controls

All in the existing `LeafWidgets` extension: no new target, entitlement or capability. The extension already has the
App Group, and controls need nothing extra.

- **The snapshot.** `LiveActivityShared/LeafWidgetSnapshot.swift`: `LeafWidgetSnapshot` (today's minutes and goal, the
  current book and its page, today's pages, three books up next with their likely finish, the week, the running session
  or the pot steeping) and `LeafWidgetStore` (the App Group's shared defaults, key `leaf.widget`). `Leaf/Services/WidgetFeed.swift`
  builds it from the store (`LibraryStore.widgetSnapshot`) after every change, a steep, a new forecast, the day
  changing and going to the background; it writes only when the snapshot differs and only then reloads the `LeafToday`
  timelines and the controls. Covers are the Live Activity's (`LiveActivityCover.prepare`), written once per book per
  launch. Screenshot runs never write it.
- **The Today widget** (`LeafWidgets/LeafTodayWidget.swift`, views in `LiveActivityShared/LeafWidgetViews.swift` so the
  app can stage them): small, medium and large on the Home Screen (the small one is what StandBy shows), and circular,
  rectangular and inline on the Lock Screen, matching the watch complications. One entry now and one at each moment it
  changes by itself (the goal crossed, the tea ready, the pot cold, midnight); the seconds are `Text(timerInterval:)`.
  Interactive buttons: Read (`StartReadingIntent`) and Steep (`StartSteepIntent`) by day, Pause or Resume and "A page"
  while reading.
- **Controls** (`LeafWidgets/LeafControls.swift`): Start reading, Steep a pot, and Log pages (the reader picks how many
  pages per press when adding it; `LogPagesControlConfiguration`). Each works from Control Center, the Lock Screen and the
  Action button.
- **Where the intents run.** `StartReadingIntent` and `StartSteepIntent` set `openAppWhenRun`, so the system opens Leaf
  and performs them there; `LogPagesIntent` is a `LiveActivityIntent`, so it runs in the app's process without opening it.
  All of them are in `LiveActivityShared/ReadingIntents.swift`, compiled into both targets, and reach the store through
  `ReadingIntentBridge` (`Leaf/Services/ReadingAppIntents.swift`). Log pages with no session moves the bookmark of the
  book Today suggests (Reading shelf only).
- **Screenshots.** `-LeafScreen widgets.home`, `widgets.timer`, `widgets.lock` draw the widgets on a stand-in Home
  Screen, Lock Screen and StandBy (`Leaf/Features/Session/WidgetStage.swift`); shots `wg-1` to `wg-4`. Controls can't
  be staged in the app.

## The live timer on the wrist (Smart Stack and Dock)

One timer, one card. A Live Activity started on the iPhone is mirrored to the watch's Smart Stack (and shows in the
Dock) by the system, so whenever the phone has one for this session, that is the card, and the watch's own Timer widget
stays out of the way. Otherwise the watch's Timer widget is the card. The rule is `LiveTimerRules.watchShowsCard`
(`Shared/LiveTimer.swift`, tested in `LeafTests/LiveTimerTests.swift`).

| Started on | What | Phone | Watch |
|---|---|---|---|
| Phone | Reading session | Live Activity (Lock Screen, Dynamic Island) | The mirrored Live Activity, in its small layout. Leaf's Timer widget shows today's reading. If Live Activities are off on the phone, the Timer widget shows the session instead. |
| Phone | Tea steeping | Live Activity counting down to the tea, then "(tea) is ready"; it carries on as the session if the reader starts reading that book | The mirrored Live Activity. |
| Watch | Reading session | A Live Activity only if the phone app is open when it hears of the session (ActivityKit starts them only in the foreground, and Leaf has no push server) | Leaf's Timer widget, until the phone says it has a Live Activity for this session; then the mirrored one. |
| Watch | Tea steeping | Nothing (the phone doesn't hear of a watch steep) | Leaf's Timer widget, counting down, then "(tea) is ready" for up to 30 minutes. |

How the pieces talk:

- `LeafWidgets/ReadingLiveActivity.swift` declares `.supplementalActivityFamilies([.small])`, and
  `ReadingActivityFamilyView` reads `activityFamily`: `.small` draws `ReadingActivityWatchCard`
  (`LiveActivityShared/ReadingActivityViews.swift`), a two-line card for the watch and CarPlay; `.medium` is the
  Lock Screen view. The content state gained `steeping` and `teaReady`; old states decode as before.
- The phone tells the watch which session its Live Activity covers: `WatchSnapshot.liveActivitySessionID` (optional,
  decoded if present, so an older phone's snapshot still loads), set from `LiveActivityController.sessionShown` and
  pushed whenever an activity starts or ends.
- The watch writes the timer into its `ComplicationSnapshot` (`timer: ComplicationTimer?`,
  `WatchComplicationShared/ComplicationTimer.swift`) with `ComplicationFeed.publish`, and reloads both widget kinds.
- `LeafWatchWidgets/LeafWatchTimerWidget.swift` (`LeafTimerWidget`, kind `LeafWatchTimer`, rectangular, corner,
  circular and inline) draws it with `Text(timerInterval:pauseTime:countsDown:showsHours:)` and
  `ProgressView(timerInterval:)`, so nothing updates per second. Its timeline is the timer's phases (running, then
  reached at the goal or when the tea is ready, then settled five minutes later) with `TimelineEntryRelevance`
  scores (1 while running, 1 for ready tea, 0.8 at a met goal, 0.6 paused, falling back after five minutes), then an
  entry at expiry with today's reading and relevance 0. Policy `.never`: the app writes a new snapshot on every change.
- A timer expires so it never lingers: a steep 30 minutes after the tea is ready, a reading session 8 hours after it
  started.
- The watch's `WKExtendedRuntimeSession` still keeps a watch-started session alive; the widget is what shows when the
  app isn't on screen.

No new target, entitlement or capability: the Timer widget lives in `LeafWatchWidgets`, and the small Live Activity
layout in `LeafWidgets`.

## Privacy manifests

The app, the watch app and the extension each carry a `PrivacyInfo.xcprivacy`. The extension's declares no tracking, no
collected data and no required-reason APIs yet. Add the matching reason the first time code in that bundle uses one:
for example `NSPrivacyAccessedAPICategoryUserDefaults` with reason `1C8F.1` when the app or extension reads or writes
`UserDefaults(suiteName: "group.com.norvodesigns.leaf")`, or the file timestamp category when it reads modification
dates of files in the group container. The App Privacy answer stays "Data Not Collected" while everything lives on the
device or in the reader's own private iCloud (NEXT.md section 16).

## The project checker

The project file is edited by hand and Xcode is not available on the machines that edit it, so run this after every
edit to `Leaf.xcodeproj`, `Config/`, an `.entitlements` file or a synchronized folder's layout:

```bash
python3 scripts/check_pbxproj.py              # exit status 1 and a list of problems when something is wrong
python3 scripts/check_pbxproj.py --summary    # also prints the targets, folders and embeds
python3 scripts/check_pbxproj.py --self-test  # breaks the project in memory 21 ways and proves each is caught
```

It needs only Python 3. It checks balanced braces and a readable file, that every id is 24 uppercase hex digits and
defined exactly once, that every reference resolves and nothing is left unreferenced, that each target has build phases,
a configuration list and a product, that embed phases hold real products whose target is a dependency, that bundle ids
nest and versions match, that synchronized folders exist and that plist and entitlements files inside them are excluded
from membership, that no Swift file name is compiled twice, that schemes point at real targets, and Leaf's own
contract (bundle ids, entitlement and Info.plist values, which targets compile which folders, exactly one `@main` in the
extension). CI runs it first, before spending Mac minutes.

To add another extension (a Control Center control extension, say), copy the pattern: a product file reference, a
synchronized folder, a native target with Sources, Frameworks and Resources phases and a configuration list, a target
dependency plus container proxy, a copy-files phase with `dstSubfolderSpec = 13` in `Leaf`, a plist in `Config/`, an
entitlement file excluded from membership. Then update the contract tables at the top of the checker.

## What CI checks

`.github/workflows/ios.yml` still builds, tests and screenshots without signing. The unsigned archive step now also
fails the build unless `Leaf.app/PlugIns/LeafWidgets.appex` exists, its Info.plist declares the
`com.apple.widgetkit-extension` extension point, its bundle id, version and build number are right, and the app's
Info.plist has `NSSupportsLiveActivities`, `NSSupportsLiveActivitiesFrequentUpdates = NO` and the `remote-notification`
background mode. Entitlements are not embedded in an unsigned build, so those are covered by the project checker and by
`scripts/testflight.sh`, which inspects the signed archive.

## Apple Developer portal checks

Do these once, at developer.apple.com/account under **Certificates, Identifiers & Profiles** (or in Xcode, under
Signing & Capabilities, which does the same thing). Automatic signing can create most of this for you on the first
archive, but a quick look avoids a failed 10 minute upload.

1. **App IDs.** Under Identifiers, look for three: `com.norvodesigns.leaf`, `com.norvodesigns.leaf.watchkitapp` and
   `com.norvodesigns.leaf.widgets`. The last one is new.
2. **Capabilities on `com.norvodesigns.leaf`:** iCloud (with CloudKit), App Groups and Push Notifications.
3. **Capabilities on `com.norvodesigns.leaf.widgets`:** App Groups. Live Activities need no capability.
4. **App Group.** Under Identifiers, filter by App Groups: `group.com.norvodesigns.leaf` exists, and both the app's and
   the widget's App ID have it ticked.
5. **iCloud container.** Filter by iCloud Containers: `iCloud.com.norvodesigns.leaf` exists, and the app's App ID uses it.
6. **CloudKit schema (when sync ships).** TestFlight and App Store builds use CloudKit's Production environment, while
   Xcode and development builds use Development. In the CloudKit Dashboard
   (icloud.developer.apple.com), after the sync code has run once from a development build, use **Deploy Schema Changes**
   to promote the record types to Production before testers try sync.

### What automatic signing creates on the next archive

With **Automatically manage signing** on (the project's setting) and `-allowProvisioningUpdates`
(`scripts/testflight.sh` passes it; Xcode does the same when you press Archive), Xcode registers the App ID
`com.norvodesigns.leaf.widgets`, turns on the capabilities named in the entitlements files for each App ID, creates the
App Group and the iCloud container if they are missing, and makes a development and an App Store provisioning profile
for each of the three bundle ids. You do not map profiles per bundle id anywhere. An Apple ID that cannot create
identifiers (usually anyone below Admin) will get a signing error naming the missing item; create it by hand in
the portal and run again.

### If signing complains

- The first `error:` line in the `xcodebuild` output is the one that matters. Names of the bundle id, capability or
  entitlement are in it.
- In Xcode: select the target, open **Signing & Capabilities**; red text under the team explains what is missing. The
  Report navigator (Cmd+9) keeps the full build and signing logs.
- An export failure prints the path of a `.xcdistributionlogs` bundle; open it in Finder for the full Apple response.
  `build/export/Packaging.log` and `DistributionSummary.plist` appear next to the exported files when there are any.
- "No profiles found", or a capability the profile does not include: the team is not chosen for `LeafWidgets` (do step
  2 of TESTFLIGHT.md for all three targets), or the capability is missing on that App ID in the portal.
- An entitlement the profile does not allow, such as an App Group the App ID does not have: tick the group on the App
  ID in the portal, then run again so Xcode regenerates the profile.
- `scripts/testflight.sh` stops before exporting if the archive is missing the extension or the watch app, and warns if
  the signed app lacks the iCloud container, App Group or push entitlement.

## What could not be verified without Xcode

Nothing here has been built by Xcode. The project edits follow the format Xcode 26 writes for synchronized folders
(membership exception sets, `dstSubfolderSpec = 13` for plug-ins, `explicitFileType = "wrapper.app-extension"`), the
checker confirms the structure, and the placeholder Swift files use only well-trodden WidgetKit and ActivityKit calls.
The first CI run is the real test; the likely failures, if any, are in the log's first `error:` line.
