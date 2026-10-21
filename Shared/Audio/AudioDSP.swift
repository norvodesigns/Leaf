import Foundation

// Small building blocks for the procedural sounds (ambience and cues). Everything here is a plain value type that
// does no heap work once it has been created, so a render loop can run on a real-time audio thread. Time is always
// in seconds and is turned into per-sample coefficients once, so every recipe works at any sample rate.

/// The range of sample rates the synths accept (Low Power Mode uses 22.05 kHz; some routes ask for 96 kHz).
enum AudioSampleRate {
    static let range: ClosedRange<Double> = 8_000...192_000

    /// `rate` pulled into `range`; anything that is not a number becomes 44.1 kHz.
    static func clamped(_ rate: Double) -> Double {
        rate.isNaN ? 44_100 : min(max(rate, range.lowerBound), range.upperBound)
    }
}

// MARK: - Randomness

/// White noise and random draws from a tiny xorshift generator. Seeds go through `SeededGenerator`, so a given seed
/// always makes the same sound, and nothing here reads the clock or the system random source. (Cheaper than
/// `SeededGenerator` per call, which matters when it runs once per audio sample.)
struct AudioRandom: Sendable {
    private var state: UInt64

    /// `stream` splits one seed into independent sequences, so a recipe's left and right noise never match.
    init(seed: UInt64, stream: UInt64 = 0) {
        var seeder = SeededGenerator(seed: seed &+ stream &* 0x9E37_79B9_7F4A_7C15)
        let first = seeder.next()
        state = first == 0 ? 0x2545_F491_4F6C_DD1D : first
    }

    private mutating func bits() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Float { Float(bits() >> 40) * (1.0 / 16_777_216.0) }

    /// Uniform in [-1, 1).
    mutating func signed() -> Float { Float(bits() >> 40) * (1.0 / 8_388_608.0) - 1.0 }

    mutating func range(_ low: Float, _ high: Float) -> Float { low + (high - low) * unit() }
}

// MARK: - Filters

/// A one-pole filter: the cheapest way to tilt, band-limit or smooth a signal.
struct AudioOnePole: Sendable {
    /// How far the output moves toward the input each sample.
    private(set) var coefficient: Float
    private var state: Float = 0

    init(cutoff: Double, sampleRate: Double) {
        coefficient = AudioOnePole.coefficient(cutoff: cutoff, sampleRate: sampleRate)
    }

    static func coefficient(cutoff: Double, sampleRate: Double) -> Float {
        let limit = max(sampleRate, 1) * 0.45
        let hz = cutoff.isNaN ? limit : min(max(cutoff, 1), limit)
        return Float(1 - exp(-2 * Double.pi * hz / max(sampleRate, 1)))
    }

    mutating func retune(cutoff: Double, sampleRate: Double) {
        coefficient = AudioOnePole.coefficient(cutoff: cutoff, sampleRate: sampleRate)
    }

    mutating func lowpass(_ input: Float) -> Float {
        state += coefficient * (input - state)
        return state
    }

    mutating func highpass(_ input: Float) -> Float { input - lowpass(input) }
}

/// A second-order band-pass (RBJ cookbook, 0 dB at the centre) for formants, bell-like bands and the pour sweep.
struct AudioBiquad: Sendable {
    private var b0: Float = 0
    private var b2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0
    private var z1: Float = 0
    private var z2: Float = 0

    init(bandpass frequency: Double, q: Double, sampleRate: Double) {
        retune(bandpass: frequency, q: q, sampleRate: sampleRate)
    }

    /// Moves the band without clearing the filter's memory, so sweeping it never clicks.
    mutating func retune(bandpass frequency: Double, q: Double, sampleRate: Double) {
        let rate = max(sampleRate, 1)
        let hz = min(max(frequency, 20), rate * 0.45)
        let w0 = 2 * Double.pi * hz / rate
        let alpha = sin(w0) / (2 * max(q, 0.1))
        let a0 = 1 + alpha
        b0 = Float(alpha / a0)
        b2 = Float(-alpha / a0)
        a1 = Float(-2 * cos(w0) / a0)
        a2 = Float((1 - alpha) / a0)
    }

    /// Transposed direct form II.
    mutating func process(_ input: Float) -> Float {
        let output = b0 * input + z1
        z1 = a1 * -output + z2
        z2 = b2 * input + a2 * -output
        return output
    }
}

// MARK: - Noise

enum AudioNoiseColor: String, CaseIterable, Sendable {
    /// Equal energy at every frequency: a bright hiss.
    case white
    /// Equal energy per octave: the sound of rain and rooms.
    case pink
    /// Falls 6 dB per octave: a deep rumble with almost nothing up high.
    case brown
}

/// A coloured noise source. Output sits near unit RMS for every colour, so recipes can mix layers by feel.
struct AudioNoiseSource: Sendable {
    let color: AudioNoiseColor
    private var random: AudioRandom
    private let whiteScale: Float
    private let outputScale: Float
    private var slow: AudioOnePole
    private var medium: AudioOnePole
    private var fast: AudioOnePole
    private var brown: AudioOnePole

    /// Gain on the pink filter bank that brings it to unit RMS (measured at 44.1 kHz).
    static let pinkNormalisation: Float = 0.3348

    init(color: AudioNoiseColor, seed: UInt64, stream: UInt64 = 0, sampleRate: Double = 44_100) {
        self.color = color
        random = AudioRandom(seed: seed, stream: stream)
        // Uniform noise has variance 1/3. Scaling by the square root of the rate keeps the spectrum level the
        // same at any sample rate, so a recipe sounds alike at 22 kHz and at 48 kHz.
        whiteScale = Float(3.0.squareRoot() * (max(sampleRate, 1) / 44_100).squareRoot())
        slow = AudioOnePole(cutoff: 16.5, sampleRate: sampleRate)
        medium = AudioOnePole(cutoff: 265, sampleRate: sampleRate)
        fast = AudioOnePole(cutoff: 3_945, sampleRate: sampleRate)
        brown = AudioOnePole(cutoff: 15, sampleRate: sampleRate)
        switch color {
        case .white, .pink:
            outputScale = color == .white ? 1 : AudioNoiseSource.pinkNormalisation
        case .brown:
            // A one-pole low-pass of white noise has variance c / (2 - c); undo it to land on unit RMS.
            let c = brown.coefficient
            let rateScale = Float((max(sampleRate, 1) / 44_100).squareRoot())
            outputScale = ((2 - c) / max(c, 1e-6)).squareRoot() / rateScale
        }
    }

    mutating func next() -> Float {
        let white = random.signed() * whiteScale
        switch color {
        case .white:
            return white
        case .pink:
            // Three low-passes at spread corners plus a little of the raw signal approximate a 1/f slope
            // (Paul Kellet's filter, written in hertz so it holds at other sample rates).
            let sum = 0.1848 * white + 42.14 * slow.lowpass(white) + 8.014 * medium.lowpass(white) + 2.448 * fast.lowpass(white)
            return sum * outputScale
        case .brown:
            return brown.lowpass(white) * outputScale
        }
    }
}

// MARK: - Control signals

/// A smooth random control signal in -1 to 1: it glides between random waypoints, so it never steps. Drives gusts,
/// flicker, murmur swells and drifting formants.
struct AudioWander: Sendable {
    private var random: AudioRandom
    private var from: Float
    private var to: Float
    private var progress: Float = 0
    private var step: Float = 0
    private let shortest: Float
    private let longest: Float
    private let rate: Float

    /// `period` is how long, in seconds, one glide between waypoints takes.
    init(seed: UInt64, stream: UInt64 = 0, period: ClosedRange<Double>, sampleRate: Double) {
        random = AudioRandom(seed: seed, stream: stream)
        from = random.signed()
        to = random.signed()
        shortest = Float(max(period.lowerBound, 1e-3))
        longest = Float(max(period.upperBound, period.lowerBound, 1e-3))
        rate = Float(max(sampleRate, 1))
        step = nextStep()
    }

    private mutating func nextStep() -> Float {
        1 / max(1, random.range(shortest, longest) * rate)
    }

    mutating func next() -> Float {
        progress += step
        if progress >= 1 {
            progress -= 1
            from = to
            to = random.signed()
            step = nextStep()
        }
        let eased = progress * progress * (3 - 2 * progress)
        return from + (to - from) * eased
    }
}

/// Random moments in time (a Poisson process): droplets, crackles, clinks. The rate can change as it runs.
struct AudioEventClock: Sendable {
    private var random: AudioRandom
    private var countdown: Int = 1
    private let sampleRate: Float

    init(seed: UInt64, stream: UInt64 = 0, rate: Float, sampleRate: Double) {
        random = AudioRandom(seed: seed, stream: stream)
        self.sampleRate = Float(max(sampleRate, 1))
        countdown = nextInterval(rate: rate)
    }

    /// True on the sample an event lands, at `rate` events per second on average.
    mutating func tick(rate: Float) -> Bool {
        countdown -= 1
        guard countdown <= 0 else { return false }
        guard rate > 0 else {
            countdown = 2_048
            return false
        }
        countdown = nextInterval(rate: rate)
        return true
    }

    private mutating func nextInterval(rate: Float) -> Int {
        guard rate > 0 else { return 2_048 }
        let u = max(random.unit(), 1e-7)
        let samples = -log(u) / rate * sampleRate
        return max(1, Int(min(samples, 1_000_000_000)))
    }

    /// Draws used to give each event its own pitch, size and place.
    mutating func unit() -> Float { random.unit() }
    mutating func signed() -> Float { random.signed() }
    mutating func range(_ low: Float, _ high: Float) -> Float { random.range(low, high) }
}

// MARK: - Level control

/// A gain that glides to a new value with an ease-in, ease-out curve: fades with no clicks and no sudden slope.
/// A glide lasts exactly the number of samples asked for, so fades are as long as they say they are.
struct AudioGainRamp: Sendable {
    /// Even a "jump" takes this long, because an instant change is a click.
    static let minimumSeconds = 0.01

    private(set) var value: Float
    private var origin: Float
    private(set) var target: Float
    private var position = 1
    private var length = 1

    init(value: Float) {
        let start = AudioGainRamp.clamp(value)
        self.value = start
        origin = start
        target = start
    }

    /// True once the gain has arrived at its target and will not move again until asked.
    var isSettled: Bool { position >= length }

    private static func clamp(_ gain: Float) -> Float {
        gain.isNaN ? 0 : min(1, max(0, gain))
    }

    mutating func ramp(to newTarget: Float, seconds: Double, sampleRate: Double) {
        origin = value
        target = AudioGainRamp.clamp(newTarget)
        let duration = max(AudioGainRamp.minimumSeconds, seconds.isFinite ? seconds : 0)
        length = Int(min(duration * max(sampleRate, 1), 1_000_000_000)) + 1
        position = 0
    }

    /// The gain for the next sample.
    mutating func next() -> Float {
        guard position < length else { return target }
        position += 1
        if position >= length {
            value = target
        } else {
            let progress = Float(position) / Float(length)
            let eased = progress * progress * (3 - 2 * progress)
            value = origin + (target - origin) * eased
        }
        return value
    }
}

/// The ceiling for everything that leaves the synths: about -3 dBFS, so a loud crackle or a cue on top of music
/// never clips. Quiet signals pass untouched; only peaks are bent, smoothly, toward the ceiling.
enum AudioLimiter {
    /// -3 dBFS.
    static let ceiling: Float = 0.7079
    /// Below this level the signal is left exactly as it is.
    static let knee: Float = 0.45

    static func limit(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > knee else { return sample.isNaN ? 0 : sample }
        guard magnitude.isFinite else { return sample.isNaN ? 0 : (sample > 0 ? ceiling : -ceiling) }
        let room = ceiling - knee
        let bent = min(ceiling, knee + room * tanh((magnitude - knee) / room))
        return sample < 0 ? -bent : bent
    }
}

/// Equal-power panning, so a sound keeps its loudness as it moves across the stage.
enum AudioPan {
    /// -1 is hard left, 1 is hard right.
    static func gains(_ pan: Float) -> (left: Float, right: Float) {
        let clamped = pan.isNaN ? 0 : min(1, max(-1, pan))
        let angle = (clamped + 1) * Float.pi / 4
        return (cos(angle), sin(angle))
    }
}

// MARK: - Ringing voices

/// One ringing voice: a decaying resonator that is struck once. Droplets, crackles, bubbles and clinks are all this
/// with different pitch and decay.
struct AudioResonator {
    var y1: Float = 0
    var y2: Float = 0
    var a1: Float = 0
    var a2: Float = 0
    /// The strike, applied to the first sample the voice plays.
    var kick: Float = 0
    var gainLeft: Float = 0
    var gainRight: Float = 0
    /// Samples to wait before the strike (events land at an exact sample inside a block).
    var delay: Int = 0
    /// Samples left before the voice has decayed by about 60 dB and is switched off.
    var remaining: Int = 0
    var isActive: Bool = false
}

/// A fixed set of `AudioResonator`s, allocated once up front so striking one on the audio thread never allocates.
/// If every slot is busy the one closest to the end of its ring is reused.
final class AudioResonatorPool {
    let capacity: Int
    private let voices: UnsafeMutablePointer<AudioResonator>
    private let sampleRate: Float

    init(capacity: Int, sampleRate: Double) {
        self.capacity = max(1, capacity)
        self.sampleRate = Float(max(sampleRate, 1))
        voices = UnsafeMutablePointer<AudioResonator>.allocate(capacity: self.capacity)
        voices.initialize(repeating: AudioResonator(), count: self.capacity)
    }

    deinit {
        voices.deinitialize(count: capacity)
        voices.deallocate()
    }

    /// How many voices are ringing (or waiting to start).
    var activeCount: Int {
        var count = 0
        for index in 0..<capacity where voices[index].isActive { count += 1 }
        return count
    }

    /// Strikes a voice. `decay` is the time, in seconds, for it to fall to a third of its loudness; `delay` is in
    /// samples from the start of the block being rendered.
    func strike(frequency: Float, decay: Float, amplitude: Float, pan: Float, delay: Int = 0) {
        let nyquistLimit = 0.45 * sampleRate
        let hz = min(max(frequency, 20), nyquistLimit)
        let theta = 2 * Float.pi * hz / sampleRate
        let tau = max(decay, 0.0005)
        let radius = exp(-1 / (tau * sampleRate))
        let (left, right) = AudioPan.gains(pan)

        var slot = 0
        var quietest = Int.max
        for index in 0..<capacity {
            if !voices[index].isActive {
                slot = index
                break
            }
            if voices[index].remaining < quietest {
                quietest = voices[index].remaining
                slot = index
            }
        }

        var voice = AudioResonator()
        voice.a1 = 2 * radius * cos(theta)
        voice.a2 = -radius * radius
        // sin(theta) cancels the resonator's own gain, so `amplitude` is roughly the peak of the ring.
        voice.kick = amplitude * sin(theta)
        voice.gainLeft = left
        voice.gainRight = right
        voice.delay = max(0, delay)
        voice.remaining = Int(min(tau * sampleRate * 7, 100_000_000)) + 1
        voice.isActive = true
        voices[slot] = voice
    }

    /// Adds every ringing voice to the buffers.
    func render(addingTo left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        for index in 0..<capacity where voices[index].isActive {
            var voice = voices[index]
            var frame = 0
            while frame < frames {
                if voice.delay > 0 {
                    let skip = min(voice.delay, frames - frame)
                    voice.delay -= skip
                    frame += skip
                    continue
                }
                let output = voice.kick + voice.a1 * voice.y1 + voice.a2 * voice.y2
                voice.kick = 0
                voice.y2 = voice.y1
                voice.y1 = output
                left[frame] += output * voice.gainLeft
                right[frame] += output * voice.gainRight
                voice.remaining -= 1
                if voice.remaining <= 0 {
                    voice.isActive = false
                    break
                }
                frame += 1
            }
            voices[index] = voice
        }
    }
}

// MARK: - A general second-order filter

/// A second-order filter in the cookbook's low-pass, high-pass or band-pass shape (the band-pass peaks at 0 dB), in
/// transposed direct form II. Used where a one-pole is too gentle: the fire's roar, a room's distance, a voice's
/// formants.
struct AudioFilter: Sendable {
    enum Shape: Sendable { case lowpass, highpass, bandpass }

    private var b0: Float = 0
    private var b1: Float = 0
    private var b2: Float = 0
    private var a1: Float = 0
    private var a2: Float = 0
    private var z1: Float = 0
    private var z2: Float = 0

    init(_ shape: Shape, frequency: Double, q: Double = 0.7071, sampleRate: Double) {
        retune(shape, frequency: frequency, q: q, sampleRate: sampleRate)
    }

    mutating func retune(_ shape: Shape, frequency: Double, q: Double, sampleRate: Double) {
        let rate = max(sampleRate, 1)
        let hz = min(max(frequency.isNaN ? 1_000 : frequency, 10), rate * 0.45)
        let w0 = 2 * Double.pi * hz / rate
        let cosine = cos(w0)
        let alpha = sin(w0) / (2 * max(q, 0.1))
        let a0 = 1 + alpha
        let numerator: (Double, Double, Double)
        switch shape {
        case .lowpass: numerator = ((1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2)
        case .highpass: numerator = ((1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2)
        case .bandpass: numerator = (alpha, 0, -alpha)
        }
        b0 = Float(numerator.0 / a0)
        b1 = Float(numerator.1 / a0)
        b2 = Float(numerator.2 / a0)
        a1 = Float(-2 * cosine / a0)
        a2 = Float((1 - alpha) / a0)
    }

    mutating func process(_ input: Float) -> Float {
        let output = b0 * input + z1
        z1 = b1 * input - a1 * output + z2
        z2 = b2 * input - a2 * output
        return output
    }
}

// MARK: - Noise bursts

/// One burst of noise ringing out through a broad band: a crackle, a paper crinkle, a scuff.
struct AudioBurst {
    var random = AudioRandom(seed: 1)
    var level: Float = 0
    var decay: Float = 0
    var filter = AudioFilter(.bandpass, frequency: 1_000, q: 1, sampleRate: 44_100)
    var gainLeft: Float = 0
    var gainRight: Float = 0
    var delay: Int = 0
    var remaining: Int = 0
    var isActive = false
}

/// Short bursts of noise through a broad band-pass, made up front and reused. Unlike `AudioResonatorPool`, nothing
/// here rings at a pitch: a burst is noise whose level falls away in a fraction of a millisecond to a few
/// milliseconds, and the band (Q of about 1) only colours it. That is what a crackle is; a ringing sine is a drip.
/// Each burst draws its noise from its own generator, so the sound is the same however rendering is split into blocks.
final class AudioBurstPool {
    let capacity: Int
    private let voices: UnsafeMutablePointer<AudioBurst>
    private let sampleRate: Double
    private let seed: UInt64
    private let stream: UInt64
    /// Every burst gets its own noise, numbered in the order they were struck (never by the slot it lands in, which
    /// can depend on how rendering was split).
    private var struck: UInt64 = 0

    init(capacity: Int, sampleRate: Double, seed: UInt64, stream: UInt64) {
        self.capacity = max(1, capacity)
        self.sampleRate = max(sampleRate, 1)
        self.seed = seed
        self.stream = stream
        voices = UnsafeMutablePointer<AudioBurst>.allocate(capacity: self.capacity)
        voices.initialize(repeating: AudioBurst(), count: self.capacity)
    }

    deinit {
        voices.deinitialize(count: capacity)
        voices.deallocate()
    }

    var activeCount: Int {
        var count = 0
        for index in 0..<capacity where voices[index].isActive { count += 1 }
        return count
    }

    /// Starts a burst `delay` frames into the next render. `decay` is the noise's time constant in seconds;
    /// `amplitude` is its starting level.
    func strike(frequency: Float, q: Float, decay: Float, amplitude: Float, pan: Float, delay: Int = 0) {
        let tau = Double(max(decay, 0.00005))
        let (left, right) = AudioPan.gains(pan)
        var slot = 0
        var quietest = Int.max
        for index in 0..<capacity {
            if !voices[index].isActive {
                slot = index
                break
            }
            if voices[index].remaining < quietest {
                quietest = voices[index].remaining
                slot = index
            }
        }
        var voice = voices[slot]
        struck &+= 1
        voice.random = AudioRandom(seed: seed &+ stream &* 0x1000_0000, stream: struck)
        voice.level = amplitude
        voice.decay = Float(exp(-1 / (tau * sampleRate)))
        voice.filter = AudioFilter(.bandpass, frequency: Double(frequency), q: Double(q), sampleRate: sampleRate)
        voice.gainLeft = left
        voice.gainRight = right
        voice.delay = max(0, delay)
        // Nine time constants of noise, then a little for the band to settle.
        voice.remaining = Int(min(tau * sampleRate * 9, 10_000_000)) + 64
        voice.isActive = true
        voices[slot] = voice
    }

    func render(addingTo left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        for index in 0..<capacity where voices[index].isActive {
            var voice = voices[index]
            var frame = 0
            while frame < frames {
                if voice.delay > 0 {
                    let skip = min(voice.delay, frames - frame)
                    voice.delay -= skip
                    frame += skip
                    continue
                }
                let excitation = voice.random.signed() * voice.level
                voice.level *= voice.decay
                let output = voice.filter.process(excitation)
                left[frame] += output * voice.gainLeft
                right[frame] += output * voice.gainRight
                voice.remaining -= 1
                if voice.remaining <= 0 {
                    voice.isActive = false
                    break
                }
                frame += 1
            }
            voices[index] = voice
        }
    }
}

// MARK: - Bubbles

/// One bubble: a sine that dies away in a few milliseconds while its pitch rises, as a real bubble's does when it
/// nears the surface.
struct AudioBubble {
    var phase: Float = 0
    var step: Float = 0
    var chirp: Float = 1
    var level: Float = 0
    var decay: Float = 0
    var gainLeft: Float = 0
    var gainRight: Float = 0
    var delay: Int = 0
    var remaining: Int = 0
    var isActive = false
}

/// Bubbles for the kettle, made up front and reused. Short and rising, they read as bubbling where a fixed-pitch ring
/// reads as a drip.
final class AudioBubblePool {
    let capacity: Int
    private let voices: UnsafeMutablePointer<AudioBubble>
    private let sampleRate: Float

    init(capacity: Int, sampleRate: Double) {
        self.capacity = max(1, capacity)
        self.sampleRate = Float(max(sampleRate, 1))
        voices = UnsafeMutablePointer<AudioBubble>.allocate(capacity: self.capacity)
        voices.initialize(repeating: AudioBubble(), count: self.capacity)
    }

    deinit {
        voices.deinitialize(count: capacity)
        voices.deallocate()
    }

    var activeCount: Int {
        var count = 0
        for index in 0..<capacity where voices[index].isActive { count += 1 }
        return count
    }

    /// A bubble at `frequency` that fades with time constant `decay` (seconds) and rises by `rise` (0.3 is 30
    /// percent) over three time constants.
    func strike(frequency: Float, decay: Float, rise: Float, amplitude: Float, pan: Float, delay: Int = 0) {
        let tau = max(decay, 0.0003)
        let hz = min(max(frequency, 40), 0.4 * sampleRate)
        let (left, right) = AudioPan.gains(pan)
        var slot = 0
        var quietest = Int.max
        for index in 0..<capacity {
            if !voices[index].isActive {
                slot = index
                break
            }
            if voices[index].remaining < quietest {
                quietest = voices[index].remaining
                slot = index
            }
        }
        let lifetime = tau * sampleRate * 7
        var voice = AudioBubble()
        voice.step = 2 * Float.pi * hz / sampleRate
        voice.chirp = 1 + max(0, rise) / max(3 * tau * sampleRate, 1)
        voice.level = amplitude
        voice.decay = exp(-1 / (tau * sampleRate))
        voice.gainLeft = left
        voice.gainRight = right
        voice.delay = max(0, delay)
        voice.remaining = Int(min(lifetime, 10_000_000)) + 1
        voice.isActive = true
        voices[slot] = voice
    }

    func render(addingTo left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        let ceilingStep = 2 * Float.pi * 0.45
        for index in 0..<capacity where voices[index].isActive {
            var voice = voices[index]
            var frame = 0
            while frame < frames {
                if voice.delay > 0 {
                    let skip = min(voice.delay, frames - frame)
                    voice.delay -= skip
                    frame += skip
                    continue
                }
                voice.phase += voice.step
                if voice.phase > 2 * Float.pi { voice.phase -= 2 * Float.pi }
                voice.step = min(voice.step * voice.chirp, ceilingStep)
                let output = sin(voice.phase) * voice.level
                voice.level *= voice.decay
                left[frame] += output * voice.gainLeft
                right[frame] += output * voice.gainRight
                voice.remaining -= 1
                if voice.remaining <= 0 {
                    voice.isActive = false
                    break
                }
                frame += 1
            }
            voices[index] = voice
        }
    }
}

// MARK: - A room

/// A small room around the sounds that are meant to be across it (Freeverb's shape: four damped combs into two
/// all-passes per side, the right side a little longer). Fed one mono send, it returns a diffuse stereo tail, so
/// distant voices, pages and footsteps arrive with the room around them instead of dry in the ear. Its memory is made
/// in `init`.
final class AudioRoom {
    private static let combs = [1_116, 1_188, 1_277, 1_356]
    private static let allpasses = [556, 441]
    private static let spread = 23

    private let lengths: [Int]
    private let buffers: UnsafeMutablePointer<Float>
    private let starts: [Int]
    private let total: Int
    private var positions: [Int]
    private var damping: [Float]
    private let feedback: Float
    private let damp: Float

    /// `size` scales the delay lengths (1 is Freeverb's); `feedback` is how long the tail is (0.7 to 0.85);
    /// `damp` how quickly its highs fade.
    init(sampleRate: Double, size: Double, feedback: Float, damp: Float) {
        let scale = max(sampleRate, 8_000) / 44_100 * max(size, 0.2)
        var lengths: [Int] = []
        for side in 0..<2 {
            for delay in AudioRoom.combs { lengths.append(max(1, Int(Double(delay + side * AudioRoom.spread) * scale))) }
        }
        for side in 0..<2 {
            for delay in AudioRoom.allpasses { lengths.append(max(1, Int(Double(delay + side * AudioRoom.spread) * scale))) }
        }
        var starts: [Int] = []
        var offset = 0
        for length in lengths {
            starts.append(offset)
            offset += length
        }
        self.lengths = lengths
        self.starts = starts
        total = offset
        buffers = UnsafeMutablePointer<Float>.allocate(capacity: offset)
        buffers.initialize(repeating: 0, count: offset)
        positions = [Int](repeating: 0, count: lengths.count)
        damping = [Float](repeating: 0, count: 8)
        self.feedback = min(0.95, max(0, feedback))
        self.damp = min(0.95, max(0, damp))
    }

    deinit {
        buffers.deinitialize(count: total)
        buffers.deallocate()
    }

    /// One sample of send in, one stereo sample of room out.
    func process(_ input: Float) -> (left: Float, right: Float) {
        var out: (Float, Float) = (0, 0)
        for side in 0..<2 {
            var sum: Float = 0
            for comb in 0..<4 {
                let line = side * 4 + comb
                let at = starts[line] + positions[line]
                let delayed = buffers[at]
                damping[line] = delayed * (1 - damp) + damping[line] * damp
                buffers[at] = input + damping[line] * feedback
                positions[line] += 1
                if positions[line] >= lengths[line] { positions[line] = 0 }
                sum += delayed
            }
            for pass in 0..<2 {
                let line = 8 + side * 2 + pass
                let at = starts[line] + positions[line]
                let delayed = buffers[at]
                let output = delayed - sum
                buffers[at] = sum + delayed * 0.5
                positions[line] += 1
                if positions[line] >= lengths[line] { positions[line] = 0 }
                sum = output
            }
            if side == 0 { out.0 = sum * 0.25 } else { out.1 = sum * 0.25 }
        }
        return out
    }
}

// MARK: - Scratch space

/// Buffers made once for a voice that mixes in more than one pass, freed with it. (Voices are value types, so they
/// can't free memory themselves.)
final class AudioScratch {
    let capacity: Int
    private let buffers: [UnsafeMutablePointer<Float>]

    init(count: Int, capacity: Int) {
        self.capacity = max(1, capacity)
        var made: [UnsafeMutablePointer<Float>] = []
        for _ in 0..<max(1, count) {
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
            buffer.initialize(repeating: 0, count: self.capacity)
            made.append(buffer)
        }
        buffers = made
    }

    deinit {
        for buffer in buffers {
            buffer.deinitialize(count: capacity)
            buffer.deallocate()
        }
    }

    subscript(index: Int) -> UnsafeMutablePointer<Float> { buffers[index] }
}
