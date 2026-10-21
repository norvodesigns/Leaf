import Foundation

// MARK: - A build

/// The app's marketing version and build number, as Info.plist gives them ("1.0", "202610210530"). TestFlight builds
/// of one version differ only in their build number, so both count.
struct AppBuild: Codable, Hashable, Comparable, Sendable {
    var version: String
    var build: String

    init(version: String, build: String) {
        self.version = version.trimmingCharacters(in: .whitespaces)
        self.build = build.trimmingCharacters(in: .whitespaces)
    }

    /// "1.0 (202610210530)", or just the version when there is no build number.
    var label: String { build.isEmpty ? version : "\(version) (\(build))" }

    /// Versions compare part by part as numbers ("1.10" is after "1.9", "1.0" equals "1.0.0"); builds as numbers when
    /// both are, otherwise as text.
    static func < (a: AppBuild, b: AppBuild) -> Bool {
        let order = compareVersions(a.version, b.version)
        if order != .orderedSame { return order == .orderedAscending }
        return compareBuilds(a.build, b.build) == .orderedAscending
    }

    static func == (a: AppBuild, b: AppBuild) -> Bool {
        compareVersions(a.version, b.version) == .orderedSame && compareBuilds(a.build, b.build) == .orderedSame
    }

    func hash(into hasher: inout Hasher) {
        var parts = AppBuild.numbers(version)
        while parts.last == 0 { parts.removeLast() }
        hasher.combine(parts)
        hasher.combine(Int(build) ?? -1)
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let x = numbers(a)
        let y = numbers(b)
        for index in 0..<max(x.count, y.count) {
            let left = index < x.count ? x[index] : 0
            let right = index < y.count ? y[index] : 0
            if left != right { return left < right ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func compareBuilds(_ a: String, _ b: String) -> ComparisonResult {
        if let x = Int(a), let y = Int(b) {
            if x == y { return .orderedSame }
            return x < y ? .orderedAscending : .orderedDescending
        }
        if a == b { return .orderedSame }
        return a < b ? .orderedAscending : .orderedDescending
    }
}

// MARK: - When to show What's new

/// Decides when the What's new sheet appears: once after an update, never on a fresh install (onboarding runs then),
/// and only for releases the reader hasn't been shown.
enum WhatsNewGate {
    /// What this device remembers: the last build that ran, and the releases already shown.
    struct State: Codable, Equatable, Sendable {
        var lastBuild: AppBuild?
        var shownReleases: [String]

        init(lastBuild: AppBuild? = nil, shownReleases: [String] = []) {
            self.lastBuild = lastBuild
            self.shownReleases = shownReleases
        }
    }

    /// The releases to show now, newest first. `releaseIDs` is the list in the app, newest first.
    ///
    /// - Before onboarding is done: nothing (a fresh install shows onboarding, not news).
    /// - Onboarded, but this device has no record (it updated from a build before What's new existed): the newest
    ///   release only, not the whole history.
    /// - A newer build than the last one that ran: every release not yet shown.
    /// - The same build again, or an older one: nothing.
    static func releasesToShow(current: AppBuild, state: State?, hasOnboarded: Bool, releaseIDs: [String]) -> [String] {
        guard hasOnboarded, let newest = releaseIDs.first else { return [] }
        guard let state else { return [newest] }
        if let last = state.lastBuild, !(last < current) { return [] }
        return releaseIDs.filter { !state.shownReleases.contains($0) }
    }

    /// What to remember once the sheet has been shown, or once a launch decided there was nothing to show: this
    /// build ran, and these releases were seen. A launch before onboarding records every release as seen, so a new
    /// reader is never shown news about an app they just met.
    static func remember(current: AppBuild, state: State?, shown: [String], hasOnboarded: Bool, releaseIDs: [String]) -> State {
        var next = state ?? State()
        next.lastBuild = current
        let seen = hasOnboarded ? shown : releaseIDs
        for id in seen where !next.shownReleases.contains(id) { next.shownReleases.append(id) }
        return next
    }
}

// MARK: - The tour

/// The parts of the app the tour visits.
enum TourArea: String, CaseIterable, Codable, Sendable {
    case today, library, plan, search, settings
}

/// One coach mark: what it points at (`id` is also its anchor) and what it says.
struct TourStep: Identifiable, Hashable, Sendable {
    var id: String
    var area: TourArea
    var title: String
    var text: String
    /// Shown without an arrow, near the bottom, when what it points at isn't on screen (rows inside a form).
    var canFloat: Bool = false
}

/// Where the reader is in the tour. Coach marks show only while it runs, one at a time, each once; skipping ends it,
/// and only "Replay the tour" starts it again.
struct TourProgress: Codable, Equatable, Sendable {
    var isRunning = false
    var seen: [String] = []

    /// From the start (Settings, What's new, or the end of onboarding).
    mutating func start() {
        isRunning = true
        seen = []
    }

    /// Stops the tour; nothing more shows until it is started again.
    mutating func skip() {
        isRunning = false
    }

    mutating func markSeen(_ id: String) {
        if !seen.contains(id) { seen.append(id) }
    }

    /// Marks a step seen and ends the tour when that was the last one anywhere.
    mutating func advance(past id: String, steps: [TourStep]) {
        markSeen(id)
        if steps.allSatisfy({ seen.contains($0.id) }) { isRunning = false }
    }

    /// The next step to show in `area`: the first unseen one whose target is on screen (`available`), or one that can
    /// float. Steps go in order, so a later step never shows before an earlier one in the same area.
    func nextStep(in area: TourArea, steps: [TourStep], available: Set<String>) -> TourStep? {
        guard isRunning else { return nil }
        for step in steps where step.area == area && !seen.contains(step.id) {
            if available.contains(step.id) || step.canFloat { return step }
            return nil
        }
        return nil
    }

    /// Steps of `area` not yet seen, in order: what VoiceOver hears as one list instead of floating marks.
    func remaining(in area: TourArea, steps: [TourStep]) -> [TourStep] {
        guard isRunning else { return [] }
        return steps.filter { $0.area == area && !seen.contains($0.id) }
    }
}
