#!/usr/bin/env bash
# Renders previews of every ambience (as it is now, and as the first TestFlight had it, for comparison) and every cue
# with the app's own synthesis in Shared/, as .m4a files and a MEASURES.md table, into docs/audio-previews (or the
# directory given). CI runs it on every push and publishes the result to refs/ci/audio.
#
#   scripts/render_ambience_previews.sh [out-dir]
#
# Needs a Swift toolchain (Xcode on macOS, or swift.org on Linux) and afconvert (macOS) or ffmpeg.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/audio-previews}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT" "$WORK/wav"

# shellcheck disable=SC2046
swiftc -O -swift-version 5 -module-name AmbiencePreviews \
  $(find "$ROOT/Shared" -name '*.swift' | sort) "$ROOT/scripts/AmbiencePreviews/main.swift" -o "$WORK/render"
"$WORK/render" "$WORK/wav"

for wav in "$WORK"/wav/*.wav; do
  name="$(basename "$wav" .wav)"
  if command -v afconvert >/dev/null 2>&1; then
    afconvert -f m4af -d aac -b 128000 "$wav" "$OUT/$name.m4a"
  else
    ffmpeg -loglevel error -y -i "$wav" -c:a aac -b:a 128k "$OUT/$name.m4a"
  fi
done
cp "$WORK/wav/MEASURES.md" "$OUT/MEASURES.md"
echo "previews: $(du -sk "$OUT" | cut -f1) KB in $OUT"
