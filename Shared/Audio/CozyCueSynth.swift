import Foundation

/// The little sounds of the tea ritual and the page, made from nothing. Each is a few hundred milliseconds to a couple
/// of seconds long, rendered once into a buffer and played from there.
enum CozyCue: String, CaseIterable, Sendable {
    /// The kettle's switch: a small click and a soft thunk.
    case kettleClick
    /// Water into a cup, rising in pitch as it fills.
    case pour
    /// Two soft bell tones, a rising fourth: the tea is ready.
    case steepReady
    /// A page lifted and let fall.
    case pageTurn
}

/// Cues that belong together, for the tea timer to play without doing its own timing sums.
enum CozyCueSequence {
    struct Step: Hashable, Sendable {
        var cue: CozyCue
        /// Seconds after the sequence starts.
        var delay: TimeInterval
    }

    /// Putting the kettle on and pouring: the click, then the pour once the water has settled.
    static let brewStart: [Step] = [Step(cue: .kettleClick, delay: 0), Step(cue: .pour, delay: 0.55)]

    /// The tea is ready.
    static let ready: [Step] = [Step(cue: .steepReady, delay: 0)]
}

/// Synthesises the cues. Deterministic (the seed only shapes the noise in the click, pour and page), mono, and always
/// finite: every cue starts and ends at exactly zero, so it can be played back to back with anything without a pop.
enum CozyCueSynth {
    /// Length in seconds.
    static func duration(of cue: CozyCue) -> TimeInterval {
        switch cue {
        case .kettleClick: return 0.34
        case .pour: return 2.0
        case .steepReady: return 2.6
        case .pageTurn: return 0.6
        }
    }

    /// The loudest sample, before the player's own volume. Cues are small on purpose.
    static func peak(of cue: CozyCue) -> Float {
        switch cue {
        case .kettleClick: return 0.26
        case .pour: return 0.26
        case .steepReady: return 0.30
        case .pageTurn: return 0.22
        }
    }

    static func render(_ cue: CozyCue, sampleRate: Double = 44_100, seed: UInt64 = 1) -> [Float] {
        let rate = AudioSampleRate.clamped(sampleRate)
        var buffer = CueBuffer(seconds: duration(of: cue), sampleRate: rate)
        switch cue {
        case .kettleClick: kettleClick(&buffer, seed: seed)
        case .pour: pour(&buffer, seed: seed)
        case .steepReady: steepReady(&buffer)
        case .pageTurn: pageTurn(&buffer, seed: seed)
        }
        buffer.finish(peak: peak(of: cue), tail: cue == .steepReady ? 0.2 : 0.05)
        return buffer.samples
    }

    // MARK: Recipes

    private static func kettleClick(_ buffer: inout CueBuffer, seed: UInt64) {
        // The switch: a short, dry tick of plastic. Noise through a broad band, so nothing rings or stings.
        buffer.addBurst(start: 0.003, decay: 0.0008, frequency: 2_200, q: 0.9, amplitude: 1.0, seed: seed, stream: 1)
        // Then the body of the kettle answers with a soft, low knock: mostly noise, with only a breath of pitch.
        buffer.addBurst(start: 0.035, decay: 0.012, frequency: 320, q: 0.8, amplitude: 2.2, seed: seed, stream: 2)
        buffer.addPing(start: 0.035, frequency: 260, decay: 0.012, amplitude: 0.25, attack: 0.002)
    }

    private static func pour(_ buffer: inout CueBuffer, seed: UInt64) {
        let rate = buffer.sampleRate
        let seconds = duration(of: .pour)
        var noise = AudioNoiseSource(color: .white, seed: seed, stream: 3, sampleRate: rate)
        var band = AudioBiquad(bandpass: 520, q: 2.2, sampleRate: rate)
        var rumble = AudioOnePole(cutoff: 380, sampleRate: rate)
        var flow = AudioWander(seed: seed, stream: 4, period: 0.04...0.12, sampleRate: rate)
        for index in buffer.samples.indices {
            let time = Double(index) / rate
            if index % 64 == 0 {
                // The cup fills, so the note of the water climbs.
                let filled = min(1, time / seconds)
                band.retune(bandpass: 520 + 900 * pow(filled, 1.3), q: 2.0, sampleRate: rate)
            }
            let attack = smooth(min(1, time / 0.18))
            let release = smooth(min(1, (seconds - time) / 0.5))
            let turbulence = 0.75 + 0.25 * flow.next()
            let air = noise.next()
            let water = band.process(air) * 2.4 + rumble.lowpass(air) * 0.5
            buffer.samples[index] += water * Float(attack * release) * turbulence
        }
    }

    private static func steepReady(_ buffer: inout CueBuffer) {
        // E5 then A5: a rising fourth, the second softer. Each note is a bell: a fundamental with a slightly detuned
        // twin (a slow shimmer) and a few quickly fading overtones.
        let notes: [(start: Double, frequency: Double, level: Float)] = [(0, 659.25, 1.0), (0.34, 880.0, 0.85)]
        let partials: [(ratio: Double, level: Float, decay: Double)] = [
            (1.0, 1.0, 0.7), (1.004, 0.45, 0.65), (2.0, 0.18, 0.4), (2.99, 0.05, 0.25), (4.16, 0.015, 0.15),
        ]
        for note in notes {
            for partial in partials {
                buffer.addPing(
                    start: note.start,
                    frequency: note.frequency * partial.ratio,
                    decay: partial.decay,
                    amplitude: note.level * partial.level,
                    attack: 0.012
                )
            }
        }
    }

    private static func pageTurn(_ buffer: inout CueBuffer, seed: UInt64) {
        let rate = buffer.sampleRate
        var lift = AudioNoiseSource(color: .white, seed: seed, stream: 5, sampleRate: rate)
        var liftBand = AudioBiquad(bandpass: 1_200, q: 1.0, sampleRate: rate)
        var swish = AudioNoiseSource(color: .white, seed: seed, stream: 6, sampleRate: rate)
        var swishBand = AudioBiquad(bandpass: 2_600, q: 0.8, sampleRate: rate)
        // Paper heard from a chair, not with an ear to it: the top taken off.
        var soften = AudioFilter(.lowpass, frequency: 5_000, sampleRate: rate)
        var crinkle = AudioEventClock(seed: seed, stream: 7, rate: 70, sampleRate: rate)
        var crinkleLevel: Float = 0
        let crinkleDecay = Float(exp(-1 / (0.006 * rate)))

        for index in buffer.samples.indices {
            let time = Double(index) / rate
            // The lift: a quick breath of paper as the page leaves the stack.
            var sample: Float = 0
            if time < 0.14 {
                let u = time / 0.14
                let bump = 4 * u * (1 - u)
                sample += liftBand.process(lift.next()) * Float(bump * bump) * 1.2
            }
            // The swish: the page travels across, its sound sweeping down in pitch, crinkling as it goes.
            if crinkle.tick(rate: 70) { crinkleLevel += 0.4 + 0.6 * crinkle.unit() }
            crinkleLevel *= crinkleDecay
            if time >= 0.10 && time < 0.38 {
                let u = (time - 0.10) / 0.28
                if index % 32 == 0 {
                    swishBand.retune(bandpass: 2_600 - 1_500 * u, q: 0.8, sampleRate: rate)
                }
                let bump = 4 * u * (1 - u)
                sample += swishBand.process(swish.next()) * Float(bump * bump) * (0.45 + 0.6 * min(crinkleLevel, 1)) * 1.6
            }
            buffer.samples[index] += soften.process(sample)
        }
        // The settle: the page lands with a soft, low pat.
        buffer.addBurst(start: 0.40, decay: 0.006, frequency: 260, q: 0.8, amplitude: 0.5, seed: seed, stream: 8)
    }

    private static func smooth(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}

/// A mono buffer being built up from layers.
private struct CueBuffer {
    var samples: [Float]
    let sampleRate: Double

    init(seconds: TimeInterval, sampleRate: Double) {
        self.sampleRate = sampleRate
        samples = [Float](repeating: 0, count: max(1, Int(seconds * sampleRate)))
    }

    /// A struck, ringing tone: a sine that fades exponentially (`decay` is the time to fall to a third), with a
    /// very short attack so the start is never a click.
    mutating func addPing(start: Double, frequency: Double, decay: Double, amplitude: Float, attack: Double = 0.0006) {
        let first = Int(start * sampleRate)
        guard first < samples.count, decay > 0 else { return }
        let last = min(samples.count, first + Int(decay * 8 * sampleRate) + 1)
        let step = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        for index in first..<last {
            let t = Double(index - first) / sampleRate
            let envelope = exp(-t / decay) * min(1, t / attack)
            samples[index] += amplitude * Float(envelope * sin(step * Double(index - first)))
        }
    }

    /// Noise that dies away with time constant `decay`, through a broad band at `frequency`: a tick, a knock or a pat
    /// that has a colour but no pitch.
    mutating func addBurst(start: Double, decay: Double, frequency: Double, q: Double, amplitude: Float, seed: UInt64, stream: UInt64) {
        let first = Int(start * sampleRate)
        let count = Int(decay * 9 * sampleRate) + 64
        guard first < samples.count, decay > 0 else { return }
        var random = AudioRandom(seed: seed, stream: stream)
        var band = AudioFilter(.bandpass, frequency: frequency, q: q, sampleRate: sampleRate)
        let fall = Float(exp(-1 / (decay * sampleRate)))
        var level = amplitude
        for offset in 0..<count where first + offset < samples.count {
            samples[first + offset] += band.process(random.signed() * level)
            level *= fall
        }
    }

    /// A short burst of noise that fades out, for the dry edge of a click.
    mutating func addNoise(start: Double, seconds: Double, amplitude: Float, seed: UInt64, stream: UInt64) {
        let first = Int(start * sampleRate)
        let count = Int(seconds * sampleRate)
        guard first < samples.count, count > 0 else { return }
        var random = AudioRandom(seed: seed, stream: stream)
        for offset in 0..<count where first + offset < samples.count {
            let fade = 1 - Float(offset) / Float(count)
            samples[first + offset] += random.signed() * amplitude * fade * fade
        }
    }

    /// Fades the first few milliseconds in and the last `tail` seconds out, scales so the loudest sample is `peak`,
    /// and limits. The first and last samples come out as exactly zero.
    mutating func finish(peak: Float, tail: Double) {
        let headCount = min(samples.count, max(2, Int(0.002 * sampleRate)))
        let tailCount = min(samples.count, max(2, Int(tail * sampleRate)))
        var loudest: Float = 0
        for index in samples.indices {
            var level: Float = 1
            if index < headCount {
                let w = Float(index) / Float(headCount)
                level *= w * w * (3 - 2 * w)
            }
            let fromEnd = samples.count - 1 - index
            if fromEnd < tailCount {
                let w = Float(fromEnd) / Float(tailCount)
                level *= w * w * (3 - 2 * w)
            }
            samples[index] *= level
            loudest = max(loudest, abs(samples[index]))
        }
        let gain = loudest > 1e-9 ? peak / loudest : 0
        for index in samples.indices { samples[index] = AudioLimiter.limit(samples[index] * gain) }
    }
}
