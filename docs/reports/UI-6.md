# UI-6 report: the watch app, wrist-down runtime, complications and reminders

```
=== REPORT FOR LEAD ===
Package: UI-6 (Apple Watch: pages, session timer, extended runtime, complications, notifications)
Status: __STATUS__
Commits pushed to main:
  0f6cff4 UI-6 part 1: the watch nook, focus-pull timer, crown screens, forecast, shelf and add
  5517f85 UI-6 part 2: watch complications and Smart Stack card
  3ceebd6 Watch reminders: leave the mirrored Snooze and Skip to the phone, handle Start on the wrist
  __FIXES__
CI: __CI__
Screens / states built (staging name -> screenshot file, all with -LeafDemo YES):
  Today nook: greeting, cup ring, Steep and read, reading times  -LeafScreen today          -> w1-today
  Session: focus-pull countdown over bokeh                       -LeafScreen session        -> w2-session
  Session page picker (end of session)                           -LeafScreen pages          -> w3-pages
  Shelf: Reading and Up next                                     -LeafScreen shelf          -> w4-shelf
  Tea steeping                                                   -LeafScreen steep          -> w5-steep
  Tea ready, hand-off to a cup of reading                        -LeafScreen steepready     -> w6-steep-ready
  A cup-timed session (counts down the cup)                      -LeafScreen session.cup    -> w7-session-cup
  Always-On session (minutes only, dimmed)                       -LeafScreen aod            -> w8-always-on
  Log page (per book: Log, Page)                                 -LeafScreen log            -> w9-log
  Quick log on the crown (minutes, then page)                    -LeafScreen quicklog       -> w10-quicklog
  Where was I? on the crown                                      -LeafScreen where          -> w11-where
  Forecast: year ring and sentence, per-book sentences           -LeafScreen forecast       -> w12-forecast
  Week as tea rings, streak                                      -LeafScreen week           -> w13-week
  Shelf book actions (start / mark finished / set aside)         -LeafScreen shelf.actions  -> w14-shelf-actions
  Add by dictation (book, thought, quote) with confirmation      -LeafScreen add.sent       -> w15-add
  Complications drawn in the app (circular, inline, rectangular) -LeafScreen complications  -> w16-complications
New public types or files (one line each):
  LeafWatch/WatchRuntime.swift      ReadingRuntime (mindfulness WKExtendedRuntimeSession + goal tap), WatchNotifications
  LeafWatch/WatchPages.swift        WatchRoute, LogPage, QuickLogView, WhereWasIView, ForecastPage, AddPage, WatchAtmosphere
  LeafWatch/TodayPage.swift         TodayPage (nook), SteepTimerView, WeekPage, WatchTeaRing, ShelfPage, WatchBookRow,
                                    ShelfBookActions (rewritten; BooksPage became ShelfPage)
  LeafWatch/SessionView.swift       the focus-pull countdown (timer rewritten; page picker and wrap-up unchanged)
  LeafWatch/ComplicationFeed.swift  ComplicationFeed (writes the snapshot, reloads timelines on change), DEBUG gallery
  WatchComplicationShared/          ComplicationSnapshot + ComplicationStore (App Group), the four complication views
  LeafWatchWidgets/                 the watchOS widget extension: LeafComplication, ComplicationProvider, ComplicationTimeline
  WatchStore: sessionTarget(for:), wrist-down hooks (keepAwake/letSleep), demo slots and steep staging
  WatchTheme.tea, WatchTheme.warm
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  WatchSnapshot greeting/tea/cupMinutes/queue/forecasts/yearGoal/slots/week/today, WatchStore start(bookID:teaID:
  goalSeconds:)/pause/resume/finish/cancel/quickLog/setPage/addJournal/moveBook/addBook/startSteep/cancelSteep,
  AtmosphereField.bokeh(seed:time:count:calm:), LeafFormat.
  Missing: a SyncEvent for "skip today" from the watch, so Skip stays with the phone's mirrored notification (fine
  while the system routes background actions to the iPhone app; see below). WatchForecast has only a median, no range,
  so the Forecast page shows the phone's sentence rather than a drawn range.
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/ (engine fixes, project file):
  Leaf.xcodeproj: new target LeafWatchWidgets (app extension, watchOS, embedded in LeafWatch/PlugIns), new
  synchronized folders LeafWatchWidgets/ and WatchComplicationShared/, LeafWatch gets INFOPLIST_FILE and
  CODE_SIGN_ENTITLEMENTS. Config/: LeafWatch-Info.plist (WKBackgroundModes = [mindfulness]), LeafWatch.entitlements and
  LeafWatchWidgets.entitlements (App Group), LeafWatchWidgets-Info.plist. scripts/check_pbxproj.py knows the new
  target, folders, entitlements, Info.plists and @main (self-test 21/21). .github/workflows/ios.yml packaging check
  verifies the embedded watch extension and the mindfulness mode. LeafWatch/PrivacyInfo.xcprivacy adds 1C8F.1 (App
  Group defaults). scripts/ci_screenshots.sh (w4-w16). docs/PLATFORM.md, docs/DESIGN_SYSTEM.md. No Shared/ changes.
Could not verify (device-only things):
  Double Tap, Always-On (staged by forcing isLuminanceReduced; real dimming and the once-a-minute cadence need a
  device), the extended runtime session (start, wrist-down survival, the goal tap, the one-hour expiry tap), all
  haptics, complications on a real face and in the Smart Stack (tinting, relevance ranking, reload budget), the App
  Group container on the watch, notification routing for mirrored actions, dictation through TextFieldLink.
Design decisions the owner should know about or veto:
  - Session type: mindfulness (WKBackgroundModes = [mindfulness]). Reading is not meditation, so App Review may push
    back; self-care was the alternative but caps a session at 10 minutes. If review rejects it, drop the mode: the
    timer still keeps time from the start date, only the wrist-down goal tap is lost (the scheduled notification nudge
    remains as the fallback).
  - The countdown counts to the cup's length for a tea-started session, else to what is left of today's goal; past it,
    it counts up. Digits are crisp for two thirds of each minute and soften towards the change (not blurry
    mid-minute), with exact mm:ss underneath; Reduce Motion turns the blur off.
  - Only sessions the watch times start the runtime; a session mirrored from the phone keeps the old notification nudge.
  - The wrist is tapped once at the goal: by the runtime while it runs, otherwise by the in-app celebration.
  - Crown screens are pushed views, never pages, so the crown cannot page the TabView mid-adjustment.
  - Reminders: the watch registers no category; the phone's mirrored Start / Snooze / Skip stay the phone's, and Start
    (a foreground action) starts the session on the wrist.
  - Complications reuse the phone's App Group identifier (the watch has its own container under it).
  - Smart Stack relevance uses TimelineEntryRelevance (high 15 minutes before to 30 minutes after each reading time,
    and while reading; none once the goal is met).
Known issues / follow-ups, most important first:
  __FOLLOWUPS__
  - Enable the App Group on the two watch App IDs in the developer portal before the next TestFlight (TESTFLIGHT.md).
  - RelevanceKit (watchOS 26 relevant widgets) could replace TimelineEntryRelevance for the Smart Stack.
  - Not built from NEXT.md section 12: pace taps, the sleep timer, Mindful minutes (HealthKit, opt-in).
Next package you recommend: a device pass on the watch (Double Tap, Always-On, runtime, complications, haptics).
=== END REPORT ===
```
