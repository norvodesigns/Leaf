# UI-5 report: Search shop, Library, book detail, Settings and onboarding

```
=== REPORT FOR LEAD ===
Package: UI-5 (Search browsing, Library and book detail, Settings, onboarding)
Status: done
Commits pushed to main:
  3b38215 UI-5: a shop of rows, the Paused shelf, editions and journal, new Settings and first times
  __FIXES__
CI: __CI__
Screens / states built (staging name -> screenshot file):
  Search front table: hero "Picked for you", jump bar, mood rows   -LeafScreen search          -> 90-search-browse(-dark)
  Series row as spines                                             -LeafScreen search.series   -> 91-search-series
  Author row with its header                                       -LeafScreen search.author   -> 92-search-author
  Time-budget row (reading time on each cover)                     -LeafScreen search.time     -> 93-search-time
  Seasonal tinted row                                              -LeafScreen search.seasonal -> 94-search-seasonal
  "See all" grid                                                   -LeafScreen search.seeall   -> 95-search-seeall
  More like this                                                   -LeafScreen search.similar  -> 96-search-similar
  Your taste                                                       -LeafScreen search.taste -LeafScenario year -> 97-search-taste
  First use (no library yet)                                       -LeafScreen search -LeafScenario new -> 98-search-first-use
  "Not for me" with Undo                                           -LeafScreen search.undo     -> 99-search-undo
  Library: Paused shelf, "Pick it back up"                         -LeafScreen library.paused  -> 100-library-paused(-dark)
  Book detail: journal tab                                         -LeafScreen book.journal    -> 101-book-journal
  Book detail: more like this                                      -LeafScreen book.more       -> 102-book-more
  Book detail: edition picker                                      -LeafScreen book.edition    -> 103-book-edition
  Settings: plan (catch-up, year goal, letter, progress)           -LeafScreen settings.plan   -> 104-settings-plan
  Settings: tea, cup, ambience and volume, sound cues              -LeafScreen settings.tea    -> 105-settings-tea
  Settings: iCloud status, Sync now, honest reset copy             -LeafScreen settings.cloud  -> 106-settings-cloud
  Onboarding: first reading times + extra time, iCloud note        (no new staging; existing onboarding shots)
New public types or files (one line each):
  Leaf/Features/Search/SearchShelves.swift  shelf kinds by id, SearchShelfRow, SpineShelf, AuthorShelfHeader, jump bar,
                                            front-table note, Open Library credit, UndoToast, CollectionGridView,
                                            SimilarBooksView, TasteView (+ SimilarRoute, TasteRoute)
  Leaf/Features/Book/BookDetailExtras.swift BookEditionPicker, BookJournalList, BookMoreLikeThis
  Leaf/Features/Library/LibraryPausedShelf.swift  the Paused shelf
  Leaf/Services/CozySettings.swift          sound cues, tea strength, ambience volume (device-local, applied at launch)
  Leaf/Features/Settings/SettingsCozy.swift Tea, Plan, Extras and iCloud sections
  Leaf/Features/Onboarding: OnboardingTimesView + OnboardingExtraTime (replace the single reminder step)
  AppRouter: searchPath (NavigationPath), searchStage, bookStage, settingsStage
  BookCatalog.similar(to:context:limit:), BookCatalog.tasteProfile(context:) (detached wrappers)
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  BookCatalog.collections(context:) and BookCollection.reasons, Recommender.similar, TasteProfileBuilder (topGenres,
  topThemes), Genre.name, store.dismiss/undismiss, store.pause, store.journal(for:), Book.pageCounts,
  store.sync?.status / pendingChanges / forceFullSync(), AILibrarian.isAvailable, CozySounds.shared.isEnabled,
  AmbiencePlayer.shared.setVolume.
  Missing: a stable shelf "kind" on BookCollection; I classify by id prefix (for-you, series-, author-, time-, ...)
  in SearchShelfKind. If the catalog renames an id family, that row falls back to the plain carousel.
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/ (engine fixes, project file):
  scripts/ci_screenshots.sh (shots 90-106), docs/DESIGN_SYSTEM.md (UI-5 section). No Shared/ changes.
Could not verify (device-only things):
  iCloud status and Sync now against a real account (simulator has no iCloud), Apple Intelligence greetings
  availability, ambience volume and sound cues by ear, Dynamic Type at the largest sizes on every new row.
Design decisions the owner should know about or veto:
  - Progress mode stays per book (book detail), not a Settings preference; Settings explains where it lives.
  - Tea strength, cup sounds and ambience volume are device-local (UserDefaults) and do not sync.
  - Your taste is read-only: it shows what Leaf learned, without weight dials.
  - "Not for me" hides at once and offers Undo for a few seconds; nothing is asked.
  - Search keeps every row lazy: rows are LazyVStack sections, covers inside LazyHStack, "See all" a LazyVGrid.
Known issues / follow-ups, most important first:
  __FOLLOWUPS__
Next package you recommend: a device pass for iCloud sync status and the Settings copy with a real account.
=== END REPORT ===
```
