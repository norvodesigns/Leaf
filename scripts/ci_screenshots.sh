#!/bin/bash
# Stages screens with debug launch arguments and captures them on the simulators.
set -uo pipefail
OUT="${1:-screenshots}"
mkdir -p "$OUT"
APP="build/Build/Products/Debug-iphonesimulator/Leaf.app"
WATCH_APP="build/Build/Products/Debug-watchsimulator/LeafWatch.app"
BUNDLE=com.norvodesigns.leaf
WATCH_BUNDLE=com.norvodesigns.leaf.watchkitapp

boot() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
}

boot "$IOS_SIM"
xcrun simctl status_bar "$IOS_SIM" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --cellularMode active || true
xcrun simctl install "$IOS_SIM" "$APP"

# A smaller JPEG copy of one shot, printed as base64 right away so it can be read from the job log even if the step
# is cut short (scripts/ci.py shots).
emit() { # name
  local n=$1
  mkdir -p "$OUT/jpg"
  sips -s format jpeg -s formatOptions 72 -Z 1100 "$OUT/$n.png" --out "$OUT/jpg/$n.jpg" >/dev/null 2>&1 || return 0
  echo "=====BEGIN $n====="
  base64 -b 120 -i "$OUT/jpg/$n.jpg"
  echo "=====END $n====="
}

shot() { # name wait args...
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$IOS_SIM" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$IOS_SIM" "$BUNDLE" "$@" >/dev/null
  sleep "$wait"
  if xcrun simctl io "$IOS_SIM" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1; then
    echo "captured $name"
    [ "$name" = 00-warmup ] || emit "$name"
  fi
}

# Warm-up launch so Open Library covers are cached for the real shots.
shot 00-warmup 8 -LeafDemo YES -LeafScreen today
rm -f "$OUT/00-warmup.png"

for appearance in light dark; do
  xcrun simctl ui "$IOS_SIM" appearance "$appearance"
  suffix=""; [ "$appearance" = dark ] && suffix="-dark"
  if [ "$appearance" = light ]; then
    shot 01-welcome 4 -LeafScreen onboarding.welcome
    shot 02-speedtest 4 -LeafScreen onboarding.speedtest
    shot 03-quiz 4 -LeafScreen onboarding.quiz
    shot 04-result 5 -LeafScreen onboarding.result
    shot 05-minutes 4 -LeafScreen onboarding.minutes
    shot 06-days 4 -LeafScreen onboarding.days
    shot 07-reminder 4 -LeafScreen onboarding.reminder
    shot 08-firstbooks 5 -LeafScreen onboarding.books
    shot 13-search 6 -LeafDemo YES -LeafScreen search
    shot 14-search-query 7 -LeafDemo YES -LeafScreen search.query
    shot 17-settings 4 -LeafDemo YES -LeafScreen settings
    shot 18-finished 5 -LeafDemo YES -LeafScreen library.finished
    shot 19-outcome 5 -LeafDemo YES -LeafScreen session.outcome
    # Today, one state per shot (DemoData.Scenario + a staged clock).
    shot 20-today-morning 6 -LeafDemo YES -LeafScreen today -LeafTime 07:40
    shot 22-today-rest 6 -LeafDemo YES -LeafScreen today -LeafScenario rest -LeafTime 10:15
    shot 23-today-goalmet 6 -LeafDemo YES -LeafScreen today -LeafScenario goalmet -LeafTime 21:10
    shot 25-today-new 7 -LeafDemo YES -LeafScreen today -LeafScenario new -LeafTime 18:00
    shot 26-today-returning 6 -LeafDemo YES -LeafScreen today -LeafScenario returning -LeafTime 17:20
    shot 27-today-finishing 6 -LeafDemo YES -LeafScreen today -LeafScenario finishing -LeafTime 20:45
    shot 28-today-steep 6 -LeafDemo YES -LeafScreen today.steep
    shot 29-today-newbook 6 -LeafDemo YES -LeafScreen today -LeafScenario newbook -LeafTime 20:00
    shot 31-today-week 7 -LeafDemo YES -LeafScreen today -LeafTime 20:30 -LeafScroll week
    shot 32-today-pick 7 -LeafDemo YES -LeafScreen today -LeafTime 20:30 -LeafScroll pick
    shot 33-today-sidebyside 6 -LeafDemo YES -LeafScreen today -LeafScenario sidebyside -LeafTime 07:10
    shot 35-position-page 5 -LeafDemo YES -LeafScreen position.page
    shot 36-position-percent 5 -LeafDemo YES -LeafScreen position.percent
    shot 37-position-read 5 -LeafDemo YES -LeafScreen position.read
    shot 39-readingtimes-edit 5 -LeafDemo YES -LeafScreen readingtimes.edit
    shot 41-onboarding-deck 8 -LeafScreen onboarding.deck
    # Session: the tea ritual, the cup, the extras (UI-2).
    shot 43-session-steeping 5 -LeafDemo YES -LeafScreen session.steeping
    shot 44-session-ready 5 -LeafDemo YES -LeafScreen session.ready
    shot 46-session-cupdone 5 -LeafDemo YES -LeafScreen session.cupdone
    shot 47-session-paused 5 -LeafDemo YES -LeafScreen session.paused
    shot 48-session-note 6 -LeafDemo YES -LeafScreen session.note
    shot 49-session-ambience 6 -LeafDemo YES -LeafScreen session.ambience
    # Nook scenes: the scene rides in the argument domain, so it isn't saved for the shots after these.
    shot 45a-nook-rain 6 -LeafDemo YES -LeafScreen session -leaf.cozy.nookScene rain
    shot 45b-nook-hearth 6 -LeafDemo YES -LeafScreen session -leaf.cozy.nookScene hearth
    shot 45c-nook-library 6 -LeafDemo YES -LeafScreen session -leaf.cozy.nookScene library
    shot 45d-nook-sheet 6 -LeafDemo YES -LeafScreen session.nook -leaf.cozy.nookScene rain
    shot 45e-nook-large-type 6 -LeafDemo YES -LeafScreen session -leaf.cozy.nookScene hearth -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
    # The Live Activity on a stand-in Lock Screen, with the Dynamic Island regions.
    shot 50-la-reading 5 -LeafDemo YES -LeafScreen liveactivity.reading
    shot 51-la-paused 5 -LeafDemo YES -LeafScreen liveactivity.paused
    shot 52-la-goal 5 -LeafDemo YES -LeafScreen liveactivity.goal
    shot 53-la-cup 5 -LeafDemo YES -LeafScreen liveactivity.cup
    # The design system and its motion pages (Leaf/DesignSystem).
    shot 60-gallery 5 -LeafDemo YES -LeafScreen gallery
    shot 61-gallery-palette 4 -LeafDemo YES -LeafScreen gallery.palette
    shot 63-gallery-scenes 5 -LeafDemo YES -LeafScreen gallery.scenes
    shot 66-gallery-drum 4 -LeafDemo YES -LeafScreen gallery.drum
    # Plan: forecast, insights and challenges (UI-4). The engines run off the main actor, so give them a moment.
    shot 69-plan-reading 8 -LeafDemo YES -LeafScreen plan.reading
    shot 71-plan-whatif 8 -LeafDemo YES -LeafScreen plan.whatif
    shot 72-plan-care 8 -LeafDemo YES -LeafScreen plan.care -LeafScenario returning
    shot 73-plan-order 8 -LeafDemo YES -LeafScreen plan.order
    shot 74-plan-finishline 8 -LeafDemo YES -LeafScreen plan.finishline
    shot 75-plan-suggest 8 -LeafDemo YES -LeafScreen plan.suggest
    shot 77-insights-time 9 -LeafDemo YES -LeafScreen plan.insights.time -LeafScenario year
    shot 78-insights-mix 9 -LeafDemo YES -LeafScreen plan.insights.mix -LeafScenario year
    shot 79-insights-personality 9 -LeafDemo YES -LeafScreen plan.insights.personality -LeafScenario year
    shot 81-weekly-letter 8 -LeafDemo YES -LeafScreen plan.letter -LeafScenario year
    shot 83-stamps 8 -LeafDemo YES -LeafScreen plan.stamps -LeafScenario year
    shot 84-plan-new 6 -LeafDemo YES -LeafScreen plan -LeafScenario new
    shot 85-insights-new 6 -LeafDemo YES -LeafScreen plan.insights -LeafScenario new
    shot 86-plan-large-type 8 -LeafDemo YES -LeafScreen plan -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
    shot 87-share-posters 8 -LeafDemo YES -LeafScreen gallery.posters -LeafScenario year
    # Search browsing, Library, Settings (UI-5). Rows are built off the main thread after the catalog opens.
    shot 91-search-series 10 -LeafDemo YES -LeafScreen search.series
    shot 92-search-author 10 -LeafDemo YES -LeafScreen search.author
    shot 93-search-time 10 -LeafDemo YES -LeafScreen search.time
    shot 94-search-seasonal 10 -LeafDemo YES -LeafScreen search.seasonal
    shot 95-search-seeall 10 -LeafDemo YES -LeafScreen search.seeall
    shot 96-search-similar 9 -LeafDemo YES -LeafScreen search.similar
    shot 97-search-taste 8 -LeafDemo YES -LeafScreen search.taste -LeafScenario year
    shot 98-search-first-use 10 -LeafDemo YES -LeafScreen search -LeafScenario new
    shot 99-search-undo 10 -LeafDemo YES -LeafScreen search.undo
    # Fast book adding: the toast after an add, the hand form prefilled, a typed ISBN.
    shot a02-add-added 11 -LeafDemo YES -LeafScreen search.added
    shot a04-add-manual 11 -LeafDemo YES -LeafScreen search.manual
    shot a05-add-isbn 9 -LeafDemo YES -LeafScreen search.isbn
    # Reading circles: starting one, moving a friend along, the schedule, the empty page, and large text.
    shot e02-circles-new 7 -LeafDemo YES -LeafScreen plan.circles.new
    shot e03-circles-member 7 -LeafDemo YES -LeafScreen plan.circles.member
    shot e04-circles-schedule 7 -LeafDemo YES -LeafScreen plan.circles.schedule
    shot e05-circles-empty 6 -LeafDemo YES -LeafScreen plan.circles -LeafScenario new
    shot lt-e01-circles 7 -LeafDemo YES -LeafScreen plan.circles -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
    shot 101-book-journal 7 -LeafDemo YES -LeafScreen book.journal
    shot 102-book-more 9 -LeafDemo YES -LeafScreen book.more
    shot 103-book-edition 7 -LeafDemo YES -LeafScreen book.edition
    shot 104-settings-plan 6 -LeafDemo YES -LeafScreen settings.plan
    shot 105-settings-tea 6 -LeafDemo YES -LeafScreen settings.tea
    shot 106-settings-cloud 6 -LeafDemo YES -LeafScreen settings.cloud
    # Books and tea: a tea of your own, Leaf's teas, editing a tin, the history, a pairing, a tasting note.
    shot 111-tea-add 6 -LeafDemo YES -LeafScreen tea.add
    shot 112-tea-catalog 6 -LeafDemo YES -LeafScreen tea.catalog
    shot 113-tea-edit 6 -LeafDemo YES -LeafScreen tea.edit
    shot 114-tea-history 6 -LeafDemo YES -LeafScreen tea.history
    shot 115-book-pairing 7 -LeafDemo YES -LeafScreen book.pairing
    shot 116-session-tasting 5 -LeafDemo YES -LeafScreen session.tasting
    # Reading history: the log filtered, the numbers by dates, quote card styles, the library section in Settings.
    shot 122-log-finished 6 -LeafDemo YES -LeafScreen log.finished -LeafScenario year
    shot 124-numbers-range 8 -LeafDemo YES -LeafScreen numbers.range -LeafScenario year
    shot 126-quote-style 6 -LeafDemo YES -LeafScreen quote.style
    shot 127-settings-data 6 -LeafDemo YES -LeafScreen settings.data
    shot 128-insights-more 9 -LeafDemo YES -LeafScreen plan.insights.more -LeafScenario year
    shot 131-shelf-slip 8 -LeafDemo YES -LeafScreen shelf.slip -LeafScenario year
    shot 132-shelf-poster 7 -LeafDemo YES -LeafScreen shelf.poster -LeafScenario year
    shot 134-wrapped-tea 7 -LeafDemo YES -LeafScreen wrapped.1 -LeafScenario year
    shot 135-wrapped-hour 7 -LeafDemo YES -LeafScreen wrapped.2 -LeafScenario year
    shot 136-wrapped-slowburn 7 -LeafDemo YES -LeafScreen wrapped.4 -LeafScenario year
    shot 137-wrapped-quoted 7 -LeafDemo YES -LeafScreen wrapped.5 -LeafScenario year
    shot 138-wrapped-personality 7 -LeafDemo YES -LeafScreen wrapped.6 -LeafScenario year
    shot 140-insights-wrapped-offer 8 -LeafDemo YES -LeafScreen plan.insights.wrapped -LeafScenario year
    shot 142-settings-soundlab 6 -LeafDemo YES -LeafScreen settings.soundlab
    shot 143-today-largetype 7 -LeafDemo YES -LeafScreen today -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityM
    shot 144-today-rest-largetype 7 -LeafDemo YES -LeafScreen today -LeafScenario rest -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityM
    shot 147-tour-today-steep 7 -LeafDemo YES -LeafScreen tour.today.steep
    shot 148-tour-library 6 -LeafDemo YES -LeafScreen tour.library
    shot 149-tour-plan 8 -LeafDemo YES -LeafScreen tour.plan
    shot 150-tour-search 8 -LeafDemo YES -LeafScreen tour.search
    shot 151-tour-settings 6 -LeafDemo YES -LeafScreen tour.settings
    shot 152-liveactivity-steeping 6 -LeafDemo YES -LeafScreen liveactivity.steeping
    shot 153-liveactivity-watch 6 -LeafDemo YES -LeafScreen liveactivity.watch
    # Widgets: the Lock Screen accessories and StandBy, and the Home Screen at a large text size.
    shot wg-1-lock 6 -LeafDemo YES -LeafScreen widgets.lock
    shot wg-4-home-largetype 6 -LeafDemo YES -LeafScreen widgets.home -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityM
    # Polish pass: every main screen at an accessibility text size (lt-*), to catch truncation and clipped layouts.
    lt=(-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL)
    shot lt-01-welcome 4 -LeafScreen onboarding.welcome "${lt[@]}"
    shot lt-05-minutes 4 -LeafScreen onboarding.minutes "${lt[@]}"
    shot lt-11-library 6 -LeafDemo YES -LeafScreen library "${lt[@]}"
    shot lt-13-search 8 -LeafDemo YES -LeafScreen search "${lt[@]}"
    shot lt-14-search-query 8 -LeafDemo YES -LeafScreen search.query "${lt[@]}"
    shot lt-15-book 6 -LeafDemo YES -LeafScreen book:OL27482W "${lt[@]}"
    shot lt-16-session 6 -LeafDemo YES -LeafScreen session "${lt[@]}"
    shot lt-17-settings 5 -LeafDemo YES -LeafScreen settings "${lt[@]}"
    shot lt-19-outcome 6 -LeafDemo YES -LeafScreen session.outcome "${lt[@]}"
    shot lt-24-today-between 8 -LeafDemo YES -LeafScreen today -LeafScenario between -LeafTime 19:30 "${lt[@]}"
    shot lt-25-today-new 7 -LeafDemo YES -LeafScreen today -LeafScenario new -LeafTime 18:00 "${lt[@]}"
    shot lt-34-position 6 -LeafDemo YES -LeafScreen position -LeafScenario newbook "${lt[@]}"
    shot lt-40-deck 8 -LeafDemo YES -LeafScreen deck "${lt[@]}"
    shot lt-B2-librarian-picks 9 -LeafDemo YES -LeafScreen librarian.answer "${lt[@]}"
    shot lt-42-session-ritual 6 -LeafDemo YES -LeafScreen session.ritual "${lt[@]}"
    shot lt-69-plan-reading 8 -LeafDemo YES -LeafScreen plan.reading "${lt[@]}"
    shot lt-82-challenges 8 -LeafDemo YES -LeafScreen plan.challenges -LeafScenario year "${lt[@]}"
    shot lt-110-tea-cabinet 6 -LeafDemo YES -LeafScreen tea.cabinet "${lt[@]}"
    shot lt-121-log 6 -LeafDemo YES -LeafScreen log -LeafScenario year "${lt[@]}"
    shot lt-145-whatsnew 6 -LeafDemo YES -LeafScreen whatsnew "${lt[@]}"
    shot lt-146-tour-today 7 -LeafDemo YES -LeafScreen tour.today "${lt[@]}"
    shot 88-insights-large-type 9 -LeafDemo YES -LeafScreen plan.insights -LeafScenario year -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  fi
  shot "10-today$suffix" 5 -LeafDemo YES -LeafScreen today -LeafTime 20:30
  shot "21-today-late$suffix" 6 -LeafDemo YES -LeafScreen today -LeafTime 23:30
  shot "24-today-between$suffix" 8 -LeafDemo YES -LeafScreen today -LeafScenario between -LeafTime 19:30
  shot "30-today-times$suffix" 7 -LeafDemo YES -LeafScreen today -LeafTime 20:30 -LeafScroll leftoff
  shot "34-position$suffix" 5 -LeafDemo YES -LeafScreen position -LeafScenario newbook
  shot "38-readingtimes$suffix" 5 -LeafDemo YES -LeafScreen readingtimes
  shot "40-deck$suffix" 8 -LeafDemo YES -LeafScreen deck
  shot "B1-librarian$suffix" 7 -LeafDemo YES -LeafScreen librarian
  shot "B2-librarian-picks$suffix" 9 -LeafDemo YES -LeafScreen librarian.answer
  shot "42-session-ritual$suffix" 5 -LeafDemo YES -LeafScreen session.ritual
  shot "45-session-cup$suffix" 5 -LeafDemo YES -LeafScreen session.cup
  shot "11-library$suffix" 5 -LeafDemo YES -LeafScreen library
  shot "15-book$suffix" 5 -LeafDemo YES -LeafScreen book:OL27482W
  shot "16-session$suffix" 5 -LeafDemo YES -LeafScreen session
  shot "62-gallery-blur$suffix" 6 -LeafDemo YES -LeafScreen gallery.blur
  shot "64-gallery-ribbon$suffix" 5 -LeafDemo YES -LeafScreen gallery.ribbon
  shot "65-gallery-scrub$suffix" 4 -LeafDemo YES -LeafScreen gallery.scrub
  shot "70-plan-forecast$suffix" 8 -LeafDemo YES -LeafScreen plan
  shot "76-insights$suffix" 9 -LeafDemo YES -LeafScreen plan.insights -LeafScenario year
  shot "80-year-in-books$suffix" 9 -LeafDemo YES -LeafScreen plan.year -LeafScenario year
  shot "82-challenges$suffix" 8 -LeafDemo YES -LeafScreen plan.challenges -LeafScenario year
  shot "90-search-browse$suffix" 10 -LeafDemo YES -LeafScreen search
  shot "a01-add-quick$suffix" 11 -LeafDemo YES -LeafScreen search.quickadd
  shot "a03-add-scan$suffix" 11 -LeafDemo YES -LeafScreen search.scan
  shot "e01-circles$suffix" 6 -LeafDemo YES -LeafScreen plan.circles
  shot "e06-circles-prompts$suffix" 7 -LeafDemo YES -LeafScreen plan.circles.prompts
  shot "100-library-paused$suffix" 5 -LeafDemo YES -LeafScreen library.paused
  shot "107-library-toread$suffix" 5 -LeafDemo YES -LeafScreen library.toread
  shot "110-tea-cabinet$suffix" 6 -LeafDemo YES -LeafScreen tea.cabinet
  shot "117-today-teaweek$suffix" 7 -LeafDemo YES -LeafScreen today -LeafTime 20:30 -LeafScroll teaweek
  shot "120-book-timeline$suffix" 7 -LeafDemo YES -LeafScreen book.timeline
  shot "121-log$suffix" 6 -LeafDemo YES -LeafScreen log -LeafScenario year
  shot "123-numbers$suffix" 8 -LeafDemo YES -LeafScreen numbers.alltime -LeafScenario year
  shot "125-quote-card$suffix" 6 -LeafDemo YES -LeafScreen quote
  shot "130-shelf$suffix" 7 -LeafDemo YES -LeafScreen shelf -LeafScenario year
  shot "133-wrapped$suffix" 7 -LeafDemo YES -LeafScreen wrapped -LeafScenario year
  shot "139-wrapped-shelf$suffix" 7 -LeafDemo YES -LeafScreen wrapped.7 -LeafScenario year
  shot "141-today-wrapped$suffix" 7 -LeafDemo YES -LeafScreen wrapped.offer -LeafScroll wrapped
  shot "145-whatsnew$suffix" 6 -LeafDemo YES -LeafScreen whatsnew
  shot "146-tour-today$suffix" 7 -LeafDemo YES -LeafScreen tour.today
  shot "wg-2-home$suffix" 6 -LeafDemo YES -LeafScreen widgets.home -LeafTime 20:30
  shot "wg-3-timer$suffix" 6 -LeafDemo YES -LeafScreen widgets.timer -LeafTime 20:30
done
xcrun simctl ui "$IOS_SIM" appearance light

if [ -n "${WATCH_SIM:-}" ] && [ -d "$WATCH_APP" ]; then
  boot "$WATCH_SIM"
  xcrun simctl install "$WATCH_SIM" "$WATCH_APP"
  wshot() {
    local name=$1; shift
    xcrun simctl terminate "$WATCH_SIM" "$WATCH_BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$WATCH_SIM" "$WATCH_BUNDLE" "$@" >/dev/null
    sleep 5
    if xcrun simctl io "$WATCH_SIM" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1; then
      echo "captured $name"
      emit "$name"
    fi
  }
  wshot w1-today -LeafDemo YES -LeafScreen today
  wshot w2-session -LeafDemo YES -LeafScreen session
  wshot w3-pages -LeafDemo YES -LeafScreen pages
  wshot w4-shelf -LeafDemo YES -LeafScreen shelf
  wshot w5-steep -LeafDemo YES -LeafScreen steep
  wshot w6-steep-ready -LeafDemo YES -LeafScreen steepready
  wshot w7-session-cup -LeafDemo YES -LeafScreen session.cup
  wshot w8-always-on -LeafDemo YES -LeafScreen aod
  wshot w9-log -LeafDemo YES -LeafScreen log
  wshot w10-quicklog -LeafDemo YES -LeafScreen quicklog
  wshot w11-where -LeafDemo YES -LeafScreen where
  wshot w12-forecast -LeafDemo YES -LeafScreen forecast
  wshot w13-week -LeafDemo YES -LeafScreen week
  wshot w14-shelf-actions -LeafDemo YES -LeafScreen shelf.actions
  wshot w15-add -LeafDemo YES -LeafScreen add.sent
  wshot w16-complications -LeafDemo YES -LeafScreen complications
  wshot w17-timers -LeafDemo YES -LeafScreen timers
  wshot w18-timers-steep -LeafDemo YES -LeafScreen timers.steep
  # Polish pass: the watch at its largest text size.
  wshot lt-w1-today -LeafDemo YES -LeafScreen today -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXXXL
  wshot lt-w2-session -LeafDemo YES -LeafScreen session -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXXXL
fi
