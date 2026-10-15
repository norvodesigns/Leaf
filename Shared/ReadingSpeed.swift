import Foundation

/// Words-per-minute math: the speed test, comprehension weighting, and calibration from real sessions.
enum ReadingSpeed {
    /// Average silent reading speed for adults reading non-fiction (Brysbaert, 2019).
    static let typicalAdultWPM: Double = 238
    static let plausibleRange: ClosedRange<Double> = 60...1000

    static func wpm(words: Int, seconds: Double) -> Double {
        guard seconds > 0 else { return typicalAdultWPM }
        return Double(words) / (seconds / 60)
    }

    /// Skimming without taking anything in isn't reading, so low comprehension scales the result down.
    static func comprehensionFactor(correct: Int, total: Int) -> Double {
        guard total > 0 else { return 1 }
        let ratio = Double(max(0, min(correct, total))) / Double(total)
        switch ratio {
        case 0.999...: return 1.0
        case 0.6...: return 0.92
        case 0.3...: return 0.78
        default: return 0.65
        }
    }

    static func effectiveWPM(words: Int, seconds: Double, correct: Int, total: Int) -> Double {
        clamp(wpm(words: words, seconds: seconds) * comprehensionFactor(correct: correct, total: total))
    }

    static func clamp(_ wpm: Double) -> Double {
        min(plausibleRange.upperBound, max(plausibleRange.lowerBound, wpm))
    }

    /// Rough share of adults who read slower (normal approximation, mean 238, sd 70).
    static func percentile(for wpm: Double) -> Int {
        let z = (wpm - typicalAdultWPM) / 70
        let cdf = 0.5 * (1 + erf(z / 2.0.squareRoot()))
        return Int(min(99, max(1, (cdf * 100).rounded())))
    }

    static func descriptor(for wpm: Double) -> String {
        switch wpm {
        case ..<180: return "Unhurried"
        case ..<230: return "Steady"
        case ..<290: return "Brisk"
        case ..<380: return "Swift"
        default: return "Rapid"
        }
    }

    /// Speed observed in a real session, or nil when the session is too short or implausible to learn from.
    static func observedWPM(pagesRead: Int, wordsPerPage: Double, seconds: Double) -> Double? {
        guard seconds >= 180, pagesRead >= 2 else { return nil }
        let value = Double(pagesRead) * wordsPerPage / (seconds / 60)
        guard plausibleRange.contains(value) else { return nil }
        return value
    }

    /// Nudges the current estimate toward what the reader actually did, ignoring wild outliers.
    static func calibrated(current: Double, observed: Double, weight: Double = 0.2) -> Double {
        guard observed > current * 0.4, observed < current * 2.5 else { return current }
        return clamp(current * (1 - weight) + observed * weight)
    }
}
