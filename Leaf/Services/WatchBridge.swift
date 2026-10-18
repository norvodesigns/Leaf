import Foundation
import WatchConnectivity

/// Keeps the Apple Watch app in step with the phone: snapshots go out, sessions come back.
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    private weak var store: LibraryStore?
    private var pushTask: Task<Void, Never>?

    /// A session logged on the watch (so the phone can celebrate, too).
    var onRemoteOutcome: ((SessionOutcome) -> Void)?

    func activate(store: LibraryStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    func push() {
        guard WCSession.isSupported(), let store else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let payload = SyncCodec.encode(store.watchSnapshot(), key: SyncCodec.snapshotKey)
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func receive(_ event: SyncEvent) {
        if case .addBook(let query) = event {
            addDictatedBook(query)
            return
        }
        if let outcome = store?.apply(event) { onRemoteOutcome?(outcome) }
        push()
    }

    /// A title dictated on the wrist: take the catalog's best match and put it at the end of To read.
    private func addDictatedBook(_ query: String) {
        Task { [weak self] in
            await BookCatalog.shared.load()
            guard let self, let store = self.store, let match = BookCatalog.shared.search(query, limit: 1).first else { return }
            if store.item(match.id) == nil { store.add(match, to: .toRead) }
            self.push()
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let event = SyncCodec.decode(SyncEvent.self, from: message, key: SyncCodec.eventKey) else { return }
        Task { @MainActor in self.receive(event) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let event = SyncCodec.decode(SyncEvent.self, from: message, key: SyncCodec.eventKey)
        replyHandler([:])
        guard let event else { return }
        Task { @MainActor in self.receive(event) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let event = SyncCodec.decode(SyncEvent.self, from: userInfo, key: SyncCodec.eventKey) else { return }
        Task { @MainActor in self.receive(event) }
    }
}

extension LibraryStore {
    /// The compact view of today that the watch shows.
    func watchSnapshot() -> WatchSnapshot {
        let today = todayAssignments.map { pair in
            WatchAssignment(bookID: pair.item.id, title: pair.item.book.title, minutes: pair.assignment.minutes, fromPage: pair.assignment.fromPage, toPage: pair.assignment.toPage)
        }
        var books = reading
        // A live session for a book that isn't on the Reading shelf still needs its book on the watch.
        if let active = activeSession, !books.contains(where: { $0.id == active.bookID }), let item = item(active.bookID) {
            books.append(item)
        }
        if books.isEmpty, let next = toRead.first { books = [next] }
        let watchBooks = books.prefix(8).map { item in
            WatchBook(
                id: item.id,
                title: item.book.title,
                author: item.book.author,
                currentPage: item.currentPage,
                pages: item.book.pages,
                wordsPerPage: item.book.wordsPerPage,
                paletteSeed: item.book.paletteSeed,
                finish: plan.book(item.id)?.finish
            )
        }
        let days = week.map { WatchDay(date: $0.date, minutes: $0.minutes, goal: preferences.dailyMinutes, isReadingDay: $0.isReadingDay) }
        return WatchSnapshot(
            generatedAt: Date(),
            dailyMinutes: preferences.dailyMinutes,
            minutesReadToday: minutesReadToday,
            isReadingDay: isReadingDay,
            streak: streak,
            wpm: wpm,
            today: today,
            reading: Array(watchBooks),
            week: days,
            activeSession: activeSession,
            hasOnboarded: hasOnboarded
        )
    }
}
