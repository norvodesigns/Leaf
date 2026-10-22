# Ask the Librarian (assignment B)

A written, offline conversation that ends in a shelf of picks. Nothing is spoken, and no network AI is used.

## What shipped

- **Engine, `Shared/Librarian.swift`** (Foundation-only, tested in `LeafTests/LibrarianTests.swift`).
  `LibrarianAsk` (mood, time, length) → `Librarian.answer` → `LibrarianAnswer` (picks, every match, what was loosened).
  - Moods are the carousel moods: `CollectionBuilder.moods` became internal instead of private. Only its visibility
    changed.
  - Time is measured at the reader's own pace: Just tonight (up to 3 h), A weekend (up to 8 h), This week (fits in
    seven days of their daily minutes), Something to live in (two weeks or more). Length is in pages: Slim, Middling,
    A doorstop, Any.
  - The recommender orders the matches (one per author), so personal taste still leads.
  - When fewer than 8 books fit, it loosens length first, then time, then how strictly the mood must match, and the
    reply says which it loosened.
  - The "why this" line is always true. It uses the recommender's personal reason when there is one ("Because you
    finished X"); otherwise it names the strongest themes the book shares with the mood ("Tea & cafes and cats, for a
    cozy mood"). A fit line follows: "About 5 h, a weekend at your pace".
  - `LibrarianLines` holds the librarian's written copy. A test checks every line against `VoiceTone`.
- **UI, `Leaf/Features/Librarian/`** (Canopy, Oat; Forest as the accent).
  - `LibrarianModel`: the conversation (mood, time, then length, which is skipped when the time already settles it).
    The search runs off the main thread. "Show me others" never repeats a book. "More like this" uses
    `catalog.similar`. "Start over" keeps the conversation on screen.
  - `LibrarianScreen`: the librarian's notes on glass beside a lamp avatar, the reader's answers in Forest glass on
    the right, the answers as `CanopyChip`s (time chips in Dusk) in a wrapping layout, and new entries arriving with
    Focus In.
  - `LibrarianShelf`: a carousel of glass cards with the cover, title in New York, the "why this" line with a Forest
    mark, and the fit line with a Dusk clock. Want to read (`.keep`) and Start (`.startNow`) are glass buttons.
    More like this and Not for me (with Undo) sit in the context menu and the VoiceOver actions.
  - "Swipe through the shelf" opens the existing swipe deck, dealt from everything that matched.
  - `LibrarianBanner` is the way in. It's on Search now, and the redesign thread is putting it at the bottom of
    Library.
- **Screenshots:** `-LeafScreen librarian` (B1, the first question) and `librarian.answer` (B2, Cozy + A weekend
  answered), in light, dark and large text (`lt-B2`).

## Device checks

- Search → Ask the Librarian: tap a mood, a time and a length, and the picks scroll into view. Check that the chips
  wrap cleanly at the largest text size.
- On a pick, tap Want to read and Start; the card should show "On your To read" or "Reading now". Long-press for
  More like this and Not for me, then Undo.
- Show me others should bring only new books. Swipe through the shelf should keep and pass straight into the library.
- With Reduce Motion on, replies should appear without the writing pause and arrive as a crossfade.

## Needs from engine

- None blocking. At the 250k catalog, `Librarian.matches` scans the whole browse pool (about 25k books) once per
  answer, off the main thread, in milliseconds. If the pool grows a lot, a SQLite prefilter on theme or genre keys
  would keep it fast.
- Nice to have: a `TasteProfile` hook so "Not for me" from the librarian could also say why (too long, not this
  mood).

## Known issues

- "If you like X, try these." is an inline string in `LibrarianModel` rather than in `LibrarianLines`, so the voice
  test doesn't cover it.
- The thinking pause is a fixed 0.65 s.
