import Foundation

// MARK: - Best time of day

/// When in the day the reader does their best reading: where they show up most and where they are quickest.
///
/// Only timed sessions say when someone really sat down (a typed-in session carries the moment it was logged), so only
/// those are used, and there must be enough of them to mean something. Below that the answer is nil rather than a guess.
struct BestTimeOfDay: Hashable, Sendable {
    /// How much one stretch of the day (a `Daypart`) holds.
    struct Total: Hashable, Sendable {
        var daypart: Daypart
        var sessions: Int
        /// Distinct days with a session in this stretch.
        var days: Int
        var minutes: Double
        /// Share of all timed minutes, 0 to 1.
        var minuteShare: Double
        /// Share of all timed sittings, 0 to 1.
        var sessionShare: Double
        /// Sittings long enough to measure a speed from.
        var speedSamples: Int
        /// Words per minute across those sittings, or nil when there are none.
        var wpm: Double?
    }

    /// A stretch of the day with the two-hour window where most of it happens.
    struct Slot: Hashable, Sendable {
        var daypart: Daypart
        /// First hour of the window, 0 to 23.
        var startHour: Int
        /// Hour the window ends, 0 to 23 (exclusive; wraps past midnight, so 23 to 1 means 11 pm to 1 am).
        var endHour: Int
        var sessions: Int
        var minutes: Double
        var minuteShare: Double
        var wpm: Double?
    }

    /// Where most reading happens: the stretch with the biggest blend of sittings and minutes.
    var consistent: Slot
    /// Where the reader is quickest, or nil when the evidence does not support a winner (too few measurable sittings
    /// in two stretches, or speeds within a few percent of each other).
    var fastest: Slot?
    /// A sentence a person could read aloud.
    var reason: String
    /// Timed sittings behind this answer.
    var sessionCount: Int
    var readingDays: Int
    /// Every stretch of the day, in the order of `Daypart.allCases`.
    var dayparts: [Total]

    static let minimumSessions = 10
    static let minimumDays = 5
    static let minimumSpeedSamples = 4
    /// How much quicker a stretch must be than the rest before it is called fastest.
    static let minimumLead = 0.03

    /// "in the evening", "at tea time", ...
    static func phrase(for daypart: Daypart) -> String {
        switch daypart {
        case .smallHours: return "in the small hours"
        case .dawn: return "early in the morning"
        case .morning: return "in the morning"
        case .lunch: return "around lunchtime"
        case .afternoon: return "in the afternoon"
        case .teaTime: return "at tea time"
        case .dusk: return "at dusk"
        case .evening: return "in the evening"
        case .late: return "late at night"
        }
    }

    /// "6 am", "noon", "9 pm", "midnight".
    static func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        if h == 0 { return "midnight" }
        if h == 12 { return "noon" }
        return h < 12 ? "\(h) am" : "\(h - 12) pm"
    }

    /// "7 to 9 pm", "11 pm to 1 am", "noon to 2 pm".
    static func windowText(startHour: Int, endHour: Int) -> String {
        let start = ((startHour % 24) + 24) % 24
        let end = ((endHour % 24) + 24) % 24
        let bothMorning = (1...11).contains(start) && (1...11).contains(end)
        let bothAfternoon = (13...23).contains(start) && (13...23).contains(end)
        if bothMorning || bothAfternoon { return "\(start % 12) to \(hourLabel(end))" }
        return "\(hourLabel(start)) to \(hourLabel(end))"
    }
}

extension InsightsEngine {
    /// The stretch of the day the reader reads most, and the one they read fastest in. Nil until there are at least
    /// ten timed sittings on five different days.
    func bestTimeOfDay() -> BestTimeOfDay? {
        let timed = sittings.filter { $0.isTimed && $0.countsAsReading }
        let dayCount = Set(timed.map(\.day)).count
        guard timed.count >= BestTimeOfDay.minimumSessions, dayCount >= BestTimeOfDay.minimumDays else { return nil }
        let totalMinutes = timed.reduce(0) { $0 + $1.minutes }
        guard totalMinutes > 0 else { return nil }

        let grouped = Dictionary(grouping: timed, by: \.daypart)
        let totals: [BestTimeOfDay.Total] = Daypart.allCases.map { part in
            let mine = grouped[part] ?? []
            let minutes = mine.reduce(0) { $0 + $1.minutes }
            let samples = mine.filter { $0.wpm != nil }
            let sampleMinutes = samples.reduce(0) { $0 + $1.minutes }
            return BestTimeOfDay.Total(
                daypart: part,
                sessions: mine.count,
                days: Set(mine.map(\.day)).count,
                minutes: minutes,
                minuteShare: minutes / totalMinutes,
                sessionShare: Double(mine.count) / Double(timed.count),
                speedSamples: samples.count,
                wpm: sampleMinutes > 0 ? samples.reduce(0) { $0 + $1.words } / sampleMinutes : nil
            )
        }

        // Consistency blends how often and how long: a stretch with many short sittings and one with a few long ones
        // both count, in equal measure.
        let populated = totals.filter { $0.sessions > 0 }
        guard let consistentTotal = populated.max(by: { lhs, rhs in
            let l = lhs.minuteShare + lhs.sessionShare
            let r = rhs.minuteShare + rhs.sessionShare
            if abs(l - r) > 1e-9 { return l < r }
            if abs(lhs.minutes - rhs.minutes) > 1e-9 { return lhs.minutes < rhs.minutes }
            return lhs.daypart.insightsOrder > rhs.daypart.insightsOrder
        }) else { return nil }

        var fastestTotal: BestTimeOfDay.Total?
        let measurable = totals.filter { $0.speedSamples >= BestTimeOfDay.minimumSpeedSamples && $0.wpm != nil }
        var otherWPM: Double?
        if measurable.count >= 2,
           let best = measurable.max(by: { ($0.wpm ?? 0) != ($1.wpm ?? 0) ? ($0.wpm ?? 0) < ($1.wpm ?? 0) : $0.daypart.insightsOrder > $1.daypart.insightsOrder }),
           let bestWPM = best.wpm {
            let rest = timed.filter { $0.daypart != best.daypart && $0.wpm != nil }
            let restMinutes = rest.reduce(0) { $0 + $1.minutes }
            if rest.count >= BestTimeOfDay.minimumSpeedSamples, restMinutes > 0 {
                let restWPM = rest.reduce(0) { $0 + $1.words } / restMinutes
                if restWPM > 0, bestWPM >= restWPM * (1 + BestTimeOfDay.minimumLead) {
                    fastestTotal = best
                    otherWPM = restWPM
                }
            }
        }

        let consistent = slot(for: consistentTotal, in: grouped[consistentTotal.daypart] ?? [])
        let fastest = fastestTotal.map { slot(for: $0, in: grouped[$0.daypart] ?? []) }
        let reason = bestTimeReason(
            consistent: consistent, fastest: fastest, otherWPM: otherWPM,
            sessionCount: timed.count, hasSpeedEvidence: measurable.count >= 2
        )
        return BestTimeOfDay(
            consistent: consistent,
            fastest: fastest,
            reason: reason,
            sessionCount: timed.count,
            readingDays: dayCount,
            dayparts: totals
        )
    }

    /// A two-hour window around the busiest hour of a stretch, leaning toward the busier neighbour.
    private func slot(for total: BestTimeOfDay.Total, in sittings: [Sitting]) -> BestTimeOfDay.Slot {
        var minutesByHour = [Double](repeating: 0, count: 24)
        for sitting in sittings { minutesByHour[sitting.hour] += sitting.minutes }
        var peak = 0
        for hour in 0..<24 where minutesByHour[hour] > minutesByHour[peak] + 1e-9 { peak = hour }
        let before = minutesByHour[(peak + 23) % 24]
        let after = minutesByHour[(peak + 1) % 24]
        let start = after >= before ? peak : (peak + 23) % 24
        return BestTimeOfDay.Slot(
            daypart: total.daypart,
            startHour: start,
            endHour: (start + 2) % 24,
            sessions: total.sessions,
            minutes: total.minutes,
            minuteShare: total.minuteShare,
            wpm: total.wpm
        )
    }

    private func bestTimeReason(consistent: BestTimeOfDay.Slot, fastest: BestTimeOfDay.Slot?, otherWPM: Double?, sessionCount: Int, hasSpeedEvidence: Bool) -> String {
        let percent = Int((consistent.minuteShare * 100).rounded())
        let window = BestTimeOfDay.windowText(startHour: consistent.startHour, endHour: consistent.endHour)
        var text = "You read most \(BestTimeOfDay.phrase(for: consistent.daypart)): \(consistent.sessions) of your \(sessionCount) timed sittings and \(percent)% of your minutes, mostly from \(window)."
        guard hasSpeedEvidence else {
            return text + " There isn’t enough pacing data yet to say when you read fastest."
        }
        guard let fastest, let wpm = fastest.wpm, let other = otherWPM else {
            return text + " Your speed is about the same whenever you sit down."
        }
        let wpmText = Int(wpm.rounded())
        let otherText = Int(other.rounded())
        if fastest.daypart == consistent.daypart {
            text += " It is also when you read fastest, about \(wpmText) words a minute against \(otherText) the rest of the day."
        } else {
            text += " You read fastest \(BestTimeOfDay.phrase(for: fastest.daypart)), about \(wpmText) words a minute against \(otherText) otherwise."
        }
        return text
    }
}

extension Daypart {
    /// Position in the order dayparts are listed, for stable tie-breaks.
    fileprivate var insightsOrder: Int { Daypart.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Speed trend

/// How the reader's speed (words per minute) has moved over time, from timed sessions only.
struct SpeedTrend: Hashable, Sendable {
    enum Label: String, Sendable {
        /// Fewer than eight timed sittings in the last year, or they span under three weeks.
        case notEnoughData
        case faster, steady, slower
    }

    struct Point: Hashable, Identifiable, Sendable {
        var date: Date
        /// Average of this sitting and the six before it.
        var wpm: Double
        /// This sitting on its own.
        var sessionWPM: Double

        var id: Date { date }
    }

    /// Rolling averages over every measurable sitting, oldest first, thinned to the requested size.
    var points: [Point]
    /// Measurable timed sittings in all of history.
    var sampleCount: Int
    /// Change in words per minute per month over the last twelve months (0 when `label` is `notEnoughData`).
    var slopePerMonth: Double
    /// The latest rolling average.
    var currentWPM: Double?
    var label: Label
    /// A plain, kind sentence about the trend.
    var sentence: String

    static let window = 7
    static let minimumSamples = 8
    static let minimumSpanDays = 21
    /// The shift over the period that counts as real, as a share of the average speed.
    static let minimumChange = 0.03
}

extension InsightsEngine {
    /// The reader's speed over time. The label looks at the last twelve months: faster or slower only when the line
    /// is clearly sloped (two standard errors from flat) and the shift is at least 3% of their average speed.
    func speedTrend(maxPoints: Int = 90) -> SpeedTrend {
        let samples = sittings.filter { $0.wpm != nil }
        let rolled = rollingPoints(samples)
        let points = thin(rolled, to: maxPoints)

        let recentStart = addDays(-364, to: today)
        let recent = samples.filter { $0.day >= recentStart && $0.day <= today }
        guard recent.count >= SpeedTrend.minimumSamples, let first = recent.first, let last = recent.last,
              last.start.timeIntervalSince(first.start) >= Double(SpeedTrend.minimumSpanDays) * 86_400 else {
            return SpeedTrend(
                points: points, sampleCount: samples.count, slopePerMonth: 0, currentWPM: rolled.last?.wpm,
                label: .notEnoughData,
                sentence: "Time a few more sittings and your speed trend will appear here."
            )
        }

        let monthSeconds = 30.4375 * 86_400
        let typical = InsightsMath.median(recent.compactMap(\.wpm))
        // Clamp outliers so one distracted or skimmed session cannot tilt the line.
        let x = recent.map { $0.start.timeIntervalSince(first.start) / monthSeconds }
        let y = recent.map { min(typical * 2, max(typical * 0.5, $0.wpm ?? typical)) }
        guard let fit = InsightsMath.linearFit(x: x, y: y) else {
            return SpeedTrend(
                points: points, sampleCount: samples.count, slopePerMonth: 0, currentWPM: rolled.last?.wpm,
                label: .steady, sentence: steadySentence(rolled.last?.wpm)
            )
        }

        let span = x.last ?? 0
        let average = InsightsMath.mean(y)
        let change = average > 0 ? fit.slope * span / average : 0
        let label: SpeedTrend.Label
        if abs(fit.tStatistic) >= 2, abs(change) >= SpeedTrend.minimumChange {
            label = fit.slope > 0 ? .faster : .slower
        } else {
            label = .steady
        }

        let sentence: String
        let perMonth = Int(abs(fit.slope).rounded())
        switch label {
        case .faster:
            sentence = perMonth >= 1
                ? "You’re getting faster: about \(perMonth) more words a minute each month."
                : "You’re getting a little faster each month."
        case .slower:
            sentence = perMonth >= 1
                ? "Your pace has eased by about \(perMonth) words a minute each month. Slower is often just a richer book."
                : "Your pace has eased a little. Slower is often just a richer book."
        case .steady, .notEnoughData:
            sentence = steadySentence(rolled.last?.wpm)
        }
        return SpeedTrend(
            points: points, sampleCount: samples.count, slopePerMonth: fit.slope, currentWPM: rolled.last?.wpm,
            label: label, sentence: sentence
        )
    }

    private func steadySentence(_ wpm: Double?) -> String {
        guard let wpm else { return "Your speed has held steady." }
        return "Your speed has held steady at about \(Int(wpm.rounded())) words a minute."
    }

    private func rollingPoints(_ samples: [Sitting]) -> [SpeedTrend.Point] {
        guard samples.count >= 3 else { return [] }
        var result: [SpeedTrend.Point] = []
        result.reserveCapacity(samples.count)
        var running = 0.0
        for (index, sample) in samples.enumerated() {
            let value = sample.wpm ?? 0
            running += value
            if index >= SpeedTrend.window { running -= samples[index - SpeedTrend.window].wpm ?? 0 }
            guard index >= 2 else { continue }
            let count = min(index + 1, SpeedTrend.window)
            result.append(SpeedTrend.Point(date: sample.start, wpm: running / Double(count), sessionWPM: value))
        }
        return result
    }

    /// Keeps the first and last points and spreads the rest evenly.
    private func thin(_ points: [SpeedTrend.Point], to limit: Int) -> [SpeedTrend.Point] {
        guard limit > 0 else { return [] }
        guard points.count > limit else { return points }
        if limit == 1 { return Array(points.suffix(1)) }
        return (0..<limit).map { step in
            points[Int((Double(step) * Double(points.count - 1) / Double(limit - 1)).rounded())]
        }
    }
}
