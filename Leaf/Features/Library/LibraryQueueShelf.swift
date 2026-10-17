import SwiftUI
import UIKit

/// The To read shelf (DESIGN.md §6): the running order. Rows are `index` "01", a cover S, title and
/// author, and "by 3 Dec" in `data`.
///
/// - **Reorder:** a 0.3 s long press lifts a row (`reorderLift`, scale 1.03, `paperRaised`, the lifted
///   shadow). Each slot it crosses plays `selection`. Dropping plays `reorderDrop`, calls
///   `store.reorder`, then the dates reflow: they roll with `numericText`, flash `ribbonSoft`, show
///   a DeltaChip for 2.5 s and play a `riffle`.
/// - **Swipe** a row left for Start, To top and Remove.
/// - **VoiceOver:** "Move up", "Move down", "Move to top", "Start reading" and "Remove".
struct LibraryQueueShelf: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onRemove: (Book) -> Void

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 76

    /// The row being dragged.
    @State private var liftedID: String?
    /// The row showing its swipe buttons.
    @State private var openSwipeID: String?
    /// The last drag distance seen, so a drag that never reports its end can still be dropped.
    @State private var lastTranslation: CGFloat = 0
    /// A tap right after a drop must not open the book.
    @State private var tapGuardUntil = Date.distantPast
    /// Days each finish date just moved by (positive = sooner), shown as DeltaChips.
    @State private var deltas: [String: Int] = [:]
    @State private var deltaGeneration = 0
    @GestureState private var dragTranslation: CGFloat = 0
    @GestureState private var isGestureActive = false

    init(onRemove: @escaping (Book) -> Void) {
        self.onRemove = onRemove
    }

    // MARK: Body

    var body: some View {
        let items = store.toRead
        if items.isEmpty {
            EmptyState(
                title: "The queue is clear.",
                message: "Add the books you mean to get to.",
                actionTitle: "Find a book"
            ) {
                router.tab = .search
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(index: index, item: item, count: items.count)
                }
            }
            .onChange(of: currentSlot) { old, new in
                if old != nil, new != nil { Haptics.shared.selection() }
            }
            .onChange(of: isGestureActive) { _, active in
                if !active { releaseIfStuck() }
            }
        }
    }

    private func row(index: Int, item: LibraryItem, count: Int) -> some View {
        let isLifted = liftedID == item.id
        let finish = store.plan.book(item.id)?.finish
        return LibrarySwipeReveal(
            actions: swipeActions(index: index, item: item),
            height: rowHeight,
            isOpen: openSwipeID == item.id,
            isEnabled: liftedID == nil,
            setOpen: { setSwipe(item.id, open: $0) }
        ) {
            LibraryQueueRowContent(
                position: index + 1,
                item: item,
                finish: finish,
                finishText: finishText(finish),
                delta: deltas[item.id],
                flashDelay: Motion.reflowStagger * Double(index),
                isLifted: isLifted,
                height: rowHeight
            )
            .liftedRow(isLifted)
            .padding(.horizontal, -Space.m)
        }
        .contentShape(.rect)
        .offset(y: yOffset(index: index, id: item.id, count: count))
        .zIndex(isLifted ? 1 : 0)
        .animation(isLifted ? nil : Motion.resolved(Motion.paper, reduceMotion: reduceMotion), value: currentSlot)
        .onTapGesture { open(item) }
        .gesture(reorderGesture(item: item))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(index: index, count: count, item: item, finish: finish))
        .accessibilityHint("Opens book details. Use the actions to reorder.")
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            if index > 0 {
                Button("Move up") { moveForVoiceOver(from: index, to: index - 1, count: count) }
                Button("Move to top") { moveForVoiceOver(from: index, to: 0, count: count) }
            }
            if index < count - 1 {
                Button("Move down") { moveForVoiceOver(from: index, to: index + 1, count: count) }
            }
            Button("Start reading") { startReading(item) }
            Button("Remove from Library") { onRemove(item.book) }
        }
    }

    // MARK: Swipe actions

    private func swipeActions(index: Int, item: LibraryItem) -> [LibrarySwipeAction] {
        var actions: [LibrarySwipeAction] = [
            LibrarySwipeAction(
                id: "start",
                title: "Start",
                accessibilityLabel: "Start reading",
                systemImage: "book",
                background: Color.accent,
                foreground: Color.paper,
                handler: { startReading(item) }
            ),
        ]
        if index > 0 {
            actions.append(
                LibrarySwipeAction(
                    id: "top",
                    title: "To top",
                    accessibilityLabel: "Move to top",
                    systemImage: "arrow.up.to.line",
                    background: Color.ink,
                    foreground: Color.paper,
                    handler: { commitMove(from: index, to: 0) }
                )
            )
        }
        actions.append(
            LibrarySwipeAction(
                id: "remove",
                title: "Remove",
                accessibilityLabel: "Remove from Library",
                systemImage: "trash",
                background: Color(uiColor: .systemRed),
                foreground: Color.white,
                handler: { onRemove(item.book) }
            )
        )
        return actions
    }

    private func setSwipe(_ id: String, open: Bool) {
        if open {
            openSwipeID = id
        } else if openSwipeID == id {
            openSwipeID = nil
        }
    }

    private func startReading(_ item: LibraryItem) {
        Haptics.shared.press()
        Motion.animate(Motion.paper) {
            store.startReading(item.id)
        }
    }

    private func open(_ item: LibraryItem) {
        guard liftedID == nil, Date() >= tapGuardUntil else { return }
        if openSwipeID != nil {
            withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) { openSwipeID = nil }
            return
        }
        router.libraryPath.append(BookRoute(book: item.book))
    }

    // MARK: Reordering

    /// Where the dragged row would land, or nil when nothing is lifted.
    private var currentSlot: Int? {
        guard let id = liftedID else { return nil }
        let items = store.toRead
        guard let source = items.firstIndex(where: { $0.id == id }) else { return nil }
        return slot(from: source, translation: dragTranslation, count: items.count)
    }

    private func slot(from source: Int, translation: CGFloat, count: Int) -> Int {
        guard rowHeight > 0 else { return source }
        let moved = Int((translation / rowHeight).rounded())
        return min(max(source + moved, 0), max(count - 1, 0))
    }

    /// How far a row sits from its slot: the lifted row follows the finger, and the rows it passes
    /// step aside by one row height.
    private func yOffset(index: Int, id: String, count: Int) -> CGFloat {
        guard let id0 = liftedID,
              let source = store.toRead.firstIndex(where: { $0.id == id0 }),
              let target = currentSlot else { return 0 }
        if id == id0 {
            let lowest = -CGFloat(source) * rowHeight
            let highest = CGFloat(count - 1 - source) * rowHeight
            return min(max(dragTranslation, lowest), highest)
        }
        if source < target, index > source, index <= target { return -rowHeight }
        if source > target, index >= target, index < source { return rowHeight }
        return 0
    }

    private func reorderGesture(item: LibraryItem) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($dragTranslation) { value, state, _ in
                if case .second(true, let drag?) = value {
                    state = drag.translation.height
                }
            }
            .updating($isGestureActive) { _, state, _ in
                state = true
            }
            .onChanged { value in
                if case .second(true, let drag) = value {
                    if liftedID != item.id { lift(item) }
                    if let drag { lastTranslation = drag.translation.height }
                }
            }
            .onEnded { value in
                if case .second(true, let drag) = value {
                    finishLift(translation: drag?.translation.height ?? lastTranslation)
                }
            }
    }

    private func lift(_ item: LibraryItem) {
        guard liftedID == nil else { return }
        lastTranslation = 0
        Haptics.shared.play(.reorderLift, heft: Haptics.heft(pages: item.book.pages))
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            openSwipeID = nil
            liftedID = item.id
        }
    }

    /// The one way out of a drag: drop the row where it was carried.
    private func finishLift(translation: CGFloat) {
        guard let id = liftedID else { return }
        tapGuardUntil = Date().addingTimeInterval(0.4)
        lastTranslation = 0
        let items = store.toRead
        guard let source = items.firstIndex(where: { $0.id == id }) else {
            liftedID = nil
            return
        }
        let target = slot(from: source, translation: translation, count: items.count)
        if target == source {
            Haptics.shared.play(.reorderDrop, heft: Haptics.heft(pages: items[source].book.pages))
            withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) { liftedID = nil }
        } else {
            commitMove(from: source, to: target)
        }
    }

    /// A drag that ended without `onEnded` (a system interruption) would leave the row lifted.
    private func releaseIfStuck() {
        guard liftedID != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            if liftedID != nil, !isGestureActive {
                finishLift(translation: lastTranslation)
            }
        }
    }

    /// Moves the book at `source` to `target` and lets the dates reflow.
    private func commitMove(from source: Int, to target: Int) {
        let items = store.toRead
        guard source != target, items.indices.contains(source), items.indices.contains(target) else {
            liftedID = nil
            return
        }
        let pages = items[source].book.pages
        let before = finishDates()
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            liftedID = nil
            openSwipeID = nil
            // List.onMove semantics: the destination is an index in the array before the move.
            store.reorder(.toRead, fromOffsets: IndexSet(integer: source), toOffset: target > source ? target + 1 : target)
        }
        Haptics.shared.play(.reorderDrop, heft: Haptics.heft(pages: pages))
        reflowDates(from: before, earlier: target < source)
    }

    private func moveForVoiceOver(from source: Int, to target: Int, count: Int) {
        commitMove(from: source, to: target)
        UIAccessibility.post(notification: .announcement, argument: "Moved to position \(target + 1) of \(count)")
    }

    // MARK: Reflow

    private func finishDates() -> [String: Date] {
        var dates: [String: Date] = [:]
        for planned in store.plan.books {
            if let finish = planned.finish { dates[planned.id] = finish }
        }
        return dates
    }

    /// Compares finish dates before and after a move, shows DeltaChips for the books that moved and
    /// plays the riffle (crisp when the moved book went earlier, dull when later).
    private func reflowDates(from before: [String: Date], earlier: Bool) {
        let calendar = store.calendar
        var changes: [String: Int] = [:]
        for (id, newDate) in finishDates() {
            guard let oldDate = before[id] else { continue }
            let sooner = LibraryDates.days(from: newDate, to: oldDate, calendar: calendar)
            if sooner != 0 { changes[id] = sooner }
        }
        guard !changes.isEmpty else { return }
        deltaGeneration += 1
        let generation = deltaGeneration
        let moved = changes.count
        let animation = Motion.resolved(Motion.paper, reduceMotion: reduceMotion)
        withAnimation(animation) { deltas = changes }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            Haptics.shared.riffle(count: moved, earlier: earlier)
            try? await Task.sleep(for: .seconds(Motion.deltaChipDuration))
            guard generation == deltaGeneration else { return }
            withAnimation(animation) { deltas = [:] }
        }
    }

    // MARK: Text

    private func finishText(_ finish: Date?) -> String {
        guard let finish else { return "—" }
        return "by " + LibraryDates.day(finish, now: store.now, calendar: store.calendar)
    }

    private func spokenLabel(index: Int, count: Int, item: LibraryItem, finish: Date?) -> String {
        var text = "\(item.book.title), by \(item.book.author). Number \(index + 1) of \(count)."
        if let finish {
            text += " Finishes \(LibraryDates.day(finish, now: store.now, calendar: store.calendar))."
        }
        return text
    }
}

// MARK: - Row

/// The face of a To read row: index, cover S, title and author, and the finish date. It fills the
/// margin-wide row and pads itself 12 pt in, so a lifted row's card reaches past the text.
private struct LibraryQueueRowContent: View {
    let position: Int
    let item: LibraryItem
    let finish: Date?
    let finishText: String
    let delta: Int?
    let flashDelay: TimeInterval
    let isLifted: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: Space.m) {
            Text(String(format: "%02d", position))
                .leafStyle(.index)
                .frame(minWidth: 40, alignment: .leading)

            BookCover(book: item.book, size: .s)
                .libraryBookZoomSource(item.id)

            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(item.book.title)
                    .leafStyle(.headline)
                    .lineLimit(2)
                Text(item.book.author)
                    .leafStyle(.author)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: Space.xxs) {
                Text(finishText)
                    .leafStyle(.data)
                    .contentTransition(.numericText())
                    .leafAnimation(Motion.paper, value: finishText)
                    .reflowFlash(trigger: finish, delay: flashDelay)
                if let delta, delta != 0 {
                    DeltaChip(daysSooner: delta)
                        .transition(.deltaChip)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, Space.m)
        .frame(height: height)
        .overlay(alignment: .bottom) {
            Hairline()
                .padding(.horizontal, Space.m)
                .opacity(isLifted ? 0 : 1)
        }
    }
}
