# Reading circles as a shared race (2026-10-23)

Matt's ask before App Store review: circles felt like a gimmick. They should work like Apple Fitness competitions:
invite the people reading the same book, see where they really are, and set goals for where everyone needs to be by
a date. No moving other people along by hand. Plus a circle card on Today, right under "Where you left off", with
everyone's progress next to yours, or a dismissible suggestion and how-to when there's no circle yet.

Engine's iCloud sharing (247b174, `CircleSharing`) already did the plumbing: invitations by CKShare, friends joining
as their own member, each person's page written from their own library. This package is the model and UI on top of
it. Nothing in CloudKit, entitlements or the TestFlight script was touched.

## What changed

**Model (Shared/Circle, Linux-tested).**
- Meetings are now *goals* in every word on screen ("page 200 by Thursday"). The type is still `CircleMeeting`, so
  sync records don't change. `CirclePlanner.goals(pages:startsOn:finishBy:everyDays:)` plans them from a finish date:
  a goal every week, every two weeks, or just the finish.
- `CircleMember.log`: where someone's page moved, at most 40 `CircleCheckIn`s, the first one where they started (so
  joining at page 80 doesn't count as reading 80 pages). Moves within 30 minutes fold into one sitting.
  `CircleShareRules.withMyPage` now writes through `CircleMember.move(to:at:)`, so friends get the log with the page.
  The reader's own log comes from their sessions (`CircleCheckIn.log(from:bookID:)`).
- The snapshot adds standings: place (ties share it), pages today and this week, goals met by their day, pages to the
  goal, and a line on where the reader stands ("You're 16 pages behind Sam."). `CirclePlanner.activity` lists
  sittings, goals reached, finishes and joins from the last 14 days.
- Tests: 9 new in `LeafTests/CircleTests.swift`; all 912 Linux tests pass.

**Circle page (You › Circles).**
- The goal card: "Goal 2 of 4", a countdown chip, **Page 200** big, and a track through the book with everyone's
  face where they've read to and the next goal flagged in Dusk.
- Standings: crown for the leader, a bar to the goal, "Goal met" or "12 to go", "+12 today", leaf medals for goals met.
- Lately: "Sam read 24 pages", "Priya reached page 100, Thursday's goal", "Jo joined at page 12".
- Questions to talk over (unchanged deck), then the goals, each with the faces of who made it.
- Inviting is the way in: a new circle goes straight to the invitation when iCloud is on; a circle that's just you
  shows an invite card; "Invite" sits on the standings. Before the first invitation the reader gives a name, so
  friends don't see the owner as "You". With iCloud off, the alert offers Settings; builds without iCloud (Debug,
  CI) say invitations need the App Store or TestFlight version.
- Friends who joined can't be moved by hand; their sheet shows their page, today, this week and goals met. Friends
  added by name in older circles keep the page editor, with a note to invite them.
- New circle: book, name, finish date (2/4/6/8 weeks or a date), goal cadence, where you'll talk (optional), your name.

**Today.** `TodayCircleCard` sits right after "Where you left off" (between books: under the deck). With a circle
under way: its soonest goal ("Page 200 by Thursday · 3 days left"), a bar per person through the book with the goal
as a Dusk tick lined up down the rows, and where you stand. Tap opens that circle. With no circles at all: "Read with
friends, and race to the page", a little sample race, the three steps, "Start a circle" (opens the new-circle sheet
on You) and "Not now" / × (remembered on the device, `today.circleTipDismissed`).

**Staging and shots.** `-LeafScreen plan.circles.standings | .goals | .name`, `-LeafScroll circles`,
`-LeafScenario nocircles`. New shots e07–e11 (and e12 light/dark). Demo circle friends now joined from an invite,
with a week of sittings, so the standings and Lately look lived in.

## NEEDS FROM ENGINE

Engine answered the first list in b609363 (ENGINE REPORT 2, 2026-10-23):

1. **Live pages: done.** Silent pushes (a shared-database subscription and one per owned circle zone) call
   `CircleSharing.refreshForPush()`, and while the app is in front it polls every 3 minutes when a circle is shared.
   Fetches never overlap, so the Circles page's `connect()` on appear stays.
2. **The book for joiners: done.** Joining puts the circle's book on Reading (`LibraryStore.addCircleBook`), matching
   a copy they already have by id, else title and author. The circle screens use `store.circleItem(for:)`.
3. **Two-account test: still to do**, on a TestFlight build of b609363 or later (Caleb's checklist in docs/SYNC.md).
   Circles are App Store screenshot 7, so a reviewer may try an invitation.
4. **After 1.0: Fitness-style notifications**, opt-in: a friend reached the goal, someone passed you, the goal is
   tomorrow and you're behind. `refreshForPush` already knows when a circle changed.

The member log rides inside the existing encrypted `LeafCircle` payload (about 3 KB per member at most), and older
copies decode with an empty log.

## CI

Run 40035684607 on b940719 (my 690837d plus Engine's b609363) is green: build, tests, archive and every screenshot.
Shots reviewed: e07 standings, e08 goals, e10/e12 Today card (light and dark), e11 the suggestion, e02 new circle,
e03 a friend. The You tab now opens on "Make it yours", which pushed the circle page below the fold in e01 and in
App Store shot 7, so `-LeafScreen plan.circles` (and Today's card) now scroll You to the circle.

## Known limits

- Anyone in a shared circle can edit the goals (the share is read-write). If Matt wants owner-only goals, that's a
  share permission and a small UI change.
- The reader's own "pages today" counts timed sessions; a page set by hand under "Where are you?" moves the bar but
  doesn't show up as a sitting.
- Untested on a device: there is no Mac here, so the CI build and screenshots are the check.
- Opening a circle from Today scrolls You after the tab's usual 700 ms staging pause.

## Next package I recommend

The two-device pass on a TestFlight build. After that, a circle line on the Today widget.
