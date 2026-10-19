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

- `Color(hex: UInt32, opacity: Double = 1)` — `Color(hex: 0xF4EFE6)`.
- `UIColor(hex: UInt32, alpha: CGFloat = 1)`, `UIColor.leafDynamic(light:dark:lightAlpha:darkAlpha:)`.
- `LeafUIColor.paper`, `.ink`, … — the same tokens as dynamic `UIColor`s for UIKit code.
- `CoverPalette(book: Book)` → `.background`, `.foreground`, `.rule` (`Color`), `.name`, `.index`.
  `CoverPalette.all` (10 palettes, §2 order), `CoverPalette.index(for: book)` (= `paletteSeed % 10`).
  Book detail's stage for a generated cover: `CoverPalette(book: book).background.opacity(0.18)` over paper.
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
- `view.ribbonSway(trigger: some Equatable)` — the §7 keyframes (rotation about the top edge). `BookCover`
  uses it via `swaysRibbon:`.
- Transitions: `.transition(.inkIn)`, `.transition(.rise())` / `.rise(12)` (onboarding steps),
  `.transition(.countdownNumeral)`, `.transition(.deltaChip)`.
- Strike / rules: draw with `.trim(from: 0, to: drawn ? 1 : 0)` animated by `Motion.strike` /
  `Motion.ruleDraw`; under Reduce Motion set `drawn = true` without animation.
- Numbers: `.contentTransition(.numericText(value: Double(n)))` + `.leafAnimation(Motion.paper, value: n)`.

## Covers — `BookCover.swift`, `GeneratedCover.swift`

- `BookCover(book: Book, size: BookCover.Size, ribbon: Bool = false, swaysRibbon: Bool = false)`
  (also `BookCover(_ book:, size:, …)`). Generated cover underneath, Open Library scan (`?default=false`,
  `.large` for L/XL) fading in over 0.3 s, bad-scan handling, hinge finish, inner stroke, shadow.
  VoiceOver: "Cover of {title} by {author}". `ribbon` draws on M+ and hangs `size.ribbonTail` (0.12 h)
  **below** the frame — leave room. `swaysRibbon` plays `ribbonSway` on each appearance (Today hero).
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
- `WeekdayPicker(selection: Binding<Set<Int>>)` — weekdays 1 = Sun … 7 = Sat, laid out from
  `Calendar.current.firstWeekday`; `masthead` letters, `ribbon` underline, `selection()` haptic, each
  column a toggle ("Monday, reading day"). `WeekdayPicker.orderedWeekdays()` → `[Int]` in display order.
  An empty selection is allowed; the screen disables its button and says "Pick at least one day."
- `ShelfSwitcher(selection: Binding<Shelf>, counts: [Shelf: Int])` — "Reading² To read⁷ Finished³¹",
  sliding `ribbon` underline, `selection()` haptic. Bind to `router.libraryShelf` via `@Bindable`.
  `ShelfSwitcher.title(for: Shelf) -> String` ("Reading", "To read", "Finished").

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

- `CozyColor.teaPaper`, `.chai`, `.matcha`, `.rooibos`, `.steam` (a warm grey on light paper, near white at night),
  `.amber` (lamp), `.rose`, `.teaRing` — dynamic light/dark `Color`s.
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

## Rules of thumb (from DESIGN.md)

- Paper is content, glass is chrome: glass only on tab bar, toolbars, accessory, buttons, session
  controls/panel, add buttons, the plan-mode picker, sheets. Never on rows, cards, text, covers.
- One `.glassProminent` per screen. Don't nest glass; controls inside the accessory or the panel use `.buttonStyle(.plain)`.
- Scrolling screens: `.scrollEdgeEffectStyle(.soft, for: .top)`.
- Only books cast shadows (plus a row while it's lifted).
- Haptics come from `Haptics.shared` per DESIGN.md §8; components above already play theirs.
