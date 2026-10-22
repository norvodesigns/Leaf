import SwiftUI

/// A stand-in Home Screen, Lock Screen and StandBy that draw Leaf's widgets with the same views the extension uses,
/// from the demo library's own snapshot. CI can't show a real Home Screen, so screenshot runs land here
/// (`-LeafScreen widgets.home`, `widgets.timer`, `widgets.lock`). Not reachable in release builds.
struct WidgetStage: View {
    enum Kind: String, CaseIterable {
        /// Small, medium and large on today's reading.
        case home
        /// The same while a session runs, paused, and while tea steeps.
        case timer
        /// The Lock Screen accessories in every state, and StandBy.
        case lock
    }

    let kind: Kind

    @Environment(LibraryStore.self) private var store
    @State private var art = LeafWidgetArt()

    var body: some View {
        GeometryReader { proxy in
            let sizes = Self.sizes(width: proxy.size.width)
            ScrollView {
                VStack(spacing: 18) {
                    switch kind {
                    case .home: home(sizes)
                    case .timer: timers(sizes)
                    case .lock: lock(sizes)
                    }
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(wallpaper.ignoresSafeArea())
        .task { loadArt() }
    }

    // MARK: States

    private var today: LeafWidgetSnapshot {
        store.widgetSnapshot(coverName: { _ in nil })
    }

    private func reading(paused: Bool = false, cup: Bool = false) -> LeafWidgetSnapshot {
        var snapshot = today
        let now = Date()
        snapshot.session = LeafWidgetSnapshot.Session(
            bookID: snapshot.current?.id ?? "",
            timerStart: now.addingTimeInterval(paused ? -(14 * 60) : -(9 * 60 + 41)),
            isPaused: paused,
            pausedElapsed: paused ? 9 * 60 + 41 : 0,
            goalSeconds: cup ? 25 * 60 : 13 * 60,
            teaName: cup ? "Earl Grey" : nil
        )
        return snapshot
    }

    private func steeping(ready: Bool = false) -> LeafWidgetSnapshot {
        var snapshot = today
        snapshot.steep = LeafWidgetSnapshot.Steep(teaName: "Earl Grey", startedAt: Date().addingTimeInterval(ready ? -300 : -70), steepSeconds: 240)
        return snapshot
    }

    // MARK: Screens

    @ViewBuilder
    private func home(_ sizes: Sizes) -> some View {
        let snapshot = today
        let phase = snapshot.phase(at: store.now)
        HStack(spacing: sizes.gap) {
            tile(sizes.small, sizes.small) { LeafWidgetSmall(snapshot: snapshot, phase: phase, art: art, now: store.now) }
            tile(sizes.small, sizes.small) { LeafWidgetSmall(snapshot: Self.goalMet(snapshot), phase: .goalMet, art: art, now: store.now) }
        }
        tile(sizes.wide, sizes.small) { LeafWidgetMedium(snapshot: snapshot, phase: phase, art: art, now: store.now) }
        tile(sizes.wide, sizes.large) { LeafWidgetLarge(snapshot: snapshot, phase: phase, art: art, now: store.now) }
    }

    @ViewBuilder
    private func timers(_ sizes: Sizes) -> some View {
        let live = reading()
        let paused = reading(paused: true)
        let steep = steeping()
        HStack(spacing: sizes.gap) {
            tile(sizes.small, sizes.small) { LeafWidgetSmall(snapshot: live, phase: .reading, art: art, now: store.now) }
            tile(sizes.small, sizes.small) { LeafWidgetSmall(snapshot: steep, phase: .steeping, art: art, now: store.now) }
        }
        tile(sizes.wide, sizes.small) { LeafWidgetMedium(snapshot: paused, phase: .paused, art: art, now: store.now) }
        tile(sizes.wide, sizes.small) { LeafWidgetMedium(snapshot: reading(cup: true), phase: .reading, art: art, now: store.now) }
        HStack(spacing: sizes.gap) {
            tile(sizes.small, sizes.small) { LeafWidgetSmall(snapshot: steeping(ready: true), phase: .teaReady, art: art, now: store.now) }
            tile(sizes.small, sizes.small) { LeafWidgetSmall(snapshot: live, phase: .goalReached, art: art, now: store.now) }
        }
    }

    @ViewBuilder
    private func lock(_ sizes: Sizes) -> some View {
        let rows: [(String, LeafWidgetSnapshot, LeafWidgetPhase)] = [
            ("Today", today, today.phase(at: store.now)),
            ("Goal met", Self.goalMet(today), .goalMet),
            ("Reading", reading(), .reading),
            ("Steeping", steeping(), .steeping),
        ]
        VStack(spacing: 2) {
            Text(LeafFormat.format(Date(), template: "EEEEdMMMM"))
                .font(.system(.headline, weight: .semibold))
            Text("9:41")
                .font(.system(size: 72, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.9))
        ForEach(rows.indices, id: \.self) { index in
            VStack(alignment: .leading, spacing: 6) {
                Text(rows[index].0).font(.caption2).foregroundStyle(.white.opacity(0.6))
                LeafWidgetInline(snapshot: rows[index].1, phase: rows[index].2, now: store.now)
                    .font(.system(.subheadline, weight: .medium))
                HStack(spacing: 12) {
                    LeafWidgetCircular(snapshot: rows[index].1, phase: rows[index].2)
                        .frame(width: 72, height: 72)
                    LeafWidgetRectangular(snapshot: rows[index].1, phase: rows[index].2, now: store.now)
                        .padding(8)
                        .frame(width: 172, height: 76)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .frame(width: sizes.wide, alignment: .leading)
        }
        // StandBy: the small widget, large, on black, without its paper.
        VStack(alignment: .leading, spacing: 6) {
            Text("StandBy").font(.caption2).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 16) {
                LeafWidgetSmall(snapshot: today, phase: today.phase(at: store.now), art: art, now: store.now)
                    .padding(14)
                    .frame(width: (sizes.wide - 16) / 2, height: (sizes.wide - 16) / 2)
                LeafWidgetSmall(snapshot: reading(cup: true), phase: .reading, art: art, now: store.now)
                    .padding(14)
                    .frame(width: (sizes.wide - 16) / 2, height: (sizes.wide - 16) / 2)
            }
            .padding(10)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
        .frame(width: sizes.wide, alignment: .leading)
    }

    // MARK: Pieces

    struct Sizes {
        var small: CGFloat
        var wide: CGFloat
        var large: CGFloat
        var gap: CGFloat { wide - small * 2 }
    }

    /// The system's widget sizes for the screen width (the 6.3" and 6.9" phones, else the 6.1").
    static func sizes(width: CGFloat) -> Sizes {
        width >= 400 ? Sizes(small: 170, wide: 364, large: 382) : Sizes(small: 158, wide: 338, large: 354)
    }

    private func tile<Content: View>(_ width: CGFloat, _ height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(width: width, height: height)
            .background(LeafWidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var wallpaper: some View {
        LinearGradient(
            colors: kind == .lock ? [Color(hex: 0x2B3A4A), Color(hex: 0x14181F)] : [Color(hex: 0x9DB3A4), Color(hex: 0x4E6457)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static func goalMet(_ snapshot: LeafWidgetSnapshot) -> LeafWidgetSnapshot {
        var met = snapshot
        met.minutesReadToday = Double(max(met.dailyMinutes, 1))
        return met
    }

    private func loadArt() {
        var loaded = LeafWidgetArt()
        let books = [store.nextBook].compactMap { $0 } + (store.reading + store.toRead).prefix(4)
        for item in books where loaded.covers[item.id] == nil {
            let rendered = LiveActivityCover.images(for: item.book)
            loaded.covers[item.id] = rendered.cover.map { Image(uiImage: $0) }
        }
        art = loaded
    }
}
