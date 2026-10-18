import Foundation

/// Where a tea ritual is, from the first pour to the stretch.
enum TeaRitualStage: String, Codable, Sendable {
    case steeping, reading, stretching, done
}

/// A tea ritual as a plan: steep the tea, read for one cup, then stretch. The steep happens before the reading
/// session begins, never inside it, so the session’s seconds are reading seconds and the reader’s pace stays honest.
struct TeaRitual: Codable, Hashable, Sendable {
    var teaID: String
    var teaName: String
    var strength: TeaStrength
    var steepSeconds: Int
    /// A cup-length read, from `preferences.cupMinutes`.
    var readSeconds: Int
    /// The stretch break after the read.
    var breakSeconds: Int

    /// Keeps a cup-length read to something a person could mean: a minute at the least, eight hours at the most.
    static let cupMinutesRange = 1...480

    /// Plans the ritual for a tea. `cupMinutes` is `preferences.cupMinutes`.
    static func plan(tea: Tea, strength: TeaStrength = .regular, cupMinutes: Int = 25) -> TeaRitual {
        let minutes = min(cupMinutesRange.upperBound, max(cupMinutesRange.lowerBound, cupMinutes))
        let read = minutes * 60
        return TeaRitual(
            teaID: tea.id,
            teaName: tea.name,
            strength: strength,
            steepSeconds: TeaSuggester.steepSeconds(for: tea, strength: strength),
            readSeconds: read,
            breakSeconds: breakSeconds(forReadSeconds: read)
        )
    }

    /// A fifth of the read, from one to ten minutes: five minutes after a 25 minute cup.
    static func breakSeconds(forReadSeconds read: Int) -> Int {
        min(600, max(60, read / 5))
    }

    /// What a session adopts as `goalSeconds`: the cup-length read.
    var goalSeconds: Double { Double(readSeconds) }

    var totalSeconds: Int { steepSeconds + readSeconds + breakSeconds }

    /// When the tea is ready, if the kettle is poured at `start`.
    func readyAt(poured start: Date) -> Date { start.addingTimeInterval(Double(steepSeconds)) }

    /// The stage `elapsed` seconds after the pour. Negative time counts as the start.
    func stage(afterElapsed elapsed: Double) -> TeaRitualStage {
        let t = max(0, elapsed)
        if t < Double(steepSeconds) { return .steeping }
        if t < Double(steepSeconds + readSeconds) { return .reading }
        if t < Double(totalSeconds) { return .stretching }
        return .done
    }

    /// The live session for the read, to start when the tea is ready. It carries the tea and the cup-length goal, so
    /// the session screen, the Live Activity and the watch all count down the same cup. The caller supplies the id
    /// (a fresh `UUID()`), so nothing in here is random.
    func makeSession(id: UUID, bookID: String, startPage: Int, origin: SessionDevice, now: Date, ambienceID: String? = nil) -> ActiveSession {
        ActiveSession(
            id: id,
            bookID: bookID,
            startedAt: now,
            startPage: startPage,
            origin: origin,
            teaID: teaID,
            goalSeconds: goalSeconds,
            ambienceID: ambienceID
        )
    }
}
