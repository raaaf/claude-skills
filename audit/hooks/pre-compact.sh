#!/usr/bin/env bash
# pre-compact.sh — Block auto-compaction while an audit WAVE is in flight.
# Exit 2 = block compaction. Exit 0 = allow.
#
# Registered globally in ~/.claude/settings.json under PreCompact, via the same fail-open probe
# the audit skill uses for its PreToolUse hook (see SKILL.md frontmatter): the settings entry
# looks for this file in the known install locations and exits 0 when none matches, so a missing
# install never blocks compaction in an unrelated project. It lives here, in the skill, so it is
# versioned and synced with the rules it enforces — an unversioned copy under ~/.claude/hooks/
# drifts from references/context-budget.md the moment either one changes.
#
# Scope is a wave, not a run. The window that actually needs protection is the one where
# findings live only in context: between dispatching a wave and writing its results to the
# audit log + state file. Once a round is persisted, compaction is safe by design —
# audit/references/state-file.md: the loop state "survives session death, context compaction,
# and interruptions".
#
# The marker used to be set once at run start with a 3h stale window, which blocked compaction
# for the whole run. Measured cost on a 2026-08-27 full-audit: context grew to 989k token and
# averaged 503k over 2860 turns = 1440M cache-read token for 4M output. The audits were not
# expensive because of their fan-out; they were expensive because nothing was ever allowed to
# shrink. See audit/references/context-budget.md.

CWD_HASH=$(pwd | md5 2>/dev/null || pwd | md5sum 2>/dev/null | cut -d' ' -f1)
MARKER="/tmp/claude-audit-in-progress-${CWD_HASH}"

# A wave is minutes, not hours. A marker older than this is a leak (crashed run, forgotten
# release) and must not keep costing the budget — the state file makes recovery cheap anyway.
MAX_WAVE_AGE=1200   # 20 minutes

if [ -f "$MARKER" ]; then
  MTIME=$(stat -f%m "$MARKER" 2>/dev/null || stat -c%Y "$MARKER" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  AGE=$(( NOW - MTIME ))
  if [ "$AGE" -lt "$MAX_WAVE_AGE" ]; then
    echo "PreCompact blocked: audit wave in flight (marker age: ${AGE}s). Compaction deferred." >&2
    exit 2
  fi
  echo "PreCompact: stale wave marker (${AGE}s > ${MAX_WAVE_AGE}s) — releasing, compaction allowed." >&2
  rm -f "$MARKER"
fi

exit 0
