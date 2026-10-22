import CloudKit
import SwiftUI

/// The Circles page under You: reading circles (book clubs, buddy reads) kept on this phone. A shelf of circles across
/// the top; below it the chosen circle: the next meeting and what it takes to get there, a ring for everyone in it,
/// questions to bring, and the schedule.
///
/// Canopy jobs: Bloom labels the page (it sits with challenges and memories), Forest is progress, Dusk is meeting
/// times. Friends are added by name and moved along by hand while circles are local. Everything a shared version would
/// change (who the members are, where their pages come from) sits behind `CircleStore` and `CirclePlanner`, so this
/// screen stays as it is when that arrives.
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
        .onAppear { circles.loadIfDeferred() }
        .task { stage(shelf) }
        .sheet(item: $sheet) { item in
            CircleSheetHost(sheet: item) { created in
                selectedID = created
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
            Text("The schedule and everyone’s pages go with it. Your own reading stays in your library.")
        }
        .sheet(item: $invite) { invite in
            CircleShareSheet(share: invite.share, circleID: invite.circleID, title: invite.title)
                .ignoresSafeArea()
        }
        .alert("Couldn’t share the circle", isPresented: Binding(get: { inviteError != nil }, set: { if !$0 { inviteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inviteError ?? "")
        }
    }

    private func current(in shelf: [ReadingCircle]) -> ReadingCircle? {
        shelf.first { $0.id == selectedID } ?? shelf.first
    }

    // MARK: Detail

    @ViewBuilder
    private func detail(_ circle: ReadingCircle) -> some View {
        let item = store.item(circle.book.id)
        let snapshot = CirclePlanner.snapshot(
            for: circle, myPage: item?.currentPage, wpm: store.wpm, now: store.now, calendar: .current
        )
        VStack(alignment: .leading, spacing: Canopy.Space.section) {
            CircleMeetingCard(circle: circle, snapshot: snapshot, item: item, now: store.now) {
                _ = ReadingSessionLauncher.start(
                    bookID: circle.book.id, store: store, router: router, from: ReadingSessionLauncher.accessorySource
                )
            } onAdd: {
                store.add(circle.book, to: .reading)
            }

            VStack(alignment: .leading, spacing: Canopy.Space.m) {
                CanopyLabel("The circle", accent: .bloom, linkTitle: "Add someone") {
                    sheet = .addFriend(circleID: circle.id)
                }
                CircleMemberGrid(snapshot: snapshot, pages: circle.book.pages) { member in
                    sheet = .member(circleID: circle.id, memberID: member.id)
                }
            }
            .id("members")

            if !snapshot.isComplete {
                CirclePromptDeck(circle: circle, snapshot: snapshot, shuffle: $shuffle, now: store.now)
                    .id("prompts")
            }

            VStack(alignment: .leading, spacing: Canopy.Space.m) {
                CanopyLabel("Schedule", accent: .bloom, linkTitle: "Edit") {
                    sheet = .schedule(circleID: circle.id)
                }
                CircleScheduleList(circle: circle, snapshot: snapshot, now: store.now)
            }
            .id("schedule")

            footer(circle)
        }
    }

    private func footer(_ circle: ReadingCircle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Only in builds with iCloud, with iCloud on: friends join and move their own pages.
            if CircleSharing.shared.isOn(for: store) {
                footerButton(
                    preparingInvite ? "Getting the invitation ready…" : (CircleSharing.shared.isShared(circle.id) ? "Shared with iCloud: invite more" : "Invite friends with iCloud"),
                    color: Canopy.textSecondary
                ) {
                    shareCircle(circle)
                }
                .disabled(preparingInvite)
            }
            footerButton(circle.isArchived ? "Bring this circle back" : "Put this circle away", color: Canopy.textSecondary) {
                CanopyFeel.play(.planChanged)
                withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
                    circles.setArchived(!circle.isArchived, circle.id, now: store.now)
                }
            }
            footerButton("Delete circle", color: Canopy.textTertiary) {
                CanopyFeel.play(.tap)
                confirmsDelete = true
            }
        }
    }

    private func shareCircle(_ circle: ReadingCircle) {
        CanopyFeel.play(.tap)
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

    private func footerButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .canopyText(.callout, color: color)
                .frame(minHeight: Canopy.Space.hitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Staging

    /// Screenshots: `router.circleStage` opens a sheet ("new", "member", "schedule"); scrolling is the You tab's.
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

/// No circles yet: what a circle is, and one way to start.
private struct CircleEmptyCard: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            Image(systemName: "person.2")
                .font(.system(.title2, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CanopyAccent.bloom.color)
                .accessibilityHidden(true)
            Text("Read with friends")
                .canopyText(.headline)
            Text("Start a circle for a book club, a buddy read or a long-distance read with someone you love. Everyone gets a page to aim for, and a few good questions for when you meet.")
                .canopyText(.callout, color: Canopy.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            CanopyGlassButton("Start a circle", systemImage: "plus", accent: .bloom, compact: true, action: onStart)
                .padding(.top, Canopy.Space.xs)
        }
        .canopyCard()
    }
}

// MARK: - Sheets

enum CircleSheet: Identifiable, Hashable {
    case new
    case member(circleID: UUID, memberID: UUID)
    case addFriend(circleID: UUID)
    case schedule(circleID: UUID)

    var id: String {
        switch self {
        case .new: "new"
        case .member(let circle, let member): "member-\(circle)-\(member)"
        case .addFriend(let circle): "friend-\(circle)"
        case .schedule(let circle): "schedule-\(circle)"
        }
    }
}

/// Sheets on system glass, medium first where the content fits (DESIGN_SYSTEM.md §6).
private struct CircleSheetHost: View {
    let sheet: CircleSheet
    let onCreated: (UUID) -> Void

    var body: some View {
        NavigationStack {
            switch sheet {
            case .new:
                NewCircleSheet(onCreated: onCreated)
            case .member(let circleID, let memberID):
                CircleMemberSheet(circleID: circleID, memberID: memberID)
            case .addFriend(let circleID):
                CircleAddFriendSheet(circleID: circleID)
            case .schedule(let circleID):
                CircleScheduleSheet(circleID: circleID)
            }
        }
        .presentationDetents(detents)
    }

    private var detents: Set<PresentationDetent> {
        switch sheet {
        case .addFriend: [.medium]
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
