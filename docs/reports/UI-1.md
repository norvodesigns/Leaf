# UI-1 report: Today, Where are you, reading times, swipe deck

```
=== REPORT FOR LEAD ===
Package: UI-1 (Today, Where are you, reading times, swipe deck)
Status: partly done (code complete and pushed, NOT compiled: CI is blocked by GitHub billing)
Commits pushed to main:
  0757be6 Today: Reading Nook and cards, Where are you sheet, reading times editor, swipe deck
  3002539 Today, deck: spell out CGFloat and Double conversions, name the deck's picked choice
  (plus a docs-only commit with DESIGN_SYSTEM.md and this report)
CI: runs 39201136081 and 39201358821 are red, but neither job started. GitHub says: "The job was not
  started because recent account payments have failed or your spending limit needs to be increased."
  No compile, no tests, no screenshots exist for this package yet. The owner has to fix
  Settings > Billing & plans (macOS minutes), then re-run the latest iOS run or push again.
Screens / states built (staging name -> screenshot file):
  Today, every state, from DemoData.Scenario + -LeafTime:
    evening (standard)       -LeafScreen today -LeafTime 20:30           -> 10-today(-dark)
    morning                  -LeafTime 07:40                             -> 20-today-morning
    late night               -LeafTime 23:30                             -> 21-today-late(-dark)
    rest day                 -LeafScenario rest                          -> 22-today-rest
    goal met                 -LeafScenario goalmet -LeafTime 21:10       -> 23-today-goalmet
    nothing in Reading       -LeafScenario between                       -> 24-today-between(-dark)
    brand new                -LeafScenario new                           -> 25-today-new
    back after two weeks     -LeafScenario returning                     -> 26-today-returning
    finishing a book tonight -LeafScenario finishing                     -> 27-today-finishing
    tea steeping             -LeafScreen today.steep                     -> 28-today-steep
    new book, no position    -LeafScenario newbook (nudge + red chip)    -> 29-today-newbook
    cards below the fold     -LeafScroll leftoff | week | pick           -> 30-today-times(-dark), 31-today-week, 32-today-pick
    side by side, a time per book  -LeafScenario sidebyside              -> 33-today-sidebyside
  Where are you?  position (first start, newbook), position.page, position.percent, position.read
                                                                         -> 34-position(-dark), 35/36/37-position-*
  Reading times   readingtimes, readingtimes.edit                        -> 38-readingtimes(-dark), 39-readingtimes-edit
  Swipe deck      deck (sheet over Search), onboarding.deck, Search banner in 13-search
                                                                         -> 40-deck(-dark), 41-onboarding-deck
New public types or files (one line each):
  Leaf/DesignSystem/CozyColor.swift      CozyColor tokens (teaPaper, chai, matcha, rooibos, steam, amber, rose, teaRing), liquor(for:)
  Leaf/DesignSystem/TeaCup.swift         TeaCup (cup progress with steam), CupBody/CupHandle/CupSaucer/CupLiquid shapes, SteamWisps
  Leaf/DesignSystem/TeaRingStamp.swift   TeaRingStamp, TeaRingWeek (week as tea rings)
  Leaf/DesignSystem/NookAtmosphere.swift NookAtmosphere (daypart light, bokeh from AtmosphereField)
  Leaf/Features/Today/TodayNook.swift    TodayNook header, NookAction, NookActions
  Leaf/Features/Today/TodayCards.swift   TodayCard, PageChip, LeftOffCard, DeskCard, ForecastCard, ReadingTimesCard,
                                         PickCard, WeekCard, YearGoalCard, ChallengeCard, QuoteCard, NudgeCard, ReadingSlotText
  Leaf/Features/Today/TodaySteep.swift   TeaSteepState (the pot on Today, UserDefaults), SteepText
  Leaf/Features/Today/TodayView.swift    rewritten on store.todayBrief; TodayHero.swift deleted
  Leaf/Features/Position/WhereAreYouSheet.swift  PositionChoice, WhereAreYouSheet
  Leaf/Features/Settings/ReadingTimesView.swift  ReadingTimesSection, ReadingSlotRow, ReadingSlotEditor, ReadingTimesSheet
  Leaf/Features/Discover/SwipeDeckView.swift     SwipeDeckModel, DeckCommit, SwipeDeckView, SwipeCard, SwipeDeckScreen,
                                                 TodayDeckCard, DeckBanner
  Leaf/Features/Onboarding/OnboardingDeckView.swift  the deck as onboarding step (new OnboardingStep.deck, folio ix)
  AppRouter: PositionRequest, positionRequest, askPosition(for:then:), showReadingTimes, readingSlotToEdit, showDeck
  LaunchOptions: -LeafScenario, -LeafTime HH:MM (store.now), -LeafScroll <card>; DemoData.Scenario (9 variants),
                 demo library now has two reading times (7:30 weekdays "Morning tea", 21:00 "Before bed")
  Haptics: HapticMoment.teaReady, .deckKeep, .deckStart
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  Used: store.todayBrief / markGreetingShown, ForecastService.refresh/result, ForecastNarrator.yearSentence,
  TeaSuggester.ranked/steepSeconds, TeaRitual.plan, store.apply(StartingPosition, to:), add/update/removeReadingSlot,
  effectiveReadingSlots, slotPlans, SwipeDeck(pool:stats:context:seed:) peek/swipe/undo/swipes,
  store.recommendationContext, dismiss/undismiss, AtmosphereField.steam/bokeh, Cups, ChallengeCatalog.
  Odd 1: SlotPlanner puts a time tied to a book that isn't planned today into the free pool, so in one-at-a-time
  mode "mornings are for Circe" reads The Hobbit. I added a "Read side by side" prompt (Settings and editor) instead
  of changing the engine.
  Odd 2: todayBrief's greeting depends on isFirstLaunchOfDay, which flips after markGreetingShown, so recomputing
  the brief changes the line. Today pins the greeting per day and mode to stop the flicker.
  Odd 3: addReadingSlot switches reminderEnabled on without asking iOS; the editor asks for permission when the
  first time is added.
  Missing: no engine words for the cup ("a few sips in", "about half a cup"); written in TodayNook. No API to
  dismiss a nudge.
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/:
  scripts/ci_screenshots.sh (22 new shot lines; 10-today now staged at 20:30), docs/DESIGN_SYSTEM.md (new
  components), docs/reports/UI-1.md. No engine changes, no project-file changes.
Could not verify (device-only things):
  Everything, this time: nothing has compiled because the CI job never started. Beyond that, device-only:
  Core Haptics patterns (teaReady, deckKeep, deckStart), drag feel and thresholds of the deck, steam and bokeh
  frame cost, Low Power behaviour, notification permission flow from the reading-time editor.
Design decisions the owner should know about or veto:
  - Cup progress lives in the Nook (the cup in the still life, with "12 of 25 min" beside it), not a separate card.
  - Steeping happens on Today, before the session (TeaRitual says the steep is never inside a session). The pot
    persists in UserDefaults and is cleared half an hour after it's ready. Nothing plays a sound; the only cue is
    the teaReady haptic while Today is open. No "tea's ready" notification yet.
  - Starting a book that has never been read and has no position always shows Where are you? first (launcher-level,
    so Today, the accessory, book detail and reminder starts all get it). Default answer: Just starting.
  - The Settings "Reminders" section is replaced by "Reading times" (times + one "Remind me" switch).
  - Between books, Today shows the live deck in place (sideways swipes only inside the scroll view; start now is a
    button) and keeps it open while you swipe, even after a kept book makes you "reading" again.
  - Onboarding gains a deck step between Reminder and Books; deck picks show in a "Your stack" section of Books.
  - Book detail's "Update page" became "Where are you?" (same sheet everywhere); the old BookPageSheet is unused.
Known issues / follow-ups, most important first:
  1. Get CI running (billing), then fix whatever the compiler finds and review all shots in light and dark.
  2. The ribbon as an alternative position control waits for UI-3 (the sheet has scrubber + typed page + percent).
  3. The session screen ignores the tea and the cup-length goalSeconds the Nook passes in; UI-2 should show them.
  4. Quick log without the timer (NEXT.md §4 module 4) is not on Today yet.
  5. Reminders still set content.sound = .default (pre-existing); consider whether that fits "no sound by itself".
Next package you recommend: finish UI-1 verification once CI runs, then UI-2 (session, tea stage, Live Activity).
=== END REPORT ===
```
