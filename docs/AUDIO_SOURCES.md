# Audio sources

Every sound in Leaf is made on the device, in code (`Shared/Audio/`). Leaf ships no recordings, so there is no
licence to track and nothing to credit.

## Why the rebuild is procedural, not recorded

The plan after the first TestFlight was to use CC0 / public-domain field recordings where they beat synthesis
(Freesound with the CC0 filter, Wikimedia Commons, archive.org). The build environment could not reach any of those
hosts (`freesound.org`, `commons.wikimedia.org`, `upload.wikimedia.org` and `archive.org` were all refused by its
network policy), so no recording was fetched, checked or bundled. The four weak sounds were rebuilt as physical
models instead, and measured against what the real sounds are like (below).

If recordings are wanted later, the path is ready:

1. Use only files whose page states CC0 or public domain. Record each one here: title, author, URL, licence, date
   fetched, and what was done to it. Anything that needs attribution also needs a line in Settings, under About.
2. Cut 20 to 40 seconds, loudness-normalise to the recipe's `targetLoudness`, and make the join seamless with
   `AudioLoop.seamless(_:crossfade:)` (a 50 to 100 ms equal-power crossfade; `AudioLoop.seamJump` checks it).
3. Encode as AAC under about 400 KB, add to `Leaf/Resources/Sounds`, and play it through `AmbiencePlayer` beside the
   procedural layer (an `AVAudioPlayerNode` scheduling the buffer with `.loops`), keeping the synth's occasional
   events on top so the loop never sounds like a loop.

| Sound | File | Source URL | Licence | Notes |
|---|---|---|---|---|
| (none yet) | | | | |

## Hearing them

`docs/audio-previews/` holds 30-second previews of every ambience as it is now (`*-new.m4a`) and as the first TestFlight
had it (`*-old.m4a`), the kettle at 45 seconds so its rise can be heard, rain (unchanged), and the four cues. They are
rendered by `scripts/render_ambience_previews.sh` with the app's own code, so they are exactly what the app plays. CI
renders them on every push and publishes them to `refs/ci/audio` (`git fetch origin refs/ci/audio`), with
`MEASURES.md` beside them.

On the phone, Settings has a Sound lab (always in debug builds; in TestFlight builds, tap the version number in About
seven times). It plays each ambience old or new at one volume, and each cue.

## How each sound is made, and what it is held to

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
