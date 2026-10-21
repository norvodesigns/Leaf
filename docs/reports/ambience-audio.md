# Ambience audio rebuild: report

```
=== REPORT FOR LEAD ===
Package: Ambience audio rebuild (fireplace, library, kettle, cafe; cues)
Status: done in code and measured; not yet heard by a person (see "Could not verify")
Commits pushed to main:
  cf66393 Ambience rebuilt from physical models, matched in loudness, with previews and a Sound lab
  9f9fab6 Ambience: the cafe and the crackles sound the same at any sample rate (Low Power Mode is 22 kHz)
  b3c3e31 Ambience previews: the rendered 30-second previews and their measures, old and new
CI: the first full run carrying it (on 1e460e6) was red on one test: the cafe came out 11 LU too loud at
  22.05 kHz (Low Power Mode), fixed in 9f9fab6. Run 39655925407 (a63477d, which carries both): build and every unit
  test green, including all AudioTests at 22.05, 44.1 and 48 kHz; previews rendered and published to refs/ci/audio.
Approach per sound, and my honest confidence:
  Rain       unchanged recipe, only matched in loudness (-16.9 LUFS, 3.6 dB quieter than before). High: testers
             liked it.
  Fireplace  physical model, rebuilt: a flickering low roar, a faint breath of gas, and crackles as clusters of
             very short noise bursts through broad bands (no resonant filters, so nothing rings at a pitch), in
             spells, with the odd pop and spark spray. The "water dripping in a bucket" was the old pops ringing at a
             pitch: ringing 0.51 -> 0.19. Medium-high.
  Library    physical model, rebuilt: a dark room tone with nothing in the band a phone speaker turns into hiss,
             and reading-room events across it (pages turned, someone passing, a book set down) through a small
             room. The "random static" was a constant hiss: hiss between events -21 -> -49 dB; events over the room
             1 -> 23 dB. Medium: the static is gone for certain; whether synthesized page turns read as pages on a
             phone speaker I can't hear.
  Kettle     physical model, rebuilt: the seethe on the element, then chirped bubbles (Minnaert resonances rising as
             real bubbles do), from the odd one to a rolling simmer over about 30 s, then it simmers on. No whistle.
             Medium.
  Cafe       procedural speech babble: ten voices (glottal pulses, three moving formants, syllables and phrases,
             men's and women's pitches, each placed and distanced) through a room, a quiet room tone, a cup on a
             saucer now and then. Low-medium: the measures match murmur (a peak between 250 Hz and 1 kHz, syllable-rate
             movement), but synthesized babble is the hardest of these to make convincing, and a real recording
             would beat it.
  Cues       softened: the kettle switch is a short tick and a low knock (no bright pings), the page turn darker with
             a soft pat, the chime slower to start with fewer high overtones. Under a tenth of their energy above
             6 kHz. Medium-high.
Why procedural: the brief's first choice was CC0 / public-domain recordings, but this environment's network policy
  refused freesound.org, commons.wikimedia.org, upload.wikimedia.org and archive.org, so nothing was fetched. Leaf
  ships no recordings, so there is nothing to credit. docs/AUDIO_SOURCES.md says so and sets out the path for adding
  recordings later (licence table, loop crossfade helper, player wiring).
App size increase: no assets. The rebuild adds about 2,000 lines of Swift to the app targets (Shared/Audio and the
  Sound lab), including the original recipes kept for the A/B (about 400 lines) and the loudness meter (about 360).
  I can't measure a binary here; for DSP code of this size I'd expect the executable to grow by roughly 100 to 300 KB.
  CI now prints the app and executable sizes in the archive step from the next run on, so future packages can report
  a real number. The previews in docs/audio-previews (4.8 MB) are in the repository only, not in the app.
Screens / states built (staging name -> screenshot file):
  Sound lab (DEBUG always; TestFlight: tap the version in About seven times)
                                          -LeafScreen settings.soundlab -> 142-settings-soundlab(-dark)
New public types or files (one line each):
  Shared/Audio/AudioDSP.swift          AudioFilter, AudioBurstPool, AudioBubblePool, AudioRoom (small reverb), AudioScratch
  Shared/Audio/AudioMeasure.swift      AudioMeasure: K-weighted loudness, hiss between events, event contrast, ringing,
                                       transient rate, narrow spectral peaks
  Shared/Audio/AudioLoop.swift         AudioLoop.seamless and seamJump, for recordings later
  Shared/Audio/AmbienceVoicesOriginal.swift  the first TestFlight's recipes, for the A/B
  AmbienceRecipe.Version (.current, .original), targetLoudness, rawToTarget(version)
  Leaf/Features/Settings/SoundLabView.swift  the Sound lab
  scripts/AmbiencePreviews/main.swift, scripts/render_ambience_previews.sh  previews from the app's own code
  Tests: LeafTests/AudioTests.swift (AmbienceCharacterTests per sound, loudness within 1.5 LU, block-size
         invariance, other sample rates, cue softness, loop seams)
Engine APIs I used, and any I needed but did not find or that behaved oddly:
  AmbienceSynth, AmbiencePlayer, CozySounds, CozyCueSynth. A struct voice can't free its buffers (no deinit), hence
  AudioScratch. Glottal-pulse loudness scales with the sample rate squared, which CI's 22 kHz test caught.
Changes I made outside Leaf/, LeafWatch/, LeafWidgets/, LiveActivityShared/:
  Shared/Audio/*, LeafTests/AudioTests.swift, scripts/AmbiencePreviews, scripts/render_ambience_previews.sh,
  .github/workflows/ios.yml (render and publish previews to refs/ci/audio; app sizes in the archive step),
  docs/AUDIO_SOURCES.md, docs/audio-previews/.
Could not verify (device-only things):
  Listening. I can't hear; every judgement above is from measures, spectra and what the real sounds are physically
  like. Please listen to docs/audio-previews (old and new side by side) on a phone speaker and on headphones, and in
  the Sound lab. Also: CPU and battery while playing (each voice is a few hundred multiply-adds a sample), and the
  sound at Low Power Mode's 22 kHz on a real device (tested in code only).
Design decisions the owner should know about or veto:
  - All five ambiences sit at the same loudness (-17 LUFS at full volume) except the library, 8 LU quieter, since a
    library is a hush. Default volume 0.5.
  - The kettle never whistles (a whistle is an alarm, not an ambience).
  - The old recipes stay in the app for the A/B in the Sound lab; delete AmbienceVoicesOriginal.swift once you've
    compared them.
  - Nothing plays or speaks by itself: ambience and cues stay opt-in, as before.
Known issues / follow-ups, most important first:
  - The cafe is the weakest; if the network policy can allow freesound.org (CC0 filter), a recorded murmur bed under
    the synth's clinks would be the next step (the path is in AUDIO_SOURCES.md).
  - The cafe's cup clinks are pitched (5 to 8 kHz, a few per 30 s); they show as the "narrow peak" in MEASURES.md and
    are intended. If they sound like bells on device, shorten their ring.
  - Previews are re-rendered on every push to refs/ci/audio; the committed ones are from a63477d.
Next package you recommend: the Today fixes and What's new (done), then Widgets.
=== END REPORT ===
```
