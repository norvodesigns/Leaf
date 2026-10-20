# Leaf design system — API index

Everything here implements `docs/DESIGN.md` §2–§5, §7 and §9. Feature code uses these and never
re-creates them. Signatures below are exact; defaults are shown. Every component has a `#Preview`;
`DesignSystemGallery` (debug only) shows them all in light and dark.

## Colour — `LeafColor.swift`

Tokens are `Color`s declared on `ShapeStyle where Self == Color`, so all forms work:
`.foregroundStyle(.ink)`, `.fill(.hairline)`, `.tint(.accent)`, `Color.paper`, `Color.ink.opacity(0.12)`.

| Token | Use |
|---|---|
| `.paper` / `.paperRaised` / `.paperSunken` | screen background / tiles, settings rows, lifted row / detail stage, wells, chip fills |
| `.ink` / `.inkSecondary` / `.inkTertiary` | headlines, numerals, body / authors, meta, captions / eyebrows, index numerals, unselected |
| `.inkFaint` | **non-text only**: leader dots, future-day dots, missed rings |
| `.hairline` / `.hairlineStrong` | 1 px rules, tracks / ruler ticks, double-rule top, rest dashes |
| `.accent` / `.accentSoft` | done, sooner, progress, toggles, links / today's span, "sooner" chip |
| `.ribbon` / `.ribbonSoft` | "now" (today marker, caret, live dot, needle, cover ribbon), < 3% of a screen / 0.6 s date flash |
| `.glassTint` | `.glassEffect(.regular.tint(.glassTint).interactive(), in: .capsule)` |
| `.lamp` | session mesh centre point |
| `.coverShadow` | cover shadow base (alpha per use). There is no `.shadow` token. |
| `.teaPaper` `.chai` `.matcha` `.rooibos` `.steam` `.amber` `.rose` | cozy tints, **atmosphere only** (never text, never state): tea rings, steam, lamplight, bokeh, scenes. Light and dark each. |

- `Color(hex: UInt32, opacity: Double = 1)` — `Color(hex: 0xF4EFE6)`.
- `UIColor(hex: UInt32, alpha: CGFloat = 1)`, `UIColor.leafDynamic(light:dark:lightAlpha:darkAlpha:)`.
- `LeafUIColor.paper`, `.ink`, … — the same tokens as dynamic `UIColor`s for UIKit code.
- `CoverPalette(book: Book)` → `.background`, `.foreground`, `.rule` (`Color`), `.name`, `.index`.
  `CoverPalette.all` (10 palettes, §2 order), `CoverPalette.index(for: book)` (= `paletteSeed % 10`).
  Book detail's stage is `BlurredCoverBackdrop(book:)` (see Motion language).
- Destructive actions: system `role: .destructive`, never a custom red.

## Type — `LeafType.swift`

- `LeafType.heroNumeral`, `.countdown`, `.wordmark`, `.timer`, `.display`, `.masthead`, `.statNumeral`,
  `.index`, `.pullQuote`, `.title`, `.headline`, `.body`, `.passage`, `.author`, `.ui`, `.uiBody`,
  `.caption`, `.eyebrow`, `.data` — plain `Font`s (§3). Fonts can't carry tracking/case/colour, so on
  views prefer:
- `view.leafStyle(_ style: LeafTextStyle, color: Color? = nil)` — **the default way to set text.**
  Applies font, tracking, line spacing (`body` 5, `passage` 9), uppercase (`eyebrow`), the spec colour,
  `lineLimit(1)` + `minimumScaleFactor(0.5)` (`heroNumeral`, `timer`), and the accessibility2 Dynamic
  Type cap (`display`, `masthead`, `statNumeral`). Spec colours: `caption`/`author` → `inkSecondary`,
  `eyebrow`/`index` → `inkTertiary`, everything else → `ink`. Override with `color:` — an outer
  `.foregroundStyle` will **not** override it.
  `Text("This week").leafStyle(.eyebrow)` · `Text(title).leafStyle(.headline).lineLimit(2)` ·
  `Text("12:04").leafStyle(.timer, color: isPaused ? .inkTertiary : .ink)`
- `view.leafFont(_ style:)` — same, but leaves colour to the outside `.foregroundStyle`.
- `text.leafText(_ style:, color: Color? = nil) -> Text` — font + tracking + colour as a `Text`, for
  styled runs inside one `Text`: `Text("of \(Text(title).leafText(.title).italic())")`. No case/spacing.
  (Prefer interpolating `Text` runs over `Text + Text` concatenation.)
- `LeafTextStyle` cases: the same 19 names as `LeafType`. Properties: `font`, `tracking`, `lineSpacing`,
  `isUppercase`, `defaultColor`, `capsDynamicType`, `lineLimit`, `minimumScaleFactor`.
- `LeafFontName.regular` / `.italic` — "InstrumentSerif-Regular" / "InstrumentSerif-Italic".
- Pass eyebrow strings in sentence case ("This week"): they're uppercased on screen and VoiceOver
  reads them as words. Book titles in running text: add `.italic()`.

## Space, shape, rules — `Layout.swift`

- `Space.xxs 2`, `.xs 4`, `.s 8`, `.m 12`, `.l 16`, `.xl 20`, `.xxl 28`, `.xxxl 40`, `.section 56`;
  `Space.margin 20` (side margin), `.sectionGap 40`, `.hitTarget 44`.
- `view.leafMargins()` — `.padding(.horizontal, Space.margin)`.
- `Radius.coverSmall 2` (XS, S), `.cover 3` (M+), `.tile 16`, `.card 22`, `.panel 32`;
  `Radius.shape(_ r: CGFloat) -> RoundedRectangle` (continuous). Buttons, chips, accessory: capsules.
- `Hairline(color: Color = .hairline, axis: Axis = .horizontal)` — a true 1 px rule.
- `DoubleRule()` — 1 pt `hairlineStrong`, 2 pt gap, 1 px `hairline` (Today's dateline).

## Elevation — `Elevation.swift`

- `view.coverShadow(_ size: BookCover.Size)` — the two-layer cover shadow (ambient 0.5 in dark).
  `BookCover` already applies it.
- `view.liftedRow(_ isLifted: Bool, cornerRadius: CGFloat = Radius.tile)` — scale 1.03, `paperRaised`,
  lifted shadow, `zIndex` 1. Animate with `Motion.paper`.

## Paper & appearance

- `view.paperBackground(_ color: Color = .paper)` — paper behind the view, ignoring safe areas. Put it on
  each screen's root (inside the `NavigationStack`). For `Form`/`List` also `.scrollContentBackground(.hidden)`.
- `PaperBackground(_ color: Color = .paper)` — the same as a view.
- `LeafAppearance.configure()` — called by `LeafApp.init`. Large nav titles = `masthead` (Instrument
  Serif 40, `UIFontMetrics` scaled), inline titles = New York 17 semibold, both `ink`; system bar
  backgrounds untouched. `LeafAppearance.newYork(size:weight:) -> UIFont`.

## Motion — `Motion.swift` (§7)

Animations (`Animation`): `Motion.paper`, `.board`, `.glass`, `.inkIn`, `.strike`, `.ruleDraw` (has its
0.3 s delay), `.breathe`, `.inkBleed`, `.theEndTitle` (0.4 s at +0.3 s), `.coverFade`, `.fade` (the
Reduce Motion crossfade, 0.2 s).
Constants: `inkInStagger 0.05`, `inkInRise 8`, `inkInMaxItems 6`, `countUpDuration 1.2`,
`breathePhases [1, 0.55]`, `inkBleedBlur 8`, `reflowStagger 0.045`, `reflowFlashDuration 0.6`,
`countdownScale 1.15`, `deltaChipDuration 2.5`.

- `Motion.resolved(_ animation:, reduceMotion: Bool) -> Animation` — use with
  `@Environment(\.accessibilityReduceMotion)`: `withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) { … }`.
- `Motion.animate(_ animation:, _ body:)` — `withAnimation` that checks Reduce Motion itself (main actor).
- `Motion.transition(_ t: AnyTransition, reduceMotion: Bool) -> AnyTransition` — `.opacity` under Reduce Motion.
- `Motion.stagger(_ index: Int, step: = 0.05) -> TimeInterval` — capped after 6 items.
- `Motion.countUpProgress(_ t: Double) -> Double` — ease-out cubic for the WPM count-up (`TimelineView`).
- `view.leafAnimation(_ animation:, value:)` — `.animation(_:value:)` that crossfades under Reduce Motion.
- `view.inkIn(_ index: Int = 0)` — screen entrance (fade + 8 pt rise, staggered). ≤ 6 top-level blocks, not lazy rows.
- `view.inkBleed(delay: TimeInterval = 0)` — welcome wordmark (blur 8→0, fade in, 1.2 s).
- `view.breathing(_ isActive: Bool = true)` — 1 ↔ 0.55 opacity loop; off under Reduce Motion.
- `view.reflowFlash(trigger: some Equatable, delay: TimeInterval = 0)` — 0.6 s `ribbonSoft` flash behind
  a date when `trigger` changes. Stagger rows: `delay: Motion.reflowStagger * Double(row)`.
- `view.ribbonSway(trigger: some Equatable)` — the §7 keyframes (rotation about the top edge), for
  a flat ribbon-like view. Cover ribbons are `PhysicalRibbon`s now.
- Transitions: `.transition(.inkIn)`, `.transition(.rise())` / `.rise(12)` (onboarding steps),
  `.transition(.countdownNumeral)`, `.transition(.deltaChip)`.
- Strike / rules: draw with `.trim(from: 0, to: drawn ? 1 : 0)` animated by `Motion.strike` /
  `Motion.ruleDraw`; under Reduce Motion set `drawn = true` without animation.
- Numbers: `.contentTransition(.numericText(value: Double(n)))` + `.leafAnimation(Motion.paper, value: n)`.

## Covers — `BookCover.swift`, `GeneratedCover.swift`

- `BookCover(book: Book, size: BookCover.Size, ribbon: Bool = false, swaysRibbon: Bool = false, ribbonTucked: Bool = false)`
  (also `BookCover(_ book:, size:, …)`). Generated cover underneath, Open Library scan (`?default=false`,
  `.large` for L/XL) fading in over 0.3 s, bad-scan handling, hinge finish, inner stroke, shadow.
  VoiceOver: "Cover of {title} by {author}". `ribbon` draws on M+ and hangs `size.ribbonTail` (0.12 h)
  **below** the frame — leave room. The ribbon is a `PhysicalRibbon`: it follows tilt and can be tugged.
  `swaysRibbon` sways it on appearance and lets it breathe a little before it sleeps (Today hero);
  `ribbonTucked` pulls it up behind the cover (a finished book).
  The frame is exactly the cover, so zoom straight from it:
  `BookCover(book: b, size: .m).matchedTransitionSource(id: b.id, in: ns)` and
  `BookDetailView(book: b).navigationTransition(.zoom(sourceID: b.id, in: ns))`.
- `BookCover.Size`: `.xs` 24×36 (accessory), `.s` 44×66 (rows), `.m` 96×144 (shelves, carousels),
  `.l` 140×210 (Today hero, finished), `.xl` 200×300 (detail). Properties: `width`, `height`,
  `dimensions: CGSize`, `cornerRadius`, `allowsRibbon`, `ribbonTail`, `ambientShadow`, `imageSize`.
- `BookCover.imageURL(for: Book, size: BookCover.Size) -> URL?` — the exact scan URL.
- `CoverImageCache.shared.cachedImage(for: URL) -> UIImage?` / `await CoverImageCache.shared.image(for: URL) -> UIImage?`
  — the shared, validated scan cache (Book detail can use it for its `CIAreaAverage` stage colour).
- `GeneratedCover(book: Book, showsFinish: Bool = true)` (also `GeneratedCover(_ book:)`) — §9 typeset
  cover; fills the 2:3 frame you give it. For a live preview of a draft book (AddBookManuallyView) prefer
  `BookCover(book: draft, size: .l)`, which shows the generated cover (no `coverID`) with shadow.
- `CoverFinish(cornerRadius:)` — the hinge overlay + inner stroke, if you ever build a cover-like surface.

## Progress

- `ProgressBar(progress: Double, tint: Color = .ink, height: CGFloat = 2)` (also `ProgressBar(_ progress:)`) — rows.
- `PageSpanBar(current: Int, todayTo: Int, total: Int)` — 12 pt tall, full width. Read = ink, today's
  span = `accentSoft` + `accent` stroke, `ribbon` caret at `current`; all `accent` when `current >= total`.
  Pass `todayTo: current` when nothing is scheduled.
- `ProgressRing(progress: Double, diameter: CGFloat, lineWidth: CGFloat, showsHead: Bool = false, tint: Color = .accent, label: String = "Today's reading")`
  — `ProgressRing.accessory(progress:, tint: = .accent)` (22/2.5), `ProgressRing.session(progress:, tint:)`
  (300/4 with the `ribbon` head). Overlay the timer or a `checkmark` with `.overlay { … }`.
  Goal met in session: keep progress at 1 and tint the timer `accent`.

## Buttons — `PrimaryGlassButton.swift`, `GlassIconButton.swift`, `ButtonStyles.swift`

- `PrimaryGlassButton(_ title: String, systemImage: String? = nil, isLoading: Bool = false, playsHaptic: Bool = true, action: @escaping () -> Void)`
  (also `title:` label). `.glassProminent` tinted `ink`, `paper` semibold label, 54 pt (scaled), full
  width, `press()` haptic, 40% when `.disabled(true)`, spinner when loading. **One per screen.**
  Pass `playsHaptic: false` when the action plays a signature haptic (e.g. "Save page" → `pageTurn`, "End" → `soft(0.5)`).
- `SecondaryGlassButton(_ title: String, systemImage: String? = nil, compact: Bool = false, playsHaptic: Bool = true, action:)`
  (also `title:`). `.glass`, `ink` label, 54 pt (44 compact), full width, `tap()` haptic.
  Side by side: wrap in `GlassEffectContainer(spacing: 12)` (session: 20) and an `HStack`. Morph with
  `.glassEffectID("pause", in: ns)` applied from outside.
- `GlassIconButton(systemImage: String, label: String, diameter: CGFloat = 44, playsHaptic: Bool = true, action:)`
  — round vellum glass icon (`label` is the VoiceOver label). Keeps a 44 pt hit area at 36 pt.
- `GlassIcon(systemImage: String, diameter: CGFloat = 44)` — the visual only, e.g. as a `Menu` label:
  `Menu { … } label: { GlassIcon(systemImage: "plus", diameter: 36) }.accessibilityLabel("Add")`.
- **Toolbars:** items already sit on system glass — use a plain `Button { } label: { Image(systemName: "gearshape") }`
  with `.accessibilityLabel`, and play `Haptics.shared.tap()`. Don't nest `GlassIcon` there.
- `.buttonStyle(.pressable)` (`PressableButtonStyle`) — dims to 55% while pressed. Rows, covers, links on paper.
- `TextButton(_ title: String, style: LeafTextStyle = .ui, color: Color = .accent, action:)` — text link
  ("Change", "Retake") with a 44 pt hit area.

## Headers, labels, chips

- `SectionHeader(_ eyebrow: String, style: SectionHeader.Style = .single, topSpacing: CGFloat = Space.xxxl, actionTitle: String? = nil, action: (() -> Void)? = nil)`
  (also `eyebrow:` label). Eyebrow + optional trailing `caption` action + rule; 40 above (`topSpacing`),
  12 below. `.double` uses the double rule. `SectionHeader("Under four hours at your pace", actionTitle: "See all") { … }`.
  Use `topSpacing: 0` for a screen's first header.
- `Eyebrow(_ text: String, color: Color? = nil)` — an eyebrow `Text`.
- `IndexNumeral(_ number: Int)` — "01" in `index` `inkTertiary`, min 40 pt wide.
- `LeaderDots()` — 2 pt `inkFaint` dots every 6 pt, flexible width; put it in an
  `HStack(alignment: .firstTextBaseline)` between title and date. Hidden from VoiceOver.
- `Chip(_ text: String, systemImage: String? = nil, tone: Chip.Tone = .neutral)` — 22 pt capsule,
  `caption` semibold. Tones `.neutral` (inkSecondary/paperSunken), `.accent` (accent/accentSoft),
  `.ribbon` (ribbon/ribbonSoft).
- `DeltaChip(daysSooner: Int)` or `DeltaChip(from oldFinish: Date, to newFinish: Date)` — "6 days sooner"
  (accent) / "4 days later" (neutral); draws nothing for 0. `DeltaChip.text(daysSooner:)` for the string.
  Show for `Motion.deltaChipDuration` with `.transition(.deltaChip)`.

## Tiles & empty states

- `StatTile(value: String, label: String)` (also `StatTile(_ value:, label:)`) — `statNumeral` over an
  eyebrow on `paperRaised`, 1 px stroke, `Radius.tile`, min 84 pt. Label in sentence case ("At your pace").
- `StatTileRow { StatTile(…); StatTile(…); StatTile(…) }` — equal widths and heights, 8 pt gaps; stacks
  vertically at accessibility sizes.
- `EmptyState(title: String, message: String, actionTitle: String? = nil, prominent: Bool = false, action: (() -> Void)? = nil)`
  (also `EmptyState(_ title:, message:, …)`). "❦", `masthead` title, `body` message (max 300 pt), 56 pt
  vertical padding. The button is a compact secondary, or a `PrimaryGlassButton` when `prominent: true`.
  Pass `message: ""` for a title-only state.

## Dials & pickers

- `MinutesDial(minutes: Binding<Int>)` — 5–180; `heroNumeral` readout with `numericText`, "MINUTES A
  DAY", tick ruler (spacing 8, major 5, labels 15/30/45/60/90/120/180). Haptics: `selection` per
  minute, `dialDetent` per 5, `rigid(0.8)` on labels. VoiceOver ±5. `MinutesDial.range`, `.labelled`.
- `PageScrubber(page: Binding<Int>, range: ClosedRange<Int>, estimate: Int?)` — start page…page count,
  spacing 10, major 10, labels every 50, `ribbon` "est." over `estimate`. No readout: show the page in
  `heroNumeral` above it. Haptics: `selection` per page, `dialDetent` per 10. VoiceOver ±1.
  `range` must be valid (`lower <= upper`); clamp `page` into it before showing.
- `TickRuler(range: ClosedRange<Int>, value: Binding<Int>, spacing: CGFloat = 8, majorEvery: Int = 5, labels: Set<Int> = [], estimate: Int? = nil, rigidAtLabels: Bool = false, voiceOverLabel: String = "Value", adjustStep: Int = 1, valueDescription: @escaping (Int) -> String = { "\($0)" })`
  — the shared ruler (88 pt tall, full width, centre `ribbon` needle, faded edges). `TickRuler.height`.
  Runs on `ScrubController` (flick to coast, rubber band, velocity blur; `estimate` is a magnet, and so are the
  labels with `rigidAtLabels`). Haptics come from `ScrubModel` through `Haptics.shared.scrub(_:)`.
- `WeekdayPicker(selection: Binding<Set<Int>>)` — weekdays 1 = Sun … 7 = Sat, laid out from
  `Calendar.current.firstWeekday`; `masthead` letters, `ribbon` underline, `selection()` haptic, each
  column a toggle ("Monday, reading day"). `WeekdayPicker.orderedWeekdays()` → `[Int]` in display order.
  An empty selection is allowed; the screen disables its button and says "Pick at least one day."
- `ShelfSwitcher(selection: Binding<Shelf>, shelves: [Shelf] = Shelf.main)` — a segmented control over Reading, To
  read and Finished, playing `selection()`; the counts live in the Library's caption line.
  `ShelfSwitcher.title(for: Shelf) -> String` ("Reading", "To read", "Finished", "Set aside").

## Week & plan

- `WeekStrip(days: [DayStat], streak: Int = 0, fillsTodayOnAppear: Bool = false)` — pass `store.week`
  and `store.streak`; the "N reading days in a row" caption appears only when `streak >= 3`. A day reads
  as read at ≥ 1 minute. `fillsTodayOnAppear: true` (session outcome) fills today's marker with
  `Motion.board` after appearing. `WeekStrip.letter(for: Date) -> String`.
- `TimelineScale(start: Date, end: Date)` or `TimelineScale(covering: [PlannedBook], today: Date)` —
  the shared axis (today → a week past the last finish). `fraction(of: Date) -> CGFloat`, `monthStarts() -> [Date]`.
- `TimelineBand(start: Date, finish: Date?, scale: TimelineScale, isReading: Bool)` or
  `TimelineBand(_ planned: PlannedBook, scale:)` — the 6 pt band; `accent` (Reading) / `hairlineStrong`
  (To read); fades out when `finish == nil`. Full width of its column; animate with `Motion.paper`.
- `TimelineGrid(scale: TimelineScale, today: Date = Date())` — month gridlines (hairline 50%) + 1 pt
  `ribbon` today rule. Use as `.background { TimelineGrid(…) }` behind the band column, same insets.
- `TimelineMonthLabels(scale: TimelineScale)` — "NOV", "DEC" eyebrows positioned on the axis.

## Cozy (NEXT.md §6) — `CozyColor.swift`, `TeaCup.swift`, `TeaRingStamp.swift`, `NookAtmosphere.swift`

Warm tints for atmosphere only; ink and the one green accent still do the work, and none of these carries text.

- The tints are `LeafColor` tokens now (`.chai`, `Color.matcha`, `LeafUIColor.amber`); `CozyColor.teaPaper` … `.rose`
  remain as aliases, plus `.teaRing`. `.steam` is a warm grey on light paper, near white at night; `.amber` is the lamp.
  `CozyColor.color(for: CozyPalette.chai)` maps the data layer's tokens; `CozyColor.liquor(for: Tea)` is the tea in
  the cup (fixed colours, like covers).
- `TeaCup(fill: Double, liquor: Color, steams: Bool = false, width: CGFloat = 96)` — an inked cup that fills 0…1 with
  today's minutes; steam (from `AtmosphereField.steam`, 15 fps) when full or while a pot steeps. Hidden from
  VoiceOver: always put the real minutes beside it. `TeaCup.height(for:)`, `TeaCup.steamHeight(for:)`.
- `TeaRingStamp(mark: .read(share) | .rest | .missed | .upcoming, seed: Int, diameter: CGFloat = 38)` — a day as a
  tea ring on the paper; the ring grows with the share of the goal and leaves a drip at 1. No red, ever.
- `TeaRingWeek(days: [DayStat], goalMinutes: Int, streak: Int = 0, cupMinutes: Int = 25)` — the week as rings with
  letters, a `ribbon` underline on today, and the real numbers under it ("2 h 41 min this week · 6 cups").
- `NookAtmosphere(daypart: Daypart)` — the light behind Today's header: window panes in the morning, a warm wash in
  the afternoon, the lamp and a few soft bokeh lights from dusk, a small pool of lamplight late. Fades into paper at
  the bottom. Reduce Transparency → flat tint; Reduce Motion / Low Power / inactive → still.
  `NookAtmosphere.light(for:dark:)` returns the recipe.

## Motion language (UI-3, NEXT.md §7–9)

Blur is for what you feel, crispness for what you act on. Nothing runs a frame when nothing moves: every timeline
pauses when its scene is still, the app is inactive, Reduce Motion is on or Low Power Mode is on.

- **Blur** — `Blur.swift`. `.transition(.focusPull)` / `.focusPullTransition()` (outgoing blurs and drifts back as the
  incoming sharpens; crossfade under Reduce Motion or Reduce Transparency). `.focusPull(isFocused:radius: 6)` keeps a
  view soft while something is in front of it (Today while a book is open). `.numericBlur(value:velocityBlur:)` is
  the big numerals' transition: `numericText` plus a 0.28 s blur-through, and a live smear (≤ 6 pt) while scrubbing.
  `PerDigitBlurText(text:value:)` runs a blur wave across the digits (`DigitBlurRenderer`, a `TextRenderer`).
- **Cover backdrop** — `CoverBackdrop.swift`. `BlurredCoverBackdrop(book:scrim: 0.5)`: paper, a 3×3 `MeshGradient`
  from the cover's colours, the cover pre-rendered once at 60×90 and blurred (Core Image), then a paper scrim that
  reaches full paper at the bottom. Rendered once per cover and cached (`CoverBackdropRenderer.shared`). Flat 18% wash
  under Reduce Transparency. Use it behind a cover-led stage (book detail).
- **Scenes** — `AtmosphereScene.swift`. `AtmosphereScene(kind: .bokeh | .rain | .steam, calm: 0...1, density: 1,
  tint: .amber, seed:)`: a `Canvas` at 15 fps drawn from `AtmosphereField`; as `calm` reaches 0 the clock eases to a
  stop and the timeline pauses. Put it over a background of your own; it is hidden from VoiceOver.
- **Ribbon** — `PhysicalRibbon.swift`. `PhysicalRibbon(length:width:color: .ribbon, seed:breathes:swaysOnAppear:
  isTucked:grabFrom:isInteractive:followsTilt:)`: `RibbonSimulation` drawn as a Catmull-Rom satin strip that tapers to
  a swallowtail, with a highlight from curvature and a soft shadow. Tilt from `RibbonTilt.shared` (Core Motion, 30 Hz,
  only while a ribbon is on screen, published only when gravity really changes). Drag below `grabFrom` to tug it
  (rubber band, a continuous haptic that follows `stretch`), let go to flick. Its timeline stops when the ribbon
  settles. Reduce Motion → `reducedMotionPose`. `PhysicalRibbon.canvasSize(length:width:)` is the room it draws in.
- **Ribbon as progress control** — `RibbonPageControl(page:pages:startPage:)`: the ribbon hangs down a page block as
  thick as the book; drag down the block to set the page (`RibbonDepthMapping`: slow lands on pages, fast snaps to
  round numbers). Typed field and VoiceOver adjustable action always present.
- **Scrub numbers** — `Scrub.swift`, `ScrubVariants.swift`. `ScrubController(configuration:value:)` (observable
  `ScrubModel` with coasting, haptics and blur) drives `ScrubRuler` (the Canvas ruler) and
  `ScrubNumber(value:configuration:caption:numeral:labels:estimate:accessibilityLabel:spoken:adjustSteps:consequence:)`
  — numeral, ruler, a tap-to-type fallback and adjustable VoiceOver. Variants: `MinutesDial`, `PageScrubber` (via
  `TickRuler`), `SteepTimeScrub(seconds:suggested:)`, `FinishByScrub(scrub: DateScrub, offset:magnetOffsets:)` ("About
  N min a day" under the date), `TimeDrum(hour:minute:minuteStep: 5)` built from `DrumWheel`s.
  `.scrubsHorizontally(controller)` adds the gesture to any view.
- **Haptics** — `Haptics.shared.scrub(_ event: ScrubHapticEvent)`, named moments `.magnetSnap`, `.boundsHit`, and the
  continuous stretch `beginStretch()` / `updateStretch(_:)` / `endStretch()`.
- **Gallery** — `MotionGallery(section:)` (debug): `-LeafScreen gallery`, `gallery.palette`, `.blur`, `.scenes`,
  `.ribbon`, `.scrub`, `.drum`; also linked from `DesignSystemGallery`.

## Today, position, reading times, deck (feature components)

- `TodayCard(_ eyebrow:, actionTitle:, action:) { … }` — Today's paper card (`paperRaised`, hairline, `Radius.card`).
- `PageChip(item:, needsPosition:, action:)` — "p. 142 ✎" (or "46%", or a `ribbon` "Where are you?").
- `WhereAreYouSheet(request: PositionRequest, item:, now:)` — presented by `MainTabs` for `router.positionRequest`;
  ask with `router.askPosition(for:then:)`. `ReadingSessionLauncher.start` asks automatically before a book's first
  session (`needsPosition`).
- `ReadingTimesSection()` (a `Form` section), `ReadingSlotEditor(slot:isNew:onSaved:)`, `ReadingTimesSheet()`
  (`router.showReadingTimes`, `router.readingSlotToEdit`).
- `SwipeDeckModel` + `SwipeDeckView(model:style:wpm:height:onBrowse:)` (`.full` drags any way; `.compact` sits in a
  scroll view and only moves sideways), `DeckCommit.connect(model, store:)`, `SwipeDeckScreen()`
  (`router.showDeck`), `TodayDeckCard`, `DeckBanner`.
- Haptics: `.teaReady`, `.deckKeep` (the heavier keeper), `.deckStart`; a pass is `soft(0.45)`, crossing into a
  choice while dragging is `selection()`.

## Session and Live Activity (UI-2)

- `ReadingSessionLauncher.beginRitual(bookID:teaID:store:router:from:)` opens the session screen at the tea
  (`router.ritual`): `SessionRitualView` picks a tea and strength, pours (`TeaSteepState`), counts the steep down with
  digits that come into focus as it gets ready, then starts one cup (`TeaRitual.goalSeconds`). Nothing is counted
  until the cup starts.
- `SessionClock(…, cup:)` counts down the cup for a tea session; today's goal still decides "goal met".
- `AmbienceSheet` (opt-in sounds and volume), `JournalCaptureSheet` (thought or quote, with `QuoteScanSheet` /
  `QuoteScannerView` for Live Text, text only).
- `ReadingActivityModel`, `ReadingActivityLockScreen`, `ReadingActivityCompactLeading/Trailing`,
  `ReadingActivityMinimal`, `ReadingActivityExpanded*`, `ReadingActivityGallery`, `ReadingActivityPalette` (the
  night palette; the activity always sits on a darkened blurred cover).

## Plan: forecast, insights, challenges (UI-4)

The Plan tab is three pages under `PlanSectionSwitcher` (`router.planSection`: `.forecast`, `.insights`,
`.challenges`). `PlanDesk` (Leaf/Services) runs every engine off the main actor once per library change and keeps the
results: `forecast` (`ForecastSnapshot`: result, tonight only, catch-up, stalled books, the year goal's inverse plan),
`insights` (`InsightsSnapshot`), `challenges` (`ChallengeSnapshot`), `backtest`, plus on-demand `runWhatIf`,
`inversePlan(bookID:by:)` and `smartOrder(goal:)`, all with the day seed so differences are the change itself.
Sheets: `router.planSheet` (`.finishLine(bookID:)`, `.smartOrder`, `.yearInBooks`, `.weeklyLetter`);
`router.openWeeklyLetter()` is what the Sunday notification calls.

- **Charts** — `ForecastCharts.swift`, Swift Charts, hidden from VoiceOver behind the narrator's sentence.
  `BookFanChart(forecast:currentPage:pages:narrator:calendar:today:)`: pages over dates, median line, 10–90 fan,
  tap or drag a date for `chanceSentence` (VoiceOver: adjustable by two days). `YearForecastChart(year:finishes:today:calendar:)`:
  the year's finishes as a step, a fan from today to 31 December, dashed median, goal rule. `SpeedTrendChart(trend:)`.
- **Forecast page** — `ForecastPage(desk:)`: year card, a `BookForecastCard` per book in Reading, "For you"
  (`TodayCard` tonight only, `CatchUpCard` with the reader's `CatchUpMode`, `StallCard` → `store.pause`), what-if
  (`MinutesDial`, `WeekdayPicker`, `WhatIfSummary` with `DeltaChip`s; nothing changes until "Keep this plan"),
  the plan as a running order (`PlanRow`, plan style), next seven days, assumptions and the backtest line.
- **Sheets** — `FinishLineSheet(desk:initialBookID:)` (book menu, `FinishByScrub` with magnets at the likely finish,
  Christmas and New Year's Eve, then `inverseSentence` and "Make it N min a day"); `SmartOrderSheet(desk:)` (three
  goals, per-book `DeltaChip`, `store.applyQueueOrder(_:)`).
- **Insights page** — `InsightsPage(desk:)`: `TeaRingHeatmap(cells:calendar:)` (a Canvas, a column per week, rings sized
  by `HeatCell.ring`, gold drop for a finished book, scrolls from today), `YearInBooksCard`, `WeeklyLetterCard`,
  `BestTimeCard`, `SpeedCard`, `MixCard`, `TBRCard`, `PersonalityCard` (shares `PersonalityPoster` as an image).
- **Year in Books** — `YearInBooksView(summary:)` with `MonthRingCollage(months:ringSize:showsLabels:)`, highlights,
  finished list, and a `YearInBooksPoster` share image. Words in `YearInBooksText`.
- **Weekly letter** — `WeeklyLetterView(letter:)`; `WeeklyLetterView.copy(for:calendar:)` maps `WeeklyLetterData` to
  `WeeklyLetterText` with a seed that holds for the week.
- **Challenges page** — `ChallengesPage(desk:)`: `ChallengeProgressCard` (ring, status line, prompts or a bingo card,
  stamps; leave from its menu), `ChallengeOfferCard` (join), `StampWall` of `StampSeal(rings:token:diameter:symbol:isEarned:)`.
- **Share images** — `SharePoster.render(_:size:)` renders any view on paper in the day palette at 3x.
- **Staging** — `-LeafScreen plan`, `plan.whatif`, `plan.care`, `plan.order`, `plan.finishline`, `plan.suggest`,
  `plan.insights` (`.time`, `.mix`, `.personality`), `plan.year`, `plan.letter`, `plan.challenges`, `plan.stamps`;
  `-LeafScenario year` adds a year of reading.

## Search, Library, Settings (UI-5)

- **Search shop** — `SearchShelves.swift`. `SearchShelfKind(collection)` reads a row's style and jump-bar category
  from its id: `.hero` ("Picked for you": L covers with the reason printed), `.series` (`SpineShelf`: spines on a
  shelf, as tall as the book is long), `.author` (`AuthorShelfHeader` monogram), `.time` (reading time on each cover),
  `.seasonal` (tinted panel), `.standard`. `SearchShelfRow` draws any of them with a "See all" link
  (`CollectionGridView`). `SearchCarouselCover(… size:badge:showsReason:)` menus: add, "More like this"
  (`SimilarRoute` → `SimilarBooksView`), "Not for me" (with `UndoToast`). `SearchJumpBar` is pinned over the rows.
  `SearchFrontTableNote` for a reader with no personal rows; `TasteView` (`TasteRoute`) from `TasteProfile`;
  `OpenLibraryCredit` at the foot. Search's path is a `NavigationPath`.
- **Catalog helpers** — `BookCatalog.similar(to:context:limit:)` and `tasteProfile(context:)`, both off the main actor.
- **Book detail** — `BookDetailExtras.swift`: `BookEditionPicker` (from `Book.pageCounts`), `BookJournalList`
  (Sittings | Journal tabs), `BookMoreLikeThis`. The page line honours `ProgressMode`; the page chip is `PageChip`.
- **Library** — `LibraryPausedShelf`, shown as the "Set aside" section at the end of Reading (no fourth segment).
- **Settings** — `SettingsCozy.swift`: `SettingsPlanSection` (missed days, yearly goal, weekly letter),
  `SettingsTeaSection` (favourite tea, strength, cup, ambience and its starting volume, sound cues),
  `SettingsExtrasSection` (Apple Intelligence greetings, Live Activity), `SettingsCloudSection` (status, waiting
  changes, Sync now). `CozySettings` keeps the device-local choices (cues, strength, volume); all quiet by default.
- **Onboarding** — the reminder step is now `OnboardingTimesView` (first reading time on the `TimeDrum`, an optional
  second time); the last step notes iCloud where it is available.
- **Staging** — `search.series|author|time|seasonal|seeall|undo|similar|taste`, `library.paused`,
  `book.journal|more|edition`, `settings.plan|tea|cloud`.

## Books and tea (NEXT.md §6)

- **Pairing** — `TeaPairingSection(book:)` on a book's page: the lead reason as a pull quote, three teas (swatch, name,
  family · steep, "in your cabinet"), and a pin (`ribbon` when pinned) for the book's own tea. The ritual shows
  "Pairs well with this book" (or "Your pairing for this book") above the chips, tap to choose it.
- **Cabinet** — `TeaCabinetView` (a `Form` on paper like Settings): In the cabinet / Run out, swipe or long-press to
  mark a tea run out or take it out; `TeaCatalogPicker` adds a tin in one tap; `TeaFormView` adds a tea of your own or
  edits any (name, brand, family, steep stepper, `TeaLeafRating`, notes, run out).
- **Tasting** — `TastingCard` after a session with tea: three strength chips (one tap saves), then `TeaAromaPicker`
  (wrapping chips, `TeaFlowLayout`) and leaves. `TeaLeaves(rating:)` shows a rating read-only.
- **History** — `TeaHistoryView`: most read with (cup in its liquor), the share of reading with a cup, your teas,
  teas per book (chips, the first in `accent`), tasting notes (long-press to delete).
- **Today** — `TeaWeekCard`, "Tea & book of the week", between the forecast and the desk (`-LeafScroll teaweek`).
- `TeaSwatch(tea:size:)` is the round liquor swatch everywhere a tea is named in a list.
- **Staging** — `tea.cabinet|add|catalog|edit|history`, `book.pairing`, `session.tasting`.

## Reading history (reads, log, numbers, quote cards)

- **Timeline** — `BookTimelineView` (from a book's page, "The whole story, as a timeline"): a card per read-through,
  newest first, with beads on a hairline (`BeadRow`: ink dots for sittings, larger accent dots for a start or a
  finish, ribbon for notes and quotes, chai for tasting notes). The ellipsis rates or takes off an earlier read;
  `EarlierReadSheet` adds a read from before Leaf.
- **Reading log** — `ReadingLogView`: segmented Everything / Sittings / Finished, a range menu (`InsightsRange`),
  search, rows by month (`LogRow`), export as CSV or Markdown through `ShareLink` (`ReadingLogCSV`,
  `ReadingLogMarkdown`: files written only when shared).
- **Your numbers** — `StatsDepthView`: range chips plus custom dates, `StatTileRow`, `DepthBar` rows (thin accent
  capsule on `paperSunken`) for pace and authors and decades, runs, best weeks, set aside, year by year.
- **Quote cards** — `QuoteCardSheet` and `QuoteCardImage` (the share poster size, `SharePoster.render`): Paper,
  Matcha, Rooibos and Night (`QuoteCardStyle`), italic serif face sized to the quote, title, author and page, a tea
  ring and the wordmark; Share and Save to Photos (add-only permission).
- **Doors** — `MoreReadingCard` on Insights; "Your library" in Settings (`SettingsLibrarySection`: reading log,
  backup, restore with a merge preview); `HistorySheet` wraps a page as a Plan sheet.
- **Staging** — `book.timeline`, `log|log.finished|log.search`, `numbers|numbers.range|numbers.alltime`,
  `quote|quote.style`, `settings.data`, `plan.insights.more`.

## Apple Watch (UI-6, NEXT.md §12)

- **Palette** — `WatchTheme`: paper at night (`paper`, `inkSecondary`), the leaf accent and `accentDeep`, `ribbon` for
  "next", `tea` (chai) for anything steeped, `warm` for raised rows. Each page sets its own
  `containerBackground(…, for: .tabView)`.
- **Pages** (vertical `TabView`, top to bottom): `TodayPage` (greeting, cup ring, Steep and read, reading times; the
  steep timer `SteepTimerView` replaces it while a pot steeps), `LogPage`, `ForecastPage`, `WeekPage`
  (`WatchTeaRing` per day), `ShelfPage`, `AddPage` (`TextFieldLink` dictation). Anything that turns the crown is a
  pushed screen (`WatchRoute`: `QuickLogView`, `WhereWasIView`, `ShelfBookActions`), so the crown never pages by
  accident.
- **Session** — the focus-pull countdown in `SessionView`: big serif minutes to go, sharp for most of each minute,
  softening up to the change and landing sharp (`.blur` animated per second; none with Reduce Motion), elapsed
  `mm:ss` underneath for an exact read. `WatchAtmosphere` draws `AtmosphereField.bokeh` behind it (12 fps, still when
  paused). Always-On (`isLuminanceReduced`) keeps only the minutes, dimmed, updated once a minute. Pause/resume carries
  `handGestureShortcut(.primaryAction)` (Double Tap).
- **Runtime and taps** — `ReadingRuntime` (a mindfulness `WKExtendedRuntimeSession`) for sessions the watch times;
  it taps at the goal, and the in-app celebration stays quiet while it runs, so the wrist is tapped once.
  `WatchNotifications` registers Start / In 30 minutes / Skip today. Demo mode starts neither.
- **Complications** — `WatchComplicationShared`: `ComplicationSnapshot` (+ `ComplicationStore` in the App Group) and
  `ComplicationCircular|Corner|Rectangular|Inline`. `widgetAccentable` marks what the face tints.
- **Staging** — `-LeafScreen today|steep|steepready|session|session.cup|aod|pages|log|quicklog|where|forecast|week|`
  `shelf|shelf.actions|add|add.sent|complications`.

## Rules of thumb (from DESIGN.md)

- Paper is content, glass is chrome: glass only on tab bar, toolbars, accessory, buttons, session
  controls/panel, add buttons, the plan-mode picker, sheets. Never on rows, cards, text, covers.
- One `.glassProminent` per screen. Don't nest glass; controls inside the accessory or the panel use `.buttonStyle(.plain)`.
- Scrolling screens: `.scrollEdgeEffectStyle(.soft, for: .top)`.
- Only books cast shadows (plus a row while it's lifted).
- Haptics come from `Haptics.shared` per DESIGN.md §8; components above already play theirs.
