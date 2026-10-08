#!/usr/bin/env bash
# Content-hash lock for the tests an independent oracle agent wrote (/delegate Phase 3.5).
# The executor must not change those tests or the shared test setup; Phase 5 checks.
#
# Usage:
#   oracle-lock.sh snapshot --run <id> <files...>   hash the files plus shared setup when present
#   oracle-lock.sh check    --run <id>              compare against the snapshot
#   oracle-lock.sh clear    --run <id>              drop the snapshot
#
# check prints ORACLE_CHANGED=<file> per changed or missing file, then
# ORACLE_RESULT=OK|CHANGED|NONE. NONE means no snapshot exists for the run id; the caller treats
# NONE as a failure while it expects one. Always exits 0, the verdict is in the output.
#
# Content hashes (not a PreToolUse hook) also catch edits made through Bash. State lives under the
# repo's shared git dir keyed by run id, so two sessions in one tree do not collide. Paths are
# relative to the repo top level. bash 3.2 compatible.
set -u

SHARED_SETUP="tests/Pest.php tests/TestCase.php phpunit.xml phpunit.xml.dist"

ACTION=${1:-}
[ $# -gt 0 ] && shift
RUN=""
FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --run) RUN=${2:-}; shift 2 || break ;;
    *) FILES+=("$1"); shift ;;
  esac
done
RUN=$(printf '%s' "$RUN" | tr -c 'A-Za-z0-9._-' '-')
if [ -z "$RUN" ] || [ -z "$ACTION" ]; then
  echo "usage: oracle-lock.sh snapshot|check|clear --run <id> [files...]" >&2
  exit 64
fi

TOP=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$TOP" || exit 1
GIT_COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [ -n "$GIT_COMMON" ] && [ -d "$GIT_COMMON" ] && [ -w "$GIT_COMMON" ]; then
  STATE_ROOT="$GIT_COMMON/claude-oracle-lock"
else
  STATE_ROOT="${TMPDIR:-/tmp}/claude-oracle-lock-$(printf '%s' "$TOP" | tr -c 'A-Za-z0-9' '-')"
fi
MANIFEST="$STATE_ROOT/$RUN"

hash_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

case "$ACTION" in
  snapshot)
    mkdir -p "$STATE_ROOT" || exit 1
    : > "$MANIFEST.tmp"
    for f in ${FILES[@]+"${FILES[@]}"}; do
      if [ -f "$f" ]; then
        printf '%s  %s\n' "$(hash_of "$f")" "$f" >> "$MANIFEST.tmp"
      else
        echo "oracle-lock: skipping missing file $f" >&2
      fi
    done
    for f in $SHARED_SETUP; do
      [ -f "$f" ] && printf '%s  %s\n' "$(hash_of "$f")" "$f" >> "$MANIFEST.tmp"
    done
    mv "$MANIFEST.tmp" "$MANIFEST"
    echo "ORACLE_SNAPSHOT=$(wc -l < "$MANIFEST" | tr -d ' ')"
    ;;
  check)
    if [ ! -f "$MANIFEST" ]; then echo "ORACLE_RESULT=NONE"; exit 0; fi
    CHANGED=0
    while IFS= read -r line; do
      want=${line%%  *}
      f=${line#*  }
      if [ ! -f "$f" ] || [ "$(hash_of "$f")" != "$want" ]; then
        echo "ORACLE_CHANGED=$f"
        CHANGED=1
      fi
    done < "$MANIFEST"
    if [ "$CHANGED" -eq 1 ]; then echo "ORACLE_RESULT=CHANGED"; else echo "ORACLE_RESULT=OK"; fi
    ;;
  clear)
    rm -f "$MANIFEST" "$MANIFEST.tmp"
    echo "ORACLE_CLEARED=$RUN"
    ;;
  *)
    echo "usage: oracle-lock.sh snapshot|check|clear --run <id> [files...]" >&2
    exit 64
    ;;
esac
exit 0
