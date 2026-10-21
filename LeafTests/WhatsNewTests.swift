import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

struct AppBuildTests {
    @Test func versionsCompareAsNumbersPartByPart() {
        #expect(AppBuild(version: "1.9", build: "1") < AppBuild(version: "1.10", build: "1"))
        #expect(AppBuild(version: "1.0", build: "5") == AppBuild(version: "1.0.0", build: "5"))
        #expect(AppBuild(version: "2.0", build: "1") > AppBuild(version: "1.99", build: "999"))
        #expect(!(AppBuild(version: "1.0", build: "7") < AppBuild(version: "1.0", build: "7")))
    }

    @Test func buildsOfOneVersionCompareAsNumbers() {
        let older = AppBuild(version: "1.0", build: "202610201200")
        let newer = AppBuild(version: "1.0", build: "202610211200")
        #expect(older < newer)
        #expect(AppBuild(version: "1.0", build: "9") < AppBuild(version: "1.0", build: "10"))
        // Not numbers: compared as text, and still consistent.
        #expect(AppBuild(version: "1.0", build: "a") < AppBuild(version: "1.0", build: "b"))
        #expect(AppBuild(version: "1.0", build: "202610201200").label == "1.0 (202610201200)")
        #expect(AppBuild(version: "1.0", build: "").label == "1.0")
    }

    @Test func aBuildSurvivesBeingSaved() throws {
        let build = AppBuild(version: " 1.2 ", build: "42")
        let data = try JSONEncoder().encode(build)
        let back = try JSONDecoder().decode(AppBuild.self, from: data)
        #expect(back == build)
        #expect(back.version == "1.2")
    }
}

struct WhatsNewGateTests {
    private let releases = ["2026-11", "2026-10"]
    private let october = AppBuild(version: "1.0", build: "202610010000")
    private let november = AppBuild(version: "1.0", build: "202611010000")

    @Test func aFreshInstallShowsNothingAndRemembersEverythingAsSeen() {
        let shown = WhatsNewGate.releasesToShow(current: november, state: nil, hasOnboarded: false, releaseIDs: releases)
        #expect(shown.isEmpty)
        let state = WhatsNewGate.remember(current: november, state: nil, shown: shown, hasOnboarded: false, releaseIDs: releases)
        #expect(state.lastBuild == november)
        #expect(state.shownReleases == releases)
        // Onboarding done, next launch of the same build: still nothing.
        let later = WhatsNewGate.releasesToShow(current: november, state: state, hasOnboarded: true, releaseIDs: releases)
        #expect(later.isEmpty)
    }

    @Test func anUpdateFromBeforeWhatsNewShowsOnlyTheNewestRelease() {
        let shown = WhatsNewGate.releasesToShow(current: november, state: nil, hasOnboarded: true, releaseIDs: releases)
        #expect(shown == ["2026-11"])
        let state = WhatsNewGate.remember(current: november, state: nil, shown: shown, hasOnboarded: true, releaseIDs: releases)
        #expect(state.shownReleases == ["2026-11"])
        #expect(WhatsNewGate.releasesToShow(current: november, state: state, hasOnboarded: true, releaseIDs: releases).isEmpty)
    }

    @Test func anUpdateShowsEveryReleaseNotYetShownOnce() {
        let before = WhatsNewGate.State(lastBuild: october, shownReleases: ["2026-10"])
        let shown = WhatsNewGate.releasesToShow(current: november, state: before, hasOnboarded: true, releaseIDs: releases)
        #expect(shown == ["2026-11"])
        let after = WhatsNewGate.remember(current: november, state: before, shown: shown, hasOnboarded: true, releaseIDs: releases)
        #expect(after.shownReleases == ["2026-10", "2026-11"])
        #expect(WhatsNewGate.releasesToShow(current: november, state: after, hasOnboarded: true, releaseIDs: releases).isEmpty)
    }

    @Test func aBuildWithNoNewReleaseOrAnOlderBuildShowsNothing() {
        let seen = WhatsNewGate.State(lastBuild: october, shownReleases: releases)
        #expect(WhatsNewGate.releasesToShow(current: november, state: seen, hasOnboarded: true, releaseIDs: releases).isEmpty)
        let ahead = WhatsNewGate.State(lastBuild: november, shownReleases: ["2026-10"])
        #expect(WhatsNewGate.releasesToShow(current: october, state: ahead, hasOnboarded: true, releaseIDs: releases).isEmpty)
        #expect(WhatsNewGate.releasesToShow(current: november, state: ahead, hasOnboarded: true, releaseIDs: releases).isEmpty)
        #expect(WhatsNewGate.releasesToShow(current: november, state: nil, hasOnboarded: true, releaseIDs: []).isEmpty)
    }
}

struct TourProgressTests {
    private let steps = [
        TourStep(id: "today.nook", area: .today, title: "", text: ""),
        TourStep(id: "today.steep", area: .today, title: "", text: ""),
        TourStep(id: "library.shelves", area: .library, title: "", text: ""),
        TourStep(id: "settings.times", area: .settings, title: "", text: "", canFloat: true),
    ]

    @Test func nothingShowsUntilTheTourStarts() {
        let progress = TourProgress()
        #expect(progress.nextStep(in: .today, steps: steps, available: ["today.nook", "today.steep"]) == nil)
        #expect(progress.remaining(in: .today, steps: steps).isEmpty)
    }

    @Test func stepsShowInOrderOneAtATimeWhenTheirTargetIsOnScreen() {
        var progress = TourProgress()
        progress.start()
        let all: Set<String> = ["today.nook", "today.steep"]
        #expect(progress.nextStep(in: .today, steps: steps, available: all)?.id == "today.nook")
        // The first step's target is off screen: the second waits rather than jumping ahead.
        #expect(progress.nextStep(in: .today, steps: steps, available: ["today.steep"]) == nil)
        progress.advance(past: "today.nook", steps: steps)
        #expect(progress.nextStep(in: .today, steps: steps, available: all)?.id == "today.steep")
        progress.advance(past: "today.steep", steps: steps)
        #expect(progress.nextStep(in: .today, steps: steps, available: all) == nil)
        // A step that can float shows without its target.
        #expect(progress.nextStep(in: .settings, steps: steps, available: [])?.id == "settings.times")
        #expect(progress.isRunning)
    }

    @Test func skippingStopsItAndOnlyAReplayBringsItBack() {
        var progress = TourProgress()
        progress.start()
        progress.markSeen("today.nook")
        progress.skip()
        #expect(progress.nextStep(in: .today, steps: steps, available: ["today.steep"]) == nil)
        progress.start()
        #expect(progress.seen.isEmpty)
        #expect(progress.nextStep(in: .today, steps: steps, available: ["today.nook"])?.id == "today.nook")
    }

    @Test func seeingTheLastStepEndsTheTour() {
        var progress = TourProgress()
        progress.start()
        for step in steps { progress.advance(past: step.id, steps: steps) }
        #expect(!progress.isRunning)
        let remaining = progress.remaining(in: .library, steps: steps)
        #expect(remaining.isEmpty)
    }

    @Test func voiceOverHearsTheAreaAsOneOrderedList() {
        var progress = TourProgress()
        progress.start()
        progress.markSeen("today.nook")
        let ids: [String] = progress.remaining(in: .today, steps: steps).map { $0.id }
        #expect(ids == ["today.steep"])
    }
}
