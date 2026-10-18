import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

// MARK: - Helpers

private func audioRMS(_ samples: ArraySlice<Float>) -> Double {
    guard !samples.isEmpty else { return 0 }
    var sum = 0.0
    for index in samples.indices {
        let x = Double(samples[index])
        sum += x * x
    }
    return (sum / Double(samples.count)).squareRoot()
}

private func audioRMS(_ samples: [Float]) -> Double { audioRMS(samples[...]) }

/// RMS over both channels together.
private func audioRMS(_ left: [Float], _ right: [Float]) -> Double {
    let count = left.count + right.count
    guard count > 0 else { return 0 }
    var sum = 0.0
    for index in left.indices { sum += Double(left[index]) * Double(left[index]) }
    for index in right.indices { sum += Double(right[index]) * Double(right[index]) }
    return (sum / Double(count)).squareRoot()
}

private func audioPeak(_ samples: [Float]) -> Float {
    samples.reduce(0) { max($0, abs($1)) }
}

private func audioDecibels(_ linear: Double) -> Double { 20 * log10(max(linear, 1e-12)) }

private func audioMaxStep(_ samples: [Float]) -> Float {
    var worst: Float = 0
    for index in samples.indices.dropFirst() { worst = max(worst, abs(samples[index] - samples[index - 1])) }
    return worst
}

private func audioMaxDifference(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count else { return .infinity }
    var worst: Float = 0
    for index in a.indices { worst = max(worst, abs(a[index] - b[index])) }
    return worst
}

private func audioAllFinite(_ samples: [Float]) -> Bool { samples.allSatisfy { $0.isFinite } }

/// Share of the energy above `cutoff`, measured with the simplest possible filter: a one-pole low-pass subtracted
/// from the signal.
private func audioHighShare(_ samples: [Float], cutoff: Double, sampleRate: Double) -> Double {
    let a = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
    var low = 0.0
    var high = 0.0
    var total = 0.0
    for sample in samples {
        let x = Double(sample)
        low += a * (x - low)
        high += (x - low) * (x - low)
        total += x * x
    }
    return high / max(total, 1e-12)
}

private func audioLowShare(_ samples: [Float], cutoff: Double, sampleRate: Double) -> Double {
    let a = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
    var low = 0.0
    var lowEnergy = 0.0
    var total = 0.0
    for sample in samples {
        let x = Double(sample)
        low += a * (x - low)
        lowEnergy += low * low
        total += x * x
    }
    return lowEnergy / max(total, 1e-12)
}

/// Strength of one frequency in a stretch of samples (the Goertzel algorithm).
private func audioTone(_ samples: ArraySlice<Float>, frequency: Double, sampleRate: Double) -> Double {
    let coefficient = 2 * cos(2 * Double.pi * frequency / sampleRate)
    var s1 = 0.0
    var s2 = 0.0
    for sample in samples {
        let s = Double(sample) + coefficient * s1 - s2
        s2 = s1
        s1 = s
    }
    return (s1 * s1 + s2 * s2 - coefficient * s1 * s2).squareRoot() / Double(max(samples.count, 1))
}

private func audioZeroCrossings(_ samples: ArraySlice<Float>) -> Int {
    var count = 0
    var previous: Float = 0
    for sample in samples {
        if (sample > 0) != (previous > 0) { count += 1 }
        previous = sample
    }
    return count
}

private func audioRender(
    _ recipe: AmbienceRecipe,
    seconds: Double,
    sampleRate: Double = 44_100,
    seed: UInt64 = 1,
    block: Int = 512,
    initialGain: Float = 1,
    configure: ((AmbienceSynth) -> Void)? = nil
) -> (left: [Float], right: [Float]) {
    let synth = AmbienceSynth(recipe: recipe, sampleRate: sampleRate, seed: seed, initialGain: initialGain)
    configure?(synth)
    let frames = Int(seconds * sampleRate)
    var left = [Float](repeating: 0, count: frames)
    var right = [Float](repeating: 0, count: frames)
    left.withUnsafeMutableBufferPointer { l in
        right.withUnsafeMutableBufferPointer { r in
            guard let leftBase = l.baseAddress, let rightBase = r.baseAddress else { return }
            var done = 0
            while done < frames {
                let count = min(block, frames - done)
                synth.render(left: leftBase + done, right: rightBase + done, frames: count)
                done += count
            }
        }
    }
    return (left, right)
}

private func audioNoise(_ color: AudioNoiseColor, count: Int, sampleRate: Double = 44_100, seed: UInt64 = 5) -> [Float] {
    var source = AudioNoiseSource(color: color, seed: seed, sampleRate: sampleRate)
    return (0..<count).map { _ in source.next() }
}

// MARK: - Building blocks

struct AudioPrimitiveTests {
    @Test func randomIsDeterministicAndWellSpread() {
        var a = AudioRandom(seed: 42)
        var b = AudioRandom(seed: 42)
        var other = AudioRandom(seed: 43)
        var split = AudioRandom(seed: 42, stream: 1)
        var same = 0
        var sum = 0.0
        for _ in 0..<20_000 {
            let x = a.signed()
            #expect(x == b.signed())
            #expect(x >= -1 && x < 1)
            if x == other.signed() { same += 1 }
            _ = split.unit()
            sum += Double(x)
        }
        #expect(same < 10)
        #expect(abs(sum / 20_000) < 0.02)

        var first = AudioRandom(seed: 42)
        var second = AudioRandom(seed: 42, stream: 1)
        #expect((0..<8).map { _ in first.unit() } != (0..<8).map { _ in second.unit() })
        for _ in 0..<5_000 {
            let u = first.unit()
            #expect(u >= 0 && u < 1)
        }
    }

    @Test func seedZeroDoesNotStick() {
        var random = AudioRandom(seed: 0)
        let values = Set((0..<64).map { _ in random.unit() })
        #expect(values.count > 60)
    }

    @Test func noiseColoursAreFiniteAndNearUnitLevel() {
        for color in AudioNoiseColor.allCases {
            for rate in [22_050.0, 44_100.0, 48_000.0] {
                let samples = audioNoise(color, count: 120_000, sampleRate: rate)
                #expect(audioAllFinite(samples), "\(color) at \(rate)")
                let rms = audioRMS(samples)
                switch color {
                case .white:
                    // White noise keeps its level per hertz, so it is quieter when there are fewer hertz to fill.
                    let expected = (rate / 44_100).squareRoot()
                    #expect(abs(rms / expected - 1) < 0.05, "white at \(rate): \(rms)")
                case .pink:
                    #expect(rms > 0.8 && rms < 1.2, "pink at \(rate): \(rms)")
                case .brown:
                    #expect(rms > 0.75 && rms < 1.3, "brown at \(rate): \(rms)")
                }
            }
        }
    }

    @Test func brownNoiseHasLessHighFrequencyEnergyThanPinkThanWhite() {
        let rate = 44_100.0
        let white = audioNoise(.white, count: 200_000)
        let pink = audioNoise(.pink, count: 200_000)
        let brown = audioNoise(.brown, count: 200_000)

        // All three are scaled to a similar RMS, so shares of energy compare fairly.
        let high = [white, pink, brown].map { audioHighShare($0, cutoff: 4_000, sampleRate: rate) }
        #expect(high[0] > 0.3, "white \(high[0])")
        #expect(high[1] < high[0] / 2, "pink \(high[1])")
        #expect(high[2] < high[1] / 10, "brown \(high[2])")
        #expect(high[2] < 0.01, "brown \(high[2])")

        let low = [white, pink, brown].map { audioLowShare($0, cutoff: 200, sampleRate: rate) }
        #expect(low[0] < low[1])
        #expect(low[1] < low[2])
        #expect(low[2] > 0.85, "brown keeps its energy low: \(low[2])")
    }

    @Test func panKeepsEqualPower() {
        for step in -10...10 {
            let pan = Float(step) / 10
            let gains = AudioPan.gains(pan)
            #expect(abs(gains.left * gains.left + gains.right * gains.right - 1) < 1e-5)
        }
        #expect(AudioPan.gains(-1).right < 1e-6)
        #expect(AudioPan.gains(1).left < 1e-6)
        #expect(AudioPan.gains(.nan).left == AudioPan.gains(0).left)
        #expect(AudioPan.gains(40).right == AudioPan.gains(1).right)
    }

    @Test func gainRampFadesInAndOutWithoutSteps() {
        let rate = 44_100.0
        let count = Int(0.5 * rate)
        var ramp = AudioGainRamp(value: 0)
        ramp.ramp(to: 1, seconds: 0.5, sampleRate: rate)
        var values: [Float] = []
        for _ in 0..<(count + 10) { values.append(ramp.next()) }

        #expect(values[0] >= 0 && values[0] < 0.001)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(values.last == 1)
        #expect(ramp.isSettled && ramp.value == 1)
        // An ease-in, ease-out curve never moves faster than 1.5 times the straight line.
        #expect(audioMaxStep(values) <= 1.5 / Float(count) + 1e-6)

        ramp.ramp(to: 0, seconds: 0.5, sampleRate: rate)
        var down: [Float] = []
        for _ in 0..<(count + 10) { down.append(ramp.next()) }
        #expect(down.last == 0)
        #expect(zip(down, down.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(audioMaxStep(down) <= 1.5 / Float(count) + 1e-6)
    }

    @Test func gainRampRetargetsMidFadeWithoutAJump() {
        let rate = 44_100.0
        var ramp = AudioGainRamp(value: 0)
        ramp.ramp(to: 1, seconds: 1, sampleRate: rate)
        var before: Float = 0
        for _ in 0..<20_000 { before = ramp.next() }
        ramp.ramp(to: 0.2, seconds: 0.25, sampleRate: rate)
        let after = ramp.next()
        #expect(abs(after - before) < 0.01)
        var last = after
        var worst: Float = 0
        for _ in 0..<20_000 {
            let value = ramp.next()
            worst = max(worst, abs(value - last))
            last = value
        }
        #expect(last == 0.2)
        #expect(worst < 0.001)
    }

    @Test func gainRampNeverJumpsAndClampsItsTarget() {
        let rate = 44_100.0
        var instant = AudioGainRamp(value: 0)
        instant.ramp(to: 1, seconds: 0, sampleRate: rate)
        var values: [Float] = []
        for _ in 0..<2_000 { values.append(instant.next()) }
        // Even "now" takes the minimum ramp, so it is not a click.
        let minimumSamples = Float(AudioGainRamp.minimumSeconds * rate)
        #expect(audioMaxStep(values) <= 1.5 / minimumSamples + 1e-6)
        #expect(values.last == 1)

        var wild = AudioGainRamp(value: 0.5)
        wild.ramp(to: .nan, seconds: .infinity, sampleRate: rate)
        for _ in 0..<5_000 { _ = wild.next() }
        #expect(wild.value == 0)
        wild.ramp(to: 9, seconds: -3, sampleRate: rate)
        for _ in 0..<5_000 { _ = wild.next() }
        #expect(wild.value == 1)
        #expect(AudioGainRamp(value: 7).value == 1)
        #expect(AudioGainRamp(value: .nan).value == 0)
    }

    @Test func limiterNeverPassesTheCeiling() {
        let ceilingDecibels = audioDecibels(Double(AudioLimiter.ceiling))
        #expect(ceilingDecibels > -3.1 && ceilingDecibels < -2.9)

        var previous: Float = -10
        var x: Float = -50
        while x <= 50 {
            let y = AudioLimiter.limit(x)
            #expect(abs(y) <= AudioLimiter.ceiling)
            #expect(AudioLimiter.limit(-x) == -y)
            if abs(x) <= AudioLimiter.knee { #expect(y == x) }
            if x > -50 { #expect(y >= previous) }
            previous = y
            x += 0.013
        }
        #expect(AudioLimiter.limit(.infinity) == AudioLimiter.ceiling)
        #expect(AudioLimiter.limit(-.infinity) == -AudioLimiter.ceiling)
        #expect(AudioLimiter.limit(.greatestFiniteMagnitude) == AudioLimiter.ceiling)
        #expect(AudioLimiter.limit(.nan) == 0)
        #expect(AudioLimiter.limit(0) == 0)
        // The bend is smooth where the knee starts: no kink for the ear to find.
        let below = AudioLimiter.limit(AudioLimiter.knee - 0.001)
        let above = AudioLimiter.limit(AudioLimiter.knee + 0.001)
        #expect(abs((above - below) - 0.002) < 0.0001)
    }

    @Test func eventClockFollowsItsRate() {
        let rate = 8_000.0
        var clock = AudioEventClock(seed: 3, rate: 20, sampleRate: rate)
        var events = 0
        for _ in 0..<Int(300 * rate) where clock.tick(rate: 20) { events += 1 }
        // 20 per second for 300 seconds is 6000 on average (a standard deviation of about 77).
        #expect(events > 5_500 && events < 6_500, "\(events)")

        var silent = AudioEventClock(seed: 3, rate: 0, sampleRate: rate)
        var fired = 0
        for _ in 0..<100_000 where silent.tick(rate: 0) { fired += 1 }
        #expect(fired == 0)

        // A rate that rises later is honoured once the clock next reschedules.
        var late = AudioEventClock(seed: 3, rate: 0, sampleRate: rate)
        var count = 0
        for _ in 0..<Int(20 * rate) where late.tick(rate: 50) { count += 1 }
        #expect(count > 500)

        var a = AudioEventClock(seed: 9, rate: 5, sampleRate: rate)
        var b = AudioEventClock(seed: 9, rate: 5, sampleRate: rate)
        for _ in 0..<50_000 { #expect(a.tick(rate: 5) == b.tick(rate: 5)) }
    }

    @Test func wanderStaysInRangeAndMovesSmoothly() {
        let rate = 44_100.0
        var wander = AudioWander(seed: 11, period: 0.5...1.0, sampleRate: rate)
        var values: [Float] = []
        for _ in 0..<200_000 { values.append(wander.next()) }
        #expect(values.allSatisfy { $0 >= -1 && $0 <= 1 })
        // Smoothstep between two points in [-1, 1] over at least half a second.
        #expect(audioMaxStep(values) <= 3 / Float(0.5 * rate) + 1e-6)
        #expect((values.max() ?? 0) - (values.min() ?? 0) > 0.8)

        var again = AudioWander(seed: 11, period: 0.5...1.0, sampleRate: rate)
        #expect((0..<1_000).map { _ in again.next() } == Array(values.prefix(1_000)))
    }

    @Test func resonatorPoolRingsThenGoesQuiet() {
        let rate = 44_100.0
        let pool = AudioResonatorPool(capacity: 2, sampleRate: rate)
        let frames = 4_410
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        pool.strike(frequency: 1_000, decay: 0.01, amplitude: 1, pan: -1, delay: 100)
        #expect(pool.activeCount == 1)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                if let lb = l.baseAddress, let rb = r.baseAddress { pool.render(addingTo: lb, rb, frames: frames) }
            }
        }
        #expect(left[0..<100].allSatisfy { $0 == 0 })
        #expect(audioPeak(left) > 0.3 && audioPeak(left) < 1.2)
        #expect(audioPeak(right) < 1e-5)
        #expect(left.suffix(500).allSatisfy { $0 == 0 })
        #expect(pool.activeCount == 0)
        #expect(audioAllFinite(left))

        // A full pool reuses a voice rather than growing.
        for index in 0..<6 { pool.strike(frequency: 500 + Float(index) * 100, decay: 0.05, amplitude: 0.5, pan: 0) }
        #expect(pool.activeCount == 2)
    }

    @Test func delaysCarryAcrossBlocks() {
        let rate = 44_100.0
        let oneShot = AudioResonatorPool(capacity: 1, sampleRate: rate)
        let split = AudioResonatorPool(capacity: 1, sampleRate: rate)
        let frames = 3_000
        var whole = [Float](repeating: 0, count: frames)
        var scrap = [Float](repeating: 0, count: frames)
        var pieces = [Float](repeating: 0, count: frames)
        oneShot.strike(frequency: 2_000, decay: 0.004, amplitude: 1, pan: -1, delay: 1_300)
        split.strike(frequency: 2_000, decay: 0.004, amplitude: 1, pan: -1, delay: 1_300)
        whole.withUnsafeMutableBufferPointer { w in
            scrap.withUnsafeMutableBufferPointer { s in
                if let wb = w.baseAddress, let sb = s.baseAddress { oneShot.render(addingTo: wb, sb, frames: frames) }
            }
        }
        pieces.withUnsafeMutableBufferPointer { p in
            scrap.withUnsafeMutableBufferPointer { s in
                guard let pb = p.baseAddress, let sb = s.baseAddress else { return }
                for start in stride(from: 0, to: frames, by: 500) { split.render(addingTo: pb + start, sb + start, frames: 500) }
            }
        }
        #expect(whole == pieces)
        #expect(whole[0..<1_300].allSatisfy { $0 == 0 })
        #expect(audioPeak(whole) > 0.2)
    }

    @Test func bandpassPassesItsCentreAndStaysStable() {
        let rate = 44_100.0
        var filter = AudioBiquad(bandpass: 1_000, q: 4, sampleRate: rate)
        func response(at frequency: Double) -> Double {
            filter = AudioBiquad(bandpass: 1_000, q: 4, sampleRate: rate)
            let tone = (0..<20_000).map { Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
            let out = tone.map { filter.process($0) }
            return audioRMS(out.suffix(10_000)) / audioRMS(tone.suffix(10_000))
        }
        #expect(abs(response(at: 1_000) - 1) < 0.05)
        #expect(response(at: 500) < 0.4)
        #expect(response(at: 2_000) < 0.4)

        // Sweeping the centre while it runs must not blow up or leave NaN behind.
        var noise = AudioRandom(seed: 8)
        var swept = AudioBiquad(bandpass: 300, q: 5, sampleRate: rate)
        var finite = true
        for index in 0..<100_000 {
            if index % 64 == 0 { swept.retune(bandpass: 300 + Double(index % 7_000), q: 5, sampleRate: rate) }
            if !swept.process(noise.signed()).isFinite { finite = false }
        }
        #expect(finite)
    }

    @Test func onePoleSmoothsAndCoefficientsAreSafe() {
        let rate = 44_100.0
        var low = AudioOnePole(cutoff: 100, sampleRate: rate)
        var last: Float = 0
        for _ in 0..<44_100 { last = low.lowpass(1) }
        #expect(abs(last - 1) < 1e-4)
        // Cutoffs outside the useful range are pulled in rather than producing an unstable filter.
        for cutoff in [-5.0, 0, 1e9, .infinity] {
            let coefficient = AudioOnePole(cutoff: cutoff, sampleRate: rate).coefficient
            #expect(coefficient > 0 && coefficient < 1)
        }
    }
}

// MARK: - Ambience

struct AmbienceSynthTests {
    @Test func recipeIDsAreTheSharedCatalogIDs() {
        #expect(AmbienceRecipe.allCases.map(\.rawValue) == ["rain", "fireplace", "kettle", "cafe", "library"])
        #expect(AmbienceRecipe(id: "rain") == .rain)
        #expect(AmbienceRecipe(id: "library") == .library)
        #expect(AmbienceRecipe(id: "none") == nil)
        #expect(AmbienceRecipe(id: nil) == nil)
        #expect(AmbienceRecipe(id: "") == nil)
        #expect(AmbienceRecipe(id: "Rain") == nil)
        for recipe in AmbienceRecipe.allCases {
            #expect(recipe.targetLevel < -12 && recipe.targetLevel > -45)
            #expect(recipe.targetRMS > 0 && recipe.targetRMS < AudioLimiter.ceiling / 4)
            #expect(recipe.rawToTarget > 0)
        }
        #expect(AmbienceRecipe.library.targetLevel == AmbienceRecipe.allCases.map(\.targetLevel).min())
    }

    @Test(arguments: AmbienceRecipe.allCases)
    func thirtySecondsStayFiniteUnderTheCeilingAndOnTarget(recipe: AmbienceRecipe) {
        let rate = 44_100.0
        let (left, right) = audioRender(recipe, seconds: 30, sampleRate: rate, seed: 7)
        #expect(left.count == Int(30 * rate))
        #expect(audioAllFinite(left) && audioAllFinite(right), "\(recipe)")

        let peak = max(audioPeak(left), audioPeak(right))
        #expect(peak <= AudioLimiter.ceiling, "\(recipe) peak \(peak)")
        #expect(peak < 1)
        #expect(peak > recipe.targetRMS, "\(recipe) is not flat: peak \(peak)")

        let rms = audioRMS(left, right)
        let offTarget = audioDecibels(rms) - recipe.targetLevel
        #expect(abs(offTarget) < 1.5, "\(recipe) is \(offTarget) dB from its target")

        // No stuck DC offset, and the two ears hear different things.
        #expect(abs(left.reduce(0.0) { $0 + Double($1) } / Double(left.count)) < 0.01)
        #expect(left != right)

        // Never dead air: every two-second stretch has sound, and none is wildly louder than the rest.
        let window = Int(2 * rate)
        for start in stride(from: 0, to: left.count - window, by: window) {
            let local = audioRMS(left[start..<(start + window)])
            #expect(local > Double(recipe.targetRMS) * 0.3 && local < Double(recipe.targetRMS) * 3, "\(recipe) at \(start)")
        }

        // Each recipe sounds like itself: where its energy sits, and how peaky it is.
        let bright = audioHighShare(left, cutoff: 3_000, sampleRate: rate)
        let deep = audioLowShare(left, cutoff: 300, sampleRate: rate)
        let crest = Double(audioPeak(left)) / max(audioRMS(left), 1e-9)
        switch recipe {
        case .rain:
            // Bright patter over a wash; no deep rumble.
            #expect(bright > 0.15 && deep < 0.4, "rain bright \(bright) deep \(deep)")
        case .fireplace:
            // A deep rumble with pops and crackles standing out of it.
            #expect(deep > 0.6 && bright < 0.05 && crest > 3.5, "fire deep \(deep) bright \(bright) crest \(crest)")
        case .kettle:
            // A mid-low hush with a steady level.
            #expect(deep > 0.2 && deep < 0.7 && crest < 6, "kettle deep \(deep) crest \(crest)")
        case .cafe:
            // A murmur: mid-range, not bright, not rumbling.
            #expect(bright < 0.25 && deep < 0.4, "cafe bright \(bright) deep \(deep)")
        case .library:
            // Nearly silent, and what there is sits low.
            #expect(deep > 0.6 && audioRMS(left) < 0.04, "library deep \(deep)")
        }
    }

    @Test(arguments: AmbienceRecipe.allCases)
    func levelHoldsAcrossSeeds(recipe: AmbienceRecipe) {
        for seed in [2, 3] as [UInt64] {
            let (left, right) = audioRender(recipe, seconds: 8, seed: seed)
            let offTarget = audioDecibels(audioRMS(left, right)) - recipe.targetLevel
            #expect(abs(offTarget) < 2.2, "\(recipe) seed \(seed): \(offTarget) dB")
        }
    }

    @Test(arguments: AmbienceRecipe.allCases)
    func otherSampleRatesStayFiniteAndRoughlyOnTarget(recipe: AmbienceRecipe) {
        for rate in [22_050.0, 48_000.0] {
            let (left, right) = audioRender(recipe, seconds: 5, sampleRate: rate, seed: 5)
            #expect(left.count == Int(5 * rate))
            #expect(audioAllFinite(left) && audioAllFinite(right))
            #expect(max(audioPeak(left), audioPeak(right)) <= AudioLimiter.ceiling)
            let offTarget = audioDecibels(audioRMS(left, right)) - recipe.targetLevel
            #expect(abs(offTarget) < 3, "\(recipe) at \(rate): \(offTarget) dB")
        }
    }

    @Test(arguments: AmbienceRecipe.allCases)
    func theSameSeedGivesTheSameSoundWhateverTheBlockSize(recipe: AmbienceRecipe) {
        let reference = audioRender(recipe, seconds: 2, seed: 21, block: 512)
        let again = audioRender(recipe, seconds: 2, seed: 21, block: 512)
        #expect(reference.left == again.left && reference.right == again.right)
        for block in [37, 4_096] {
            let other = audioRender(recipe, seconds: 2, seed: 21, block: block)
            // Only the order in which overlapping drops are added together can differ, which is rounding noise.
            let worst = max(audioMaxDifference(reference.left, other.left), audioMaxDifference(reference.right, other.right))
            #expect(worst < 1e-5, "\(recipe) with blocks of \(block) differs by \(worst)")
        }
        let different = audioRender(recipe, seconds: 1, seed: 22)
        #expect(Array(reference.left.prefix(different.left.count)) != different.left)
        #expect(!reference.left.allSatisfy { $0 == 0 })
    }

    @Test func seedZeroWorksAndDiffersFromSeedOne() {
        let zero = audioRender(.rain, seconds: 1, seed: 0)
        let one = audioRender(.rain, seconds: 1, seed: 1)
        #expect(zero.left != one.left)
        #expect(audioRMS(zero.left) > 0.01)
    }

    @Test func interleavedAndMonoRendersMatchTheStereoOnes() {
        for recipe in AmbienceRecipe.allCases {
            let frames = 5_000
            let planar = audioRender(recipe, seconds: Double(frames) / 44_100, seed: 4)
            let count = planar.left.count

            let interleavedSynth = AmbienceSynth(recipe: recipe, seed: 4)
            var interleaved = [Float](repeating: 0, count: count * 2)
            interleaved.withUnsafeMutableBufferPointer { buffer in
                if let base = buffer.baseAddress { interleavedSynth.render(into: base, frames: count, channels: 2) }
            }
            for index in stride(from: 0, to: count, by: 97) {
                #expect(interleaved[index * 2] == planar.left[index])
                #expect(interleaved[index * 2 + 1] == planar.right[index])
            }

            // A mono mix of two different ears has about the loudness of either ear.
            let monoSynth = AmbienceSynth(recipe: recipe, seed: 4)
            var mono = [Float](repeating: 0, count: 4 * 44_100)
            mono.withUnsafeMutableBufferPointer { buffer in
                if let base = buffer.baseAddress { monoSynth.render(left: base, right: nil, frames: buffer.count) }
            }
            let stereo = audioRender(recipe, seconds: 4, seed: 4)
            let difference = audioDecibels(audioRMS(mono)) - audioDecibels(audioRMS(stereo.left, stereo.right))
            #expect(abs(difference) < 2.5, "\(recipe) mono is \(difference) dB from stereo")
            #expect(audioPeak(mono) <= AudioLimiter.ceiling)
            #expect(audioAllFinite(mono))
        }
    }

    @Test func fadeInStartsSilentArrivesAtFullGainAndHasNoClicks() {
        for recipe in [AmbienceRecipe.library, .kettle] {
            let rate = 44_100.0
            let fadeSeconds = 1.5
            let faded = audioRender(recipe, seconds: 2.5, seed: 6, initialGain: 0) { $0.fade(to: 1, over: fadeSeconds) }
            let plain = audioRender(recipe, seconds: 2.5, seed: 6)

            #expect(abs(faded.left[0]) < 0.001, "\(recipe) starts at silence")
            #expect(audioRMS(faded.left[0..<2_000]) < audioRMS(plain.left[0..<2_000]) * 0.05)
            // After the fade the sound is exactly the unfaded sound.
            let settled = Int(fadeSeconds * rate) + 10
            #expect(faded.left[settled...] == plain.left[settled...])

            // Fading by a smooth gain adds no step bigger than the gain's own slope times the signal.
            let n = Float(fadeSeconds * rate)
            let allowed = audioMaxStep(plain.left) * 1.05 + (1.5 / n) * audioPeak(plain.left) + 1e-5
            #expect(audioMaxStep(faded.left) <= allowed, "\(recipe) clicks while fading in")
        }
    }

    @Test func fadeOutEndsInExactSilenceAndCanComeBack() {
        let rate = 44_100.0
        let half = Int(rate / 2)
        let synth = AmbienceSynth(recipe: .cafe, seed: 2)
        let steady = AmbienceSynth(recipe: .cafe, seed: 2)
        func renderHalfSecond(_ source: AmbienceSynth) -> [Float] {
            var buffer = [Float](repeating: 0, count: half)
            buffer.withUnsafeMutableBufferPointer { storage in
                if let base = storage.baseAddress { source.render(left: base, right: nil, frames: half) }
            }
            return buffer
        }
        // A twin that never fades shows how big the steps in the sound itself are.
        let reference = (0..<4).map { _ in renderHalfSecond(steady) }
        let referenceStep = reference.map(audioMaxStep).max() ?? 0
        let referencePeak = reference.map(audioPeak).max() ?? 0

        _ = renderHalfSecond(synth)
        #expect(synth.currentGain == 1 && !synth.isSilent)
        synth.fade(to: 0, over: 0.75)
        let during = renderHalfSecond(synth)
        #expect(synth.currentGain > 0 && synth.currentGain < 1)
        #expect(!synth.isSilent)
        #expect(audioMaxStep(during) <= referenceStep * 1.05 + 1.5 / Float(0.75 * rate) * referencePeak + 1e-5)

        let tail = renderHalfSecond(synth)
        #expect(synth.currentGain == 0 && synth.isSilent)
        // The fade finishes 0.25 s into this half second; from then on it is exactly zero.
        #expect(tail[Int(0.26 * rate)...].allSatisfy { $0 == 0 })
        #expect(renderHalfSecond(synth).allSatisfy { $0 == 0 })

        synth.fade(to: 1, over: 0.3)
        let back = renderHalfSecond(synth)
        #expect(!synth.isSilent && synth.currentGain == 1)
        #expect(audioRMS(back.suffix(5_000)) > 0.01)
        #expect(audioMaxStep(back) <= referenceStep * 1.05 + 1.5 / Float(0.3 * rate) * referencePeak + 1e-5)
    }

    @Test func fadeRequestsAreClampedAndNeverBreakTheSound() {
        let synth = AmbienceSynth(recipe: .library, seed: 1, initialGain: 0.5)
        var buffer = [Float](repeating: 0, count: 22_050)
        func renderAndCheck() {
            buffer.withUnsafeMutableBufferPointer { storage in
                if let base = storage.baseAddress { synth.render(left: base, right: nil, frames: storage.count) }
            }
            #expect(audioAllFinite(buffer))
            #expect(audioPeak(buffer) <= AudioLimiter.ceiling)
        }
        synth.fade(to: 7, over: 0.1)
        renderAndCheck()
        #expect(synth.currentGain == 1)
        synth.fade(to: .nan, over: .nan)
        renderAndCheck()
        renderAndCheck()
        #expect(synth.currentGain == 0)
        synth.fade(to: -3, over: -1)
        renderAndCheck()
        #expect(synth.currentGain == 0)
        // The last request before a block wins.
        synth.fade(to: 0, over: 1)
        synth.fade(to: 1, over: 0.05)
        renderAndCheck()
        #expect(synth.targetGain == 1 && synth.currentGain == 1)
    }

    @Test func volumeCurveIsMonotonicAndClamped() {
        #expect(AmbienceSynth.gain(forVolume: 0) == 0)
        #expect(AmbienceSynth.gain(forVolume: 1) == 1)
        #expect(AmbienceSynth.gain(forVolume: -4) == 0)
        #expect(AmbienceSynth.gain(forVolume: 9) == 1)
        #expect(AmbienceSynth.gain(forVolume: .nan) == 0)
        var previous: Float = -1
        for step in 0...100 {
            let gain = AmbienceSynth.gain(forVolume: Float(step) / 100)
            #expect(gain >= previous)
            #expect(gain <= Float(step) / 100 + 1e-6, "the curve only ever lowers the gain")
            previous = gain
        }
    }

    @Test func renderingHandlesTheEdges() {
        let synth = AmbienceSynth(recipe: .fireplace, seed: 3)
        var sentinel = [Float](repeating: 0.123, count: 8)
        sentinel.withUnsafeMutableBufferPointer { storage in
            guard let base = storage.baseAddress else { return }
            synth.render(left: base, right: nil, frames: 0)
            synth.render(left: base, right: nil, frames: -5)
            synth.render(into: base, frames: 0)
        }
        #expect(sentinel.allSatisfy { $0 == 0.123 })

        // A request much bigger than the internal block is split up and still comes out right.
        var big = [Float](repeating: 0, count: 200_000)
        big.withUnsafeMutableBufferPointer { storage in
            if let base = storage.baseAddress { synth.render(left: base, right: nil, frames: storage.count) }
        }
        #expect(audioAllFinite(big))
        #expect(audioPeak(big) <= AudioLimiter.ceiling)
        #expect(audioRMS(big) > 0.01)

        // Absurd sample rates are pulled into a sensible range.
        #expect(AmbienceSynth(recipe: .rain, sampleRate: 5).sampleRate == 8_000)
        #expect(AmbienceSynth(recipe: .rain, sampleRate: 1e9).sampleRate == 192_000)
        let extreme = audioRender(.rain, seconds: 0.2, sampleRate: 192_000)
        #expect(audioAllFinite(extreme.left) && audioPeak(extreme.left) <= AudioLimiter.ceiling)
        let low = audioRender(.cafe, seconds: 0.5, sampleRate: 8_000)
        #expect(audioAllFinite(low.left) && audioPeak(low.left) <= AudioLimiter.ceiling)
    }

    @Test func kettleBubblesBuildWithoutGettingLouder() {
        let rate = 44_100.0
        let kettle = audioRender(.kettle, seconds: 25, seed: 12).left
        let early = audioRMS(kettle[0..<Int(4 * rate)])
        let rolling = audioRMS(kettle[Int(21 * rate)..<Int(25 * rate)])
        #expect(abs(audioDecibels(early) - audioDecibels(rolling)) < 2.5, "the simmer keeps its loudness")

        // The bubbling starts slow, rises smoothly, then levels off at a rolling simmer.
        let rise = AmbienceKettleVoice.riseSeconds
        #expect(rise > 5 && rise < 60)
        #expect(AmbienceKettleVoice.bubbleRate(atSeconds: 0, rolling: 0) == 2.5)
        #expect(AmbienceKettleVoice.bubbleRate(atSeconds: rise, rolling: 0) == 24.5)
        #expect(AmbienceKettleVoice.bubbleRate(atSeconds: rise * 10, rolling: 0) == 24.5)
        var previous = AmbienceKettleVoice.bubbleRate(atSeconds: 0, rolling: 0)
        var worstJump: Float = 0
        for step in 0...400 {
            let rate = AmbienceKettleVoice.bubbleRate(atSeconds: Float(step) * rise / 400, rolling: 0)
            #expect(rate >= previous)
            worstJump = max(worstJump, rate - previous)
            previous = rate
        }
        #expect(worstJump < 0.3)
        // Rolling only swells or eases the simmer a little, and bad input cannot push it out of bounds.
        let swell = AmbienceKettleVoice.bubbleRate(atSeconds: rise, rolling: 1)
        let ease = AmbienceKettleVoice.bubbleRate(atSeconds: rise, rolling: -1)
        #expect(ease < 24.5 && swell > 24.5 && swell < 40)
        #expect(AmbienceKettleVoice.bubbleRate(atSeconds: rise, rolling: 50) == swell)

        // As bubbles multiply they get quieter, so the energy they carry (rate times loudness squared) holds steady.
        let slow = AmbienceKettleVoice.bubbleRate(atSeconds: 0, rolling: 0)
        let busy = AmbienceKettleVoice.bubbleRate(atSeconds: rise, rolling: 0)
        #expect(AmbienceKettleVoice.bubbleLoudness(forRate: busy) < AmbienceKettleVoice.bubbleLoudness(forRate: slow))
        let slowEnergy = slow * AmbienceKettleVoice.bubbleLoudness(forRate: slow) * AmbienceKettleVoice.bubbleLoudness(forRate: slow)
        let busyEnergy = busy * AmbienceKettleVoice.bubbleLoudness(forRate: busy) * AmbienceKettleVoice.bubbleLoudness(forRate: busy)
        #expect(abs(slowEnergy - busyEnergy) < 0.01)
    }
}

// MARK: - Cues

struct CozyCueTests {
    @Test(arguments: CozyCue.allCases)
    func everyCueIsFiniteShortAndEndsInSilence(cue: CozyCue) {
        let rate = 44_100.0
        let samples = CozyCueSynth.render(cue, sampleRate: rate)
        let seconds = CozyCueSynth.duration(of: cue)
        #expect(seconds > 0.1 && seconds < 5)
        #expect(samples.count == Int(seconds * rate))
        #expect(audioAllFinite(samples))

        let peak = audioPeak(samples)
        #expect(peak <= AudioLimiter.ceiling)
        #expect(abs(peak - CozyCueSynth.peak(of: cue)) < 0.01, "\(cue) peak \(peak)")
        #expect(audioRMS(samples) > 0.01, "\(cue) is audible")

        // It begins and ends at exactly zero, and the last stretch is a gentle slope, not a cut.
        #expect(samples.first == 0)
        #expect(samples.last == 0)
        let tail = Array(samples.suffix(Int(0.003 * rate)))
        #expect(audioPeak(tail) < peak * 0.25, "\(cue) ends quietly")
        #expect(audioMaxStep(Array(samples.suffix(Int(0.02 * rate)))) < peak * 0.2, "\(cue) ends without a click")
        #expect(audioMaxStep(Array(samples.prefix(Int(0.002 * rate)))) < peak * 0.2, "\(cue) starts without a click")
    }

    @Test(arguments: CozyCue.allCases)
    func cuesAreDeterministicAndFollowTheSampleRate(cue: CozyCue) {
        let first = CozyCueSynth.render(cue, seed: 3)
        #expect(first == CozyCueSynth.render(cue, seed: 3))
        if cue != .steepReady {
            // The chime has no noise in it; the rest use the seed for their texture.
            #expect(first != CozyCueSynth.render(cue, seed: 4))
        } else {
            #expect(first == CozyCueSynth.render(cue, seed: 4))
        }
        for rate in [22_050.0, 48_000.0] {
            let other = CozyCueSynth.render(cue, sampleRate: rate, seed: 3)
            #expect(other.count == Int(CozyCueSynth.duration(of: cue) * rate))
            #expect(audioAllFinite(other))
            #expect(other.first == 0 && other.last == 0)
            #expect(audioPeak(other) <= AudioLimiter.ceiling)
        }
        // Nonsense rates are clamped rather than trusted.
        #expect(!CozyCueSynth.render(cue, sampleRate: 0).isEmpty)
        #expect(CozyCueSynth.render(cue, sampleRate: .nan).allSatisfy { $0.isFinite })
    }

    @Test func theChimeIsTwoNotesAFourthApart() {
        let rate = 44_100.0
        let chime = CozyCueSynth.render(.steepReady)
        let beforeSecond = chime[Int(0.05 * rate)..<Int(0.30 * rate)]
        let afterSecond = chime[Int(0.45 * rate)..<Int(0.70 * rate)]
        // A5 (880 Hz) is not in the first note at all, and is the heart of the second.
        let highBefore = audioTone(beforeSecond, frequency: 880, sampleRate: rate)
        let highAfter = audioTone(afterSecond, frequency: 880, sampleRate: rate)
        #expect(highAfter > highBefore * 5, "A5 before \(highBefore) after \(highAfter)")
        // E5 (659.25 Hz) starts strong and fades.
        let lowBefore = audioTone(beforeSecond, frequency: 659.25, sampleRate: rate)
        #expect(lowBefore > highBefore * 5)
        // And it rings out: well over a second later it is still there, but small.
        let late = audioRMS(chime[Int(1.8 * rate)..<Int(2.0 * rate)])
        let early = audioRMS(chime[Int(0.45 * rate)..<Int(0.65 * rate)])
        #expect(late > 0 && late < early * 0.5)
    }

    @Test func thePourClimbsInPitchAsTheCupFills() {
        let rate = 44_100.0
        let pour = CozyCueSynth.render(.pour)
        let early = audioZeroCrossings(pour[Int(0.3 * rate)..<Int(0.7 * rate)])
        let late = audioZeroCrossings(pour[Int(1.2 * rate)..<Int(1.6 * rate)])
        #expect(Double(late) > Double(early) * 1.15, "early \(early) late \(late)")
        // It swells in and settles out rather than starting or stopping at full strength.
        #expect(audioRMS(pour[0..<2_000]) < audioRMS(pour[Int(0.8 * rate)..<Int(1.2 * rate)]) * 0.6)
        #expect(audioRMS(pour.suffix(2_000)) < audioRMS(pour[Int(0.8 * rate)..<Int(1.2 * rate)]) * 0.6)
    }

    @Test func theKettleClickIsTwoTransientsClose() {
        let rate = 44_100.0
        let click = CozyCueSynth.render(.kettleClick)
        // The dry click is bright and short; the thunk that follows is lower.
        let clickPart = click[0..<Int(0.02 * rate)]
        let thunkPart = click[Int(0.04 * rate)..<Int(0.12 * rate)]
        let brightClick = audioHighShare(Array(clickPart), cutoff: 2_000, sampleRate: rate)
        let brightThunk = audioHighShare(Array(thunkPart), cutoff: 2_000, sampleRate: rate)
        #expect(brightClick > brightThunk, "click \(brightClick) thunk \(brightThunk)")
        #expect(audioRMS(click.suffix(Int(0.1 * rate))) < audioRMS(thunkPart) * 0.2)
    }

    @Test func sequencesAreOrderedAndDoNotOverlapTheirNeighbours() {
        for sequence in [CozyCueSequence.brewStart, CozyCueSequence.ready] {
            #expect(!sequence.isEmpty)
            #expect(sequence.allSatisfy { $0.delay >= 0 && $0.delay.isFinite })
            #expect(zip(sequence, sequence.dropFirst()).allSatisfy { $0.delay <= $1.delay })
            #expect(sequence.first?.delay == 0)
        }
        let brew = CozyCueSequence.brewStart
        #expect(brew.map(\.cue) == [.kettleClick, .pour])
        #expect(brew[1].delay >= CozyCueSynth.duration(of: .kettleClick))
        #expect(CozyCueSequence.ready.map(\.cue) == [.steepReady])
    }
}
