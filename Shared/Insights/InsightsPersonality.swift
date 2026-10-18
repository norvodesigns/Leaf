import Foundation

/// A fun, shareable reading archetype, chosen by rules from how and when the reader reads. It is a mirror, not a
/// verdict: every archetype is flattering, and every number behind it is shown.
struct ReadingPersonality: Hashable, Sendable {
    enum Archetype: String, CaseIterable, Sendable {
        case eveningSteeper, earlyBird, nightOwl, lunchBreakReader, teatimeRegular
        case weekendBinger, steadySipper, marathoner, nibbler
        case sampler, completionist, wanderer, genreLoyalist
        /// Enough history, but no strong pattern. A warm default.
        case cozyReader
        /// Not enough history yet.
        case freshPage

        var title: String {
            switch self {
            case .eveningSteeper: return "The Evening Steeper"
            case .earlyBird: return "The Early Bird"
            case .nightOwl: return "The Night Owl"
            case .lunchBreakReader: return "The Lunch-Break Reader"
            case .teatimeRegular: return "The Teatime Regular"
            case .weekendBinger: return "The Weekend Binger"
            case .steadySipper: return "The Steady Sipper"
            case .marathoner: return "The Marathoner"
            case .nibbler: return "The Nibbler"
            case .sampler: return "The Sampler"
            case .completionist: return "The Completionist"
            case .wanderer: return "The Wanderer"
            case .genreLoyalist: return "The Genre Loyalist"
            case .cozyReader: return "The Cozy Reader"
            case .freshPage: return "The Fresh Page"
            }
        }

        var blurb: String {
            switch self {
            case .eveningSteeper: return "Your best pages come after the day has settled, with the lamp on and the tea at the right temperature."
            case .earlyBird: return "You read while the house is still quiet, and the day starts with a book instead of a screen."
            case .nightOwl: return "The later it gets, the better the book gets, and bedtime is more of a suggestion."
            case .lunchBreakReader: return "You carve a chapter out of the middle of the day and go back to work a little calmer."
            case .teatimeRegular: return "Four o’clock means a cup and a chapter, and you keep that appointment."
            case .weekendBinger: return "Weekdays are for waiting; the weekend is when you sink in for hours at a time."
            case .steadySipper: return "Little and often, nearly every day: a rhythm that quietly adds up to a lot of books."
            case .marathoner: return "When you sit down you really sit down, and an hour disappears before you look up."
            case .nibbler: return "A few pages here and a few there: you fit reading into every spare corner of the day."
            case .sampler: return "You like to taste widely, with a lot of books open at once and plenty of curiosity to go around."
            case .completionist: return "If you start a book, you finish it, and the finished shelf shows it."
            case .wanderer: return "No two books in a row feel alike; your shelf is a map of everywhere you have been curious about."
            case .genreLoyalist: return "You know what you love and you go back to it, and you have read your corner of the library deeply."
            case .cozyReader: return "No single habit defines you yet; you simply read when it feels right, which is the best way."
            case .freshPage: return "Your reading story is just beginning, and a few more sittings will bring your archetype into focus."
            }
        }
    }

    /// One number that shows why this archetype was picked.
    struct Evidence: Hashable, Sendable {
        var key: String
        var value: Double
        /// "78% of your reading starts after 5:30 pm".
        var text: String
    }

    var archetype: Archetype
    var title: String
    /// One sentence.
    var blurb: String
    var evidence: [Evidence]
    /// How strongly the rules matched, 0 to 1. Zero for the two defaults.
    var score: Double
    /// The next best match, when there is one.
    var runnerUp: Archetype?
    /// True for the gentle defaults used when there is too little history or no strong pattern.
    var isDefault: Bool

    /// The least a rule's score may be for its archetype to be chosen.
    static let minimumScore = 0.2
    static let minimumSessions = 8
    static let minimumReadDays = 4
}

/// What the rules look at, worked out once.
private struct PersonalityFacts {
    var sessions = 0
    var readDays = 0
    var minutes = 0.0
    var timedMinutes = 0.0
    var daypartMinutes: [Daypart: Double] = [:]
    var weekendMinutes = 0.0
    var weekendDays = 0
    var weekdayMinutes = 0.0
    var weekdayDays = 0
    var medianSession = 0.0
    var adherence = 0.0
    var scheduledDaysObserved = 0
    var dailyVariation = 0.0
    var finished = 0
    var open = 0
    var topGenreShare = 0.0
    var topGenreName = ""
    var distinctGenres = 0

    func share(of parts: [Daypart]) -> Double {
        guard timedMinutes > 0 else { return 0 }
        return parts.reduce(0) { $0 + (daypartMinutes[$1] ?? 0) } / timedMinutes
    }

    var weekendShare: Double { minutes > 0 ? weekendMinutes / minutes : 0 }
    var finishRate: Double { finished + open > 0 ? Double(finished) / Double(finished + open) : 0 }
}

extension InsightsEngine {
    /// The reader's archetype. Looks at the last twelve months of sittings and at the whole library. With fewer than
    /// eight sittings on four days (and no library pattern) it returns a gentle default instead.
    func personality() -> ReadingPersonality {
        let facts = personalityFacts()
        let hasSessions = facts.sessions >= ReadingPersonality.minimumSessions && facts.readDays >= ReadingPersonality.minimumReadDays

        var scored: [(ReadingPersonality.Archetype, Double)] = []
        for archetype in ReadingPersonality.Archetype.allCases {
            let score = personalityScore(archetype, facts, hasSessions: hasSessions)
            if score >= ReadingPersonality.minimumScore { scored.append((archetype, score)) }
        }
        // Highest score wins; ties go to the archetype listed first, so the answer never depends on hashing order.
        let order = ReadingPersonality.Archetype.allCases
        scored.sort { lhs, rhs in
            abs(lhs.1 - rhs.1) > 1e-9 ? lhs.1 > rhs.1 : (order.firstIndex(of: lhs.0) ?? 0) < (order.firstIndex(of: rhs.0) ?? 0)
        }

        guard let best = scored.first else {
            let fallback: ReadingPersonality.Archetype = hasSessions ? .cozyReader : .freshPage
            return ReadingPersonality(
                archetype: fallback, title: fallback.title, blurb: fallback.blurb,
                evidence: defaultEvidence(facts), score: 0, runnerUp: nil, isDefault: true
            )
        }
        return ReadingPersonality(
            archetype: best.0, title: best.0.title, blurb: best.0.blurb,
            evidence: personalityEvidence(best.0, facts), score: best.1,
            runnerUp: scored.dropFirst().first?.0, isDefault: false
        )
    }

    private func personalityFacts() -> PersonalityFacts {
        var facts = PersonalityFacts()
        let start = addDays(-364, to: today)
        let window = sittings(from: start, through: today).filter(\.countsAsReading)
        facts.sessions = window.count
        facts.minutes = window.reduce(0) { $0 + $1.minutes }

        var perDay: [Date: Double] = [:]
        var weekendDays = Set<Date>()
        var weekdayDays = Set<Date>()
        for sitting in window {
            perDay[sitting.day, default: 0] += sitting.minutes
            if sitting.isTimed {
                facts.timedMinutes += sitting.minutes
                facts.daypartMinutes[sitting.daypart, default: 0] += sitting.minutes
            }
            if sitting.weekday == 1 || sitting.weekday == 7 {
                facts.weekendMinutes += sitting.minutes
                weekendDays.insert(sitting.day)
            } else {
                facts.weekdayMinutes += sitting.minutes
                weekdayDays.insert(sitting.day)
            }
        }
        facts.readDays = perDay.count
        facts.weekendDays = weekendDays.count
        facts.weekdayDays = weekdayDays.count
        facts.medianSession = InsightsMath.median(window.map(\.minutes))

        let dailyMinutes = perDay.keys.sorted().compactMap { perDay[$0] }
        let mean = InsightsMath.mean(dailyMinutes)
        if dailyMinutes.count >= 2, mean > 0 {
            let variance = dailyMinutes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(dailyMinutes.count)
            facts.dailyVariation = variance.squareRoot() / mean
        }

        // Adherence: the share of planned days, over the last eight weeks (or since the first sitting), that had reading.
        if let firstDay = window.first?.day {
            let observedStart = max(firstDay, addDays(-55, to: today))
            var scheduled = 0
            var read = 0
            var day = observedStart
            while day <= today {
                let planned = schedule.contains(calendar.component(.weekday, from: day))
                let didRead = perDay[day] != nil
                // Today only counts once the reader has read; the evening is still ahead otherwise.
                if (planned && (day != today || didRead)) { scheduled += 1 }
                if planned && didRead { read += 1 }
                day = addDays(1, to: day)
            }
            facts.scheduledDaysObserved = scheduled
            facts.adherence = scheduled > 0 ? Double(read) / Double(scheduled) : 0
        }

        let finished = data.items.filter { $0.shelf == .finished }
        facts.finished = finished.count
        facts.open = data.items.filter { $0.shelf == .reading || $0.shelf == .paused }.count
        let mix = genreMix()
        facts.distinctGenres = mix.filter { $0.tag != "other" }.count
        if let top = mix.first, top.tag != "other" {
            facts.topGenreShare = top.share
            facts.topGenreName = top.name
        }
        return facts
    }

    private func personalityScore(_ archetype: ReadingPersonality.Archetype, _ f: PersonalityFacts, hasSessions: Bool) -> Double {
        typealias A = ReadingPersonality.Archetype
        let ramp = InsightsMath.ramp
        let timeEvidence = hasSessions && f.timedMinutes >= 120
        switch archetype {
        case .eveningSteeper:
            return timeEvidence ? 0.95 * ramp(f.share(of: [.dusk, .evening]), 0.5, 0.85) : 0
        case .earlyBird:
            return timeEvidence ? 0.95 * ramp(f.share(of: [.dawn, .morning]), 0.5, 0.85) : 0
        case .nightOwl:
            return timeEvidence ? 0.95 * ramp(f.share(of: [.late, .smallHours]), 0.4, 0.75) : 0
        case .lunchBreakReader:
            return timeEvidence ? 0.95 * ramp(f.share(of: [.lunch, .afternoon]), 0.45, 0.8) : 0
        case .teatimeRegular:
            return timeEvidence ? 0.95 * ramp(f.share(of: [.teaTime]), 0.25, 0.6) : 0
        case .weekendBinger:
            guard hasSessions, f.weekendDays >= 3 else { return 0 }
            let weekendPerDay = f.weekendMinutes / Double(f.weekendDays)
            let weekdayPerDay = f.weekdayDays > 0 ? f.weekdayMinutes / Double(f.weekdayDays) : .infinity
            let lift = weekdayPerDay > 0 ? weekendPerDay / weekdayPerDay : .infinity
            return ramp(f.weekendShare, 0.5, 0.8) * ramp(lift, 1.2, 2.5)
        case .steadySipper:
            guard hasSessions, f.scheduledDaysObserved >= 10 else { return 0 }
            return 0.8 * ramp(f.adherence, 0.65, 0.95) * (1 - ramp(f.dailyVariation, 0.6, 1.3))
        case .marathoner:
            return hasSessions ? ramp(f.medianSession, 40, 80) : 0
        case .nibbler:
            guard hasSessions, f.readDays >= 8 else { return 0 }
            return ramp(18 - f.medianSession, 0, 10)
        case .sampler:
            guard f.finished + f.open >= 5 else { return 0 }
            return ramp(Double(f.open), 3, 7) * (1 - ramp(f.finishRate, 0.2, 0.6))
        case .completionist:
            guard f.finished >= 4, f.open <= 2 else { return 0 }
            return ramp(f.finishRate, 0.7, 1.0) * ramp(Double(f.finished), 3, 8)
        case .wanderer:
            guard f.finished >= 5, f.distinctGenres >= 3 else { return 0 }
            return ramp(0.45 - f.topGenreShare, 0, 0.25) * ramp(Double(f.distinctGenres), 3, 6)
        case .genreLoyalist:
            guard f.finished >= 5 else { return 0 }
            return ramp(f.topGenreShare, 0.55, 0.9)
        case .cozyReader, .freshPage:
            return 0
        }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func personalityEvidence(_ archetype: ReadingPersonality.Archetype, _ f: PersonalityFacts) -> [ReadingPersonality.Evidence] {
        typealias E = ReadingPersonality.Evidence
        func share(_ key: String, _ parts: [Daypart], _ words: String) -> [E] {
            let value = f.share(of: parts)
            return [E(key: key, value: value, text: "\(percent(value)) of your timed reading \(words)"), minutesLine(f)]
        }
        switch archetype {
        case .eveningSteeper: return share("eveningShare", [.dusk, .evening], "is between 5:30 pm and 11 pm")
        case .earlyBird: return share("morningShare", [.dawn, .morning], "is between 5 am and 11:30 am")
        case .nightOwl: return share("nightShare", [.late, .smallHours], "is between 11 pm and 5 am")
        case .lunchBreakReader: return share("middayShare", [.lunch, .afternoon], "is between 11:30 am and 4 pm")
        case .teatimeRegular: return share("teatimeShare", [.teaTime], "is between 4 pm and 5:30 pm")
        case .weekendBinger:
            let weekendPerDay = f.weekendDays > 0 ? f.weekendMinutes / Double(f.weekendDays) : 0
            return [
                E(key: "weekendShare", value: f.weekendShare, text: "\(percent(f.weekendShare)) of your minutes are on weekends"),
                E(key: "weekendMinutesPerDay", value: weekendPerDay, text: "\(LeafFormat.duration(minutes: weekendPerDay)) on an average weekend reading day"),
            ]
        case .steadySipper:
            return [
                E(key: "adherence", value: f.adherence, text: "You read on \(percent(f.adherence)) of your planned days lately"),
                E(key: "medianSession", value: f.medianSession, text: "A typical sitting is \(LeafFormat.duration(minutes: f.medianSession))"),
            ]
        case .marathoner:
            return [
                E(key: "medianSession", value: f.medianSession, text: "A typical sitting is \(LeafFormat.duration(minutes: f.medianSession))"),
                minutesLine(f),
            ]
        case .nibbler:
            return [
                E(key: "medianSession", value: f.medianSession, text: "A typical sitting is \(LeafFormat.duration(minutes: f.medianSession))"),
                E(key: "readDays", value: Double(f.readDays), text: "You read on \(f.readDays) different days this past year"),
            ]
        case .sampler:
            return [
                E(key: "open", value: Double(f.open), text: "\(f.open) books on Reading or Paused"),
                E(key: "finishRate", value: f.finishRate, text: "\(f.finished) finished so far"),
            ]
        case .completionist:
            return [
                E(key: "finished", value: Double(f.finished), text: "\(f.finished) books finished"),
                E(key: "finishRate", value: f.finishRate, text: "\(percent(f.finishRate)) of the books you start get finished"),
            ]
        case .wanderer:
            return [
                E(key: "distinctGenres", value: Double(f.distinctGenres), text: "\(f.distinctGenres) different genres finished"),
                E(key: "topGenreShare", value: f.topGenreShare, text: "No genre is more than \(percent(f.topGenreShare)) of your shelf"),
            ]
        case .genreLoyalist:
            return [
                E(key: "topGenreShare", value: f.topGenreShare, text: "\(percent(f.topGenreShare)) of what you finish is \(f.topGenreName)"),
                E(key: "finished", value: Double(f.finished), text: "\(f.finished) books finished"),
            ]
        case .cozyReader, .freshPage:
            return defaultEvidence(f)
        }
    }

    private func minutesLine(_ f: PersonalityFacts) -> ReadingPersonality.Evidence {
        ReadingPersonality.Evidence(key: "minutes", value: f.minutes, text: "\(LeafFormat.duration(minutes: f.minutes)) read over the past year")
    }

    private func defaultEvidence(_ f: PersonalityFacts) -> [ReadingPersonality.Evidence] {
        [
            ReadingPersonality.Evidence(key: "sessions", value: Double(f.sessions), text: "\(f.sessions) sittings on \(f.readDays) days this past year"),
            ReadingPersonality.Evidence(key: "finished", value: Double(f.finished), text: "\(f.finished) books finished"),
        ]
    }
}
