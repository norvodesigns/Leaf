#!/usr/bin/env bash
# Rebuilds the bundled ambience beds (Leaf/Resources/Sounds) and nook scene loops (Leaf/Resources/Scenes) from their
# sources. Where each file comes from and under what licence: docs/AUDIO_SOURCES.md and docs/SCENE_SOURCES.md.
# Not part of CI: run it by hand when a source or a step changes, listen and look, then commit the results.
#
#   scripts/media/build_media.sh [work-dir]
#
# Needs curl, ffmpeg (with libx265) and python3 with numpy. Takes about 40 minutes, most of it the fireplace.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOLS="$ROOT/scripts/media"
WORK="${1:-$(mktemp -d)}"
SRC="$WORK/src"
mkdir -p "$SRC" "$WORK/beds" "$WORK/proc"

fetch() { [ -s "$SRC/$2" ] || curl -fsSL -A 'Mozilla/5.0' -o "$SRC/$2" "$1"; }

# Sounds: BigSoundBank (CC0). Newer recordings are served as FLAC, older ones as broadcast WAV.
for id in 2856 2857 2561 2458 1411 2210 2211 2212 2213 2214 2215 2216; do
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
fetch "https://assets.mixkit.co/videos/28342/28342-2160.mp4" "mixkit-28342-2160.mp4"
fetch "https://assets.mixkit.co/videos/4695/4695-2160.mp4" "mixkit-4695-2160.mp4"
fetch "https://assets.mixkit.co/videos/1704/1704-2160.mp4" "mixkit-1704-2160.mp4"

encode() { # raw rgb24 1080x2340 at 23.976 fps (a file, or - for stdin) -> HEVC
  ffmpeg -v error -y -f rawvideo -pix_fmt rgb24 -s 1080x2340 -r 24000/1001 -i "$1" -c:v libx265 -preset slow \
    -crf "$2" -pix_fmt yuv420p -tag:v hvc1 -x265-params log-level=error -movflags +faststart -an "$3"
}
poster() { # the loop's first frame, half size
  ffmpeg -v error -y -i "$1" -vf "select='eq(n\,0)',scale=540:1170:flags=lanczos" -frames:v 1 -q:v 4 "$2"
}

cd "$WORK/proc"

# Fireplace: track the camera's slow push-in on a small copy (flames masked out), warp every 4K frame back onto the
# middle frame so the shot holds still, crop the hearth, crossfade the last second into the first, and set it low in a
# portrait frame with a dark, firelit wall above: low enough (110 px from the foot) that the flames start under the
# session's ring and its caption.
ffmpeg -v error -y -i "$SRC/mixkit-2707-2160.mp4" -vf "scale=480:270,format=rgb24" -f rawvideo fire-small.rgb
python3 -I "$TOOLS/track.py" fire-small.rgb 480 270 270 fire-track.json >/dev/null
python3 -I "$TOOLS/warp.py" "$SRC/mixkit-2707-2160.mp4" fire-track.json 3840 2160 1080 1200 668 0 1944 2160 fire-region.rgb 1
frames=$(( $(stat -c %s fire-region.rgb) / (1080 * 1200 * 3) ))
python3 -I "$TOOLS/compose_fire.py" fire-region.rgb 1080 1200 "$frames" 24 1080 2340 fire-loop.rgb 110
encode fire-loop.rgb 27 nook-hearth.mp4

# Sunrise: ten seconds of a slow drone glide, cropped to portrait, played forward and back with the turns eased (32 s
# a round), warmed a touch, and the sky carried up above the mountains. The plain's last 220 rows are cut so the sun
# sits under the session's ring.
ffmpeg -v error -y -ss 6 -t 10.05 -i "$SRC/mixkit-1944-2160.mp4" \
  -vf "crop=1600:2160:1580:0,scale=1080:1458:flags=lanczos" -f rawvideo -pix_fmt rgb24 sun-region.rgb
frames=$(( $(stat -c %s sun-region.rgb) / (1080 * 1458 * 3) ))
python3 -I "$TOOLS/compose_sun.py" sun-region.rgb 1080 1458 "$frames" 32 1080 2340 sun-loop.rgb 220
encode sun-loop.rgb 26 nook-landscape.mp4

# The other landscapes (compose_land.py): a stretch of the clip cropped to portrait, played forward and back with the
# turns eased, its light held steady, and where the crop is shorter than the screen its sky carried up above it.
#   land name source from length crop regionW regionH secondsARound crf [compose_land options]
land() {
  local name=$1 src=$2 from=$3 len=$4 crop=$5 rw=$6 rh=$7 round=$8 crf=$9; shift 9
  ffmpeg -v error -y -ss "$from" -t "$len" -i "$SRC/$src" -vf "crop=$crop,scale=$rw:$rh:flags=lanczos" \
    -f rawvideo -pix_fmt rgb24 "$name-region.rgb"
  local n=$(( $(stat -c %s "$name-region.rgb") / (rw * rh * 3) ))
  python3 -I "$TOOLS/compose_land.py" "$name-region.rgb" "$rw" "$rh" "$n" "$round" 1080 2340 - "$@" \
    | encode - "$crf" "nook-$name.mp4"
}
# Misty forest: a drone drifting over a pine forest with mist rising through it, the hills' line just under the ring.
land forest mixkit-28342-2160.mp4 1.5 12.5 1600:2160:1120:0 1080 1458 40 27 \
  --steady 1 --grade 0.9,0,1.08 --zenith 0.45,0.48,0.56
# Above the clouds: a time-lapse over a sea of clouds at dusk, a volcano's shadow on the horizon; six seconds of it at
# half speed at most, the dusk's dimming held off.
land clouds mixkit-4695-2160.mp4 0.5 6 1600:2160:400:0 1080 1458 39 26 --steady 1 --zenith 0.7,0.75,0.85
# Starlight: a time-lapse of the Milky Way over a still lake, the full height of the shot (the stars can't be carried
# up), at about half speed.
land stars mixkit-1704-2160.mp4 0.2 11.6 997:2160:1700:0 1080 2340 66 28 --steady 1

for scene in hearth landscape forest clouds stars; do
  cp "nook-$scene.mp4" "$ROOT/Leaf/Resources/Scenes/"
  poster "nook-$scene.mp4" "$ROOT/Leaf/Resources/Scenes/nook-$scene-poster.jpg"
done
du -sh "$ROOT/Leaf/Resources/Sounds" "$ROOT/Leaf/Resources/Scenes"
