// Fixture: lock-guarded connect that protects the success and failure paths
// but leaves the entry/install path unguarded. An orphaned earlier connect
// task can clobber a newer, already-connected client because the install
// happens outside the lock and without a generation check.
// Real-world origin: fix agents missed this twice in a row on 2026-07-03;
// only the adversarial verifier pass caught it.
import Foundation

final class NetworkClient {
    let host: String
    init(host: String) { self.host = host }
    func open() async throws {}
    func close() {}
}

final class PrinterConnectionManager {
    enum State { case idle, connecting, connected, failed }

    private let lock = NSLock()
    private var client: NetworkClient?
    private var state: State = .idle

    func connect(host: String) {
        // BUG: entry path installs the new client without taking the lock
        // and without invalidating in-flight connects. A second connect()
        // racing with the first leaves whichever task finishes last as the
        // winner, even if its client belongs to a stale host.
        let newClient = NetworkClient(host: host)
        client = newClient
        state = .connecting

        Task {
            do {
                try await newClient.open()
                lock.lock()
                if client === newClient { state = .connected }
                lock.unlock()
            } catch {
                lock.lock()
                if client === newClient {
                    client = nil
                    state = .failed
                }
                lock.unlock()
            }
        }
    }

    func disconnect() {
        lock.lock()
        client?.close()
        client = nil
        state = .idle
        lock.unlock()
    }
}
