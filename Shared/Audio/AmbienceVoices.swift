import Foundation

// The five ambience recipes. Each voice is a value type that renders raw, un-normalised stereo into two buffers;
// `AmbienceSynth` adds the level, fades and the limiter. A voice never allocates while rendering (its ringing
// layers live in an `AudioResonatorPool` made at the start), and everything random comes from a seed.
//
// Conventions: layer levels below are relative to the unit-RMS noise sources, and the synth later scales the whole
// mix to the recipe's target loudness, so only the balance between layers matters here.

/// Something that can fill two buffers with raw ambience.
protocol AmbienceVoice {
    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int)
}

// MARK: - Rain

/// Rain on a window: a soft wash of band-limited pink noise that swells and eases like gusts, a fine grainy patter
/// on top, and the odd bigger drop.
struct AmbienceRainVoice: AmbienceVoice {
    private struct Lane {
        var wash: AudioNoiseSource
        var washHighpass: AudioOnePole
        var washLowpass: AudioOnePole
        var hiss: AudioNoiseSource
        var hissHighpass: AudioOnePole
        var hissLowpass: AudioOnePole
        var grains: AudioEventClock
        var grain: Float = 0
        let grainDecay: Float

        init(seed: UInt64, stream: UInt64, sampleRate: Double) {
            wash = AudioNoiseSource(color: .pink, seed: seed, stream: stream, sampleRate: sampleRate)
            washHighpass = AudioOnePole(cutoff: 220, sampleRate: sampleRate)
            washLowpass = AudioOnePole(cutoff: 5_200, sampleRate: sampleRate)
            hiss = AudioNoiseSource(color: .white, seed: seed, stream: stream + 10, sampleRate: sampleRate)
            hissHighpass = AudioOnePole(cutoff: 2_600, sampleRate: sampleRate)
            hissLowpass = AudioOnePole(cutoff: 9_000, sampleRate: sampleRate)
            grains = AudioEventClock(seed: seed, stream: stream + 20, rate: 120, sampleRate: sampleRate)
            grainDecay = Float(exp(-1 / (0.0035 * sampleRate)))
        }

        mutating func next(gust: Float) -> Float {
            let body = washLowpass.lowpass(washHighpass.highpass(wash.next()))
            // Each grain is a tiny burst of the hiss, so the patter is granular instead of a steady sizzle.
            if grains.tick(rate: 120 * gust) { grain = min(2.5, grain + 0.35 + 0.65 * grains.unit()) }
            grain *= grainDecay
            let patter = hissLowpass.lowpass(hissHighpass.highpass(hiss.next())) * grain
            return body * gust + patter * 1.1
        }
    }

    private var laneLeft: Lane
    private var laneRight: Lane
    private var gusts: AudioWander
    private var drops: AudioEventClock
    private let pool: AudioResonatorPool

    init(sampleRate: Double, seed: UInt64) {
        laneLeft = Lane(seed: seed, stream: 1, sampleRate: sampleRate)
        laneRight = Lane(seed: seed, stream: 2, sampleRate: sampleRate)
        gusts = AudioWander(seed: seed, stream: 3, period: 4...9, sampleRate: sampleRate)
        drops = AudioEventClock(seed: seed, stream: 4, rate: 8, sampleRate: sampleRate)
        pool = AudioResonatorPool(capacity: 12, sampleRate: sampleRate)
    }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            let gust = 1 + 0.18 * gusts.next()
            left[frame] = laneLeft.next(gust: gust)
            right[frame] = laneRight.next(gust: gust)
            if drops.tick(rate: 8 * gust) {
                // Most drops are small and low; a few are bright. Each one lands somewhere on the stage.
                let size = drops.unit()
                let loud = drops.unit()
                pool.strike(
                    frequency: 1_800 + 3_400 * size * size,
                    decay: drops.range(0.004, 0.012),
                    amplitude: 0.10 + 0.55 * loud * loud,
                    pan: drops.signed() * 0.85,
                    delay: frame
                )
            }
        }
        pool.render(addingTo: left, right, frames: frames)
    }
}

// MARK: - Fireplace

/// A hearth: a deep brown-noise rumble with a warmer mid roar, both flickering slowly, and irregular crackles, some
/// in little bursts, with the occasional soft pop.
struct AmbienceFireVoice: AmbienceVoice {
    private struct Lane {
        var rumble: AudioNoiseSource
        var rumbleLowpass: AudioOnePole
        var roar: AudioNoiseSource
        var roarHighpass: AudioOnePole
        var roarLowpass: AudioOnePole

        init(seed: UInt64, stream: UInt64, sampleRate: Double) {
            rumble = AudioNoiseSource(color: .brown, seed: seed, stream: stream, sampleRate: sampleRate)
            rumbleLowpass = AudioOnePole(cutoff: 700, sampleRate: sampleRate)
            roar = AudioNoiseSource(color: .pink, seed: seed, stream: stream + 10, sampleRate: sampleRate)
            roarHighpass = AudioOnePole(cutoff: 140, sampleRate: sampleRate)
            roarLowpass = AudioOnePole(cutoff: 1_300, sampleRate: sampleRate)
        }

        mutating func next(flicker: Float, swell: Float) -> Float {
            let deep = rumbleLowpass.lowpass(rumble.next())
            let warm = roarLowpass.lowpass(roarHighpass.highpass(roar.next()))
            return deep * flicker * 0.9 + warm * swell * 0.8
        }
    }

    private var laneLeft: Lane
    private var laneRight: Lane
    private var flickers: AudioWander
    private var swells: AudioWander
    private var activity: AudioWander
    private var crackles: AudioEventClock
    private var pops: AudioEventClock
    private let pool: AudioResonatorPool
    private let sampleRate: Float

    init(sampleRate: Double, seed: UInt64) {
        laneLeft = Lane(seed: seed, stream: 1, sampleRate: sampleRate)
        laneRight = Lane(seed: seed, stream: 2, sampleRate: sampleRate)
        flickers = AudioWander(seed: seed, stream: 3, period: 0.6...2.2, sampleRate: sampleRate)
        swells = AudioWander(seed: seed, stream: 4, period: 2...6, sampleRate: sampleRate)
        activity = AudioWander(seed: seed, stream: 5, period: 3...8, sampleRate: sampleRate)
        crackles = AudioEventClock(seed: seed, stream: 6, rate: 14, sampleRate: sampleRate)
        pops = AudioEventClock(seed: seed, stream: 7, rate: 0.5, sampleRate: sampleRate)
        pool = AudioResonatorPool(capacity: 24, sampleRate: sampleRate)
        self.sampleRate = Float(sampleRate)
    }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            let flicker = 1 + 0.3 * flickers.next()
            let swell = 1 + 0.25 * swells.next()
            // How lively the fire is right now: crackles come in spells, not at an even pace.
            let lively = 1 + 0.6 * activity.next()
            left[frame] = laneLeft.next(flicker: flicker, swell: swell)
            right[frame] = laneRight.next(flicker: flicker, swell: swell)

            if crackles.tick(rate: 14 * lively) {
                let size = crackles.unit()
                strikeCrackle(amplitude: 0.12 + 2.0 * size * size * size, delay: frame)
                if crackles.unit() < 0.22 {
                    // A little burst: a few small crackles close behind the first.
                    let extra = 1 + Int(crackles.unit() * 3)
                    var offset = frame
                    for _ in 0..<extra {
                        offset += Int(sampleRate * crackles.range(0.004, 0.025))
                        strikeCrackle(amplitude: 0.1 + 0.5 * crackles.unit(), delay: offset)
                    }
                }
            }
            if pops.tick(rate: 0.5 * lively) {
                let warmth = pops.unit()
                let pan = pops.signed() * 0.8
                pool.strike(frequency: 380 + 520 * warmth, decay: 0.012 + 0.02 * pops.unit(), amplitude: 0.9 + 1.0 * pops.unit(), pan: pan, delay: frame)
                pool.strike(frequency: 2_400, decay: 0.002, amplitude: 0.7, pan: pan, delay: frame)
            }
        }
        pool.render(addingTo: left, right, frames: frames)
    }

    private mutating func strikeCrackle(amplitude: Float, delay: Int) {
        pool.strike(
            frequency: 1_100 + 4_200 * crackles.unit(),
            decay: crackles.range(0.0008, 0.003),
            amplitude: amplitude,
            pan: crackles.signed() * 0.9,
            delay: delay
        )
    }
}

// MARK: - Kettle

/// A kettle coming up to the simmer: a soft steady hush with a low thrum underneath, and bubbles that start few and
/// slow and grow busier over the first half minute. Never a whistle. The bubbles get quieter as they get more
/// numerous, so the overall loudness stays put.
struct AmbienceKettleVoice: AmbienceVoice {
    /// Seconds for the bubbling to build from the first slow blips to a rolling simmer.
    static let riseSeconds: Float = 20

    private struct Lane {
        var hush: AudioNoiseSource
        var hushBand: AudioBiquad
        var thrum: AudioNoiseSource
        var thrumLowpass: AudioOnePole

        init(seed: UInt64, stream: UInt64, sampleRate: Double) {
            hush = AudioNoiseSource(color: .pink, seed: seed, stream: stream, sampleRate: sampleRate)
            hushBand = AudioBiquad(bandpass: 1_100, q: 0.7, sampleRate: sampleRate)
            thrum = AudioNoiseSource(color: .brown, seed: seed, stream: stream + 10, sampleRate: sampleRate)
            thrumLowpass = AudioOnePole(cutoff: 240, sampleRate: sampleRate)
        }

        mutating func next(level: Float) -> Float {
            hushBand.process(hush.next()) * level + thrumLowpass.lowpass(thrum.next()) * 0.35
        }
    }

    private var laneLeft: Lane
    private var laneRight: Lane
    private var wobble: AudioWander
    private var rolls: AudioWander
    private var bubbles: AudioEventClock
    private var ticks: AudioEventClock
    private let pool: AudioResonatorPool
    private let sampleRate: Float
    private var elapsed: Int = 0

    init(sampleRate: Double, seed: UInt64) {
        laneLeft = Lane(seed: seed, stream: 1, sampleRate: sampleRate)
        laneRight = Lane(seed: seed, stream: 2, sampleRate: sampleRate)
        wobble = AudioWander(seed: seed, stream: 3, period: 4...10, sampleRate: sampleRate)
        rolls = AudioWander(seed: seed, stream: 4, period: 3...8, sampleRate: sampleRate)
        bubbles = AudioEventClock(seed: seed, stream: 5, rate: 2.5, sampleRate: sampleRate)
        ticks = AudioEventClock(seed: seed, stream: 6, rate: 0.5, sampleRate: sampleRate)
        pool = AudioResonatorPool(capacity: 24, sampleRate: sampleRate)
        self.sampleRate = Float(sampleRate)
    }

    /// How far along the build-up is at `seconds`, 0 to 1, easing in and out.
    static func warmth(atSeconds seconds: Float) -> Float {
        let progress = min(1, max(0, seconds / riseSeconds))
        return progress * progress * (3 - 2 * progress)
    }

    /// Bubbles per second: a few at first, a rolling simmer once warm. `rolling` (-1 to 1) is the slow swell of the
    /// simmer.
    static func bubbleRate(atSeconds seconds: Float, rolling: Float) -> Float {
        2.5 + 22 * warmth(atSeconds: seconds) * (1 + 0.3 * min(1, max(-1, rolling)))
    }

    /// How loud each bubble is at a given rate. Falls with the square root of the rate, so the total energy of the
    /// bubbles (rate times loudness squared) stays the same as they multiply.
    static func bubbleLoudness(forRate rate: Float) -> Float {
        1.6 / (max(rate, 2.5) / 2.5).squareRoot()
    }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            let seconds = Float(elapsed) / sampleRate
            elapsed += 1
            let level = 1 + 0.15 * wobble.next()
            left[frame] = laneLeft.next(level: level)
            right[frame] = laneRight.next(level: level)

            let rate = AmbienceKettleVoice.bubbleRate(atSeconds: seconds, rolling: rolls.next())
            if bubbles.tick(rate: rate) {
                let small = bubbles.unit()
                pool.strike(
                    frequency: 300 + 1_100 * small * small,
                    decay: 0.006 + 0.018 * bubbles.unit(),
                    amplitude: AmbienceKettleVoice.bubbleLoudness(forRate: rate) * (0.5 + 0.5 * bubbles.unit()),
                    pan: bubbles.signed() * 0.7,
                    delay: frame
                )
            }
            // The metal ticking as it warms, which fades once the water is moving.
            let warm = AmbienceKettleVoice.warmth(atSeconds: seconds)
            if ticks.tick(rate: 0.1 + 0.9 * (1 - warm)) {
                pool.strike(frequency: 2_800 + 1_200 * ticks.unit(), decay: ticks.range(0.003, 0.006), amplitude: 0.35, pan: ticks.signed(), delay: frame)
            }
        }
        pool.render(addingTo: left, right, frames: frames)
    }
}

// MARK: - Cafe

/// A cafe a few tables away: several unseen talkers made of band-limited noise whose formants drift and whose
/// loudness rises and falls like syllables and phrases, a soft room underneath, and the odd faint clink.
struct AmbienceCafeVoice: AmbienceVoice {
    /// How often, in samples, the formants are re-tuned (cheap, and slower than the ear can follow).
    private static let retuneInterval = 64

    private struct Talker {
        var breath: AudioNoiseSource
        var low: AudioBiquad
        var high: AudioBiquad
        var syllables: AudioWander
        var phrases: AudioWander
        var driftLow: AudioWander
        var driftHigh: AudioWander
        let centreLow: Double
        let centreHigh: Double
        let gainLeft: Float
        let gainRight: Float
        let sampleRate: Double

        init(index: Int, seed: UInt64, sampleRate: Double) {
            let stream = UInt64(index) * 16 + 100
            // Each talker has their own voice: a first formant near 400 to 650 Hz and a second near 1.4 to 2.4 kHz.
            let lows: [Double] = [430, 540, 620, 480]
            let highs: [Double] = [1_500, 1_900, 2_300, 1_700]
            let pans: [Float] = [-0.75, -0.25, 0.3, 0.8]
            let slot = index % lows.count
            centreLow = lows[slot]
            centreHigh = highs[slot]
            (gainLeft, gainRight) = AudioPan.gains(pans[slot])
            self.sampleRate = sampleRate
            breath = AudioNoiseSource(color: .white, seed: seed, stream: stream, sampleRate: sampleRate)
            low = AudioBiquad(bandpass: centreLow, q: 3.5, sampleRate: sampleRate)
            high = AudioBiquad(bandpass: centreHigh, q: 4.5, sampleRate: sampleRate)
            syllables = AudioWander(seed: seed, stream: stream + 1, period: 0.14...0.4, sampleRate: sampleRate)
            phrases = AudioWander(seed: seed, stream: stream + 2, period: 1.5...6, sampleRate: sampleRate)
            let control = sampleRate / Double(AmbienceCafeVoice.retuneInterval)
            driftLow = AudioWander(seed: seed, stream: stream + 3, period: 2...6, sampleRate: control)
            driftHigh = AudioWander(seed: seed, stream: stream + 4, period: 2...6, sampleRate: control)
        }

        mutating func retune() {
            low.retune(bandpass: centreLow * Double(1 + 0.3 * driftLow.next()), q: 3.5, sampleRate: sampleRate)
            high.retune(bandpass: centreHigh * Double(1 + 0.22 * driftHigh.next()), q: 4.5, sampleRate: sampleRate)
        }

        /// One sample of this talker, before panning.
        mutating func next() -> Float {
            let air = breath.next()
            let syllable = syllables.next() * 0.5 + 0.5
            let phrase = phrases.next() * 0.5 + 0.5
            let syllableLevel = 0.25 + 0.75 * syllable
            let envelope = syllableLevel * syllableLevel * (0.55 + 0.45 * phrase)
            return (low.process(air) + 0.6 * high.process(air)) * envelope
        }
    }

    private struct Room {
        var air: AudioNoiseSource
        var lowpass: AudioOnePole

        init(seed: UInt64, stream: UInt64, sampleRate: Double) {
            air = AudioNoiseSource(color: .pink, seed: seed, stream: stream, sampleRate: sampleRate)
            lowpass = AudioOnePole(cutoff: 2_200, sampleRate: sampleRate)
        }

        mutating func next() -> Float { lowpass.lowpass(air.next()) }
    }

    private var talkers: [Talker]
    private var roomLeft: Room
    private var roomRight: Room
    private var clinks: AudioEventClock
    private let pool: AudioResonatorPool
    private var untilRetune = 0

    init(sampleRate: Double, seed: UInt64) {
        talkers = (0..<4).map { Talker(index: $0, seed: seed, sampleRate: sampleRate) }
        roomLeft = Room(seed: seed, stream: 1, sampleRate: sampleRate)
        roomRight = Room(seed: seed, stream: 2, sampleRate: sampleRate)
        clinks = AudioEventClock(seed: seed, stream: 3, rate: 0.22, sampleRate: sampleRate)
        pool = AudioResonatorPool(capacity: 10, sampleRate: sampleRate)
    }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            if untilRetune <= 0 {
                untilRetune = AmbienceCafeVoice.retuneInterval
                for index in talkers.indices { talkers[index].retune() }
            }
            untilRetune -= 1

            var murmurLeft: Float = 0
            var murmurRight: Float = 0
            for index in talkers.indices {
                let voice = talkers[index].next()
                murmurLeft += voice * talkers[index].gainLeft
                murmurRight += voice * talkers[index].gainRight
            }
            left[frame] = murmurLeft * 6 + roomLeft.next() * 0.22
            right[frame] = murmurRight * 6 + roomRight.next() * 0.22

            if clinks.tick(rate: 0.22) {
                // A glass or a spoon: two inharmonic partials with a long, quiet ring.
                let base = clinks.range(2_600, 4_300)
                let ring = clinks.range(0.07, 0.2)
                let amplitude = clinks.range(0.35, 0.8)
                let pan = clinks.signed() * 0.85
                pool.strike(frequency: base, decay: ring, amplitude: amplitude, pan: pan, delay: frame)
                pool.strike(frequency: base * clinks.range(1.52, 2.1), decay: ring * 0.6, amplitude: amplitude * 0.55, pan: pan, delay: frame)
            }
        }
        pool.render(addingTo: left, right, frames: frames)
    }
}

// MARK: - Library

/// A library on a weekday: almost nothing. A faint low room tone, a breath of air, and now and then a page turned
/// somewhere far off.
struct AmbienceLibraryVoice: AmbienceVoice {
    private struct Lane {
        var tone: AudioNoiseSource
        var toneLowpass: AudioOnePole
        var air: AudioNoiseSource
        var airLowpass: AudioOnePole

        init(seed: UInt64, stream: UInt64, sampleRate: Double) {
            tone = AudioNoiseSource(color: .brown, seed: seed, stream: stream, sampleRate: sampleRate)
            toneLowpass = AudioOnePole(cutoff: 260, sampleRate: sampleRate)
            air = AudioNoiseSource(color: .pink, seed: seed, stream: stream + 10, sampleRate: sampleRate)
            airLowpass = AudioOnePole(cutoff: 1_600, sampleRate: sampleRate)
        }

        mutating func next(level: Float) -> Float {
            toneLowpass.lowpass(tone.next()) * 0.8 * level + airLowpass.lowpass(air.next()) * 0.55
        }
    }

    /// A distant page turn: a short rustle of band-limited noise that arrives quickly and trails off.
    private struct Rustle {
        var paper: AudioNoiseSource
        var band: AudioBiquad
        var crinkle: AudioEventClock
        var crinkleLevel: Float = 0
        var gainLeft: Float = 0
        var gainRight: Float = 0
        var elapsed = 0
        var length = 0
        var cooldown = 0
        let crinkleDecay: Float
        let sampleRate: Double

        init(seed: UInt64, sampleRate: Double) {
            paper = AudioNoiseSource(color: .white, seed: seed, stream: 50, sampleRate: sampleRate)
            band = AudioBiquad(bandpass: 2_400, q: 0.9, sampleRate: sampleRate)
            crinkle = AudioEventClock(seed: seed, stream: 51, rate: 70, sampleRate: sampleRate)
            crinkleDecay = Float(exp(-1 / (0.006 * sampleRate)))
            self.sampleRate = sampleRate
        }

        var isActive: Bool { elapsed < length }

        mutating func begin() {
            let seconds = Double(crinkle.range(0.45, 0.9))
            length = Int(seconds * sampleRate)
            elapsed = 0
            cooldown = Int(6 * sampleRate)
            let pan = crinkle.signed() * 0.7
            (gainLeft, gainRight) = AudioPan.gains(pan)
            band.retune(bandpass: Double(crinkle.range(1_800, 3_200)), q: 0.9, sampleRate: sampleRate)
        }

        /// One sample of rustle as (left, right); silent between page turns.
        mutating func next(rate: Float) -> (Float, Float) {
            if cooldown > 0 { cooldown -= 1 }
            if crinkle.tick(rate: 70) { crinkleLevel += 0.4 + 0.6 * crinkle.unit() }
            crinkleLevel *= crinkleDecay
            guard isActive else { return (0, 0) }
            let t = Float(elapsed) / Float(max(length, 1))
            elapsed += 1
            let attack = min(1, t / 0.12)
            let envelope = attack * attack * (3 - 2 * attack) * (1 - t) * (1 - t)
            let sound = band.process(paper.next()) * envelope * (0.3 + crinkleLevel)
            return (sound * gainLeft, sound * gainRight)
        }
    }

    private var laneLeft: Lane
    private var laneRight: Lane
    private var breathing: AudioWander
    private var turns: AudioEventClock
    private var rustle: Rustle

    init(sampleRate: Double, seed: UInt64) {
        laneLeft = Lane(seed: seed, stream: 1, sampleRate: sampleRate)
        laneRight = Lane(seed: seed, stream: 2, sampleRate: sampleRate)
        breathing = AudioWander(seed: seed, stream: 3, period: 5...14, sampleRate: sampleRate)
        turns = AudioEventClock(seed: seed, stream: 4, rate: 1.0 / 20, sampleRate: sampleRate)
        rustle = Rustle(seed: seed, sampleRate: sampleRate)
    }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            let level = 1 + 0.2 * breathing.next()
            if turns.tick(rate: 1.0 / 20), !rustle.isActive, rustle.cooldown == 0 { rustle.begin() }
            let page = rustle.next(rate: 70)
            left[frame] = laneLeft.next(level: level) + page.0 * 3
            right[frame] = laneRight.next(level: level) + page.1 * 3
        }
    }
}
