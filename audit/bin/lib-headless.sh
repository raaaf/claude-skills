#!/usr/bin/env bash
#
# Shared headless runner for `claude -p` audit sessions (bench/run-case.sh), 2026-10-02.
# Source it; bash 3.2 compatible. Evidence it answers: headless sessions refused every Bash call that sourced
# lib-orchestrator.sh or called orch_*, and one session ended while the find.js Workflow still ran.
#
# `claude --help` facts used (checked 2026-10-02):
#   --allowedTools, --allowed-tools <tools...>  "Comma or space-separated list of tool names to allow (e.g. "Bash(git *) Edit")"
#   --output-format <format>                    "json" (single result): carries session_id and result
#   -r, --resume [value]                        resume by session ID; works together with -p
#   --permission-mode <mode>                    acceptEdits stays; bypassPermissions / --dangerously-skip-permissions are never used
# No flag waits for background tasks, so completion is checked by a sentinel line and the session is resumed.
#
# audit_headless_run <dir> <prompt> <sentinel> <outfile> [timeout-secs]
#   0 = sentinel seen, 124 = timed out, 3 = no sentinel after HEADLESS_MAX_RESUMES resumes, else the claude exit code.
#   Sets HEADLESS_RESUMES. <outfile> receives the readable result text of every attempt; raw JSON stays in <outfile>.json.N.
HEADLESS_MAX_RESUMES="${HEADLESS_MAX_RESUMES:-3}"
HEADLESS_POLL_SECS="${HEADLESS_POLL_SECS:-5}"
HEADLESS_RESUME_PROMPT="Warte auf laufende Workflows und schließe den Lauf ab"
HEADLESS_SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Allow list for the headless audit; one pattern per line with its purpose.
audit_headless_allowed_tools() {
  local home_skill="$HOME/.claude/skills/audit" d list=""
  for d in "$home_skill" "$HEADLESS_SKILL_DIR"; do
    case ",$list," in *",Bash(. $d/bin/*),"*) continue ;; esac
    list="$list${list:+,}"
    # source the audit lib (. and source forms), run its scripts, run node helpers
    list="${list}Bash(. $d/bin/*),Bash(source $d/bin/*),Bash(bash $d/bin/*),Bash($d/bin/*),Bash(node $d/bin/*.mjs*)"
  done
  list="$list,Bash(orch_*)"                                  # helper functions from lib-orchestrator.sh (ledger, marker, backlog, log)
  list="$list,Bash(git status*),Bash(git diff*),Bash(git log*),Bash(git show*),Bash(git rev-parse*)"   # git read commands
  list="$list,Bash(git ls-files*),Bash(git merge-base*),Bash(git branch*),Bash(git symbolic-ref*)"
  list="$list,Workflow,Skill,Agent,Read,Edit,Write,Grep,Glob"
  printf '%s' "$list"
}

# audit_headless_cmdline <prompt> [resume-session-id]: the exact claude command as a printable line.
audit_headless_cmdline() {
  printf 'claude -p %q%s --output-format json --permission-mode acceptEdits --allowedTools %q' \
    "$1" "${2:+ --resume $2}" "$(audit_headless_allowed_tools)"
}

_headless_once() { # <dir> <outfile> <timeout> <prompt> [session-id]
  local pid rc start=$SECONDS
  ( cd "$1" && exec claude -p "$4" ${5:+--resume "$5"} --output-format json --permission-mode acceptEdits \
      --allowedTools "$(audit_headless_allowed_tools)" ) > "$2" 2>&1 < /dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$3" -gt 0 ] && [ $((SECONDS - start)) -ge "$3" ]; then
      pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null
      sleep 2; pkill -KILL -P "$pid" 2>/dev/null; kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep "$HEADLESS_POLL_SECS"
  done
  wait "$pid"; rc=$?
  return "$rc"
}

# audit_headless_text <jsonfile>: the result text of a `--output-format json` run; raw content when it is no JSON.
audit_headless_text() {
  node -e '
    const raw = require("fs").readFileSync(process.argv[1], "utf8");
    try { const j = JSON.parse(raw); process.stdout.write(String(j.result ?? raw) + "\n"); }
    catch (e) { process.stdout.write(raw); }' "$1" 2>/dev/null || cat "$1"
}

audit_headless_run() {
  local dir="$1" prompt="$2" sentinel="$3" out="$4" tmo="${5:-0}" n=0 rc sid=""
  HEADLESS_RESUMES=0
  : > "$out"
  while :; do
    if [ "$n" -eq 0 ]; then _headless_once "$dir" "$out.json.$n" "$tmo" "$prompt"
    else _headless_once "$dir" "$out.json.$n" "$tmo" "$HEADLESS_RESUME_PROMPT" "$sid"; fi
    rc=$?
    { printf '== attempt %s ==\n' "$n"; audit_headless_text "$out.json.$n"; } >> "$out"
    [ "$rc" = 0 ] || return "$rc"
    grep -qF "$sentinel" "$out.json.$n" && return 0
    [ -n "$sid" ] || sid=$(grep -o '"session_id" *: *"[^"]*"' "$out.json.$n" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    if [ "$n" -ge "$HEADLESS_MAX_RESUMES" ] || [ -z "$sid" ]; then return 3; fi
    n=$((n + 1)); HEADLESS_RESUMES=$n
  done
}
