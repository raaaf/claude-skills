import { Database } from "bun:sqlite";
import { unlinkSync, renameSync } from "node:fs";

const LIVE_DB = process.env.SV_DB_PATH ?? "./sprachverliebt.db";
const SNAPSHOT_PATH = "./backups/latest.db";
const TMP_PATH = "./backups/latest.db.tmp";

export function runBackup() {
  const db = new Database(LIVE_DB);

  // BUG: the live DB runs in WAL mode (journal_mode=WAL). db.serialize()
  // snapshots the main file's on-disk image without forcing a checkpoint
  // first, so on a busy live DB the copy is missing pages that only exist
  // in the not-yet-checkpointed WAL file -- an internally inconsistent
  // SQLite image.
  const bytes = db.serialize();
  Bun.write(TMP_PATH, bytes);

  // This readonly integrity check is correct in isolation, but because
  // TMP_PATH was produced by the non-checkpointed serialize() above, it
  // reliably fails to even open (SQLITE_CANTOPEN) rather than reporting a
  // clean integrity_check failure -- the catch below treats that identically
  // to "backup was corrupt, prune it."
  try {
    const verify = new Database(TMP_PATH, { readonly: true });
    const ok = verify.query("PRAGMA integrity_check").get() as { integrity_check: string };
    verify.close();
    if (ok.integrity_check !== "ok") {
      throw new Error(`integrity check failed: ${ok.integrity_check}`);
    }
  } catch {
    // BUG (compounding): every run hits this branch because the copy is
    // always inconsistent under WAL, not just on genuine corruption, so the
    // fresh snapshot is pruned and the job exits 1 on every single cron
    // invocation. No backup has ever actually been produced, and the exit
    // code has looked identical to "no new data to back up" for as long as
    // this has been running.
    unlinkSync(TMP_PATH);
    db.close();
    throw new Error("backup verify failed, pruned");
  }

  renameSync(TMP_PATH, SNAPSHOT_PATH);
  db.close();
}
