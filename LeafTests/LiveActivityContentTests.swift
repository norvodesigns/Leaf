#if !canImport(LeafCore)
import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

@Suite struct LiveActivityContentTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func content(
        paused: Bool = false, elapsed: Int = 0, goal: Int? = nil, state: ReadingActivityState = .reading
    ) -> ReadingActivityContent {
        ReadingActivityContent(timerStart: start, isPaused: paused, pausedElapsedSeconds: elapsed, goalSeconds: goal, currentPage: 12, state: state)
    }

    @Test func countdownRangeEndsAtTheGoal() {
        let c = content(goal: 1500)
        #expect(c.countsDown)
        #expect(c.timerRange.lowerBound == start)
        #expect(c.timerRange.upperBound == start.addingTimeInterval(1500))
    }

    @Test func openEndedCountsUpOverABoundedRange() {
        let c = content(goal: nil)
        #expect(!c.countsDown)
        #expect(c.timerRange.upperBound.timeIntervalSince(start) == ReadingActivityContent.longestTimerSeconds)
    }

    @Test func reachedAndFinishingCountUp() {
        #expect(!content(goal: 600, state: .goalReached).countsDown)
        #expect(!content(goal: 600, state: .finishing).countsDown)
        #expect(content(goal: 600, state: .paused).countsDown)
    }

    @Test func nonsenseGoalsFallBackToCountingUp() {
        for goal in [0, -5, Int.min] {
            let c = content(goal: goal)
            #expect(!c.countsDown)
            #expect(c.timerRange.lowerBound <= c.timerRange.upperBound)
        }
    }

    @Test func hugeGoalIsClamped() {
        let c = content(goal: Int.max)
        #expect(c.timerRange.upperBound.timeIntervalSince(start) == ReadingActivityContent.longestTimerSeconds)
    }

    @Test func pauseDateOnlyWhilePaused() {
        #expect(content(paused: false, elapsed: 300, goal: 900).pauseDate == nil)
        #expect(content(paused: true, elapsed: 300, goal: 900).pauseDate == start.addingTimeInterval(300))
    }

    @Test func pauseDateStaysInsideTheRange() {
        for elapsed in [-100, 0, 1, 899, 900, 901, 1_000_000, Int.max] {
            for goal in [nil, 0, 900, Int.max] as [Int?] {
                let c = content(paused: true, elapsed: elapsed, goal: goal)
                guard let pause = c.pauseDate else { Issue.record("paused content had no pause date"); continue }
                #expect(c.timerRange.contains(pause))
            }
        }
    }

    @Test func rangeIsAlwaysValidForAnyStart() {
        for date in [Date.distantPast, Date(timeIntervalSince1970: 0), start, Date.distantFuture] {
            let c = ReadingActivityContent(timerStart: date, currentPage: 1)
            #expect(c.timerRange.lowerBound <= c.timerRange.upperBound)
        }
    }

    @Test func codableRoundTripKeepsEverything() throws {
        let c = content(paused: true, elapsed: 321, goal: 1200, state: .paused)
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(ReadingActivityContent.self, from: data) == c)
        #expect(data.count < 400)
    }

    @Test func stateRawValuesAreStable() {
        #expect(ReadingActivityState.allRawValuesForTest == ["reading", "paused", "goalReached", "finishing", "steeping", "teaReady"])
    }
}

private extension ReadingActivityState {
    static var allRawValuesForTest: [String] {
        [ReadingActivityState.reading, .paused, .goalReached, .finishing, .steeping, .teaReady].map(\.rawValue)
    }
}
#endif
