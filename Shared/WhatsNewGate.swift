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
