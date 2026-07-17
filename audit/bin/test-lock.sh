#!/usr/bin/env bash
# Serializes test runs across parallel agents (fix agents, verifiers,
# orchestrator). Two concurrent `php artisan test` runs against the same DB
# corrupt each other's fixtures — this is a semaphore, not a convention.
#
# Usage: test-lock.sh <command...>
#   bash "$AUDIT_BIN/test-lock.sh" php artisan test --compact tests/Unit/FooTest.php
#
# Portable mkdir spinlock (flock is not available on stock macOS). Lock is
# per-repo (hash of toplevel), TTL 15 min against stale locks from killed runs.
# A background heartbeat touches the lock dir every 60s while the wrapped
# command runs, so a legitimately slow run keeps refreshing its own mtime and
# is never mistaken for an orphan. WAIT_MAX is kept >= TTL_SECONDS so a waiter
# never times out before an actual orphan ages past the TTL.

set -u

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
HASH=$(printf '%s' "$REPO_ROOT" | { md5 2>/dev/null || md5sum | cut -d' ' -f1; })
LOCK_DIR="${TMPDIR:-/tmp}/claude-audit-test-lock-${HASH}"
TTL_SECONDS=900
WAIT_MAX=960
WAITED=0

acquire() {
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    # Stale lock? (owner died without cleanup)
    if [ -d "$LOCK_DIR" ]; then
      NOW=$(date +%s)
      LOCK_TS=$(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo "$NOW")
      if [ $((NOW - LOCK_TS)) -gt "$TTL_SECONDS" ]; then
        echo "test-lock: removing stale lock (older than ${TTL_SECONDS}s)" >&2
        rm -rf "$LOCK_DIR"
        continue
      fi
    fi
    if [ "$WAITED" -ge "$WAIT_MAX" ]; then
      echo "test-lock: timeout after ${WAIT_MAX}s waiting for $LOCK_DIR" >&2
      exit 75
    fi
    sleep 2
    WAITED=$((WAITED + 2))
  done
}

acquire
HB_PID=""
trap 'kill "$HB_PID" 2>/dev/null; rm -rf "$LOCK_DIR"' EXIT INT TERM

# Heartbeat: refresh the lock dir mtime periodically so a live, slow run is
# never aged past TTL_SECONDS and reaped by a waiter. Runs sleep 60 as an
# explicit child and traps TERM inside the subshell so `kill "$HB_PID"` in
# the cleanup trap above kills the sleep child too, instead of leaving it
# as an orphan for up to 60s after the wrapped command exits.
(
  SLEEP_PID=""
  trap 'kill "$SLEEP_PID" 2>/dev/null; exit 0' TERM
  while :; do
    sleep 60 &
    SLEEP_PID=$!
    wait "$SLEEP_PID" 2>/dev/null
    touch "$LOCK_DIR" 2>/dev/null || exit
  done
) &
HB_PID=$!

"$@"
