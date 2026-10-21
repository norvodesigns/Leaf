import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

private let ltNow = Date(timeIntervalSince1970: 1_800_000_000)

private func ltReading(started minutesAgo: Double, goal: Double? = 25 * 60, pausedAt: Double? = nil, origin: LiveTimer.Origin = .watch, session: UUID? = nil) -> LiveTimer {
    LiveTimer(
        kind: .reading, origin: origin, sessionID: session, start: ltNow.addingTimeInterval(-minutesAgo * 60),
        pausedElapsed: pausedAt, goalSeconds: goal, title: "The Hobbit", teaName: nil
    )
}

private func ltSteep(started secondsAgo: Double, steep: Double = 240, origin: LiveTimer.Origin = .watch) -> LiveTimer {
    LiveTimer(
        kind: .steep, origin: origin, sessionID: nil, start: ltNow.addingTimeInterval(-secondsAgo),
        pausedElapsed: nil, goalSeconds: steep, title: nil, teaName: "Earl Grey"
    )
}

struct LiveTimerTests {
    @Test func aRunningSessionCountsTowardItsGoalThenReachesIt() {
        let timer = ltReading(started: 10)
        #expect(timer.state(at: ltNow) == .running)
        let goal = ltNow.addingTimeInterval(15 * 60)
        #expect(timer.goalDate == goal)
        #expect(timer.state(at: goal) == .reached)
        let phases = timer.phases(from: ltNow)
        let states: [LiveTimer.State] = phases.map { $0.state }
        #expect(states == [.running, .reached, .reached])
        #expect(phases[1].from == goal)
        let first: Double = phases[0].relevance
        let settled: Double = phases[2].relevance
        #expect(first == 1)
        #expect(settled < first)
    }

    @Test func aPausedSessionHoldsItsTimeAndHasNoGoalDate() {
        let timer = ltReading(started: 30, pausedAt: 600)
        #expect(timer.isPaused)
        #expect(timer.goalDate == nil)
        #expect(timer.elapsed(at: ltNow) == 600)
        #expect(timer.state(at: ltNow) == .paused)
        let phases = timer.phases(from: ltNow)
        #expect(phases.count == 1)
        let relevance: Double = phases[0].relevance
        #expect(relevance > 0 && relevance < 1)
    }

    @Test func anOpenEndedSessionJustRuns() {
        let timer = ltReading(started: 5, goal: nil)
        #expect(timer.goalDate == nil)
        #expect(timer.phases(from: ltNow).count == 1)
        #expect(ltReading(started: 5, goal: -3).goalDate == nil)
    }

    @Test func aSteepIsReadyAtItsTimeThenGoesCold() {
        let timer = ltSteep(started: 60)
        let ready = ltNow.addingTimeInterval(180)
        #expect(timer.goalDate == ready)
        #expect(timer.state(at: ready) == .reached)
        #expect(timer.expiresAt == ready.addingTimeInterval(LiveTimer.teaGoesCold))
        let phases = timer.phases(from: ltNow)
        let readiness: Double = phases[1].relevance
        #expect(readiness == 1)
        // Cold tea is gone from the face.
        #expect(timer.isExpired(at: timer.expiresAt))
        #expect(timer.phases(from: timer.expiresAt).isEmpty)
    }

    @Test func aForgottenTimerNeverLingers() {
        let timer = ltReading(started: 9 * 60)
        #expect(timer.isExpired(at: ltNow))
        #expect(timer.phases(from: ltNow).isEmpty)
        let recent = ltReading(started: 60)
        let left: TimeInterval = recent.expiresAt.timeIntervalSince(ltNow)
        #expect(left == LiveTimer.forgottenReading - 3600)
    }

    @Test func aTimerSurvivesBeingSaved() throws {
        let timer = ltReading(started: 3, pausedAt: 120, session: UUID())
        let data = try JSONEncoder().encode(timer)
        let back = try JSONDecoder().decode(LiveTimer.self, from: data)
        #expect(back == timer)
    }
}

struct LiveTimerRulesTests {
    @Test func theMirroredLiveActivityIsTheOnlyCardWhenThePhoneHasOne() {
        let session = UUID()
        let phoneStarted = ltReading(started: 2, origin: .phone, session: session)
        #expect(!LiveTimerRules.watchShowsCard(for: phoneStarted, phoneActivitySessionID: session))
        // The phone has no Live Activity for it (they're off, or it couldn't start one): the watch shows its own.
        #expect(LiveTimerRules.watchShowsCard(for: phoneStarted, phoneActivitySessionID: nil))
        #expect(LiveTimerRules.watchShowsCard(for: phoneStarted, phoneActivitySessionID: UUID()))
        let watchStarted = ltReading(started: 2, origin: .watch, session: session)
        #expect(!LiveTimerRules.watchShowsCard(for: watchStarted, phoneActivitySessionID: session))
        #expect(LiveTimerRules.watchShowsCard(for: watchStarted, phoneActivitySessionID: nil))
    }

    @Test func aSteepBelongsToTheDeviceItStartedOn() {
        #expect(LiveTimerRules.watchShowsCard(for: ltSteep(started: 10, origin: .watch), phoneActivitySessionID: nil))
        #expect(!LiveTimerRules.watchShowsCard(for: ltSteep(started: 10, origin: .phone), phoneActivitySessionID: nil))
    }
}
