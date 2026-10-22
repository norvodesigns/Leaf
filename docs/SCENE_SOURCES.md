# Scene sources

Two of the reading nook's scenes are filmed: the fireplace and the sunrise. They are real footage from Mixkit, steadied,
cropped to portrait and made into seamless loops. The rain scene, and the soft ones, are still drawn by the app
(`NookShaders.swift`, `NookScene.swift`). The sounds have their own log: [AUDIO_SOURCES.md](AUDIO_SOURCES.md).

## Licence

Both clips are under the **Mixkit Stock Video Free License** (https://mixkit.co/license/#videoFree), as each clip's
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
License; both of ours are the Free one (checked on each clip's page). No credit is required; a line under About,
"Fireplace and sunrise footage: Mixkit", would be a courtesy, not an obligation.

## The clips

Fetched 2026-10-22 (the 4K originals) by `scripts/media/build_media.sh`.

| Scene | Files | Source | What was done |
|---|---|---|---|
| Fireplace | `nook-hearth.mp4`, `nook-hearth-poster.jpg` | [A fireplace lit at Christmas time](https://mixkit.co/free-stock-video/a-fireplace-lit-at-christmas-time-2707/), Mixkit #2707, 3840×2160, 11 s, 24 fps | The camera pushes in slowly through the shot. Its zoom and drift were tracked frame by frame (phase correlation on edges, with the flames masked out; `track.py`) and every frame warped back onto the middle one (`warp.py`), so the hearth holds still and only the fire moves. The brick hearth was cropped out (no Christmas decorations in frame), its last second crossfaded into its first for a 10.3 s loop, and it was set low in a portrait frame with a dark wall above, lit a little by the fire, so the timer sits on dark (`compose_fire.py`). |
| Sunrise | `nook-landscape.mp4`, `nook-landscape-poster.jpg` | [Beautiful sunrise landscape](https://mixkit.co/free-stock-video/beautiful-sunrise-landscape-1944/), Mixkit #1944, 3840×2160 | A slow drone glide over a misty plain toward the sun rising behind mountains. Ten seconds (from 6 s) cropped to portrait, played forward and then back with the turns eased, so the glide slows to a stop and drifts back over 32 seconds with no seam and no visible reversal; graded a touch warmer, and the sky carried up above the mountains so the sun sits mid-screen (`compose_sun.py`). |

Both are HEVC (`hvc1`), 1080×2340 at 23.976 fps, muted, with `faststart`: the fireplace 3.3 MB, the sunrise 0.8 MB.
Each poster is the loop's first frame at 540×1170 (45 KB and 17 KB); it is the scene's card in the picker and sits
under the video while it loads. Scripts: `scripts/media/`.

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
2. Make it loop without a seam, portrait 1080 wide, HEVC, under about 8 MB, with the timer's top third dark enough to
   read on.
3. Add its steps to `scripts/media/build_media.sh`.

From the build environment on 2026-10-22, Pexels and Pixabay showed a browser challenge and Wikimedia Commons
rate-limited downloads, so Mixkit was the library in reach.
