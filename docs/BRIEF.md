# Leaf — product brief

Leaf is a native iOS reading planner (SwiftUI, iOS 26+, Xcode only, no third-party
dependencies, no accounts, everything stored on device).

## What it does

1. **Reading speed test (onboarding).** The user reads a short original passage
   (~300 words) while Leaf times them, then answers 3 quick comprehension
   questions. Result: words per minute (WPM), adjusted by comprehension. They can
   retake it any time from Settings. Real reading sessions later refine the WPM
   automatically.
2. **Daily time.** The user picks how many minutes a day they read (5–180), and
   which days of the week.
3. **Library with three shelves:** *Reading* (currently reading, with current page),
   *To read* (an ordered queue the user can reorder), *Finished*.
4. **Book catalog.** A bundled offline catalog of several thousand popular and
   classic books (title, author, year, page count, estimated word count, Open
   Library cover id, subjects). It merges with live Open Library search (free, no key)
   when online. Users can also add a book manually or edit its page count.
5. **Reading plan.** From WPM, daily minutes, reading days, and the
   Reading + To read order, Leaf simulates day by day and produces a finish date
   for every book, plus *today's assignment*: "22 min of The Hobbit, about pp. 142–158".
   Two modes: *One at a time* (focus) and *Side by side* (split the daily time
   across everything in Reading).
6. **Reading session.** A full-screen timer for reading now. When the user ends
   it, they enter the page they reached. That updates progress, logs the session
   (streaks and stats), and recalibrates WPM.
7. **Daily reminders.** Local notifications (UNUserNotificationCenter) at a
   time the user picks, personalized with that day's assignment. They are rescheduled
   whenever the plan changes, and today's reminder is skipped once today's goal is met.

## Feel

- Visual direction: **editorial paper + Liquid Glass**. Warm paper backgrounds,
  serif display type, ink text, and generous whitespace (a literary magazine),
  combined with iOS 26 Liquid Glass for floating, interactive chrome (tab bar,
  toolbars, primary buttons, timer controls, sheets).
- Unique, beautiful, intuitive. Put real care into the signature moments.
- **Rich haptics** throughout: Core Haptics custom patterns for signature moments
  (page turn, finishing a book, countdown heartbeat), plus selection ticks on dials and
  pickers, impacts on presses, and success/warning notifications.
- Light and dark mode (dark = "paper at night", warm, not pure black).
- Accessible: Dynamic Type friendly, VoiceOver labels, Reduce Motion respected.

## Tech constraints

- SwiftUI, iOS 26.0 deployment target, Swift 5 language mode, Xcode 26 SDK APIs only.
- No packages, no Expo, no backend. Open Library HTTP API only (search + covers).
- Fonts: system SF Pro + system serif (New York, `.serif` design), plus optionally one
  bundled OFL display face (e.g. Instrument Serif), registered at runtime.
- Persistence: Codable JSON file in Application Support.
