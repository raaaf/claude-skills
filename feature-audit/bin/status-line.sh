#!/usr/bin/env bash
# Deterministic AUDIT_STATUS line for /feature-audit. Counts come from parsing the
# FEATURE_AUDIT.md table + the "Needs human review" section, NOT from the model's
# memory. test_exit is passed in from run-tests.sh (the real process exit code).
#
# Table schema (pipe-delimited; cells must not contain a raw "|", escape as "\|"):
#   | ID | Feature | User story | Expected behaviour | Status | Test | Notes |
# Status values: todo | tested | passing | failing
#
# Usage: status-line.sh <FEATURE_AUDIT.md> <test_exit>
set -euo pipefail
FILE="${1:?usage: status-line.sh <file> <test_exit>}"
TEST_EXIT="${2:-none}"

if [ ! -f "$FILE" ]; then
  echo "AUDIT_STATUS total=0 with_story=0 tested=0 passing=0 failing=0 needs_review=0 test_exit=$TEST_EXIT"
  exit 0
fi

awk -v texit="$TEST_EXIT" '
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
  BEGIN{ FS="|"; story_col=0; status_col=0; in_review=0;
         total=0; with_story=0; tested=0; passing=0; failing=0; needs=0 }

  # Track the "Needs human review" section (count bullets, ignore "none"/placeholders).
  /^[[:space:]]*##[[:space:]]/ { in_review = (tolower($0) ~ /needs human review/) ? 1 : 0; next }
  in_review && /^[[:space:]]*[-*][[:space:]]+/ {
    item=trim($0); sub(/^[-*][[:space:]]+/,"",item); l=tolower(trim(item))
    if (l!="" && l!="none" && l!="none found" && l!="(none)") needs++
    next
  }

  # Table rows.
  /^[[:space:]]*\|/ {
    # Locate columns from the header row (first table row that has a "Status" cell).
    if (status_col==0) {
      for(i=1;i<=NF;i++){ c=tolower(trim($i));
        if(c=="status") status_col=i;
        if(c=="user story") story_col=i }
      if (status_col>0) next   # consumed the header row
    }
    # Skip the markdown separator row (| --- | --- |).
    if ($0 ~ /^[[:space:]]*\|[[:space:]:|-]+$/) next
    if (status_col>0) {
      st=tolower(trim($status_col))
      if (st=="") next         # not a real data row
      total++
      if (story_col>0 && trim($story_col)!="") with_story++
      if (st!="todo") tested++
      if (st=="passing") passing++
      if (st=="failing") failing++
    }
  }

  END{
    printf "AUDIT_STATUS total=%d with_story=%d tested=%d passing=%d failing=%d needs_review=%d test_exit=%s\n",
      total, with_story, tested, passing, failing, needs, texit
  }
' "$FILE"
