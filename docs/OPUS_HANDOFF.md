# Leaf: UI and design handoff

You are picking up **Leaf**, a native iOS 26 / watchOS 26 SwiftUI app: a cozy reading planner ("a warm corner, a pot of
tea, a good book"). All the logic is built and tested. **Your job is the UI, motion and design**, plus a little
Apple-platform plumbing that can only be compiled on a Mac. Read this whole file first, then the docs it points to.

Owner's standing rule: **commit and push straight to `main`. Never create a branch** unless asked. Run
`git pull --rebase origin main` before each push; other engineers are pushing to the same branch.

---

## 1. What exists

Leaf is on TestFlight (first round). Reader feedback after that round, and what we did about it:

| Feedback | Where it stands |
|---|---|
| Library too small, picking should be easy | Logic done: 5k books now, SQLite catalog for 250k, 140 carousels, taste recommender, swipe deck. **UI to do.** |
| "Where are you?" is hidden | Logic done (`StartingPosition`, `confirmPosition`, `ProgressMode`). **UI to do.** |
| Today (home) isn't useful | `TodayBrief` view-model done. **UI to do.** |
| Love the "Still up?" greeting | Greeting engine done (385 lines, ~50 moments). **UI to do.** |
| Cozy books and tea niche | Tea, cups, ambience sounds, challenges, stamps done. **UI to do.** |
| Gaussian blur design language | Not started in UI. Physics helpers done. **UI to do.** |
| Bookmark ribbon feels rigid | Physics done (`RibbonSimulation`). **UI to do.** |
| Love the sliders and blurred numbers | `ScrubModel` done. **UI to do.** |
| Plan page could be awesome | Forecast engine and stats done. **UI to do.** |
| Live Activity with the countdown | Extension target exists with a plain placeholder. **UI + controller to do.** |
| Watch app is boring | Protocol and store done. **UI to do.** |
| Multiple reading times per day, a book per time | Logic done (`ReadingSlot`, `SlotPlanner`). **UI to do.** |

Nothing in the screens has been redesigned yet. The existing screens still work; they just don't use the new engines.

## 2. Ground rules

- **Language and targets:** Swift, SwiftUI, iOS 26.0 and watchOS 26.0, Swift 5 language mode. No third-party packages,
  no accounts, no analytics, no network beyond Open Library covers. Everything stays on device or in the reader's iCloud.
- **Design intent:** mix of editorial paper and Liquid Glass. Calm, warm, one green accent. Crisp for what you act on,
  soft (blurred) for what you feel. Read `docs/DESIGN.md` (principles, colour, type, screens, motion, haptics, voice)
  and `docs/DESIGN_SYSTEM.md` (the component API; use it, extend it, never fork it). Where `docs/NEXT.md` disagrees
  with `DESIGN.md`, `NEXT.md` is newer.
- **Voice means written tone, not sound.** Nothing in Leaf ever speaks: there is no text-to-speech and no spoken greeting.
  The "voice engine" (`Shared/Voice/`) only writes short text lines like the "Good afternoon." headline on Today. The
  only audio is the optional ambience (rain, fire...) and a few tiny cue sounds, and **both are off until the reader
  turns them on** (`preferences.ambienceID == nil`, `CozySounds.shared.isEnabled == false`). Never start audio
  automatically, never on launch.
- **Copy:** warm, short, specific, never guilt, no exclamation marks, typographic apostrophes in UI copy (’).
  The engines already write most of the words; use theirs.
- **Accessibility is not optional:** Dynamic Type must not clip the big numerals, every gesture needs a non-gesture
  alternative, honour Reduce Motion and Reduce Transparency (blur becomes a flat tint, drifting stops), VoiceOver reads
  forecasts as sentences (the narrator provides them), check contrast in light and dark, and be careful in Low Power Mode.
- **Performance and battery:** blur cost scales with radius and area. Pre-render static blurs, animate small areas, keep
  `TimelineView` scenes at about 15 fps, stop simulations when settled (`isSettled`). The session screen stays awake, so
  keep it cheap.
- **Do not change engine logic.** `Shared/` is pure Foundation code with tests; it also compiles into the watch app and
  runs on Linux. If you find a bug there, fix it minimally with a test and mention it in your report. Do not move logic
  into views. Views draw view-models.
- **Keep names unique** (grep before adding a type). **Don't add files to `Shared/`** unless they are Foundation-only.
- **Haptics:** reuse `Haptics.shared` (see `Leaf/Services/Haptics.swift` and DESIGN.md section 8). New moments (tea ready,
  stamp earned, magnet snap) should be new named patterns in that file, not ad-hoc calls.

## 3. How to verify (there is no Mac)

You cannot run Xcode. The compiler is **GitHub Actions on a macOS runner**.

1. `git push origin main` triggers the `iOS` workflow (it ignores pushes that only touch `docs/**` or `*.md`).
2. `python3 scripts/ci.py wait` blocks until the newest run finishes and prints each step.
3. `python3 scripts/ci.py errors` prints the compiler and test errors. Fix, push, repeat. A cycle takes 8 to 12
   minutes, so **batch changes and read your own code carefully before pushing**. A single typo costs a cycle.
4. `python3 scripts/ci.py shots` saves the simulator screenshots from the last run into `.ci/shots/` (light and dark,
   iPhone and watch). Open them and **look at them**: this is how you check the design. Screenshots are staged by
   `scripts/ci_screenshots.sh` using debug launch arguments, for example
   `-LeafDemo YES -LeafScreen today` (see `Leaf/App/LaunchOptions.swift`, `RootView.swift`, `MainTabs.swift`,
   `LeafWatch/WatchStore.swift` `LaunchScreen`). **Every new screen or state you build should get a staging name and a
   `shot` line in that script**, otherwise you are designing blind. `DemoData.make()` fills a lived-in library
   (paused book, journal, tea sessions, challenges); extend it if a state needs data.
5. `scripts/check_pbxproj.py` must pass if you ever touch `Leaf.xcodeproj` (CI runs it first). New Swift files in
   `Leaf/`, `LeafWatch/`, `LeafWidgets/` and `LiveActivityShared/` are picked up automatically (synchronized folders);
   only new *targets*, entitlements or build settings need the project file.
6. Logic tests run anywhere with a Swift toolchain: `scripts/linux_tests.sh` (Shared/ only). Store and UI tests run in CI.
7. Previews: every component should have a `#Preview` (light and dark), like the existing design system does.

Things CI cannot show: real Dynamic Island, Live Activity, Core Haptics, audio, CloudKit, Double Tap, device motion.
Write those carefully, keep them small, and say in your report what could not be verified.

## 4. Repo map

```
Leaf/App            LeafApp (startup wiring), RootView, MainTabs, AppRouter, DemoData, LaunchOptions
Leaf/Features/      Today, Session, Library, Book, Search, Plan, Settings, Onboarding (SwiftUI screens)
Leaf/DesignSystem/  colour, type, motion, buttons, covers, rings, dials, scrubbers (28 files, see DESIGN_SYSTEM.md)
Leaf/Services/      LibraryStore (the one source of truth, @Observable), BookCatalog, Reminders, Haptics,
                    WatchBridge, CloudSync, AmbiencePlayer, CozySounds, AILibrarian, TodayService (ForecastService,
                    LibraryStore.todayBrief), Persistence, OpenLibrary
LeafWatch/          watch app (WatchStore, PhoneBridge, TodayPage, SessionView)
LeafWidgets/        Live Activity widget extension (placeholder UI) + LiveActivityShared/ (ActivityAttributes)
Shared/             pure logic, Foundation only, tested on Linux: Models, Planner, Recommender, Collections, SwipeDeck,
                    StartingPosition, ReadingSlots, TodayBrief, WatchSync, Moment (Season, Daypart, Cups) and the
                    folders Forecast/ Insights/ Voice/ Cozy/ Audio/ Sync/ Interaction/
LeafTests/          Swift Testing (Linux for Shared, Xcode for the store)
docs/               DESIGN.md, DESIGN_SYSTEM.md, NEXT.md (long brief, sections tagged [UI]), ENGINEERING.md, PLATFORM.md,
                    SYNC.md, CATALOG.md, TESTFLIGHT.md, this file
scripts/            ci.py, ci_screenshots.sh, linux_tests.sh, check_pbxproj.py, testflight.sh, catalog/ (data pipeline)
```

`LibraryStore` (`@MainActor @Observable`, injected as an environment object) owns `data: LeafData` and the `plan`.
Views read from it and call its methods; it saves, schedules reminders, pushes to the watch and syncs to iCloud.
`BookCatalog.shared` is the offline catalog (`books` is the browse pool, `search`, `book(id:)`, `collections(context:)`,
`starterBooks`).

## 5. The engines and what each screen should call

### Today (the home screen)
- `let brief = store.todayBrief(catalog: catalog, forecast: forecastService.result, weather: nil)` returns a
  **`TodayBrief`**: `mode` (`brandNew`, `reading`, `goalMet`, `restDay`, `betweenBooks`), `greeting` (headline plus
  subline, a `tag`, and a `lineID`), `tea` and `steepSeconds`, `current` (`TodayBook`: the item, today's `assignment`,
  `needsPosition`), `slots` (today's reading times with the book and pages for each) and `nextSlot`, `minutesReadToday`,
  `goalMinutes`, `goalProgress`, `minutesToGoal`, `cupsToday`, `cupMinutes`, `streak`, `week` (`[DayStat]`),
  `yearGoal` (`YearGoalPacing?`), `nudges` (`[TodayNudge]`, at most 3), `picks` (`[Recommendation]`: 6 when between
  books, else 1), `challenges` (`[ChallengeProgress]`, running ones), `quote` (`JournalEntry?`), `forecastSentence`.
- Call `store.markGreetingShown(brief)` once when the greeting appears (so tomorrow's line differs).
- `ForecastService` (`@Observable`): `refresh(from: store)` then read `result`; `sentence(for: bookID, store:)`.
- Actions: `store.startSession(bookID:origin:teaID:goalSeconds:ambienceID:)`; `TeaRitual.plan(tea:strength:cupMinutes:)`
  (steep first, then a cup-length read; `.stage(afterElapsed:)`, `.makeSession(...)`); `store.logManual(bookID:minutes:toPage:)`
  (quick log without the timer); `store.apply(StartingPosition, to:)`; `store.pause(_:)`; `store.dismiss(_:)`.
- **Reading times:** `ReadingSlot` (hour, minute, optional weekdays, optional `bookID`, label). Store:
  `addReadingSlot/updateReadingSlot/removeReadingSlot`, `slotPlans()`, `nextSlotToday`. With several books on the
  go, tie a time to a book ("mornings are for Circe"). Tying slots to different books works best with
  `planMode == .sideBySide`; consider prompting for it.
- States to design for: morning, evening, late night, rest day, goal met, nothing in Reading, brand new, returning after
  two weeks, finishing a book tonight.
- Concept to build: **the Reading Nook** header (atmosphere, big serif greeting, one "Steep and read" button) over a
  stack of purposeful cards (Left off with a tappable `p. 142` chip, Forecast insight, Cup progress, Reading times,
  Tonight's pick or the swipe deck when between books, Week as tea-ring stamps, Year goal pacing, Challenge, Quote,
  Nudges). Details in NEXT.md section 4.

### "Where are you?" (position)
- `StartingPosition`: `.justStarting`, `.page(Int)`, `.percent(Double)`, `.alreadyRead(on: Date?)`;
  `store.apply(position, to: bookID)`. `LibraryItem.positionConfirmed`, `.progressMode`, `.startPage`.
- Show it as a sheet before a book is first started or added with no position, from Today's page chip, from book detail,
  and from the `confirmPosition` nudge. Make it big and prominent, with the page scrubber as the main control and the
  ribbon as an alternative. Keep a numeric fallback. NEXT.md section 3.

### Session screen (reading timer, tea ritual, journal)
- `ActiveSession` (`teaID`, `goalSeconds`, `ambienceID`, `remaining(at:)`); `Tea`/`TeaCatalog`/`TeaSuggester`;
  `TeaRitual` (stages: steeping, ready, reading). `CozySounds.shared.teaBrewStarted()/teaReady()/pageTurned()`;
  `AmbiencePlayer.shared.play(id, volume:)/stop(fadeOut:)` with `AmbienceCatalog` (rain, fireplace, kettle, cafe, library).
  Set `CozySounds.shared.isEnabled` from a preference you add if you want a sound toggle.
- Journal: `store.addJournalEntry(bookID:kind:text:page:sessionID:)` (kinds `.thought`, `.quote`), `journal(for:)`,
  `updateJournalEntry`, `deleteJournalEntry`. Quote scanning is VisionKit Live Text (`DataScannerViewController`) and is yours to add;
  store text only.
- End of session: `SessionOutcome` plus `SessionWrapUp.line(for: SessionWrapUpInput, seed:)`.

### Plan -> Forecast (and stats)
- `ForecastService.result: ForecastResult`: `books: [BookForecast]` (`median`, `p10`, `p90`, `probability(by:)`,
  `curve(points:)` for fan charts, `confidence`), `year: YearForecast` (range, `probabilityOfGoal`), `plan`.
- What-if sliders: `await forecastService.whatIf(dailyMinutes:readingDays:store:)` then
  `whatIfResult.comparison(against: baseline)` for delta chips (use the **same seed**; the service does).
- `ForecastEngine(data:now:calendar:)` directly (off the main actor!) for `inversePlan(bookID:by:)` (minutes per day
  needed, `tonightOnly`), `inversePlan(booksThisYear:)`, `smartOrder(goal:)` (`OrderSuggestion` with per-book deltas),
  `catchUp()`, `stalledBooks()`, `backtest()` ("your 80 percent ranges have been right 78 percent of the time").
- `ForecastNarrator(now:calendar:)` writes the sentences ("Probably done Sunday, between Saturday and Tuesday."): use them
  for text and VoiceOver. Always show real numbers beside any cute unit.
- `InsightsEngine(data:now:calendar:)`: `heatmap(year:)` (`HeatCell.ring` sizes the tea-ring stamps), `bestTimeOfDay()`,
  `speedTrend()`, `genreMix()`, `lengthMix()`, `tbrDepth()`, `personality()` (shareable archetype), `yearInBooks(year:)`
  (a cozy wrapped with `months` rings), `weeklyLetter(weekEnding:)`, `yearGoalPacing()`, streaks. `WeeklyLetterText.compose`
  writes the Sunday letter. `JournalTools` for search/export/quote of the day.
- Challenges: `ChallengeCatalog.all`, `ChallengeEvaluator.allProgress(data:now:calendar:)`, `.availableChallenges(...)`,
  `.enrollment(for:now:)` to join (`store.joinChallenge/leaveChallenge`), `StampLedger.entries(...)` for the collectible
  stamp wall. Palette tokens (`paper, chai, matcha, rooibos, steam, amber, rose`) need colours in `LeafColor.swift`.

### Library, Book detail, Search, Onboarding
- Shelves: `Shelf` is now `reading, toRead, finished, paused` (`Shelf.main` is the three tab shelves). **Paused has no
  home in the UI yet**: design where it lives (a quiet section on the Library, or a fourth tab). `store.pause(id)`,
  `startReading(id)`.
- Search rows: `catalog.collections(context: store.recommendationContext(catalog: catalog))` returns up to 140
  `BookCollection`s (`title`, `subtitle`, `kind` personal/context/browse, `books`, `reasons` by book id). The current
  Search screen draws them as plain covers in a `LazyVStack`. To design: row shapes, "See all", the **why this** caption
  (`reasons`), "Not for me" (`store.dismiss`) with Undo (`undismiss`), "More like this"
  (`Recommender(stats:context:).similar(to:in:limit:)`), a **Your taste** screen (`TasteProfile.topGenres/topThemes`), a jump bar
  of categories, and the **swipe deck** (`SwipeDeck(pool:stats:context:seed:)`: `peek(n)`, `swipe(.keep/.pass/.startNow)`, `undo()`;
  commit `keeps`/`starts`/`passes` to the store). The deck is also a great onboarding step.
- Book detail: edition picker from `Book.pageCounts` ("Your copy has 310 pages. Others: 330, 366"; apply with
  `store.updateBook(_, pages:)`), journal tab, progress as the ribbon, "Set aside" (pause), reread.
- Settings to add: reading times, favourite tea and strength, cup length (`cupMinutes`), ambience and volume, catch-up
  mode (`CatchUpMode`), yearly goal, weekly letter, Apple Intelligence greetings (`AILibrarian.isAvailable`,
  `preferences.aiGreetings`), Live Activities, **iCloud** (`store.sync?.status`, `.pendingChanges`, `forceFullSync()`;
  the Reset confirmation must say other devices keep their copy), progress mode, haptics.

### Motion, blur and interaction (`Shared/Interaction/`, check the files for exact names)
- **Blur language** (NEXT.md section 7): focus-pull transitions (outgoing blurs as incoming sharpens), blurred cover
  backdrops (pre-rendered, with a scrim for legibility), bokeh, rain on glass, steam, per-digit blur. `AtmosphereField` gives
  seeded, time-parameterised positions to draw from a `TimelineView`/`Canvas` at about 15 fps; `calm` slows everything when paused.
- **Ribbon** (section 8): `RibbonSimulation` is a verlet chain with tilt/impulse/drag inputs and `isSettled`; draw it with
  `Canvas` (Catmull-Rom curve, tapered width, satin highlight from curvature, soft shadow). `RibbonDepth` maps ribbon depth to page.
  Feed device tilt from `CMMotionManager` at about 30 Hz and stop everything when settled. Reduce Motion gets the fixed pose.
- **Scrub numbers** (section 9): `ScrubModel` gives detents, magnetic stops, rubber banding, momentum and the feedback to
  play (haptic event with intensity/sharpness, blur radius clamped to 6 pt, digit transition). Generalise `MinutesDial`,
  `TickRuler` and `PageScrubber` into one scrub control and use it for minutes, pages, finish-by dates, tea steep time,
  the what-if sliders and the watch crown.

### Apple Watch (`LeafWatch/`)
- `WatchSnapshot` now carries `greeting`, `tea`, `cupMinutes`, `queue`, `forecasts`, `yearGoal`, `slots`, `liveActivities`
  alongside the old fields. `WatchStore` methods: `start(bookID:teaID:goalSeconds:)`, `quickLog`, `setPage`, `addJournal`,
  `moveBook`, `addBook(query:)`, `startSteep/cancelSteep` (`SteepTimer`). Pages to design (NEXT.md section 12): Today nook,
  focus-pull countdown timer with steam/bokeh, tea timer handing off to reading, quick log with the crown, Where was I,
  Forecast, Week stamps, Shelf, quick add by dictation, Journal by dictation, Always-On variant (`isLuminanceReduced`),
  Double Tap (`handGestureShortcut(.primaryAction)`).
- Still to build for the watch (platform, needs the project file): `WKExtendedRuntimeSession` so a session survives
  wrist-down, and complications / Smart Stack widgets (a watch widget extension target). Add `WKBackgroundModes` only if you
  also verify which session type App Review accepts for reading; note the uncertainty in your report.

### Live Activity and Dynamic Island
- Target and placeholder UI exist: `LeafWidgets/ReadingLiveActivity.swift`, state in
  `LiveActivityShared/ReadingActivityAttributes.swift` (`ReadingActivityContent`: `timerStart`, `isPaused`,
  `pausedElapsedSeconds`, `goalSeconds`, `currentPage`, `state`). **There is no `LiveActivityController` yet**: write it
  (start in the foreground when a session starts, update on pause/resume/page log, end on finish, respect
  `preferences.liveActivities` and the 8-hour limit, hide when ActivityKit is disabled).
- Hard limits (NEXT.md section 11): no per-second custom animation; the countdown must be `Text(timerInterval:)` or
  `ProgressView(timerInterval:)`; the blurred focus-pull has to come from state changes (pause, resume, goal reached,
  page logged) via `.contentTransition` and a **pre-rendered blurred cover** saved in the App Group container
  (`group.com.norvodesigns.leaf`) and referenced by name. Keep `ContentState` tiny. `LeafWidgets` cannot import `Shared/`;
  compute short lines in the app (`LiveActivityLines.line(for:...)`, at most 28 characters) and put them in the state.
- App Intents (Start, Pause, Resume, Log pages), an `AppShortcutsProvider`, and a Focus filter are still to do. Intents used as
  Live Activity buttons must be compiled into both the app and the extension (`LiveActivityShared/`).

## 6. Work packages

Do these in order unless told otherwise. Each ends with a report (section 8). Keep each push building green.

1. **UI-1: Today, Where are you, reading times, swipe deck.** The Nook header and card stack, the position sheet, the
   reading-times editor and display, the deck (Search tab entry, Today's between-books state, and an onboarding step). Add
   staging names and screenshots for every state listed above.
2. **UI-2: Session, tea ritual, journal, Live Activity.** The session screen with the tea steep stage, ambience picker,
   quick journal/quote capture, wrap-up; `LiveActivityController`, the real Live Activity and Dynamic Island design; App
   Intents, Shortcuts and the Focus filter.
3. **UI-3: Motion language.** Blur primitives, the physical ribbon (replace `RibbonTail`) and its use as the progress
   control, the generalised scrub control, haptic patterns, and applying them across the app (focus-pull transitions,
   blurred cover backdrops, numeric text transitions).
4. **UI-4: Plan to Forecast, stats, challenges.** Fan charts, what-if sliders with live delta chips, finish-line mode,
   smart-order preview, catch-up, stall prompts, the tea-ring heatmap, personality, Year in Books, the weekly letter,
   challenges and the stamp wall.
5. **UI-5: Library, Book detail, Search rows, Settings, Onboarding.** Paused shelf, edition picker, journal tab, row
   designs with reasons / not-for-me / See all / jump bar / Your taste, all the new Settings (including iCloud status), and
   onboarding updates (sync note, first reading times, deck).
6. **UI-6: Apple Watch overhaul** plus complications and extended runtime (platform work in the project file; use
   `scripts/check_pbxproj.py`).

## 7. Things to know

- `Leaf/Resources/catalog.sqlite` (when present) is the book database; `scripts/catalog/` builds it. See `docs/CATALOG.md`.
- iCloud sync is per build (`LEAF_CLOUDKIT_ENABLED`, one Release setting that Organizer and testflight.sh share: on in Release since the schema went to Production on 2026-10-22; off in Debug and CI). See `docs/SYNC.md`.
- The forecast, insights and recommender are deterministic given a seed and `now`; use `SeededGenerator.daySeed(now, calendar:)`.
- Dates in tests and previews should use an injected `Calendar`; never call `Date()` inside a view-model.
- The user is on TestFlight: do not break launch. Old saved data must keep loading (all new model fields are optional or
  defaulted; keep it that way).
- Two catalog formats exist during the transition; if `BookCatalog` or `Leaf/Resources` changed since you started, pull first.

## 8. Report back (required)

When a work package is finished, or you are stopping, end your final message with this block so the lead engineer can
see exactly what changed. Also commit it as `docs/reports/<package>.md` if useful.

```
=== REPORT FOR LEAD ===
Package: <UI-n name>
Status: done | partly done | blocked
Commits pushed to main: <short shas and one-line messages>
CI: <last run id, green or red, what failed if red>
Screens / states built (with the staging name and screenshot file for each): ...
New public types or files (one line each): ...
Engine APIs I used, and any I needed but did not find or that behaved oddly: ...
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/ (engine fixes, project file): ...
Could not verify (device-only things): ...
Design decisions the owner should know about or veto: ...
Known issues / follow-ups, most important first: ...
Next package you recommend: ...
=== END REPORT ===
```
