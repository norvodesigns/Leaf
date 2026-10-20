import SwiftUI

/// The Challenges page of the Plan tab: the challenges the reader has joined, with their progress and prompts; the ones
/// on offer now or soon, to join with a tap; and a wall of every stamp earned, from finished books, good months and
/// challenges. Nothing here scolds: a challenge that ends unfinished just ends.
struct ChallengesPage: View {
    let desk: PlanDesk

    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var leaving: ChallengeProgress?

    var body: some View {
        if let snapshot = desk.challenges {
            VStack(alignment: .leading, spacing: 0) {
                joined(snapshot)
                offers(snapshot)
                StampWall(stamps: snapshot.stamps, locked: lockedStamps(snapshot))
                    .id("stamps")
            }
            .confirmationDialog(
                "Leave \(leaving.flatMap { ChallengeCatalog.challenge(id: $0.challengeID)?.title } ?? "this challenge")?",
                isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
                titleVisibility: .visible
            ) {
                Button("Leave", role: .destructive) {
                    if let leaving { leave(leaving) }
                }
            } message: {
                // Stamps are worked out from the challenges joined, so leaving takes the ones earned in it too.
                Text(leaving.map { $0.stamps.isEmpty } ?? true
                    ? "You can join again while it’s on offer."
                    : "The stamps you earned in it will leave your wall too.")
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    // MARK: Joined

    @ViewBuilder
    private func joined(_ snapshot: ChallengeSnapshot) -> some View {
        let order: [ChallengeStatus] = [.active, .completed, .upcoming, .ended, .retired]
        let progress = snapshot.progress.sorted {
            (order.firstIndex(of: $0.status) ?? 9, $0.challengeID) < (order.firstIndex(of: $1.status) ?? 9, $1.challengeID)
        }
        SectionHeader("Yours", topSpacing: Space.s)
        if progress.isEmpty {
            Text("Nothing joined yet. Pick one below; there’s no penalty for not finishing.")
                .leafStyle(.body, color: .inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: Space.m) {
                ForEach(progress, id: \.instanceID) { item in
                    if let challenge = ChallengeCatalog.challenge(id: item.challengeID) {
                        ChallengeProgressCard(challenge: challenge, progress: item) {
                            leaving = item
                        }
                    }
                }
            }
        }
    }

    // MARK: Offers

    @ViewBuilder
    private func offers(_ snapshot: ChallengeSnapshot) -> some View {
        let open = snapshot.offers.filter { !$0.isJoined }
        if !open.isEmpty {
            SectionHeader("On offer")
            VStack(spacing: Space.m) {
                ForEach(open) { offer in
                    ChallengeOfferCard(offer: offer) {
                        join(offer)
                    }
                }
            }
        }
    }

    private func join(_ offer: ChallengeOffer) {
        let enrollment = ChallengeEvaluator.enrollment(for: offer, now: store.now)
        Haptics.shared.play(.pageTurn)
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            store.joinChallenge(enrollment.id, year: enrollment.year)
        }
    }

    private func leave(_ progress: ChallengeProgress) {
        let year = store.data.challenges.first { $0.id == progress.challengeID && ($0.year == nil || $0.year == progress.year) }?.year
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            store.leaveChallenge(progress.challengeID, year: year)
        }
        leaving = nil
    }

    /// Stamps still to earn in the challenges joined and under way: drawn as empty outlines on the wall.
    private func lockedStamps(_ snapshot: ChallengeSnapshot) -> [StampDesign] {
        snapshot.progress.filter { $0.status == .active }.flatMap { progress -> [StampDesign] in
            guard let challenge = ChallengeCatalog.challenge(id: progress.challengeID) else { return [] }
            let earned = Set(progress.stamps.map(\.design.id))
            return challenge.stamps.filter { !earned.contains($0.id) }
        }
    }
}

// MARK: - Cards

/// A joined challenge: a ring of progress, the status line, the prompts (as a card for bingo), and its stamps.
struct ChallengeProgressCard: View {
    let challenge: Challenge
    let progress: ChallengeProgress
    let onLeave: () -> Void

    @Environment(LibraryStore.self) private var store

    private var tint: Color { StampSeal.color(for: challenge.paletteToken) }

    var body: some View {
        TodayCard(eyebrow) {
            HStack(alignment: .center, spacing: Space.m) {
                ProgressRing(progress: progress.fraction, diameter: 56, lineWidth: 5, tint: tint, label: challenge.title)
                    .overlay {
                        Text("\(progress.current)")
                            .font(.system(size: 17, weight: .regular, design: .serif).monospacedDigit())
                            .foregroundStyle(Color.ink)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .leafStyle(.headline)
                    Text(challenge.subtitle)
                        .leafStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(progress.current) of \(progress.target) \(challenge.unitName(for: progress.target))")
                        .leafStyle(.caption, color: .ink)
                }
                Spacer(minLength: 0)
                // A finished or ended challenge stays: leaving it would only take its stamps away.
                if progress.status == .active || progress.status == .upcoming {
                    Menu {
                        Button("Leave challenge", systemImage: "xmark", role: .destructive, action: onLeave)
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Color.inkTertiary)
                            .frame(width: Space.hitTarget, height: Space.hitTarget)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("More for \(challenge.title)")
                }
            }
            .accessibilityElement(children: .contain)
            Text(progress.statusLine)
                .leafStyle(.body, color: .inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if challenge.kind == .genreBingo, progress.tasks.count == 9 {
                bingoCard
            } else if !progress.tasks.isEmpty, progress.tasks.count <= 8 {
                taskList
            }
            if !progress.stamps.isEmpty {
                HStack(spacing: Space.s) {
                    ForEach(progress.stamps) { stamp in
                        StampSeal(rings: stamp.design.rings, token: stamp.design.paletteToken, diameter: 30)
                            .accessibilityLabel("\(stamp.design.name) stamp")
                    }
                }
            }
        }
    }

    /// A completed prompt names the book or tea that did it; the engine hands over an id.
    private func evidenceName(_ evidence: String?) -> String? {
        guard let evidence else { return nil }
        if let book = store.item(evidence)?.book { return book.title }
        if let tea = store.tea(id: evidence) { return tea.name }
        // A family of tea (the Tasting Notebook) is named already.
        if TeaFamily.allCases.contains(where: { $0.title == evidence }) { return evidence }
        // A tasting note on a tea that has since left the cabinet keeps its name.
        if let note = store.data.tastings.first(where: { $0.teaID == evidence }), !note.teaName.isEmpty { return note.teaName }
        return nil
    }

    private var eyebrow: String {
        switch progress.status {
        case .active: progress.daysLeft.map { $0 == 1 ? "1 day left" : "\($0) days left" } ?? "Under way"
        case .completed: "Done"
        case .upcoming: "Starting soon"
        case .ended: "Ended"
        case .retired: "Retired"
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(progress.tasks) { task in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isComplete ? tint : Color.inkFaint)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(task.title)
                            .leafStyle(.ui, color: task.isComplete ? Color.ink : Color.inkSecondary)
                        if let evidence = evidenceName(task.evidence) {
                            Text(evidence).leafStyle(.caption, color: .inkTertiary)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(task.title), \(task.isComplete ? "done" : "to do")\(evidenceName(task.evidence).map { ", \($0)" } ?? "")")
            }
        }
    }

    private var bingoCard: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(progress.tasks) { task in
                Text(task.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(task.isComplete ? Color.ink : Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .padding(Space.xs)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(task.isComplete ? tint.opacity(0.22) : Color.paperSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if task.isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tint)
                                .padding(4)
                        }
                    }
                    .accessibilityLabel("\(task.title), \(task.isComplete ? "done" : "to do")")
            }
        }
    }
}

/// A challenge on offer: what it is, when it runs, and a join button.
struct ChallengeOfferCard: View {
    let offer: ChallengeOffer
    let onJoin: () -> Void

    var body: some View {
        TodayCard(when) {
            HStack(alignment: .top, spacing: Space.m) {
                StampSeal(rings: offer.challenge.stamps.map(\.rings).max() ?? 1, token: offer.challenge.paletteToken, diameter: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(offer.challenge.title)
                        .leafStyle(.headline)
                    Text(offer.challenge.subtitle)
                        .leafStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(offer.challenge.stamps.count) \(offer.challenge.stamps.count == 1 ? "stamp" : "stamps") to collect")
                        .leafStyle(.caption, color: .inkTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            SecondaryGlassButton(offer.isOpenNow ? "Join" : "Join for when it starts", compact: true, action: onJoin)
                .accessibilityLabel(offer.isOpenNow ? "Join \(offer.challenge.title)" : "Join \(offer.challenge.title) for when it starts")
        }
    }

    private var when: String {
        if offer.isOpenNow {
            return offer.daysLeft.map { $0 == 1 ? "Open · 1 day left" : "Open · \($0) days left" } ?? "Open any time"
        }
        return offer.startsInDays == 1 ? "Starts tomorrow" : "Starts in \(offer.startsInDays) days"
    }
}

// MARK: - Stamp wall

/// Every stamp earned, newest first, as rings of tea on paper; the ones still to earn in a challenge under way are
/// faint outlines.
struct StampWall: View {
    let stamps: [StampEntry]
    let locked: [StampDesign]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Stamp wall")
            Text(summary)
                .leafStyle(.caption)
                .padding(.bottom, Space.m)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Space.m)], spacing: Space.l) {
                ForEach(stamps.sorted { $0.earnedAt > $1.earnedAt }) { stamp in
                    VStack(spacing: Space.xs) {
                        StampSeal(rings: stamp.rings, token: stamp.paletteToken, diameter: 62, symbol: symbol(for: stamp.source))
                        Text(stamp.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(stamp.detail)
                            .font(.caption2)
                            .foregroundStyle(Color.inkTertiary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stamp.name). \(stamp.detail)")
                }
                ForEach(locked) { design in
                    VStack(spacing: Space.xs) {
                        StampSeal(rings: design.rings, token: design.paletteToken, diameter: 62, isEarned: false)
                        Text(design.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.inkTertiary)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(design.name), not earned yet")
                }
            }
        }
    }

    private var summary: String {
        let books = stamps.filter { $0.source == .book }.count
        let months = stamps.filter { $0.source == .month }.count
        let challenges = stamps.filter { $0.source == .challenge }.count
        if stamps.isEmpty { return "Finish a book or read a week of days in a month, and your first stamp lands here." }
        return "\(stamps.count) \(stamps.count == 1 ? "stamp" : "stamps"): \(books) from books, \(months) from months, \(challenges) from challenges."
    }

    private func symbol(for source: StampEntry.Source) -> String {
        switch source {
        case .book: "book.closed"
        case .month: "calendar"
        case .challenge: "leaf"
        }
    }
}

/// A stamp: concentric rings of tea in the stamp's colour, each a little off true like a cup set down twice, with an
/// optional symbol in the middle. Unearned stamps are a dashed outline.
struct StampSeal: View {
    let rings: Int
    let token: String
    var diameter: CGFloat = 56
    var symbol: String?
    var isEarned = true

    /// The stamp's colour. Paper would vanish on paper, so it stamps in chai.
    static func color(for token: String) -> Color {
        token == CozyPalette.paper ? Color.chai : CozyColor.color(for: token)
    }

    var body: some View {
        let color = Self.color(for: token)
        ZStack {
            Canvas { context, size in
                let count = max(1, min(rings, 5))
                for index in 0..<count {
                    let inset = CGFloat(index) * size.width * 0.09
                    let wobble = CGFloat((index * 5 + token.count) % 5 - 2) * 0.6
                    let rect = CGRect(x: inset + wobble, y: inset - wobble, width: size.width - inset * 2, height: size.height - inset * 2)
                    if isEarned {
                        if index == 0 {
                            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.16)))
                        }
                        context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.85 - Double(index) * 0.1)), lineWidth: index == 0 ? 2 : 1.2)
                    } else {
                        context.stroke(Path(ellipseIn: rect), with: .color(Color.inkFaint), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
            }
            if let symbol, isEarned {
                Image(systemName: symbol)
                    .font(.system(size: diameter * 0.26, weight: .regular))
                    .foregroundStyle(color)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

extension ChallengeProgress {
    /// A challenge can be joined again in a later year or season: the id plus the instance's year tells them apart.
    var instanceID: String { "\(challengeID)@\(year)" }
}
