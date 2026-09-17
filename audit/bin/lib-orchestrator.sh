#!/usr/bin/env bash
#
# Shared library: the orchestrator prologue every skill used to paste.
# Sourced by the bash blocks in audit/, full-audit/, design-audit/, delegate/,
# ship/ and plan-it/ SKILL.md. Before 2026-09-16 each of them carried its own
# copy of helper resolution, cwd hashing, the in-progress marker, the Stripe
# parse and the agent-roster guard, with variations; three audit runs named
# the drift as one condition, so it is one file now.
#
# EVERY BASH BLOCK IS A FRESH SHELL. The Bash tool starts a new process per block, so a
# function sourced in Phase 1 does not exist in Phase 4 (the pre-refactor SKILL.md files
# re-declared AUDIT_BIN in Phase 4 for exactly this reason, and the 2026-09-16 audit found
# seven blocks calling orch_* after that re-declaration had been refactored away). The
# rule: every block that calls an orch_ function begins with this one line, verbatim:
#
#   for c in "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit/bin/lib-orchestrator.sh" "$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; do [ -f "$c" ] && { . "$c"; break; }; done
#
# audit/SKILL.md, which owns this bin/, lists "${CLAUDE_SKILL_DIR}/bin/lib-orchestrator.sh"
# first; every other skill uses the line above verbatim (full-audit carried a third,
# CLAUDE_PROJECT_DIR-derived candidate until 2026-09-16; that variable exists only in hooks). The
# guard after the line names the first function the block needs (`type orch_run_log` in
# delegate/ship/plan-it, `type orch_resolve_audit_root` in the three audit skills); the
# difference is intentional, not drift. A block that only sets shell variables from a
# previous block's output cannot exist: re-derive or re-read, never assume.
#
# VARIABLES DO NOT CROSS BLOCKS EITHER. Runs 8, 10 and 11 of 2026-09-16 each found one
# (`TEST_COMMAND`, `AUDIT_DIMENSIONS`, `STRIPE_FILES`): set in one block, tested in a later one
# where it was empty, and the test silently took the wrong branch. The mechanism since then is
# orch_state_save / orch_state_load: a block that produces a value a later block needs ends with
# `orch_state_save NAME...`, and every block that reads a carried value calls `orch_state_load`
# right after the source line. The state dir is cleared by orch_progress_claim (a new run starts
# empty), so a value that was never saved this run reads as unset, never as last run's.
# check-fresh-shell.sh enforces both halves: a block reading a variable it did not set must load,
# and the name must be saved by some scanned SKILL.md or references block (the state dir is shared per cwd).
#
# Functions (all bash 3.2, no arrays exported, no side effects beyond the
# variables named):
#   orch_resolve_audit_root   sets AUDIT_ROOT, AUDIT_BIN, AUDIT_AGENTS_DIR; returns 1 if none found
#   orch_helper <script.sh>   prints "$AUDIT_BIN/<script>" if it exists, else nothing (rc 1)
#   orch_hash_passed          md5 of $PWD WITHOUT newline  -> /tmp/claude-audit-passed-*
#   orch_hash_progress        md5 of pwd  WITH newline     -> /tmp/claude-audit-in-progress-*
#   orch_progress_claim | orch_progress_touch | orch_progress_release   (claim also clears the state dir; every marker access refuses a symlink or a file another user owns)
#   orch_state_save NAME...   writes each named variable's value to the run's state dir (one file per name)
#   orch_state_load           reads every saved variable back into the current shell; the answer to
#                             "a value set in an earlier block" (see the block rule below)
#   orch_state_clear          removes the state dir; called by orch_progress_claim, and by skills without a claim (ship) at their start
#   orch_tree_hash            tree object id of the working tree (tracked files) via `git stash create`, HEAD's tree when clean
#   orch_marker_write         writes orch_tree_hash into /tmp/claude-audit-passed-*; the marker certifies a tree, not a moment
#   orch_marker_matches       rc 0 when the passed marker's tree equals orch_tree_hash now, rc 2 when the
#                             delta is prose-only (classify-diff.sh --paths), rc 1 otherwise
#   orch_marker_delta         prints the paths that changed since the marker's tree
#   orch_url_host <url>       prints the host of an http(s) URL (userinfo dropped, [IPv6] kept whole), else nothing
#   orch_host_public <host>   rc 0 unless loopback/private/link-local/ULA/mapped, *.local/*.internal, or a
#                             numeric host that is not a canonical dotted quad (decimal, octal, hex, short forms)
#   orch_verify_agents        runs verify-agents.sh against AUDIT_AGENTS_DIR; returns its rc
#   orch_parse_stripe [root]  sets STRIPE, STRIPE_MODE, STRIPE_RECURRING, STRIPE_FILES
#   orch_run_log <args...>    calls run-log.sh if present; never fails the caller
#   orch_patterns_from_file recur|dismissed <file>   feeds patterns-store.sh one line at a time, each as one argv element
#   orch_ship_value <key> [root]   prints `<key>:` from .claude/ship.md (test-command, deploy-command, health-check), else nothing (rc 1)
#   orch_test_command_declared [root]   = orch_ship_value test-command
#   orch_test_command [root]  declared value, else a manifest guess (composer/npm/swift/pytest), else nothing (rc 1)
#   orch_frontend_ext_re      prints FRONTEND_EXT_RE from lib-git-base.sh (literal fallback mirrors collect-scope.sh)
#   orch_payments_guidelines <matches>   prints GUIDELINE_MATCHES with payments.md appended when missing
#   orch_payments_floor <dims> <stripe_files> <root> <floor_json>   merges the payments scout floor into FLOOR_FILES
#
# The two hash conventions are deliberately two functions with two names. They
# differ by one trailing newline, reading one family with the other produces a
# different hash, and that exact mix-up broke /ship's audit gate once (CLAUDE.md
# Gotchas). Callers name the family they mean.

orch__md5() {
  # stdin -> hex digest, macOS (md5) or coreutils (md5sum)
  if command -v md5 >/dev/null 2>&1; then md5
  else md5sum | cut -d' ' -f1
  fi
}

orch_hash_passed()   { printf '%s' "$PWD" | orch__md5; }
orch_hash_progress() { pwd | orch__md5; }

orch_resolve_audit_root() {
  AUDIT_ROOT=""
  local c
  for c in "${CLAUDE_SKILL_DIR:-}" \
           "$(dirname "${CLAUDE_SKILL_DIR:-/nonexistent}")/audit" \
           "$HOME/.claude/skills/audit"; do
    [ -n "$c" ] && [ -d "$c/agents" ] && [ -f "$c/bin/verify-agents.sh" ] && { AUDIT_ROOT="$c"; break; }
  done
  [ -n "$AUDIT_ROOT" ] || return 1
  AUDIT_BIN="$AUDIT_ROOT/bin"
  AUDIT_AGENTS_DIR="$AUDIT_ROOT/agents"
  return 0
}

orch_helper() {
  [ -n "${AUDIT_BIN:-}" ] || orch_resolve_audit_root || return 1
  [ -f "$AUDIT_BIN/$1" ] || return 1
  printf '%s' "$AUDIT_BIN/$1"
}

# Claim and touch are the same touch on the same file; claim additionally starts the
# run's variable state from empty (orch_state_clear), so the two names read as
# "claim once, touch after each wave". Release removes the marker only: the learning
# phase runs after it and still reads saved values; the next claim clears them.
# Both marker paths are predictable (md5 of cwd) under a shared /tmp, so every access
# refuses a symlink and a file another user owns (same guard as the state dir below);
# nine runs named the unguarded touch before this landed (2026-09-16).
orch__marker_ok() { [ ! -L "$1" ] && { [ ! -e "$1" ] || [ -O "$1" ]; }; }
orch__progress_path() { printf '/tmp/claude-audit-in-progress-%s' "$(orch_hash_progress)"; }
orch__passed_path()   { printf '/tmp/claude-audit-passed-%s' "$(orch_hash_passed)"; }
orch_progress_touch()   { local m; m=$(orch__progress_path); orch__marker_ok "$m" || { echo "orch_progress_touch: refusing $m (symlink or not owned by $USER)" >&2; return 1; }; touch "$m"; }
orch_progress_claim()   { orch_state_clear; orch_progress_touch; }
orch_progress_release() { local m; m=$(orch__progress_path); [ -L "$m" ] && { rm -f "$m"; return 0; }; orch__marker_ok "$m" || return 1; rm -f "$m"; }

# Cross-block variable state. One file per variable, raw bytes, under a 0700 dir the
# current user owns; nothing is ever eval'd or sourced from it, values come back through
# `read -r -d ''`, so a value containing `$(...)` or quotes is inert text. Names are
# restricted to what a SKILL.md can assign (uppercase identifiers) minus the ones a
# shell or git would act on, as defence in depth behind the ownership check.
orch_state_dir() { printf '/tmp/claude-audit-state-%s' "$(orch_hash_progress)"; }

orch__state_dir_ok() {
  local d="$1"
  [ ! -L "$d" ] && [ -d "$d" ] && [ -O "$d" ]
}

orch__state_name_ok() {
  case "$1" in
    ""|*[!A-Z0-9_]*|[0-9]*) return 1 ;;
    PATH|IFS|HOME|TMPDIR|ENV|CDPATH|PS4|SHELLOPTS|BASHOPTS|PROMPT_COMMAND|EDITOR|VISUAL|PAGER) return 1 ;;
    BASH*|GIT_*|LD_*|DYLD_*|CLAUDE_*) return 1 ;;
  esac
  return 0
}

orch_state_clear() {
  local d; d="$(orch_state_dir)"
  [ -e "$d" ] || [ -L "$d" ] || return 0
  if [ -L "$d" ]; then rm -f "$d"; return 0; fi
  orch__state_dir_ok "$d" || { echo "orch_state_clear: refusing $d (not a directory owned by $USER)" >&2; return 1; }
  rm -rf "$d"
}

# orch_state_save NAME [NAME...]   an unset name is saved as empty and reported on stderr
orch_state_save() {
  local d n; d="$(orch_state_dir)"
  if [ ! -e "$d" ]; then (umask 077; mkdir "$d") || return 1; fi
  orch__state_dir_ok "$d" || { echo "orch_state_save: refusing $d (not a directory owned by $USER)" >&2; return 1; }
  for n in "$@"; do
    orch__state_name_ok "$n" || { echo "orch_state_save: refusing name $n" >&2; continue; }
    [ -n "${!n+x}" ] || echo "orch_state_save: $n is unset in this block (saved as empty)" >&2
    printf '%s' "${!n-}" > "$d/$n"
  done
}

orch_state_load() {
  local d f n; d="$(orch_state_dir)"
  [ -e "$d" ] || return 0
  orch__state_dir_ok "$d" || { echo "orch_state_load: refusing $d (not a directory owned by $USER)" >&2; return 1; }
  for f in "$d"/*; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    n="${f##*/}"
    orch__state_name_ok "$n" || continue
    IFS= read -r -d '' "$n" < "$f" || true
  done
}

# The passed marker used to be an empty file whose mtime was the whole claim, so an
# edit made after the audit but inside the 30-minute window shipped as "audited"
# (run 11, 2026-09-16). It now records the tree it certified: the working tree's
# tracked content (what /ship's `git add -u` will commit), via `git stash create`,
# which writes a dangling commit and touches neither index nor working tree; a
# clean tree has no stash to create and is HEAD's tree. /ship compares after its
# own commit, when HEAD's tree is that same tree if nothing changed in between.
# The PreToolUse push hook still checks existence and age only (it has no run
# context); /ship's gate is the consumer that binds.
orch_tree_hash() {
  local c; c=$(git stash create 2>/dev/null); c="${c:-HEAD}"
  git rev-parse "$c^{tree}" 2>/dev/null
}
# orch_marker_write <selected> <skipped> <incomplete> <degraded>
#
# The coverage arguments are mandatory, and that is the point: the gate used to live only in
# SKILL.md prose, so an orchestrator that misread its own run result could call this helper and
# get a green marker anyway. On 2026-09-17 three runs passed find.js its arguments by pointer
# instead of by value, every scout got an empty scope, 13 of 14 dimensions came back `skipped`,
# and the marker was written over a diff nobody had examined. Refusing here makes the numbers
# impossible to skip past.
orch_marker_write() {
  local selected="${1-}" skipped="${2-}" incomplete="${3-}" degraded="${4-}"
  for n in "$selected" "$skipped" "$incomplete" "$degraded"; do
    case "$n" in
      ''|*[!0-9]*)
        echo "orch_marker_write: needs <selected> <skipped> <incomplete> <degraded> as counts from the find.js result" >&2
        return 1 ;;
    esac
  done
  [ "$selected" -gt 0 ] || { echo "orch_marker_write: refusing, no dimension was selected" >&2; return 1; }
  [ "$incomplete" -eq 0 ] || { echo "orch_marker_write: refusing, $incomplete dimension(s) incomplete" >&2; return 1; }
  [ "$degraded" -eq 0 ] || { echo "orch_marker_write: refusing, $degraded dimension(s) degraded" >&2; return 1; }
  # One empty dimension is a repo without a frontend; most of them empty is a broken run.
  if [ $((skipped * 2)) -gt "$selected" ]; then
    echo "orch_marker_write: refusing, $skipped of $selected dimension(s) skipped (more than half)" >&2
    return 1
  fi
  local t m; t=$(orch_tree_hash) || t=""; m=$(orch__passed_path)
  orch__marker_ok "$m" || { echo "orch_marker_write: refusing $m (symlink or not owned by $USER)" >&2; return 1; }
  printf '%s\n' "$t" > "$m"
}
# rc 0: the marker certifies exactly the current tree. rc 2: the trees differ but every
# path in the delta is prose by classify-diff.sh's definition (a /ship docs-sync edit,
# a README fix), which the audit would have gated as prose anyway. rc 1: anything else.
orch_marker_matches() {
  local m rec now delta cls; m=$(orch__passed_path)
  [ -f "$m" ] && orch__marker_ok "$m" || return 1
  rec=$(head -1 "$m" 2>/dev/null); now=$(orch_tree_hash) || return 1
  [ -n "$rec" ] || return 1
  [ "$rec" = "$now" ] && return 0
  delta=$(git diff --name-only "$rec" "$now" 2>/dev/null) || return 1
  [ -n "$delta" ] || return 1
  cls=$(printf '%s\n' "$delta" | bash "$(orch_helper classify-diff.sh)" --paths 2>/dev/null | sed -n 's/^DIFF_CLASS=//p')
  [ "$cls" = "prose" ] && return 2
  return 1
}
orch_marker_delta() {   # the paths that changed since the marker's tree, for the gate's message
  local m rec now; m=$(orch__passed_path)
  rec=$(head -1 "$m" 2>/dev/null) || return 1; now=$(orch_tree_hash) || return 1
  git diff --name-only "$rec" "$now" 2>/dev/null
}

orch_verify_agents() {
  [ -n "${AUDIT_BIN:-}" ] || orch_resolve_audit_root || { echo "verify-agents: audit root not found"; return 1; }
  bash "$AUDIT_BIN/verify-agents.sh" "$AUDIT_AGENTS_DIR"
}

orch_parse_stripe() {
  local root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  local out
  out="$(bash "$AUDIT_BIN/detect-stripe.sh" "$root" 2>/dev/null)" || out=""
  STRIPE=$(printf '%s\n' "$out" | sed -n 's/^STRIPE=//p'); STRIPE="${STRIPE:-no}"
  STRIPE_MODE=$(printf '%s\n' "$out" | sed -n 's/^STRIPE_MODE=//p')
  STRIPE_RECURRING=$(printf '%s\n' "$out" | sed -n 's/^STRIPE_RECURRING=//p')
  # BSD sed: `p;}` not `p}` (that exact slip emptied this list twice on 2026-09-14)
  STRIPE_FILES=$(printf '%s\n' "$out" | sed -n '/^STRIPE_FILES<<END$/,/^END$/{/^STRIPE_FILES<<END$/d;/^END$/d;p;}')
}

orch_run_log() {
  local rl
  rl=$(orch_helper run-log.sh) || return 0
  bash "$rl" "$@" || true
}

# One parser for `.claude/ship.md` `test-command:`. Before 2026-09-16 /ship used
# `grep | cut -d' ' -f2-` (breaks on a tab, keeps trailing spaces) and /audit used
# `sed -n 's/^test-command:[[:space:]]*//p'`; two readers of one line disagreed.
# One parser for every `key: value` line in .claude/ship.md (test-command,
# deploy-command, health-check). /ship parsed deploy-command and health-check
# with `grep | cut -d' ' -f2-` until 2026-09-16, the pattern already replaced for
# test-command one commit earlier: a tab after the colon broke it and trailing
# spaces survived into the command. Prints the value, rc 1 when absent/empty.
orch_ship_value() {
  local key="$1" root="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" v
  v=$(sed -n "s/^${key}:[[:space:]]*//p" "$root/.claude/ship.md" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

orch_test_command_declared() { orch_ship_value test-command "${1:-}"; }

# /audit's variant: the declared command, else the manifest's own. /ship deliberately
# uses only the declared one, so a repo that never configured a test gate does not
# start running `composer test` on ship day because of this fallback.
orch_test_command() {
  local root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" v
  v=$(orch_test_command_declared "$root") && { printf '%s' "$v"; return 0; }
  if   jq -e '.scripts.test' "$root/composer.json" >/dev/null 2>&1; then printf 'composer test'
  elif jq -e '.scripts.test' "$root/package.json"  >/dev/null 2>&1; then printf 'npm test'
  elif [ -f "$root/Package.swift" ];                                 then printf 'swift test'
  elif [ -f "$root/pytest.ini" ] || [ -f "$root/pyproject.toml" ];   then printf 'pytest'
  else return 1
  fi
}

# "Which files are frontend?" has exactly one definition, FRONTEND_EXT_RE in
# lib-git-base.sh (CLAUDE.md Gotchas). design-audit carried its own regex until
# 2026-09-16 and the two had drifted (styl, tailwind.config vs xml, storyboard).
# Prints the shared pattern; the literal fallback mirrors collect-scope.sh.
orch_frontend_ext_re() {
  local lib="${AUDIT_BIN:-$HOME/.claude/skills/audit/bin}/lib-git-base.sh"
  # shellcheck disable=SC1090
  [ -f "$lib" ] && . "$lib"
  printf '%s' "${FRONTEND_EXT_RE:-\.(blade\.php|html?|vue|tsx?|jsx?|css|scss|sass|less|styl|svelte|astro|swift|kt|kts|dart|xml|storyboard|xib)$}"
}

# payments.md always applies once the payments dimension runs (the detector has
# already established a Stripe integration), but its applies_to path regex may
# not match a generic file in the surface, so match-guidelines.sh can omit it.
# Prints GUIDELINE_MATCHES with the line appended when missing. Was pasted in
# audit and full-audit until 2026-09-16.
orch_payments_guidelines() {
  local matches="$1"
  if printf '%s\n' "$matches" | grep -q '^payments\.md'; then printf '%s' "$matches"
  else printf '%s\npayments.md\tmandatory\tscoped' "$matches"
  fi
}

# Merges the payments scout floor (computed over STRIPE_FILES, not the shared
# scope) into the FLOOR_FILES JSON. Usage:
#   FLOOR_FILES=$(orch_payments_floor "$AUDIT_DIMENSIONS" "$STRIPE_FILES" "$PROJECT_ROOT" "$FLOOR_FILES")
# No payments in the selection, or no jq: prints the input unchanged (a NOTE on
# stderr for the jq case). Was pasted in audit and full-audit until 2026-09-16.
orch_payments_floor() {
  local dims="$1" stripe_files="$2" root="$3" floor="$4" pay
  case ",$dims," in *,payments,*) ;; *) printf '%s' "$floor"; return 0;; esac
  if ! command -v jq >/dev/null 2>&1; then
    echo "NOTE payments floor: jq unavailable, payments floor computed over the shared scope only" >&2
    printf '%s' "$floor"; return 0
  fi
  pay=$(printf '%s\n' "$stripe_files" | node "${AUDIT_BIN:?}/compute-floor.mjs" "$root" "payments") || { printf '%s' "$floor"; return 0; }
  jq -s '.[0] * .[1]' <(printf '%s' "$floor") <(printf '%s' "$pay")
}

# Recurrence and dismissal feed, from a FILE the orchestrator wrote with the
# Write tool, one pattern per line. A pattern is derived from a finding, i.e.
# from audited-repo content, and must never be spliced into a command line:
# `patterns-store.sh recur {pattern}` written out by an orchestrator was a
# Critical on 2026-09-16 (same class as the validate-locations.sh case). Here
# each line reaches the script as one quoted argv element, never parsed by a
# shell. Usage: orch_patterns_from_file recur|dismissed <file>
orch_patterns_from_file() {
  local op="$1" file="$2" p n=0
  case "$op" in recur|dismissed) ;; *) echo "orch_patterns_from_file: op must be recur or dismissed" >&2; return 1;; esac
  [ -f "$file" ] || { echo "orch_patterns_from_file: no such file: $file" >&2; return 1; }
  [ -n "${AUDIT_BIN:-}" ] || orch_resolve_audit_root || return 1
  while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    bash "$AUDIT_BIN/patterns-store.sh" "$op" "$p" >/dev/null 2>&1 || true
    n=$((n+1))
  done < "$file"
  echo "PATTERNS_FED=$n"
}

# /ship's health check curls a URL the audited repo wrote into .claude/ship.md. Six audit
# runs named the unfiltered curl; run 10 filtered by host, run 11 found the numeric
# bypasses (2130706433, 0177.0.0.1, 0x7f000001, 127.1 all reach loopback). A host that is
# only digits and dots must be a canonical dotted quad with every octet in range, and
# only then is it matched against the private ranges; hex and short forms are refused
# outright. IPv6 stays bracketed so the ranges match on the bracket form.
orch_url_host() {
  printf '%s' "$1" | sed -nE 's#^https?://([^/@]*@)?(\[[^]]+\]|[^/:?@]+).*#\2#p'
}
orch_host_public() {
  local h o
  h=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')   # DNS and the literals below are case-insensitive; LOCALHOST and [FC00::1] slipped past (run 12)
  case "$h" in
    ""|localhost|*.local|*.internal) return 1 ;;
    "[::1]"|"[::]"|"[fc"*|"[fd"*|"[fe80"*|"[::ffff:"*) return 1 ;;
    0[xX]*) return 1 ;;
    *[!0-9.]*) return 0 ;;
  esac
  # numeric host: canonical dotted quad only
  printf '%s' "$h" | grep -Eq '^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$' || return 1
  for o in $(printf '%s' "$h" | tr '.' ' '); do [ "$o" -le 255 ] || return 1; done
  case "$h" in
    127.*|0.*|10.*|192.168.*|169.254.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 1 ;;
  esac
  return 0
}
