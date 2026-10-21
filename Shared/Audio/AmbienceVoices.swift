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

/// A wood fire a few feet away, built from what a fire is rather than what its spectrum looks like:
/// - a low roar (brown noise between 60 and 350 Hz) that flickers and swells,
/// - a faint breath of burning gas above it,
/// - crackles: clusters of tiny noise bursts (a tenth of a millisecond to under a millisecond each, coloured by a
///   broad band anywhere from 0.9 to 7 kHz), arriving in spells; most are small, a few are sharp,
/// - now and then a pop, a bigger and lower burst followed by a spray of small ones.
/// Nothing rings at a pitch, so nothing drips.
struct AmbienceFireVoice: AmbienceVoice {
    private struct Lane {
        var brown: AudioNoiseSource
        var roarHighpass: AudioFilter
        var roarLowpass: AudioFilter
        var gas: AudioNoiseSource
        var gasHighpass: AudioFilter
        var gasLowpass: AudioFilter

        init(seed: UInt64, stream: UInt64, sampleRate: Double) {
            brown = AudioNoiseSource(color: .brown, seed: seed, stream: stream, sampleRate: sampleRate)
            roarHighpass = AudioFilter(.highpass, frequency: 60, sampleRate: sampleRate)
            roarLowpass = AudioFilter(.lowpass, frequency: 350, sampleRate: sampleRate)
            gas = AudioNoiseSource(color: .pink, seed: seed, stream: stream + 10, sampleRate: sampleRate)
            gasHighpass = AudioFilter(.highpass, frequency: 900, sampleRate: sampleRate)
            gasLowpass = AudioFilter(.lowpass, frequency: 3_500, sampleRate: sampleRate)
        }

        mutating func next(roar: Float, breath: Float) -> Float {
            let low = roarLowpass.process(roarHighpass.process(brown.next()))
            let air = gasLowpass.process(gasHighpass.process(gas.next()))
            return low * roar + air * breath
        }
    }

    static let roarLevel: Float = 0.45
    static let breathLevel: Float = 0.02
    static let crackleLevel: Float = 3
    /// Crackle clusters a second, before the fire's liveliness.
    static let clusterRate: Float = 6
    static let popRate: Float = 0.12

    private var laneLeft: Lane
    private var laneRight: Lane
    private var flicker: AudioWander
    private var swell: AudioWander
    private var activity: AudioWander
    private var flutter: AudioWander
    private var clusters: AudioEventClock
    private var pops: AudioEventClock
    private let bursts: AudioBurstPool
    private let sampleRate: Float

    init(sampleRate: Double, seed: UInt64) {
        laneLeft = Lane(seed: seed, stream: 1, sampleRate: sampleRate)
        laneRight = Lane(seed: seed, stream: 2, sampleRate: sampleRate)
        flicker = AudioWander(seed: seed, stream: 3, period: 0.5...1.6, sampleRate: sampleRate)
        swell = AudioWander(seed: seed, stream: 4, period: 3...8, sampleRate: sampleRate)
        activity = AudioWander(seed: seed, stream: 5, period: 2...7, sampleRate: sampleRate)
        flutter = AudioWander(seed: seed, stream: 6, period: 0.06...0.25, sampleRate: sampleRate)
        clusters = AudioEventClock(seed: seed, stream: 7, rate: AmbienceFireVoice.clusterRate, sampleRate: sampleRate)
        pops = AudioEventClock(seed: seed, stream: 8, rate: AmbienceFireVoice.popRate, sampleRate: sampleRate)
        bursts = AudioBurstPool(capacity: 48, sampleRate: sampleRate, seed: seed, stream: 9)
        self.sampleRate = Float(sampleRate)
    }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            let roar = AmbienceFireVoice.roarLevel * (1 + 0.22 * flicker.next()) * (1 + 0.15 * swell.next())
            let lively = 1 + 0.7 * activity.next()
            let breath = AmbienceFireVoice.breathLevel * (1 + 0.5 * flutter.next()) * (0.7 + 0.3 * lively)
            left[frame] = laneLeft.next(roar: roar, breath: breath)
            right[frame] = laneRight.next(roar: roar, breath: breath)
            if clusters.tick(rate: AmbienceFireVoice.clusterRate * lively) { crackle(at: frame) }
            if pops.tick(rate: AmbienceFireVoice.popRate * lively) { pop(at: frame) }
        }
        bursts.render(addingTo: left, right, frames: frames)
    }

    /// A broad colour between `low` and `high` Hz, spread evenly on a log scale (`u` from 0 to 1).
    static func band(_ low: Float, _ high: Float, _ u: Float) -> Float {
        exp(log(low) + (log(high) - log(low)) * u)
    }

    /// A cluster: one to a dozen bursts a few milliseconds apart. Loudness follows a heavy tail, so most crackles are
    /// small and a few are sharp.
    private mutating func crackle(at frame: Int) {
        let u = max(clusters.unit(), 1e-6)
        let size = min(1.8, 0.12 * pow(u, -1 / 1.8))
        var count = 1
        while clusters.unit() < 0.62 && count < 12 { count += 1 }
        let pan = clusters.signed() * 0.85
        var offset = frame
        for index in 0..<count {
            let amplitude = size * (index == 0 ? 1 : 0.25 + 0.65 * clusters.unit())
            bursts.strike(
                frequency: AmbienceFireVoice.band(900, 7_000, clusters.unit()),
                q: 0.7 + 0.6 * clusters.unit(),
                decay: 0.00012 + 0.0006 * clusters.unit(),
                amplitude: amplitude * AmbienceFireVoice.crackleLevel,
                pan: pan + 0.1 * clusters.signed(),
                delay: offset
            )
            // Exponential gaps averaging about seven milliseconds.
            offset += Int(sampleRate * (0.0006 - 0.007 * log(max(clusters.unit(), 1e-6))))
        }
    }

    /// A pop: a lower, longer burst, then embers spitting.
    private mutating func pop(at frame: Int) {
        let pan = pops.signed() * 0.7
        bursts.strike(
            frequency: 500 + 1_100 * pops.unit(),
            q: 0.6,
            decay: 0.0015 + 0.0025 * pops.unit(),
            amplitude: (1.2 + 1.0 * pops.unit()) * AmbienceFireVoice.crackleLevel,
            pan: pan,
            delay: frame
        )
        var offset = frame + Int(sampleRate * 0.004)
        let sparks = 3 + Int(pops.unit() * 6)
        for _ in 0..<sparks {
            offset += Int(sampleRate * (0.003 - 0.018 * log(max(pops.unit(), 1e-6))))
            bursts.strike(
                frequency: AmbienceFireVoice.band(1_200, 7_000, pops.unit()),
                q: 0.9,
                decay: 0.0001 + 0.0005 * pops.unit(),
                amplitude: (0.3 + 0.7 * pops.unit()) * 0.8 * AmbienceFireVoice.crackleLevel,
                pan: pan + 0.2 * pops.signed(),
                delay: offset
            )
        }
    }
}

// MARK: - Kettle

/// A kettle coming to the boil in the next room, never a whistle: first the quiet seethe of tiny bubbles collapsing on
/// the element (granular noise around 2 kHz) over a low roar, then bubbles proper, each a few milliseconds long and
/// rising in pitch, growing from a few to a rolling simmer over the first half minute, after which it simmers on.
/// The bubbles get quieter as they multiply, so the simmer doesn't keep getting louder.
struct AmbienceKettleVoice: AmbienceVoice {
    /// Seconds for the water to come up to the simmer.
    static let riseSeconds: Float = 30

    private struct Lane {
        var brown: AudioNoiseSource
        var roarHighpass: AudioFilter
        var roarLowpass: AudioFilter
        var seethe: AudioNoiseSource
        var seetheBand: AudioFilter
        var grains: AudioEventClock
        var grain: Float = 0
        let grainDecay: Float
        var outputLowpass: AudioFilter

        init(seed: UInt64, stream: UInt64, sampleRate: Double) {
            brown = AudioNoiseSource(color: .brown, seed: seed, stream: stream, sampleRate: sampleRate)
            roarHighpass = AudioFilter(.highpass, frequency: 90, sampleRate: sampleRate)
            roarLowpass = AudioFilter(.lowpass, frequency: 450, sampleRate: sampleRate)
            seethe = AudioNoiseSource(color: .white, seed: seed, stream: stream + 10, sampleRate: sampleRate)
            seetheBand = AudioFilter(.bandpass, frequency: 2_200, q: 0.8, sampleRate: sampleRate)
            grains = AudioEventClock(seed: seed, stream: stream + 20, rate: 120, sampleRate: sampleRate)
            grainDecay = Float(exp(-1 / (0.0005 * sampleRate)))
            outputLowpass = AudioFilter(.lowpass, frequency: 5_000, sampleRate: sampleRate)
        }

        mutating func next(roar: Float, seetheLevel: Float, grainRate: Float) -> Float {
            let low = roarLowpass.process(roarHighpass.process(brown.next())) * roar
            if grains.tick(rate: grainRate) { grain += 0.3 + 0.9 * grains.unit() }
            grain *= grainDecay
            return low + seetheBand.process(seethe.next()) * grain * seetheLevel
        }
    }

    private var laneLeft: Lane
    private var laneRight: Lane
    private var rolls: AudioWander
    private var drift: AudioWander
    private var bubbles: AudioEventClock
    private var ticks: AudioEventClock
    private let bubblePool: AudioBubblePool
    private let bursts: AudioBurstPool
    private let room: AudioRoom
    private let sampleRate: Float
    private var elapsed = 0

    init(sampleRate: Double, seed: UInt64) {
        laneLeft = Lane(seed: seed, stream: 1, sampleRate: sampleRate)
        laneRight = Lane(seed: seed, stream: 2, sampleRate: sampleRate)
        rolls = AudioWander(seed: seed, stream: 3, period: 2...6, sampleRate: sampleRate)
        drift = AudioWander(seed: seed, stream: 4, period: 4...10, sampleRate: sampleRate)
        bubbles = AudioEventClock(seed: seed, stream: 5, rate: 1, sampleRate: sampleRate)
        ticks = AudioEventClock(seed: seed, stream: 6, rate: 0.5, sampleRate: sampleRate)
        bubblePool = AudioBubblePool(capacity: 40, sampleRate: sampleRate)
        bursts = AudioBurstPool(capacity: 6, sampleRate: sampleRate, seed: seed, stream: 7)
        room = AudioRoom(sampleRate: sampleRate, size: 0.9, feedback: 0.7, damp: 0.5)
        self.sampleRate = Float(sampleRate)
    }

    static func smoothstep(_ value: Float) -> Float {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }

    /// How far the water has come, 0 to 1, at `seconds`.
    static func warmth(atSeconds seconds: Float) -> Float { smoothstep(seconds / riseSeconds) }

    /// How far the bubbling has settled into a simmer, 0 to 1 (it starts most of the way through the rise).
    static func simmer(atSeconds seconds: Float) -> Float { smoothstep((seconds - riseSeconds * 0.7) / (riseSeconds * 0.5)) }

    /// Bubbles a second: one now and then at first, a rolling simmer at the end. `rolling` (-1 to 1) is its swell.
    static func bubbleRate(atSeconds seconds: Float, rolling: Float) -> Float {
        let settled = simmer(atSeconds: seconds)
        return (0.5 + 75 * settled * settled + 8 * warmth(atSeconds: seconds)) * (1 + 0.35 * min(1, max(-1, rolling)))
    }

    /// How loud each bubble is at a given rate: quieter as they multiply (the energy of the bubbling, rate times
    /// loudness squared, stays put), and small while the water is still coming up.
    static func bubbleLoudness(forRate rate: Float, simmer: Float) -> Float {
        4 * (0.2 + 0.8 * simmer) / (max(rate, 4) / 4).squareRoot()
    }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            let seconds = Float(elapsed) / sampleRate
            elapsed += 1
            let warm = AmbienceKettleVoice.warmth(atSeconds: seconds)
            let settled = AmbienceKettleVoice.simmer(atSeconds: seconds)
            let roll = rolls.next()
            let roar = 0.4 * (0.25 + 0.75 * warm) * (1 + 0.2 * roll)
            let seetheLevel = 0.2 * warm * (1 - 0.35 * settled) * (1 + 0.15 * drift.next())
            let grainRate = (120 + 480 * warm) * (1 + 0.2 * roll)
            left[frame] = laneLeft.next(roar: roar, seetheLevel: seetheLevel, grainRate: grainRate)
            right[frame] = laneRight.next(roar: roar, seetheLevel: seetheLevel, grainRate: grainRate)

            let rate = AmbienceKettleVoice.bubbleRate(atSeconds: seconds, rolling: roll)
            if bubbles.tick(rate: rate) {
                // Bigger (lower) bubbles as it comes to the simmer.
                let size = bubbles.unit() * (0.4 + 0.6 * settled)
                bubblePool.strike(
                    frequency: 3_600 / pow(4.5, size),
                    decay: 0.0015 + 0.0035 * bubbles.unit(),
                    rise: 0.2 + 0.5 * bubbles.unit(),
                    amplitude: AmbienceKettleVoice.bubbleLoudness(forRate: rate, simmer: settled) * (0.4 + 0.6 * bubbles.unit()),
                    pan: bubbles.signed() * 0.6,
                    delay: frame
                )
            }
            // The element ticking as it heats, until the water is moving.
            if ticks.tick(rate: 0.05 + 0.5 * (1 - warm)) {
                bursts.strike(frequency: 2_500 + 1_500 * ticks.unit(), q: 0.9, decay: 0.0002, amplitude: 0.06, pan: ticks.signed() * 0.5, delay: frame)
            }
        }
        bubblePool.render(addingTo: left, right, frames: frames)
        bursts.render(addingTo: left, right, frames: frames)
        // The next room: a little of it around the sound, and the top taken off.
        for frame in 0..<frames {
            let wet = room.process(0.5 * (left[frame] + right[frame]))
            left[frame] = laneLeft.outputLowpass.process(left[frame] + 0.3 * wet.left)
            right[frame] = laneRight.outputLowpass.process(right[frame] + 0.3 * wet.right)
        }
    }
}

// MARK: - Cafe

/// A café a few tables away: ten people talking, each a voice made the way speech is made (a pitched buzz from the
/// throat shaped by three moving formants into syllables, a breath of consonant now and then), with their own pitch,
/// distance and place in the room, talking in phrases and pausing. All of it reaches you through the room, so the
/// words blur into murmur. Underneath, the room itself; now and then a cup on a saucer.
struct AmbienceCafeVoice: AmbienceVoice {
    /// How often, in samples, the formants follow their targets (cheap, and quicker than the ear can follow).
    private static let retuneInterval = 32
    static let talkerCount = 10
    static let vowels: [(Double, Double, Double)] = [
        (730, 1_090, 2_440), (530, 1_840, 2_480), (270, 2_290, 3_010), (570, 840, 2_410),
        (300, 870, 2_240), (660, 1_720, 2_410), (490, 1_350, 1_690),
    ]

    private struct Talker {
        var random: AudioRandom
        let pitch: Float
        let scale: Double
        let gain: Float
        let gainLeft: Float
        let gainRight: Float
        let send: Float
        let sampleRate: Double
        /// The throat's pulse is low-passed then differenced, which scales its level with the square of the sample
        /// rate; this undoes that, so the café sounds the same at 22 kHz (Low Power Mode) as at 44.1.
        let pulseHeight: Float
        /// White noise holds its level per hertz at any rate, as `AudioNoiseSource` does.
        let noiseScale: Float
        var phase: Float = 0
        var glottis: AudioFilter
        var previous: Float = 0
        var first: AudioFilter
        var second: AudioFilter
        var third: AudioFilter
        var current: (Double, Double, Double)
        var target: (Double, Double, Double)
        var distanceA: AudioOnePole
        var distanceB: AudioOnePole
        var consonant: AudioOnePole
        var hiss: Float = 0
        let hissDecay: Float
        var speaking = false
        var left = 0
        var phraseLength = 1
        var phrasePosition = 0
        var syllableLeft = 0
        var syllableLength = 1
        var accent: Float = 1
        var level: Float = 0

        init(index: Int, seed: UInt64, sampleRate: Double) {
            var random = AudioRandom(seed: seed, stream: 100 + UInt64(index))
            let female = index % 2 == 1
            pitch = female ? 175 + 50 * random.unit() : 95 + 40 * random.unit()
            scale = female ? 1.15 : 1
            let distance = random.unit()
            gain = 1 - 0.6 * distance
            send = 1.4 - gain
            (gainLeft, gainRight) = AudioPan.gains(random.signed() * 0.9)
            self.sampleRate = sampleRate
            let ratio = sampleRate / 44_100
            pulseHeight = Float(ratio * ratio)
            noiseScale = Float(ratio.squareRoot())
            glottis = AudioFilter(.lowpass, frequency: 700, q: 0.6, sampleRate: sampleRate)
            let vowel = AmbienceCafeVoice.vowel(random.unit())
            current = (vowel.0 * scale, vowel.1 * scale, vowel.2 * scale)
            target = current
            first = AudioFilter(.bandpass, frequency: current.0, q: current.0 / 80, sampleRate: sampleRate)
            second = AudioFilter(.bandpass, frequency: current.1, q: current.1 / 120, sampleRate: sampleRate)
            third = AudioFilter(.bandpass, frequency: current.2, q: current.2 / 160, sampleRate: sampleRate)
            let cutoff = 3_200 - 1_700 * Double(distance)
            distanceA = AudioOnePole(cutoff: cutoff, sampleRate: sampleRate)
            distanceB = AudioOnePole(cutoff: cutoff, sampleRate: sampleRate)
            consonant = AudioOnePole(cutoff: 2_500, sampleRate: sampleRate)
            hissDecay = Float(exp(-1 / (0.02 * sampleRate)))
            // Half the room is already mid-sentence when the sound starts.
            if index % 2 == 0 {
                speaking = true
                left = Int(Double(0.4 + 2.5 * random.unit()) * sampleRate)
                phraseLength = left + Int(sampleRate)
                phrasePosition = Int(sampleRate)
                level = 0.5
            } else {
                left = Int(Double(2 * random.unit()) * sampleRate)
            }
            self.random = random
        }

        /// The formants glide a quarter of the way to their targets.
        mutating func retune() {
            current.0 += 0.25 * (target.0 - current.0)
            current.1 += 0.25 * (target.1 - current.1)
            current.2 += 0.25 * (target.2 - current.2)
            first.retune(.bandpass, frequency: current.0, q: current.0 / 80, sampleRate: sampleRate)
            second.retune(.bandpass, frequency: current.1, q: current.1 / 120, sampleRate: sampleRate)
            third.retune(.bandpass, frequency: current.2, q: current.2 / 160, sampleRate: sampleRate)
        }

        /// Whether there is anything to hear from this talker right now.
        var isQuiet: Bool { level < 1e-4 && !speaking && hiss < 1e-4 }

        /// One sample of this talker, before panning.
        mutating func next() -> Float {
            left -= 1
            if left <= 0 {
                if speaking {
                    speaking = false
                    left = Int(Double(0.6 + 3 * random.unit()) * sampleRate)
                } else {
                    speaking = true
                    left = Int(Double(1.2 + 3.5 * random.unit()) * sampleRate)
                    phraseLength = left
                    phrasePosition = 0
                    syllableLeft = 0
                }
            }
            var want: Float = 0
            if speaking {
                phrasePosition += 1
                syllableLeft -= 1
                if syllableLeft <= 0 {
                    syllableLength = Int(Double(0.11 + 0.17 * random.unit()) * sampleRate)
                    syllableLeft = syllableLength
                    let vowel = AmbienceCafeVoice.vowel(random.unit())
                    let lilt = scale * Double(0.95 + 0.1 * random.unit())
                    target = (vowel.0 * lilt, vowel.1 * lilt, vowel.2 * lilt)
                    accent = 0.9 + 0.25 * random.unit()
                    if random.unit() < 0.45 { hiss = 0.5 + 0.5 * random.unit() }
                }
                let position = 1 - Float(syllableLeft) / Float(max(syllableLength, 1))
                let rise = min(1, position / 0.15)
                let fall = min(1, (1 - position) / 0.3)
                want = rise * fall * accent
            }
            level += 0.004 * (want - level)
            if isQuiet { return 0 }

            // The pitch falls a little through each phrase, with a touch of jitter.
            let progress = Float(phrasePosition) / Float(max(phraseLength, 1))
            let hz = pitch * accent * (1.12 - 0.22 * progress) * (1 + 0.012 * random.signed())
            phase += hz / Float(sampleRate)
            var pulse: Float = 0
            if phase >= 1 {
                phase -= 1
                pulse = pulseHeight
            }
            let flow = glottis.process(pulse)
            let source = (flow - previous) * 30 + random.signed() * 0.02 * noiseScale
            previous = flow
            var voice = first.process(source) + 0.5 * second.process(source) + 0.25 * third.process(source)
            voice *= level
            hiss *= hissDecay
            if speaking && hiss > 1e-4 {
                let noise = random.signed() * noiseScale
                voice += (noise - consonant.lowpass(noise)) * hiss * 0.03
            }
            return distanceB.lowpass(distanceA.lowpass(voice)) * gain
        }
    }

    /// A vowel's three formants (an adult male's), picked by `u` from 0 to 1.
    static func vowel(_ u: Float) -> (Double, Double, Double) {
        let index = min(vowels.count - 1, max(0, Int(u * Float(vowels.count))))
        return vowels[index]
    }

    static let wetLevel: Float = 0.5
    static let clinkLevel: Float = 0.07
    static let roomToneLevel: Float = 0.0013

    private var talkers: [Talker]
    private var toneLeft: AudioNoiseSource
    private var toneRight: AudioNoiseSource
    private var toneLowLeft: AudioOnePole
    private var toneLowRight: AudioOnePole
    private var clinks: AudioEventClock
    private let pool: AudioResonatorPool
    private let room: AudioRoom
    private let scratch: AudioScratch
    private var untilRetune = 0

    init(sampleRate: Double, seed: UInt64) {
        talkers = (0..<AmbienceCafeVoice.talkerCount).map { Talker(index: $0, seed: seed, sampleRate: sampleRate) }
        toneLeft = AudioNoiseSource(color: .pink, seed: seed, stream: 1, sampleRate: sampleRate)
        toneRight = AudioNoiseSource(color: .pink, seed: seed, stream: 2, sampleRate: sampleRate)
        toneLowLeft = AudioOnePole(cutoff: 1_200, sampleRate: sampleRate)
        toneLowRight = AudioOnePole(cutoff: 1_200, sampleRate: sampleRate)
        clinks = AudioEventClock(seed: seed, stream: 3, rate: 0.2, sampleRate: sampleRate)
        pool = AudioResonatorPool(capacity: 12, sampleRate: sampleRate)
        room = AudioRoom(sampleRate: sampleRate, size: 1.6, feedback: 0.84, damp: 0.4)
        scratch = AudioScratch(count: 2, capacity: AmbienceSynth.blockSize)
    }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        var done = 0
        while done < frames {
            let count = min(scratch.capacity, frames - done)
            renderPiece(left: left + done, right: right + done, frames: count)
            done += count
        }
    }

    private mutating func renderPiece(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        let clinkLeft = scratch[0]
        let clinkRight = scratch[1]
        // Clinks first, into their own buffers, so they can go to the room as well as straight to the ear.
        clinkLeft.update(repeating: 0, count: frames)
        clinkRight.update(repeating: 0, count: frames)
        for frame in 0..<frames where clinks.tick(rate: 0.2) {
            // A cup or a spoon: two inharmonic partials, the upper one shorter.
            let base = clinks.range(2_200, 4_800)
            let ring = clinks.range(0.04, 0.14)
            let amplitude = AmbienceCafeVoice.clinkLevel * clinks.range(0.3, 1)
            let pan = clinks.signed() * 0.8
            pool.strike(frequency: base, decay: ring, amplitude: amplitude, pan: pan, delay: frame)
            pool.strike(frequency: base * clinks.range(1.5, 2.1), decay: ring * 0.6, amplitude: amplitude * 0.5, pan: pan, delay: frame)
        }
        pool.render(addingTo: clinkLeft, clinkRight, frames: frames)

        for frame in 0..<frames {
            if untilRetune <= 0 {
                untilRetune = AmbienceCafeVoice.retuneInterval
                for index in talkers.indices { talkers[index].retune() }
            }
            untilRetune -= 1
            var dryLeft: Float = 0
            var dryRight: Float = 0
            var send: Float = 0
            for index in talkers.indices {
                let voice = talkers[index].next()
                dryLeft += voice * talkers[index].gainLeft
                dryRight += voice * talkers[index].gainRight
                send += voice * talkers[index].send
            }
            send += 0.6 * (clinkLeft[frame] + clinkRight[frame])
            let wet = room.process(send)
            left[frame] = dryLeft + clinkLeft[frame] + wet.left * AmbienceCafeVoice.wetLevel
                + toneLowLeft.lowpass(toneLeft.next()) * AmbienceCafeVoice.roomToneLevel
            right[frame] = dryRight + clinkRight[frame] + wet.right * AmbienceCafeVoice.wetLevel
                + toneLowRight.lowpass(toneRight.next()) * AmbienceCafeVoice.roomToneLevel
        }
    }
}

// MARK: - Library

/// A reading room on a weekday: very nearly silent, a dark low room tone you feel more than hear (nothing up where a
/// phone speaker would turn it into hiss), and the sounds that make a library a library, each across the room and
/// softened by it: pages turned now and then (a slide, then the flip with its crinkle), someone walking past, a book
/// set down on a table.
struct AmbienceLibraryVoice: AmbienceVoice {
    static let bedLevel: Float = 0.12
    static let airLevel: Float = 0.02
    static let eventLevel: Float = 2
    /// Page turns a second, somewhere in the room.
    static let turnRate: Float = 1.0 / 7
    static let walkRate: Float = 1.0 / 70
    static let bookRate: Float = 1.0 / 50

    private struct Lane {
        var brown: AudioNoiseSource
        var toneHighpass: AudioFilter
        var toneLowpass: AudioFilter
        var air: AudioNoiseSource
        var airLowpass: AudioFilter

        init(seed: UInt64, stream: UInt64, sampleRate: Double) {
            brown = AudioNoiseSource(color: .brown, seed: seed, stream: stream, sampleRate: sampleRate)
            toneHighpass = AudioFilter(.highpass, frequency: 40, sampleRate: sampleRate)
            toneLowpass = AudioFilter(.lowpass, frequency: 180, sampleRate: sampleRate)
            air = AudioNoiseSource(color: .pink, seed: seed, stream: stream + 10, sampleRate: sampleRate)
            airLowpass = AudioFilter(.lowpass, frequency: 500, q: 0.6, sampleRate: sampleRate)
        }

        mutating func next(breathing: Float) -> Float {
            let tone = toneLowpass.process(toneHighpass.process(brown.next()))
            return tone * AmbienceLibraryVoice.bedLevel * breathing + airLowpass.process(air.next()) * AmbienceLibraryVoice.airLevel
        }
    }

    private var laneLeft: Lane
    private var laneRight: Lane
    private var breathing: AudioWander
    private var events: AudioRandom
    private var turns: AudioEventClock
    private var walks: AudioEventClock
    private var books: AudioEventClock
    private var paper: AudioNoiseSource
    private var swish: AudioFilter
    private var thudNoise: AudioNoiseSource
    private var thudLowpass: AudioFilter
    private var distanceLeft: AudioOnePole
    private var distanceRight: AudioOnePole
    private var wetLeft: AudioOnePole
    private var wetRight: AudioOnePole
    private let bursts: AudioBurstPool
    private let room: AudioRoom
    private let scratch: AudioScratch
    private let sampleRate: Float

    // The page being turned.
    private var turnLength = 0
    private var turnElapsed = 0
    private var turnFlip = 0
    private var turnLevel: Float = 0
    private var turnDistance: Float = 0
    private var turnLeft: Float = 0
    private var turnRight: Float = 0
    private var turnPan: Float = 0
    // Someone walking past.
    private var stepsTaken = 0
    private var stepsInWalk = 0
    private var untilStep = 0
    private var walkFrom: Float = 0
    private var walkTo: Float = 0
    // A soft low thud: a footfall or a book.
    private var thud: Float = 0
    private let thudDecay: Float
    private var thudLeft: Float = 0.7
    private var thudRight: Float = 0.7

    init(sampleRate: Double, seed: UInt64) {
        laneLeft = Lane(seed: seed, stream: 1, sampleRate: sampleRate)
        laneRight = Lane(seed: seed, stream: 2, sampleRate: sampleRate)
        breathing = AudioWander(seed: seed, stream: 3, period: 6...15, sampleRate: sampleRate)
        events = AudioRandom(seed: seed, stream: 4)
        turns = AudioEventClock(seed: seed, stream: 5, rate: AmbienceLibraryVoice.turnRate, sampleRate: sampleRate)
        walks = AudioEventClock(seed: seed, stream: 6, rate: AmbienceLibraryVoice.walkRate, sampleRate: sampleRate)
        books = AudioEventClock(seed: seed, stream: 7, rate: AmbienceLibraryVoice.bookRate, sampleRate: sampleRate)
        paper = AudioNoiseSource(color: .white, seed: seed, stream: 8, sampleRate: sampleRate)
        swish = AudioFilter(.bandpass, frequency: 1_800, q: 0.55, sampleRate: sampleRate)
        thudNoise = AudioNoiseSource(color: .white, seed: seed, stream: 9, sampleRate: sampleRate)
        thudLowpass = AudioFilter(.lowpass, frequency: 220, q: 0.8, sampleRate: sampleRate)
        distanceLeft = AudioOnePole(cutoff: 2_500, sampleRate: sampleRate)
        distanceRight = AudioOnePole(cutoff: 2_500, sampleRate: sampleRate)
        wetLeft = AudioOnePole(cutoff: 1_400, sampleRate: sampleRate)
        wetRight = AudioOnePole(cutoff: 1_400, sampleRate: sampleRate)
        bursts = AudioBurstPool(capacity: 40, sampleRate: sampleRate, seed: seed, stream: 10)
        room = AudioRoom(sampleRate: sampleRate, size: 1.15, feedback: 0.78, damp: 0.55)
        scratch = AudioScratch(count: 5, capacity: AmbienceSynth.blockSize)
        thudDecay = Float(exp(-1 / (0.018 * sampleRate)))
        self.sampleRate = Float(sampleRate)
    }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        var done = 0
        while done < frames {
            let count = min(scratch.capacity, frames - done)
            renderPiece(left: left + done, right: right + done, frames: count)
            done += count
        }
    }

    private mutating func renderPiece(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        let burstLeft = scratch[0]
        let burstRight = scratch[1]
        let eventLeft = scratch[2]
        let eventRight = scratch[3]
        let eventSend = scratch[4]
        // Pass one, sample by sample: the room tone, every event's start, the page and the thuds. The bursts
        // (crinkles, scuffs) are struck with their frame and rendered after.
        burstLeft.update(repeating: 0, count: frames)
        burstRight.update(repeating: 0, count: frames)
        for frame in 0..<frames {
            let breath = 1 + 0.12 * breathing.next()
            left[frame] = laneLeft.next(breathing: breath)
            right[frame] = laneRight.next(breathing: breath)
            scheduleEvents(at: frame)
            var dryLeft: Float = 0
            var dryRight: Float = 0
            var send: Float = 0
            if turnElapsed < turnLength {
                let sample = pageSample()
                dryLeft += sample * turnLeft
                dryRight += sample * turnRight
                send += sample * (0.4 + 0.8 * turnDistance)
            }
            if thud > 1e-4 {
                let low = thudLowpass.process(thudNoise.next() * thud)
                thud *= thudDecay
                dryLeft += low * thudLeft * 2.2
                dryRight += low * thudRight * 2.2
                send += low * 1.2
            }
            eventLeft[frame] = dryLeft
            eventRight[frame] = dryRight
            eventSend[frame] = send
        }
        bursts.render(addingTo: burstLeft, burstRight, frames: frames)

        // Pass two: everything that happened, softened by distance and given the room.
        for frame in 0..<frames {
            let dryLeft = eventLeft[frame] + burstLeft[frame]
            let dryRight = eventRight[frame] + burstRight[frame]
            let send = eventSend[frame] + 0.6 * (burstLeft[frame] + burstRight[frame])
            let wet = room.process(send)
            let nearLeft = distanceLeft.lowpass(dryLeft)
            let nearRight = distanceRight.lowpass(dryRight)
            left[frame] += (nearLeft + 0.6 * wetLeft.lowpass(wet.left)) * AmbienceLibraryVoice.eventLevel
            right[frame] += (nearRight + 0.6 * wetRight.lowpass(wet.right)) * AmbienceLibraryVoice.eventLevel
        }
    }

    /// Starts whatever happens at `frame`: a page, a walk and its steps, a book set down.
    private mutating func scheduleEvents(at frame: Int) {
        if turns.tick(rate: AmbienceLibraryVoice.turnRate), turnElapsed >= turnLength {
            turnLength = Int(sampleRate * (0.35 + 0.35 * events.unit()))
            turnElapsed = 0
            turnFlip = Int(Float(turnLength) * (0.45 + 0.2 * events.unit()))
            turnDistance = events.unit()
            turnLevel = (0.35 + 0.65 * events.unit()) * (1 - 0.6 * turnDistance)
            turnPan = events.signed() * 0.8
            (turnLeft, turnRight) = AudioPan.gains(turnPan)
            swish.retune(.bandpass, frequency: Double(1_200 + 1_400 * events.unit()), q: 0.55, sampleRate: Double(sampleRate))
        }
        // The crinkle as the page flips: tiny bursts, about 260 a second for a fifth of a second.
        if turnElapsed < turnLength, abs(turnElapsed - turnFlip) < Int(0.1 * sampleRate), events.unit() < 260 / sampleRate {
            let pan = turnPan
            bursts.strike(
                frequency: exp(log(1_500) + log(3) * events.unit()),
                q: 0.8,
                decay: 0.0002 + 0.0004 * events.unit(),
                amplitude: turnLevel * (0.2 + 0.5 * events.unit()),
                pan: pan,
                delay: frame
            )
        }
        if walks.tick(rate: AmbienceLibraryVoice.walkRate), stepsTaken >= stepsInWalk {
            stepsInWalk = 6 + Int(events.unit() * 7)
            stepsTaken = 0
            untilStep = 0
            walkFrom = events.signed() * 0.9
            walkTo = -walkFrom * (0.5 + 0.5 * events.unit())
        }
        if stepsTaken < stepsInWalk {
            untilStep -= 1
            if untilStep <= 0 {
                untilStep = Int(sampleRate * (0.52 + 0.08 * events.unit()))
                let progress = Float(stepsTaken) / Float(max(stepsInWalk - 1, 1))
                let pan = walkFrom + (walkTo - walkFrom) * progress
                let near = sin(Float.pi * (0.15 + 0.7 * progress))
                thud = max(thud, 0.5 * near * (0.8 + 0.4 * events.unit()))
                (thudLeft, thudRight) = AudioPan.gains(pan)
                bursts.strike(frequency: 1_800 + 800 * events.unit(), q: 0.7, decay: 0.004 + 0.004 * events.unit(), amplitude: 0.05 * near, pan: pan, delay: frame + Int(0.03 * sampleRate))
                stepsTaken += 1
            }
        }
        if books.tick(rate: AmbienceLibraryVoice.bookRate) {
            thud = max(thud, 0.7 + 0.5 * events.unit())
            (thudLeft, thudRight) = AudioPan.gains(events.signed() * 0.8)
            bursts.strike(frequency: 900 + 900 * events.unit(), q: 0.7, decay: 0.0015, amplitude: 0.25, pan: 0, delay: frame)
        }
    }

    /// One sample of the page: a soft slide building up, then the flip, gone in a moment.
    private mutating func pageSample() -> Float {
        let t = Float(turnElapsed) / Float(max(turnLength, 1))
        let slideRise = min(1, t / 0.25)
        let slide = slideRise * slideRise * (3 - 2 * slideRise)
        var flip: Float = 0
        if turnElapsed > turnFlip - Int(0.2 * sampleRate) {
            let distance = Float(turnElapsed - turnFlip) / (0.12 * sampleRate)
            flip = exp(-distance * distance)
        }
        turnElapsed += 1
        let envelope = 0.25 * slide * (1 - t) + flip
        return swish.process(paper.next()) * envelope * turnLevel * 0.5
    }
}
