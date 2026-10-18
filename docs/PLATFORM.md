# Leaf: platform plumbing

What each Xcode target, entitlement and Info.plist key is for, how the hand-edited project is organised, and what to
check in your Apple Developer account. The engineering rules are in [`ENGINEERING.md`](ENGINEERING.md), the feature
plans in [`NEXT.md`](NEXT.md) (sections 11 and 16), and the upload steps in [`TESTFLIGHT.md`](TESTFLIGHT.md).

## Targets

| Target | Product | Bundle id | Folders it compiles | Entitlements |
| --- | --- | --- | --- | --- |
| `Leaf` | `Leaf.app` (iPhone, iOS 26) | `com.norvodesigns.leaf` | `Shared/`, `Leaf/`, `LiveActivityShared/` | `Leaf/Leaf.entitlements` |
| `LeafWatch` | `LeafWatch.app` (watchOS 26), embedded in `Leaf` | `com.norvodesigns.leaf.watchkitapp` | `Shared/`, `LeafWatch/` | none |
| `LeafWidgets` | `LeafWidgets.appex` (widget extension, iOS 26), embedded in `Leaf` | `com.norvodesigns.leaf.widgets` | `LeafWidgets/`, `LiveActivityShared/` | `LeafWidgets/LeafWidgets.entitlements` |
| `LeafTests` | `LeafTests.xctest`, hosted by `Leaf` | `com.norvodesigns.leafTests` | `LeafTests/` | none |

Every target builds in Swift 5 language mode. Version and build number are set once at the project level, so the app,
the watch app and the extension always match (Apple expects an embedded extension to carry its host's version and
build number). The extension's bundle id must start with the app's bundle id, which is why it is `.widgets` and not something
unrelated.

`DEVELOPMENT_TEAM` is empty in the project on purpose, like it was before the extension existed. Pick your team once in
Xcode (Signing & Capabilities, for each of `Leaf`, `LeafWatch`, `LeafWidgets`), or let `scripts/testflight.sh` pass
`DEVELOPMENT_TEAM=$TEAM_ID` on the command line.

## Folders and what goes where

The project uses synchronized folders: a file you add under one of these folders joins every target that lists the
folder, with no project edit.

- `Shared/`: Foundation-only logic. Compiled into the phone and the watch (and into the Linux tests). Not into the
  extension.
- `Leaf/`: the iPhone app. `Leaf/Leaf.entitlements` lives here but is excluded from the target's membership, so it is
  used for signing and never copied into the app as a resource.
- `LeafWatch/`: the watch app.
- `LeafWidgets/`: sources only the widget extension compiles (the widget bundle, the Live Activity views, later the
  Home Screen widgets and controls), its entitlements and privacy manifest.
- `LiveActivityShared/`: compiled into both the app and the extension, and nothing else. This is for types both sides
  must agree on: the Live Activity attributes now, and the App Intents the Live Activity buttons run later (an
  interactive Live Activity button runs its intent in the app's process, but the extension has to see the type). Keep it
  to Foundation, ActivityKit, AppIntents and WidgetKit. It cannot use anything from `Shared/`, because the extension
  does not compile `Shared/`. If the extension ever needs `Shared/` (for `LeafFormat`, say), add the `Shared` folder to
  the `LeafWidgets` target's synchronized folders in the project file and re-run the checker.
- `Config/`: `Info.plist` (merged with the generated Info.plist keys) for the app and `LeafWidgets-Info.plist` for the
  extension. These sit outside any synchronized folder so they can never be bundled as resources by accident.
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

Not built yet (a later step, once CI shows these targets work): the Live Activity controller that starts, updates and
ends the activity, the App Intents, the widget snapshot writer, the cover pre-rendering into the App Group, and the
CloudKit sync itself. A Live Activity can only be started while the app is in the foreground, lasts up to 8 hours, and
can sit on the Lock Screen for about 4 more (NEXT.md section 11).

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
