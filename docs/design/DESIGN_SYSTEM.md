# Canopy: Leaf's design system

Status: Phase 1 (2026-10-21). This replaces the old paper-and-ink system, which is kept for reference in
`docs/design/legacy/DESIGN_SYSTEM_v1.md` until every screen has moved over in Phase 2.
Code: `Leaf/DesignSystem/Canopy/`. Gallery: `-LeafScreen gallery.canopy` (also `.components`, `.today`, `.plan`).
The redesign itself (IA, screens, haptics, icon) is in `docs/design/REDESIGN.md`.

## 1. The feel

**Minimal, clean, cozy, and still Leaf.** Revision 2 (2026-10-22) evolves the live app instead of replacing it: the same
masthead, Instrument Serif greetings, New York book titles, cover and cup, and the Steep / Begin pair, on a brighter,
cleaner cream with the amber wash removed. Cream is the page; green is the ink you act with (labels, links, progress,
toggles), never a big fill; black is the one hero button.

- **Minimal:** one obvious action per screen, few things at once, generous space.
- **Clean:** a clean cream page, crisp type, nothing sits blurred, no bokeh or amber glow.
- **Cozy:** the live app's editorial voice, the teacup, soft haptics, warm ink instead of pure black text.

If a screen needs explaining, it is redesigned, not annotated. No coach marks, no tours. The one exception, at the
owner's request (2026-10-23), is a first-use tip (§12): a short glass note beside one thing worth knowing, the first
few times a reader reaches that part of the app.

## 2. The one rule set

Every screen follows these, in this order.

1. **One hero per screen.** At most one black Hero button. Everything else is glass.
2. **Glass is the default material.** Chrome, cards, buttons, chips, sheets, timers, controls: glass. Opaque fills are
   only for the Hero (black), book covers, and charts' data marks.
3. **Colour means a job.** An accent is only used for its job (see §3). Text is neutral unless it *is* a status.
4. **Blur is a moment, not a state.** Things may arrive blurred and resolve to sharp (Focus In, 0.5 s). Nothing
   stays blurred: not a timer, not a number, not a background behind a sheet. Decorative steam is the only soft thing
   that persists, and it carries no information.
5. **Numbers are rounded, words are plain, titles are literary.** SF Pro Rounded for numerals, SF Pro for UI, New York
   for book titles, greetings and quotes only.
6. **Depth by disclosure.** Level 0 answers "what now?", level 1 answers "how is it going?", level 2 holds the rich
   stuff. Never put level 2 on a level 0 surface.
7. **Every meaningful touch has a named haptic** from the map (`CanopyFeel`). No ad-hoc generator calls in screens.
8. **Light and dark are designed together.** Every token has both. Reduce Transparency swaps glass for `surface`;
   Reduce Motion swaps Focus In for a crossfade.

## 3. Colour

Cream is the page, green the ink you act with. Three candidate palettes are built in for the owner to choose from
(`CanopyPalette`). **The owner chose Oat (2026-10-22)**, now the default; `-CanopyPalette linen|ivory` for screenshots). Only the neutrals and the green differ.
Hex values are light / dark.

| Token | Linen | **Oat (chosen)** | Ivory |
|---|---|---|---|
| `canvas` (the page) | `#FAF6EE` / `#161513` | `#F5EFE4` / `#1B1916` | `#FCFBF7` / `#121413` |
| `surface` (cards) | `#FFFDF9` / `#211F1C` | `#FCF8F1` / `#26231F` | `#FFFFFF` / `#1C1F1D` |
| `text` (warm ink) | `#1F1C17` / `#F4EDDF` | `#24201A` / `#F2EADA` | `#1A1D1B` / `#F1EEE6` |
| `textSecondary` | `#625C52` / `#B8AF9F` | `#665F54` / `#B5AB99` | `#5D625E` / `#AEB2AD` |
| `textTertiary` (non-text) | `#8B8478` / `#857D70` | `#8C8478` / `#847B6E` | `#878C88` / `#7E837F` |
| `separator` | `#E8E1D4` / `#34302A` | `#E5DCCB` / `#3A352E` | `#ECEAE3` / `#2C302D` |
| **Forest** (the green) | `#3A6A4F` / `#9CC8A9` | `#48705A` / `#A9CDB2` sage | `#2C5A43` / `#8FC2A2` pine |

Dark mode is a warm charcoal with cream text, not green. `hero` is black in both modes.

Supporting accents, same in every palette, used small (a word, a ring, a chip):

| Accent | Light | Dark | Job |
|---|---|---|---|
| **Dusk** | `#46559A` | `#A9B5F2` | Reading and time: sessions, reading times, timers |
| **Clay** | `#A44A28` | `#EB9C74` | Tea: steeping, cabinet, caffeine |
| **Bloom** | `#963B62` | `#E79BBB` | Memories and insights: journal, quotes, challenges |

Every text token and accent passes 4.5:1 on its canvas and surface in both modes (Oat's sage is the tightest at 4.9:1).

### Backdrop

`CanopyBackdrop` is the cream canvas with a soft daylight fall from the top (white on cream, a faint lift at night)
and the faintest tint of the screen's accent low down. No amber, no bokeh. Glass cards carry a cream tint so the cream
reads clearly through them.

## 4. Type

Kept from the live app: Instrument Serif for greetings and big numbers, New York for books, quotes and timers, SF Pro
for everything you operate. Dynamic Type everywhere.

| Style | Face | Use |
|---|---|---|
| `.eyebrow` | SF Pro semibold, caption 2, uppercase, tracked | The masthead date line |
| `.display` | Instrument Serif 52 | Today's greeting ("Evening hush.") |
| `.subline` | Instrument Serif Italic 24 | The greeting's second line |
| `.title` | SF Pro bold, title | Titles inside content |
| `.bookTitle` | New York semibold, title 2 | Book titles |
| `.headline` / `.body` / `.callout` | SF Pro | Rows, buttons, running text |
| `.caption` / `.label` | SF Pro footnote | Meta; section labels in green |
| `.timer` | New York light 80, monospaced digits | Session and steep timers |
| `.stat` | Instrument Serif 36 | Minutes today, pages, streak |
| `.quote` | New York italic | Journal quotes |

## 5. Space and shape

- 4 pt grid: `Canopy.Space` `xxs 2, xs 4, s 8, m 12, l 16, xl 24, xxl 32, xxxl 48`. Screen margin 20. Card padding 20.
  Gap between cards 16. Gap between sections 32.
- Radii (`Canopy.Radius`), continuous corners: `chip` capsule, `control 16`, `card 28`, `sheet 36`, `cover 6`.
  Cards nest: an inner element's radius is the card's radius minus its inset (28 − 12 = 16).
- Hit targets at least 44 × 44. Hero and primary glass buttons are 56 tall; compact glass buttons 44.

## 6. Materials: Liquid Glass

| Tier | API | Where |
|---|---|---|
| System chrome | automatic (iOS 26) | Tab bar, toolbars, navigation bars, sheets, menus, the session accessory |
| Card glass | `.canopyCard()` = `.glassEffect(.regular, in: .rect(cornerRadius: 28))` | Every content card |
| Accent glass | `.canopyGlass(.dusk)` = `.regular.tint(accent.soft).interactive()` | Slot rows, tea chips, timer housings |
| Control glass | `.buttonStyle(.glass)` / `CanopyGlassButton` | Secondary buttons, icon buttons, steppers |
| Hero | `CanopyHeroButton` | Black fill under `.regular.tint(.black).interactive()` glass, white label, specular rim |

Rules:
- Group neighbouring glass controls in a `GlassEffectContainer` so they merge and morph.
- Glass on glass is allowed only for controls inside a card (they use control glass, never card glass).
- Sheets use system glass with a `.medium` detent first; content inside them is plain text and glass controls.
- Under Reduce Transparency every tier becomes `surface` with a 1 pt `separator` border; the Hero stays black.

## 7. Iconography

- SF Symbols only, `.hierarchical` rendering, medium weight, tinted with the job's accent when they carry meaning,
  `textSecondary` otherwise.
- Fixed vocabulary, one symbol per idea: reading `book.pages`, start `play.fill`, pause `pause.fill`, finish
  `checkmark`, reading time `clock`, today `sun.max`, plan `calendar`, library `books.vertical`, you `person.crop.circle`,
  tea `cup.and.heat.waves`, steep timer `timer`, swap book `arrow.triangle.2.circlepath`, add `plus`, journal
  `quote.bubble`, insights `chart.bar`, challenge `rosette`, settings `gearshape`.
- Symbol effects carry state: `.bounce` on start, `.replace` for play/pause, `.pulse` only while a timer is
  finishing its last 3 seconds.

## 8. Motion

| Token | Value | Use |
|---|---|---|
| `Canopy.Motion.snappy` | `.snappy(duration: 0.28)` | Controls, toggles, chips, selection |
| `Canopy.Motion.smooth` | `.smooth(duration: 0.42)` | Layout changes, cards appearing, reorders |
| `Canopy.Motion.bouncy` | `.bouncy(duration: 0.5, extraBounce: 0.08)` | Celebrations only: goal met, book finished |
| `Canopy.Motion.focusIn` | 0.5 s, blur 12 → 0, opacity 0 → 1, scale 1.04 → 1 | Things arriving: a timer starting, "Ready", sheet content, a swapped book |

**Focus In** is the brand's signature: something soft resolves to crystal clear. It always ends sharp. It is a
transition (`.canopyFocusIn` / `.transition(.canopyFocusIn)`) or a one-shot on a value change (`.canopyFocusIn(on:)`),
never a resting modifier. Reduce Motion: a 0.2 s crossfade.

Navigation uses zoom transitions from the tapped card (cover into book, Hero into session).

## 9. Haptics

Haptics are part of the brand. Screens call `CanopyFeel.play(.moment)`, never a generator. The full map, with patterns,
is in `docs/design/REDESIGN.md` §6; the enum lives in `Leaf/DesignSystem/Canopy/CanopyFeel.swift` and plays through
`Haptics.shared`, which still follows Settings → Feel (full, light, off).

## 10. Components (`Leaf/DesignSystem/Canopy/`)

| Component | What it is |
|---|---|
| `CanopyBackdrop` | Screen base: canvas + accent glows. `.canopyBackdrop(.dusk)` |
| `CanopyCard` / `.canopyCard()` | Glass card with 20 pt padding and an optional label row |
| `CanopyHeroButton` | The one black glass action. Plays `.sessionStart` (or its own moment) |
| `CanopyGlassButton` | Secondary glass action, optional accent icon, regular or compact |
| `CanopyIconButton` | Round glass icon button, 44 pt |
| `CanopyChip` | Glass capsule chip, selectable, accent-tinted when selected |
| `CanopyLabel` | Section label: accent-coloured, sentence case, optional trailing link |
| `CanopyProgressBar` | Forest bar on a separator track, rounded |
| `CanopyRing` | Progress ring in any accent, with an optional centre numeral |
| `CanopyStat` | Big rounded numeral with a unit and a caption |
| `CanopyTimerText` | The timer numeral: rounded, monospaced, numeric-text roll, Focus In on start, never blurred |
| `CanopySlotRow` | A reading time: time chip (Dusk), cover, title, pages; swap and time actions |
| `CanopyBookRow` | Cover, title (New York), author, progress |
| `NookSceneBackdrop` | The session's scene. Plain (default) is the Dusk backdrop. The others sit outside the chrome and are exempt from Canopy's no-blur/no-glow rules (owner, 2026-10-22): realistic rain on a window, fireplace and mountains (Metal shaders compiled at run time, `NookShaders.swift`), and soft glow, mist and drizzle. They turn the session dark, hold still when paused, under Reduce Motion, Low Power and in the background. Picked in `NookSceneSheet` or Settings; pictures only, never a sound |
| `CanopyTip` | A first-use note: accent-tinted glass with a pointer toward what it's about, a symbol, a title, a line and a close button (§12) |
| `CanopyGallery` | Foundations, components, and Today and Plan mock-ups on the real tokens |

## 11. Accessibility

- Contrast: every text token and accent passes 4.5:1 on `canvas` and `surface` (checked, see §3).
- Dynamic Type up to AX5; numerals scale with `@ScaledMetric` and use `minimumScaleFactor(0.6)` only on timers.
- VoiceOver: timers read as sentences ("12 minutes left"), slot rows as "7:30 AM, Circe, pages 142 to 158".
- Every gesture (swipe to swap, long-press) has a visible button too.
- Reduce Motion, Reduce Transparency and Increase Contrast are each handled by the tokens, not by screens.

## 12. First-use tips

The owner asked (2026-10-23) for a walk-through that isn't intrusive: as the reader explores, each part of the app says
the one thing worth knowing there, once. Code: `Shared/FirstUseTips.swift` (the words, the order and the rules, tested on
Linux), `Leaf/Services/FirstUseTipStore.swift` (`FirstUseTips.shared`), `CanopyTip` and `.firstUseTip(_:)`.

| Tip | Where | Points at | Goes for good when |
|---|---|---|---|
| Two ways to begin | Today, under the nook (only when Steep / Begin show) | Steep and read, Begin reading | a session opens |
| Make it your nook | The reading timer, over the extras | Scene, with the sound beside it | the scene or sound sheet opens |
| Your timer keeps going | The reading timer, next visit, in the same spot (clear of the timer) | (no pointer; names the arrow) | the session is tucked away |
| Your reading times | Plan, under today's times | The time chips | a time or a book is changed |
| Add a book | Library, over the shelves | `plus` | Search opens |
| Not on this page? | A book you're reading, over its card | The page chip | "Where are you?" opens |
| Make Leaf yours | You, over the summary | (no pointer) | closed |

Rules:
- **Beside, never over.** A tip sits in the layout next to what it's about, its pointer facing it. Only the reading timer,
  which can't grow, lays its tips over the screen. Nothing dims, nothing waits for a tap, the screen works as normal.
- **One at a time, one per visit.** A place shows its tips in order. Once one is closed, the next waits for the next
  visit rather than popping up in its place.
- **Gone when it's learned.** The close button ends a tip, and so does doing what it says. One the reader ignores shows
  on three launches at most, then stops asking.
- **A beat late.** A tip arrives 0.6 s after its screen, with Focus In, so the screen comes first.
- Dusk for the timer and reading times, Forest otherwise. Settings › About › Show tips again brings them all back;
  Erase all data does too. Screenshot runs show none unless `-LeafTips` names them.

