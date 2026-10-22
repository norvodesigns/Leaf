#!/usr/bin/env bash
# Rebuilds the bundled ambience beds (Leaf/Resources/Sounds) and nook scene loops (Leaf/Resources/Scenes) from their
# sources. Where each file comes from and under what licence: docs/AUDIO_SOURCES.md and docs/SCENE_SOURCES.md.
# Not part of CI: run it by hand when a source or a step changes, listen and look, then commit the results.
#
#   scripts/media/build_media.sh [work-dir]
#
# Needs curl, ffmpeg (with libx265) and python3 with numpy. Takes about 20 minutes, most of it the fireplace.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOLS="$ROOT/scripts/media"
WORK="${1:-$(mktemp -d)}"
SRC="$WORK/src"
mkdir -p "$SRC" "$WORK/beds" "$WORK/proc"

fetch() { [ -s "$SRC/$2" ] || curl -fsSL -A 'Mozilla/5.0' -o "$SRC/$2" "$1"; }

# Sounds: BigSoundBank (CC0). Newer recordings are served as FLAC, older ones as broadcast WAV.
for id in 2856 2561 2458 1411 2210 2211 2212 2213 2214 2215 2216; do
  fetch "https://bigsoundbank.com/UPLOAD/flac/$id.flac" "bsb-$id.flac"
done
for id in 0820 0660 0362 0363 0164; do
  fetch "https://bigsoundbank.com/UPLOAD/bwf-en/$id.wav" "bsb-$id.wav"
done
python3 -I "$TOOLS/make_beds.py" "$SRC" "$WORK/beds"
cp "$WORK"/beds/ambience-*.m4a "$ROOT/Leaf/Resources/Sounds/"

# Footage: Mixkit (Stock Video Free License), the 4K originals.
fetch "https://assets.mixkit.co/videos/2707/2707-2160.mp4" "mixkit-2707-2160.mp4"
fetch "https://assets.mixkit.co/videos/1944/1944-2160.mp4" "mixkit-1944-2160.mp4"

encode() { # raw rgb24 1080x2340 at 23.976 fps -> HEVC
  ffmpeg -v error -y -f rawvideo -pix_fmt rgb24 -s 1080x2340 -r 24000/1001 -i "$1" -c:v libx265 -preset slow \
    -crf "$2" -pix_fmt yuv420p -tag:v hvc1 -x265-params log-level=error -movflags +faststart -an "$3"
}
poster() { # the loop's first frame, half size
  ffmpeg -v error -y -i "$1" -vf "select='eq(n\,0)',scale=540:1170:flags=lanczos" -frames:v 1 -q:v 4 "$2"
}

cd "$WORK/proc"

# Fireplace: track the camera's slow push-in on a small copy (flames masked out), warp every 4K frame back onto the
# middle frame so the shot holds still, crop the hearth, crossfade the last second into the first, and set it low in a
# portrait frame with a dark, firelit wall above.
ffmpeg -v error -y -i "$SRC/mixkit-2707-2160.mp4" -vf "scale=480:270,format=rgb24" -f rawvideo fire-small.rgb
python3 -I "$TOOLS/track.py" fire-small.rgb 480 270 270 fire-track.json >/dev/null
python3 -I "$TOOLS/warp.py" "$SRC/mixkit-2707-2160.mp4" fire-track.json 3840 2160 1080 1200 668 0 1944 2160 fire-region.rgb 1
frames=$(( $(stat -c %s fire-region.rgb) / (1080 * 1200 * 3) ))
python3 -I "$TOOLS/compose_fire.py" fire-region.rgb 1080 1200 "$frames" 24 1080 2340 fire-loop.rgb 260
encode fire-loop.rgb 27 nook-hearth.mp4

# Sunrise: ten seconds of a slow drone glide, cropped to portrait, played forward and back with the turns eased (32 s
# a round), warmed a touch, and the sky carried up above the mountains.
ffmpeg -v error -y -ss 6 -t 10.05 -i "$SRC/mixkit-1944-2160.mp4" \
  -vf "crop=1600:2160:1580:0,scale=1080:1458:flags=lanczos" -f rawvideo -pix_fmt rgb24 sun-region.rgb
frames=$(( $(stat -c %s sun-region.rgb) / (1080 * 1458 * 3) ))
python3 -I "$TOOLS/compose_sun.py" sun-region.rgb 1080 1458 "$frames" 32 1080 2340 sun-loop.rgb
encode sun-loop.rgb 26 nook-landscape.mp4

for scene in hearth landscape; do
  cp "nook-$scene.mp4" "$ROOT/Leaf/Resources/Scenes/"
  poster "nook-$scene.mp4" "$ROOT/Leaf/Resources/Scenes/nook-$scene-poster.jpg"
done
du -sh "$ROOT/Leaf/Resources/Sounds" "$ROOT/Leaf/Resources/Scenes"
