# Canopy: Leaf's design system

Status: Phase 1 (2026-10-21). This replaces the old paper-and-ink system, which is kept for reference in
`docs/design/legacy/DESIGN_SYSTEM_v1.md` until every screen has moved over in Phase 2.
Code: `Leaf/DesignSystem/Canopy/`. Gallery: `-LeafScreen gallery.canopy` (also `.components`, `.today`, `.plan`).
The redesign itself (IA, screens, haptics, icon) is in `docs/design/REDESIGN.md`.

## 1. The feel

**Minimal, clean, cozy.** A reading nook with the clutter taken out: deep forest green, a clean cream, soft lamplight
on glass.

- **Minimal:** one obvious action per screen, few things at once, generous space. Nothing decorative that needs
  explaining.
- **Clean:** a clean cream (warm off-white, never the old yellow wash), crisp type, big legible numbers, nothing
  sits blurred.
- **Cozy:** deep forest green as the brand, warm lamplight glows behind the glass, New York serif for books, soft
  haptics, a cup of tea one tap away.

If a screen needs explaining, it is redesigned, not annotated. No coach marks, no tours.

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

Deep forest green on a clean cream; dark mode turns it around into cream on a forest night. Three supporting accents
each have one job. Hex values are light / dark.

### Neutrals

| Token | Light | Dark | Use |
|---|---|---|---|
| `Canopy.canvas` | `#F5F1E8` cream | `#0E1813` forest night | Every screen's base, under the backdrop glow |
| `Canopy.surface` | `#FCFAF5` | `#172520` | Opaque stand-in for glass under Reduce Transparency; list cells |
| `Canopy.text` | `#16211B` | `#F3EEE2` | Titles, body, numerals (14.7:1 / 15.7:1) |
| `Canopy.textSecondary` | `#5B675F` | `#AEB9B0` | Authors, captions, meta (5.3:1 / 9.0:1) |
| `Canopy.textTertiary` | `#7A847D` | `#7C8A81` | Large or non-text only: placeholders, units beside big numerals |
| `Canopy.separator` | `#E4DED1` | `#22332A` | Hairlines, progress tracks |
| `Canopy.hero` | `#000000` | `#000000` | The Hero button, in both modes (a specular rim lifts it off the forest night) |

### Accents (each has `.color`, `.soft` for tints and fills, `.glow` for the backdrop)

| Accent | Light | Dark | Job | Examples |
|---|---|---|---|---|
| **Forest** (primary) | `#1F4D36` | `#93CFA9` | Brand, selection, growth: progress, done, goals, streaks | Tab tint, toggles, progress bars, "Done", goal ring, labels |
| **Dusk** | `#46559A` | `#A9B5F2` | Reading and time: sessions, reading times, timers, "now" | Slot times, session ring, Live Activity, next-up dot |
| **Clay** | `#A44A28` | `#EB9C74` | Tea: steeping, cabinet, caffeine; also the lamplight glow | Steep ring, tea chips, "Steep and read" icon |
| **Bloom** | `#963B62` | `#E79BBB` | Memories and insights: journal, quotes, challenges, stamps, year in books | Quote cards, challenge rings, insight highlights |

All text tokens and accents pass 4.5:1 on `canvas` and `surface` in both modes (Clay light is the tightest at 5.2:1).
Supporting accents are muted on purpose so the green leads. An accent never floods a screen; it is a word, a ring, a
chip, a glow.

### Backdrop

Glass needs something to bend. `CanopyBackdrop(_ accent:)` paints `canvas` plus two large, very soft, static glows:
the screen's accent top-leading (10% light, 20% dark) and a second one bottom-trailing (6% / 10%): Clay lamplight on
Forest screens, Forest elsewhere. Pre-rendered gradients, not a live blur, so it costs nothing. Today, Library and You
use Forest (so they get the warm lamp corner), the session uses Dusk, Tea uses Clay, insights use Bloom. Under Reduce
Transparency the glows halve.

## 4. Type

Dynamic Type everywhere; every style is built on a text style so it scales.

| Style | Face | Base | Use |
|---|---|---|---|
| `.display` | New York, semibold | 34 (largeTitle) | Today's greeting, a finished book's title |
| `.title` | SF Pro, bold | 28 (title) | Screen titles inside content |
| `.bookTitle` | New York, semibold | 22 (title2) | Book titles on cards and detail |
| `.headline` | SF Pro, semibold | 17 | Card titles, row titles, buttons |
| `.body` | SF Pro | 17 | Running text |
| `.callout` | SF Pro | 16 | Card supporting lines |
| `.caption` | SF Pro, medium | 13 (footnote) | Meta, authors on small rows |
| `.label` | SF Pro, semibold | 13 (footnote) | Section labels, in the section's accent. Sentence case, never all caps |
| `.timer` | SF Pro Rounded, semibold, monospaced digits | 76 | Session and steep timers |
| `.stat` | SF Pro Rounded, semibold, monospaced digits | 34 | Minutes today, pages, streak |
| `.statSmall` | SF Pro Rounded, semibold, monospaced digits | 20 (title3) | Numbers inside rows and chips |
| `.quote` | New York, regular italic | 20 (title3) | Journal quotes |

Instrument Serif retires. Numbers use `contentTransition(.numericText())` when they change.

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
| `CanopyGallery` | Foundations, components, and Today and Plan mock-ups on the real tokens |

## 11. Accessibility

- Contrast: every text token and accent passes 4.5:1 on `canvas` and `surface` (checked, see §3).
- Dynamic Type up to AX5; numerals scale with `@ScaledMetric` and use `minimumScaleFactor(0.6)` only on timers.
- VoiceOver: timers read as sentences ("12 minutes left"), slot rows as "7:30 AM, Circe, pages 142 to 158".
- Every gesture (swipe to swap, long-press) has a visible button too.
- Reduce Motion, Reduce Transparency and Increase Contrast are each handled by the tokens, not by screens.
