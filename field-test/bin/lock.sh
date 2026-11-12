#!/usr/bin/env bash
# Machine-wide simulator lock for /field-test (only one thread runs simulators or the shared :3001 backends at a time).
#
# Usage: lock.sh acquire [timeout-seconds] | release | status
#   acquire  waits (poll every FIELD_TEST_LOCK_POLL s, default 5) until the lock is free; default timeout 5400 s.
#            A lock is stale and is broken when its owner PID is no longer alive (kill -0) or it is older than 120 min.
#            Exit 0 acquired, 1 timeout, 2 usage.
#   release  removes the lock. Exit 0 always.
#   status   prints FREE or HELD <age>s <owner label>. Exit 0 free, 1 held.
# Env: FIELD_TEST_LOCK (lock dir, default ~/Developer/field-test/.sim-lock), FIELD_TEST_LABEL (owner label written on acquire),
#      FIELD_TEST_OWNER_PID (PID whose death frees the lock; default: the caller, $PPID. ios-matrix.sh passes its own).
# The lock dir holds `pid` (owner PID), `started` (epoch seconds) and `owner` (label + timestamp).
# mkdir is the atomic primitive. bash 3.2 compatible.

set -u
LOCK=${FIELD_TEST_LOCK:-$HOME/Developer/field-test/.sim-lock}
POLL=${FIELD_TEST_LOCK_POLL:-5}
STALE=7200 # 120 min max age
OWNER_PID=${FIELD_TEST_OWNER_PID:-$PPID}

age() {
  local m; m=$(cat "$LOCK/started" 2>/dev/null || stat -f %m "$LOCK" 2>/dev/null) || { echo 0; return; }
  echo $(( $(date +%s) - m ))
}
# Stale: recorded owner PID is dead, or the lock is older than STALE. A lock without a pid file (older format or the
# owner is between mkdir and the write) is only stale by age.
is_stale() {
  local p; p=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; then return 0; fi
  [ "$(age)" -gt "$STALE" ]
}

case "${1:-}" in
  acquire)
    TIMEOUT=${2:-5400}
    mkdir -p "$(dirname "$LOCK")"
    START=$(date +%s)
    while :; do
      if mkdir "$LOCK" 2>/dev/null; then
        echo "$OWNER_PID" > "$LOCK/pid"
        date +%s > "$LOCK/started"
        echo "${FIELD_TEST_LABEL:-pid $OWNER_PID} $(date +%FT%T)" > "$LOCK/owner"
        echo "lock acquired"
        exit 0
      fi
      if [ -d "$LOCK" ] && is_stale; then
        echo "lock stale (age $(age)s, owner pid $(cat "$LOCK/pid" 2>/dev/null || echo ?)), breaking" >&2
        rm -rf "$LOCK"
        continue
      fi
      [ $(( $(date +%s) - START )) -ge "$TIMEOUT" ] && { echo "lock timeout after ${TIMEOUT}s" >&2; exit 1; }
      sleep "$POLL"
    done
    ;;
  release)
    rm -rf "$LOCK"
    echo "lock released"
    ;;
  status)
    if [ -d "$LOCK" ]; then
      echo "HELD $(age)s $(cat "$LOCK/owner" 2>/dev/null)"
      exit 1
    fi
    echo FREE
    ;;
  *)
    echo "usage: lock.sh acquire [timeout-seconds] | release | status" >&2
    exit 2
    ;;
esac
