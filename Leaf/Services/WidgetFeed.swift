import Foundation
import WidgetKit

/// Keeps the Home Screen and Lock Screen widgets and the Control Center controls in step with the library: after every
/// change it writes a small snapshot to the App Group and, only when that snapshot differs, asks WidgetKit to reload.
/// The widgets count their own seconds (`Text(timerInterval:)`), so a running session costs nothing here.
@MainActor
final class WidgetFeed {
    static let shared = WidgetFeed()

    private weak var store: LibraryStore?
    private var task: Task<Void, Never>?
    /// The cover file written for each book this launch, so a scanned cover isn't rendered again on every change.
    private var covers: [String: String?] = [:]

    private init() {}

    func configure(store: LibraryStore) {
        self.store = store
        schedule()
    }

    /// Publishes a moment from now, so a burst of changes writes once.
    func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    func publish() {
        // Screenshot runs use a made-up library; they never write over the reader's widgets. Until the library has
        // been read the store holds an empty stand-in, and the widgets keep what they had.
        guard let store, !store.isLoadDeferred, !LaunchOptions.current.isScripted else { return }
        let snapshot = store.widgetSnapshot(coverName: cover(for:))
        guard LeafWidgetStore.write(snapshot) else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: LeafWidgetStore.todayKind)
        ControlCenter.shared.reloadAllControls()
    }

    private func cover(for book: Book) -> String? {
        if let done = covers[book.id] { return done }
        let name = LiveActivityCover.prepare(book: book)
        covers[book.id] = name
        return name
    }
}

extension LibraryStore {
    /// Today as the widgets draw it. `coverName` writes (or finds) a book's cover in the App Group.
    func widgetSnapshot(coverName: @escaping (Book) -> String?, at date: Date = Date()) -> LeafWidgetSnapshot {
        let session = activeSession
        let current = session.flatMap { item($0.bookID) } ?? nextBook
        let forecast = WatchBridge.shared.forecast
        func book(_ item: LibraryItem) -> LeafWidgetSnapshot.Book {
            LeafWidgetSnapshot.Book(
                id: item.id, title: item.book.title, author: item.book.author, currentPage: item.currentPage,
                pages: item.book.pages, paletteSeed: item.book.paletteSeed, coverFileName: coverName(item.book),
                finish: forecast?.book(item.id)?.median ?? plan.book(item.id)?.finish, isReading: item.shelf == .reading
            )
        }
        let assignment = current.flatMap { current in todayAssignments.first { $0.item.id == current.id }?.assignment }
        let upNext = (reading + toRead).filter { $0.id != current?.id }.prefix(3)
        let live = session.flatMap { session -> LeafWidgetSnapshot.Session? in
            guard item(session.bookID) != nil else { return nil }
            return LeafWidgetSnapshot.Session(
                bookID: session.bookID,
                timerStart: session.startedAt.addingTimeInterval(session.pausedSeconds),
                isPaused: session.isPaused,
                // Only while paused, so the snapshot stays the same from one change to the next while it runs.
                pausedElapsed: session.isPaused ? session.elapsed(at: date).rounded(.down) : 0,
                goalSeconds: LiveActivityController.goalSeconds(for: session, store: self).map(Double.init),
                teaName: tea(id: session.teaID)?.name
            )
        }
        let steep = live == nil ? TeaSteepState.load(now: date).map {
            LeafWidgetSnapshot.Steep(teaName: $0.tea.name, startedAt: $0.startedAt, steepSeconds: $0.steepSeconds)
        } : nil
        return LeafWidgetSnapshot(
            day: calendar.startOfDay(for: now),
            dailyMinutes: preferences.dailyMinutes,
            minutesReadToday: minutesReadToday,
            isReadingDay: isReadingDay,
            hasOnboarded: hasOnboarded,
            streak: streak,
            current: current.map(book),
            fromPage: assignment?.fromPage,
            toPage: assignment?.toPage,
            upNext: upNext.map(book),
            week: week.map { LeafWidgetSnapshot.Day(date: $0.date, minutes: $0.minutes, isReadingDay: $0.isReadingDay) },
            session: live,
            steep: steep,
            slots: slotPlans().compactMap { plan -> LeafWidgetSnapshot.Slot? in
                guard let part = plan.parts.first, let item = item(part.bookID) else { return nil }
                return LeafWidgetSnapshot.Slot(
                    id: plan.slot.id.uuidString, minuteOfDay: plan.slot.minuteOfDay, bookID: part.bookID, title: item.book.title,
                    minutes: plan.minutes.rounded(), fromPage: part.fromPage, toPage: plan.parts.last?.toPage ?? part.toPage
                )
            }
        )
    }
}
