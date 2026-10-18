import Foundation

/// Small numeric helpers shared by the interaction engines (ribbon, scrubbing, atmosphere). Everything is a pure
/// function: no clock, no `Calendar.current`, no random source. Noise is hashed from a seed, so the same inputs give the
/// same pixels on every device and in every test.
enum InteractionMath {
    /// `value` limited to `lower...upper`. NaN becomes `lower` and infinities land on the nearer bound, so a bad sensor
    /// reading or a wild gesture can never leak a non-finite number into a pose.
    static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        if value.isNaN { return lower }
        return min(max(value, lower), upper)
    }

    /// `value` when it is a finite number, otherwise `fallback`.
    static func finite(_ value: Double, fallback: Double = 0) -> Double {
        value.isFinite ? value : fallback
    }

    static func lerp(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        from + (to - from) * amount
    }

    /// 0 below `edge0`, 1 above `edge1`, and a gentle S in between.
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
        return t * t * (3 - 2 * t)
    }

    /// The fractional part of `x`, always in 0..<1 (also for negative `x`).
    static func fract(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        let f = x - x.rounded(.down)
        return f < 1 ? f : 0
    }

    /// Grows from 0 toward `limit` as `excess` grows, with slope 1 at the start and never beyond `limit`. This is the
    /// shape of a rubber band: free at first, then more and more resistance. Strictly increasing, so "further" always
    /// means "more".
    static func softLimit(_ excess: Double, limit: Double) -> Double {
        guard excess > 0, limit > 0 else { return 0 }
        return limit * (1 - exp(-excess / limit))
    }

    // MARK: Hashing and noise

    /// Mixes a salt into a seed (SplitMix64 finalizer). Stable across launches and platforms, unlike `Hasher`.
    static func mix(_ seed: UInt64, _ salt: UInt64) -> UInt64 {
        var z = seed &+ (salt &+ 1) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A stable number in 0..<1 for a (seed, salt) pair.
    static func unit(_ seed: UInt64, _ salt: UInt64) -> Double {
        Double(mix(seed, salt) >> 11) / Double(1 << 53)
    }

    /// Smooth one-dimensional value noise in -1...1: random values on the integers, blended with a quintic fade so the
    /// result and its slope are continuous. Used for breathing and drift, where a sine alone would look mechanical.
    static func smoothNoise(seed: UInt64, at x: Double) -> Double {
        let safe = clamp(finite(x), -1e12, 1e12)
        let base = safe.rounded(.down)
        let t = safe - base
        let fade = t * t * t * (t * (t * 6 - 15) + 10)
        let index = UInt64(bitPattern: Int64(base))
        let a = unit(seed, index) * 2 - 1
        let b = unit(seed, index &+ 1) * 2 - 1
        return lerp(a, b, fade)
    }

    /// The signed difference between two angles, wrapped into -pi...pi.
    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 2 * Double.pi)
        if d > Double.pi { d -= 2 * Double.pi }
        if d < -Double.pi { d += 2 * Double.pi }
        return d
    }
}
