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

shot() { # name wait args...
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$IOS_SIM" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$IOS_SIM" "$BUNDLE" "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$IOS_SIM" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1 && echo "captured $name"
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
  fi
  shot "10-today$suffix" 5 -LeafDemo YES -LeafScreen today -LeafTime 20:30
  shot "21-today-late$suffix" 6 -LeafDemo YES -LeafScreen today -LeafTime 23:30
  shot "24-today-between$suffix" 8 -LeafDemo YES -LeafScreen today -LeafScenario between -LeafTime 19:30
  shot "30-today-times$suffix" 7 -LeafDemo YES -LeafScreen today -LeafTime 20:30 -LeafScroll leftoff
  shot "34-position$suffix" 5 -LeafDemo YES -LeafScreen position -LeafScenario newbook
  shot "38-readingtimes$suffix" 5 -LeafDemo YES -LeafScreen readingtimes
  shot "40-deck$suffix" 8 -LeafDemo YES -LeafScreen deck
  shot "11-library$suffix" 5 -LeafDemo YES -LeafScreen library
  shot "12-plan$suffix" 5 -LeafDemo YES -LeafScreen plan
  shot "15-book$suffix" 5 -LeafDemo YES -LeafScreen book:OL27482W
  shot "16-session$suffix" 5 -LeafDemo YES -LeafScreen session
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
    xcrun simctl io "$WATCH_SIM" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1 && echo "captured $name"
  }
  wshot w1-today -LeafDemo YES -LeafScreen today
  wshot w2-session -LeafDemo YES -LeafScreen session
  wshot w3-pages -LeafDemo YES -LeafScreen pages
  wshot w4-books -LeafDemo YES -LeafScreen books
fi

# Smaller JPEG copies, also printed as base64 so they can be read from the job log.
mkdir -p "$OUT/jpg"
for f in "$OUT"/*.png; do
  [ -e "$f" ] || continue
  n=$(basename "$f" .png)
  sips -s format jpeg -s formatOptions 72 -Z 1100 "$f" --out "$OUT/jpg/$n.jpg" >/dev/null 2>&1
  echo "=====BEGIN $n====="
  base64 -b 120 -i "$OUT/jpg/$n.jpg"
  echo "=====END $n====="
done
