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
    shot 88-insights-large-type 9 -LeafDemo YES -LeafScreen plan.insights -LeafScenario year -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
  fi
  shot "10-today$suffix" 5 -LeafDemo YES -LeafScreen today -LeafTime 20:30
  shot "21-today-late$suffix" 6 -LeafDemo YES -LeafScreen today -LeafTime 23:30
  shot "24-today-between$suffix" 8 -LeafDemo YES -LeafScreen today -LeafScenario between -LeafTime 19:30
  shot "30-today-times$suffix" 7 -LeafDemo YES -LeafScreen today -LeafTime 20:30 -LeafScroll leftoff
  shot "34-position$suffix" 5 -LeafDemo YES -LeafScreen position -LeafScenario newbook
  shot "38-readingtimes$suffix" 5 -LeafDemo YES -LeafScreen readingtimes
  shot "40-deck$suffix" 8 -LeafDemo YES -LeafScreen deck
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
  wshot w4-books -LeafDemo YES -LeafScreen books
fi
