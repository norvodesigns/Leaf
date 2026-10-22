# UI report: assignments A to H on Canopy (Oat)

The consolidated report for the Engine session, written by the final review pass (assignment G) on 2026-10-22.
Every screen is on the Canopy design system with the Oat palette (`docs/design/DESIGN_SYSTEM.md`), which Matt
approved on 2026-10-22. Per-feature detail is in the reports linked under each assignment.

```
=== UI REPORT ===
Final commit on main: 6c82f49 (code; this report is a docs-only commit on top, which CI skips)
CI status for that commit: build, all unit tests, watch build, unsigned archive and warnings GREEN.
  The run shows red only because the Screenshots step hit its 55-minute limit after publishing 225 shots
  (refs/ci/screenshots); the watch shots at the end were cut. Run 39753663066:
  https://github.com/norvodesigns/leaf/actions/runs/39753663066

Assignments:
A done    | Fast adding: search-as-you-type over the offline FTS catalog (Open Library merged after 250 ms), one-tap +
            to Up next with an Undo toast, hold for Start reading / Want to read / Already read, a .medium quick-add
            sheet, VisionKit barcode scan and typed ISBN (Open Library lookup, online only), a prefilled hand form.
            docs/reports/fast-adding.md
B done    | Ask the Librarian: an offline written conversation (mood, time at your pace, length) ending in a
            carousel of picks with a true "why this" line and a fit line; Show me others, More like this, Not for me
            with Undo, and "Swipe through the shelf" into the deck. Engine: Shared/Librarian.swift (tested).
            Ways in: Search and Library's "Find your next book". No speech, no network AI.
            docs/reports/ask-the-librarian.md
C done    | Widgets on Canopy: small (goal ring + next reading time), medium (book, pages, black Begin reading),
            large (today's reading times, Up next, the week), Lock Screen (circular, rectangular, inline), StandBy.
            Control Center: Begin reading, Steep and read, Log pages (no app launch). Live Activity in Oat charcoal
            with a Dusk timer and Clay steep; watch complications match. Reports: UI-2.md, watch-live-timer.md,
            and the widgets section of docs/PLATFORM.md
D done    | Nook scenes: Plain (default, Canopy Dusk), realistic Rain on glass / Fireplace / Dawn (Metal shaders
            compiled at run time) and soft Glow / Mist / Drizzle. Visual only; ambience audio stays a separate opt-in.
            Scenes hold still when paused, under Reduce Motion, in Low Power Mode and in the background, and turn
            the session dark. Matt exempted the scenes from Canopy's no-blur rule (they sit behind the UI).
E done    | Reading circles (under You): club shelf, shared schedule with meetings and page targets, discussion
            prompt cards, a progress ring per member (local/manual members), empty state, share sheet. Every member
            already has a `remoteID` so a synced version can slot in without a redesign.
F done    | Polish pass: "Read without tea" is a real button, 44 pt targets, empty states, CanopyFeel haptics in
            History / Tea / Position / Settings, What's New dismissible, the coach tour removed (Canopy rule: no
            tours). docs/reports/F-polish-pass.md
G done    | This review: all ~200 CI screenshots (light, dark, AX text) checked against DESIGN_SYSTEM.md. Fixed in
            6c82f49: Plan's reading-time rows at accessibility sizes (titles and times were cut to "The…",
            "Morn-ing"), the reading log's date column breaking mid-word ("We d 21"), the Reading shelf going one
            card wide at AX sizes so titles and authors aren't cut, the bottom bar saying "Find your first book" to
            readers who have finished books ("Find your next book" now), and the Live Activity's tea label ending
            in "EARL GREY · STEE…" (falls back to the tea's name). Earlier review passes: agent2-review.md.
H done    | Watch: live reading and steep timers in the Smart Stack / Dock (one timer, one card: phone-started
            sessions mirror the Live Activity; watch-started ones use Leaf's Timer widget), extended runtime with the
            wrist down, then restyled on Oat-on-black with rounded numerals and no blur or bokeh behind the timer.
            The six existing pages were kept (the redesign brief's three-page merge would remove features).
            docs/reports/watch-live-timer.md, UI-6.md

Files added / changed (grouped by feature):
  Design system   Leaf/DesignSystem/Canopy/* (tokens, controls, displays, surfaces, CanopyFeel, gallery),
                  docs/design/DESIGN_SYSTEM.md, docs/design/REDESIGN.md, app icon (scripts/design/make_icon.py)
  Shell / Today   Leaf/Features/Today/*, Leaf/Features/Session/SessionAccessory.swift, Leaf/Features/You/YouView.swift
  Session / tea   Leaf/Features/Session/*, Leaf/Features/Tea/*, Shared/TeaPreferences.swift ("Teas you like")
  A Fast adding   Leaf/Features/Search/{SearchView,SearchRows,SearchShelves,SearchMerge,QuickAddSheet,ISBNScanSheet}.swift,
                  Leaf/Features/Book/AddBookManuallyView.swift, Shared/ISBN.swift (+ LeafTests/ISBNTests.swift),
                  OpenLibrary.lookup(isbn:)
  B Librarian     Leaf/Features/Librarian/{LibrarianModel,LibrarianView,LibrarianShelf}.swift, Shared/Librarian.swift
                  (+ LeafTests/LibrarianTests.swift); CollectionBuilder.moods became internal (visibility only)
  C Widgets       LeafWidgets/{LeafTodayWidget,LeafControls,ReadingLiveActivity}.swift,
                  LiveActivityShared/ReadingActivityViews.swift, LeafWatchWidgets/*
  D Nook scenes   Leaf/DesignSystem/{NookScene,NookShaders,NookAtmosphere}.swift, LeafTests/NookShaderTests.swift,
                  NookSceneSheet, Settings › Reading nook
  E Circles       Leaf/Features/Circle/{CirclesPage,CircleCards,CircleSheets}.swift, Leaf/Services/CircleStore.swift,
                  Shared/Circle/ReadingCircle.swift
  F Polish        Leaf/Features/{Settings,History,Position}/*, Leaf/DesignSystem/ButtonStyles.swift, scripts/ci_screenshots.sh (lt-*)
  G Review        Leaf/DesignSystem/Canopy/{CanopyDisplays,CanopyControls}.swift, Leaf/Features/History/ReadingLogView.swift,
                  Leaf/Features/Library/LibraryReadingShelf.swift, Leaf/Features/Session/SessionAccessory.swift,
                  LiveActivityShared/ReadingActivityViews.swift
  H Watch         LeafWatch/*, LeafWatchWidgets/LeafWatchTimerWidget.swift, Shared/LiveTimer.swift

Screens to eyeball on device (what to test by hand and what to look for):
  - Today, light and dark: the cream reads clean (not yellow), "Begin reading" is the only black button, the
    steep countdown stays sharp while it counts.
  - Session: start from Today and from the bottom bar; one haptic on start, not two. Try each nook scene for 20+
    minutes and note warmth and battery (Rain and Fireplace are the heaviest). Check the fire behind the
    Note / Scene / Ambience buttons doesn't bother you.
  - Fast adding: scan a real paperback (one hit, about a second, camera pauses while it looks up); deny camera and
    reopen (Settings link + typed field); tap + on a result, then Undo.
  - Librarian: mood, time, length; chips wrap at the largest text size; Show me others never repeats.
  - Widgets and controls: add each size and each control. Begin reading / Steep and read open Leaf and start;
    Log pages moves the bookmark without opening the app. Lock Screen lines aren't cut.
  - Live Activity and watch: start a reading session and a steep on the phone and on the watch; the Smart Stack
    shows one card per timer, the steep turns into "Earl Grey is ready" on time, the watch timer keeps running
    with the wrist down. Complications on a real face.
  - Large text (Settings › Accessibility › Larger Text, max): Plan's reading times, the reading log and the
    Library Reading shelf (all changed in this pass), You's chips, Circles shelf names.
  - Reduce Motion and Reduce Transparency: Focus In becomes a crossfade, glass becomes solid cream, scenes hold still.

NEEDS FROM ENGINE:
  0. CI: raise the Screenshots step's timeout-minutes (55 → 80) or split the watch shots into their own step, so a
     full run can go green and include the watch.
  1. ISBNs in the built-in catalog: an `isbn → work id` table in catalog.sqlite (many ISBNs per work), so barcode
     scan and typed ISBNs work offline and instantly. Today they need Open Library.
  2. A "read before Leaf" add: Search › Already read uses `store.add(book, to: .finished)`, which dates the finish
     today and counts it in this year's stats. Needs `addEarlierRead` without a date (or a flag) so it isn't
     counted as finished today.
  3. Circles into LeafData: circles live in circles.json via CircleStore. Move them into LeafData so they're in
     backup/restore and can sync, then iCloud sharing (CKShare) for real members. `CircleMember.remoteID` is ready.
  Nice to have: a `TasteProfile` hook so the Librarian's "Not for me" can record why (too long, wrong mood); a SQLite
  prefilter for `Librarian.matches` if the browse pool grows far past 25k books.

Known issues / skipped:
  - Search's browse rows load after the sheet opens ("Setting out the shelves…"); several CI shots (13, 40, 91)
    catch that spinner. Real use is fine; the staging could wait longer.
  - The legacy ribbon red is still the "now" marker (ruler needle, today's underline, weekday picks, the cover
    ribbon). Kept on purpose from the live app; say if it should become Forest.
  - StatTile / StatTileRow in Your numbers is still the old component (in Oat colours).
  - The screenshot step now runs past its 55-minute limit, so the run goes red and the watch shots (w*) at the end
    are cut. The watch shots were last reviewed on the e5d5fa9 run by the widgets thread.
  - Goodreads / StoryGraph CSV import not built. Open Library page counts are the work's median, not the edition's
    (Where are you? offers the edition picker).
  - No `audio` background mode, so opt-in ambience stops when the screen locks (product call).
  - Engine-side, from agent2-review.md: offline Reset can re-merge old iCloud data once sync is on.

Ideas (value/effort):
  - Library loans with finish odds: high / M (agent2-ideas.md #1)
  - Snap your page (camera reads the page number for Where are you?): high / S–M
  - Bookshop mode ("do I own it, how long would it take me" offline): medium / M
  - Shortcuts that answer (value-returning App Intents): medium / S
  - Read-aloud nights for families: medium / L
  - A Canopy StatTile shared by You, Insights and History: medium / S
  - Goodreads / StoryGraph CSV import: high / M

Anything the owner must do (Xcode settings, capabilities, TestFlight notes):
  - Nothing new for signing, entitlements or capabilities in this batch. The widget extension, controls, Live
    Activity and watch widget extension were already in the project; check they still sign with your team in Xcode.
  - TestFlight "What to test": Canopy (Oat) everywhere, fast adding with barcode scan, Ask the Librarian, nook
    scenes, reading circles (local only, sync is off), widgets and controls, watch timers.
  - Optional: `cancel-in-progress: false` in .github/workflows/ios.yml (PR #1) so screenshot runs finish when
    several sessions push.
=== END ===
```
