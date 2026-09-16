#!/usr/bin/env bash
#
# Every ```bash block in a SKILL.md runs in a fresh shell (Bash tool contract),
# so a block that calls an orch_* function from lib-orchestrator.sh must source
# the lib itself. This checks exactly that, mechanically, across every SKILL.md.
#
# Sourcing is recognised by the actual sourcing form, `. "$c"` / `source ` on a
# line that names lib-orchestrator.sh, NOT by the file name appearing anywhere
# in the block: the first version of this scan (an inline python one-off on
# 2026-09-16) accepted a comment that merely mentioned the lib and missed
# ship/SKILL.md's Phase 2 block, which two audit runs then reported as Critical.
#
# Usage: bash check-fresh-shell.sh [root]
# Output: `FRESH_SHELL_HIT <file>:<line> <orch_fn,...>` per offending block, then
# exactly one `FRESH_SHELL_RESULT=OK|HITS (N)|SKIP (reason)`. bash 3.2, awk only.
set -uo pipefail
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
FILES=$(ls "$ROOT"/*/SKILL.md 2>/dev/null)
[ -n "$FILES" ] || { echo "FRESH_SHELL_RESULT=SKIP (no */SKILL.md under $ROOT)"; exit 0; }
HITS=0
for f in $FILES; do
  out=$(awk -v file="${f#"$ROOT"/}" '
    function flush() {
      if (inblock && uses != "" && !sourced) { printf "FRESH_SHELL_HIT %s:%d %s\n", file, start, uses; hits++ }
      inblock=0; uses=""; sourced=0; named=0; dotted=0
    }
    /^[[:space:]]*```bash/ { flush(); inblock=1; start=NR; next }
    /^[[:space:]]*```[[:space:]]*$/ { if (inblock) flush(); next }
    inblock {
      line=$0
      # strip a trailing comment so a mention there does not count as a call or a source
      sub(/[[:space:]]#.*$/, "", line)
      # The one-line form has both on one line; the four-line prologue form has the
      # file name on the `for` line and `. "$c"` two lines later. Two flags, block-wide.
      if (line ~ /lib-orchestrator\.sh/) named=1
      if (line ~ /(^|[^A-Za-z_])(\.|source)[[:space:]]+"?\$c"?/) dotted=1
      if (named && dotted) sourced=1
      while (match(line, /orch_[a-z_]+/)) {
        fn=substr(line, RSTART, RLENGTH); line=substr(line, RSTART+RLENGTH)
        if (index(uses, fn) == 0) uses = (uses == "" ? fn : uses "," fn)
      }
    }
    END { flush(); exit hits }
  ' "$f"); rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"
  HITS=$((HITS + rc))
done
[ "$HITS" -eq 0 ] && echo "FRESH_SHELL_RESULT=OK" || echo "FRESH_SHELL_RESULT=HITS ($HITS)"
exit 0
