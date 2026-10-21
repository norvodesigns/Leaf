import SwiftUI

/// The Circles page of the Plan tab: reading circles (book clubs, buddy reads) kept on this phone. A shelf of
/// circles across the top; below it the chosen circle: the next meeting and what it takes to get there, a ring for
/// everyone in it, questions to bring, and the schedule.
///
/// Friends are added by name and moved along by hand while circles are local. Everything a shared version would
/// change (who the members are, where their pages come from) sits behind `CircleStore` and `CirclePlanner`, so this
/// screen stays as it is when that arrives.
struct CirclesPage: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var circles: CircleStore { CircleStore.shared }

    @State private var selectedID: UUID?
    @State private var sheet: CircleSheet?
    @State private var shuffle = 0
    @State private var confirmsDelete = false

    var body: some View {
        let shelf = circles.shelf(now: store.now)
        VStack(alignment: .leading, spacing: 0) {
            if shelf.isEmpty {
                EmptyState(
                    title: "Read with friends.",
                    message: "Start a circle for a book club, a buddy read or a long-distance read with someone you love. Everyone gets a page to aim for, and a few good questions for when you meet.",
                    actionTitle: "Start a circle"
                ) {
                    sheet = .new
                }
                .padding(.top, Space.xxl)
            } else {
                CircleShelf(circles: shelf, selectedID: current(in: shelf)?.id, now: store.now) { id in
                    guard id != current(in: shelf)?.id else { return }
                    Haptics.shared.selection()
                    withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                        selectedID = id
                        shuffle = 0
                    }
                } onNew: {
                    sheet = .new
                }
                if let circle = current(in: shelf) {
                    detail(circle)
                        .id(circle.id)
                        .focusPullTransition()
                }
            }
        }
        .onAppear { circles.loadIfDeferred() }
        .task { stage(shelf) }
        .sheet(item: $sheet) { sheet in
            CircleSheetHost(sheet: sheet) { created in
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
                Haptics.shared.warning()
                withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                    circles.delete(id)
                    selectedID = nil
                }
            }
        } message: {
            Text("The schedule and everyone’s pages go with it. Your own reading stays in your library.")
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
        VStack(alignment: .leading, spacing: 0) {
            CircleMeetingCard(circle: circle, snapshot: snapshot, item: item, now: store.now) {
                readTowards(circle, snapshot: snapshot)
            } onAdd: {
                Haptics.shared.play(.pageTurn)
                store.add(circle.book, to: .reading)
            }
            .padding(.top, Space.l)

            SectionHeader("The circle", actionTitle: "Add someone") {
                sheet = .addFriend(circleID: circle.id)
            }
            CircleMemberGrid(snapshot: snapshot, pages: circle.book.pages) { member in
                sheet = .member(circleID: circle.id, memberID: member.id)
            }
            .id("members")

            if !snapshot.isComplete {
                CirclePromptDeck(circle: circle, snapshot: snapshot, shuffle: $shuffle, now: store.now)
                    .id("prompts")
            }

            SectionHeader("Schedule", actionTitle: "Edit") {
                sheet = .schedule(circleID: circle.id)
            }
            CircleScheduleList(circle: circle, snapshot: snapshot, now: store.now)
                .id("schedule")

            footer(circle)
        }
    }

    private func footer(_ circle: ReadingCircle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.s)
            TextButton(circle.isArchived ? "Bring this circle back" : "Put this circle away", color: .inkSecondary) {
                withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                    circles.setArchived(!circle.isArchived, circle.id, now: store.now)
                }
            }
            TextButton("Delete circle", color: .inkTertiary) {
                confirmsDelete = true
            }
        }
    }

    private func readTowards(_ circle: ReadingCircle, snapshot: CircleSnapshot) {
        _ = ReadingSessionLauncher.start(
            bookID: circle.book.id, store: store, router: router, from: ReadingSessionLauncher.accessorySource
        )
    }

    // MARK: Staging

    /// Screenshots: `router.circleStage` opens a sheet ("new", "member", "schedule") or scrolls (handled by PlanView).
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
        .presentationBackground(Color.paper)
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
                .leafMargins()
        }
        .paperBackground()
    }
    .environment(circlesPreviewStore())
    .environment(AppRouter())
}

#Preview("Circles · dark") {
    NavigationStack {
        ScrollView {
            CirclesPage()
                .leafMargins()
        }
        .paperBackground()
    }
    .environment(circlesPreviewStore())
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
