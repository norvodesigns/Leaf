# Leaf redesign: Phase 1

Chief of Design, 2026-10-21. Status: **revision 2 approved with the Oat palette (2026-10-22); Phase 2 under way**. Revision 2 (2026-10-22) follows the
owner's note that the green was too heavy and the cream not prominent: it evolves the live look instead of replacing
it, and offers three cream palettes to choose from (Linen, Oat, Ivory).

The engines stay. The UI starts over on a new system, **Canopy** (`docs/design/DESIGN_SYSTEM.md`,
`Leaf/DesignSystem/Canopy/`). This doc covers what the app is, where things live, every screen, the haptics map,
and the icon. Rendered mock-ups of Today and Plan built from the real tokens are in the gallery
(`-LeafScreen gallery.canopy.today`, `gallery.canopy.plan`), and show up in CI screenshots as `C0`–`C3`.

## 0. What Leaf is, in one line

> **Leaf tells you what to read, when, and gets you reading in one tap.**

Everything on the surface serves that line. Everything else (forecasts, insights, tea lore, challenges, circles,
journal) is depth, one level down.

## 1. Information architecture

Four tabs. The system tab bar is Liquid Glass and minimises on scroll; the live session docks above it as the
system bottom accessory.

| Tab | Question it answers | What lives there | Accent |
|---|---|---|---|
| **Today** `sun.max` | What do I read now? | Next reading time (Hero), today's plan (2–3 slot rows), goal ring, tea suggestion, "Log pages" | Forest (Dusk for times) |
| **Plan** `calendar` | When do I read what? | The day timeline of reading times, each with its book; week strip; Up next queue; finish dates | Forest (Dusk for times) |
| **Library** `books.vertical` | What am I reading, and what next? | Reading, Up next, Finished shelves; search and Discover (add a book) in the same tab | Forest |
| **You** `person.crop.circle` | How is it going, and how do I like it? | Streak and week, Insights, History and journal, Challenges, Tea cabinet and tea preferences, Settings | Bloom |

Why this split: today's three old tabs plus search mixed "now", "later" and "stats" on every screen. Now each tab
has one question. Search is not a tab: you search when you want to add a book, so it lives in Library (pull-down
search field plus a glass `+`). Tea is not a tab: it is part of reading (Today's tea row, the session ritual), and
its setup (cabinet, preferences) sits in You.

### The three daily jobs

| Job | Path | Taps |
|---|---|---|
| **Start reading** | Today → **Begin reading** (Hero, the next slot's book) | 1 |
| | or the session accessory, the widget, the Live Activity, the watch | 1 |
| | with tea: Today → **Steep and read** | 1 |
| **See today's plan** | Open the app: Today shows the day's reading times with books and pages | 0 |
| | change it: tap a slot → Plan with that slot open | 1 |
| **Log / finish** | In a session: **Done** → page dial (pre-set to the expected page) → **Save** | 2 |
| | Without the timer: Today → **Log pages** on the book → **Save** | 2 |
| | Finishing: the page dial's last stop is **Finished**, which plays the finish moment | 2 |

## 2. Progressive disclosure

| Level | Rule | Contents |
|---|---|---|
| **0 · Surface** | Answers "what now?" in one glance. No charts, no lists longer than 3 | Today: Hero, today's slots, goal ring, tea row. Plan: today's timeline. Library: the Reading shelf. You: streak + this week |
| **1 · One tap** | Answers "how is it going?" | Book detail (progress, finish date sentence, next session), Plan's week and Up next, the full shelves, Insights summary, Tea cabinet, Settings list |
| **2 · Depth** | The rich engines, for the curious | Forecast detail and what-ifs, insights depth (heatmap, timing, personality), Year in books and Wrapped, challenges and stamps, journal and quote cards, history and read-throughs, tea history and tasting notes, circles, the librarian, ambience, speed test |

Rule of thumb for Phase 2: if a level-2 engine has a great one-line result (the forecast's finish sentence, a streak),
that *sentence* may appear at level 0 or 1; its chart may not.

## 3. Brand

**Minimal, clean, cozy, and still Leaf.** Built from the live app: its masthead, Instrument Serif greeting, cover and
cup, and the Steep / Begin pair stay. What changes: a brighter, cleaner cream page with the amber wash and bokeh gone;
green used as ink (labels, links, progress, toggles), never as big fills; black for the one hero button; glass cards
tinted cream; Dusk, Clay and Bloom used small for reading time, tea and memories. Three palettes are on offer: Linen
(recommended), Oat, Ivory. Full spec in `DESIGN_SYSTEM.md`.

## 4. Screens

Sketches show light mode; dark mode swaps tokens only. `[▓ … ▓]` is the black Hero, `( … )` is glass,
`╭─╮` is a glass card.

### 4.1 Today

Evolved from the live Today: same masthead, greeting, cover and cup, and the Steep / Begin pair; cleaner cream, no
amber bokeh, and today's reading times added right under the actions.

```
 THURSDAY, OCTOBER 22                  NO. 42  ← eyebrow, kept
 ─────────────────────────────────────────────
 Evening hush.                                 ← Instrument Serif, kept
 The lamp and the book do the talking.         ← italic subline, kept

 ┌────────┐   ╭─╮
 │ cover  │   ╰─╯  12 of 25 min                ← cover + cup, kept; green progress line
 └────────┘        ━━━━━━─────
 ( ☕ Bedtime blend · 7 min steep )             ← glass chip, Clay icon
 ( ☕ Steep and read )  [▓ Begin reading ▓]     ← glass + black glass Hero
 ╭───────────────────────────────────────────╮
 │ Today's reading times            Edit ›   │ ← green label
 │ (7:30) ┌┐ ✓ Project Hail Mary    (⇄)      │
 │ (8:30) ┌┐ ● The Hobbit  pp.143–154 (⇄)    │ ← tap time or ⇄ to change
 ╰───────────────────────────────────────────╯
 ╭ 🍃 A short book would bring the year goal back within reach. Find a short book ╮
```

States (one hero always): **reading** (above); **goal met** (Hero becomes "Keep reading", ring full, a single Forest
line "Goal met. Anything more is a bonus."); **rest day** (Hero "Read anyway" is replaced by a glass "Read a little"
and no Hero, so it never pushes); **between books** (Hero "Pick your next book" opens the swipe deck); **brand new**
(Hero "Add your first book"); **session running** (Hero becomes "Back to Circe · 14:02", Dusk timer, Focus In).
Late night: tea row suggests caffeine-free only (engine rule), greeting from the voice engine.

### 4.2 Plan: which book, at what time

Fixes "reading several books at once makes no sense". The day is a timeline of reading times; each time has one
book (or "Shared", which splits between Reading books). Changing a time or a book is a direct tap on that row.

```
 Plan                                   ( + )  ← add a reading time
 ( One book at a time | Several books )        ← shown only with 2+ books in Reading
 M  T  W [T] F  S  S                           ← week strip; tap a day to see its plan

 Thursday · 3 reading times · 45 min
 ╭───────────────────────────────────────────╮
 │ (7:30 AM)  ┌─┐ Project Hail Mary     (⇄)  │ ← time chip: tap → wheel (5-min ticks)
 │  Morning   └─┘ 15 min · pp. 80–96         │   ⇄: swap the book for this time
 ├───────────────────────────────────────────┤
 │ (8:30 PM)  ┌─┐ Circe                 (⇄)  │
 │  Evening   └─┘ 20 min · pp. 142–158       │
 ├───────────────────────────────────────────┤
 │ (10:00 PM) ◌   Shared                (⇄)  │ ← no book pinned: splits what's left
 │  Bedtime       10 min · Circe 158–164     │
 ╰───────────────────────────────────────────╯

 Up next                               Edit ›  ← reorderable To-read queue (level 1)
 1 ┌─┐ Piranesi            starts Nov 4
 2 ┌─┐ The Remains of…     starts Nov 19

 Finish dates                                  ← Forest sentences; tap → forecast (level 2)
 Circe: likely Nov 3, a day sooner than last week
```

Interactions:
- **Change time:** tap the time chip → a glass sheet with a wheel (5-minute detents, selection tick each, magnet snap
  on the hour) and weekday chips. Save plays `planChanged`, the row re-sorts with `smooth`, the time Focus-Ins.
- **Swap book:** tap ⇄ (or swipe the row left) → sheet listing Reading books + "Shared". Pick one: the row's cover
  Focus-Ins, `planChanged`. Pinning a book while in "One book at a time" switches to "Several books" and says so in one
  line under the switch (no alert).
- **Add / remove:** `+` adds a time at the next free hour, opened in the time sheet; swipe right or the sheet's
  Remove deletes (with undo toast).
- Day tap in the week strip shows that day's computed plan (`slotPlans(on:)`), read-only for other days.

### 4.3 Library (with search and Discover)

```
 Library                             ( + )     ← + = add manually / scan ISBN
 (🔍 Search books, authors)                    ← pull-down search field, glass
 ( Reading 2 | Up next 5 | Finished 31 )       ← glass segmented chips
 ╭──────────────╮ ╭──────────────╮
 │ ┌──────────┐ │ │ ┌──────────┐ │            ← big covers, 2-up grid
 │ │  Circe   │ │ │ │   Hail   │ │
 │ └──────────┘ │ │ └──────────┘ │
 │ 48% ━━━━──── │ │ 71% ━━━━━━── │
 ╰──────────────╯ ╰──────────────╯
 For you                                       ← Discover row: recommender carousels (level 1)
 ┌──┐ ┌──┐ ┌──┐ ┌──┐ →          (Swipe to pick ›)
```

Search results replace the shelves in place (Focus In). A result row has a glass `+` that adds to Up next (one tap,
`pageTurn`-light), long-press for "Start now" / "Reading" / "Finished". Discover is the recommender's carousels and
the swipe deck; the librarian and circles are level 2 entries at the bottom.

### 4.4 Book

```
 ‹                                     (⋯)
          ┌────────────┐
          │   cover    │                       ← zooms in from the tapped card
          └────────────┘
            Circe                              ← display, New York
         Madeline Miller · 393 pages

 ╭───────────────────────────────────────────╮
 │ p. 189 of 393         48% ━━━━━━━──────── │ ← tap "p. 189" → Where are you? sheet
 │ Likely done Nov 3 · reading 8:30 PM daily │ ← forecast sentence + its slot
 │ [▓▓▓▓▓▓▓▓  ▶  Read now  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓]   │ ← Hero
 ╰───────────────────────────────────────────╯
 ( Reading time: 8:30 PM ⇄ )  ( Log pages )   ← glass buttons
 Notes & quotes (3) ›    History ›    About ›   ← level 2
```

States: Up next (Hero "Start reading" asks "Where are you?" first if no position), Finished (Hero none; "Read again",
rating, quotes).

### 4.5 Session

Full screen, Dusk glow backdrop, nothing but the timer and three controls. Stays awake, so it stays cheap.

```
                Circe
         pp. 142 → about 158                   ← caption

             ╭──────────────╮
             │    14:02     │                  ← timer: rounded 76, Focus In on start,
             ╰──────────────╯                    numeric roll each second, never blurred
          ◔ 6 min to today's goal              ← Dusk ring

    ( ❚❚ )        [▓▓  Done  ▓▓]       ( ♪ )   ← pause (glass), Done (Hero), ambience (opt-in, glass)
```

**Done** → page sheet: big page numeral on a scrubber, pre-set to the forecast page, `-`/`+` glass steppers, last stop
"Finished the book". **Save** → outcome sheet: minutes, pages, goal ring filling (Forest), one sentence from the engine.
Pause dims nothing and blurs nothing; the timer turns `textSecondary` and the pause symbol replaces play.

### 4.6 Tea (ritual inside the session, cabinet and preferences in You)

The steep is a *countdown that is always sharp*:

```
              Earl Grey · 95 °C
             ╭──────────────╮
             │   ◯  3:12    │                  ← Clay ring drains around a sharp numeral
             ╰──────────────╯
     The steep isn't reading time.             ← caption
    ( Skip steep )          ( Something else ) ← glass

   …at 0:00:  "Ready" Focus-Ins (blur 12 → 0), teaReady haptic,
   the Hero appears: [▓▓  ▶ Begin reading  ▓▓]
```

The old cup blurred while steeping (`SessionRitualView.focusBlur`); that is removed. The only blur left is the
arrival of "Ready", which resolves to sharp in half a second.

**Tea preferences** (You → Tea): one page of glass chips, no forms.

```
 Teas you like     (Black) (Green ✓) (Oolong ✓) (Herbal ✓) (Rooibos) (Chai) (Matcha) (White)
 Caffeine          ( Any | Mornings only | Low | None )
 Flavours          (Floral ✓) (Citrus) (Smoky) (Malty) (Fruity ✓) (Minty) (Spicy) (Nutty) …
 By time of day    Morning  (Green ✓)(Black)        ← optional per-daypart family picks
                   Evening  (Herbal ✓)(Rooibos ✓)
 Your cabinet ›    Tea history ›
```

Today's tea row and the ritual's "Something else" follow these (engine change, see §8).

### 4.7 You (history, insights, tea, settings)

```
 You                                    (⚙)
 ╭─────────────────────╮ ╭─────────────────╮
 │ 9-day streak        │ │ 3h 40m this week│  ← level 0 of You
 ╰─────────────────────╯ ╰─────────────────╯
 ╭───────────────────────────────────────────╮
 │ Insights · You read most at 9 PM          │  ← Bloom; one sentence from InsightsEngine
 │ ▁▃▅▂▆▇▃  this week                         │  → Insights (level 2)
 ╰───────────────────────────────────────────╯
 ( History › )  ( Journal › )  ( Challenges 2 › )  ( Year in books › )
 ( Tea › cabinet, preferences, history )
 ( Circles › )
```

### 4.8 Discover

Lives in Library ("For you", "Swipe to pick"). The swipe deck is full screen glass cards: right = keep (Up next),
left = pass, up = start now. Each has a visible glass button too.

### 4.9 Settings (from You, the gear)

A plain inset-grouped list on the backdrop, glass rows: **Reading** (daily minutes, days, reading speed + retake
test), **Reminders**, **Tea**, **Feel** (haptics full / light / off, ambience off by default, sounds off by default),
**Appearance** (system / light / dark), **iCloud** (status only), **Data** (export, backup, erase), **About**.

### 4.10 Onboarding: four steps, no tutorial

```
 1  Welcome        Leaf icon Focus-Ins. "Leaf tells you what to read, when." [▓ Get started ▓]
 2  Your book      Search + starter covers. Tap one (or more) → "Where are you?" inline page dial.
 3  Your time      One screen: minutes (dial 5–180), when (Morning / Lunch / Evening / Bedtime chips → slots),
                   days (weekday chips, all on by default). Reminders toggle here.
 4  Your plan      The Plan tab's timeline, live, with the finish sentence. [▓ Begin reading ▓] or "Later".
```

The speed test leaves onboarding: Leaf starts at 230 wpm and learns from real sessions; "Measure my speed" is offered
once on Today after the first session and stays in Settings. (Open question for the owner.)

### 4.11 Apple Watch

Same tokens on black. Three pages, vertical:

```
 ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
 │ 8:30 PM       │  │    14:02      │  │ 12/25 min     │
 │ Circe         │  │  Circe        │  │   ◔ (Forest)    │
 │ pp. 142–158   │  │ (❚❚)  (Done)  │  │ 9-day streak  │
 │ [▓ ▶ Read ▓]  │  │               │  │               │
 └───────────────┘  └───────────────┘  └───────────────┘
   Next (Dusk)        Session            Today
```

Complications: circular goal ring (Forest), rectangular "8:30 PM · Circe" (Dusk), corner minutes.

### 4.12 Widgets and Live Activity

- **Small:** goal ring + minutes, next time. **Medium:** next slot (cover, time, pages) + "Begin reading" button
  (intent). **Large:** today's slots. **Lock Screen:** ring, "8:30 PM · Circe".
- **Live Activity:** Dusk timer (system `Text(timerInterval:)`, always sharp), book title, pause/done buttons. Steeping
  shows the Clay countdown, then "Ready". Dynamic Island compact: Dusk ring + minutes.
- Widgets use the canvas and accent tints; glass where the system renders it (iOS 26 accented and clear widget modes).

## 5. Owner feedback, and how each is fixed

| Feedback | Fix |
|---|---|
| "Begin reading" is the hero, solid black with Liquid Glass | `CanopyHeroButton`: black fill under interactive black-tinted glass with a specular rim, white label, in both modes. One per screen |
| "Steep and read", not "…anyway" | Fixed in Phase 1 (`TodayNook.steepButton`); the new Today never uses "anyway" |
| Tea timer must never sit blurred | Fixed in Phase 1: the steep countdown's resting blur is gone. Rule 4 of the system; `CanopyTimerText` has no blur parameter at all |
| Tea preferences | You → Tea preferences page (§4.6), suggestions follow (§8 engine change) |
| Several books at once | Plan timeline: a book per reading time, tap time or ⇄ to change (§4.2) |
| Yellow wash, no accents | Clean cream (not yellow) with deep forest green, plus Dusk, Clay, Bloom with one job each |
| Can't tell what the app does | One line on Welcome and Today's structure; 4 tabs with one question each |
| Haptics lost | §6 map, one enum (`CanopyFeel`) for every screen |

### Blur audit (`Leaf/DesignSystem/Blur.swift` and users)

| Use | Verdict |
|---|---|
| `FocusPullTransition` (transition) | Keep: a moment that ends sharp. Becomes `canopyFocusIn` |
| `focusPull(isFocused:)` (screen behind a sheet stays blurred, on `TodayView`) | **Remove in Phase 2.** It is a resting blur |
| `numericBlur` / `PerDigitBlurText` (blur-through on change, velocity smear while scrubbing) | Keep for scrubbers only (it resolves when the finger slows). Not on timers |
| `SessionRitualView.focusBlur` (steep countdown blurred until ready) | **Removed now** |
| `TeaCup` steam blur 2.5 pt | Keep: decorative steam, carries no information |
| Nook / atmosphere scenes, cover backdrops (large blurred art) | Retire with the paper look; the Canopy backdrop is static gradients |

## 6. Haptics map

All through `CanopyFeel` (`Leaf/DesignSystem/Canopy/CanopyFeel.swift`), which plays `Haptics.shared` patterns and
respects Settings → Feel. ✱ = new Core Haptics pattern added in Phase 1.

| Moment | `CanopyFeel` | Pattern |
|---|---|---|
| Begin reading / start session | `.start` | `sessionStart`: firm tap, short low swell |
| Pause | `.pause` | ✱ `pauseSettle`: one soft, dull tap (0.5, sharpness 0.15) |
| Resume | `.resume` | light impact |
| Done (end session) | `.finishSession` | `sessionEnd`: swell into a firm tap |
| Page logged (Save) | `.pageLogged` | `pageTurn`: soft brush then a tap |
| Page dial ticks | `.tick` / scrub events | selection ticks, `magnetSnap` on the forecast page, `boundsHit` at ends |
| Daily goal reached | `.goalReached` | `goalReached`: two rising taps and a glow |
| Book finished | `.bookFinished` | `bookFinished`: three rising taps, swell, cover closes (heavier for long books) |
| Steep started | `.steepStart` | ✱ `steepPour`: a short low rumble, like pouring (0.35 s) |
| Last 3 s of the steep | `.countdown` | `countdownBeat` once per second |
| Steep done / tea ready | `.teaReady` | `teaReady`: two soft clinks |
| Plan changed (time saved, book swapped, mode switched) | `.planChanged` | ✱ `planChanged`: crisp click, a soft echo 70 ms later |
| Time wheel detent | `.tick` | selection; `magnetSnap` on the hour |
| Swipe action crosses its threshold | `.swipeThreshold` | rigid 0.6 |
| Deck keep / pass / start | `.keep` / `.tick` / `.startNow` | `deckKeep` / selection / `deckStart` |
| Reorder lift / drop | `.lift` / `.drop` | `reorderLift` / `reorderDrop` |
| Tab change, chip or toggle | `.select` | selection |
| Secondary glass button | `.tap` | light impact |
| Hero button | its moment (`.start`) | never a plain tap |
| Error, can't do that | `.warning` | notification warning |

## 7. App icon

**Concept: "Leaf, open."** An open book seen from above whose two pages curve into a single leaf: the spine is the
leaf's midrib, the page edges are its veins. Revision 2 follows the live icon's lead (a green leaf on cream): two green
glass panes with a bright rim on a clean cream, a short stem. It holds at 40 px (`docs/design/icon/sizes.png`).

- iPhone: 1024 px light (green on cream), dark (sage panes on warm charcoal), and tinted (greyscale for the
  system tint).
- Watch: 1024 px, the same mark, centred for the circular mask.
- Single-size asset catalog entries: Xcode renders every required size from the 1024 master.
- Files: `Leaf/Resources/Assets.xcassets/AppIcon.appiconset/`, `LeafWatch/Assets.xcassets/AppIcon.appiconset/`;
  source `scripts/design/make_icon.py` (Pillow); previews in `docs/design/icon/`.

## 8. Engine and model changes Phase 2 will need

Kept small and Foundation-only, each with Linux tests.

1. **Tea preferences.** `TeaPreferences` in `Shared/Cozy/` (liked families, caffeine choice, liked flavours/aromas,
   optional families per daypart), stored on `Preferences` with tolerant decoding. `TeaSuggester.ranked` gains a
   `preferences:` parameter: liked families and flavours add to the fit score, the caffeine choice lowers the cap
   (never raises the engine's hard night rule), daypart picks win for their daypart. Needs Engine's OK for the synced
   field (CloudSync merge of a new `Preferences` field).
2. **Slot swap convenience.** `LibraryStore.setBook(_:forSlot:)` and `moveSlot(_:hour:minute:)` wrapping
   `updateReadingSlot`, which also switch `planMode` to `.sideBySide` when a second book gets pinned. View-side only
   if Engine prefers.
3. **Expected page.** The session's page dial wants the forecast page for "now"; `TodayBrief.current.assignment.toPage`
   covers it, so no change unless the session runs past the assignment (then extrapolate by WPM in the view model).

Nothing in CloudKit, entitlements, TestFlight or the catalog changes.

## 9. Phase 2 order (after OK)

1. Shell: four tabs (Today, Plan, Library, You), backdrop, accessory restyle.
2. Today on Canopy, then Session (timer, page sheet, outcome), then the tea ritual.
3. Plan timeline with time and swap sheets.
4. Library + search + Discover, then Book.
5. You (insights entry, history, journal, challenges, tea cabinet and preferences), then Settings.
6. Onboarding (four steps).
7. Watch, widgets, Live Activity.
8. Delete the retired paper components once nothing uses them.

Each step is a small batch of commits that builds, pushed together to save CI minutes, with screenshots checked.

## 10. Open questions for the owner

1. **Tabs:** Today · Plan · Library · You, with search inside Library. OK, or keep search as its own tab?
2. **Speed test:** move it out of onboarding (Leaf learns your speed from sessions; the test stays in Settings)?
3. **Rest days:** no Hero on a rest day, just a quiet "Read a little". OK?
4. **Icon:** the open-book leaf, green glass on cream (previews attached). Keep, or try another direction?
5. **Palette:** Linen, Oat or Ivory (screenshots C2-canopy-today-*)?
