#!/usr/bin/env bash
#
# PreToolUse hook for the /audit skill.
#
# Blocks `git push` invocations unless a recent audit-passed marker exists for
# the current working directory. The marker is written by the /audit skill
# itself when an audit run completes cleanly and is valid for 30 minutes.
#
# Input: Claude Code PreToolUse hook payload on stdin (JSON with
# `tool_input.command` and `cwd`).
#
# Exit codes:
#   0 — allow the tool call (no push detected, or marker is fresh)
#   1 — block the tool call and surface the stderr message to Claude
set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command')

# Match `git push` even with flags/options before the subcommand. Also matches
# chained commands (`foo && git push`, `foo; git push`, `foo | git push`).
if ! echo "$cmd" | grep -qE '(^|&&|;|\|)\s*git\s+((-[A-Za-z]|--[a-z-]+)(\s+\S+)?\s+)*push'; then
  exit 0
fi

cwd=$(echo "$input" | jq -r '.cwd')
hash=$(echo -n "$cwd" | md5 2>/dev/null || echo -n "$cwd" | md5sum 2>/dev/null | cut -d' ' -f1)
marker="/tmp/claude-audit-passed-$hash"

# Marker valid for 30 minutes (1800 s). If fresh, allow the push.
# Do NOT delete the marker here — multiple hooks may check the same marker
# sequentially. The marker expires via TTL (30 min) and is harmless after that.
marker_mtime=$(stat -f%m "$marker" 2>/dev/null || stat -c%Y "$marker" 2>/dev/null || echo 0)
if [ "$marker_mtime" -gt 0 ] && [ $(( $(date +%s) - marker_mtime )) -lt 1800 ]; then
  exit 0
fi

echo 'BLOCKED: Kein /audit-Marker vorhanden. Du MUSST den User ZUERST per AskUserQuestion fragen ob er /audit laufen lassen moechte. Starte NIEMALS automatisch den Audit. Frage: "Vor dem Push wurde kein /audit ausgefuehrt. Soll ich den Audit jetzt starten?" Optionen: "Ja, Audit starten" / "Nein, direkt pushen". Erst NACH der Antwort handeln.' >&2
exit 1
