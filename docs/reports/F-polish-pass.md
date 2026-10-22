# F. Known gaps and polish pass: report

Final commit of this pass on main: e5d5fa9
CI for e5d5fa9: green (build, all tests, watch build, archive, screenshots), run 39731550204
https://github.com/norvodesigns/leaf/actions/runs/39731550204

## Before the redesign (on the paper look)
- "Read without tea" on the tea screen is a real button. The Today top gap and "Begin reading" were already fixed upstream.
- 44 pt tap areas for text links, chip buttons, the tea-rating leaves, the session bar's button and Wrapped's buttons.
- Plan: the tabs fit at large text, and long titles wrap instead of being cut off. The tasting wrap-up opens tall, with paper behind Done.
- Today: a band of paper under the clock once you scroll. The tea-rings chart fades at its left edge.
- An empty state for the reading log.
- CI: a large-text screenshot sweep (lt-*) of the main screens and the watch.

## On Canopy (after the redesign)
- Haptics: History, Tea, Position and Settings call CanopyFeel. I added `CanopyFeel.saved`, and a saved reading time plays `.planChanged`.
- Settings: cream rows on the backdrop, section labels in each job's accent (Dusk for reading, Clay for tea), Canopy type, the pace as a CanopyStat, Data before About. The tour row is gone.
- Where are you: a black hero to confirm, and the typed-page field is no longer hidden behind the buttons.
- History (reading log, the numbers, book timeline, quote cards): Canopy type and colours, Bloom labels, glass range chips, a black Share hero beside a matching glass Save.

## Files
Leaf/Features/Settings/*, Leaf/Features/History/*, Leaf/Features/Position/WhereAreYouSheet.swift, Leaf/Features/Tea/* (haptics only),
Leaf/DesignSystem/Canopy/CanopyFeel.swift (.saved), Leaf/DesignSystem/ButtonStyles.swift (TextButton hit area), scripts/ci_screenshots.sh (lt-*).
Earlier commits also touched Plan, Today, Session and Wrapped files; those screens have since been rebuilt by the redesign.

## Screens to check on a device
- Settings in light and dark at the largest text size. Check that the "Brisk" pill and the long rows wrap cleanly.
- The quote card in dark mode. Check that the black Share hero stands out enough on the charcoal sheet.
- Where are you: type a page with the keyboard up, and check that the field stays visible above the buttons.

## NEEDS FROM ENGINE
None.

## Known issues / skipped
- StatTile and StatTileRow (the numbers' headline tiles) are still the old component, though they now use the Oat colours.
- In Tea, I only changed the haptics, since the redesign thread is restyling Tea.

## Ideas (value / effort)
- A Canopy version of StatTile shared by You, Insights and History (medium value, low effort).
