#!/usr/bin/env bash
# One iOS cell for /field-test: creates a throwaway simulator, sets appearance and Dynamic Type size, runs the product's
# ScreensCatalogTests (screens/references/platform-apple.md) and copies the PNGs to <out>. Takes the machine-wide
# simulator lock (lock.sh) for the whole cell. The trap shuts down and deletes ONLY the simulator this run created,
# removes its temp dir and releases the lock it took, also on error or SIGTERM.
#
# Usage: ios-matrix.sh --root <project root> --xcodeproj <path rel. to root> --scheme <name> --ui-target <name>
#          --product <name> --device "<simctl device type name>" --size <content size> --appearance light|dark
#          --out <dir> [--entries id1,id2] [--lock-timeout <s>] [--timeout <s>]
#   --device      exact `xcrun simctl list devicetypes` name, e.g. "iPhone SE (3rd generation)". Missing type: exit 3.
#   --size        simctl content size: extra-small ... large (default) ... extra-extra-extra-large,
#                 accessibility-medium ... accessibility-extra-extra-extra-large.
#   --entries     manifest entry ids (TEST_RUNNER_SCREENS_ENTRIES); empty = every entry of the platform.
#   --lock-timeout wait for the simulator lock (default 5400 s). --timeout xcodebuild wall clock (default 2400 s).
# PNG names: <entry>__<state>__<role>__<device slug>-<size>__<appearance>.png (the test builds them from
# SCREENS_VIEWPORT_ID and SCREENS_THEME).
# Exit: 0 at least one PNG copied, 1 xcodebuild failed or no PNG, 2 usage, 3 device type missing, 4 lock timeout.
# Env: FIELD_TEST_DERIVED_DATA (default ~/Library/Developer/Xcode/DerivedData/<product>-field-test-sim).
# bash 3.2 compatible.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=""; PROJ=""; SCHEME=""; UITARGET=""; PRODUCT=""; DEVICE=""; SIZE="large"; APPEAR=""; OUT=""; ENTRIES=""; LOCK_TO=5400; RUN_TO=2400
usage() { sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --root) ROOT=$2;; --xcodeproj) PROJ=$2;; --scheme) SCHEME=$2;; --ui-target) UITARGET=$2;; --product) PRODUCT=$2;;
    --device) DEVICE=$2;; --size) SIZE=$2;; --appearance) APPEAR=$2;; --out) OUT=$2;; --entries) ENTRIES=$2;;
    --lock-timeout) LOCK_TO=$2;; --timeout) RUN_TO=$2;;
    *) usage;;
  esac
  shift 2
done
for v in ROOT PROJ SCHEME UITARGET PRODUCT DEVICE APPEAR OUT; do eval "[ -n \"\$$v\" ]" || usage; done
case "$APPEAR" in light|dark) ;; *) usage;; esac
[ -f "$ROOT/.screens/manifest.json" ] || { echo "ios-matrix: $ROOT/.screens/manifest.json missing" >&2; exit 2; }
ROOT=$(cd "$ROOT" && pwd -P); mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd -P)

UDID=""; TMP=""; LOCKED=0; WATCHDOG=""
cleanup() {
  [ -n "$WATCHDOG" ] && kill "$WATCHDOG" 2>/dev/null
  if [ -n "$UDID" ]; then xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl delete "$UDID" >/dev/null 2>&1; fi
  [ -n "$TMP" ] && rm -rf "$TMP"
  [ "$LOCKED" = 1 ] && bash "$HERE/lock.sh" release >/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# Device type and newest iOS runtime; no lock needed for the lookup.
TYPE_ID=$(xcrun simctl list devicetypes -j | python3 -c '
import json,sys
name=sys.argv[1]
for t in json.load(sys.stdin)["devicetypes"]:
    if t["name"]==name: print(t["identifier"]); break' "$DEVICE")
[ -n "$TYPE_ID" ] || { echo "ios-matrix: device type \"$DEVICE\" does not exist (xcrun simctl list devicetypes)" >&2; exit 3; }
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
tid=sys.argv[1]
rs=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r.get("platform","iOS")=="iOS"
    and any(d.get("identifier")==tid for d in r.get("supportedDeviceTypes",[]))]
rs.sort(key=lambda r:[int(x) for x in r["version"].split(".") if x.isdigit()])
print(rs[-1]["identifier"] if rs else "")' "$TYPE_ID")
[ -n "$RUNTIME" ] || { echo "ios-matrix: no available iOS runtime supports "$DEVICE"" >&2; exit 1; }

FIELD_TEST_OWNER_PID=$$ FIELD_TEST_LABEL="$PRODUCT ios $(date +%FT%T)" bash "$HERE/lock.sh" acquire "$LOCK_TO" >&2 || exit 4
LOCKED=1

SLUG=$(printf '%s' "$DEVICE" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')
# $$ keeps the name unique, so cleanup can never delete a simulator this run did not create.
UDID=$(xcrun simctl create "field-test-$PRODUCT-$SLUG-$$" "$TYPE_ID" "$RUNTIME") || { UDID=""; echo "ios-matrix: simctl create failed" >&2; exit 1; }
xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || { echo "ios-matrix: boot failed" >&2; exit 1; }
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl ui "$UDID" appearance "$APPEAR"
xcrun simctl ui "$UDID" content_size "$SIZE"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/field-test-ios.XXXXXX")
DD=${FIELD_TEST_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/$PRODUCT-field-test-sim}
LOG="$TMP/xcodebuild.log"
cd "$ROOT" || exit 1
TEST_RUNNER_SCREENS_MANIFEST_PATH="$ROOT/.screens/manifest.json" \
TEST_RUNNER_SCREENS_CONFIG_PATH="$ROOT/.screens/config.json" \
TEST_RUNNER_SCREENS_ENTRIES="$ENTRIES" \
TEST_RUNNER_SCREENSHOT_DIR="$TMP" \
TEST_RUNNER_SCREENS_THEME="$APPEAR" \
TEST_RUNNER_SCREENS_VIEWPORT_ID="$SLUG-$SIZE" \
TEST_RUNNER_SCREENS_PROJECT_ROOT="$ROOT" \
nice -n 10 xcodebuild test -project "$PROJ" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" \
  -only-testing:"$UITARGET/ScreensCatalogTests" >"$LOG" 2>&1 &
XB=$!
( sleep "$RUN_TO"; kill "$XB" 2>/dev/null ) & WATCHDOG=$!
wait "$XB"; XB_RC=$?

N=0
for f in "$TMP"/*.png; do [ -f "$f" ] && cp "$f" "$OUT/" && N=$((N+1)); done
echo "ios-matrix: xcodebuild exit $XB_RC, $N PNG(s) -> $OUT"
if [ "$N" -eq 0 ] || [ "$XB_RC" -ne 0 ]; then
  grep -E "error:|\*\* TEST|Test Case .*failed|BUILD FAILED" "$LOG" | tail -n 8 >&2
fi
[ "$N" -gt 0 ] && exit 0
exit 1
