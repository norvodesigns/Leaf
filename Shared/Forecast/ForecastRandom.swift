import Foundation

/// Random-number helpers for the forecast. Every draw comes from `SeededGenerator` (Shared/Recommender.swift), so the
/// same seed always produces the same futures. Nothing here touches `Date()`, `Hasher` or the system generator.
enum ForecastRandom {
    /// SplitMix64's finalizer, used to scatter seeds.
    static func scramble(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// An independent stream for one purpose inside one simulated future. Consecutive seeds would make streams that are
    /// shifted copies of each other (SplitMix64 steps its state by a constant), so seed, run and purpose are scrambled
    /// separately and combined. Giving each purpose its own stream also means a what-if that changes one input does
    /// not shift the random numbers used by the others, so before and after share the same luck.
    static func stream(seed: UInt64, run: Int, salt: UInt64) -> SeededGenerator {
        let mixed = scramble(seed) ^ scramble(UInt64(truncatingIfNeeded: run) &+ 1) ^ scramble(salt &+ 0x5851_F42D_4C95_7F2D)
        return SeededGenerator(seed: scramble(mixed))
    }

    /// The standard normal quantile (Acklam's rational approximation, relative error about 1e-9).
    static func inverseNormal(_ probability: Double) -> Double {
        let p = min(max(probability, 1e-12), 1 - 1e-12)
        if p < 0.02425 {
            return tail(p)
        }
        if p > 1 - 0.02425 {
            return -tail(1 - p)
        }
        let q = p - 0.5
        let r = q * q
        var num = -3.969683028665376e+01
        num = num * r + 2.209460984245205e+02
        num = num * r - 2.759285104469687e+02
        num = num * r + 1.383577518672690e+02
        num = num * r - 3.066479806614716e+01
        num = num * r + 2.506628277459239e+00
        var den = -5.447609879822406e+01
        den = den * r + 1.615858368580409e+02
        den = den * r - 1.556989798598866e+02
        den = den * r + 6.680131188771972e+01
        den = den * r - 1.328068155288572e+01
        den = den * r + 1
        return num * q / den
    }

    /// Lower-tail branch of `inverseNormal` (p below about 2.4 percent).
    private static func tail(_ p: Double) -> Double {
        let q = (-2 * log(p)).squareRoot()
        var num = -7.784894002430293e-03
        num = num * q - 3.223964580411365e-01
        num = num * q - 2.400758277161838e+00
        num = num * q - 2.549732539343734e+00
        num = num * q + 4.374664141464968e+00
        num = num * q + 2.938163982698783e+00
        var den = 7.784695709041462e-03
        den = den * q + 3.224671290700398e-01
        den = den * q + 2.445134137142996e+00
        den = den * q + 3.754408661907416e+00
        den = den * q + 1
        return num / den
    }

    /// Standard normal CDF.
    static func normalCDF(_ x: Double) -> Double {
        0.5 * (1 + erf(x / 2.0.squareRoot()))
    }

    /// One standard normal draw, from exactly one uniform, so the number of draws never depends on the value drawn.
    static func normal(_ rng: inout SeededGenerator) -> Double {
        inverseNormal(rng.unit())
    }

    /// Gamma(shape, 1) by Marsaglia and Tsang. The loop is bounded so a pathological stream cannot hang a forecast.
    static func gamma(shape: Double, _ rng: inout SeededGenerator) -> Double {
        let k = max(shape, 1e-3)
        if k < 1 {
            let u = max(rng.unit(), 1e-12)
            return gamma(shape: k + 1, &rng) * pow(u, 1 / k)
        }
        let d = k - 1.0 / 3.0
        let c = 1.0 / (9.0 * d).squareRoot()
        for _ in 0..<100 {
            let x = normal(&rng)
            let t = 1 + c * x
            if t <= 0 { continue }
            let v = t * t * t
            let u = max(rng.unit(), 1e-12)
            if log(u) < 0.5 * x * x + d - d * v + d * log(v) { return d * v }
        }
        return d
    }

    /// Beta(a, b), the posterior of a probability after counting successes and failures.
    static func beta(a: Double, b: Double, _ rng: inout SeededGenerator) -> Double {
        let x = gamma(shape: a, &rng)
        let y = gamma(shape: b, &rng)
        let total = x + y
        guard total > 0 else { return a / max(a + b, 1e-9) }
        return x / total
    }
}
