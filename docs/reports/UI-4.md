# UI-4 report: Plan becomes Forecast, Insights and Challenges

```
=== REPORT FOR LEAD ===
Package: UI-4 (Plan tab: forecast, insights, challenges and stamps)
Status: done
Commits pushed to main:
  14b1d31 UI-4: Plan becomes Forecast, Insights and Challenges
  cfd7a91 UI-4 screenshot review: heatmap ends today, empty states, goal pace line
  9841ea2 UI-4 review fixes: honest leaving, fresh what-ifs, pinned odds, readable evidence
  c40c6dd Insights: best-time rows wrap their two layouts in a Group before the accessibility modifiers
CI: run 39239991576 (14b1d31) and 39245240942 (cfd7a91) green. 9841ea2 failed to compile (a modifier on an
  if/else in InsightsPage's best-time rows); runs for the next pushes stopped at the same error until c40c6dd fixed
  it. Run 39284653017 (c40c6dd) green: build, unit tests, watch, unsigned archive and 132 screenshots. A scan of
  every Swift file for the same mistake found no other case.
Screens / states built (staging name -> screenshot file):
  Forecast: year chart + header sentence      -LeafScreen plan                    -> 70-plan-forecast(-dark)
  Now reading: per-book fan charts            -LeafScreen plan.reading            -> 69-plan-reading
  What-if (+15 min), delta chips              -LeafScreen plan.whatif             -> 71-plan-whatif
  For you: tonight only, catch-up, gone quiet -LeafScreen plan.care -LeafScenario returning -> 72-plan-care
  The plan (running order, plan style)        -LeafScreen plan.order              -> 73-plan-order
  Finish line sheet (date scrub + inverse)    -LeafScreen plan.finishline         -> 74-plan-finishline
  Suggested order sheet                       -LeafScreen plan.suggest            -> 75-plan-suggest
  Insights: heatmap, year card, letter card   -LeafScreen plan.insights -LeafScenario year -> 76-insights(-dark)
  Best time + speed trend                     -LeafScreen plan.insights.time      -> 77-insights-time
  Genre and length mix, TBR depth             -LeafScreen plan.insights.mix       -> 78-insights-mix
  Reading personality (share)                 -LeafScreen plan.insights.personality -> 79-insights-personality
  Year in Books                               -LeafScreen plan.year               -> 80-year-in-books(-dark)
  Weekly letter                               -LeafScreen plan.letter             -> 81-weekly-letter
  Challenges: bingo card, seasonal, offers    -LeafScreen plan.challenges         -> 82-challenges(-dark)
  Stamp wall                                  -LeafScreen plan.stamps             -> 83-stamps
  Brand-new reader                            -LeafScreen plan / plan.insights -LeafScenario new -> 84-plan-new, 85-insights-new
  Accessibility text size (AX L)              plan, plan.insights + -UIPreferredContentSizeCategoryName -> 86, 88
  The two share images                        -LeafScreen gallery.posters         -> 87-share-posters
New public types or files (one line each):
  Leaf/Services/PlanDesk.swift            PlanDesk (off-main engine runs, what-if, inverse plan, smart order) + snapshots
  Leaf/Features/Plan/PlanView.swift       PlanView container, PlanSectionSwitcher, sheet host
  Leaf/Features/Plan/ForecastPage.swift   ForecastPage, BookForecastCard, CatchUpCard, StallCard, WhatIfSummary
  Leaf/Features/Plan/ForecastCharts.swift BookFanChart, YearForecastChart, SpeedTrendChart (Swift Charts)
  Leaf/Features/Plan/ForecastSheets.swift FinishLineSheet, SmartOrderSheet
  Leaf/Features/Plan/InsightsPage.swift   InsightsPage, TeaRingHeatmap, Best time/Speed/Mix/TBR/Personality cards, SharePoster
  Leaf/Features/Plan/YearInBooksView.swift YearInBooksView, MonthRingCollage, YearInBooksPoster, WeeklyLetterView
  Leaf/Features/Plan/ChallengesPage.swift ChallengesPage, ChallengeProgressCard (bingo grid), ChallengeOfferCard, StampWall, StampSeal
  AppRouter: PlanSection, PlanSheet, planSection/planSheet/planStage, openWeeklyLetter()
  LibraryStore.applyQueueOrder(_:) (tested); DemoData.Scenario.year (a year of reading; tested)
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  ForecastEngine forecast/whatIf/comparison(against:)/inversePlan(bookID:by:)/inversePlan(booksThisYear:)/tonightOnly/
  smartOrder/catchUp/stalledBooks/backtest, ForecastNarrator (every sentence), InsightsEngine heatmap/bestTimeOfDay/
  speedTrend/genreMix/lengthMix/tbrDepth/personality/yearGoalPacing/yearInBooks/weeklyLetter, WeeklyLetterText.compose,
  ChallengeEvaluator allProgress/availableChallenges/enrollment(for:now:), StampLedger.entries.
  Missing: a WeeklyLetterData -> WeeklyLetterInput mapping (written in the view layer, WeeklyLetterView.copy); a
  queue-reorder store API (added applyQueueOrder in Leaf/Services, not Shared).
  Odd: the deterministic plan and the Monte Carlo median can disagree by weeks for the same book (e.g. Oct 27 vs
  Nov 12); the plan section now says its dates assume every planned minute while the forecast allows for real life.
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/ (engine fixes, project file):
  LeafTests/LibraryStoreTests.swift (two tests), scripts/ci_screenshots.sh (UI-4 shots), docs. No Shared/ changes.
Could not verify (device-only things):
  Share sheets with the rendered images (ShareLink needs a person to tap), the Sunday notification actually opening
  the letter (the hook is wired; notification delivery needs a device), haptics while scrubbing the what-if and the
  finish line, chart drag selection feel, performance of 2,000-run what-ifs on older phones.
Design decisions the owner should know about or veto:
  - The tab keeps its name "Plan" with three pages: Forecast, Insights, Challenges.
  - What-ifs never change anything until "Keep this plan"; the running order and next seven days show the what-if.
  - Finish line only offers a new daily time when the date needs more than the reader gives now, and offers the
    comfortable-margin number, never a reduction.
  - The year chart draws the goal as a steady-pace line from January, so the gap to the forecast is visible.
  - A single missed day doesn't raise the catch-up card; two or more (or a non-default mode) do.
  - Share images are always on paper in the day palette.
Known issues / follow-ups, most important first:
  - The plan's dates (every planned minute) and the forecast median (real life) can differ by weeks; the plan
    section says so, but a single shared "likely finish" would read better.
  - The review fixes (9841ea2) were verified by CI only from c40c6dd onward; their screenshots are in that run.
  - Weekly letter mapping (WeeklyLetterData -> WeeklyLetterInput) lives in the view; it belongs in Shared/.
Next package you recommend: a device pass on UI-3/UI-4 feel (haptics, ribbon, scrub, chart selection).
=== END REPORT ===
```
