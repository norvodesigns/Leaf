import Foundation

/// Measures for judging a sound without listening to it: loudness, spectrum, how spiky a band is, whether transients
/// ring at a pitch, how events are spaced in time. The tests use them to hold each ambience to what its real
/// counterpart is like, and the preview renderer prints them beside each file. Plain loops over `[Float]`; not for
/// the audio thread.
enum AudioMeasure {
    // MARK: Filters

    /// A biquad with explicit coefficients (a0 already divided out).
    private struct Section {
        var b0: Double
        var b1: Double
        var b2: Double
        var a1: Double
        var a2: Double

        func run(_ input: [Float]) -> [Float] {
            var output = [Float](repeating: 0, count: input.count)
            var z1 = 0.0
            var z2 = 0.0
            for index in input.indices {
                let x = Double(input[index])
                let y = b0 * x + z1
                z1 = b1 * x - a1 * y + z2
                z2 = b2 * x - a2 * y
                output[index] = Float(y)
            }
            return output
        }
    }

    /// The ITU-R BS.1770 K-weighting (its high shelf and its high-pass), worked out for any sample rate.
    static func kWeighted(_ samples: [Float], sampleRate: Double) -> [Float] {
        let shelfK = tan(Double.pi * 1_681.974450955533 / sampleRate)
        let shelfQ = 0.7071752369554196
        let vh = pow(10, 3.999843853973347 / 20)
        let vb = pow(vh, 0.4996667741545416)
        let shelfA0 = 1 + shelfK / shelfQ + shelfK * shelfK
        let shelf = Section(
            b0: (vh + vb * shelfK / shelfQ + shelfK * shelfK) / shelfA0,
            b1: 2 * (shelfK * shelfK - vh) / shelfA0,
            b2: (vh - vb * shelfK / shelfQ + shelfK * shelfK) / shelfA0,
            a1: 2 * (shelfK * shelfK - 1) / shelfA0,
            a2: (1 - shelfK / shelfQ + shelfK * shelfK) / shelfA0
        )
        let passK = tan(Double.pi * 38.13547087602444 / sampleRate)
        let passQ = 0.5003270373238773
        let passA0 = 1 + passK / passQ + passK * passK
        let pass = Section(b0: 1, b1: -2, b2: 1, a1: 2 * (passK * passK - 1) / passA0, a2: (1 - passK / passQ + passK * passK) / passA0)
        return pass.run(shelf.run(samples))
    }

    /// Loudness in LUFS, K-weighted and ungated: fine for steady sounds like these.
    static func loudness(left: [Float], right: [Float], sampleRate: Double) -> Double {
        let l = meanSquare(kWeighted(left, sampleRate: sampleRate))
        let r = meanSquare(kWeighted(right, sampleRate: sampleRate))
        return -0.691 + 10 * log10(l + r + 1e-20)
    }

    /// The part of the signal between `low` and `high` Hz (two high-pass and two low-pass sections).
    static func band(_ samples: [Float], low: Double, high: Double, sampleRate: Double) -> [Float] {
        var a = AudioFilter(.highpass, frequency: low, sampleRate: sampleRate)
        var b = AudioFilter(.highpass, frequency: low, sampleRate: sampleRate)
        var c = AudioFilter(.lowpass, frequency: high, sampleRate: sampleRate)
        var d = AudioFilter(.lowpass, frequency: high, sampleRate: sampleRate)
        var output = [Float](repeating: 0, count: samples.count)
        for index in samples.indices {
            output[index] = d.process(c.process(b.process(a.process(samples[index]))))
        }
        return output
    }

    static func highpass(_ samples: [Float], cutoff: Double, sampleRate: Double) -> [Float] {
        var a = AudioFilter(.highpass, frequency: cutoff, sampleRate: sampleRate)
        var output = [Float](repeating: 0, count: samples.count)
        for index in samples.indices { output[index] = a.process(samples[index]) }
        return output
    }

    // MARK: Levels

    static func meanSquare(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for sample in samples { sum += Double(sample) * Double(sample) }
        return sum / Double(samples.count)
    }

    static func decibels(_ power: Double) -> Double { 10 * log10(max(power, 1e-30)) }

    static func mono(_ left: [Float], _ right: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: min(left.count, right.count))
        for index in output.indices { output[index] = 0.5 * (left[index] + right[index]) }
        return output
    }

    /// Energy of each `seconds`-long frame.
    static func frameEnergies(_ samples: [Float], seconds: Double, sampleRate: Double) -> [Double] {
        let size = max(1, Int(seconds * sampleRate))
        var energies: [Double] = []
        var start = 0
        while start + size <= samples.count {
            energies.append(meanSquare(Array(samples[start..<(start + size)])))
            start += size
        }
        return energies
    }

    static func percentile(_ values: [Double], _ share: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * share).rounded())))
        return sorted[position]
    }

    /// How far events rise above the bed in what a phone speaker plays (300 Hz to 4 kHz): the 98th percentile of
    /// 50 ms energy over the median, in dB. A hiss scores about 1; a quiet room with sounds in it, 10 or more.
    static func phoneBandContrast(_ samples: [Float], sampleRate: Double) -> Double {
        let energies = frameEnergies(band(samples, low: 300, high: 4_000, sampleRate: sampleRate), seconds: 0.05, sampleRate: sampleRate)
        let top = percentile(energies, 0.98)
        let middle = percentile(energies, 0.5)
        return decibels(top) - decibels(middle)
    }

    /// The 2 to 8 kHz level in the quieter half of 50 ms frames, against the whole sound's level, in dB: a constant
    /// hiss scores high, silence between events scores very low.
    static func quietHiss(_ samples: [Float], sampleRate: Double) -> Double {
        let energies = frameEnergies(band(samples, low: 2_000, high: 8_000, sampleRate: sampleRate), seconds: 0.05, sampleRate: sampleRate)
        return decibels(percentile(energies, 0.5)) - decibels(meanSquare(samples))
    }

    /// Energy between `low` and `high` against energy between 60 and 400 Hz, in dB.
    static func bandBalance(_ samples: [Float], low: Double, high: Double, sampleRate: Double) -> Double {
        let upper = meanSquare(band(samples, low: low, high: high, sampleRate: sampleRate))
        let lower = meanSquare(band(samples, low: 60, high: 400, sampleRate: sampleRate))
        return decibels(upper) - decibels(lower)
    }

    // MARK: Spectrum

    /// In-place radix-2 FFT; `real.count` must be a power of two.
    static func fft(_ real: inout [Double], _ imaginary: inout [Double]) {
        let n = real.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                real.swapAt(i, j)
                imaginary.swapAt(i, j)
            }
        }
        var length = 2
        while length <= n {
            let angle = -2 * Double.pi / Double(length)
            let stepReal = cos(angle)
            let stepImaginary = sin(angle)
            var start = 0
            while start < n {
                var wReal = 1.0
                var wImaginary = 0.0
                for k in 0..<(length / 2) {
                    let a = start + k
                    let b = a + length / 2
                    let tReal = real[b] * wReal - imaginary[b] * wImaginary
                    let tImaginary = real[b] * wImaginary + imaginary[b] * wReal
                    real[b] = real[a] - tReal
                    imaginary[b] = imaginary[a] - tImaginary
                    real[a] += tReal
                    imaginary[a] += tImaginary
                    let next = wReal * stepReal - wImaginary * stepImaginary
                    wImaginary = wReal * stepImaginary + wImaginary * stepReal
                    wReal = next
                }
                start += length
            }
            length <<= 1
        }
    }

    /// Welch's power spectrum: Hann windows of `size` samples overlapping by half. Returns the power per bin
    /// (bin k is k * sampleRate / size Hz).
    static func spectrum(_ samples: [Float], size: Int = 4_096) -> [Double] {
        var window = [Double](repeating: 0, count: size)
        for index in 0..<size { window[index] = 0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(size)) }
        var power = [Double](repeating: 0, count: size / 2 + 1)
        var segments = 0
        var start = 0
        while start + size <= samples.count {
            var real = [Double](repeating: 0, count: size)
            var imaginary = [Double](repeating: 0, count: size)
            for index in 0..<size { real[index] = Double(samples[start + index]) * window[index] }
            fft(&real, &imaginary)
            for bin in 0...(size / 2) { power[bin] += real[bin] * real[bin] + imaginary[bin] * imaginary[bin] }
            segments += 1
            start += size / 2
        }
        guard segments > 0 else { return power }
        for bin in power.indices { power[bin] /= Double(segments) }
        return power
    }

    /// The frequency with the most power between `low` and `high` Hz.
    static func spectralPeak(_ samples: [Float], low: Double, high: Double, sampleRate: Double) -> Double {
        let size = 4_096
        let power = spectrum(samples, size: size)
        let hzPerBin = sampleRate / Double(size)
        var best = 0
        var bestPower = -1.0
        for bin in power.indices {
            let hz = Double(bin) * hzPerBin
            guard hz >= low, hz < high else { continue }
            if power[bin] > bestPower {
                bestPower = power[bin]
                best = bin
            }
        }
        return Double(best) * hzPerBin
    }

    /// How far the strongest narrow peak between `low` and `high` Hz stands above the spectrum around it (a running
    /// median of 31 bins), in dB. A whistle or a hum scores high; noise and broad colour score a few dB.
    static func tonalPeak(_ samples: [Float], low: Double = 200, high: Double = 8_000, sampleRate: Double) -> Double {
        let size = 4_096
        let power = spectrum(samples, size: size)
        let hzPerBin = sampleRate / Double(size)
        var levels: [Double] = []
        for bin in power.indices {
            let hz = Double(bin) * hzPerBin
            if hz >= low && hz < high { levels.append(decibels(power[bin])) }
        }
        guard levels.count > 31 else { return 0 }
        var worst = 0.0
        for index in levels.indices {
            let from = max(0, index - 15)
            let to = min(levels.count, index + 16)
            let neighbourhood = Array(levels[from..<to]).sorted()
            let median = neighbourhood[neighbourhood.count / 2]
            worst = max(worst, levels[index] - median)
        }
        return worst
    }

    /// Share of the 300 Hz to 3 kHz envelope's movement that happens at 2 to 8 Hz: the rate of syllables. Speech
    /// scores about a third; a steady noise much less.
    static func syllableModulation(_ samples: [Float], sampleRate: Double) -> Double {
        let speechBand = band(samples, low: 300, high: 3_000, sampleRate: sampleRate)
        let step = max(1, Int(sampleRate / 441))
        var envelope: [Float] = []
        var start = 0
        while start + step <= speechBand.count {
            var sum: Float = 0
            for index in start..<(start + step) { sum += abs(speechBand[index]) }
            envelope.append(sum / Float(step))
            start += step
        }
        let mean = envelope.reduce(0, +) / Float(max(envelope.count, 1))
        let centred = envelope.map { $0 - mean }
        let size = 512
        let power = spectrum(centred, size: size)
        let rate = sampleRate / Double(step)
        var inBand = 0.0
        var all = 0.0
        for bin in power.indices {
            let hz = Double(bin) * rate / Double(size)
            if hz > 0.3 && hz < 30 { all += power[bin] }
            if hz >= 2 && hz < 8 { inBand += power[bin] }
        }
        return all > 0 ? inBand / all : 0
    }

    // MARK: Events

    /// Where transients start above 1 kHz: the envelope (1 ms average of the rectified high band) crossing six times
    /// its median, at least 2 ms after the last onset.
    static func onsets(_ samples: [Float], sampleRate: Double) -> [Int] {
        let high = highpass(highpass(samples, cutoff: 1_000, sampleRate: sampleRate), cutoff: 1_000, sampleRate: sampleRate)
        let width = max(1, Int(sampleRate * 0.001))
        var envelope = [Float](repeating: 0, count: high.count)
        var running: Float = 0
        for index in high.indices {
            running += abs(high[index])
            if index >= width { running -= abs(high[index - width]) }
            envelope[index] = running / Float(width)
        }
        let median = Float(percentile(envelope.map { Double($0) }, 0.5))
        let threshold = 6 * median + 1e-9
        let gap = Int(sampleRate * 0.002)
        var found: [Int] = []
        var last = -Int.max / 2
        for index in 1..<envelope.count where envelope[index] > threshold && envelope[index - 1] <= threshold {
            if index - last > gap {
                found.append(index)
                last = index
            }
        }
        return found
    }

    struct Spacing: Equatable {
        /// Events a second.
        var rate: Double
        /// Standard deviation of the gaps over their mean: 0 for a metronome, 1 for chance, more for bursts.
        var variation: Double
        /// Share of gaps under 20 ms: events that come in clusters.
        var closeShare: Double
    }

    static func spacing(_ onsets: [Int], seconds: Double, sampleRate: Double) -> Spacing {
        guard onsets.count >= 3 else { return Spacing(rate: Double(onsets.count) / max(seconds, 1e-9), variation: 0, closeShare: 0) }
        var gaps: [Double] = []
        for index in 1..<onsets.count { gaps.append(Double(onsets[index] - onsets[index - 1]) / sampleRate) }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        var variance = 0.0
        for gap in gaps { variance += (gap - mean) * (gap - mean) }
        variance /= Double(gaps.count)
        let close = Double(gaps.filter { $0 < 0.02 }.count) / Double(gaps.count)
        return Spacing(rate: Double(onsets.count) / max(seconds, 1e-9), variation: variance.squareRoot() / max(mean, 1e-12), closeShare: close)
    }

    /// Whether transients ring at a pitch: for the 12 ms after each onset (above 500 Hz), the strongest normalised
    /// autocorrelation at lags of 0.2 to 5 ms, past the first zero crossing; the median over events. A drip (a damped
    /// sine) scores near 1; a crackle of noise, about 0.2.
    static func ringing(_ samples: [Float], onsets: [Int], sampleRate: Double) -> Double {
        let high = highpass(highpass(samples, cutoff: 500, sampleRate: sampleRate), cutoff: 500, sampleRate: sampleRate)
        let window = Int(sampleRate * 0.012)
        let shortest = max(1, Int(sampleRate * 0.0002))
        let longest = Int(sampleRate * 0.005)
        var peaks: [Double] = []
        for onset in onsets.prefix(400) {
            guard onset + window <= high.count else { continue }
            var segment = (0..<window).map { Double(high[onset + $0]) }
            let mean = segment.reduce(0, +) / Double(window)
            for index in segment.indices { segment[index] -= mean }
            var energy = 0.0
            for value in segment { energy += value * value }
            guard energy > 0 else { continue }
            var crossed = false
            var best = 0.0
            for lag in 1..<longest {
                var sum = 0.0
                for index in 0..<(window - lag) { sum += segment[index] * segment[index + lag] }
                let value = sum / energy
                if !crossed {
                    if value < 0 { crossed = true }
                    continue
                }
                if lag >= shortest { best = max(best, value) }
            }
            peaks.append(best)
        }
        return percentile(peaks, 0.5)
    }
}
