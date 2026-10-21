# Today fixes: report

```
=== REPORT FOR LEAD ===
Package: Today fixes (ribbon tilt, the reading buttons, the nook to the top edge)
Status: done (device-only checks listed below)
Commits pushed to main:
  a63477d Today: Steep and read beside Begin reading, the nook's light up to the top edge, a still ribbon
CI: run 39655925407 (a63477d): every step green (build, all unit tests, watch build, unsigned archive, warnings,
  screenshots published); GitHub lists the run as cancelled only because my next push (c932db9) cancelled its
  final housekeeping. Screenshots reviewed in light and dark.
What changed, and the decisions:
  1. The ribbon: tilt removed, everywhere it appears (Today's book, covers, the ribbon page control). I couldn't make
     tilt feel good without a device to hold, so I chose removal, as the brief allowed. The ribbon now hangs still,
     sways once to settle when it first appears, gives a small nudge when the page is set (instead of restarting
     its swing), and ribbons on covers never take a drag from a scroll. Drag on Today's ribbon is unchanged.
     The shelf wall's parallax (shadows only, filtered) is a separate thing and stays.
  2. "Read without tea" is now "Begin reading" (the owner's wording): a solid ink button paired with "Steep and
     read" in glass, side by side when they fit and stacked at large text sizes, with the helper line kept under the
     tea chip. On a rest day "Begin reading" is an ink outline and the glass button reads "Steep and read anyway", so
     neither pushes.
  3. The empty band at the top of Today is gone: the nook's light (its daypart gradient) runs behind the status bar
     and the gear to the top edge, and the content keeps its place below the safe area.
Screens / states built (staging name -> screenshot file; reviewed in light and dark):
  Today, evening                       -LeafScreen today -LeafTime 20:30          -> 10-today(-dark)
  Morning, late, rest day, goal met, between times     -LeafScreen today (-LeafTime / -LeafScenario)
                                                       -> 20-today-morning, 21-today-late, 22-today-rest,
                                                          23-today-goalmet, 24-today-between
  Today scrolled to the tea week       -LeafScreen today -LeafScroll teaweek       -> 117-today-teaweek(-dark)
  Today with the Wrapped offer         -LeafScreen wrapped.offer                   -> 141-today-wrapped(-dark)
  Today at accessibility text sizes    -LeafScreen today (AccessibilityM)          -> 143-today-largetype (new)
  Rest day at accessibility sizes      -LeafScreen today -LeafScenario rest (AccM) -> 144-today-rest-largetype (new)
New public types or files (one line each):
  InkButton (Leaf/DesignSystem/PrimaryGlassButton.swift): the solid or outlined ink button
  NookAtmosphere.edge(daypart:) / NookEdge: the colour the nook's light has at the top edge
  RibbonTilt removed from PhysicalRibbon; PhysicalRibbon gained nudge and isInteractive
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  None beyond the views; onScrollGeometryChange for the top inset.
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/:
  docs/DESIGN_SYSTEM.md (ribbon and buttons), scripts/ci_screenshots.sh (143, 144).
Could not verify (device-only things):
  How the still ribbon feels in the hand; the light behind the status bar on a phone with the Dynamic Island in
  both appearances; the button pair at every Dynamic Type size on a small phone.
Design decisions the owner should know about or veto:
  - Tilt is gone from the ribbon for good unless asked back; Core Motion now runs only for the shelf wall.
  - "Begin reading" is ink (the strongest thing on screen) and "Steep and read" glass, side by side: both are first-
    class ways in; tea is the default suggestion only by being listed first.
Known issues / follow-ups, most important first:
  - Scrolled down, Today's cards pass under the clock with the system's soft scroll-edge fade rather than a band of
    paper (117, 141). That is how the full-bleed top works on iOS 26; if it reads as busy on a device, a short
    paper-coloured fade at the very top is a two-line change.
  - At accessibility text sizes the pair stacks and "Begin reading" sits below the fold, under the session bar, until
    the reader scrolls (143, 144). Both are reachable; the nook itself is taller at those sizes.
Next package you recommend: Widgets.
=== END REPORT ===
```
