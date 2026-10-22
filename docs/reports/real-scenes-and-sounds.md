# Real scene footage and sounds

The owner's feedback on the redesign (2026-10-22): the fireplace "looks like a gimmicky graphic"; make it
photorealistic. The sounds "are better, but still not amazing. maybe look online for free sound libraries". Later:
"also add a photorealistic sunrise scene". The timer moving to the top while a scene is on was done separately
(9926223).

## What shipped

- **A filmed fireplace** (`nook-hearth.mp4`, 3.3 MB). Real footage of a log fire in a brick hearth (Mixkit #2707,
  4K). The camera's slow push-in was tracked and undone, so the hearth holds still and only the fire moves. It loops
  every 10.3 s with a one-second crossfade, and sits low in a portrait frame with a dark, firelit wall above, where
  the timer is.
- **A filmed sunrise** (`nook-landscape.mp4`, 0.8 MB), the scene once called Dawn, now **Sunrise**. A slow drone
  glide toward the sun rising behind mountains, mist over the plain (Mixkit #1944, 4K). It plays forward and back
  with eased turns, 32 s a round, with the sky carried up so the sun sits mid-screen. The stored value stays
  `landscape`, so a reader's choice carries over.
- **Posters.** Each clip's first frame (`nook-*-poster.jpg`) is its card in the scene picker and sits under the video
  while it loads, so there is no black flash.
- **Recorded ambiences.** Rain, fireplace, kettle, café and library now play real CC0 field recordings
  (BigSoundBank, Joseph Sardin): 32 to 92 s each, cleaned, loudness-matched (-18 LUFS, the library 8 LU lower),
  peak-limited, and crossfaded into seamless loops when loaded. 5.2 MB for the five. The made-in-code sounds stay as
  the fallback and as the Sound lab's Old. The cues are still made in code. Ambience is still opt-in, and nothing is
  ever spoken.
- **Code.** `Shared/Audio/AmbienceRecording.swift` (the loop and its voice, Foundation-only), `AmbienceSynth` playing a
  recording at its own rate and level, `AmbiencePlayer` decoding the bundled file off the main thread, and
  `NookVideo` posters. Tests: `LeafTests/AmbienceRecordingTests.swift` (the join is seamless, playback is
  sample-exact and wraps, each start opens elsewhere, fades still apply).
- **Provenance.** docs/AUDIO_SOURCES.md and docs/SCENE_SOURCES.md log every file's source, author, licence and
  processing. `scripts/media/build_media.sh` fetches the sources and rebuilds every file.

Added to the app: 9.3 MB (5.2 MB of sound, 4.0 MB of footage, 68 KB of posters).

## Licences

The recordings are CC0. The footage is **not CC0**: it is under the Mixkit Stock Video Free License, which allows
commercial use in an app, with modification and no attribution required, but Mixkit keeps the copyright and its
terms forbid redistributing the clips as stock. Details and the licence wording are in SCENE_SOURCES.md. Crediting
Mixkit under About would be a courtesy.

## Not done

- **Rain stays drawn.** The rain-on-glass footage within reach was stylised green bokeh or flat grey daytime 1080p,
  and neither beat the shader's night window. A filmed `nook-rain.mp4` would drop straight in.
- freesound.org, Pixabay and Pexels refused the build environment, and Wikimedia Commons rate-limited it, so the sources
  are BigSoundBank (sound) and Mixkit (footage).

## Screenshots

`45b-nook-hearth`, `45c-nook-landscape`, `45g-nook-sheet` (the picker's cards).

## Eyeball on a device

- Turn on Fireplace and watch for a minute: the loop point (every 10 s) shouldn't show a jump, and the fire should be
  the only thing moving.
- Sunrise: the glide should ease to a stop and drift back, with no visible reverse.
- Play each ambience for a full loop (the library is 90 s) on the speaker and on headphones. Listen for the join and
  for anything that repeats noticeably.
- Low Power Mode and Reduce Motion should hold the video still on its frame.
- Memory: the ambience holds 11 to 32 MB of decoded audio while it plays. Check that's fine on the oldest supported
  phone.

Next package you recommend: a filmed rain-on-a-window loop at night (or a darker regrade of the best daytime one), so
all three realistic scenes are footage, plus a Mixkit credit line under About.
