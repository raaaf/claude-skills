#!/usr/bin/env bash
# Deterministic FULL_AUDIT_STATUS line for /full-audit. Counts come from parsing
# the state file (.claude/audits/full-audit-state.md), NOT from the model's memory.
# Bash decides completion, not the LLM.
#
# Deliberate copy of the feature-audit/bin/status-line.sh awk pattern (different
# schema/semantics; the single-source invariant covers the audit<->full-audit pair
# only). If you fix a parser bug here, check the feature-audit twin as well.
#
# State file schema (pipe-delimited; cells must not contain a raw "|", escape as "\|"):
#   | ID | Directory | Files | Rounds | C | I | M | Status | HEAD |   (legacy German headers Verzeichnis/Dateien/Runden still parsed)
# Status values: pending | running | clean | blocked
# Header keys: post-phases: <phase>=pending | <phase>=done:<witness> | <phase>=skipped:<reason>
#   post_phases=done requires ALL THREE required phase keys (cross_ref, log,
#   issues -- the fixed set documented in references/state-file.md) to each
#   carry a witnessed "=done:<witness>" or "=skipped:<reason>", matched
#   ANCHORED to the start of that key's value. A bare "<phase>=done" with no
#   ":<witness>" (old pre-witness format, or a value written without
#   evidence) does NOT count as done. A key outside the required set (typo,
#   rename, or free text that happens to contain "=done:...") is ignored,
#   not counted -- an anchored match against an unrecognised key can no
#   longer substitute for a real one. See references/state-file.md
#   "Post-Phase Witnesses" for why (post_phases=done was reported once while
#   the cross-reference round genuinely had not run yet). A witness may
#   contain spaces (e.g. "skipped:effort was low"); only the leading
#   "key=value" token of each whitespace-separated fragment is read for a
#   known key, trailing free-text words are parsed but discarded once they
#   don't themselves look like "key=value" for a required key.
# Section "## Blocked / Needs review": bullets count as blocked items ("- none" does not).
#
# Output: exactly one line, e.g.
#   FULL_AUDIT_STATUS batches_total=3 pending=1 running=1 clean=1 blocked=0 rounds_used=3 critical=1 important=3 minor=5 blocked_items=0 post_phases=pending
#
# Usage: status-line.sh <STATE_FILE>
set -euo pipefail
FILE="${1:?usage: status-line.sh <state-file>}"

if [ ! -f "$FILE" ]; then
  echo "FULL_AUDIT_STATUS batches_total=0 pending=0 running=0 clean=0 blocked=0 rounds_used=0 critical=0 important=0 minor=0 blocked_items=0 post_phases=pending"
  exit 0
fi

awk '
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
  BEGIN{ FS="|"; status_col=0; rounds_col=0; c_col=0; i_col=0; m_col=0
         total=0; pending=0; running=0; clean=0; blocked=0
         rounds=0; crit=0; imp=0; minor=0; items=0; in_blocked=0
         # Fixed required set (see references/state-file.md). A phase key
         # outside this set -- typo, rename, or dropped -- is never counted,
         # no matter what its value looks like.
         pp_required["cross_ref"]=1; pp_required["log"]=1; pp_required["issues"]=1
         pp_n_required=3 }

  # post-phases header key: only a WITNESSED done ("=done:<witness>") or a
  # documented skip ("=skipped:<reason>") on one of the REQUIRED phase keys
  # counts -- see references/state-file.md "Post-Phase Witnesses". Two
  # defects fixed here (2026-08-11, reproduced against the committed
  # version): (1) the value match is now ANCHORED to the start of the
  # value, so a bogus value that merely CONTAINS "=done:..." as a substring
  # (e.g. "cross_ref=pending-see-log=done:1") no longer passes; (2) the key
  # is checked against the required set before its value is even looked at,
  # so a misspelled/renamed/wrong key (e.g. "zzz=done:1") can no longer
  # substitute for a real phase. Tolerant of leading whitespace (matches the
  # sibling rules below) and of a witness containing a space -- splitting on
  # runs of whitespace can turn one witness into several tokens, but only
  # the first token of a phase carries its "key=value" shape; later
  # fragments lack a required key and are dropped, not mis-attributed.
  /^[[:space:]]*post-phases:/ {
    line=$0; sub(/^[[:space:]]*post-phases:[ \t]*/,"",line)
    n=split(line, kv, /[ \t]+/)
    for(k=1;k<=n;k++){
      if(kv[k]=="") continue
      eq=index(kv[k], "=")
      if(eq==0) continue
      key=substr(kv[k],1,eq-1); val=substr(kv[k],eq+1)
      if(!(key in pp_required)) continue
      if(val ~ /^done:.+$/ || val ~ /^skipped:.+$/) pp_seen[key]=1
    }
    next
  }

  # Track the "Blocked / Needs review" section (count bullets, ignore "none").
  /^[[:space:]]*##[[:space:]]/ { in_blocked = (tolower($0) ~ /blocked/) ? 1 : 0; next }
  in_blocked && /^[[:space:]]*[-*][[:space:]]+/ {
    item=trim($0); sub(/^[-*][[:space:]]+/,"",item); l=tolower(trim(item))
    sub(/^\[[ xX]\][[:space:]]*/,"",l)
    if (l!="" && l!="none" && l!="none found" && l!="(none)") items++
    next
  }

  # Table rows.
  /^[[:space:]]*\|/ {
    if (status_col==0) {
      for(f=1;f<=NF;f++){ c=tolower(trim($f))
        if(c=="status") status_col=f
        if(c=="runden" || c=="rounds") rounds_col=f
        if(c=="c") c_col=f
        if(c=="i") i_col=f
        if(c=="m") m_col=f }
      if (status_col>0) next   # consumed the header row
    }
    if ($0 ~ /^[[:space:]]*\|[[:space:]:|-]+$/) next   # separator row
    if (status_col>0) {
      st=tolower(trim($status_col))
      if (st=="") next
      total++
      if (st=="pending") pending++
      if (st=="running") running++
      if (st=="clean")   clean++
      if (st=="blocked") blocked++
      if (rounds_col>0) { r=trim($rounds_col); sub(/\/.*$/,"",r); if (r ~ /^[0-9]+$/) rounds+=r }
      if (c_col>0) { v=trim($c_col); if (v ~ /^[0-9]+$/) crit+=v }
      if (i_col>0) { v=trim($i_col); if (v ~ /^[0-9]+$/) imp+=v }
      if (m_col>0) { v=trim($m_col); if (v ~ /^[0-9]+$/) minor+=v }
    }
  }

  END{
    pp_done_count=0
    for (rk in pp_required) if (rk in pp_seen) pp_done_count++
    pp=(pp_done_count==pp_n_required) ? "done" : "pending"
    printf "FULL_AUDIT_STATUS batches_total=%d pending=%d running=%d clean=%d blocked=%d rounds_used=%d critical=%d important=%d minor=%d blocked_items=%d post_phases=%s\n",
      total, pending, running, clean, blocked, rounds, crit, imp, minor, items, pp
  }
' "$FILE"
