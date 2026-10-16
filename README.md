# Leaf

A reading planner for iPhone and Apple Watch. Take a two-minute reading speed
test and tell Leaf how long you read each day. It turns your **Reading** and
**To read** shelves into a day-by-day plan, with a finish date for every book
and today's pages ("22 min of *The Hobbit*, pp. 142–158"). A gentle reminder
arrives at the time you choose.

Native SwiftUI, iOS 26 / watchOS 26, Liquid Glass. No accounts, no servers, no
third-party code. Everything lives on the device.

**Shipping to TestFlight? Start with [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md).**

## Features

- **Reading speed test.** Read a short original passage, answer three quick
  questions, and get your words per minute, weighted by comprehension. Real
  sessions keep refining it.
- **Shelves.** Reading, To read (drag to reorder, and the plan reflows), and Finished.
- **Thousands of books offline.** A bundled catalog of popular and classic books
  with page and word counts, plus live Open Library search when online. You
  can also add any book by hand.
- **The plan.** One-at-a-time or side-by-side reading, rest days, finish dates,
  and a timeline that reflows when you change your daily minutes.
- **Reading sessions.** A full-screen timer. When you stop, log the page
  you reached, and Leaf updates your progress, streak, and speed.
- **Daily reminders.** Local notifications personalised with that day's
  assignment, plus a quiet nudge when you hit today's goal.
- **Apple Watch.** Today's ring and assignment, and a live session timer that
  runs in parallel with the phone (start on either, see it on both). Log the
  page you reached with the Digital Crown, and feel a wrist tap at your goal.
- **Haptics.** Core Haptics patterns for the signature moments: page turns,
  finishing a book, the speed-test countdown, and dial detents.

## Layout

```
Leaf.xcodeproj        Xcode project (synchronized folders: add files and they're in)
Shared/               Plain-Foundation logic used by both apps: models, planner,
                      reading speed, stats, formatting, watch sync payloads
Leaf/                 iPhone app
  App/                entry point, router, launch options, demo data
  Services/           store + persistence, catalog search, Open Library,
                      reminders, haptics, watch bridge
  DesignSystem/       colors, type, and components
  Features/           Onboarding, Today, Library, Plan, Search, Book, Session, Settings
  Core/               speed-test passages
  Resources/          asset catalog, bundled books.json, fonts, privacy manifest
LeafWatch/            Apple Watch app
LeafTests/            unit tests (Swift Testing)
scripts/              catalog builder (Open Library → books.json), CI helpers
docs/                 TestFlight guide, privacy policy, design spec
```

## Running it

Open `Leaf.xcodeproj` in Xcode 26 or later, pick an iPhone simulator, and press
**⌘R**. Run the tests with **⌘U**.

Debug builds accept launch arguments that stage screens with sample data, which
is useful for screenshots. For example:

```
-LeafDemo YES -LeafScreen plan
```

## Rebuilding the book catalog

```bash
python3 scripts/build_catalog.py   # Python 3 standard library only; caches responses in scripts/.cache
```

## Credits

Book data and covers from [Open Library](https://openlibrary.org).
Display type: [Instrument Serif](https://github.com/Instrument/instrument-serif) (SIL Open Font License).
