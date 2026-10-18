# Leaf: next round (ideas, constraints, handoff)

Notes from the first TestFlight round. **No UI was built for this doc.** Anything tagged **[UI]** is a brief for the
Opus design pass. Anything tagged **[ENG]** is logic or data work that can be built and tested without design (most of
it runs on Linux, see `docs/ENGINEERING.md`). **[PLATFORM]** means a new Xcode target or entitlement.

Read `docs/DESIGN.md` first. This doc extends it; where they disagree, this one is newer.

## 1. Feedback, mapped

| What you said | Why it feels that way today | Direction | Section |
|---|---|---|---|
| Library is too small, picking should be easy | 5,265 bundled books, a search box, and a few shelves | 100k+ books offline, browse-by-mood, swipe deck, ISBN scan, CSV import | 2 |
| "Adjust page" is hidden | It's a small `Update page` text button on book detail | Make "Where are you?" a first-class step whenever a book is started or added | 3 |
| Home isn't useful | One assignment, a week strip, "up next". Nothing to do except start | Make Today a launchpad for the next ten minutes: quick log, forecasts, picks, tea | 4 |
| Love "Still up?" greeting | Only 4 time buckets, no context | A real voice engine: time, season, weather, streak, book state, tea | 5 |
| Cozy books and tea niche | Palette is cozy, features aren't | Tea ritual, cups as a unit, tea-ring stamps, ambience, nook scenes | 6 |
| Likes Gaussian blur | Used nowhere except system glass | A blur design language: focus pulls, blurred covers, bokeh, rain | 7 |
| Bookmark is cool but rigid | It's a static shape with one keyframe sway | A physical ribbon: verlet chain, tilt, drag, the bookmark *is* the progress control | 8 |
| Loves the sliders and blurred numbers | Only the minutes dial and page scrubber use them | Scrub-anything numbers with motion blur and detents | 9 |
| Planning page could be awesome | Deterministic dates only | A forecast engine: pace model, adherence model, Monte Carlo ranges, what-ifs | 10 |
| Live Activity with the countdown effect | Doesn't exist | Lock Screen and Dynamic Island, plus widgets and a Control Center button | 11 |
| Watch app is boring and useless | A timer, a ring, a list | Focus-pull timer, tea timer, double-tap, complications, quick log, more | 12 |
| Needs enough features for daily use | | A feature pool to choose from | 13 |

---

## 2. Book library: bigger, and pick instead of type

### 2.1 Where we are
`Leaf/Resources/books.json` has 5,265 books, built by `scripts/build_catalog.py` from the Open Library search API.
The loader (`BookCatalog.load()`) decodes the entire file into `[Book]` plus a search index in memory. That is fine at
5k and **wrong at 100k** (tens of MB of heap, slow launch). The catalog format has to change with the size.

### 2.2 Size math [ENG]
About 145 bytes per book as compact JSON. Estimates for the bundled data:

| Books | Raw size | Notes |
|---|---|---|
| 5k (today) | 0.76 MB | |
| 100k | ~15 MB | Popular books, any language we choose to include |
| 250k | ~36 MB | Close to "everything people actually read" |
| 1M+ | ~145 MB | No. Use live search for the tail |

Covers stay remote by Open Library **cover ID**, which is not rate-limited (lookups by ISBN or OLID are). Add a disk
`URLCache` and always request `-M` (medium) thumbnails.

### 2.3 Two ways to build it [ENG]
**A. Sharded search crawl.** Extend `build_catalog.py`: query by subject × decade × sort (`readinglog`, `want_to_read`,
`rating`), `limit=100`, filter `number_of_pages_median:[40 TO 2500]`. About 1 request per second, so 60k to 120k books in
one to two hours. Simple. Popularity comes straight from the API.

**B. Bulk dumps on a CI runner.** `ol_dump_works` is 4.1 GB gz, `ol_dump_editions` is 12.6 GB gz, `ratings` is 9 MB,
`reading-log` is 123 MB. Stream them (`curl | zcat | python`) in a GitHub Actions job. Edition records give page counts
(take the median per work); reading-log counts give popularity. Best coverage and the most accurate page counts, but a
one-off job that takes an hour or two. Check Open Library's current terms on their dumps page before shipping.

**Decision: ~250k+ books, so build path B.** A crawl alone can't reach that cleanly (search paging depth limits, heavy
duplication), so use the dump pipeline on a GitHub Actions runner and commit the generated database. Use path A only
to seed a quick first cut so the loader and search can be built and tested before the full build finishes.

Quality rules (extend the existing ones): one entry per work, drop study guides, summaries, box sets and omnibuses,
require an author and a page count, keep the language field (English by default, others behind a setting), and add
`pageCountSources` (how many editions agree) so the UI can say "page counts vary by edition."

### 2.4 Storage and search [ENG]
- Ship a **read-only SQLite database** with an FTS5 prefix index, built at catalog-build time. Open it with the
  system `sqlite3` C API (no packages). Never decode the whole table into Swift.
- Target search latency under 30 ms at 250k rows, results ranked by popularity plus match quality.
- Keep `BookCatalog`'s public API (`search`, `collections`, `book(id:)`) so the UI doesn't churn.
- Curated collections become SQL queries over genre, length-at-your-pace and year (see 2.5). Keep them cheap.

### 2.5 Picking UX [UI]
- **Browse the shelves:** mood rows ("Rainy-day reads", "Cozy mysteries", "Short enough for a weekend", "Under four
  hours at your pace"), plus awards and decade lists, generated from catalog data.
- **Swipe deck:** a card stack of covers. Swipe right to add to To read, left to pass, up to start now. Haptic tick on
  every card, a heavier one on a keeper. This is the fastest way to build a TBR and a great onboarding step.
- **One-tap add** on every cover anywhere in the app, long-press for the menu (Start, Next up, End of queue).
- **More like this:** from subject overlap on a book's detail page.
- **Series awareness:** "Next in the series" after finishing a book (see 13).
- **ISBN barcode scan** (VisionKit `DataScannerViewController`) for physical books, then Open Library lookup by ISBN.
- **Import** Goodreads and StoryGraph CSV exports: titles, authors, ISBNs, pages, shelves, dates read.
- **Edition picker:** on detail, "Your copy has 310 pages. Others: 330, 366." Progress is page-based, so this matters.

---

## 3. "Where are you?": a prominent starting position

**Principle:** progress is the app's whole model. Starting wrong makes every forecast wrong.

### Flows [UI]
- Starting a book with 0 progress (from Today, Library, detail, Search quick-add): show a **"Where are you?"** sheet
  *before* the session begins. Options: **Just starting**, **I'm on page __**, **I'm __% in** (e-readers), **I've
  already read it** (goes to Finished, asks for a date).
- Adding from the swipe deck or onboarding: ask later, not per card, but flag unset books and ask on first start.
- Today's hero shows the page as a tappable chip (`p. 142 ✎`), not a text link on another screen.
- Reuse `PageScrubber` as the main control with the big haptic numerals, large and centered.

### The bookmark is the progress control [UI]
Drag the ribbon down the side of a stylized page block to set where you are. The ribbon's depth *is* your page, and
the page block shows thickness for long books. It fits the brand, answers the "bookmark feels rigid" feedback (section
8), and turns a chore into a small delight. Keep an accessible numeric alternative (the scrubber and a text field).

### Data [ENG]
- Add `ProgressMode` (`pages`, `percent`) to `LibraryItem`. Store position as pages always, derive from percent using
  `book.pages`. Add `startPage` (where the reader began) so the first session's speed isn't computed from page 0.
- `PlanInput` already starts from `currentPage`, so nothing else changes.

---

## 4. Home (Today)

### Diagnosis
Today answers "what's my assignment?" and then stops. It has one action (Start). There's no way to log reading
without a timer, no hint of how the plan is doing, no suggestion when you're between books, and it looks the same on
every day.

### Purpose
**Today is the launchpad for the next ten minutes of reading.** Everything above the fold answers: what should I
read, how do I begin right now (with tea), and how am I doing.

### Three concepts [UI]
- **A. The Reading Nook.** One atmospheric scene: lamp glow, a teacup that fills as you read, the book on a table,
  greeting in big serif. A single "Steep and read" button. Calm, emotional, less dense.
- **B. The Daily Brew.** A stack of purposeful cards: Now, Left off, Forecast insight, Tonight's pick, Shelf strip,
  Week, Nudge. Dense and useful.
- **C. The Desk.** A top-down flat-lay of the book, bookmark, teacup and notebook. Playful and tactile, hardest to do
  well.

**Recommendation: A's header over B's cards.** The nook is the first screen of the app (atmosphere, greeting, one big
button, tea), and the cards sit under it for people who want detail.

### Modules, ranked by usefulness [UI]
1. **Greeting + tea pick** (section 5, 6). One line, plus a chip like "Earl Grey, 4 min".
2. **Start button that does the right thing:** "Steep and read" starts a tea-timed session; long-press for options
   (book, duration, ambience).
3. **Left off:** cover, `p. 142 ✎` (tap to adjust), "13 min to stay on plan".
4. **Quick log:** "Read without the timer": a scrub-number for pages plus minutes. Works for people who forgot to
   start the timer.
5. **Forecast insight of the day** (from section 10): "At this pace you'll finish *The Hobbit* Sunday. Six more
   minutes tonight makes it Saturday."
6. **Cup progress:** today's goal as a filling teacup, steam when done (alternative to the ring).
7. **Between-books mode:** if nothing is in Reading, show a swipe deck or "Tonight's pick" instead of an empty state.
8. **Week and streak:** keep, but as tea-ring stamps (section 6).
9. **Year goal pacing:** "On track for 24 books (18 to 29)."
10. **Recommendation:** "Because you finished *Klara and the Sun*".
11. **Gentle nudges:** stalled book, paused-book shelf, "borrowed from Sam, due back soon" if lending exists.

States to design for: morning, evening, late night, rest day, goal met, nothing in Reading, brand new user, returning
after two weeks, finishing a book tonight, travelling.

---

## 5. The voice: a greeting engine

"Still up?" works because it sounds like a person who noticed. Make that the app's personality everywhere, not one line.

### Engine [ENG]
`GreetingEngine.line(for: GreetingContext) -> Greeting` where `Greeting` has a headline and an optional subline. Pure
and deterministic: the context plus a daily seed picks the line, so it doesn't flicker on re-render. Testable on Linux.

Context inputs: daypart (dawn, morning, lunch, afternoon, tea-time, dusk, evening, late, small hours), weekday, season,
holiday, moon phase (optional), weather (optional), streak length, days since last session, book state (just started,
halfway, near finish, stalled), goal state (not started, met), rest day, first launch of the day, first-ever launch.

### Tone rules
- Short (about nine words), specific, warm, never guilt. No exclamation marks. No streak threats.
- Tea and cozy words are seasoning: at most about one line in three, so it never gets cloying.
- Always leaves a door open: the line should make starting feel easy.

### Sample lines (to grow to 300+)
| Moment | Lines |
|---|---|
| 5 to 8 | "Early bird. The kettle's barely warm." / "Quiet house. Good light." |
| 8 to 11 | "Morning. Ten minutes before the day begins?" |
| Lunch | "Lunch with a chapter." |
| 4pm | "Tea o'clock." / "The afternoon is better with a book in it." |
| Dusk | "The lamp's calling." |
| Evening | "Good evening. Kettle on?" / "Dinner's done. You've earned a chapter." |
| 11pm to 2 | "Still up? One more page, then bed." |
| 2 to 5 | "The whole house is asleep. Except you and the book." |
| Rain | "Rain on the window. Perfect." |
| Cold | "Blanket weather." |
| Autumn | "Leaves are turning. So are your pages." |
| Sunday | "Slow Sunday. No rush." |
| Streak 7+ | "Seven evenings in a row. The tea tastes better." |
| Back after a gap | "Welcome back. Your bookmark's right where you left it." |
| Near the end | "Eleven pages from the end of *The Hobbit*. The kettle can wait." |
| Goal met | "Today's pages are done. Anything more is a gift." |
| Rest day | "Day off. The book will keep." |
| First ever | "Welcome to your nook." |

### Reuse it everywhere
The same engine writes notification copy (varied, instead of one template), Live Activity lines, the watch Today
page, widgets, the end-of-session wrap-up, and the weekly letter (13).

### Optional on-device AI [ENG, needs a decision]
iOS 26's `FoundationModels` framework (`LanguageModelSession`, guided generation) can write fresh lines privately on
device. It only runs on Apple Intelligence devices that have it enabled, so it is **opt-in sugar over the template
engine**: check `SystemLanguageModel.default.availability`, constrain output (one sentence, banned words, no
exclamation marks), cache per daypart, and fall back to templates on any failure.

---

## 6. Cozy: books and tea

The brand promise is "a warm corner, a pot of tea, a good book." Today the palette says it and the features don't.

**Vocabulary.** nook, kettle, pot, cup, steep, lamp, bookmark, shelf. Use it in copy, not in the navigation.

**Ideas**
- **Tea ritual.** Pick a tea, get a steep time (green about 2:00, black 3 to 5, oolong 3 to 5, herbal 5 to 7). A
  session can begin *as* the steep ("tea's ready, now read"), or run a cup-length read (about 25 min) followed by a
  stretch break. Tapping the greeting suggests a tea for the hour. A kettle-click and pour sound plus a haptic. [UI + ENG]
- **Cups as a friendly unit.** 1 cup = 25 minutes, 1 pot = 4 cups. "You've read 112 cups this year." Real minutes are
  always one tap away. [ENG]
- **Tea-ring stamps.** Each read day leaves a faint tea-ring on the paper, sized by minutes. The week strip and the
  year heatmap become a table covered in rings. A finished book gets a bigger ring with a date. [UI]
- **Ambience.** Rain, fireplace, kettle, cafe murmur, library hush. Generate or use CC0 loops; keep `.ambient` audio
  with `mixWithOthers` so the reader's own music still works. Procedural noise (AVAudioEngine) for rain and fire
  avoids licensing and keeps the app small. [ENG]
- **Nook scenes.** Selectable atmospheres for the session and Today header (rainy window, lamplit desk, morning
  window, fireplace), built from blur and gradients, not photos (section 7). [UI]
- **Palette additions.** Tea-stained paper, chai, matcha, rooibos, steam-white, lamp amber. Keep ink and the single
  green accent; use warm tints for atmosphere only.
- **Seasonal sets.** Autumn leaves, winter hearth, spring rain, summer porch: small changes to the nook scene and
  greeting pool.
- **Reading Focus.** A Focus filter and an auto-"Reading" Focus during sessions (13).

---

## 7. A Gaussian blur design language [UI]

Blur is how this app should create depth and calm. Rule: **crisp for what you act on, soft for what you feel.**

- **Focus pulls.** Transitions rack focus: the outgoing screen blurs as it recedes while the incoming one sharpens
  (blur radius ~14 to 0 with opacity). Use for Today to detail, session start and end, tab changes. Also for the
  numbers (section 9).
- **Blurred cover backdrops.** The current book's cover, heavily blurred (radius 40+), becomes the atmosphere behind
  Today, book detail, the session, widgets and the Live Activity. Extract two or three dominant colors for a
  `MeshGradient` instead of blurring the raw image where legibility is at risk.
- **Bokeh.** A few large, slowly drifting blurred circles (candlelight, fairy lights) behind the session screen.
  `Canvas` in a `TimelineView` at about 15 fps.
- **Rain on glass.** Layered blurred streaks with a refractive pass (Metal `layerEffect` shader, iOS 17+). The
  signature nook scene.
- **Steam.** Soft vertical wisps (blurred, low opacity) rising from the cup; slower when you pause.
- **Per-digit blur.** `TextRenderer` (iOS 18+) gives per-glyph effects, so a countdown digit can blur in and out as it
  changes. `.contentTransition(.numericText())` plus `.blur` is the cheap version.
- **Motion blur by velocity.** While scrubbing a dial, blur radius rises with finger speed (clamped to about 6 pt) so
  fast flicks smear and slow ones are crisp.

**Rules and costs**
- Blur cost scales with radius and area. Blur **pre-rendered bitmaps** when static (covers); animate only small areas.
- Honor Reduce Transparency and Reduce Motion: replace blur with flat tints, stop drifting.
- Keep text on blur legible with a scrim or material; check contrast in light and dark.
- Pause drifting scenes in Low Power Mode and when the app isn't active; the session screen stays awake, so keep it
  cheap.

---

## 8. Motion: the ribbon and friends [UI, with ENG for the physics]

### Why the ribbon feels rigid
`RibbonTail` in `Leaf/DesignSystem/BookCover.swift` is a fixed shape and `ribbonSway` in `Motion.swift` is one keyframe
rotation on appear. Real ribbon is cloth.

### Physical ribbon
- Model it as a **verlet chain** of 6 to 8 points anchored at the top, with distance constraints and damping.
- Forces: gravity, **device tilt** (`CMMotionManager` gravity at about 30 Hz), scroll velocity, tap impulses, and a
  faint idle breathing from smooth noise.
- Render with `Canvas`: a Catmull-Rom curve through the points, tapered width, a swallowtail that follows the last
  segment, a satin highlight that slides with curvature and tilt, and a soft shadow on the cover.
- Interactions: **drag it** (rubber band, with a Core Haptics continuous event whose intensity follows the stretch),
  flick on release, flutter on a page turn, tuck away when a book is finished.
- **Sleep when settled:** stop the simulation when speed falls below a threshold so it costs nothing at rest.
  Reduce Motion gets a fixed gentle curve.
- Put the simulation in `Shared/`-style pure code (`RibbonSimulation`) so it can be unit-tested on Linux, and let the
  view only draw.

### Other animation upgrades
- **Book opens:** a hardcover hinge (rotation3D around the spine) when a cover zooms into detail.
- **Parallax tilt** on covers using device motion.
- **Ink-drying** checkmarks, a **tea-pour** fill for goal progress, **page-turn** flutters on finishing a page entry.
- Replace one-off springs with a small set of interruptible, velocity-aware springs; stagger lists consistently.
- Add a signature **settle** (tiny overshoot, then still) to every committed action so confirmation feels physical.

---

## 9. Sliders and numbers: scrub anything [UI]

`TickRuler`, `MinutesDial` and `PageScrubber` are the best interactions in the app. Generalize them.

- **Scrub-numbers anywhere.** Press and drag on any number (daily minutes, goal, pages, "finish by" date) to change it,
  with detent haptics and the blurred-digit transition. A text field stays as the accessible fallback.
- **Rolling drum** for times (reminder hour and minute) with the same haptics.
- **Velocity-aware feedback:** faster scrubs get a lighter, denser haptic pattern and more motion blur; slow ones get
  crisp detents. Major ticks get a heavier tap.
- **Magnetic stops** at meaningful values: your daily goal, a finish date that changes the book count, round hours.
- **Live consequences:** while scrubbing minutes, the forecast beneath updates continuously with blurred numbers
  ("Finish Nov 3 -> Oct 29").
- **Date scrubbing** for "finish by": drag a timeline, see the required minutes per day.
- Use the same control for the tea steep time, the session goal, the watch crown (section 12), and the what-if
  sliders in the forecast (section 10).

---

## 10. Plan becomes Forecast

Today the planner is deterministic: pace times words, spread over days. A real reader's life is noisy. Model that
noise honestly and the Plan screen becomes the reason to open the app.

### Models [ENG, all on-device, all testable on Linux]
1. **Personal pace model.** Per-session speed = pages x words-per-page / minutes. Use hierarchical shrinkage: global
   pace, then by genre, then by book, each pulled toward its parent with a prior weight of about 5 sessions. Add
   effects for session length (warm-up in the first ~10 min, fatigue after ~45) and time of day. After 3 sessions on a
   book, apply a per-book correction (clamped to 0.7 to 1.4) so slow books update their own finish dates.
2. **Adherence model.** Probability of reading on each weekday as a Beta posterior over the last 8 weeks, seeded by the
   reading days you chose. Minutes on days you read: a log-normal fit.
3. **Monte Carlo.** About 2,000 simulated futures with a deterministic seed (so results don't jitter), run off the main
   actor and cached. Outputs: per-book finish date as **median plus 10th/90th percentile**, "chance to finish by
   Friday", and year-end book count as a range.
4. **Backtesting.** Replay the user's own history to score the model ("Your 80% ranges have been right 78% of the
   time"). Use the same harness in unit tests with synthetic reader personas to check the intervals are calibrated.
5. **Inverse planning.** Given a target date or a book count, solve for the minutes per day needed.
6. **Smart ordering.** Suggest a TBR order that finishes the most books by a date (shortest first), alternates genres,
   or inserts a short "palate cleanser" after a heavy read. Show it as a preview with the same delta chips.
7. **Elastic catch-up.** When you miss days: **shift** the plan, **compress** to catch up, or **forgive** (default,
   no guilt).
8. **Stall detection.** A book with no progress for about 14 days gets a gentle "set aside?" and moves to a **Paused**
   shelf (adds `Shelf.paused`, `ProgressMode`-style data work).

### Screens and ideas [UI]
- **Fan chart** per book (median line, shaded 10 to 90 band) and for the year goal. Tap a date to see odds.
- **What-if sliders** (minutes per day, reading days) using the scrub-numbers (section 9). Dates reflow with blurred
  digits and delta chips (already in the spec).
- **Finish line mode:** pick a book club date or a "finish by Christmas" and see what it takes.
- **Reading heatmap** as tea-ring stamps across the year; **best time of day** (when you're fastest and most
  consistent); **speed trend**; **genre and length mix**; **TBR depth** ("Your TBR is 14 months deep at this pace").
- **Reading personality**: a fun, shareable archetype ("The Evening Steeper", "The Weekend Binger") derived from the
  stats.
- **Year in books**: a cozy wrapped (pages, cups, longest streak, favorite hour, a "tea ring" collage) as a
  shareable image. **Weekly letter**: a Sunday-evening local notification and a short recap.
- Always show real numbers beside any cute unit.

---

## 11. Live Activity, widgets, Control Center [PLATFORM + UI]

### Live Activity (ActivityKit)
- **Lock Screen:** blurred cover backdrop, title, the **countdown** to goal (or time read), a bar showing progress,
  pause/resume and "log page" buttons (interactive via `LiveActivityIntent`).
- **Dynamic Island:** compact (cup or ring + time), expanded (cover, title, time, buttons), minimal (ring).
- **StandBy:** Live Activities appear there; design the Lock Screen layout so it scales to the big landscape view.
- **States:** reading, paused, goal reached ("Goal met. Anything more is a gift."), finishing a book.

### What the countdown effect can and can't be
- Widgets and Live Activities **cannot run per-second custom animations.** The system updates `Text(timerInterval:)`
  and `ProgressView(timerInterval:)` for you. That is the only way to get a live second-by-second timer without
  burning the update budget.
- So the blurred, focus-pull effect has to come from **state-driven changes** (pause, resume, goal reached, page
  logged) using `.contentTransition` and blur transitions, plus a **pre-rendered blurred cover** as the background.
  Verify on a real device how digits animate; a smooth circular countdown ring is not directly supported, so use the
  timer-driven bar or a state-driven ring.
- Keep `ContentState` tiny (it is size-limited); put images in the app-group container and reference them by name.

### Constraints that shape the design
- A Live Activity can be active for up to **8 hours**, and may stay on the Lock Screen for a further ~4 hours after it
  ends. Long reading sessions need an end/restart plan.
- You can only **start** one while the app is in the foreground (or via push-to-start, which needs a server). So a
  session started on the **watch** cannot start a phone Live Activity without the phone app being open. Phone-started
  sessions work and are **mirrored on the Apple Watch Smart Stack**. Updating or ending can happen in the background.

### Widgets and Controls (WidgetKit)
- **Home Screen:** small (today's goal as a cup or ring over a blurred cover), medium (week strip + current book), large
  (next three books with forecast dates).
- **Lock Screen:** circular ring, rectangular "13 min . p. 143", inline "13 min . The Hobbit".
- **Interactive:** a Start/Stop button and "+10 pages" via App Intents.
- **Control Center / Lock Screen controls** (iOS 18 `ControlWidget`): "Start reading". Action Button support for free.
- Widgets read a small shared snapshot from an **App Group** file written by the app (and the watch bridge).

---

## 12. Apple Watch overhaul [UI + ENG]

The watch is the best device for reading time: it is on your wrist while your hands hold a book and a cup.

### The timer
- **Focus-pull countdown:** big serif digits that sharpen as each minute lands and soften between, with a faint
  steam/bokeh backdrop. Per-glyph blur via `TextRenderer` where available.
- **Tea timer** built in: pick a tea, steep, then it hands off to the reading timer. Soft haptic when ready.
- **Double Tap** (Series 9 / Ultra 2 and later) mapped to pause/resume with `handGestureShortcut(.primaryAction)`:
  one-handed control while holding tea.
- **Always-On:** a dimmed, minutes-only variant (`isLuminanceReduced`).
- **Wrist-down runtime:** a `WKExtendedRuntimeSession` so the session keeps running and can tap you at the goal. Use a
  mindfulness or self-care session type; verify which one App Review accepts for reading.

### Pages
1. **Today (nook):** the greeting line, a cup or ring, "Steep and read".
2. **Quick log:** crown to set pages, tap to save, no timer needed.
3. **Where was I?** the book, the page, and a one-tap "adjust".
4. **Forecast:** this book's finish range and the year-goal pacing.
5. **Week:** tea-ring stamps and the streak.
6. **Shelf:** Reading and the first few of To read; mark finished; swap the active book.
7. **Quick add:** dictate a title, resolve against the catalog (or via the phone).
8. **Journal:** dictate a thought or quote and attach it to the current book.

### Platform features
- **Complications and Smart Stack:** accessory circular/corner ring, rectangular "13 min . p. 143", and a relevant widget
  around your usual reading time (RelevanceKit on watchOS 26).
- **Actionable notifications:** Start, Snooze 30 min, Skip today.
- **Pace taps** (optional): a soft tap every estimated page, so you know you're moving without looking.
- **Sleep timer:** reading in bed ends the session and dims the display on a countdown.
- **Mindful minutes** (opt-in HealthKit): log reading as a mindful session. This changes the privacy answers and
  review notes; keep it off by default.

---

## 13. Feature pool (chosen options are recorded in section 16)

| Feature | Idea | Effort | Daily-use pull |
|---|---|---|---|
| Tea ritual + ambience | Steep timer tied to sessions, ambient loops, nook scenes | M | High |
| Reading journal + quotes | Notes per session and book; scan a quote with the camera (VisionKit Live Text); shareable quote cards | M | High |
| Cozy challenges | Seasonal readathons, yearly goal, collectible stamps, cups | M | Medium |
| Audiobook + e-book formats | Track listening time and % progress with separate pace models | M | High for listeners |
| Forecast + stats | Monte Carlo ranges, year in books, heatmap, best-time insights | L | High |
| Fast book adding | ISBN scan, Goodreads/StoryGraph import, series and next-up | M | High at the start |
| On-device AI librarian | Greetings, "something like X" picks, journal summaries (Apple Intelligence devices) | M | Medium |
| iCloud sync + backup | Private CloudKit, no account; survives deleting the app; syncs iPhone and iPad | M | **Essential** for trust |
| Live Activity + Dynamic Island | Section 11 | M | High |
| Widgets + Control Center | Section 11 | M | High |
| Watch overhaul | Section 12 | L | High |
| Siri, Shortcuts, Focus | "Start reading", auto Reading Focus, automations ("when I get home") | S-M | Medium |
| Paused/DNF shelf, lending, tags | Park a book without guilt, "lent to Jess", custom tags | S | Medium |
| Series tracking | Next-up and reading order | M | Medium (data is patchy) |
| Libby / library deep links | "Borrow" button opens Libby search | S | Medium |
| Book club mode | Shared book and deadline with progress (CloudKit sharing, no accounts) | L | Stretch |

---

## 14. Constraints and gotchas

- **No accounts, on-device only** stays the promise. Weather needs location and WeatherKit; offer it as an optional
  upgrade, and make the engine good with no permissions (time, season, moon, streak). HealthKit and any analytics would
  change the App Privacy answers.
- **Foundation Models** only on Apple Intelligence devices that have it turned on. Never make a core flow depend on it.
- **Live Activity limits** (section 11): 8 hours, foreground start, tiny state, no custom per-second animation.
- **Catalog scale:** do not decode the whole database into Swift (section 2.4).
- **Performance and battery:** blur and drifting scenes cost power. Respect Reduce Motion, Reduce Transparency and
  Low Power Mode. The session screen stays awake, so keep it cheap.
- **Build/CI:** everything in `Shared/` and any new `Forecast/` logic compiles on Linux and is tested there; UI is
  verified from the CI screenshots. Widget and Live Activity extensions are new Xcode targets in `project.pbxproj`
  (edited by hand; check the packaging step in `.github/workflows/ios.yml` after adding them). TestFlight must be built
  with a **release** Xcode (26.6), not a beta.
- **Accessibility:** every animated or scrubbed control needs a non-gesture alternative; Dynamic Type must not clip the
  big numerals; VoiceOver should read forecasts as sentences ("probably done Sunday, between Saturday and Tuesday").

---

## 15. Suggested order and who does what

Dependencies drive the order: **iCloud sync touches every model, so it goes first**, and the catalog is the biggest
independent job.

| Step | Work | Who |
|---|---|---|
| 1 | **Sync-ready data model:** `updatedAt` on items and preferences, tombstones for deletes, session IDs already unique; migrate the JSON file | **[ENG]** any model |
| 2 | **Catalog:** dump pipeline on Actions, SQLite + FTS5 database (~250k), new loader, search tests | **[ENG]** any model |
| 3 | **Forecast engine:** pace, adherence, Monte Carlo, backtest, inverse planning, smart order | **[ENG]** any model |
| 4 | **Voice + tea:** greeting engine (templates first), tea data, cups, AI wrapper behind availability checks | **[ENG]** any model |
| 5 | **iCloud sync:** CloudKit container, `CKSyncEngine`, merge rules, conflict tests, status in Settings | **[PLATFORM + ENG]** any model |
| 6 | **App Intents:** Start/Pause/Log intents, shortcuts provider, Focus filter; **widget extension target** + App Group + shared snapshot for the Live Activity (no visuals) | **[PLATFORM]** any model |
| 7 | **Ribbon simulation** (pure physics), `ProgressMode`, `startPage`, `Shelf.paused`, journal and quote data model | **[ENG]** any model |
| 8 | **UI pass:** Today (nook + brew cards), "Where are you?", ribbon drawing and drag, blur language, nook scenes, tea ritual, journal and quote cards, challenges, Plan -> Forecast, Search browsing and swipe deck, scrub-numbers | **[UI]** Opus |
| 9 | **Live Activity + Dynamic Island visuals**, **watch overhaul visuals**, per-glyph blur | **[UI]** Opus |

Steps 1 to 7 need no design decisions and can start now.

---

## 16. Decisions

Chosen after the first round of feedback.

**Build**
- **Rituals:** tea ritual + ambience; reading journal + quotes; cozy challenges.
- **Smart:** forecast + stats engine; on-device AI librarian; iCloud sync + backup.
- **Platform:** Live Activity + Dynamic Island; Apple Watch overhaul; Siri, Shortcuts + Focus.
- **Library:** ~250k+ books bundled (section 2, path B).

**Parked** (kept in section 13 so they're easy to pull in later)
- Audiobook + e-book formats (note: `ProgressMode.percent` from section 3 still ships, so e-reader users can start
  from a percentage).
- Fast book adding: ISBN scan, Goodreads/StoryGraph import, series tracking.
- Home/Lock Screen widgets and the Control Center button. The Live Activity and its shared App Group and extension
  target are in scope, so widgets are cheap to add on the same target.
- Book club mode, Libby links, lending and tags.

**Still in the UI brief even though the add-books features are parked:** browse-by-mood rows, the swipe deck, one-tap
add, "more like this", the edition picker and the whole "Where are you?" flow (sections 2.5 and 3). You asked for picking
to be much easier, and these are design work rather than extra data features.

**Technical notes for the chosen work**
- **iCloud sync:** private CloudKit database, no account (it uses the device's iCloud). Use `CKSyncEngine` (iOS 17+).
  Sessions are append-only and have unique IDs, so they merge without conflicts. Library items and preferences use
  last-writer-wins on `updatedAt`. Deleted items need tombstones. **Never sync** the live `ActiveSession` (it is
  device-local and the watch bridge already handles it). Needs the iCloud capability and a container such as
  `iCloud.com.norvodesigns.leaf` in the entitlements; the hand-edited project file and the unsigned CI archive both need
  checking afterwards.
- **On-device AI:** `FoundationModels` behind `SystemLanguageModel.default.availability`; every use has a written
  fallback. Used for greetings, "something like X" picks (the model proposes themes, the **catalog supplies the actual
  books** so nothing is invented) and journal summaries.
- **Siri, Shortcuts, Focus:** App Intents (`StartReadingIntent`, `PauseReadingIntent`, `LogPagesIntent`), an
  `AppShortcutsProvider` with natural phrases, and a `SetFocusFilterIntent` so a "Reading" Focus can silence
  notifications. The same intents power the Live Activity buttons, so they must be shared with the extension target.
- **Live Activity:** add `NSSupportsLiveActivities`, a widget extension target and an App Group
  (`group.com.norvodesigns.leaf`) for the shared snapshot and pre-rendered blurred cover. See section 11 for what the
  countdown effect can and can't do.
- **Journal and quotes:** quotes can come from the camera (VisionKit Live Text). Store text only; keep the photo out
  unless the reader chooses to save it. Synced through the same CloudKit path.
- **Privacy:** still "Data Not Collected" as long as everything stays on device or in the reader's own iCloud, and
  weather and HealthKit stay off.
