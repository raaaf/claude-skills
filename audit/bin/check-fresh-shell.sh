#!/usr/bin/env bash
#
# Every ```bash block in a SKILL.md runs in a fresh shell (Bash tool contract). Two
# things therefore do not survive from one block to the next, and this checks both,
# mechanically, across every SKILL.md:
#
# 1. FUNCTIONS. A block that calls an orch_* function from lib-orchestrator.sh must
#    source the lib itself. Sourcing is recognised by the actual sourcing form,
#    `. "$c"` / `source ` on a line that names lib-orchestrator.sh, NOT by the file
#    name appearing anywhere in the block: the first version of this scan (an inline
#    python one-off on 2026-09-16) accepted a comment that merely mentioned the lib
#    and missed ship/SKILL.md's Phase 2 block, which two audit runs then reported as
#    Critical.
# 2. VARIABLES. A block that expands an uppercase variable it does not set itself is
#    reading a value from an earlier block, which is empty in a fresh shell; three
#    audit runs (8, 10, 11 of 2026-09-16) each found one by hand. Such a block must
#    call orch_state_load, and the name must be saved by an orch_state_save in the
#    same SKILL.md (lib-orchestrator.sh header). Names a block sets itself
#    (assignment, read, for, local, export, printf -v, or the lib setters
#    orch_resolve_audit_root / orch_parse_stripe / orch_state_load) and the few
#    environment names below are not reads of an earlier block. A save of a name the
#    saving block never set is a hit too: it would store empty and mask the read.
#
# Scanned: every */SKILL.md and every */references/*.md (a reference's block runs as a
# fresh shell exactly like the orchestrator's). The set of saved names is collected
# across ALL scanned files first, because the state dir is shared per cwd and one
# skill runs another's blocks (/full-audit runs /audit's Phases 2-5, and its own scope
# walk lives in references/scope.md).
#
# Usage: bash check-fresh-shell.sh [root]
# Output: `FRESH_SHELL_HIT <file>:<line> <detail>` per offending block, then exactly
# one `FRESH_SHELL_RESULT=OK|HITS (N)|SKIP (reason)`. bash 3.2, awk only.
set -uo pipefail
ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
FILES=$(ls "$ROOT"/*/SKILL.md "$ROOT"/*/references/*.md 2>/dev/null)
[ -n "$FILES" ] || { echo "FRESH_SHELL_RESULT=SKIP (no */SKILL.md under $ROOT)"; exit 0; }
# pass 1: every name any orch_state_save in any scanned file carries
SAVED_NAMES=$(cat $FILES | awk '
  /^[[:space:]]*```bash/ { b=1; next } /^[[:space:]]*```[[:space:]]*$/ { b=0; next }
  b { line=$0; sub(/[[:space:]]#.*$/, "", line)
      while (match(line, /orch_state_save([ ]+[A-Z][A-Z0-9_]+)+/)) {
        k=split(substr(line, RSTART, RLENGTH), p, " "); for (i=2; i<=k; i++) if (p[i] != "") print p[i]
        line=substr(line, RSTART+RLENGTH) } }' | sort -u | tr '\n' ' ')
# Names that legitimately come from outside any block: the session environment, the
# skill runtime ($ARGUMENTS is substituted before the model sees the file), and the
# perf-measure eval output. The headless inputs AUDIT_DIMENSIONS and AUDIT_FIX_SCOPE are
# deliberately NOT here: a block reads them as `NAME="${NAME:-...}"`, an assignment, and a bare
# read of AUDIT_DIMENSIONS in a later block was exactly the run-10 Critical.
ENV_NAMES="HOME PWD TMPDIR PATH CLAUDE_SKILL_DIR CLAUDE_EFFORT CLAUDE_PROJECT_DIR ARGUMENTS OSTYPE IFS RANDOM USER PERF_MEASURE_CMD"
HITS=0
for f in $FILES; do
  out=$(awk -v file="${f#"$ROOT"/}" -v envnames="$ENV_NAMES" -v savednames="$SAVED_NAMES" '
    function flush(   n, vars, badsave) {
      if (inblock) {
        if (uses != "" && !sourced) { printf "FRESH_SHELL_HIT %s:%d %s\n", file, start, uses; hits++ }
        vars=""
        for (n in reads) {
          if (n in sets || n in env) continue
          if (loads && (n in saved)) continue
          vars = vars " " n (loads ? " (never saved)" : "")
        }
        if (vars != "") { printf "FRESH_SHELL_HIT %s:%d vars:%s\n", file, start, vars; hits++ }
        badsave=""
        for (n in savesHere) if (!(n in sets)) badsave = badsave " " n
        if (badsave != "") { printf "FRESH_SHELL_HIT %s:%d save-unset:%s\n", file, start, badsave; hits++ }
      }
      inblock=0; uses=""; sourced=0; named=0; dotted=0; loads=0
      delete reads; delete sets; delete savesHere
    }
    function noteSets(line,   tmp, n) {
      tmp=line
      while (match(tmp, /(^|[^A-Za-z0-9_$])[A-Z][A-Z0-9_]+=/)) {
        n=substr(tmp, RSTART, RLENGTH); sub(/^[^A-Z]/, "", n); sub(/=$/, "", n); sets[n]=1
        tmp=substr(tmp, RSTART+RLENGTH)
      }
      tmp=line
      while (match(tmp, /(read [^;|]*|for |export |local |printf -v )[A-Z][A-Z0-9_]+/)) {
        n=substr(tmp, RSTART, RLENGTH); sub(/.*[ ]/, "", n); sets[n]=1
        tmp=substr(tmp, RSTART+RLENGTH)
      }
      if (line ~ /orch_resolve_audit_root/) { sets["AUDIT_ROOT"]=1; sets["AUDIT_BIN"]=1; sets["AUDIT_AGENTS_DIR"]=1 }
      if (line ~ /orch_parse_stripe/) { sets["STRIPE"]=1; sets["STRIPE_MODE"]=1; sets["STRIPE_RECURRING"]=1; sets["STRIPE_FILES"]=1 }
    }
    function noteReads(line,   tmp, n) {
      tmp=line
      while (match(tmp, /\$\{?[A-Z][A-Z0-9_]+/)) {
        n=substr(tmp, RSTART, RLENGTH); sub(/^\$\{?/, "", n); reads[n]=1
        tmp=substr(tmp, RSTART+RLENGTH)
      }
    }
    function noteSaves(line,   tmp, i, k, parts) {
      # orch_state_save A B C   -> every following word up to a shell separator is a name
      tmp=line
      while (match(tmp, /orch_state_save([ ]+[A-Z][A-Z0-9_]+)+/)) {
        k=split(substr(tmp, RSTART, RLENGTH), parts, " ")
        for (i=2; i<=k; i++) if (parts[i] != "") { saved[parts[i]]=1; savesHere[parts[i]]=1 }
        tmp=substr(tmp, RSTART+RLENGTH)
      }
    }
    BEGIN {
      n=split(envnames, e, " "); for (i=1; i<=n; i++) env[e[i]]=1
      n=split(savednames, e, " "); for (i=1; i<=n; i++) if (e[i] != "") saved[e[i]]=1
    }
    /^[[:space:]]*```bash/ { flush(); inblock=1; start=NR; next }
    /^[[:space:]]*```[[:space:]]*$/ { if (inblock) flush(); next }
    inblock {
      line=$0
      # strip a trailing or whole-line comment so a mention there is neither a call, a source nor a read
      sub(/[[:space:]]#.*$/, "", line); sub(/^[[:space:]]*#.*$/, "", line)
      # The one-line form has both on one line; the four-line prologue form has the
      # file name on the `for` line and `. "$c"` two lines later. Two flags, block-wide.
      if (line ~ /lib-orchestrator\.sh/) named=1
      if (line ~ /(^|[^A-Za-z_])(\.|source)[[:space:]]+"?\$c"?/) dotted=1
      if (named && dotted) sourced=1
      if (line ~ /orch_state_load/) loads=1
      tmp=line
      while (match(tmp, /orch_[a-z_]+/)) {
        fn=substr(tmp, RSTART, RLENGTH); tmp=substr(tmp, RSTART+RLENGTH)
        if (index(uses, fn) == 0) uses = (uses == "" ? fn : uses "," fn)
      }
      noteSets(line); noteReads(line); noteSaves(line)
    }
    END { flush(); exit hits }
  ' "$f"); rc=$?
  [ -n "$out" ] && printf '%s\n' "$out"
  HITS=$((HITS + rc))
done
[ "$HITS" -eq 0 ] && echo "FRESH_SHELL_RESULT=OK" || echo "FRESH_SHELL_RESULT=HITS ($HITS)"
exit 0
