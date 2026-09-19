#!/usr/bin/env bash
# Serializes test runs across parallel agents (fix agents, verifiers,
# orchestrator). Two concurrent `php artisan test` runs against the same DB
# corrupt each other's fixtures — this is a semaphore, not a convention.
#
# Usage: test-lock.sh <command...>
#   bash "$AUDIT_BIN/test-lock.sh" php artisan test --compact tests/Unit/FooTest.php
#
# Portable mkdir spinlock (flock is not available on stock macOS). Lock is
# per-repo, TTL 15 min against stale locks from killed runs.
#
# The lock dir lives under the repo's shared git dir (`--git-common-dir`),
# NOT under $TMPDIR: every subagent runs in its own sandbox with its own
# TMPDIR, so a TMPDIR lock was private to each agent and serialized nothing.
# Three parallel fix agents collided on the same test database on
# 2026-08-31 and again on 2026-09-02 with the lock "in place" (learning log:
# "test-lock.sh trotz Pflicht kollidiert", root cause found 2026-09-03). The
# common git dir is the one path every agent of a repo shares, across
# linked worktrees too, which is right because worktrees usually share the
# test database as well. $TMPDIR stays only as the fallback outside a repo
# or when the git dir is not writable.
# A background heartbeat touches the lock dir every 60s while the wrapped
# command runs, so a legitimately slow run keeps refreshing its own mtime and
# is never mistaken for an orphan. WAIT_MAX is kept >= TTL_SECONDS so a waiter
# never times out before an actual orphan ages past the TTL.
#
# Ownership is explicit, not just "the directory exists": each holder writes
# a PID+nonce token into a file inside the lock dir at acquisition. Stale
# reaping uses `mv` (atomic rename) instead of `rm -rf` directly, so that
# when two waiters both decide a lock looks stale, only one of them can win
# the actual reap -- the loser's `mv` fails because the source is already
# gone, instead of both `rm -rf`-ing the same path and one deleting a
# directory the other has since recreated. The EXIT trap only removes the
# lock dir if the token still inside it matches the token this process wrote.

set -u

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
HASH=$(printf '%s' "$REPO_ROOT" | { md5 2>/dev/null || md5sum | cut -d' ' -f1; })

# Lock granularity is repo PLUS destination. A PHP suite contends on one test
# database, so the repo alone is the right key there. An xcodebuild run
# contends on one booted simulator, and two runs against the SAME simulator
# kill each other: the loser dies with "Early unexpected exit, operation never
# finished bootstrapping ... Test crashed with signal kill", which reads like a
# product crash and cost a session two wasted re-runs on 2026-09-19. Two runs
# against DIFFERENT simulators are genuinely independent and should not
# serialize, so the destination id joins the key when there is one.
DEST_KEY=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-destination" ]; then
    case "$arg" in
      *id=*) DEST_KEY=$(printf '%s' "$arg" | sed -n 's/.*id=\([^,]*\).*/\1/p') ;;
      *) DEST_KEY=$(printf '%s' "$arg" | tr -c 'A-Za-z0-9' '-') ;;
    esac
  fi
  prev="$arg"
done
[ -n "$DEST_KEY" ] && DEST_KEY="-$(printf '%s' "$DEST_KEY" | tr -c 'A-Za-z0-9' '-')"

GIT_COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [ -n "$GIT_COMMON" ] && [ -d "$GIT_COMMON" ] && [ -w "$GIT_COMMON" ]; then
  LOCK_DIR="$GIT_COMMON/claude-audit-test-lock${DEST_KEY}"
else
  LOCK_DIR="${TMPDIR:-/tmp}/claude-audit-test-lock-${HASH}${DEST_KEY}"
fi
OWNER_FILE="$LOCK_DIR/owner"
TTL_SECONDS=900
WAIT_MAX=960
WAITED=0
OWNED=0
# Token identifying this process's hold on the lock, written into
# OWNER_FILE at acquisition and checked again before release.
TOKEN="$$-$RANDOM-$(date +%s 2>/dev/null || echo 0)"

# Try to atomically claim a stale-looking lock dir for removal. Returns 0
# only if THIS process won the race to rename it away; a loser's `mv` fails
# because the source no longer exists once the winner has moved it.
reap_stale() {
  local reap_dir="${LOCK_DIR}.reap.$$.${RANDOM}"
  if mv "$LOCK_DIR" "$reap_dir" 2>/dev/null; then
    rm -rf "$reap_dir"
    return 0
  fi
  return 1
}

acquire() {
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    # Stale lock? (owner died without cleanup)
    if [ -d "$LOCK_DIR" ]; then
      NOW=$(date +%s)
      LOCK_TS=$(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo "$NOW")
      if [ $((NOW - LOCK_TS)) -gt "$TTL_SECONDS" ]; then
        echo "test-lock: lock looks stale (older than ${TTL_SECONDS}s), attempting reap" >&2
        reap_stale || true
        # Whether or not our own reap won, loop back and retry mkdir --
        # never assume we hold the lock just because we decided it was
        # stale; only a winning mkdir proves ownership.
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
  # mkdir succeeded: we own the lock. Record our token so release() can
  # verify, at cleanup time, that we still own it. If the token write
  # itself fails (read-only TMPDIR, disk full), do not pretend to hold
  # the lock: an OWNED=1 with an empty/missing OWNER_FILE can never match
  # TOKEN in release(), so the lock dir would never be removed and every
  # subsequent waiter blocks until the full TTL_SECONDS reap. Fail loudly
  # and remove the directory we just created instead.
  if ! printf '%s' "$TOKEN" > "$OWNER_FILE" 2>/dev/null; then
    echo "test-lock: failed to write ownership token to $OWNER_FILE, aborting" >&2
    rm -rf "$LOCK_DIR"
    exit 74
  fi
  OWNED=1
}

release() {
  # Order matters here (bash 3.2): killing the heartbeat job BEFORE the
  # $(...) command substitution below interleaves the heartbeat's SIGCHLD
  # with the substitution's own internal subshell/wait, which corrupts
  # bash 3.2's trap bookkeeping and prints spurious internal warnings
  # ("run_pending_traps: bad value in trap_list[15]", "Terminated: 15 ...")
  # to stderr -- noise the fix-verifier would otherwise read as test
  # output. Doing the lock-directory cleanup FIRST and killing the
  # heartbeat LAST avoids the interleaving entirely (verified: 0/40 noisy
  # runs with this order vs. ~50-70% noisy with kill-first, regardless of
  # string- vs function-form trap).
  if [ "$OWNED" -eq 1 ]; then
    local current_owner
    current_owner=$(cat "$OWNER_FILE" 2>/dev/null || echo "")
    if [ "$current_owner" = "$TOKEN" ]; then
      rm -rf "$LOCK_DIR"
    fi
  fi
  kill "$HB_PID" 2>/dev/null
}

acquire
HB_PID=""
trap release EXIT INT TERM

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

# Run the wrapped command through tee so a failure can be classified without
# changing the caller-visible behavior: STATUS is still the wrapped command's
# own exit code (via PIPESTATUS), stdout/stderr still stream live. Detection
# is best-effort and fail-open -- if the temp file can't be created, fall
# back to running the command directly exactly as before.
ENV_CHECK=$(mktemp "${TMPDIR:-/tmp}/audit-test-lock-output.XXXXXX" 2>/dev/null) || ENV_CHECK=""
if [ -n "$ENV_CHECK" ]; then
  "$@" 2>&1 | tee "$ENV_CHECK"
  STATUS=${PIPESTATUS[0]}
  if [ "$STATUS" -ne 0 ] && grep -qiE 'never finished bootstrapping|crashed with signal kill|Early unexpected exit' "$ENV_CHECK" 2>/dev/null; then
    echo "TEST_LOCK_COLLISION: the test runner was killed before it connected, which is what a second concurrent run against the same simulator looks like -- not a product crash and not a failing test. Re-run once the other run has finished; the lock at $LOCK_DIR only serializes callers that go through this wrapper." >&2
  elif [ "$STATUS" -ne 0 ] && grep -qiE 'simdiskimaged|CoreSimulatorService|unable to boot device|no devices are booted|could not find.*(simulator|runtime)|no runtimes discoverable|xcresult.*(operation not permitted|permission denied)' "$ENV_CHECK" 2>/dev/null; then
    echo "TEST_LOCK_ENV_ERROR: CoreSimulator looks unreachable from this sandboxed shell (simdiskimaged/no runtimes/xcresult write denial) -- this is an environment failure, not a test failure or an incomplete fix." >&2
  fi
  rm -f "$ENV_CHECK" 2>/dev/null
else
  "$@"
  STATUS=$?
fi
exit "$STATUS"
