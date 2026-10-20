# Reading history and depth: report

```
=== REPORT FOR LEAD ===
Package: Reading history and depth (read-throughs, timeline, reading log and export, backup, quote cards, numbers)
Status: done (device-only checks listed below)
Commits pushed to main:
  f494590 Reading history, part 1: read-throughs, timeline, reading log and export, backup, deeper stats (Shared)
  c7c8204 Reading history, part 2: timeline, reading log, numbers, quote cards, backup and restore
  043da27 History screens: quote mark inside the card, Share legible in dark, range chips wrap
  389244e Quote card preview: scale from the corner so the card isn't cropped
  6f65131 CI: room for the longer screenshot run (55 minutes for screenshots, 90 for the job)
CI: f494590 red (run 39473108420): three tests caught real problems, fixed in c7c8204 (see below).
  c7c8204 green (run 39474315245): build, all unit tests incl. the sync associativity property, watch build,
  unsigned archive, 157 screenshots reviewed in light and dark. 389244e: build, tests and archive green, but the
  Screenshots step timed out at 40 minutes on the watch shots (a slower runner); the iPhone shots were published
  and reviewed. Last: 6f65131 green (run 39496114723), with the screenshot step allowed 55 minutes.
  Red on the way, all real and fixed in c7c8204: undated finished books dropped out of the genre mix; ratings
  outside 1 to 5 reached Year in Books' average; merging was not associative when a deleted book was brought back
  on another device (now a book's deletion clears read-throughs older than it, in any merge order).
Screens / states built (staging name -> screenshot file, all with -LeafDemo YES):
  Book timeline: reading again, first read, beads           -LeafScreen book.timeline        -> 120-book-timeline(-dark)
  Reading log (year scenario)                                -LeafScreen log                  -> 121-log(-dark)
  Reading log, finishes only                                 -LeafScreen log.finished         -> 122-log-finished
  Your numbers, all time (year scenario)                     -LeafScreen numbers.alltime      -> 123-numbers(-dark)
  Your numbers, custom dates                                 -LeafScreen numbers.range        -> 124-numbers-range
  Quote card, Paper                                          -LeafScreen quote                -> 125-quote-card(-dark)
  Quote card, Matcha                                         -LeafScreen quote.style          -> 126-quote-style
  Settings: Your library (log, backup, restore)              -LeafScreen settings.data        -> 127-settings-data
  Insights: More of your reading                             -LeafScreen plan.insights.more   -> 128-insights-more
  Also: log.search (search staged), book page link to the timeline (15-book), Today's journal card "Make a card".
New public types or files (one line each):
  Shared/ReadsHistory.swift        ReadThrough, LibraryItem.reads/readThroughs/asOf/keepingCurrentRead, ReadsHistory
                                   (ordinal, recovered), LeafData.withRecoveredReads
  Shared/BookTimeline.swift        BookTimeline (Chapter, Bead)
  Shared/ReadingLog.swift          ReadingLog (Show, Filter, Entry, entries, totals), ReadingLogExport (csv, markdown)
  Shared/LeafBackup.swift          LeafBackup (encode, decode, merge, preview, Failure), LeafBackupDates
  Shared/Insights/InsightsDepth.swift  InsightsDepth and InsightsEngine.depth(in:), InsightsRange, Daypart.depthTitle
  Leaf/Features/History/           BookTimelineView, EarlierReadSheet, ReadingLogView, ReadingLogCSV/Markdown,
                                   LibraryBackupFile, ExportFiles, StatsDepthView, HistorySheet, QuoteCardSheet,
                                   QuoteCardImage, QuoteCardStyle, SettingsLibrarySection
  LibraryStore: importBackup, setReadRating, addEarlierRead, removeRead; move() keeps a finish when leaving Finished
  Model: LibraryItem.reads, Tombstone.Kind.read; SyncPolicy.syncLayout 3; PlanSheet .readingLog/.numbers/.quoteCard
  Tests: LeafTests/ReadingHistoryTests.swift (read-throughs, recovery, merge, re-read stats, timeline, log, CSV and
         Markdown, backup, numbers, ranges); SyncTests random histories start books again and remove reads.
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  InsightsEngine (sittings, readDays, isRestOnly, finishedItems), Genre.name, TasteProfile.normalizeAuthor,
  SharePoster.render, LeafData.merged, TeaShelf. finishedItems(year:) now returns one finished copy per
  read-through, which made every finish-counting statistic count rereads without touching its callers.
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/ (engine fixes, project file):
  .github/workflows/ios.yml: Screenshots step 55 minutes (was 40), job 90 (was 75).
  Shared/: the new files above; Models.swift (reads, tombstone kind); Sync/LeafDataMerge.swift (read-throughs merge
  one by one, a book's deletion clears read-throughs older than it); SyncStatus.swift (layout 3); ReadingStats,
  InsightsEngine, InsightsYear (highlight ids), ChallengeEvaluator, StampLedger (count read-throughs);
  Cozy/TeaCabinet.swift (TastingNote.summary moved into Shared). Config/Info.plist: NSPhotoLibraryAddUsageDescription.
  scripts/ci_screenshots.sh (120-128). docs/SYNC.md, docs/DESIGN_SYSTEM.md.
Could not verify (device-only things):
  Save to Photos (the add-only permission prompt and the saved image), the share sheet with the CSV, Markdown and
  JSON files (and opening them in Numbers, Files, a notes app), restoring from Files (security-scoped access), the
  rendered quote card's fonts on device, iCloud round trips of read-throughs between two devices, VoiceOver.
Design decisions the owner should know about or veto:
  - A reread keeps the earlier finish (dates and rating) and it still counts: this year's books, Year in Books, the
    weekly letter, the heatmap and challenges count every finish, so a book read twice this year counts twice.
    The reread confirmation says so. A book's stamp is earned at its first finish.
  - Moving a finished book to To read or Set aside keeps its finish too (it was finished).
  - Read-throughs from before this version are recovered from sessions (a session that reached the last page
    before the current start); no ratings for those. Recovery runs on load, the same on every device, unsent.
  - Read-throughs merge one by one (a reread on one phone and a rating on another both survive); a book deleted and
    brought back keeps only read-throughs from after the deletion. SyncPolicy.syncLayout 3 means one full zone fetch
    after updating.
  - A backup is the whole library as JSON with exact dates; restoring merges by iCloud's rules (never replaces newer
    changes, keeps this device's settings and live session) after a preview of what it adds.
  - CSV fields that start with = + - @ (and aren't numbers) get a leading apostrophe so spreadsheets never run them.
  - "Books I abandoned" is "Set aside" in the app's voice: of the books begun in the range, how many were set aside
    out of those that ended, with no guilt in the sentence.
  - Quote cards render in the day palette at 1080 by 1440, in four styles; Save to Photos asks for add-only access.
Known issues / follow-ups, most important first:
  - Mixed versions: a device still on an older build drops `reads` when it re-saves a book; update every device.
  - Read-throughs' dates can't be edited yet (only rated, removed, or added from before Leaf).
  - The numbers page works out its figures on the main thread; fine for years of reading, worth moving off it for
    very large libraries.
  - Restoring a backup can't undo; a note in Settings says nothing newer is replaced.
Next package you recommend: Bookshelf wall + Reading Wrapped (it can now count rereads and use the timeline).
=== END REPORT ===
```
