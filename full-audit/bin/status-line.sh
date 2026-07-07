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
#   | ID | Verzeichnis | Dateien | Runden | C | I | M | Status | HEAD |
# Status values: pending | running | clean | blocked
# Header keys: post-phases: cross_ref=<pending|done> log=<pending|done> issues=<pending|done>
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
         pp_total=0; pp_done=0 }

  # post-phases header key: all values done -> done, else pending.
  /^post-phases:/ {
    line=$0; sub(/^post-phases:[ \t]*/,"",line)
    n=split(line, kv, /[ \t]+/)
    for(k=1;k<=n;k++){ if(kv[k]=="") continue; pp_total++
      if(kv[k] ~ /=done$/) pp_done++ }
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
    pp=(pp_total>0 && pp_done==pp_total) ? "done" : "pending"
    printf "FULL_AUDIT_STATUS batches_total=%d pending=%d running=%d clean=%d blocked=%d rounds_used=%d critical=%d important=%d minor=%d blocked_items=%d post_phases=%s\n",
      total, pending, running, clean, blocked, rounds, crit, imp, minor, items, pp
  }
' "$FILE"
