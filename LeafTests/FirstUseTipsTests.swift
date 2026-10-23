import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct FirstUseTipsTests {
    private let first = "launch-1"
    private let second = "launch-2"

    @Test func everyTipHasWordsAPlaceAndASymbol() {
        for tip in FirstUseTip.allCases {
            #expect(!tip.title.isEmpty)
            #expect(!tip.message.isEmpty)
            #expect(!tip.symbol.isEmpty)
            #expect(tip.place.tips.contains(tip))
            // Short enough to read at a glance.
            #expect(tip.message.count <= 120, "\(tip.rawValue) is \(tip.message.count) characters")
        }
        // Every place has something to say.
        for place in FirstUsePlace.allCases {
            #expect(!place.tips.isEmpty)
        }
    }

    @Test func theTimerTeachesTheSceneBeforeTuckingItAway() {
        #expect(FirstUsePlace.session.tips == [.sessionNook, .sessionMinimize])
        var journal = FirstUseJournal()
        #expect(journal.next(at: .session, launch: first) == .sessionNook)
        journal.finish(.sessionNook)
        #expect(journal.next(at: .session, launch: first) == .sessionMinimize)
        journal.finish(.sessionMinimize)
        #expect(journal.next(at: .session, launch: first) == nil)
    }

    @Test func aTipShowsOnThreeLaunchesThenStopsAsking() {
        var journal = FirstUseJournal()
        for launch in ["a", "b", "c"] {
            #expect(journal.next(at: .library, launch: launch) == .libraryAdd)
            journal.noteShown(.libraryAdd, launch: launch)
            // Seen again on the same launch: still one launch.
            journal.noteShown(.libraryAdd, launch: launch)
            #expect(journal.next(at: .library, launch: launch) == .libraryAdd)
        }
        #expect(journal.entry(.libraryAdd).launches == 3)
        #expect(journal.next(at: .library, launch: "d") == nil)
        #expect(!journal.isDone(.libraryAdd))
    }

    @Test func aRetiredTipMakesWayForTheNextAtItsPlace() {
        var journal = FirstUseJournal()
        for launch in ["a", "b", "c"] { journal.noteShown(.sessionNook, launch: launch) }
        #expect(journal.next(at: .session, launch: "d") == .sessionMinimize)
    }

    @Test func closingATipEndsItForGood() {
        var journal = FirstUseJournal()
        journal.noteShown(.todayStart, launch: first)
        journal.finish(.todayStart)
        #expect(journal.isDone(.todayStart))
        #expect(journal.next(at: .today, launch: first) == nil)
        #expect(journal.next(at: .today, launch: second) == nil)
        // Showing it again after it's done changes nothing.
        journal.noteShown(.todayStart, launch: second)
        #expect(journal.entry(.todayStart).launches == 1)
    }

    @Test func aPlaceShowsOneTipAndTheNextWaitsForTheNextVisit() {
        var journal = FirstUseJournal()
        var stage = FirstUseStage()
        // Both of the timer's notes come on screen; only the first goes out, whichever arrives first.
        let minimizeFirst = stage.arrive(.sessionMinimize, journal: journal, launch: first)
        #expect(!minimizeFirst)
        let nookOut = stage.arrive(.sessionNook, journal: journal, launch: first)
        #expect(nookOut)
        journal.noteShown(.sessionNook, launch: first)
        #expect(stage.isShowing(.sessionNook, journal: journal))
        #expect(!stage.isShowing(.sessionMinimize, journal: journal))

        // Closed: gone, and the next one doesn't take its place on this visit.
        journal.finish(.sessionNook)
        #expect(!stage.isShowing(.sessionNook, journal: journal))
        let minimizeSameVisit = stage.arrive(.sessionMinimize, journal: journal, launch: first)
        #expect(!minimizeSameVisit)

        // The next visit.
        stage.leave(.sessionMinimize)
        stage.leave(.sessionNook)
        let minimizeNextVisit = stage.arrive(.sessionMinimize, journal: journal, launch: first)
        #expect(minimizeNextVisit)
        #expect(stage.isShowing(.sessionMinimize, journal: journal))
    }

    @Test func placesDontWaitForEachOther() {
        let journal = FirstUseJournal()
        var stage = FirstUseStage()
        let todayOut = stage.arrive(.todayStart, journal: journal, launch: first)
        #expect(todayOut)
        let libraryOut = stage.arrive(.libraryAdd, journal: journal, launch: first)
        #expect(libraryOut)
        // Leaving with someone else's tip out frees nothing.
        stage.leave(.planTimes)
        #expect(stage.isShowing(.todayStart, journal: journal))
        #expect(stage.isShowing(.libraryAdd, journal: journal))
    }

    @Test func screenshotRunsShowOnlyTheTipsTheyName() {
        let journal = FirstUseJournal.only([.sessionNook])
        #expect(journal.next(at: .session, launch: first) == .sessionNook)
        for place in FirstUsePlace.allCases where place != .session {
            #expect(journal.next(at: place, launch: first) == nil)
        }
        #expect(FirstUseJournal.only([]).next(at: .session, launch: first) == nil)
    }

    @Test func showTipsAgainStartsFresh() throws {
        var journal = FirstUseJournal()
        #expect(journal.isFresh)
        journal.noteShown(.youCorner, launch: first)
        #expect(!journal.isFresh)
        journal.finish(.youCorner)
        let data = try JSONEncoder().encode(journal)
        let back = try JSONDecoder().decode(FirstUseJournal.self, from: data)
        #expect(back == journal)
        #expect(back.isDone(.youCorner))
        #expect(FirstUseJournal().next(at: .you, launch: second) == .youCorner)
    }
}
