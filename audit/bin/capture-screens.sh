#!/usr/bin/env bash
#
# Captures before/after screenshots for a visual change, with no project
# dependency: headless Chrome for web, `simctl` for a booted iOS simulator.
# Used by /delegate (visual task: once before the executor runs, once after the
# review), never on its own schedule.
#
# Deliberately not an MCP call. The browser-pane and devtools tools cannot be
# reached from a subagent or a plain shell, and a capture step that only works
# in the orchestrator's own turn is a capture step that gets skipped.
#
# Usage:
#   bash capture-screens.sh --label before --url http://localhost:5173 [--name home]
#   bash capture-screens.sh --label after  --ios [--name settings]
#
# Output: one `SCREENSHOT <path>` line per file written, then exactly one
# `CAPTURE_RESULT=OK (N)|SKIP (reason)|FAIL (reason)` line. Always exits 0: a
# missing browser or a sleeping simulator must never fail the task it documents.
#
# Files land in `<repo>/.claude/screenshots/<label>/`, which is added to
# .gitignore when nothing already covers it (same `git check-ignore` courtesy as
# cache-write.sh: never a redundant append, never a silent one).
#
# bash 3.2 compatible. BSD-safe.
set -uo pipefail

LABEL=""; URL=""; NAME="screen"; IOS=0
VIEWPORTS="1440x900 390x844"

while [ $# -gt 0 ]; do
  case "$1" in
    --label)     LABEL="${2:-}"; shift 2 ;;
    --url)       URL="${2:-}"; shift 2 ;;
    --name)      NAME="${2:-}"; shift 2 ;;
    --ios)       IOS=1; shift ;;
    --viewports) VIEWPORTS="${2:-}"; shift 2 ;;
    *) echo "CAPTURE_RESULT=FAIL (unknown argument: $1)"; exit 0 ;;
  esac
done

case "$LABEL" in
  before|after) ;;
  *) echo "CAPTURE_RESULT=FAIL (--label must be 'before' or 'after')"; exit 0 ;;
esac

# Slug the name so a route path cannot escape the output directory.
NAME=$(printf '%s' "$NAME" | tr '/' '-' | tr -cd 'A-Za-z0-9._-')
[ -n "$NAME" ] || NAME="screen"

COUNT=0

# Deferred on purpose: a run that captures nothing must not touch the repo.
# The first version created the directory and appended to .gitignore before it
# knew whether there was anything to shoot, and a bare smoke test mutated the
# skills repo itself.
prepare_out() {
  REPO=$(git rev-parse --show-toplevel 2>/dev/null) || REPO="$PWD"
  OUT="$REPO/.claude/screenshots/$LABEL"
  mkdir -p "$OUT" 2>/dev/null || { echo "CAPTURE_RESULT=FAIL (cannot create $OUT)"; exit 0; }

  # .gitignore courtesy: only when no existing rule already covers the path, and
  # never silently. A tracked file cannot be un-tracked by a .gitignore line, so
  # that case warns instead of appending.
  IGNORE_PATH=".claude/screenshots/"
  if git rev-parse --git-dir >/dev/null 2>&1; then
    if ! git -C "$REPO" check-ignore -q "$OUT" 2>/dev/null; then
      if git -C "$REPO" ls-files --error-unmatch "$IGNORE_PATH" >/dev/null 2>&1; then
        echo "NOTE $IGNORE_PATH is tracked; .gitignore cannot un-track it, screenshots will show up in the diff"
      else
        printf '%s\n' "$IGNORE_PATH" >> "$REPO/.gitignore" 2>/dev/null &&
          echo "NOTE added '$IGNORE_PATH' to .gitignore"
      fi
    fi
  fi
}

if [ "$IOS" -eq 1 ]; then
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "CAPTURE_RESULT=SKIP (xcrun not available)"; exit 0
  fi
  if ! xcrun simctl list devices booted 2>/dev/null | grep -q "Booted"; then
    echo "CAPTURE_RESULT=SKIP (no booted simulator; boot one or run the app first)"; exit 0
  fi
  prepare_out
  TARGET="$OUT/$NAME--ios.png"
  if xcrun simctl io booted screenshot "$TARGET" >/dev/null 2>&1; then
    echo "SCREENSHOT $TARGET"; COUNT=$((COUNT + 1))
  else
    echo "CAPTURE_RESULT=FAIL (simctl screenshot failed)"; exit 0
  fi
  echo "CAPTURE_RESULT=OK ($COUNT)"
  exit 0
fi

if [ -z "$URL" ]; then
  echo "CAPTURE_RESULT=SKIP (no --url and no --ios; nothing to capture)"; exit 0
fi

CHROME=""
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "/Applications/Chromium.app/Contents/MacOS/Chromium" \
         "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"; do
  [ -x "$c" ] && { CHROME="$c"; break; }
done
if [ -z "$CHROME" ]; then
  echo "CAPTURE_RESULT=SKIP (no Chrome/Chromium/Brave found for headless capture)"; exit 0
fi

# Reachability first: headless Chrome writes a PNG of an error page just as
# happily as of the real one, and a screenshot of "connection refused" is worse
# than no screenshot because it looks like a result.
if command -v curl >/dev/null 2>&1; then
  if ! curl -s -o /dev/null --max-time 10 "$URL"; then
    echo "CAPTURE_RESULT=SKIP (nothing serving $URL; start the dev server first)"; exit 0
  fi
fi

# Wait for the FILE, not for the process. Chrome writes the screenshot within a
# few seconds and then lingers (its updater and crash-handler children keep the
# process group alive), so waiting on exit reported a timeout for captures that
# had in fact already succeeded. `timeout(1)` is not on a stock macOS either,
# hence the hand-rolled poll.
capture_bounded() {
  limit="$1"; target="$2"; shift 2
  rm -f "$target" 2>/dev/null
  "$@" >/dev/null 2>&1 &
  pid=$!
  waited=0
  while [ "$waited" -lt "$limit" ]; do
    if [ -s "$target" ]; then
      # The file can still be mid-write; one more second, then stop Chrome.
      sleep 1
      kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
    waited=$((waited + 1))
  done
  kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  [ -s "$target" ] && return 0
  return 124
}

prepare_out
PROFILE_DIR=$(mktemp -d 2>/dev/null) || PROFILE_DIR="${TMPDIR:-/tmp}/capture-screens-profile.$$"
mkdir -p "$PROFILE_DIR" 2>/dev/null
trap 'rm -rf "$PROFILE_DIR" 2>/dev/null' EXIT

for vp in $VIEWPORTS; do
  W="${vp%x*}"; H="${vp#*x}"
  TARGET="$OUT/$NAME--${W}x${H}.png"
  # --user-data-dir into a throwaway profile: without it headless refuses to
  # start while the user has Chrome open, and it would otherwise touch their
  # real profile.
  # --headless=new explicitly: the bare flag resolves to the old mode on some
  # builds and never returns.
  capture_bounded 30 "$TARGET" "$CHROME" --headless=new --disable-gpu \
    --hide-scrollbars --no-first-run --user-data-dir="$PROFILE_DIR" \
    --virtual-time-budget=4000 \
    --window-size="$W,$H" --screenshot="$TARGET" "$URL"
  rc=$?
  if [ "$rc" -eq 124 ]; then
    echo "NOTE headless capture timed out at ${W}x${H}"
  elif [ -s "$TARGET" ]; then
    echo "SCREENSHOT $TARGET"; COUNT=$((COUNT + 1))
  fi
done

if [ "$COUNT" -eq 0 ]; then
  echo "CAPTURE_RESULT=FAIL (headless capture produced no file)"
else
  echo "CAPTURE_RESULT=OK ($COUNT)"
fi
exit 0
