# First-use tips: report

```
=== REPORT FOR LEAD ===
Package: First-use tips (owner's ask 2026-10-23: "a nice tutorial that is not intrusive but walks you through the
  basic fundamentals of the app as you explore yourself")
Status: done. Commits 91e6e27, f15e3ea (tuck-away note clear of the timer), 0d635d9 (floating notes lift by their
  own height; Library points up at plus). CI run 40052878904 (a850f35): build, tests, watch, archive, screenshots green
What it does:
  Seven short glass notes, each shown beside the one thing worth knowing on a screen, the first time the reader gets
  there. One per screen at a time, one per visit. A note goes for good when it's closed or when the reader does what
  it says; one that's ignored shows on three launches at most. Nothing dims or blocks; the screen works as normal.
  Settings > About > Show tips again brings them all back (so does Erase all data).
The tips (Shared/FirstUseTips.swift):
  today.start       Today, under Steep / Begin       "Two ways to begin"         done when a session opens
  session.nook      Reading timer, over the extras   "Make it your nook"         done when Scene or Sound opens
  session.minimize  Reading timer, next visit, same  "Your timer keeps going"    done when the session is tucked away
                    spot over the extras (the timer stays clear)
  plan.times        Plan, under today's times        "Your reading times"        done when a time or book changes
  library.add       Library, over the shelves        "Add a book"                done when Search opens
  book.page         A book you're reading            "Not on this page?"         done when "Where are you?" opens
  you.corner        You, over the summary            "Make Leaf yours"           closed only
Why not TipKit: the notes had to look like Canopy (accent glass, Focus In, the haptics map), stay out of every other
  screenshot and the App Store set, come back from Settings without a relaunch, and have their rules tested on Linux.
  TipKit's popovers also fight the session's sheets. The rules are a page of plain Swift instead.
New files:
  Shared/FirstUseTips.swift                 FirstUseTip (words, place, symbol), FirstUsePlace, FirstUseJournal
                                            (seen / done, three launches), FirstUseStage (one out per place)
  Leaf/Services/FirstUseTipStore.swift      FirstUseTips.shared: the journal in UserDefaults, arrive / leave / finish
  Leaf/DesignSystem/Canopy/CanopyTip.swift  CanopyTip (the note) and CanopyTipShape (card + soft pointer, one glass)
  Leaf/Features/Tips/FirstUseTipModifier.swift  .firstUseTip(_:edge:pointer:floating:isAvailable:)
  LeafTests/FirstUseTipsTests.swift         9 tests (order, three launches, one per visit, staging, reset)
Touched: one modifier line each in TodayNook, SessionView (2 + the two sheets), PlanView, LibraryView,
  BookDetailView, YouView; AppRouter (finish hooks), MainTabs (tucked-away hook), SettingsView (row + erase),
  LaunchOptions (-LeafTips), scripts/ci_screenshots.sh (ft1 to ft7, ft2 light and dark, lt-ft2 at a large size),
  docs/design/DESIGN_SYSTEM.md (§1 exception, §10 component, §12 rules).
Verified: scripts/linux_tests.sh green (9 new); scripts/check_pbxproj.py OK; ft1 to ft7 and lt-ft2 checked by eye.
  The first shots caught the timer's note sitting on Pause / Done (an ignored alignment guide); fixed in 0d635d9.
Could not verify (device only):
  The close button where a floating note hangs past its row; the Focus In arrival; the note on a small phone (SE).
Next package you recommend: look at the ft-* shots with the owner and tune the words.
=== END REPORT ===
```
