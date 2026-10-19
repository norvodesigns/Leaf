# UI-3 report: blur language, physical ribbon, scrub numbers, cozy palette

```
=== REPORT FOR LEAD ===
Package: UI-3 (Motion and blur language in Leaf/DesignSystem)
Status: done
Commits pushed to main:
  e45a9ef UI-3: motion language — blur, cover backdrops, scenes, physical ribbon, scrub numbers
  7745450 UI-3 review fixes: rain drops, finish-by labels, drum in reading times
  (plus this report, committed with the first UI-4 push)
CI: run 39211138625 (e45a9ef) green: build and test, watch, unsigned archive, zero warnings, 79 screenshots.
  Run 39237985109 (7745450) green through build, test, archive and warnings.
  Screenshots now reach this session: CI pushes the JPEGs to the hidden ref refs/ci/screenshots and
  `python3 scripts/ci.py shots` falls back to fetching it over git, because the network policy blocks GitHub's
  log and artifact storage host. The UI-1 and UI-2 screenshots were reviewed this way too (fixes below).
Screens / states built (staging name -> screenshot file):
  Design system page with a Motion entry      -LeafScreen gallery          -> 60-gallery
  Cozy palette tokens, tea liquors            -LeafScreen gallery.palette  -> 61-gallery-palette
  Focus pull, numeric and per-digit blur,
    blurred cover backdrops                   -LeafScreen gallery.blur     -> 62-gallery-blur(-dark)
  Bokeh, rain on glass, steam + calm slider   -LeafScreen gallery.scenes   -> 63-gallery-scenes
  Physical ribbons on covers, tuck-away,
    the ribbon as the page control            -LeafScreen gallery.ribbon   -> 64-gallery-ribbon(-dark)
  Minutes, pages, steep time scrub numbers    -LeafScreen gallery.scrub    -> 65-gallery-scrub(-dark)
  Finish-by date scrub, time drum             -LeafScreen gallery.drum     -> 66-gallery-drum
  Applied: book detail cover backdrop -> 15-book(-dark); Today blurs behind an open book (focus pull);
  numeric blur on the big numerals (Where are you?, session page, book detail page sheet, Today minutes,
  Settings wpm); the reading-time editor's time is now the TimeDrum -> 39-readingtimes-edit.
New public types or files (one line each):
  Leaf/DesignSystem/Blur.swift              FocusPullTransition (.focusPull), .focusPull(isFocused:), .focusPullTransition(),
                                            .numericBlur(value:velocityBlur:), DigitBlurRenderer (TextRenderer), PerDigitBlurText
  Leaf/DesignSystem/CoverBackdrop.swift     BlurredCoverBackdrop(book:scrim:), CoverBackdropRenderer (pre-render + cache), CoverBackdropArt
  Leaf/DesignSystem/AtmosphereScene.swift   AtmosphereScene(kind: .bokeh|.rain|.steam, calm:density:tint:seed:), 15 fps Canvas
  Leaf/DesignSystem/PhysicalRibbon.swift    PhysicalRibbon (RibbonSimulation drawn as satin), RibbonTilt (Core Motion, 30 Hz, shared)
  Leaf/DesignSystem/RibbonPageControl.swift RibbonPageControl(page:pages:startPage:) on RibbonDepthMapping, typed + VoiceOver fallbacks
  Leaf/DesignSystem/Scrub.swift             ScrubController (observable ScrubModel), ScrubRuler (Canvas), ScrubNumber, .scrubsHorizontally
  Leaf/DesignSystem/ScrubVariants.swift     SteepTimeScrub, FinishByScrub (DateScrub), TimeDrum, DrumWheel
  Leaf/DesignSystem/MotionGallery.swift     debug-only gallery pages for the above
  LeafColor.swift                           cozy tokens teaPaper, chai, matcha, rooibos, steam, amber, rose (light/dark); CozyColor aliases them
  Haptics.swift                             .magnetSnap, .boundsHit, scrub(_ ScrubHapticEvent), continuous stretch (begin/update/endStretch)
  TickRuler.swift                           rebuilt on ScrubController (same API): every MinutesDial/PageScrubber gains flick,
                                            rubber band, magnets, velocity blur
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  ScrubModel/ScrubConfiguration/ScrubFeedback, RibbonSimulation (+ reducedMotionPose), RibbonDepthMapping, DateScrub,
  AtmosphereField + AtmosphereClock. All behaved as documented; nothing missing. No Shared/ changes.
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/ (engine fixes, project file):
  .github/workflows/ios.yml: contents: write, a step that force-pushes the screenshots to refs/ci/screenshots,
    job 75 min / Screenshots 40 min. scripts/ci.py: `shots` falls back to that ref. scripts/ci_screenshots.sh: gallery shots.
  No project file changes (synchronized folders).
Could not verify (device-only things):
  Core Haptics patterns (detents, magnet snap, bounds knock, the continuous stretch), tilt from Core Motion, how the
  ribbon tug and flick feel under a finger, scrub coasting feel, Low Power Mode pausing, ProMotion frame pacing.
  The simulator shows the still frames; the motion itself needs a phone.
Design decisions the owner should know about or veto:
  - Cozy tints live in LeafColor now (atmosphere only, never text or state); CozyColor keeps working as aliases.
  - TickRuler keeps its API but runs on the shared scrub engine, so the existing dials changed feel everywhere.
  - Cover ribbons hold still unless asked (idle .still); only the Today hero breathes, then sleeps. Tilt is only
    published when gravity really changes, so a phone on a table costs nothing.
  - Book detail's stage is the blurred cover (mesh + pre-rendered blur + paper scrim) instead of the 18% average wash.
  - Today softens (6 pt, 70%) while a book is open over it; the steep countdown's blur ceiling dropped to 2.2 pt so
    the time stays readable.
Known issues / follow-ups, most important first:
  1. Haptic intensities are first guesses; tune on a device.
  2. Steam wisps on light paper read a little grey; worth a softer tint once seen on a phone.
  3. RibbonPageControl is built and in the gallery but not yet the page sheet's default control (kept the
     PageScrubber there; easy swap once it has been felt on a device).
Fixes from reviewing the UI-1/UI-2 screenshots (in 7745450): Live Activity buttons no longer wrap ("Re-sume"),
  steep countdown readable, reading-times intro aligned with its rows.
Next package you recommend: UI-4 (in progress in this session).
=== END REPORT ===
```
