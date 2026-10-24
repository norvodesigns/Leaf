# Audio sources

Leaf's five ambiences play real recordings: stretches of CC0 field recordings from BigSoundBank, cut, cleaned,
levelled and looped (below). The four cues (the kettle switch, the page turn, the pour, the chime) are still made on
the device, in code (`Shared/Audio/`), and so is every ambience's fallback.

Nothing here needs a credit. Every recording is CC0 (public domain dedication); BigSoundBank describes itself as a
"sound library created by Joseph SARDIN since 2005. Free, royalty-free sounds (CC0)" (https://bigsoundbank.com,
licence page https://bigsoundbank.com/licenses.html). We name Joseph Sardin here anyway, as thanks.

The filmed nook scenes have their own log: [SCENE_SOURCES.md](SCENE_SOURCES.md).

## The recordings

All fetched 2026-10-22 by `scripts/media/build_media.sh`, author Joseph Sardin (BigSoundBank), licence CC0.

| Ambience | File | Source | What was used |
|---|---|---|---|
| Fireplace | `ambience-fireplace.m4a` | [Fireplace #4](https://bigsoundbank.com/fireplace-4-s2856.html) (#2856) | 3 to 73 s: a log fire burning steadily. Rebuilt twice on 2026-10-23 (below): its top rounded off (6 dB down above 5 kHz, nothing over 9 kHz) and its steady hiss lowered 10 dB, so it's the fire's warm rush with its crackles in it. Rumble under 35 Hz removed. |
| Rain | `ambience-rain.m4a` | [Rain and storm in a tent](https://bigsoundbank.com/rain-and-storm-in-a-tent-s0820.html) (#0820) | 80 to 142 s: steady medium rain on canvas, a stretch with no thunder. Under 70 Hz removed, the top above 7 kHz softened 3 dB. |
| Café | `ambience-cafe.m4a` | [Coffee Shop at the Capucins](https://bigsoundbank.com/coffee-shop-at-the-capucins-s2561.html) (#2561) | 160 to 222 s: the interior terrace of a café in Brest, a stretch without a loud clink or laugh. Under 60 Hz removed. |
| Kettle | `ambience-kettle.m4a` | [Electric kettle](https://bigsoundbank.com/electric-kettle-s0660.html) (#0660), with [Sound Atmosphere in a House](https://bigsoundbank.com/sound-atmosphere-in-a-house-s2458.html) (#2458) | 84 to 116 s of the kettle at its rolling simmer, heard from the next room: band-limited to 80 Hz to 2.6 kHz, with a quarter of the house's own room tone (#2458, 10 to 42 s) around it. |
| Library | `ambience-library.m4a` | [Sound Atmosphere in a House](https://bigsoundbank.com/sound-atmosphere-in-a-house-s2458.html) (#2458), page turns [#2210](https://bigsoundbank.com/pages-that-turn-3-s2210.html) to [#2216](https://bigsoundbank.com/pages-that-turn-9-s2216.html), [#0362](https://bigsoundbank.com/great-page-that-turns-1-s0362.html), [#0363](https://bigsoundbank.com/great-page-that-turns-1-s0363.html), [#0164](https://bigsoundbank.com/turned-page-s0164.html), and [Closed book #2](https://bigsoundbank.com/closed-book-2-s1411.html) (#1411) | Composed: 4 to 96 s of a quiet house's room tone, with a page turned across the room every 6.5 to 13 seconds and a book closed once, each softened by distance (a low-pass near 4.5 kHz and a short, dark room tail) and placed left or right. |

The page turns in between are [#2211](https://bigsoundbank.com/pages-that-turn-4-s2211.html),
[#2212](https://bigsoundbank.com/pages-that-turn-5-s2212.html), [#2213](https://bigsoundbank.com/pages-that-turn-6-s2213.html),
[#2214](https://bigsoundbank.com/pages-that-turn-7-s2214.html) and [#2215](https://bigsoundbank.com/pages-that-turn-8-s2215.html).

Size: 5.2 MB for the five, AAC at 128 kb/s, 44.1 kHz stereo; 32 to 92 seconds each.

### How they are made

`scripts/media/make_beds.py` (run by `scripts/media/build_media.sh`, which also fetches the sources):

1. **Pick the stretch.** `scripts/media/analyze.py` prints each recording's level and spectrum second by second; the
   stretch used is a steady one, with no outlier (thunder, a laugh, a dropped cup).
2. **Clean.** A gentle high-pass to take out handling rumble, and on the rain a softer top.
3. **Level.** Loudness-normalised (EBU R128, gated) to -18 LUFS, the library to -26 (8 LU below, a hush, as before),
   with a lookahead peak limiter (1.5 ms attack, 60 ms release) holding peaks at -4.5 dBFS so the crackles and drops
   lose their spikes, not their bite. That keeps them just under the app's own limiter (`AudioLimiter`, knee at about
   -7 dBFS in the mix), so at full volume it barely touches them.

   **The fireplace** took three tries. The first bed was the recording pushed to -18 LUFS with that limiter: a crackle
   has some 30 dB between its pops and the bed under them, so the limiter flattened the pops into the bed and ducked
   it after each one, and what was left sounded like a wash of noise (the owner: "too much overwhelming background
   white noise"). The second swapped in a crisper fire (#2857) with its hiss stripped: crackles 36 dB over a near
   silent bed, which was "too crackly". The third, now, is the first recording made gentle: its top rounded off, its
   hiss lowered (`quiet_hiss`, below), levelled to -20 LUFS with peaks held at -8 dBFS and a 25 ms release, so the
   sharpest pops are rounded but none is flattened. Against the first bed: the same warm body under 1.5 kHz, 4 dB
   less in the 1.5 to 6 kHz "shh" and 12 dB less above 6 kHz, and crackles standing 19 dB over the bed instead of 14
   (the second: 36), about four a second.

   **`quiet_hiss`**: spectral subtraction of a recording's steady bed. Each frequency is turned down by how close it
   sits to its own quiet level (its 20th percentile over the recording), to at most `floor_hi_db` above 1 kHz and
   `floor_lo_db` under 250 Hz, so hiss goes and warmth stays; anything standing well above it (a crackle) passes. The
   gains are smoothed across neighbouring frequencies and released over 60 ms so nothing warbles.
4. **Loop.** Each file runs 2 seconds longer than its loop. When the app loads it, `AmbienceRecording` trims 50 ms from
   each end (room for the encoder's priming and padding) and crossfades the 2-second tail into the start
   (`AudioLoop.seamless`, equal power), so the join never clicks and never sounds like a cut. Each start opens
   somewhere else in the loop, so two sessions don't begin on the same crackle. `LeafTests/AmbienceRecordingTests.swift`
   checks the join and the playback.

### How the app plays them

`AmbiencePlayer` decodes `ambience-<id>.m4a` off the main thread the first time an ambience is chosen, holds it in
memory (11 to 32 MB of float samples, one ambience at a time), and plays it through the same synth node, fades and
limiter as before (`AmbienceSynth` with a recording). Ambience stays opt-in, and nothing is ever spoken.

If a file is missing or can't be decoded, the ambience falls back to the made-in-code sound below. The Sound lab
(Settings, always in debug builds; in TestFlight builds tap the version number in About seven times) plays each
ambience **New** (the recording) or **Old** (the first TestFlight's made-in-code sound), to compare.

## Hearing them

The recordings are the files in `Leaf/Resources/Sounds/`; any player opens them. CI also copies them, as
`*-recorded.m4a`, beside the made-in-code previews it renders on every push (`scripts/render_ambience_previews.sh`,
published to `refs/ci/audio`; `git fetch origin refs/ci/audio`).

`docs/audio-previews/` holds 30-second previews of the made-in-code ambiences as they are now (`*-new.m4a`, the
fallback) and as the first TestFlight had it (`*-old.m4a`), and the four cues, with `MEASURES.md` beside them.

## The made-in-code sounds (the cues, and every ambience's fallback)

Loudness is K-weighted and ungated (`AudioMeasure.loudness`). Rain, fire, kettle and café sit at -17 LUFS at full
volume, within 1.5 LU; the library is a hush, 8 LU below. The tests in `LeafTests/AudioTests.swift`
(`AmbienceCharacterTests`) check every point below, and several show the first TestFlight's recipe failing the same
check.

- **Fire.** A low roar (brown noise between 60 and 350 Hz, flickering), a faint breath of gas, and crackles: clusters of
  noise bursts a tenth of a millisecond to under a millisecond long, each through a broad band (Q about 1) somewhere
  between 0.9 and 7 kHz, arriving in spells, most small and a few sharp, with the odd lower pop and a spray of sparks.
  Nothing rings at a pitch. Held to: transients don't ring (autocorrelation under 0.35; the old fire's pops were pitched
  rings, which is the dripping); crackles come in bursts (gap variation over 1.2, many under 20 ms apart); no hiss
  between them.
- **Library.** A dark room tone under 180 Hz, with nothing in the band a phone speaker turns into hiss, and the sounds
  of a reading room across it, softened by distance and a small room: pages turned (a slide, then the flip with its
  crinkle) every few seconds, someone walking past now and then, a book set down. Held to: the 2 to 8 kHz level between
  events at least 35 dB under the whole (the old library: -21 dB, a constant hiss), and events at least 8 dB over the
  room in the phone's band (the old: about 1 dB, so nothing stood out).
- **Café.** Ten voices built the way speech is (a pitched buzz from the throat, three moving formants, syllables of 110
  to 280 ms, phrases and pauses, men's and women's pitches, each at its own distance and place), heard through the
  room so the words blur into murmur, with a quiet room tone and an occasional cup on a saucer. Held to: a spectral peak
  between 250 Hz and 1 kHz, envelope movement at the syllable rate, little above 4 kHz.
- **Kettle.** In the next room: the seethe of tiny bubbles on the element, then bubbles proper, each a few milliseconds
  long and rising in pitch as real ones do, from the odd one to a rolling simmer over half a minute, after which it
  simmers on. No whistle. Held to: rises by at least 8 dB from the first seconds to the simmer, and no narrow peak.
- **Rain.** Unchanged from the first TestFlight, only matched in loudness (3.6 dB quieter than before).

The cues are softer: the kettle switch is a short noise tick and a low knock instead of bright pings, the page turn
is darker with its crinkle reined in and a soft pat to finish, and the chime has a slower attack and fewer high
overtones. Held to: under a tenth of their energy above 6 kHz and a spectral centre under 2.5 kHz.

## Adding or replacing a recording

1. Use only files whose page states CC0 or public domain, and log each one in the table above: title, author, URL,
   licence, date fetched, and what was done to it. Anything that needs attribution also needs a line in Settings,
   under About.
2. Add its cut to `scripts/media/make_beds.py`, with 2 seconds to spare at the end for the join, and rebuild with
   `scripts/media/build_media.sh`.
3. Listen to the whole loop, join included, in the Sound lab before committing.

From the build environment on 2026-10-22, freesound.org, Pixabay and Pexels refused the connection (403 or a
browser challenge) and Wikimedia Commons rate-limited downloads, so BigSoundBank was the CC0 library in reach.
