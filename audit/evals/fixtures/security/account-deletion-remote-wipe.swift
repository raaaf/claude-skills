// Fixture: the account-deletion flow reports full success after the remote
// half failed. The zone delete throws, the catch logs and swallows, the pending
// flag is cleared unconditionally in the `defer`, and the user is told the data
// is gone "including from iCloud". Nothing retries, and the flag that exists to
// make a retry possible was just erased.
//
// This is a GDPR/5.1.1(v) surface: the app claims a deletion it did not
// perform. The local wipe is genuine, which is what makes the wrong claim
// plausible on screen.
//
// Everything needed to see it is in this file: the `defer` runs on the error
// path too, `.done` is reported regardless of the outcome, and the recovery
// function below can never fire because it is gated on the flag the defer just
// removed.
//
// Real-world origin: found 2026-08-06 in a codebase whose deletion flow had
// been audited on 2026-07-23 for a DIFFERENT leftover-data bug in the same
// method. The earlier pass fixed what it was looking for and did not ask
// whether the remaining steps could fail silently.
import Foundation

enum DeletionProgress: String {
    case localStore = "Lokale Einträge löschen"
    case cloudKit = "iCloud-Daten löschen"
    case done = "Fertig, auch aus iCloud gelöscht"
}

enum AccountDeletionService {

    static let pendingKey = "accountDeletionPending"
    static let defaults = UserDefaults.standard

    static func deleteAll(onProgress: (DeletionProgress) -> Void) async throws {
        defaults.set(true, forKey: pendingKey)
        // BUG: unconditional. The flag is the ONLY record that the remote half
        // is still outstanding, and it is dropped even when the zone delete
        // below throws — so `recoverIfPending` can never resume.
        defer { defaults.removeObject(forKey: pendingKey) }

        onProgress(.localStore)
        try deleteLocalStore()

        onProgress(.cloudKit)
        do {
            try await deleteCloudKitZone()
        } catch {
            // BUG: the error is logged and swallowed. Execution continues to the
            // success report below, so a network failure, a signed-out account
            // and a real deletion are indistinguishable to the user.
            print("CloudKit zone delete failed: \(error.localizedDescription)")
        }

        // BUG: claims the iCloud copy is gone on every path, including the one
        // where the request above failed.
        onProgress(.done)
    }

    /// Meant to resume an interrupted deletion on the next cold start. Dead in
    /// practice: `deleteAll`'s defer clears `pendingKey` on the failure path, so
    /// this guard never passes when it matters.
    static func recoverIfPending() async {
        guard defaults.bool(forKey: pendingKey) else { return }
        try? await deleteCloudKitZone()
        defaults.removeObject(forKey: pendingKey)
    }

    static func deleteLocalStore() throws {}

    static func deleteCloudKitZone() async throws {}
}
