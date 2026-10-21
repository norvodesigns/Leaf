# Bookshelf wall and Reading Wrapped: report

```
=== REPORT FOR LEAD ===
Package: Bookshelf wall + Reading Wrapped
Status: done (device-only checks listed below)
Commits pushed to main:
  15a2329 Bookshelf wall and Reading Wrapped
  4097528 Shelf wall: read a cover's colour on the main actor
  d254bcb Wrapped and shelf poster: rings clear of the words, taller spines on a short poster
  641e587 Shelf poster: the wordmark stays on the card (taller spines had pushed it off; at most two planks now)
CI: 15a2329 red (run 39507618834): one main-actor isolation error (a cover's colour read off the main actor), fixed in
  4097528. 4097528 green (run 39508027121): build, all unit tests, watch build, unsigned archive, screenshots reviewed
  in light and dark. d254bcb (two visual fixes) is green in run 39655925407 (a63477d),
  with its screenshots (130 to 141) reviewed again there.
Screens / states built (staging name -> screenshot file, all with -LeafDemo YES -LeafScenario year):
  Finished shelf as a wall of spines                    -LeafScreen shelf          -> 130-shelf(-dark)
  A spine held out: date, rating, tea, open              -LeafScreen shelf.slip     -> 131-shelf-slip
  The year's shelf as a poster to share                  -LeafScreen shelf.poster   -> 132-shelf-poster
  Wrapped, opening card (books, pages, month rings)      -LeafScreen wrapped        -> 133-wrapped(-dark)
  Wrapped cards: tea, best hour, slow burn, most quoted, personality, shelf
                                          -LeafScreen wrapped.1 / .2 / .4 / .5 / .6 / .7 -> 134 to 139(-dark)
  Insights in December: the offer at the top            -LeafScreen plan.insights.wrapped -> 140-insights-wrapped-offer
  Today in December: the offer card, with "Not now"      -LeafScreen wrapped.offer  -> 141-today-wrapped(-dark)
New public types or files (one line each):
  Shared/ShelfWall.swift                 ShelfSpine, ShelfWall (build from read-throughs, spine width/height, row packing)
  Shared/Insights/InsightsWrapped.swift  WrappedStory (cards, tea of the year, best hour, slow burn, most quoted),
                                         InsightsEngine.wrappedStory(year:), WrappedOffer (December and early January)
  Shared/Interaction/TiltFilter.swift    TiltFilter: low-pass, dead zone, clamp, drift back to the held pose, rate limit
  Leaf/DesignSystem/ParallaxTilt.swift   ParallaxTilt.shared: Core Motion through TiltFilter, shared, off in Low Power
  Leaf/Features/Library/LibraryShelfWall.swift  LibraryShelfWall, ShelfPlankRow, ShelfSpineView, SpineTint(s),
                                         SpineSlip, ShelfPoster, ShelfPosterSheet, ShelfWallText
  Leaf/Features/Plan/WrappedStoryView.swift     WrappedStoryView, WrappedCardView, TeaRingScatter, WrappedStyle,
                                         WrappedText, WrappedOfferCard, WrappedRequest
  SharePoster.render gained a scale (Wrapped shares at 720 x 1280)
  Tests: LeafTests/ShelfWrappedTests.swift (wall grouping, rereads, ratings, tea per read-through, packing, 640 books;
         story cards, tea, hour, slow burn, quotes, quiet years, offer dates; tilt filter on synthetic streams)
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  LibraryItem.readThroughs (a reread stands once per year, counting both), InsightsEngine.yearInBooks and personality,
  TeaShelf.tea(id:cabinet:), CoverImageCache, CoverBackdropRenderer.grid (main actor: caught by CI).
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/ (engine fixes, project file):
  Shared/: ShelfWall.swift, Insights/InsightsWrapped.swift, Interaction/TiltFilter.swift. scripts/ci_screenshots.sh.
Could not verify (device-only things):
  The parallax on a real phone (the filter is tested with synthetic streams; on device it should be still when the
  phone is still), long-press and tap on spines inside a scroll view, the slip popover, share sheets with the poster and
  the eight card images, the auto-play for screen recording, performance scrolling 500+ spines (lazy rows, one model
  build per library change, cover colours read once), VoiceOver on the wall and the story.
Design decisions the owner should know about or veto:
  - The wall shows every finish: a book read in two years stands in both; read twice in one year it stands once and
    the slip says so. A book being read again still stands in the year of its earlier finish.
  - Five stars is a "favourite" (a ribbon tail); a tea ring marks a read-through that had tea, by the sessions
    between its start and its finish.
  - Spines take the real cover's colour once Leaf has the scan (it fetches the same scan the cover grid uses), the
    generated cover's palette until then.
  - The parallax moves only the books' shadows on the back of the shelf, a few points, and only while the wall is on
    screen; never under Reduce Motion or Low Power Mode.
  - Wrapped is offered all of December and in the first week of January (for the year just ended), on Today (with
    "Not now", remembered for the year) and at the top of Insights; any time from the Year in Books ("Play your year").
  - Cards: books and pages, tea of the year, best hour, longest streak, the slow burn, most quoted, personality, the
    shelf. Missing ones are skipped; genre, busiest month and fastest book fill in up to six.
Known issues / follow-ups, most important first:
  - The poster counts the pages of the books finished ("4,161 pages, finished one by one"); Wrapped counts pages read
    in the year (4,429, including books still open). Both are right, but side by side they look like a mismatch.
  - The poster shows two planks at most; a bigger year says "and N more" under them.
  - The most-quoted card is thin when every book has one quote (it picks the newest); worth hiding below two quotes.
  - Spine titles are fixed-size type (they are part of the picture; the label carries the words for VoiceOver).
  - The story's card text doesn't scale with Dynamic Type beyond the design sizes (it is a poster as much as a page).
Next package you recommend: the Watch live timer (queued), then Widgets.
=== END REPORT ===
```
