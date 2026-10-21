# Watch live timer: report

```
=== REPORT FOR LEAD ===
Package: Watch live timer (Smart Stack / Dock)
Status: done (device-only checks listed below)
Commits pushed to main:
  07185da Watch live timer: the reading or steeping timer in the Smart Stack and the Dock
  6a39276 Watch: a screenshot of the steep and ready timer faces (w18)
CI: run 39665922123 (8c01e92): build, all unit tests (incl. LiveTimerTests and the new Live Activity raw values),
  the watch app and its widget extension, unsigned archive and screenshots green. Final run: 39676881472 (039008a), re-run after the first attempt never got a runner: build, all unit
  tests, watch app, unsigned archive and warnings green; screenshots showed the tour on Library, Plan and Search
  and the poster's footer on the card. Its screenshot step was then cancelled by another session's push to main,
  so the watch shots (w1 to w18) of that run are missing; w17 was last seen in run 39665922123, w18 not yet seen.
What shows where (phone-started vs watch-started, reading vs steep):
  One timer, one card (LiveTimerRules.watchShowsCard, Shared/LiveTimer.swift, tested; table in docs/PLATFORM.md).
  - Phone-started reading session: the phone's Live Activity (Lock Screen, Dynamic Island); the system mirrors it to
    the watch's Smart Stack, where it draws the new small layout (ReadingActivityWatchCard). Leaf's own Timer widget
    stays on today's reading. If Live Activities are off on the phone (or it couldn't start one), the phone says so
    and the watch's Timer widget shows the session instead.
  - Phone-started steep: the Live Activity now covers the steep too: "Earl Grey · steeping" counting down, then
    "Earl Grey is ready" (on time, from the stale date, with no update), and it carries on as the cup of reading if
    a session starts for the same book. Mirrored to the watch the same way.
  - Watch-started reading session: the watch's Timer widget (rectangular, corner, circular, inline) counts down to
    the goal, then up, with high relevance so the Smart Stack brings it forward. If the phone app is open when it
    hears of the session it starts a Live Activity and tells the watch, and the watch's card steps aside for the
    mirrored one. The WKExtendedRuntimeSession still keeps the session alive with the wrist down.
  - Watch-started steep: the watch's Timer widget only, counting down to ready, then "Earl Grey is ready" with top
    relevance for five minutes, gone 30 minutes after it's ready. The extended runtime now runs during a steep too
    (that's what keeps Leaf in the Dock), and the existing notification is still the one tap when it's ready.
  - No timer: the Timer widget shows today's reading, with relevance 0.
APIs confirmed from the SDK vs assumed:
  Confirmed by compiling against the iOS 26 / watchOS 26 SDKs in CI (signatures, not behaviour):
    ActivityConfiguration.supplementalActivityFamilies([.small]), EnvironmentValues.activityFamily,
    ActivityFamily.small; Text(timerInterval:pauseTime:countsDown:showsHours:); ProgressView(timerInterval:
    countsDown:label:currentValueLabel:); TimelineEntryRelevance(score:duration:); Timeline(policy: .never);
    WidgetCenter.reloadTimelines(ofKind:); accessoryRectangular / Corner / Circular / Inline with widgetLabel,
    widgetAccentable and AccessoryWidgetBackground; Activity.request / update with a stale date.
  Assumed from Apple's documentation, not seen on a device:
    - That the system mirrors an iPhone Live Activity to the paired watch's Smart Stack, and uses the .small layout
      when the activity declares it (otherwise it would squeeze the Lock Screen view).
    - That the Smart Stack actually promotes a widget for its TimelineEntryRelevance score (the system weighs it
      with its own signals; RelevanceKit isn't used because I couldn't verify its API here).
    - That a watch app holding a WKExtendedRuntimeSession shows in the Dock while it runs.
Files and targets added or changed (incl. project file):
  No new target, entitlement or capability; the project file is unchanged (synchronized folders pick up new files).
  Shared (phone + watch):       Shared/LiveTimer.swift (new: LiveTimer, phases, relevance, expiry, LiveTimerRules),
                                Shared/WatchSync.swift (WatchSnapshot.liveActivitySessionID, optional)
  LiveActivityShared (phone + LeafWidgets): ReadingActivityAttributes.swift (states steeping, teaReady; raw values
                                kept), ReadingActivityViews.swift (steep wording, ReadingActivityWatchCard)
  LeafWidgets:                  ReadingLiveActivity.swift (family switch, supplementalActivityFamilies)
  Leaf:                         LiveActivityController (steeps, carry-on into the session, sessionShown, tells the
                                watch), WatchBridge (sends sessionShown), TodaySteep (syncs the activity),
                                LiveActivityStage (liveactivity.steeping, liveactivity.watch)
  WatchComplicationShared (watch app + LeafWatchWidgets): ComplicationTimer.swift (new), TimerViews.swift (new),
                                ComplicationSnapshot (timer, optional; timerKind)
  LeafWatchWidgets:             LeafWatchTimerWidget.swift (new widget LeafWatchTimer), LeafWatchWidgets.swift (bundle)
  LeafWatch:                    ComplicationFeed (works out the timer and the rule, reloads both kinds; TimerGallery),
                                WatchStore (publishes on every change; runtime during a watch steep), LeafWatchApp
  Tests:                        LeafTests/LiveTimerTests.swift (new), LiveActivityContentTests (new raw values)
  Docs:                         docs/PLATFORM.md (the live timer on the wrist); TESTFLIGHT.md unchanged (nothing new
                                to set up)
  Screenshots: 152-liveactivity-steeping (the Lock Screen and Dynamic Island while steeping),
               153-liveactivity-watch (the small Smart Stack card in all six states), w17-timers (the watch Timer
               widget faces, drawn in the watch app's debug gallery since a simulator has no face to put them on),
               w18-timers-steep (the same for a steep and for ready tea)
Could not verify (device-only):
  The mirrored Live Activity on a real watch and which layout it uses; the Smart Stack promoting the Timer widget
  when it starts and letting it fall back; the Timer widget on a face (corner and circular sizes, tinting); the Dock;
  the hand-off when the phone starts a Live Activity for a watch-started session (a second or two of both cards is
  possible while the snapshot travels); time drift between phone and watch clocks in the countdown; battery.
Design decisions the owner should know about:
  - The phone's Live Activity wins whenever it exists; the watch's own card is the fallback, never a second card.
  - A steep belongs to the device it started on; the phone doesn't learn about watch steeps.
  - The Live Activity now covers the steep before a session (it was session-only); with Live Activities off in Leaf's
    settings nothing changes.
  - Expiry: a steep leaves the face 30 minutes after the tea is ready, a session 8 hours after it started, so a
    forgotten timer never lingers. A met goal drops to lower relevance five minutes after it's met.
  - The Timer widget is a separate widget ("Reading timer") the reader adds to a face or the stack; the existing
    complications are unchanged.
Known issues / follow-ups:
  - A watch-started session gets a phone Live Activity only if the phone app is in the foreground at some point
    while it runs (ActivityKit can't start one from the background without a push server).
  - If the reader dismisses the phone's Live Activity while the phone app is in the background, the watch keeps
    deferring to it until the phone next syncs, so the wrist can be without a card for a while.
  - Widgets (Home Screen, Lock Screen) are next in the queue and can reuse LiveTimer for a running session.
=== END REPORT ===
```
