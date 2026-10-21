# Agent 2: new feature ideas

Twenty ideas that are not built or in progress (checked against `docs/NEXT.md` sections 13 and 16, `git log`, and the
list of work already done or under way: tea ritual and ambience, journal and quote cards, challenges and stamps,
forecast and insights and Year in Books, swipe deck, book club, widgets and Control Center, ISBN/CSV import and
series, history and backup, shelf wall and Wrapped, cover and shelf scanner, AI librarian chat, nook scenes and
bedside mode, tea pairing, What's New and the walkthrough, iPad and Mac, localization). Every idea keeps Leaf's
promises: no accounts, no servers, no analytics, nothing that speaks or plays by itself, and old data keeps loading.

Effort: **S** an afternoon to two days, **M** about a week, **L** two weeks or more. Priority: **must**, **should**,
**could**.

## Top 5, ranked

1. **Library loans with finish odds** (must, M). The forecast engine is Leaf's most original asset, and a due date is
   the one deadline readers can't move. "Probably finished by Thursday, 80 percent before it's due" is a sentence no
   other reading app can write, and it turns a stressful renewal decision into a calm one.
2. **Snap your page** (must, S to M). "Where are you?" was the loudest feedback after the first TestFlight round.
   Pointing the camera at the page corner and getting the number back makes the most frequent edit in the app take
   two seconds, with VisionKit the app already uses.
3. **Bookshop mode** (should, M). Second-hand shops and library sales are where cozy readers find books. "Do I own
   this already, and how long would it take me?" answered in the aisle, from the offline catalog, is a reason to open
   Leaf away from home.
4. **Shortcuts that answer** (should, S). A handful of App Intents that return values (today's pages, the current
   book, the forecast sentence) let readers build their own rituals (a lamp that warms when it's reading time, a
   journal entry each night) with zero new UI. A quick win with long reach.
5. **Read-aloud nights** (should, L). Families read aloud every night and nobody tracks it kindly. A second, local
   reader on the same phone (a child) with picture-book-sized pages and bedtime stamps widens Leaf's audience without
   accounts.

**Quick wins that fit in an afternoon:** Shortcuts that answer (the value-returning intents alone), a letter sealed
until the last page, the Ex Libris bookplate, haptic cup pulses on the watch, and reading times as a calendar file.

---

## Habit and motivation, done gently

### 1. A letter sealed until the last page
**Pitch.** When a book is started, Leaf offers (once, skippably) a line to the reader who will finish it: why they
picked it, where they are in life, what they hope it holds. The note is sealed (hidden, not encrypted) and opens on
the finish moment, beside the wrap-up. Rereads get a new letter and can open the old one.
**Why readers love it.** It makes the finish a small ceremony and turns a long book into a conversation with oneself.
**Builds on.** `JournalEntry` (a new optional `sealedUntilFinish` flag, defaulted, so old data loads), `SessionOutcome`
(`finishedBook`), `LibraryStore.markFinished`, the wrap-up screen, `ReadThrough` for rereads. Syncs as a journal record.
**Effort.** S. **Risks.** Must stay optional and never nag; a book removed before finishing keeps its letter in the
journal. **Priority.** could.

### 2. One page, then decide
**Pitch.** A "just one page" start: no cup, no goal, one page. When it is turned, Leaf asks softly whether to keep
going into a cup. It is the implementation-intention trick behind most habit research, in Leaf's voice.
**Why readers love it.** On low days the full ritual feels like too much; one page never does.
**Builds on.** `ActiveSession` (an open session with a tiny `goalSeconds`), `TeaRitual` for the hand-off into a cup,
`SessionWrapUp` lines, a new `TodayNudge` case for evenings with nothing read yet. **Effort.** S.
**Risks.** Must never read as pressure; it should appear only when the reader opens the app, never as a notification.
**Priority.** should.

### 3. Let a book go
**Pitch.** Once a season, Leaf picks the three To read books that have waited longest without being touched and offers
a small ritual: keep it, set it aside, or let it go with a one-line thank you. Letting go removes it (with the usual
tombstone) and keeps the line in the journal.
**Why readers love it.** A heavy pile is the main source of reading guilt. Releasing books kindly is the opposite of a
streak.
**Builds on.** `InsightsEngine.tbrDepth()`, `LibraryItem.addedAt`, `LibraryStore.remove` and `dismiss`, a journal
thought, the season from `Moment.swift`. **Effort.** S to M. **Risks.** The copy is everything; test it with real
readers. **Priority.** could.

## Accessibility and inclusivity

### 4. Reading ruler for the speed test and long passages
**Pitch.** A line-focus ruler (a soft band that follows the line being read, the rest dimmed), extra letter and line
spacing, and a "my pace varies" setting that tells the forecast to keep its ranges wide. Offered in the speed test and
in any long text Leaf shows (the weekly letter, Year in Books).
**Why readers love it.** Dyslexic readers and readers with ADHD are often told their speed is "slow"; the ruler makes
the test fair, and wide ranges make the plan honest for them.
**Builds on.** `SpeedTestPassages`, `SpeedTestStages`, `ReadingSpeed.effectiveWPM`, the forecast's
`ForecastMinutesModel.sigma` (a floor raised by the setting), `ReadingPreferences` (one new defaulted field).
**Effort.** M. **Risks.** A speed measured with the ruler must stay comparable; record which mode a test used.
**Priority.** should.

### 5. Haptic cup pulses on the watch
**Pitch.** An opt-in tap on the wrist every quarter of a cup (or every 10 minutes), different at the half and at the
end, so a reader whose eyes are on the page, or who can't see the screen, feels the session's shape. No sound.
**Why readers love it.** Paper readers never look at a timer; blind and low-vision readers get the session without
VoiceOver interrupting the book.
**Builds on.** `WatchRuntime` (the extended runtime session already runs), `WKInterfaceDevice` haptics, `ActiveSession.
remaining(at:)`, a watch setting. **Effort.** S. **Risks.** Battery; keep it to a handful of taps per cup.
**Priority.** should.

### 6. High-legibility mode
**Pitch.** One switch for readers with low vision: no blur or drifting scenes, the strongest contrast pair, no italic
serif for body text, bigger hit targets, and the big numerals capped so they never clip at the largest sizes.
**Why readers love it.** Dynamic Type already works; this fixes the things it doesn't touch (italic serifs, translucent
glass, soft blurred numbers).
**Builds on.** The design tokens in `Leaf/DesignSystem` (`LeafColor`, typography `leafStyle`), the Reduce Transparency
paths that already exist, `AppearancePreference`. **Effort.** M. **Risks.** Must stay one coherent look, not a pile of
toggles. **Priority.** could.

## Reading with kids and families

### 7. Read-aloud nights (top 5)
**Pitch.** A second reader on the same iPhone, local only: "Reading with Maya". Picture books are counted in nights and
books, not minutes; a bedtime reading time; a stamp card of tea-ring stamps (cocoa rings for kids) that can be printed.
The grown-up's own plan and statistics are untouched.
**Why readers love it.** Reading aloud is the most loved reading many families do, and no app treats it gently.
**Builds on.** `LeafData` (a new optional `companions: [Companion]` with their own items and sessions, defaulted),
`ReadingSlot`, `TeaRingStamp`, `SharePoster` for the printable card, `ChallengeEvaluator` for a "100 bedtime books"
card. **Effort.** L. **Risks.** The model change is real (merge rules, sync record names, backup format); children's
data must never leave the device except through the parent's own iCloud. **Priority.** should.

### 8. Bedtime stamp card
**Pitch.** The small version of the idea above: a printable or shareable weekly card for a child with a stamp for each
night read, made from the grown-up's "read aloud" sessions (a session tag).
**Builds on.** `SessionKind` or a session tag, `TeaRingStamp`, `QuoteCardImage`-style rendering. **Effort.** S.
**Risks.** Without companions it can't tell children apart. **Priority.** could.

## Physical-book rituals

### 9. Ex Libris bookplate
**Pitch.** Design a bookplate from the generated-cover palettes (initials, a tea leaf, a motto) and print it on label
paper, sized for common label sheets, as a PDF.
**Why readers love it.** It is the most physical, giftable thing a reading app could make, and it costs nothing.
**Builds on.** `GeneratedCover` palettes, `ImageRenderer` and the quote card's export path, `LeafColor`. **Effort.** S.
**Risks.** Printer margins; offer "A4" and "US Letter" only. **Priority.** could.

### 10. Dog-ears
**Pitch.** A one-tap "dog-ear this page" during a session, on the phone or the watch crown screen: page and moment,
no text needed. A book's dog-ears list sits with its journal; any of them can become a quote later.
**Why readers love it.** Writing a note breaks the spell; folding a corner doesn't.
**Builds on.** `JournalEntry.Kind` (a new `.dogEar`, decoded tolerantly so older builds skip it), `WatchStore.addJournal`,
`SyncEvent.journalAdded`. **Effort.** S. **Risks.** A new enum case needs the tolerant decode added in this review on
every path (sync records already skip unknown payloads). **Priority.** should.

### 11. Where's my copy?
**Pitch.** Note where each physical copy lives (a room, a shelf, a box, "at Mum's") and its format. Search answers
"where is it", and the shelf wall can filter by room.
**Builds on.** `LibraryItem` (one optional field), `LibraryShelfWall`, the search screen. **Effort.** S.
**Risks.** Small, but it is model work (sync layout bump). **Priority.** could.

## Library and second-hand workflows

### 12. Library loans with finish odds (top 5, prompt below)
**Pitch.** Mark a book as borrowed from a library with a due date. The plan reads loans first when it can, and the
forecast shows the odds of finishing before it's due ("Probably done Thursday. 8 in 10 before it's due on Saturday").
When the odds drop below a half, Leaf offers the minutes per day that would make it, or a gentle "renew it?" note.
Not the parked "lending" (books you lend to friends) and not Libby links.
**Why readers love it.** Library readers juggle three-week loans and long holds; this is the first plan that knows the
date can't move.
**Builds on.** `ForecastEngine` (`BookForecast.probability(by:)`, `inversePlan(bookID:by:)`), `ForecastNarrator`,
`Planner` (loan-first ordering), `TodayNudge`, `Reminders` (an opt-in heads-up three days before), `LibraryItem` (an
optional `loan` with `dueAt` and `library`). **Effort.** M. **Risks.** Changing plan order must not surprise readers;
make "loans first" visible and reversible. **Priority.** must.

### 13. Bookshop mode (top 5, prompt below)
**Pitch.** A screen for the aisle: a want list, a big "Do I have this?" field (type or scan an ISBN), and for the book in
hand its page count, time to read at the reader's pace, which of their shelves it would join, and whether they've read
it before. Works with no connection.
**Why readers love it.** Every second-hand reader has bought a book they already owned.
**Builds on.** `BookCatalog.search` and `book(id:)` (offline), the ISBN scanner already built, `Book.minutes(atWPM:)`,
`LibraryItem.readThroughs`, `Recommender` for "you'd probably like it" from `TasteProfile`. **Effort.** M.
**Risks.** ISBN to work id mapping is incomplete in the offline catalog; fall back to title search gracefully.
**Priority.** should.

### 14. Pack for the trip
**Pitch.** Enter trip dates (and flights, optionally): Leaf works out how many pages the trip holds at the reader's
pace and suggests which books from To read to pack, with their weight estimated from page count ("two paperbacks,
about 700 g, or one hardback").
**Why readers love it.** Choosing holiday books is a joy and a worry; this is pure delight with real numbers.
**Builds on.** `ForecastEngine.inversePlan(booksThisYear:)` style solving over a date range, `Planner`, `PlanInput`
with a custom `dailyMinutes` for travel days, `Book.pages`. **Effort.** M. **Risks.** Weight estimates are rough; say
so. **Priority.** could.

## Social without accounts

### 15. A slip for the next reader
**Pitch.** When lending, donating or leaving a book in a little free library, print or show a slip with a QR code: the
book's id, a favourite quote and a short note. Anyone with Leaf scans it to add the book with the note as a journal
thought "from the last reader". No server: everything is in the code.
**Why readers love it.** It is book-crossing for cozy readers, and it travels with the paper book.
**Builds on.** `QuoteCardImage` rendering, `CIQRCodeGenerator`, the existing camera scanner, `JournalEntry`,
`BookCatalog.book(id:)`. **Effort.** S to M. **Risks.** Keep the payload tiny and validate it like any untrusted input.
**Priority.** could.

### 16. A quiet hour together (SharePlay)
**Pitch.** Start a SharePlay "quiet hour" from a FaceTime call: everyone's cup timer starts together, each person sees
the others' cups fill (no books shared unless they choose), and the hour ends with each person's one-line note.
**Why readers love it.** Long-distance friends read "together" without a club, a schedule or an account.
**Builds on.** `GroupActivities` (Apple's, no server), `ActiveSession` goal, `TeaRitual`. Different from the built
book club (CloudKit sharing of a book and deadline). **Effort.** L. **Risks.** SharePlay review and testing need
devices; keep it strictly opt-in. **Priority.** could.

## Focus, wellbeing and automation

### 17. Shortcuts that answer (top 5, prompt below)
**Pitch.** Intents that return values: "Get today's reading" (minutes left, pages, book), "Get my current book",
"Get the forecast sentence", "Log minutes", and "Offer a cup" (opens Leaf to the steep screen). Plus a short guide in
Settings with three ready-made automations: dim the lights at reading time, open Leaf instead of a feed after 22:00,
write the day's quote to Notes.
**Why readers love it.** Rituals are personal; Shortcuts lets readers build theirs.
**Builds on.** `ReadingAppIntents` and `AppReadingIntents`, `LibraryStore.todayBrief`, `ForecastService.sentence`,
`LibraryStore.logManual`. **Effort.** S. **Risks.** Intents run when the app is in the background; read the store
safely (and not before the first unlock: `LibraryStore.isLoadDeferred`). **Priority.** should.

### 18. Study cups
**Pitch.** For non-fiction: after each cup, one line of "what stayed with me", and at the end of the book a page of
those lines in order. Optional spaced reminders to reread three of them a week later.
**Builds on.** `TeaRitual` stages, `JournalEntry`, `JournalTools.markdown`, `Reminders`. **Effort.** M.
**Risks.** Reminders must stay opt-in and rare. **Priority.** could.

### 19. Reading times in your calendar
**Pitch.** Export reading times as an `.ics` file (or a subscription the reader saves to Files) so the calendar shows
"Tea and The Hobbit, 20 min" blocks. No EventKit permission needed for the file.
**Builds on.** `SlotPlanner`, `ReadingSlot`, `LeafFormat`, the share sheet from `ExportFiles`. **Effort.** S.
**Risks.** A static file goes stale; say when it was made. **Priority.** could.

## Sustainability without selling the reader

### 20. A tea for the gardener
**Pitch.** A tip jar of three consumable in-app purchases ("a cup", "a pot", "a tin"), nothing unlocked, thanked with a
one-time stamp and a line in the colophon. Optional, mentioned once (in What's New), never again.
**Why readers love it.** People who love a calm app want to keep it calm.
**Builds on.** StoreKit 2, `StampLedger`, Settings' colophon. **Effort.** S to M (App Store Connect setup). **Risks.**
App Review rules for tips; keep the wording plain. **Priority.** could.

---

## Ready-to-paste prompts for the top 3

### Prompt 1: Library loans with finish odds

```
You are an engineer joining the Leaf project: a native iOS 26 / watchOS 26 SwiftUI cozy reading planner (books and
tea; offline catalog; a Monte Carlo forecast engine; iCloud sync through the reader's own CloudKit). Repo:
https://github.com/norvodesigns/Leaf. Work directly on main; never create a branch or PR. Before each push:
git pull --rebase origin main, then git push origin HEAD:main. Small focused commits.

GOAL: Library loans with finish odds. A reader marks a book as borrowed from a library with a due date. The plan reads
loans first when it can, Today and the book page show the odds of finishing before the due date in Leaf's voice
("Probably done Thursday. 8 in 10 before it's due on Saturday."), and when the odds drop below a half Leaf offers the
minutes per day that would make it or a gentle "renew it?" note. Not lending to friends, not Libby links.

RULES
- No accounts, no servers, no analytics. Nothing speaks or plays by itself. Copy: warm, short, never guilt, no
  exclamation marks, typographic apostrophes.
- Old saved data must keep loading: new model fields are optional or defaulted. A new synced field means raising
  SyncPolicy.syncLayout and a test that an older payload still decodes (see docs/SYNC.md).
- Shared/ is Foundation only and tested on Linux with scripts/linux_tests.sh (it runs in Docker if there is no
  toolchain). There is no Mac: CI on GitHub Actions compiles and screenshots (python3 scripts/ci.py wait, errors,
  shots). Read your diff twice before pushing; never leave main red.
- Swift 5 mode. Keep #expect expressions short (annotate intermediate values). Do not edit files other engineers own
  (ask the lead which those are today).

READ FIRST: docs/OPUS_HANDOFF.md, docs/ENGINEERING.md, docs/SYNC.md, docs/DESIGN.md (voice and colour),
Shared/Models.swift (LibraryItem), Shared/Forecast/ForecastEngine.swift, ForecastResult.swift, ForecastInverse.swift,
ForecastNarrator.swift, Shared/Planner.swift, Shared/TodayBrief.swift (TodayNudge), Leaf/Services/LibraryStore.swift,
Leaf/Services/Reminders.swift, Leaf/Features/Book/, Leaf/Features/Plan/ForecastPage.swift, docs/reports/agent2-review.md.

TASKS
1. Model: LibraryItem.loan: Loan? (dueAt: Date, library: String?, renewals: Int). Tolerant decoding (absent = nil);
   merge rule: travels with the item (newest updatedAt wins as a whole, already true). Raise syncLayout. Tests: legacy
   JSON decodes, round trip, merge keeps the newer loan.
2. Planner: an option to read loans first (PlanInput.loansFirst, default true when any loan exists), ordered by due
   date, without reordering the reader's own queue otherwise. Tests: due-date order, rest days, side-by-side mode,
   a loan already finished, a loan due in the past.
3. Forecast: BookForecast already has probability(by:); add a LoanOutlook (probability by the due date, the minutes
   per day needed via inversePlan(bookID:by:) at 80 percent, and a narrated sentence from ForecastNarrator). Use the
   same seed as the main forecast. Tests: deterministic, NaN-free with no history, the sentence never promises.
4. Today and the book page: a quiet loan line with the odds and, below a half, the offer (set the minutes, or note a
   renewal: renewals += 1 and a new due date). A TodayNudge case for "due in 3 days, not started".
5. Reminders: opt-in heads-up three days before a due date, at the reader's first reading time; respects Skip today
   and the Focus hold. Keep within the 64 pending limit (Reminders caps itself at 56 daily ones).
6. Staging: add DemoData loans and screenshot states (book.loan, today.loan, plan.loan) to scripts/ci_screenshots.sh,
   light and dark, and look at them.

ACCEPTANCE
- Linux tests and CI green; screenshots reviewed in light and dark, large type included.
- A library with no loans looks and behaves exactly as before (plan order, Today, notifications).
- VoiceOver reads the odds as a sentence; numbers beside any cute unit.

REPORT: end with
=== REPORT FOR LEAD ===
Feature: Library loans with finish odds
Status: done | partly done | blocked
Commits pushed to main: <short shas and one-line messages>
CI: <last run id, green or red>
Model and sync changes (fields, syncLayout, tests): ...
Screens and staging names (with screenshot files): ...
Could not verify (device-only): ...
Decisions the owner should know or veto: ...
Follow-ups: ...
=== END REPORT ===
```

### Prompt 2: Snap your page

```
You are an engineer joining the Leaf project: a native iOS 26 SwiftUI cozy reading planner (books and tea). Repo:
https://github.com/norvodesigns/Leaf. Work directly on main; never create a branch or PR. Before each push:
git pull --rebase origin main, then git push origin HEAD:main. Small focused commits.

GOAL: "Where are you?" by camera. In the position sheet (and the quick log), a "Snap the page" button opens the camera;
Leaf reads the page number printed in the corner or at the foot of the page and sets the scrubber to it, for the
reader to confirm. Nothing is saved but the number; no photo is kept.

RULES
- No accounts, servers or analytics. The camera permission string already exists (NSCameraUsageDescription); keep its
  promise (only the number is kept). Copy: warm, short, never guilt, no exclamation marks, typographic apostrophes.
- The pure part (choosing the page number from recognised text) goes in Shared/ as Foundation-only code with Linux
  tests (scripts/linux_tests.sh; it runs in Docker without a toolchain). The camera part lives in Leaf/.
- There is no Mac: CI compiles and screenshots (python3 scripts/ci.py wait, errors, shots). Read your diff twice.
- Swift 5 mode; keep #expect expressions short. Every gesture needs a non-gesture alternative; the numeric field stays.

READ FIRST: docs/OPUS_HANDOFF.md (Where are you), docs/ENGINEERING.md, docs/DESIGN.md, Shared/StartingPosition.swift,
the position sheet in Leaf/Features (grep PositionSheet / "Where are you"), Leaf/Features/Session/SessionExtras.swift
(how the quote scanner uses VisionKit's DataScannerViewController), Leaf/Services/LibraryStore.swift
(confirmPosition, apply(StartingPosition)), docs/reports/agent2-review.md.

TASKS
1. Shared/PageNumberReader.swift: given recognised text items with their normalised bounding boxes (top/bottom/left/
   right edges), the book's page count and the current page, return the most likely page number and a confidence.
   Prefer numbers in the outer corners or the foot, within 1...pages, near the current page; ignore years, chapter
   numbers in the middle of the page, and numbers with letters. Handle roman numerals in front matter (return nil),
   two-page spreads (the larger of two facing numbers), and books whose printed numbers are offset. Tests with
   many synthetic layouts and adversarial text.
2. Leaf: a camera sheet using DataScannerViewController (text recognition, accurate, guidance on), feeding observed
   items to PageNumberReader; when confident, haptic tick and a big "Page 142?" with Use and Try again. Respect
   DataScannerViewController.isSupported/isAvailable; hide the button when unsupported.
3. Wire it into the position sheet and the quick log; the scrubber moves to the number so the reader still confirms.
4. Staging: a DEBUG path that feeds canned recognised text so CI can screenshot the confirm state (position.snap),
   light and dark.

ACCEPTANCE
- Linux tests for PageNumberReader; CI green; screenshots reviewed.
- Denied camera permission, an unsupported device and a page with no number all end in a calm message and the
  numeric field, never a dead end.

REPORT: end with
=== REPORT FOR LEAD ===
Feature: Snap your page
Status: done | partly done | blocked
Commits pushed to main: <short shas and one-line messages>
CI: <last run id, green or red>
New types and files: ...
Screens and staging names (with screenshot files): ...
Could not verify (device-only: camera, lighting, real books): ...
Decisions the owner should know or veto: ...
Follow-ups: ...
=== END REPORT ===
```

### Prompt 3: Bookshop mode

```
You are an engineer joining the Leaf project: a native iOS 26 SwiftUI cozy reading planner with a 250,000-book offline
catalog (SQLite FTS5) and a taste recommender. Repo: https://github.com/norvodesigns/Leaf. Work directly on main; never
create a branch or PR. Before each push: git pull --rebase origin main, then git push origin HEAD:main.

GOAL: Bookshop mode, a screen for the aisle of a second-hand shop or library sale. A want list; a big "Do I have this?"
field (type a title or scan an ISBN with the scanner Leaf already has); and for the book in hand: page count, time to
read at the reader's pace, whether it is already on a shelf (and which), whether they have read it before (and their
rating), and whether it fits their taste ("Close to what you've loved: cozy mysteries, found family"). Works offline.

RULES
- No accounts, servers or analytics; offline first (Open Library only as the existing optional fallback). Copy: warm,
  short, never guilt, no exclamation marks, typographic apostrophes.
- The matching and the verdict are pure Shared/ code with Linux tests (scripts/linux_tests.sh, Docker fallback). There
  is no Mac: CI compiles and screenshots (python3 scripts/ci.py wait, errors, shots). Read your diff twice.
- Old data keeps loading: the want list is an optional, defaulted field with its own merge rule and a syncLayout bump
  (docs/SYNC.md), or reuses To read with a tag; decide, explain in your report.
- Do not edit files other engineers own (ask the lead which those are today).

READ FIRST: docs/OPUS_HANDOFF.md, docs/ENGINEERING.md, docs/CATALOG.md (search ranking, known limits), docs/SYNC.md,
Leaf/Services/BookCatalog.swift, Shared/CatalogQuery.swift, Shared/Recommender.swift (TasteProfile, reasons),
Shared/ReadsHistory.swift (readThroughs), the ISBN scanner added with the import work (grep ISBN), Leaf/Features/Search,
docs/reports/agent2-review.md.

TASKS
1. Shared/ShopVerdict.swift: given a Book (or several candidates), the library, sessions, wpm and a TasteProfile, return
   a verdict: owned (shelf), read before (dates, rating), time to read, taste fit with one plain reason, and a
   "probably the same book" flag for near-duplicate titles and editions (title normalisation as in CatalogQuery).
   Tests: editions with different page counts, rereads, dismissed books ("you said not for you"), empty libraries.
2. ISBN path: map a scanned ISBN to a catalog work offline where possible; when not, search by the title the scanner
   saw, then the optional Open Library lookup with the reader's consent. Never block on the network.
3. The screen: reachable from Search ("In a bookshop?") and a Shortcut. Big field, scan button, want list, verdict card
   with Add to To read / Want / Not for me.
4. Staging and screenshots: shop.empty, shop.owned, shop.new, shop.reread, light and dark, large type.

ACCEPTANCE
- Linux tests and CI green; screenshots reviewed.
- Works in Airplane Mode with the bundled catalog; a book not in the catalog still gets a useful answer.

REPORT: end with
=== REPORT FOR LEAD ===
Feature: Bookshop mode
Status: done | partly done | blocked
Commits pushed to main: <short shas and one-line messages>
CI: <last run id, green or red>
Model and sync changes: ...
Screens and staging names (with screenshot files): ...
Could not verify (device-only): ...
Decisions the owner should know or veto: ...
Follow-ups: ...
=== END REPORT ===
```
