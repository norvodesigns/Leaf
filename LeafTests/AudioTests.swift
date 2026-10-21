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
    version: AmbienceRecipe.Version = .current,
    configure: ((AmbienceSynth) -> Void)? = nil
) -> (left: [Float], right: [Float]) {
    let synth = AmbienceSynth(recipe: recipe, sampleRate: sampleRate, seed: seed, initialGain: initialGain, version: version)
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

/// LUFS of a stereo render (K-weighted, ungated), from `from` seconds on.
private func audioLoudness(_ render: (left: [Float], right: [Float]), from seconds: Double = 0, sampleRate: Double = 44_100) -> Double {
    let start = min(render.left.count, Int(seconds * sampleRate))
    return AudioMeasure.loudness(left: Array(render.left[start...]), right: Array(render.right[start...]), sampleRate: sampleRate)
}

/// How long to render a recipe to hear it properly, and where its steady sound begins (the kettle needs its rise).
private func audioSettle(_ recipe: AmbienceRecipe) -> Double { recipe == .kettle ? 32 : 0 }

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
            #expect(recipe.targetLoudness < -12 && recipe.targetLoudness > -35)
            for version in AmbienceRecipe.Version.allCases {
                #expect(recipe.rawToTarget(version) > 0)
            }
        }
        let quietest: Double = AmbienceRecipe.allCases.map { $0.targetLoudness }.min() ?? 0
        #expect(AmbienceRecipe.library.targetLoudness == quietest)
    }

    @Test(arguments: AmbienceRecipe.allCases)
    func thirtySecondsStayFiniteUnderTheCeilingAndOnTarget(recipe: AmbienceRecipe) {
        let rate = 44_100.0
        let settle = audioSettle(recipe)
        let render = audioRender(recipe, seconds: 30 + settle, sampleRate: rate, seed: 7)
        let left = render.left
        let right = render.right
        #expect(audioAllFinite(left) && audioAllFinite(right), "\(recipe)")

        let peak = max(audioPeak(left), audioPeak(right))
        #expect(peak <= AudioLimiter.ceiling, "\(recipe) peak \(peak)")

        let loudness = audioLoudness(render, from: settle)
        let offTarget = loudness - recipe.targetLoudness
        #expect(abs(offTarget) < 1.5, "\(recipe) is \(offTarget) LU from its target (\(loudness) LUFS)")

        // No stuck DC offset, and the two ears hear different things.
        #expect(abs(left.reduce(0.0) { $0 + Double($1) } / Double(left.count)) < 0.01)
        #expect(left != right)

        // Never dead air, and no two-second stretch wildly louder than the whole.
        let window = Int(2 * rate)
        let whole = audioRMS(Array(left[Int(settle * rate)...]))
        for start in stride(from: Int(settle * rate), to: left.count - window, by: window) {
            let local = audioRMS(left[start..<(start + window)])
            #expect(local > 1e-4, "\(recipe) is silent at \(start)")
            #expect(local < whole * 4, "\(recipe) jumps at \(start)")
        }
    }

    @Test(arguments: AmbienceRecipe.allCases)
    func levelHoldsAcrossSeeds(recipe: AmbienceRecipe) {
        let settle = audioSettle(recipe)
        // The library's events are sparse, so it needs longer to average out.
        let seconds: Double = recipe == .library ? 30 : 10
        for seed in [2, 3] as [UInt64] {
            let render = audioRender(recipe, seconds: settle + seconds, seed: seed)
            let offTarget = audioLoudness(render, from: settle) - recipe.targetLoudness
            #expect(abs(offTarget) < 2.2, "\(recipe) seed \(seed): \(offTarget) LU")
        }
    }

    @Test(arguments: AmbienceRecipe.allCases)
    func otherSampleRatesStayFiniteAndRoughlyOnTarget(recipe: AmbienceRecipe) {
        for rate in [22_050.0, 48_000.0] {
            let render = audioRender(recipe, seconds: 6, sampleRate: rate, seed: 5)
            #expect(render.left.count == Int(6 * rate))
            #expect(audioAllFinite(render.left) && audioAllFinite(render.right))
            #expect(max(audioPeak(render.left), audioPeak(render.right)) <= AudioLimiter.ceiling)
            // The kettle is still coming up and the library's six seconds may hold no event; the rest are steady.
            guard recipe != .kettle && recipe != .library else { continue }
            let offTarget = audioLoudness(render, sampleRate: rate) - recipe.targetLoudness
            #expect(abs(offTarget) < 3, "\(recipe) at \(rate): \(offTarget) LU")
        }
    }

    @Test(arguments: AmbienceRecipe.allCases)
    func theOriginalRecipesStillPlayForComparison(recipe: AmbienceRecipe) {
        let render = audioRender(recipe, seconds: 3, seed: 8, version: .original)
        #expect(audioAllFinite(render.left) && audioAllFinite(render.right))
        #expect(max(audioPeak(render.left), audioPeak(render.right)) <= AudioLimiter.ceiling)
        #expect(audioRMS(render.left) > 1e-4)
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

    @Test func theKettleComesUpToASimmerAndStaysThere() {
        let rise = AmbienceKettleVoice.riseSeconds
        #expect(rise > 10 && rise < 60)
        // The bubbling starts with the odd bubble, rises smoothly, then levels off at a rolling simmer.
        let first: Float = AmbienceKettleVoice.bubbleRate(atSeconds: 0, rolling: 0)
        let settled: Float = AmbienceKettleVoice.bubbleRate(atSeconds: rise * 1.3, rolling: 0)
        let later: Float = AmbienceKettleVoice.bubbleRate(atSeconds: rise * 10, rolling: 0)
        #expect(first < 1)
        #expect(settled > 60)
        #expect(later == settled)
        var previous = first
        var worstJump: Float = 0
        for step in 0...600 {
            let rate = AmbienceKettleVoice.bubbleRate(atSeconds: Float(step) * rise * 1.5 / 600, rolling: 0)
            #expect(rate >= previous)
            worstJump = max(worstJump, rate - previous)
            previous = rate
        }
        #expect(worstJump < 1)
        // Rolling only swells or eases the simmer, and bad input cannot push it out of bounds.
        let swell = AmbienceKettleVoice.bubbleRate(atSeconds: rise * 2, rolling: 1)
        let ease = AmbienceKettleVoice.bubbleRate(atSeconds: rise * 2, rolling: -1)
        #expect(ease < later && swell > later)
        #expect(AmbienceKettleVoice.bubbleRate(atSeconds: rise * 2, rolling: 50) == swell)

        // Once simmering, more bubbles means quieter bubbles: the energy (rate times loudness squared) holds.
        let busy: Float = AmbienceKettleVoice.bubbleLoudness(forRate: 80, simmer: 1)
        let fewer: Float = AmbienceKettleVoice.bubbleLoudness(forRate: 20, simmer: 1)
        let busyEnergy: Float = 80 * busy * busy
        let fewerEnergy: Float = 20 * fewer * fewer
        #expect(abs(busyEnergy - fewerEnergy) < 0.01)
        // While the water is coming up, bubbles are small.
        #expect(AmbienceKettleVoice.bubbleLoudness(forRate: 4, simmer: 0) < AmbienceKettleVoice.bubbleLoudness(forRate: 4, simmer: 1))
    }
}

// MARK: - What each sound is like

/// Checks that hold each ambience to what its real counterpart is like, measured rather than heard. Several also show
/// that the first TestFlight's recipe fails them, which is how its fire came to sound like a drip and its library like
/// static.
struct AmbienceCharacterTests {
    private let rate = 44_100.0

    private func mono(_ recipe: AmbienceRecipe, seconds: Double, seed: UInt64 = 7, version: AmbienceRecipe.Version = .current) -> [Float] {
        let render = audioRender(recipe, seconds: seconds, seed: seed, version: version)
        return AudioMeasure.mono(render.left, render.right)
    }

    @Test func fireCracklesAreNoiseNotDrips() {
        let fire = mono(.fireplace, seconds: 15)
        let onsets = AudioMeasure.onsets(fire, sampleRate: rate)
        #expect(onsets.count > 20)
        let ringing: Double = AudioMeasure.ringing(fire, onsets: onsets, sampleRate: rate)
        #expect(ringing < 0.35, "crackles ring at a pitch: \(ringing)")

        // The first fire's pops were pitched rings, and the measure says so.
        // Its crackles barely cleared its own hiss, so it takes longer to find enough of them.
        let original = mono(.fireplace, seconds: 30, version: .original)
        let originalRinging: Double = AudioMeasure.ringing(original, onsets: AudioMeasure.onsets(original, sampleRate: rate), sampleRate: rate)
        #expect(originalRinging > ringing + 0.1, "original \(originalRinging), now \(ringing)")
    }

    @Test func fireCracklesComeInSpells() {
        let fire = mono(.fireplace, seconds: 20, seed: 9)
        let spacing = AudioMeasure.spacing(AudioMeasure.onsets(fire, sampleRate: rate), seconds: 20, sampleRate: rate)
        #expect(spacing.rate > 2 && spacing.rate < 30, "crackles a second: \(spacing.rate)")
        // Bursty: far less even than chance, with many crackles close behind another.
        #expect(spacing.variation > 1.2, "gap variation \(spacing.variation)")
        #expect(spacing.closeShare > 0.15, "close gaps \(spacing.closeShare)")
    }

    @Test func fireIsAWarmRoarWithoutHiss() {
        let fire = mono(.fireplace, seconds: 15)
        let hiss: Double = AudioMeasure.quietHiss(fire, sampleRate: rate)
        let balance: Double = AudioMeasure.bandBalance(fire, low: 2_000, high: 8_000, sampleRate: rate)
        #expect(hiss < -24, "hiss between crackles: \(hiss) dB")
        #expect(balance < -6, "highs against the roar: \(balance) dB")
        let original = mono(.fireplace, seconds: 15, version: .original)
        let originalHiss: Double = AudioMeasure.quietHiss(original, sampleRate: rate)
        #expect(originalHiss > hiss + 4, "original \(originalHiss), now \(hiss)")
    }

    @Test func theLibraryIsAQuietRoomNotStatic() {
        let library = mono(.library, seconds: 45)
        let hiss: Double = AudioMeasure.quietHiss(library, sampleRate: rate)
        let contrast: Double = AudioMeasure.phoneBandContrast(library, sampleRate: rate)
        #expect(hiss < -35, "hiss in the quiet: \(hiss) dB")
        #expect(contrast > 8, "events against the room in a phone speaker's band: \(contrast) dB")
        let onsets = AudioMeasure.onsets(library, sampleRate: rate)
        if onsets.count >= 5 {
            let ringing: Double = AudioMeasure.ringing(library, onsets: onsets, sampleRate: rate)
            #expect(ringing < 0.35, "library events ring: \(ringing)")
        }

        // The first library was a constant hiss, so nothing stood out of it.
        let original = mono(.library, seconds: 45, version: .original)
        let originalHiss: Double = AudioMeasure.quietHiss(original, sampleRate: rate)
        let originalContrast: Double = AudioMeasure.phoneBandContrast(original, sampleRate: rate)
        #expect(originalHiss > -28, "original hiss \(originalHiss)")
        #expect(originalContrast < 4, "original contrast \(originalContrast)")
    }

    @Test func theCafeIsShapedLikeSpeech() {
        let cafe = mono(.cafe, seconds: 12)
        let peak: Double = AudioMeasure.spectralPeak(cafe, low: 80, high: 4_000, sampleRate: rate)
        let syllables: Double = AudioMeasure.syllableModulation(cafe, sampleRate: rate)
        let highs: Double = AudioMeasure.decibels(AudioMeasure.meanSquare(AudioMeasure.band(cafe, low: 4_000, high: 10_000, sampleRate: rate)))
            - AudioMeasure.decibels(AudioMeasure.meanSquare(cafe))
        // Speech carries most of its power between about 250 Hz and 1 kHz, moves at the rate of syllables, and a few
        // tables away has little left above 4 kHz.
        #expect(peak > 250 && peak < 1_000, "spectral peak \(peak) Hz")
        #expect(syllables > 0.25, "syllable-rate movement \(syllables)")
        #expect(highs < -18, "above 4 kHz: \(highs) dB")
    }

    @Test func theKettleRisesWithoutAWhistle() {
        let kettle = mono(.kettle, seconds: 45, seed: 12)
        let early = AudioMeasure.meanSquare(Array(kettle[0..<Int(6 * rate)]))
        let simmer = Array(kettle[Int(35 * rate)...])
        let late = AudioMeasure.meanSquare(simmer)
        let rise: Double = AudioMeasure.decibels(late) - AudioMeasure.decibels(early)
        #expect(rise > 8, "rise from the first seconds to the simmer: \(rise) dB")
        let tonal: Double = AudioMeasure.tonalPeak(simmer, sampleRate: rate)
        #expect(tonal < 8, "a narrow peak (a whistle) \(tonal) dB above its neighbours")
    }

    @Test func noSteadySoundHumsOrWhistles() {
        for recipe in [AmbienceRecipe.rain, .fireplace] {
            let sound = mono(recipe, seconds: 20)
            let tonal: Double = AudioMeasure.tonalPeak(sound, sampleRate: rate)
            #expect(tonal < 8, "\(recipe): \(tonal) dB")
        }
    }

    @Test func theSoundsMatchInLoudness() {
        var levels: [Double] = []
        for recipe in [AmbienceRecipe.rain, .fireplace, .kettle, .cafe] {
            let settle = audioSettle(recipe)
            levels.append(audioLoudness(audioRender(recipe, seconds: settle + 12, seed: 4), from: settle))
        }
        let loudest: Double = levels.max() ?? 0
        let quietest: Double = levels.min() ?? 0
        #expect(loudest - quietest < 2.5, "loudness spread \(levels)")
    }
}

// MARK: - Loops

struct AudioLoopTests {
    @Test func aCrossfadedLoopJoinsWithoutAClick() {
        // Noise riding on a slow ramp: as a plain loop it jumps from the top of the ramp back to the bottom.
        var noise = AudioNoiseSource(color: .pink, seed: 3, sampleRate: 44_100)
        var recording: [Float] = []
        for index in 0..<88_200 {
            recording.append(noise.next() * 0.1 + Float(index) / 88_200 * 0.8)
        }
        let plain: Double = AudioLoop.seamJump(recording)
        let loop = AudioLoop.seamless(recording, crossfade: 4_410)
        let joined: Double = AudioLoop.seamJump(loop)
        #expect(plain > 5, "the plain loop clicks: \(plain)")
        #expect(joined < 1.5, "the crossfaded loop: \(joined)")
        #expect(loop.count == recording.count - 4_410)
        // Nothing to fade leaves it alone; an absurd fade is limited to half the recording.
        #expect(AudioLoop.seamless(recording, crossfade: 0) == recording)
        #expect(AudioLoop.seamless(recording, crossfade: 1_000_000).count == recording.count / 2)
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

    @Test(arguments: CozyCue.allCases)
    func cuesAreSoftNotSharp(cue: CozyCue) {
        let samples = CozyCueSynth.render(cue)
        // Little above 6 kHz, where a cue turns from soft to sharp, and its centre of brightness low.
        let above: Double = AudioMeasure.meanSquare(AudioMeasure.band(samples, low: 6_000, high: 16_000, sampleRate: 44_100))
        let all: Double = AudioMeasure.meanSquare(samples)
        let share: Double = above / max(all, 1e-20)
        #expect(share < 0.1, "\(cue): \(share) of its energy above 6 kHz")
        let power = AudioMeasure.spectrum(samples, size: 1_024)
        var weighted = 0.0
        var total = 0.0
        for bin in power.indices {
            weighted += Double(bin) * 44_100 / 1_024 * power[bin]
            total += power[bin]
        }
        let centroid: Double = weighted / max(total, 1e-20)
        #expect(centroid < 2_500, "\(cue): brightness centre \(centroid) Hz")
        #expect(CozyCueSynth.peak(of: cue) <= 0.3)
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
