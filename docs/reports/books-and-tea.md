# Books and tea: report

```
=== REPORT FOR LEAD ===
Package: Books and tea (pairing, tea cabinet, tasting notes, tea history, the week's tea and book, Tasting Notebook)
Status: done (device-only checks listed below)
Commits pushed to main:
  b62e1d2 Books and tea: pairing, cabinet, tasting notes, tea history, the week's tea and book
  411dede Tea history: break up expressions the type checker timed out on
  72533ad Store test: a closure, not a key path, inside #expect
  626c114 Tea screens: brand on the caption line, Settings-style removal, the week's tea respects the hour
  2c9bbce Review fixes: pairing lines name only their tea, real theme names, one tin per tea, fair caffeine, full
          fetch after a layout change
  7c1838c Review fixes, round two: pinned teas by the hour rule, your own teas in Tea Tasting, history in full
CI: 72533ad green (run 39384971743: build, all unit tests, watch build, unsigned archive, 144 screenshots, reviewed).
  2c9bbce green (run 39410550114). Last: 7c1838c green (run 39463126389, attempt 2: build, all unit tests, watch
  build, unsigned archive, 144 screenshots, the tea screens reviewed again). Attempt 1 never got a macOS runner and
  was cancelled after 15 minutes in the queue; re-run once.
  Two red runs on the way: a type-checker timeout in TeaHistory (fixed in 411dede) and a key path inside #expect in
  a store test (72533ad).
  Review: a five-part adversarial review (shared logic, sync, app state, the brief, copy and accessibility; three
  skeptics per finding). 15 confirmed or self-verified findings fixed in 2c9bbce and 7c1838c; the copy and
  accessibility findings could not be put to the skeptics (usage limit) and were checked by hand instead.
Screens / states built (staging name -> screenshot file, all with -LeafDemo YES):
  Tea cabinet: in stock, run out, add                      -LeafScreen tea.cabinet     -> 110-tea-cabinet(-dark)
  A tea of your own (new)                                  -LeafScreen tea.add         -> 111-tea-add
  Leaf's teas by family, one-tap add                       -LeafScreen tea.catalog     -> 112-tea-catalog
  Editing a tin (name, brand, steep, rating, run out)      -LeafScreen tea.edit        -> 113-tea-edit
  Tea history: most read with, your teas, per book, notes  -LeafScreen tea.history     -> 114-tea-history
  Book page: Pairs well with, pinned pairing, pin another  -LeafScreen book.pairing    -> 115-book-pairing
  Session wrap-up with the tasting card                    -LeafScreen session.tasting -> 116-session-tasting
  Today: Tea & book of the week                            -LeafScreen today -LeafTime 20:30 -LeafScroll teaweek
                                                                                       -> 117-today-teaweek(-dark)
  Ritual: your pairing for this book, from your cabinet    -LeafScreen session.ritual  -> 42-session-ritual (existing)
  Settings: Tea cabinet and Tea history rows               -LeafScreen settings.tea    -> 105-settings-tea (existing)
New public types or files (one line each):
  Shared/Cozy/TeaPairing.swift   TeaPairing (picks/best/reason; 23 rules by genre, theme, length and era)
  Shared/Cozy/TeaCabinet.swift   CabinetTea, TastingStrength, TastingAroma, TastingNote, TeaShelf (tea/tin/inStock/
                                 isAvailable/offerable/ritualChoices/preferred)
  Shared/Cozy/TeaHistory.swift   TeaHistory (per tea, per book, notes, share with tea), TeaAndBook, TeaOfTheWeek
  Leaf/Features/Tea/             TeaCabinetView, TeaCatalogPicker, TeaFormView, TeaHistoryView, TeaPairingSection,
                                 TastingCard, TeaWeekCard, TeaPageSheet, TeaSwatch, TeaLeafRating, TeaLeaves,
                                 TeaAromaPicker, TeaFlowLayout
  LibraryStore: tea(id:), setPairedTea, addCabinetTea, updateCabinetTea, setOutOf, removeCabinetTea,
                tasting(forSession:), saveTasting, deleteTasting; teaChoices(limit:for:), offerableTea, pairingTeas
  Model: LeafData.cabinet, LeafData.tastings, LibraryItem.pairedTeaID, Tombstone.Kind.cabinetTea/.tasting
  Sync: records LeafTea (tea.<uuid>) and LeafTasting (tasting.<uuid>); SyncMerge.newest; SyncPolicy.syncLayout
  Challenges: Tasting Notebook (notes on 1/3/6 teas, 3/5 families; stamps First Note, Steady Palate, Tea Scholar)
  Tests: LeafTests/TeaTests.swift (pairing, cabinet and shelf, history and the week, Tea Tasting with own teas,
         Tasting Notebook, migration, sync records and merge, layout); SyncTests random histories now edit the
         cabinet and notes; LibraryStoreTests tea CRUD and demo data.
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  TeaSuggester.ranked/allowed/caffeineCap (now take a candidate list), ForecastEngine/ForecastResult.book(_:).median,
  ChallengeEvaluator, SyncDiff/SyncRecordMapper/LeafData.merged.
  Odd: TeaSuggester.ranked truncates to `limit`, so "is it on offer" must never be a list-membership test; pinned
  and picked teas are judged by the hour rule and the cabinet (TeaShelf.offerable).
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/ (engine fixes, project file):
  Shared/: the new Cozy files above; Models.swift (fields, tombstone kinds); Sync/* (record types, names, entities,
  mapper, diff, merge, syncLayout); TeaSuggester (candidates); ChallengeModels/Evaluator/Catalog (tastingNotes rule,
  Tasting Notebook, own teas count in Tea Tasting). Leaf/Services/CloudSync.swift: saved state records the layout
  and an older state is dropped once for a full fetch. scripts/ci_screenshots.sh (110-117). docs/SYNC.md,
  docs/DESIGN_SYSTEM.md. No project file changes (Leaf/Features/Tea/ sits in the synchronized Leaf folder).
Could not verify (device-only things):
  iCloud: LeafTea/LeafTasting round trips between two devices, and the one-time full fetch after updating from a
  build without them (needs two signed devices on one account). Swipe actions and context menus on the cabinet
  rows and tasting notes (simulator screenshots show layout only). VoiceOver over the new screens. Haptics.
  The Swift toolchain host (download.swift.org) is blocked by this environment's network policy, so the logic tests
  ran only in CI; allow that host under the environment's Network access settings to run scripts/linux_tests.sh
  in a session.
Design decisions the owner should know about or veto:
  - CloudKit schema: deploy LeafTea and LeafTasting (payload, updatedAt, schema) to Production before the next
    TestFlight. Until then a Production build fails to save them; the error shows in Settings and the rest syncs.
  - SyncPolicy.syncLayout = 2: every device does one full zone fetch after updating to this build (merging is
    idempotent). Raise it whenever a record type, tombstone kind or synced field is added.
  - Mixed versions: a device still on an older build drops pairedTeaID when it re-saves a book, so a pin can be
    lost if a book is edited there before it updates. Update every device together.
  - A catalog tin keeps the catalog id (stats, challenges and Tea Tasting count it); a tea of your own is saved as
    "custom.<uuid>" and takes the lowest caffeine among the catalog's teas of its family.
  - The ritual offers the cabinet's teas in stock, ranked for the hour; the catalog when the cabinet is empty, all
    run out, or nothing in it suits the hour (it says so). A pinned tea leads whenever the hour allows it.
  - The tasting card saves on the first tap of a strength and never before; it has no free-text field (the brief
    asked for strength, aromas, rating). Notes are deleted from Tea history (long-press).
  - Tasting Notebook counts milestones ("2 of 5 entries"), not notes.
  - "Tea & book of the week" sits after the forecast on Today; Steep and read opens the ritual on its tea only when
    that tea suits the hour.
Known issues / follow-ups, most important first:
  - Deploy the CloudKit schema (above).
  - Tasting notes can't be edited after the wrap-up closes (only deleted); a small edit sheet from Tea history would
    close that gap, with a free-text line if wanted.
  - The watch steeps the cabinet's best tea for the hour but has no cabinet UI or tasting card.
  - Pairing weights are hand-tuned; a reader's ratings could later nudge them (on device).
Next package you recommend: Reading history and depth (reads history, per-book timeline, exports, backups).
=== END REPORT ===
```
