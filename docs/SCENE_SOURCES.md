# Scene sources

Five of the reading nook's scenes are filmed: the fireplace, and four landscapes (sunrise, forest, clouds and
starlight). They are real footage from Mixkit, steadied or slowed, cropped to portrait and made into seamless loops. The
rain scene, and the soft ones, are still drawn by the app (`NookShaders.swift`, `NookScene.swift`). The sounds have
their own log: [AUDIO_SOURCES.md](AUDIO_SOURCES.md).

## Licence

Every clip is under the **Mixkit Stock Video Free License** (https://mixkit.co/license/#videoFree), as each clip's
page states ("Download this free stock video clip for commercial or personal use, under the Mixkit Stock Video Free
License"; its structured data gives `"license":"https://mixkit.co/license/#videoFree"`). That licence, as Mixkit
showed it on 2026-10-22:

> Items under the Mixkit Stock Video Free License can be used in your commercial and non-commercial projects, for
> free. You're permitted to download, copy, modify, distribute, publicly perform and broadcast the Items. Your rights
> are non-exclusive, worldwide, sub-licensable and ongoing. Attribution is not required, however, we would appreciate
> it if you credit Mixkit where reasonably possible. There are some important limits to these rights, described in
> our User Terms.

The limits that matter to us, from Mixkit's User Terms (https://mixkit.co/terms/, clause 9): don't sell copies of an
item without altering it and combining it with other elements, and don't make items available to others on a stock
or inventory basis, or use them to build a competing stock library. Leaf uses each clip altered (steadied, cropped,
composited, looped) as one scene inside the app, which is the kind of use the licence is for.

**This is not CC0.** Mixkit keeps the copyright and the licence can be ended if its terms are broken, so the clips
must not be offered for download or reused as stock footage. Some Mixkit clips are under a different, Restricted
License; all of ours are the Free one (checked on each clip's page: its structured data says `"copyrightNotice":"Free"`).
No credit is required; a line under About, "Scene footage: Mixkit", would be a courtesy, not an obligation.

## The clips

Fetched (the 4K originals) by `scripts/media/build_media.sh`: the fireplace and the sunrise on 2026-10-22, the forest,
the clouds and the starlight on 2026-10-23.

| Scene | Files | Source | What was done |
|---|---|---|---|
| Fireplace | `nook-hearth.mp4`, `nook-hearth-poster.jpg` | [A fireplace lit at Christmas time](https://mixkit.co/free-stock-video/a-fireplace-lit-at-christmas-time-2707/), Mixkit #2707, 3840×2160, 11 s, 24 fps | The camera pushes in slowly through the shot. Its zoom and drift were tracked frame by frame (phase correlation on edges, with the flames masked out; `track.py`) and every frame warped back onto the middle one (`warp.py`), so the hearth holds still and only the fire moves. The brick hearth was cropped out (no Christmas decorations in frame), its last second crossfaded into its first for a 10.3 s loop, and it was set low in a portrait frame with a dark wall above, lit a little by the fire, so the timer sits on dark (`compose_fire.py`); since 2026-10-23 it sits 150 px lower, so the flames start under the timer's full-size ring and its caption. |
| Sunrise | `nook-landscape.mp4`, `nook-landscape-poster.jpg` | [Beautiful sunrise landscape](https://mixkit.co/free-stock-video/beautiful-sunrise-landscape-1944/), Mixkit #1944, 3840×2160 | A slow drone glide over a misty plain toward the sun rising behind mountains. Ten seconds (from 6 s) cropped to portrait, played forward and then back with the turns eased, so the glide slows to a stop and drifts back over 32 seconds with no seam and no visible reversal; graded a touch warmer, and the sky carried up above the mountains; since 2026-10-23 the plain's last 220 rows are cut so the sun sits just under the timer's ring (`compose_sun.py`). |
| Forest | `nook-forest.mp4`, `nook-forest-poster.jpg` | [Slow aerial tour through a mist-covered forest](https://mixkit.co/free-stock-video/slow-aerial-tour-through-a-mist-covered-forest-28342/), Mixkit #28342, 3840×2160, 15 s, 23.976 fps | A drone drifting slowly over a pine forest at sunrise, mist rising through the trees. 12.5 seconds (from 1.5 s, after the clip's fade-in) cropped to portrait, played forward and back with the turns eased (40 s a round), its light held steady, dimmed a touch, and the sky carried up so the hills' line sits just under the timer's ring (`compose_land.py`). |
| Clouds | `nook-clouds.mp4`, `nook-clouds-poster.jpg` | [Clouds covering the mountains](https://mixkit.co/free-stock-video/clouds-covering-the-mountains-4695/), Mixkit #4695, 3840×2160, 22 s, 25 fps | A time-lapse above a sea of clouds at dusk, a volcano's shadow on the horizon. The first six seconds (the rest goes to night), cropped to portrait, played forward and back at half speed at most (39 s a round) with the dusk's dimming held off, and the sky carried up so the horizon sits under the ring. |
| Starlight | `nook-stars.mp4`, `nook-stars-poster.jpg` | [Night sky with stars at a calm lake, time lapse](https://mixkit.co/free-stock-video/night-sky-with-stars-at-a-calm-lake-time-lapse-1704/), Mixkit #1704, 3840×2160, 12 s, 23.976 fps | A time-lapse of the Milky Way over a still lake, the far shore's lights in the water. The full height of the shot (a starry sky can't be carried up), cropped to portrait so the shore sits under the ring, played forward and back at about half speed (66 s a round), its light held steady. |

All are HEVC (`hvc1`), 1080×2340 at 23.976 fps, muted, with `faststart`: the fireplace 3.3 MB (a 10 s loop), the
sunrise 0.7 MB (32 s), the forest 1.2 MB (40 s), the clouds 1.6 MB (39 s) and the starlight 6.1 MB (66 s, at CRF 28
so the stars keep their points); 13 MB in all. Each poster is the loop's first frame at 540×1170 (16 to 45 KB); it is
the scene's card in the picker and sits under the video while it loads. Scripts: `scripts/media/`.

### Framed for the timer

Since 2026-10-23 the session keeps its full-size ring on a scene, high on the screen, so a scene's top half sits behind
the ring (a scrim and a soft shade inside the ring keep the digits readable) and its subject belongs in the band
between the ring's caption and the buttons, about 56 to 80 % of the height: the fire's flames, the sun, the forest's
mist, the sea of clouds, the lake's far shore. A new clip should be framed the same way.

## How the app plays them

`NookVideo` finds `nook-<scene>.mp4` in the bundle and `NookSceneBackdrop` plays it full screen (aspect fill), muted,
looping with `AVPlayerLooper`. It never takes the audio session. It plays only while the scene may move: a paused
session, Reduce Motion, Low Power Mode or the app going inactive pause it on its frame. Without the file, the scene
falls back to its shader.

## Rain

The rain scene keeps its drawn version. The rain-on-a-window footage within reach was either stylised (bright green
bokeh) or flat grey daytime at 1080p, and neither beat the shader's night window. A good filmed loop is a drop-in:
name it `nook-rain.mp4` (and `nook-rain-poster.jpg`), add it to `Leaf/Resources/Scenes`, and log it here.

## Adding a clip

1. Use only footage whose page states CC0, public domain, or a licence that allows commercial use in an app without
   attribution (Mixkit's Free licence, Pexels, Pixabay). Log it here: title, URL, licence and its wording, the date
   fetched, and what was done to it.
2. Make it loop without a seam, portrait 1080 wide, HEVC, under about 8 MB, with its top half calm and dark enough
   for the timer and its subject under the ring (above). `compose_land.py` does most of this for a landscape.
3. Add its steps to `scripts/media/build_media.sh`.

From the build environment on 2026-10-22, Pexels and Pixabay showed a browser challenge and Wikimedia Commons
rate-limited downloads, so Mixkit was the library in reach.
