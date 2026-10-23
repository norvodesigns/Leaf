import CloudKit
import SwiftUI

/// The Circles page under You: reading circles, run like Fitness competitions. A shelf of circles across the top;
/// below it the chosen circle: the goal everyone is reading towards and the race to it, the standings, what people
/// have read lately, questions to talk over, and the goals still to come.
///
/// Canopy jobs: Bloom labels the page (it sits with challenges and memories), Forest is progress, Dusk is goals and
/// days. Friends join from an iCloud invitation (`CircleSharing`) and their pages move as they read on their own
/// phones; nobody moves anyone else along. The reader's own page and sittings come from the library.
struct CirclesPage: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var circles: CircleStore { store.circleStore }

    @State private var selectedID: UUID?
    @State private var sheet: CircleSheet?
    @State private var shuffle = 0
    @State private var confirmsDelete = false
    /// The iCloud share being shown, once it is ready.
    @State private var invite: CircleInvite?
    @State private var preparingInvite = false
    @State private var inviteError: String?
    @State private var inviteProblem: InviteProblem?
    /// A circle to invite people to once the sheet in front (starting it, or the reader's name) has gone.
    @State private var invitesAfterSheet: UUID?

    var body: some View {
        let shelf = circles.shelf(now: store.now)
        VStack(alignment: .leading, spacing: Canopy.Space.section) {
            if shelf.isEmpty {
                CircleEmptyCard { sheet = .new }
            } else {
                CircleShelf(circles: shelf, selectedID: current(in: shelf)?.id, now: store.now) { id in
                    guard id != current(in: shelf)?.id else { return }
                    CanopyFeel.play(.select)
                    withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
                        selectedID = id
                        shuffle = 0
                    }
                } onNew: {
                    sheet = .new
                }
                if let circle = current(in: shelf) {
                    detail(circle)
                        .id(circle.id)
                        .canopyFocusInTransition()
                }
            }
        }
        .onAppear {
            circles.loadIfDeferred()
            takeFocus()
            // Friends' pages: fetch the shared circles again whenever the page opens, not only when the app does.
            if !LaunchOptions.current.isScripted { CircleSharing.shared.connect(store) }
        }
        .task { stage(shelf) }
        .onChange(of: router.circleFocus) { _, _ in takeFocus() }
        .onChange(of: router.circleStage) { _, new in
            if new != nil { stage(circles.shelf(now: store.now)) }
        }
        .sheet(item: $sheet, onDismiss: inviteAfterSheet) { item in
            CircleSheetHost(sheet: item) { created in
                selectedID = created
                // Straight on to inviting people, when this phone can.
                if CircleSharing.shared.isOn(for: store) { invitesAfterSheet = created }
            } onNamed: { circleID in
                invitesAfterSheet = circleID
            }
        }
        .confirmationDialog(
            "Delete \(current(in: shelf)?.name ?? "this circle")?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete circle", role: .destructive) {
                guard let id = current(in: shelf)?.id else { return }
                CanopyFeel.play(.warning)
                withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
                    circles.delete(id)
                    selectedID = nil
                }
            }
        } message: {
            Text(deleteMessage(current(in: shelf)))
        }
        .sheet(item: $invite) { invite in
            CircleShareSheet(share: invite.share, circleID: invite.circleID, title: invite.title)
                .ignoresSafeArea()
        }
        .alert("Couldn’t send the invitation", isPresented: Binding(get: { inviteError != nil }, set: { if !$0 { inviteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inviteError ?? "")
        }
        .alert(inviteProblem?.title ?? "", isPresented: Binding(get: { inviteProblem != nil }, set: { if !$0 { inviteProblem = nil } })) {
            if inviteProblem == .iCloudOff {
                Button("Open Settings") {
                    router.settingsStage = "cloud"
                    router.showSettings = true
                }
            }
            Button(inviteProblem == .iCloudOff ? "Not now" : "OK", role: .cancel) {}
        } message: {
            Text(inviteProblem?.message ?? "")
        }
    }

    private func current(in shelf: [ReadingCircle]) -> ReadingCircle? {
        shelf.first { $0.id == selectedID } ?? shelf.first
    }

    // MARK: Detail

    @ViewBuilder
    private func detail(_ circle: ReadingCircle) -> some View {
        let item = store.circleItem(for: circle)
        let myLog = CircleCheckIn.log(from: store.data.sessions, bookID: item?.id ?? circle.book.id)
        let snapshot = CirclePlanner.snapshot(
            for: circle, myPage: item?.currentPage, myLog: myLog, wpm: store.wpm, now: store.now, calendar: .current
        )
        let activity = CirclePlanner.activity(for: circle, myLog: myLog, now: store.now, calendar: .current, limit: 5)
        VStack(alignment: .leading, spacing: Canopy.Space.section) {
            CircleGoalCard(circle: circle, snapshot: snapshot, item: item, now: store.now) {
                _ = ReadingSessionLauncher.start(
                    bookID: item?.id ?? circle.book.id, store: store, router: router, from: ReadingSessionLauncher.accessorySource
                )
            } onAdd: {
                store.addCircleBook(circle.book)
            }

            if circle.friends.isEmpty, !circle.isArchived {
                CircleInviteCard(circle: circle, isPreparing: preparingInvite) { inviteFriends(to: circle) }
                    .id("members")
            } else {
                VStack(alignment: .leading, spacing: Canopy.Space.m) {
                    CanopyLabel("Standings", accent: .bloom, linkTitle: circle.isArchived ? nil : "Invite") {
                        inviteFriends(to: circle)
                    }
                    CircleStandings(snapshot: snapshot, pages: circle.book.pages, now: store.now) { member in
                        sheet = .member(circleID: circle.id, memberID: member.id)
                    }
                }
                .id("members")
            }

            if !activity.isEmpty {
                VStack(alignment: .leading, spacing: Canopy.Space.m) {
                    CanopyLabel("Lately", accent: .bloom)
                    CircleActivityList(circle: circle, activity: activity, now: store.now)
                }
                .id("lately")
            }

            if !snapshot.isComplete {
                CirclePromptDeck(circle: circle, snapshot: snapshot, shuffle: $shuffle, now: store.now)
                    .id("prompts")
            }

            VStack(alignment: .leading, spacing: Canopy.Space.m) {
                CanopyLabel("Goals", accent: .bloom, linkTitle: "Edit") {
                    sheet = .schedule(circleID: circle.id)
                }
                CircleGoalList(circle: circle, snapshot: snapshot, log: { $0.kind == .me ? myLog : $0.log }, now: store.now)
            }
            .id("schedule")

            footer(circle)
        }
    }

    private func footer(_ circle: ReadingCircle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            footerButton(circle.isArchived ? "Bring this circle back" : "Put this circle away", color: Canopy.textSecondary) {
                CanopyFeel.play(.planChanged)
                withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
                    circles.setArchived(!circle.isArchived, circle.id, now: store.now)
                }
            }
            footerButton(CircleSharing.shared.links[circle.id]?.isOwner == false ? "Leave circle" : "Delete circle", color: Canopy.textTertiary) {
                CanopyFeel.play(.tap)
                confirmsDelete = true
            }
        }
    }

    private func deleteMessage(_ circle: ReadingCircle?) -> String {
        guard let circle, let link = CircleSharing.shared.links[circle.id] else {
            return "The goals and everyone’s pages go with it. Your own reading stays in your library."
        }
        return link.isOwner
            ? "It ends the circle for everyone you invited. Your own reading stays in your library."
            : "You leave the circle, and the others stop seeing your page. Your own reading stays in your library."
    }

    private func footerButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .canopyText(.callout, color: color)
                .frame(minHeight: Canopy.Space.hitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Inviting

    private enum InviteProblem: Hashable {
        /// The reader has iCloud off in Settings.
        case iCloudOff
        /// A build without iCloud (Debug, screenshots).
        case noICloud

        var title: String {
            switch self {
            case .iCloudOff: "Invitations use iCloud"
            case .noICloud: "No invitations in this build"
            }
        }

        var message: String {
            switch self {
            case .iCloudOff: "Turn on iCloud in Settings, then invite friends from here. Their pages move as they read."
            case .noICloud: "This build of Leaf doesn’t have iCloud. Invitations work in the App Store and TestFlight versions."
            }
        }
    }

    /// Asks for the reader's name first if friends would see "You", then shows the system's invitation sheet.
    private func inviteFriends(to circle: ReadingCircle) {
        CanopyFeel.play(.tap)
        guard CircleSharing.isAvailable else {
            inviteProblem = .noICloud
            return
        }
        guard CircleSharing.shared.isOn(for: store) else {
            inviteProblem = .iCloudOff
            return
        }
        if CircleNameSheet.needsName(circle) {
            sheet = .name(circleID: circle.id)
            return
        }
        share(circle)
    }

    private func inviteAfterSheet() {
        guard let id = invitesAfterSheet else { return }
        invitesAfterSheet = nil
        guard let circle = circles.circle(id) else { return }
        // The sheet's own dismissal has to finish before the next one can come up.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            inviteFriends(to: circle)
        }
    }

    private func share(_ circle: ReadingCircle) {
        preparingInvite = true
        Task {
            defer { preparingInvite = false }
            do {
                let share = try await CircleSharing.shared.share(for: circle.id)
                invite = CircleInvite(circleID: circle.id, title: circle.name, share: share)
            } catch {
                inviteError = error.localizedDescription
            }
        }
    }

    // MARK: Focus and staging

    /// Today's circle card asked for a circle.
    private func takeFocus() {
        guard let id = router.circleFocus else { return }
        router.circleFocus = nil
        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) { selectedID = id }
    }

    /// `router.circleStage` opens a sheet: "new" (Today's suggestion too), and for screenshots "member", "schedule"
    /// and "name". Scrolling is the You tab's.
    private func stage(_ shelf: [ReadingCircle]) {
        guard let stage = router.circleStage else { return }
        switch stage {
        case "new":
            sheet = .new
        case "member":
            if let circle = shelf.first, let friend = circle.friends.first {
                sheet = .member(circleID: circle.id, memberID: friend.id)
            }
        case "schedule":
            if let circle = shelf.first { sheet = .schedule(circleID: circle.id) }
        case "name":
            if let circle = shelf.first { sheet = .name(circleID: circle.id) }
        default:
            return
        }
        router.circleStage = nil
    }
}

/// A circle's iCloud share, ready for the system sheet.
private struct CircleInvite: Identifiable {
    var id: UUID { circleID }
    let circleID: UUID
    let title: String
    let share: CKShare
}

/// No circles yet: what a circle is, how it works, and one way to start.
private struct CircleEmptyCard: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.l) {
            Image(systemName: "person.2")
                .font(.system(.title2, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CanopyAccent.bloom.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                Text("Read with friends")
                    .canopyText(.headline)
                Text("A circle is a book you read together: a book club, a buddy read, a long-distance read with someone you love.")
                    .canopyText(.callout, color: Canopy.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CircleHowItWorks()
            CanopyGlassButton("Start a circle", systemImage: "plus", accent: .bloom, compact: true, action: onStart)
        }
        .canopyCard()
    }
}

/// The three steps of a circle, numbered in Bloom: for the empty page and Today's suggestion.
struct CircleHowItWorks: View {
    static let steps = [
        "Pick a book and when you’ll finish it. Leaf sets goals along the way.",
        "Send an invitation to the people reading it with you.",
        "Read as usual. Everyone’s page moves on its own, and you all see who’s where.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: Canopy.Space.m) {
                    Text("\(index + 1)")
                        .font(.system(.footnote, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(CanopyAccent.bloom.color)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(CanopyAccent.bloom.soft))
                    Text(step)
                        .canopyText(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(index + 1). \(step)")
            }
        }
    }
}

// MARK: - Sheets

enum CircleSheet: Identifiable, Hashable {
    case new
    case member(circleID: UUID, memberID: UUID)
    case schedule(circleID: UUID)
    /// The reader's name, before friends are invited.
    case name(circleID: UUID)

    var id: String {
        switch self {
        case .new: "new"
        case .member(let circle, let member): "member-\(circle)-\(member)"
        case .schedule(let circle): "schedule-\(circle)"
        case .name(let circle): "name-\(circle)"
        }
    }
}

/// Sheets on system glass, medium first where the content fits (DESIGN_SYSTEM.md §6).
private struct CircleSheetHost: View {
    let sheet: CircleSheet
    let onCreated: (UUID) -> Void
    let onNamed: (UUID) -> Void

    var body: some View {
        NavigationStack {
            switch sheet {
            case .new:
                NewCircleSheet(onCreated: onCreated)
            case .member(let circleID, let memberID):
                CircleMemberSheet(circleID: circleID, memberID: memberID)
            case .schedule(let circleID):
                CircleScheduleSheet(circleID: circleID)
            case .name(let circleID):
                CircleNameSheet(circleID: circleID) { onNamed(circleID) }
            }
        }
        .presentationDetents(detents)
    }

    private var detents: Set<PresentationDetent> {
        switch sheet {
        case .name: [.medium]
        case .member: [.medium, .large]
        default: [.large]
        }
    }
}

// MARK: - Previews

@MainActor
private func circlesPreviewStore() -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    return store
}

#Preview("Circles") {
    NavigationStack {
        ScrollView {
            CirclesPage()
                .padding(.horizontal, Canopy.Space.margin)
        }
        .canopyBackdrop(.bloom)
    }
    .environment(circlesPreviewStore())
    .environment(AppRouter())
}

#Preview("Circles · dark") {
    NavigationStack {
        ScrollView {
            CirclesPage()
                .padding(.horizontal, Canopy.Space.margin)
        }
        .canopyBackdrop(.bloom)
    }
    .environment(circlesPreviewStore())
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
