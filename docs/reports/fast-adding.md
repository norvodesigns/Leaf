# Fast book adding (assignment A)

Adding a book should take seconds. Built first on the paper design (27df227), then moved to Canopy / Oat (90567e6).

## What shipped

- **Search as you type.** Every keystroke searches the offline FTS catalog. Open Library results are merged in after
  a 250 ms pause.
- **One tap to add.** The glass `+` on a result adds the book to Up next, plays a light page-turn (`CanopyFeel.pageLogged`)
  and shows an Undo toast for five seconds (REDESIGN §4.3). Touch and hold for Start reading, Up next, Want to read
  later, Already read, or More options. A book already on a shelf shows a Forest checkmark, and tapping it opens the
  quick-add sheet. Adds from the browse carousels get the same toast.
- **Quick-add sheet** (`Search/QuickAddSheet.swift`): a `.medium` system-glass sheet with the book (it arrives with
  Focus In), its year, pages and how long it takes at the reader's pace. Start reading is the screen's Hero
  (`.startNow`). Want to read, Up next and Already read are Forest glass. Already read uses the shelf's own
  `bookFinished` moment.
- **Barcode scan** (`Search/ISBNScanSheet.swift`): VisionKit `DataScannerViewController`, EAN-13 starting 978 or 979.
  Each ISBN is looked up once, and the camera stops while a lookup runs. Open Library `search.json?q=isbn:` finds the
  work, and the catalog's copy is preferred. If the camera is denied, the sheet links to Settings. With no camera
  (the simulator), the screen is the typed ISBN. A found book opens the quick-add sheet. When the book isn't found, has
  no page count, or the lookup is offline, the reader goes to the hand form with whatever was learned.
- **Typed ISBN.** An ISBN-10 or ISBN-13 typed into Search is looked up directly. A partial one shows a hint instead
  of title matches.
- **Hand form that isn't annoying** (`Book/AddBookManuallyView.swift`): it opens with the query as the title, or with
  what the barcode found, and puts the cursor in the first empty field. Most books need only a page count. The fields
  sit in a glass card, numbers are rounded, and Start reading is the Hero.
- **Entry points:** the Library's add menu (Search, Scan, By hand) and Search's barcode button. "Add by hand" and
  "Scan a barcode" also appear under every result list.
- **Shared/ISBN.swift:** parse (hyphens, "ISBN" prefix, ISBN-10 to ISBN-13 with an X check digit), the barcode
  check and `looksLikeISBN`, tested in `LeafTests/ISBNTests.swift`.
- **OpenLibrary.lookup(isbn:)**, which returns an `ISBNMatch` (`pages` is nil when unknown).

## Screenshots

`a01-add-quick` (+dark), `a02-add-added` (the toast), `a03-add-scan` (+dark), `a04-add-manual` (prefilled),
`a05-add-isbn` (a typed ISBN for Dune).

## Eyeball on a device

- Scan the back of a real paperback. It should come up within about a second, once only, and the camera should stop
  while it looks up. Try a book with no barcode ISBN (a price sticker or an EAN-5) and check it is ignored.
- Deny camera access, then reopen the scanner: it should show the Settings link and the typed field.
- Tap `+` on a result. The book should be on Up next with a light page-turn, and Undo should take it off again.
- At AX sizes the quick-add sheet should open full height with the buttons stacked.

## NEEDS FROM ENGINE

- ~~The catalog has no ISBN column, so scanning and typed ISBNs need a connection.~~ Done 2026-10-22: `isbns` table
  in `catalog.sqlite` (see docs/CATALOG.md); `ISBNLookup` asks the catalog first.
- "Already read" from Search uses `store.add(book, to: .finished)`, which dates the finish today. That counts toward
  this year's stats. A "read before Leaf" add (`addEarlierRead` without a date, or a flag) would be more honest.

## Known issues

- Goodreads and StoryGraph CSV import was not built (NEXT.md lists it with ISBN scan).
- Open Library's `number_of_pages_median` is the work's median, not the scanned edition's. "Where are you?" has the
  edition picker when the counts differ.
