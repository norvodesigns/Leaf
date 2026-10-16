# Leaf design spec

This is the single source of truth for how Leaf looks, moves and feels. Tokens and shared components live in `Leaf/DesignSystem/`. Feature code uses them and never re-creates them. If code and this file disagree, this file wins.

## 0. Concept review

Each concept is scored 1–10 on six criteria.

| Concept | Beauty | Uniqueness | Usability | Fit (paper + glass) | Haptics | Buildability | Total |
|---|---|---|---|---|---|---|---|
| **Folio** (magazine) | 9 | 8 | 8 | 10 | 7 | 8 | **50** |
| Clothbound (object) | 8 | 9 | 6 | 6 | 10 | 4 | 43 |
| Lamplight (ritual) | 8 | 7 | 8 | 7 | 8 | 7 | 45 |

**Folio wins.** It *is* "editorial paper + Liquid Glass": numbers set as headlines, stats as sentences, glass strictly for chrome. It is mostly type, rules and `numericText`, which SwiftUI does cheaply and well. Its always-present "Ticket" also fits iOS 26.0, where `.tabViewBottomAccessory` can't be hidden on demand, so the accessory changes state instead of disappearing.

- **From Clothbound:** the **ribbon** (the one "now" colour, and a bookmark tail on covers being read), **heft-scaled haptics**, a shared **hinge overlay** so scans and generated covers read as one shelf, the **page scrubber with an "est." tag**, and **directional reflow ticks** (sharp when a date moves earlier, dull when later).
- **From Lamplight:** the **guilt-free week strip**, the **page span bar** showing today's pages, **delta chips** ("6 days sooner"), the session's **reading-mode dim**, and the lamplight mesh, **confined to the session**.
- **Rejected:** pull-the-ribbon to begin (hard to discover and to make accessible), 3D page curls and swinging covers, cloth weave, deckled edges and drop caps (costly and noisy), a lamp behind every screen (battery, muddies the paper), and ratings.

## 1. Principles

- **Paper is content, glass is chrome.** Text, covers and lists sit on paper. Only controls that float above content are glass.
- **Numbers are headlines.** Each screen has one large numeral, and it's always minutes or pages. Everything else is a sentence.
- **Ration colour.** Ink does the work. *Ribbon* means "now" (today, current page, live timer) and stays under 3% of any screen. *Accent* green means "done" or "sooner".
- **Only books cast shadows.** Covers are physical objects. Nothing else is elevated, apart from a row while you're dragging it.
- **Signature moments are rare and short.** They happen at start, end, finish, goal and reflow, and each lasts 1.5 s or less. Everyday screens stay still.
- **No guilt.** No red for missed days, no loss modals, no streak pressure. Rest days are part of the plan.

## 2. Color

Define these in `Leaf/DesignSystem/LeafColor.swift` as `Color` statics built from `UIColor { traits in … }` light/dark pairs. Set the app-wide `.tint(.accent)`. Update `AccentColor.colorset` to match `accent`.

| Token | Light | Dark | Usage |
|---|---|---|---|
| `paper` | `#F4EFE6` | `#1A1714` | Every screen background |
| `paperRaised` | `#FBF8F2` | `#24201B` | Stat tiles, settings rows, lifted row |
| `paperSunken` | `#EBE4D8` | `#13110E` | Book-detail stage, wells, chip fills |
| `ink` | `#1F1A15` | `#EFE7D8` | Headlines, numerals, body, primary button tint (15:1) |
| `inkSecondary` | `#5C554B` | `#B5AB98` | Authors, meta, captions (6.4:1 / 7.9:1) |
| `inkTertiary` | `#6E6457` | `#958B7B` | Eyebrows, index numerals, unselected letters (≥4.5:1 on all papers) |
| `inkFaint` | `#B9B1A3` | `#5A5246` | **Non-text only**: leader dots, future-day dots, missed rings |
| `hairline` | `#DDD5C7` | `#36302A` | 1-px rules (`1 / displayScale`), progress tracks |
| `hairlineStrong` | `#B4AA9A` | `#554D42` | Ruler ticks, double-rule top line, rest-day dashes |
| `accent` | `#3E6B4F` | `#8DBB98` | Progress fill, done states, "sooner", toggles and links |
| `accentSoft` | `#DCE6DA` | `#2A3A2F` | Today's span on the page bar, "sooner" chip fill |
| `ribbon` | `#B23F2C` | `#E0694F` | "Now": today marker, page caret, live dot, goal strike, cover ribbon, dial needle |
| `ribbonSoft` | `#F3DDD5` | `#3F2620` | 0.6 s flash behind a date that just changed |
| `glassTint` | `#F4EFE6` @ 22% | `#1A1714` @ 30% | `.glassEffect(.regular.tint(.glassTint))`: warm "vellum" glass |
| `lamp` | `#FBF1DD` | `#2E261C` | Session mesh centre point |
| `shadow` | `#2A1F14` | `#000000` | Base colour for cover shadows (alpha set per use) |

Destructive actions use the system `role: .destructive` style, not a custom red.

### Generated-cover palettes

Choose a palette with `Book.paletteSeed % 10`. Covers keep these colours in dark mode.

| # | Name | Background | Foreground | Rule / ornament |
|---|---|---|---|---|
| 0 | Oxblood | `#6B2B26` | `#F3E9D7` | `#D9A866` |
| 1 | Ultramarine | `#26375C` | `#EDE6D8` | `#C9A46A` |
| 2 | Bottle | `#2F4A3A` | `#EADFC8` | `#C8B07A` |
| 3 | Slate | `#3D4A52` | `#E9E4DA` | `#A9B7BE` |
| 4 | Plum | `#573247` | `#F1E4E0` | `#D7A2A0` |
| 5 | Teal | `#2D5D5B` | `#EEE7D9` | `#E0B872` |
| 6 | Rust | `#9A4A2C` | `#F7EBDC` | `#F2C28A` |
| 7 | Ochre | `#C48A2C` | `#1F1A14` | `#6B2B26` |
| 8 | Sage | `#9CAE94` | `#1F2A1E` | `#2A3F2E` |
| 9 | Bone | `#E9E0CD` | `#1C1915` | `#B23F2C` |

### Watch palette

Update `WatchTheme`. The watch is always dark and suits OLED. `WatchTheme.covers` must use the ten backgrounds above, in the same order.

| Token | Hex | Usage |
|---|---|---|
| `background` | `#000000` | Session page, list background |
| `ink` | `#F1EADC` | Numerals, titles |
| `inkSecondary` | `#B9B0A0` | Captions |
| `accent` | `#8DBB98` | Ring fill, prominent buttons (label `#0E1A12`) |
| `accentDeep` | `#1E3326` | Today page gradient top, fading to `#000000` |
| `ribbon` | `#E0694F` | Live dot, "est." tag, ring head |
| `track` | `#FFFFFF` @ 14% | Ring and bar tracks |

## 3. Typography

Put these in `LeafType` as `Font` statics. Instrument Serif is display-only and never appears below 24 pt.

| Token | SwiftUI spec | Dynamic Type |
|---|---|---|
| `heroNumeral` | `.custom("InstrumentSerif-Regular", fixedSize: 120)`, tracking −3, `lineLimit(1)`, `minimumScaleFactor(0.5)` | Fixed |
| `countdown` | `.custom("InstrumentSerif-Regular", fixedSize: 160)` | Fixed |
| `wordmark` | `.custom("InstrumentSerif-Italic", fixedSize: 96)`, tracking −1 | Fixed |
| `timer` | `.system(size: 88, weight: .light, design: .serif).monospacedDigit()`, tracking −1 | Fixed |
| `display` | `.custom("InstrumentSerif-Regular", size: 56, relativeTo: .largeTitle)`, tracking −1 | Yes |
| `masthead` | `.custom("InstrumentSerif-Regular", size: 40, relativeTo: .largeTitle)`, tracking −0.5 | Yes |
| `statNumeral` | `.custom("InstrumentSerif-Regular", size: 34, relativeTo: .title)`, tracking −0.5 | Yes |
| `index` | `.custom("InstrumentSerif-Regular", size: 28, relativeTo: .title2)` | Yes |
| `pullQuote` | `.custom("InstrumentSerif-Italic", size: 24, relativeTo: .title2)`, tracking −0.2 | Yes |
| `title` | `.system(.title2, design: .serif, weight: .medium)` (22) | Yes |
| `headline` | `.system(.headline, design: .serif, weight: .semibold)` (17) | Yes |
| `body` | `.system(.body, design: .serif)`, `lineSpacing(5)` | Yes |
| `passage` | `.system(.title3, design: .serif)`, `lineSpacing(9)`, tracking 0.1 | Yes |
| `author` | `.system(.subheadline, design: .serif).lowercaseSmallCaps()`, tracking 0.6 | Yes |
| `ui` | `.system(.subheadline, weight: .medium)` (15) | Yes |
| `uiBody` | `.system(.body)` | Yes |
| `caption` | `.system(.caption)` (12), `inkSecondary` | Yes |
| `eyebrow` | `.system(.caption2, weight: .semibold)` (11), `.textCase(.uppercase)`, tracking 1.5, `inkTertiary` | Yes |
| `data` | `.system(.subheadline, weight: .medium).monospacedDigit()` | Yes |

- **Scaling caps.** Any view that uses `display`, `masthead` or `statNumeral` gets `.dynamicTypeSize(...DynamicTypeSize.accessibility2)`.
- **Accessibility sizes.** Multi-column layouts collapse to one column at accessibility sizes. Fixed numerals never scale.
- **Large titles.** Large navigation titles use `masthead` and inline titles use New York 17 semibold. Set both once through `UINavigationBarAppearance`, scaled with `UIFontMetrics`.
- **Book titles in running text** are italic.

## 4. Space, shape, elevation, glass

**Spacing** (`Space`): `xxs 2`, `xs 4`, `s 8`, `m 12`, `l 16`, `xl 20`, `xxl 28`, `xxxl 40`, `section 56`. Side margin 20, section gap 40, minimum row and hit target 44.

**Radii** (`Radius`, always `.rect(cornerRadius: r, style: .continuous)`): `cover` 2 (XS, S) or 3 (M+), `tile` 16, `card` 22, `panel` 32. Buttons, chips and the accessory are capsules.

**Rules.** A hairline is 1 px. A double rule is 1 pt `hairlineStrong`, a 2 pt gap, then a 1 px `hairline`.

**Elevation.** Only covers have shadows. Each uses two layers, both in `shadow`:

| Size | Contact | Ambient |
|---|---|---|
| S | opacity 0.22, radius 0.5, y 0.5 | opacity 0.14, radius 3, y 2 |
| M | opacity 0.22, radius 0.5, y 0.5 | opacity 0.14, radius 6, y 4 |
| L | opacity 0.22, radius 0.5, y 0.5 | opacity 0.14, radius 10, y 7 |
| XL | opacity 0.22, radius 0.5, y 0.5 | opacity 0.14, radius 16, y 12 |

In dark mode, ambient opacity is 0.5. A lifted row gets `shadow` at opacity 0.18, radius 16, y 10.

**Glass rules**
1. Glass appears only on the tab bar, toolbars, `SessionAccessory`, buttons, session controls and page panel, add (+) buttons, the plan-mode picker, and (system) sheets.
2. Never put glass on rows, cards, text blocks or covers.
3. Custom glass is `.glassEffect(.regular.tint(.glassTint).interactive(), in: .capsule)`.
4. Wrap adjacent glass controls in `GlassEffectContainer(spacing: 12)`. Session controls use spacing 20.
5. Each screen has at most one `.glassProminent` control.
6. Don't nest glass. Controls inside the accessory or the panel use `.buttonStyle(.plain)`.
7. Scrolling content gets `.scrollEdgeEffectStyle(.soft, for: .top)`.

## 5. Components

**BookCover**(`book`, `size`, `ribbon: Bool = false`). Always 2:3.

| Size | Points | Used in |
|---|---|---|
| XS | 24×36 | Accessory |
| S | 44×66 | Rows |
| M | 96×144 | Shelves, carousels |
| L | 140×210 | Today hero, finished moment |
| XL | 200×300 | Book detail |

- **Layers, bottom to top:** `GeneratedCover`; the real image (`coverURL(.medium)`, `.large` for L/XL, always `?default=false`), `.fill`, faded in over 0.3 s; the hinge overlay; a 0.5 pt inner stroke (`ink` 12% light, white 10% dark); the shadow.
- **Hinge overlay** (spine highlight): black 18%→clear across the left 7%; a 0.5 pt white-22% line at x = 6%; a top-left→bottom-right sheen, white 6%→clear.
- **Bad scans:** an image under 10 px wide counts as missing. Aspect outside 0.57–0.77 is letterboxed (`.fit`) on its palette background with a 6% inset.
- **Ribbon** (M and up): a `ribbon` strip 0.09w wide, left edge at x = 0.70w, drawn behind the cover. It shows 0.12h below the bottom edge and ends in a swallowtail notch 0.6 × its width deep.
- **Label:** "Cover of {title} by {author}".

**GeneratedCover**: see §9. **SpineView**: not used, because spines can't carry long titles at Dynamic Type sizes.

**PageSpanBar**(`current`, `todayTo`, `total`): a 4 pt `hairline` capsule track. Read pages fill `ink`. Today's span fills `accentSoft` with a 1 pt `accent` stroke. A 2×12 pt `ribbon` caret marks `current`. The fill turns `accent` when the book is finished. Height 12. **ProgressBar** (rows): 2 pt, `ink` on `hairline`.

**ProgressRing**(`progress`, `diameter`, `lineWidth`): `hairline` track, `accent` fill, round caps, starts at −90°. The session size adds a `ribbon` head dot (1.6 × line width). Sizes: accessory 22/2.5, session 300/4, watch Today 84/7, watch session 120/8.

**PrimaryGlassButton**(`title`, `systemImage?`): `.buttonStyle(.glassProminent)` with `.tint(.ink)` and a `.headline` semibold label in `paper`. Height 54, full width inside the margins. Disabled: opacity 0.4. Loading: a `paper` `ProgressView` replaces the label. Tap plays `press()`. **Secondary:** `.buttonStyle(.glass)`, `ink` label, height 54 (44 compact).

**TickRuler**(`range`, `value`, `spacing`, `majorEvery`, `labels`) is one component with two uses.
- **Build:** a horizontal `ScrollView` with `.scrollTargetLayout()`, `.scrollTargetBehavior(.viewAligned)` and `.scrollPosition(id:)`. Content margins are half the width.
- **Ticks:** 1 pt `hairlineStrong`, 12 pt tall; 22 pt at each major; 34 pt when labelled, with a 12 pt `data` label in `inkTertiary` 6 pt below. A fixed 2×48 pt `ribbon` needle sits at the centre. The outer 25% fades out. Height 88.
- **MinutesDial:** 5–180, spacing 8, major every 5, labels at 15, 30, 45, 60, 90, 120, 180. The readout above is `heroNumeral` with `numericText` and the eyebrow "MINUTES A DAY".
- **PageScrubber:** start page to page count, spacing 10, major every 10, labels every 50. A `ribbon` "est." tag sits above the predicted page.
- **VoiceOver:** `accessibilityAdjustableAction`, ±5 minutes or ±1 page.

**WeekdayPicker**: seven columns in locale order (`firstWeekday`, `veryShortStandaloneWeekdaySymbols`), letters in `masthead`. Selected: `ink` with a 20×2 pt `ribbon` underline 6 pt below. Unselected: `inkTertiary`. Hit target 44×64. Each column is a toggle labelled "Monday, reading day" or "Monday, rest day".

**WeekStrip**: seven columns of eyebrow letter over a 10 pt marker. Read: an `accent` dot. Rest: a 10×1.5 `hairlineStrong` dash. Missed: a 1.5 pt `inkFaint` ring. Future reading day: a 4 pt `inkFaint` dot. Today adds a 14×2 `ribbon` underline. A streak caption appears only from 3 days.

**StatTile**: `paperRaised`, 1 px `hairline` stroke, `Radius.tile`, 14 pt padding, minimum height 84. `statNumeral` over an `eyebrow`. Three to a row with 8 pt gaps; stacked at accessibility sizes.

**SectionHeader**(`eyebrow`, `action?`): the eyebrow, an optional trailing `caption` `inkSecondary` action ("See all"), and a 1 px `hairline` below. 40 pt above, 12 below. The `.double` variant uses the double rule.

**EmptyState**(`title`, `message`, `action?`): centred with 56 pt vertical padding. A "❦" ornament (`index`, `inkTertiary`), the title in `masthead`, the message in `body` `inkSecondary` (max 300 pt wide), and an optional button.

**PlanRow** (TimelineBand), height 64.
- **Line 1:** `index` "01" (`inkTertiary`, 40 pt wide), title in `headline`, leader dots (2 pt `inkFaint` every 6 pt, `accessibilityHidden`), finish date in `data` ("3 Dec").
- **Line 2:** a 6 pt capsule band on the shared time axis, from start to finish. `accent` for Reading books, `hairlineStrong` for To read.
- **List overlay:** month eyebrows on top, 1 px `hairline` gridlines at 50% at month starts, and a 1 pt vertical `ribbon` rule at today.
- **DeltaChip:** a 22 pt capsule with 8 pt padding, `caption` semibold, shown for 2.5 s. "6 days sooner": `accent` on `accentSoft`. "4 days later": `inkSecondary` on `paperSunken`.

**ShelfSwitcher**: three tabs in `title` with superscript counts (`caption`, `baselineOffset(8)`): "Reading² To read⁷ Finished³¹". Active: `ink` with a 2 pt `ribbon` underline that slides via `matchedGeometryEffect`. Inactive: `inkTertiary`. It sits on paper, not glass.

**SessionAccessory** (`.tabViewBottomAccessory`, always present). Expanded: a BookCover XS (a ProgressRing 22 when live), two lines (`ui` `ink` over `caption`), and a trailing 36×36 plain symbol button, with 16 pt horizontal padding. Inline (`tabViewBottomAccessoryPlacement == .inline`): the symbol and line 1 only. It's a `matchedTransitionSource` for the session zoom.

| State | Line 1 | Line 2 | Trailing | Tap |
|---|---|---|---|---|
| ready | "22 min · The Hobbit" | "pp. 142–158" | `play.fill` | Start session |
| live | "Reading · 12:04" (`numericText`), with a breathing 6 pt `ribbon` dot | "The Hobbit", or "The Hobbit · on Apple Watch" + `applewatch` | `pause.fill` | Open session |
| paused | "Paused · 12:04" (`inkSecondary`) | "The Hobbit" | `play.fill` | Open session |
| done | "Done for today · 24 min" (full ring with `checkmark`) | "5 reading days in a row" | `play.fill` | Start session |
| rest | "A rest day" | "Read anyway?" | `play.fill` | Start session |
| empty | "Find your first book" | n/a | `magnifyingglass` | Go to Search |

**PageEntryPanel**: glass in `.rect(cornerRadius: 32)`. Contents: "Where did you stop?" in `title`, the page in `heroNumeral`, the PageScrubber, and the caption "We guessed p. 158 from your pace." Buttons: "Save page" (`.glassProminent`, `ink`) and "Keep reading" (`.glass`).

**NotificationPreview**: a glass rounded rect (radius 22, 72 pt tall) with a 20 pt app icon, "LEAF · now" and the real reminder body.

## 6. Screens

**Shell:** Today (`sun.horizon`), Library (`books.vertical`), Plan (`calendar.day.timeline.leading`) and Search (`Tab(role: .search)`). The shell applies `.tabBarMinimizeBehavior(.onScrollDown)` and `.tabViewBottomAccessory { SessionAccessory() }`. The session zooms from whichever control was tapped (the hero button or the accessory), stored as `router.sessionSource`.

### Today
The only toolbar item is a trailing glass `gearshape` that opens Settings; there's no nav title. Top to bottom:
1. **Dateline:** the eyebrow "THURSDAY 16 OCTOBER" on the left, "NO. 42" (days since onboarding, labelled "Issue 42, your 42nd day with Leaf") on the right, then the double rule.
2. **Greeting** in `masthead` (§11).
3. **Hero** on paper:
   - Left: `heroNumeral` "22" over the eyebrow "MIN". Beside it: "of" in `pullQuote`, the title in `title`, the author in `author`.
   - Right: BookCover L with its ribbon, which plays `ribbonSway` on appear.
   - Below: "about pp. 142–158" in `pullQuote`, the PageSpanBar, the caption "p. 142 of 310 · done by Sun 26 Oct", and PrimaryGlassButton "Start reading".
4. **This week:** SectionHeader, WeekStrip, "5 reading days in a row".
5. **On your desk:** focus mode only, when Reading holds more than one book. Rows of cover S, title, ProgressBar, "p. 88 of 412".
6. **Up next:** "Middlemarch · begins Mon 27 Oct".

**States**
- **Goal met:** a hand-drawn 3 pt `ribbon` strike (a slightly wobbly `Path`) runs through "22" with `goalReached`. The eyebrow becomes "DONE FOR TODAY", the line reads *"Today's reading is done. Anything more is a gift."*, and the button becomes `.glass` "Read a little more".
- **Side by side:** the numeral shows the total. Under the eyebrow "IN TODAY'S ISSUE", rows of cover S, title, "20 min · pp. 142–158".
- **Rest day:** "A rest day." in `masthead`, *"Nothing's scheduled. Read anyway if you like."*, and a `.glass` "Read anyway".
- **Empty:** EmptyState "An empty issue." / "Add a book and Leaf will plan the pages." with a "Find a book" button that goes to Search.

### Library
- **Header:** the large title "Library", a trailing glass `plus` (opens AddBookManuallyView), and a ShelfSwitcher that respects `router.libraryShelf`.
- **Reading:** 168 pt rows of cover M with ribbon, title in `headline`, author, PageSpanBar, and "p. 142 of 310 · done by 26 Oct". Tapping a cover zooms to the detail.
- **To read** (the running order): 76 pt rows of `index` "01", cover S, title and author, and "by 3 Dec" in `data`.
  - **Reorder** in a custom `LazyVStack`. A 0.3 s long press lifts the row with `reorderLift`, scale 1.03, `paperRaised` and the lifted shadow. Each slot crossed plays `selection`. The drop plays `reorderDrop` and calls `store.reorder`. Then the dates reflow (§7) with `riffle` and DeltaChips.
  - **VoiceOver:** "Move up", "Move down" and "Move to top".
- **Finished:** a three-column grid of M covers, grouped by year under `display` heads ("2026").
- **Empty shelves:**
  - Reading: "Nothing open." / "Start a book from To read or Search."
  - To read: "The queue is clear." / "Add the books you mean to get to."
  - Finished: "Your finished books will live here."

### Plan
- The large title "Plan", the eyebrow "6 BOOKS · THROUGH 14 MARCH 2027", and a segmented `Picker` for "One at a time" and "Side by side".
- PlanRows with the month axis and today rule. Switching mode animates the bands with `paper`, rolls the dates, shows DeltaChips and plays `riffle`.
- **Footer:** "25 min a day · 5 days a week · 248 wpm", with a "Change" link to Settings.
- **Empty:** "Nothing to plan yet." / "Add a book to Reading or To read and Leaf will set the dates."

### Search
- **Empty query:** collections from `catalog.collections(wpm:excluding:)`. Each is a SectionHeader eyebrow ("UNDER FOUR HOURS AT YOUR PACE") over a horizontal carousel of M covers with `caption` titles.
- **Results** (`.searchable`, prompt "Title or author"): 88 pt rows of cover S, title in `headline`, author, "1937 · 310 pp", and "≈ 6 h at your pace" with `clock`.
  - Live results carry the eyebrow "OPEN LIBRARY". Offline, the eyebrow reads "OFFLINE · BOOKS ON THIS DEVICE".
  - A trailing 36 pt glass `plus` opens a Menu: "Start reading", "Add to top of To read", "Add to end of To read". It then turns into `checkmark` (`.symbolEffect(.replace)`) with `success`.
  - The last row reads "Not here? Add it by hand."
  - No results: "Nothing matches “{query}”." with an "Add it by hand" button.

### Book detail
Zooms from any cover.
- **Stage:** 360 pt tall. Its colour is the cover's `CIAreaAverage` (or the palette background for a generated cover) at 18% over `paper`, with `.backgroundExtensionEffect()`. Cover XL centred.
- **Header:** the eyebrow "FICTION · 1937", the title in `masthead` (centred), the author.
- **Facts:** three StatTiles: "310 / PAGES", "95K / WORDS", "6 h 22 m / AT YOUR PACE".
- **Status by shelf:**

  | Shelf | Content | Button |
  |---|---|---|
  | Reading | PageSpanBar and *"You'll finish on Sunday, 26 October."* | Prominent "Start reading" |
  | To read | *"Starts Mon 27 Oct, done by 3 Dec."* | `.glass` "Start reading now" |
  | Finished | "Finished 15 Oct 2026 · 34 days · 11 sessions" | none |
  | Not in library | n/a | Prominent "Start reading" and `.glass` "Add to To read" |

- **Sessions:** `data` rows such as "Tue 14 Oct · 23 min · pp. 142–158".
- **Toolbar:** a glass `ellipsis` Menu with shelf moves, "Edit page count" and "Remove from Library" (destructive, confirmed).

**AddBookManuallyView:** fields for Title, Author, Pages and Year (optional), under a live GeneratedCover L that updates as you type. Buttons: "Start reading" (prominent) and "Add to To read".

### Session (full screen)
- **Background:** a 3×3 `MeshGradient`, `paper` everywhere except the top-centre point, which is `lamp` and drifts ±0.03 over 12 s (`TimelineView(.animation(minimumInterval: 1/15))`). The idle timer is off.
- **Top:** a glass `chevron.down` on the left minimizes the session; it keeps running in the accessory. Centred: the eyebrow "THE HOBBIT · PP. 142–158".
- **Centre:** ProgressRing 300 around the `timer`, which counts down ("14:32", `numericText(countsDown: true)`). Caption below: "7 min read".
- **Bottom:** `GlassEffectContainer(spacing: 20)` with `.glass` "Pause" and `.glassProminent` "End". Pause morphs into Resume via `glassEffectID`.
- **Paused:** the digits turn `inkTertiary` and `breathe`.
- **Reading mode:** after 20 s without a touch, everything but the ring and timer fades to 25%. A tap restores it.
- **Goal reached:** `goalReached`, the ring fills, the eyebrow becomes "GOAL MET · KEEP GOING", and the timer counts up in `accent`. No modal.
- **End:** the End button morphs into the PageEntryPanel. "Save page" plays `pageTurn`, calls `finishSession(toPage:)` and presents the outcome. A session under a minute is discarded with "Session under a minute. Not logged."

### Session outcome
A sheet at `.medium` and `.large`.
- **Normal:** the eyebrow "SESSION LOGGED", "16 pages · 22 min" in `title`, and, if WPM moved by 3% or more, *"You're reading a little faster: 251 words a minute."* Then a WeekStrip whose today marker fills with `board`, and "Done".
- **Book finished:** `theEnd` (§7) plays.
  - The cover L rises; "The End" appears in Instrument Serif Italic, fixed 72; a 120 pt `accent` rule draws beneath it; `bookFinished(heft)` plays.
  - Then the colophon "Begun 11 Sept · Finished 16 Oct · 36 days · 11 sessions · 310 pages", the eyebrow "NEXT IN THE RUNNING ORDER" with a cover S and "Middlemarch begins tomorrow.", and "Done".

### Onboarding
Roman folios ("i … viii") in `eyebrow` sit at the bottom (active in `ink`), under a PrimaryGlassButton. Steps crossfade with a 12 pt rise.
1. **Welcome:** the `wordmark` "Leaf" plays `inkBleed`. Then *"Read on purpose."* and "Tell Leaf how you read. It plans the rest." Button "Begin".
2. **Speed test**
   - **Intro:** "First, a short read." / "About two minutes. Read at your usual pace — there's no clock on screen." Button "I'm ready".
   - **Countdown:** 3·2·1 in `countdown`, with a `countdownBeat` on each numeral.
   - **Passage:** the kicker as an eyebrow, the title in `masthead`, and "Written for Leaf · 312 words". The body is `passage`, with the first four words in small caps. A 1 px `ribbon` rule in the left margin grows with scroll, and a floating prominent "I've finished" button stays on screen.
3. **Quiz:** the eyebrow "QUESTION 2 OF 3" and the prompt in `title`. Answers are hairline rows starting a/b/c/d in small caps. A tap plays `selection`, a `ribbon` caret "‸" slides in, and the quiz advances after 0.35 s.
4. **Result**
   - The eyebrow "YOUR PACE" over a `heroNumeral` that counts up from 0 to 248, with `dialDetent` every 25 wpm and `sessionEnd` on landing.
   - A 100–500 ruler with a `ribbon` tick for the reader and a faint tick for "most adults · 238".
   - Caption: "words a minute · 3 of 3 understood", or "2 of 3 understood, so we eased it to 223 to keep your plan honest."
   - Pull quote: *"At this pace, The Hobbit takes about six hours."*
   - Buttons: "Continue" and a text "Retake".
5. **Minutes:** the MinutesDial over a live `pullQuote` sentence, e.g. *"About 37 pages a day — a novel every three weeks."*
6. **Days:** the WeekdayPicker with "Five days a week, weekends off." With no day picked, the button is disabled and the copy reads "Pick at least one day."
7. **Reminder:** a wheel `DatePicker` over a NotificationPreview. Buttons: "Allow notifications" (prominent) and "Not now". If declined: "No reminders. Leaf will be here when you are."
8. **Books:** inline search over a three-column grid of "Popular first reads". A tap toggles a `checkmark.circle.fill` badge with `selection`. The first pick goes to Reading and the rest to To read. Caption: "Your stack: 3 books · about 6 weeks." Buttons: "Make my plan" and "Skip for now". Today then enters with `inkIn`.

### Settings
A sheet at `.large`. A `Form` on `paper` (`.scrollContentBackground(.hidden)`), with `paperRaised` rows and eyebrow headers:
- **YOUR PACE:** "248 wpm · refined from 14 sessions", "Retake the reading test" (opens `SpeedTestView`), and a "Learn from my sessions" toggle.
- **YOUR SCHEDULE:** Minutes a day (pushes the MinutesDial), Reading days (pushes the WeekdayPicker), Plan style.
- **REMINDERS:** a toggle and a time.
- **FEEL:** Haptics: Full, Subtle or Off. Subtle uses the UIKit fallbacks only. Add `hapticsLevel` to Preferences.
- **APPEARANCE:** System, Day, Night.
- **DATA:** "Erase everything" (destructive, confirmed).
- **COLOPHON:** *"Set in Instrument Serif, New York and SF Pro. Covers courtesy of Open Library. Printed on your phone, read by you."*

### Apple Watch
Pages sit in a vertical-page `TabView`. Numerals use `.system(design: .serif).monospacedDigit()`.
- **Today:** `.containerBackground(LinearGradient(accentDeep → black), for: .tabView)`. A ring 84 shows the minutes left (30 pt) over "min left" (11 pt). Below: the title (serif `.headline`, one line), "pp. 142–158", and a `.glassProminent` "Start reading" tinted `accent`. When the goal is met: `checkmark`, "done" and "Read more".
- **Week:** a `#2A2118`→black gradient. Seven 8 pt bars, at most 60 pt tall: `accent` for read days, a `ribbon` cap on today, a dash on rest days. A dashed `track` goal line, and "5 days in a row".
- **Reading list:** rows of a 4×28 palette swatch, title, "p. 142 of 310" and a ProgressLine. Tapping asks "Read this now?" and then starts.
- **Session:** black background, ring 120, a 34 pt timer and the title above. Glass Pause and End buttons side by side. When `isLuminanceReduced`: minutes only ("14 min"), opacity 0.6, ring kept.
- **Page entry:** a 44 pt page number on `.digitalCrownRotation($page, from: start, through: pages, by: 1, sensitivity: .medium, isHapticFeedbackEnabled: true)`, a `ribbon` "est. 158" tag, "≈ 16 pages · 251 wpm", and "Save".
- **Wrap-up:** `checkmark.circle` "Logged" with "16 pages · 22 min". For a finished book: *"The End"* (serif italic) and "Next: Middlemarch". It closes itself after 4 s.

## 7. Motion

All motion lives in `Motion` (`Leaf/DesignSystem/Motion.swift`).

| Name | Spec | Use |
|---|---|---|
| `paper` | `.spring(response: 0.38, dampingFraction: 0.86)` | Layout changes, shelf underline, reflow bands |
| `board` | `.spring(response: 0.55, dampingFraction: 0.80)` | Covers rising, PageEntryPanel, week marker fill |
| `glass` | `.spring(response: 0.32, dampingFraction: 0.72)` | `glassEffectID` morphs, toggles, weekday underline |
| `inkIn` | opacity 0→1 and y +8→0, `.smooth(duration: 0.45)`, 0.05 s stagger, at most 6 items | Screen entrances |
| `strike` | `trim` 0→1, `.easeOut(duration: 0.5)` | Goal strike |
| `ruleDraw` | `trim` 0→1, `.easeOut(duration: 0.6)`, 0.3 s delay | "The End" rule |
| `countUp` | 1.2 s, ease-out cubic, through `TimelineView` | WPM result |
| `ribbonSway` | `KeyframeAnimator` rotation, anchor `.top`: `SpringKeyframe(3°, 0.25)`, `(−2°, 0.3)`, `(1°, 0.3)`, `(0°, 0.35)` | Today cover ribbon, once per appearance |
| `breathe` | `PhaseAnimator([1, 0.55])`, `.easeInOut(duration: 1.2)` | Paused timer, live accessory dot |
| `inkBleed` | blur 8→0 and opacity 0→1, `.easeOut(duration: 1.2)` | Welcome wordmark |
| `reflow` | dates via `numericText` with `paper`, 0.045 s stagger per row; `ribbonSoft` flash 0.6 s | Plan and To read changes |
| `theEnd` | cover `board` → title fade 0.4 s at +0.3 s → `ruleDraw` | Book finished |

- **Transitions:**
  - Cover to detail, and hero or accessory to session, use `.navigationTransition(.zoom(sourceID:in:))`.
  - Sheets use the system presentation.
  - Countdown numerals scale 1.15 → 1 and fade.
- **Reduce Motion.** Everything above becomes a 0.2 s opacity crossfade, except:
  - The zoom transition stays; the system adapts it.
  - Count-up shows the final number immediately, and its haptics still play.
  - The strike and rules appear fully drawn.
  - The sway, breathing and mesh drift stop.
  - The reading-mode dim still applies, since it's only a fade.

## 8. Haptics

**Heft** is `h = clamp((pages − 150) / 650, 0, 1)` and is passed as `Haptics.shared.play(.reorderLift, heft: h)`. In each event list, T marks a transient and C a continuous event. Times are in seconds, I is intensity, S is sharpness.

| Pattern | Events |
|---|---|
| `pageTurn` | C t0 d0.16 I0.35 S0.15, with `hapticIntensityControl` curve 0.2@0 → 1@0.08 → 0.1@0.16; T t0.17 I0.55 S0.35 |
| `bookFinished` | T t0 I0.45 S0.4; T t0.11 I0.6 S0.5; T t0.22 I0.8 S0.6; C t0.30 d0.45 I0.5 S0.2, curve 0.2@0.30 → 1@0.55 → 0.15@0.75; T t0.80 I(0.8+0.2h) S0.3; T t0.92 I0.3 S0.2 |
| `countdownBeat` | T t0 I0.7 S0.2; T t0.12 I0.45 S0.15 |
| `sessionStart` | T t0 I0.6 S0.5; C t0.05 d0.25 I0.3 S0.1 |
| `sessionEnd` | C t0 d0.2 I0.35 S0.1; T t0.22 I0.75 S0.3 |
| `dialDetent` | T t0 I0.45 S0.8 |
| `goalReached` | T t0 I0.6 S0.4; T t0.15 I0.9 S0.55; C t0.2 d0.35 I0.4 S0.15 |
| `reorderLift` | T t0 I(0.35+0.3h) S0.5; C t0.02 d0.12 I0.2 S0.1, curve 1@0.02 → 0@0.14 |
| `reorderDrop` | T t0 I(0.45+0.4h) S0.3; T t0.06 I0.25 S0.2 |
| `riffle(n, earlier)` | n transients (n ≤ 6), t = 0.04·i, I0.28, S0.8 if the date moved earlier, S0.3 if later |

UIKit fallbacks follow the existing `fallback(for:)`, with `riffle` falling back to one `selection`.

**Map**

| Interaction | Haptic |
|---|---|
| Any PrimaryGlassButton | `press()` |
| Tab, shelf, plan mode, segmented, quiz answer, weekday, cover pick | `selection()` |
| Toolbar or glass icon button | `tap()` |
| MinutesDial: each minute / each 5 / labelled marks | `selection()` / `dialDetent` / `rigid(0.8)` |
| PageScrubber: each page / each 10 | `selection()` / `dialDetent` |
| Speed-test countdown numeral | `countdownBeat` |
| WPM count-up: each 25 / landing | `dialDetent` / `sessionEnd` |
| Session starts (zoom completes) | `sessionStart` |
| Pause / resume | `soft(0.6)` / `tap()` |
| End tapped | `sessionEnd` |
| Save page | `pageTurn` |
| Goal reached (session, or Today strike) | `goalReached` |
| Book finished | `bookFinished(heft)`, then `success()` at +1.0 s |
| Row lift / slot crossed / drop | `reorderLift(heft)` / `selection()` / `reorderDrop(heft)` |
| Plan dates moved | `riffle(n: moved, earlier:)` |
| Book added from Search | `success()` |
| Remove or erase confirmed | `warning()` |
| Search or network error | `error()` |

**Watch** (`WKHapticType`)

| Moment | Haptic |
|---|---|
| Start | `.start` |
| Pause / resume | `.click` / `.click` |
| End | `.stop` |
| Crown page detents | built in |
| Save page | `.success` |
| Goal reached mid-session | `.success` |
| Book finished | `.success`, then `.notification` at +0.4 s |
| Sync failed | `.failure` |
| Opening a live session from Today | `.click` |

## 9. Generated cover

`GeneratedCover(book:)`. All dimensions are relative to the cover width w and height h, and nothing scales with Dynamic Type.

- **Palette:** `Book.paletteSeed % 10`, from §2. The background fills the cover.
- **Initial:**
  - Take the first letter of the title, skipping a leading "The", "A" or "An".
  - Set it in Instrument Serif at 1.2h, in the foreground colour at 8% opacity. Trailing-align it and offset it x +0.18w, y +0.10h so it bleeds off the edges.
  - Only when w ≥ 80.
- **Margins:** 0.10w.
- **Author:** at the top. SF Pro semibold uppercase, size 0.055w, tracking 0.14 em, foreground at 80%. Below it, after a 0.035w gap, a 1 px rule 0.24w long in the rule colour.
- **Title:**
  - Instrument Serif Regular, top at 0.26h, left-aligned.
  - Starts at 0.16w, with `minimumScaleFactor(0.55)` and `lineLimit(4)`.
  - A subtitle after ":" is set in Instrument Serif Italic at 0.55 × the title size, `lineLimit(2)`.
- **Foot:** the year in Instrument Serif Italic 0.07w on the left. On the right, `leaf.fill` at 0.07w in the rule colour.
- **Small sizes:**
  - w < 80: a monogram. The initial at 0.6h, centred, and a 1 px rule 0.4w wide at 0.82h.
  - w < 40: the initial only.
- **Finish:** the shared hinge overlay and inner stroke (§5), so it matches real covers.

## 10. App icon

The canvas is 1024×1024 with no text. The motif is a leaf whose stem is a bookmark ribbon. The geometry is identical in every variant:

```
ribbon:     M482 600 H542 V900 L512 866 L482 900 Z          (drawn first, behind)
leaf left:  M512 140 A316 316 0 0 0 512 700 Z
leaf right: M512 700 A316 316 0 0 0 512 140 Z
midrib:     line 512,176 → 512,700, stroke 14, round cap, colour = background top
```

| Variant | Background | Leaf left | Leaf right | Ribbon |
|---|---|---|---|---|
| Light | linear, top `#F6F1E8` → bottom `#EAE2D4` | `#2F5D4E` | `#3E6B4F` | `#B23F2C` |
| Dark | linear, top `#221E19` → bottom `#141210` | `#6F9A7C` | `#8DBB98` | `#E0694F` |
| Tinted | `#000000` | `#A6A6A6` | `#E6E6E6` | `#737373` |
| Watch | flat `#1E3326` | `#DCD2C1` | `#F1EADC` | `#E0694F` |

- **Watch layout:** the group is wrapped in `translate(512 512) scale(0.82) translate(-512 -520)` so it clears the circular mask. The midrib is `#1E3326`.
- **Small sizes:** at 29 pt it still reads as a two-tone green lens with a red tail.

## 11. Voice and strings

- **Voice:** warm, brief and specific, like a good editor's margin note.
- **Do:**
  - Lead with minutes and pages.
  - Use the book's title, in italics where the style allows.
- **Don't:**
  - Use exclamation marks.
  - Guilt anyone, use streak threats or say "Oops".
  - Write "Click".
- **Typography:** use real en dashes for ranges ("pp. 142–158") and curly quotes.

| Key | String |
|---|---|
| greeting.morning (5–11) | "Good morning." |
| greeting.afternoon (12–16) | "Good afternoon." |
| greeting.evening (17–21) | "Good evening." |
| greeting.late (22–4) | "Still up?" |
| notif.daily | "{minutes} minutes of {title} today — about pp. {pages}." |
| notif.sideBySide | "{minutes} minutes today, starting with {title}, pp. {pages}." |
| notif.nearlyDone | "{pages} pages left in {title}. You could finish today." |
| notif.goalMet (from watch) | "That's today's {minutes} minutes. Anything more is a gift." |
| today.done | "Today's reading is done. Anything more is a gift." |
| today.rest | "A rest day. Nothing's scheduled — read anyway if you like." |
| today.empty | "An empty issue. Add a book and Leaf will plan the pages." |
| streak.new | "A new run starts today." |
| plan.empty | "Nothing to plan yet. Add a book and Leaf will set the dates." |
| search.none | "Nothing matches “{query}”. Add it by hand?" |
| session.goal | "Goal met. Keep going if the chapter's good." |
| outcome.faster | "You're reading a little faster: {wpm} words a minute." |
| finished.next | "{title} begins tomorrow." |
