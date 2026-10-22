# App Store readiness review

2026-10-22, against `main` at 412a0cf, plus the fixes below. Three passes: a bug review of the iPhone app, widgets,
controls, Live Activity and watch (code, and the 225 CI screenshots of 6c82f49); a compliance audit against the
App Store Review Guidelines as revised in June and October 2026 and the App Store Connect upload checks; and UI
opportunities ranked by impact. Earlier passes are in `agent2-review.md` (data safety, crashes) and `UI-REPORT.md`
(design), and their findings aren't repeated unless they matter for submission.

Short version: the app is in good shape. The code is defensive, there are no force unwraps or unguarded ranges in the
UI, and accessibility (VoiceOver labels, Dynamic Type, Reduce Motion, dark mode) is consistently handled. Three things
would have stopped the first submission (a privacy manifest gap that fails the upload, an incomplete camera purpose
string, and a hidden Sound lab), and all three are fixed. What's left before submitting is mostly decisions and App
Store Connect work: whether 1.0 ships with iCloud, a hosted privacy policy and support page, screenshot sets in the
sizes App Store Connect requires, and the EU trader declaration.

## 1. Before you submit

| # | Item | Status | Owner |
|---|---|---|---|
| B1 | **Widget extension privacy manifest.** `LeafWidgets` reads the snapshot from App Group `UserDefaults` but its `PrivacyInfo.xcprivacy` declared no required-reason APIs. App Store Connect flags this on upload as ITMS-91053. The app also writes App Group defaults and declared only `CA92.1`. | **Fixed** 55ee25d: `1C8F.1` added to both. The watch and watch widgets were already right. | done |
| B2 | **Camera purpose string.** It only mentioned reading a quote, but Search › Scan a book also uses the camera. Guideline 5.1.1(ii) requires the string to name every use, and an incomplete one is a common rejection. | **Fixed** 55ee25d: "…to scan the barcode on a book you want to add, and to read a quote from the page you're holding…" | done |
| B3 | **Hidden feature.** Seven taps on the version number revealed the Sound lab in *every* non-debug build, App Store included. Guideline 2.3.1 forbids hidden or undocumented features. | **Fixed** a8afe5a: the taps check `AppTransaction` and unlock only in TestFlight (sandbox). | done |
| B4 | **Does 1.0 ship with iCloud?** The Release configuration has `LEAF_CLOUDKIT_ENABLED = NO`, and `scripts/testflight.sh` turns it on. Archiving from Xcode's Organizer (TESTFLIGHT.md's main path) therefore uploads a build *without* iCloud. That build showed an iCloud section reading "This build doesn't include iCloud" (now hidden, a8afe5a). If iCloud ships, two medium findings from agent2-review.md are worth closing first: an offline Erase re-merges the old iCloud library, and an account switch uploads the library into the new account. | Decision | Matt + Engine |
| B5 | **Privacy policy and support URLs.** Both are required fields in App Store Connect and must be live public pages. `docs/PRIVACY.md` is a good base, but it should also cover the camera (barcode and quote, nothing saved), ISBN lookups sent to Open Library, the on-device Apple Intelligence greetings (opt-in), and reading circles shared over iCloud with the people you invite (if that ships). Keep the in-app Privacy page (`PrivacyNoteView`) in step. | To do | Matt (hosting), UI (copy) |
| B6 | **Screenshots in accepted sizes.** App Store Connect needs a 6.9-inch iPhone set (1320×2868, the iPhone 17 Pro Max simulator) and, because the app includes a watch app, Apple Watch screenshots too. CI captures on the iPhone 17 Pro (6.3-inch), and its watch shots were cut off by the step's time limit. The October 2026 guidelines also require marketing images to represent the app accurately and to suit all ages. | To do | Engine (CI), Matt |
| B7 | **EU trader status.** Under the Digital Services Act, App Store Connect requires a trader or non-trader declaration. Apps without one aren't distributed in EU storefronts, and a trader's address, phone and email are shown on the EU product page. | To do | Matt |

## 2. Should do for 1.0

1. **Watch extended runtime for tea.** `WatchStore.startSteep` (`LeafWatch/WatchStore.swift:283`) starts the
   *mindfulness* `WKExtendedRuntimeSession` while tea steeps, with no reading session running. Reading under a
   mindfulness session is defensible, but steeping tea isn't, and 2.5.4 limits background modes to their intended
   purpose. The steep's local notification already taps the wrist when the tea is ready, so the runtime can be
   dropped for steeps. That decision is for the watch owner and Engine. Add a line about the reading runtime to the
   review notes (below).
2. **Age rating and open search.** Neither the catalog build nor Open Library search filters adult titles, and Open
   Library covers are uploaded by its users. Answer the age-rating questionnaire with that in mind (4+ is likely
   still right for a book catalog, but the reviewer may search). An `erotica` subject filter in
   `scripts/build_catalog.py` and in `OpenLibrary.search` would remove the question. This is Engine work.
3. **Covers in the store screenshots.** The CI shots show real publishers' covers (The Hobbit, Circe, Atomic Habits,
   Harry Potter). For App Store marketing images, stage public-domain books (Austen, Doyle, Alcott) or Leaf's
   generated covers. That avoids a 5.2.1 (intellectual property) question and fits the new marketing-asset section.
4. **Reading circles sharing (CKShare)**, if it's switched on for 1.0. The October revision treats any feature that
   lets people share content with each other as user-generated content (1.2), which needs ways to report and block.
   Invite-only sharing is low risk, but a "Leave circle" or "Remove person" action, plus a contact line, covers it.
   The simplest alternative is to keep sharing off for 1.0, since circles work locally.
5. **What's New.** The only release entry describes TestFlight-era changes and includes "iCloud: Your library on every
   device," which isn't true in a build without iCloud. Fresh installs never see the sheet, but Settings › What's new
   shows it. Either write a 1.0 entry or hide the row until 1.1. The October guidelines also ask for specific update
   notes from 1.1 on.
6. **Mac and Vision Pro availability.** By default, iPhone apps are offered on Apple silicon Macs and Vision Pro.
   Live Activities, the watch, the camera scan and the nook shaders are untested there. Untick both in App Store
   Connect › Pricing and Availability unless you have tried them.
7. **Accessibility Nutrition Labels** (App Store Connect › App Accessibility). Leaf can honestly claim VoiceOver,
   Larger Text, Dark Interface and Reduced Motion. Claim Sufficient Contrast only after the default tertiary text is
   darkened (UI item 3 below); Increase Contrast now firms it up (e7b901e). Voice Control and Differentiate Without
   Color need a pass on a device first.
8. **Open Library identification.** Open Library asks heavy API users to put contact details in the User-Agent and
   throttles anonymous traffic harder. Launch traffic from every install will hit it at once. Add the support email
   to `OpenLibrary.session`'s User-Agent (`Leaf/Services/OpenLibrary.swift:22`).

### Suggested App Review notes

> Leaf is a reading planner with no account or sign-in. To try it: finish the short onboarding (minutes a day, a
> reading time, a first book), then tap **Begin reading** on Today. A Live Activity appears on the Lock Screen and
> in the Dynamic Island. The camera is used in Search (the barcode icon, to scan a book's ISBN) and in a session's
> Note (to read a quote from a page); no photo is stored. Reminders are local notifications. The Apple Watch app runs
> a mindfulness extended-runtime session only while a reading session timed on the watch is running, so the timer
> keeps time and taps at the goal with the wrist down. [If iCloud ships:] iCloud sync uses the user's private
> CloudKit database only.

## 3. Bugs

### Fixed in this pass (pushed to main)

| Commit | Where | What was wrong | Fix |
|---|---|---|---|
| 55ee25d | `LeafWidgets/PrivacyInfo.xcprivacy`, `Leaf/Resources/PrivacyInfo.xcprivacy` | App Group defaults undeclared (B1) | `1C8F.1` |
| 55ee25d | `Config/Info.plist` | Camera purpose string missed barcode scanning (B2) | Names both uses |
| a8afe5a | `SettingsView` | Sound lab unlockable in App Store builds (B3) | TestFlight only, via `AppTransaction.environment == .sandbox` |
| a8afe5a | `SettingsView` | Builds without iCloud showed an iCloud section that said "This build doesn't include iCloud" | Section shown only when `CloudSync.isAvailable` |
| 589dff8 | `LeafWidgets/LeafControls.swift` | The Log pages control accepted any number, so it could read "Log 0 pages" or "Log -5 pages" while the intent silently clamped to 1 | `inclusiveRange: (1, 200)`, and the label clamps the same way |
| e7b901e | `LeafColor.swift`, `CanopyTokens.swift` | No Increase Contrast support. Tertiary text (captions, eyebrows, "Delete circle") is 3.2:1 on Oat cream, under the 4.5:1 that small text needs | With Increase Contrast on, tertiary takes secondary's colour (5.5:1), secondary darkens (8.4:1) and hairlines firm up. Nothing changes with the setting off. |
| 1a57b72 | `PlanView.swift` | Plan's reading-time rows wrapped as "7 min · pp." / "143–148" (C6 and 70 shots) | No-break spaces keep "7 min" and "pp. 143–148" whole |

### Found, not fixed

| Severity | Where | Finding | Owner |
|---|---|---|---|
| Medium | B4 above | Release builds without iCloud via Xcode Organizer; testflight.sh builds with it | Engine |
| Low | `LeafWatch/PhoneBridge.swift:23` | `send` drops an event if `WCSession` hasn't finished activating. The likeliest case is a reminder's Start launching the watch app: the start is never sent, so the phone learns of the session only when it's logged. Queue events until `activationDidComplete`. | Engine (sync) |
| Low | `Leaf/Services/Reminders.swift:52` | Notification permission asks for `.badge`, which Leaf never sets. Asking only for what you use reads better in review. | Engine |
| Low | `LiveActivityController.configure` (line 50) | A leftover activity adopted at launch restarts the 7½-hour renewal clock (already in agent2-review.md) | Engine |
| Low | `LeafWatch/SessionView.swift` | Watch captions use fixed 11 pt type, so they don't follow the watch's text size | UI (watch) |
| Low | `CanopyChip` | 36 pt minimum height, under the 44 pt target | UI (design system) |
| Info | `LiveActivityShared` | The Lock Screen line truncates ("Steeped in The Ho…") with longer titles | UI |

Nothing new turned up in the crash sweep (force unwraps, `try!`, ranges built from variables, timer intervals, `Int`
from `Double`, duplicate `ForEach` ids). The widget timeline (`LeafWidgetSnapshot.at`/`changes`), the Live Activity
lifecycle, the watch store and its runtime, the control intents and the Focus filter all read correctly.

## 4. Compliance checklist

| Area | Status |
|---|---|
| Privacy manifests (app, widgets, watch, watch widgets) | OK after B1. No tracking, no collected data, no third-party SDKs. Declared reasons: UserDefaults CA92.1/1C8F.1, file timestamp C617.1 (backup age), boot time 35F9.1 (`systemUptime`, `CACurrentMediaTime`). |
| App Privacy label | "Data Not Collected" holds: no analytics, no servers. iCloud data is in the user's private database, Open Library requests carry only the search text or ISBN, and the Apple Intelligence greetings run on the device. |
| Purpose strings | Camera fixed (B2). Photos add-only matches the quote-card save. No location, contacts, microphone, health or tracking. |
| Permissions asked in context | Notifications in onboarding with "Not now"; camera when Scan opens; photos on the first save. |
| Account deletion (5.1.1(v)) | Not applicable: there are no accounts. Erase all data is in Settings. |
| Encryption export | `ITSAppUsesNonExemptEncryption = NO` is correct (HTTPS and CloudKit only). |
| Background modes (2.5.4) | `remote-notification` only matters with iCloud (B4). Watch `mindfulness`: see section 2, item 1. No `audio` mode, so ambience stops at lock, which is consistent with its opt-in design. |
| In-app purchase | None. No external purchase links. |
| Hidden features (2.3.1) | Fixed (B3). Debug-only screens are `#if DEBUG`. |
| Completeness (2.1) | No placeholder copy, TODOs or "coming soon" in the UI. The iCloud "not in this build" text is gone. |
| Licensing | Instrument Serif under the OFL, with `OFL.txt` bundled. Every sound is synthesized (AUDIO_SOURCES.md). Speed-test passages are Conan Doyle (public domain). Catalog data is Open Library (CC0), credited in the Colophon. If the "Real scene footage" thread bundles `nook-*.mp4`, record each clip's source and licence the way AUDIO_SOURCES.md does. |
| AI (Foundation Models) | On device, opt-in, greetings only, and every output is filtered with a template fallback. Nothing user-to-user, so the UGC rules don't apply. |
| Accessibility | Good: VoiceOver labels and adjustable actions across custom controls, Dynamic Type including AX sizes, Reduce Motion and Reduce Transparency, dark mode. Increase Contrast now supported. Default tertiary contrast is still low (UI item 3). |
| Icons | 1024 px, RGB with no alpha, with light, dark and tinted variants, plus the watch icon. |
| iPad | iPhone-only, so it runs in compatibility mode on iPad. Reviewers sometimes check this; worth one run on an iPad. |

## 5. UI improvement opportunities, by impact

1. **App Store product page.** A purpose-built 6.9-inch set of five or six screens with one short caption each
   (Today's nook, a session with a scene, Plan's finish dates, Library, widgets and Live Activity, the watch),
   staged with public-domain books, plus a watch set. This is the biggest lever on installs and part of B6.
2. **Search opens on a spinner.** "Setting out the shelves…" fills the sheet for a beat on every open (CI shots
   13, 40 and 91 catch it). It's the first thing a reviewer taps after onboarding. Prewarm the browse shelves when
   the app goes idle after launch, or show skeleton rows.
3. **Default contrast for tertiary text.** Oat tertiary `0x8C8478` is 3.2:1 in light and 3.7:1 in dark on surfaces,
   and it's used for small captions. The legacy `inkTertiary` (`0x6E6457`, about 5:1) keeps the same warmth. This is
   a design call for Matt. It's also what lets you claim Sufficient Contrast.
4. **Onboarding's "Popular first reads".** Raw popularity produces The 48 Laws of Power and It Ends With Us beside
   Harry Potter. A curated, cozy starter set would set the tone better on the first screen with books.
5. **One "now" colour.** The legacy ribbon red still marks "now" (ruler needle, today's underline, weekday picks).
   This is Matt's open question from UI-REPORT.md.
6. **Your numbers' StatTile** is the last legacy component on a Canopy screen.
7. **Watch type.** Fixed 11 pt captions in the session and page picker; use `.caption2` so they scale.
8. **Live Activity line.** Shorten the session line when the title is long, so it doesn't end in "The Ho…".
9. **Chip targets.** Raise `CanopyChip` to a 44 pt minimum height; it can keep its look with padding.

## 6. NEEDS FROM ENGINE

1. B4: make the Organizer archive and `testflight.sh` agree on `LEAF_CLOUDKIT_ENABLED` for the build that goes to
   review, and, if iCloud ships, close the offline-Erase and account-switch findings.
2. B6: an App Store screenshot mode in CI: iPhone 17 Pro Max at 1320×2868, the watch shots in their own step so they
   finish, and a public-domain demo library for those shots.
3. A packaging check in `ios.yml` that each `.appex` and `.app` that uses `UserDefaults` declares it in its privacy
   manifest, so B1 can't regress. Before the first upload, also run Organizer › Validate App, which catches
   ITMS-91053 and missing icons before a submission does.
4. `PhoneBridge.send`: queue events until `WCSession` activation completes.
5. `Reminders.requestAuthorization`: drop `.badge`.
6. `OpenLibrary.session`: a User-Agent with contact details.
7. Optional: an adult-content filter in the catalog build and in Open Library results (section 2, item 2).
8. Watch: no extended runtime for a steep with no session (section 2, item 1).

## 7. App Store Connect checklist for Matt

- **Name:** "Leaf: Reading Planner" (30 characters max; "Leaf" alone is almost certainly taken). The home-screen
  name stays "Leaf".
- **Subtitle** (30): for example "A gentle daily reading plan".
- **Category:** Books, with Productivity or Lifestyle as the secondary.
- **Privacy policy URL and support URL:** live pages (B5).
- **App Privacy:** Data Not Collected.
- **Age rating:** the new questionnaire. Likely 4+; see section 2, item 2.
- **Content rights:** yes, the app shows third-party content (Open Library data and covers).
- **Trader status** (B7).
- **Availability:** untick Mac and Vision Pro unless tested.
- **Screenshots:** 6.9-inch iPhone and Apple Watch (B6).
- **Accessibility Nutrition Labels** (section 2, item 7).
- **Review notes:** section 2.
- **Build:** run Validate App in Organizer before Upload, and check the build includes the flag you chose in B4.
