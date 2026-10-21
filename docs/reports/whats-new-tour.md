# What's new and the tour: report

```
=== REPORT FOR LEAD ===
Package: What's new sheet + "A quick look around" (coach-mark tour)
Status: done (device-only checks listed below)
Commits pushed to main:
  d44e1b4 What's new once after an update, and a quick look around the app
  7c51633 Tour: notes show for targets right under a large title, and Plan's first note points at the forecast
CI: run 39665922123 (8c01e92): build, all unit tests (incl. the 12 in WhatsNewTests), watch build, archive and
  screenshots green; screenshots showed no note on Library, Plan and Search, fixed in 7c51633. Final run: 39676881472 (039008a), re-run after the first attempt never got a runner: build, all unit
  tests, watch app, unsigned archive and warnings green; screenshots showed the tour on Library, Plan and Search
  and the poster's footer on the card. Its screenshot step was then cancelled by another session's push to main,
  so the watch shots (w1 to w18) of that run are missing; w17 was last seen in run 39665922123, w18 not yet seen.
Screens / states built (staging name -> screenshot file, all with -LeafDemo YES):
  What's new sheet (this version's release)        -LeafScreen whatsnew          -> 145-whatsnew(-dark)
  Tour on Today: the nook                          -LeafScreen tour.today        -> 146-tour-today(-dark)
  Tour on Today: Steep and read                    -LeafScreen tour.today.steep  -> 147-tour-today-steep
  Tour in Library: the shelves                     -LeafScreen tour.library      -> 148-tour-library
  Tour in Plan: the forecast                       -LeafScreen tour.plan         -> 149-tour-plan
  Tour in Search: rows to browse                   -LeafScreen tour.search       -> 150-tour-search
  Tour in Settings (floating notes)                -LeafScreen tour.settings     -> 151-tour-settings
  Settings, About: "What's new" and "Replay the tour" rows (in the existing Settings screenshots)
New public types or files (one line each):
  Shared/WhatsNewGate.swift            AppBuild (version + build, compared part by part as numbers), WhatsNewGate
                                       (releasesToShow, remember), TourArea, TourStep, TourProgress
  Leaf/Features/WhatsNew/WhatsNewContent.swift  WhatsNewRelease, WhatsNew.releases (newest first; plain data),
                                       currentBuild, saved state; TourSteps.all (the tour's words)
  Leaf/Features/WhatsNew/WhatsNewView.swift     the sheet: version, headline, a card per change, Continue, Take the tour
  Leaf/Features/WhatsNew/CoachTour.swift        CoachTour (progress in UserDefaults per step), .coachMarks(area) host
  Leaf/DesignSystem/CoachMark.swift    coachMarkAnchor(_:), CoachMarkCallout, CoachMarkPlacement, CoachMarkList (VoiceOver)
  AppRouter.whatsNew (WhatsNewRequest); RootView.offerWhatsNew; Settings rows
  Tests: LeafTests/WhatsNewTests.swift (12: version and build order, fresh install, update from before What's new,
         every unseen release once, same or older build, tour order, skip, replay, last step, VoiceOver list)
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  LibraryStore.hasOnboarded, LaunchOptions.isScripted, the router's sheet flags (so What's new never lands on top of
  a session or another sheet). Nothing missing.
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/:
  Shared/WhatsNewGate.swift, LeafTests/WhatsNewTests.swift, scripts/ci_screenshots.sh (145 to 151).
Could not verify (device-only things):
  The real update path (install build N, then N+1 from TestFlight: the sheet should appear once, a second after
  launch); VoiceOver reading the tour as one list; coach marks while scrolling on a real phone (a target scrolled out
  of sight waits until it's back); Dynamic Type at the largest sizes in the callout.
Design decisions the owner should know about or veto:
  - Fresh install: no What's new ever; every release is remembered as seen, and the tour starts when onboarding ends.
  - Someone updating from a build before this one (no record on the device) sees only the newest release.
  - What's new waits for a quiet moment: if a session, sheet or Settings is open a second after launch, it skips this
    launch and tries on the next.
  - The tour is one note at a time, only on the first visit to each part while it runs; "Skip tour" ends it for good
    (Replay the tour in Settings brings it back). Settings' notes float near the bottom, since its rows are in a form.
  - With VoiceOver on, an area's notes come as one ordered list in a sheet instead of floating callouts.
  - The release list adds two lines the brief didn't name, since they ship in this version: "A wall of spines"
    (the shelf wall and Wrapped) and the watch timer in the Smart Stack (added to the Apple Watch line).
Known issues / follow-ups, most important first:
  - The first screenshot run caught Library, Plan and Search showing no note: a target only counted as on screen
    well inside the safe area, which ruled out the shelf switcher under the Library title and Search's tall first
    row, and Plan's first target was below the fold. Fixed in 7c51633 (see CI above).
  - How the ring and callout follow a target while the screen scrolls under an open note is untested on a device
    (they are placed from the target's anchor on every layout pass; a target that leaves the screen hides the note
    until it's back).
  - TestFlight builds of one version differ only in build number, so each new TestFlight build with a new release id
    shows the sheet; builds without a new release id show nothing.
Next package you recommend: Widgets (the watch timer work laid the snapshot groundwork).
=== END REPORT ===
```
