import Foundation
import WatchConnectivity

/// The watch side of WatchConnectivity: snapshots in, session events out.
@MainActor
final class PhoneBridge: NSObject {
    static let shared = PhoneBridge()

    private weak var store: WatchStore?

    func activate(store: WatchStore) {
        self.store = store
        store.send = { [weak self] event in self?.send(event) }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends now when the phone is reachable; otherwise queues it so it arrives later, guaranteed.
    func send(_ event: SyncEvent) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload = SyncCodec.encode(event, key: SyncCodec.eventKey)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in }, errorHandler: { _ in
                WCSession.default.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    func requestSnapshot() { send(.requestSnapshot) }

    /// Asks for fresh numbers only when the phone can answer now; a queued ask would arrive after they matter.
    func refreshIfReachable() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        requestSnapshot()
    }

    private func receive(_ snapshot: WatchSnapshot) {
        store?.apply(snapshot)
    }
}

extension PhoneBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = SyncCodec.decode(WatchSnapshot.self, from: session.receivedApplicationContext, key: SyncCodec.snapshotKey)
        Task { @MainActor in
            if let context { self.receive(context) }
            self.requestSnapshot()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = SyncCodec.decode(WatchSnapshot.self, from: applicationContext, key: SyncCodec.snapshotKey) else { return }
        Task { @MainActor in self.receive(snapshot) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let snapshot = SyncCodec.decode(WatchSnapshot.self, from: message, key: SyncCodec.snapshotKey) else { return }
        Task { @MainActor in self.receive(snapshot) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.requestSnapshot() }
    }
}
