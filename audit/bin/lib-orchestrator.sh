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
# Functions (all bash 3.2, no arrays exported, no side effects beyond the
# variables named):
#   orch_resolve_audit_root   sets AUDIT_ROOT, AUDIT_BIN, AUDIT_AGENTS_DIR; returns 1 if none found
#   orch_helper <script.sh>   prints "$AUDIT_BIN/<script>" if it exists, else nothing (rc 1)
#   orch_hash_passed          md5 of $PWD WITHOUT newline  -> /tmp/claude-audit-passed-*
#   orch_hash_progress        md5 of pwd  WITH newline     -> /tmp/claude-audit-in-progress-*
#   orch_progress_claim | orch_progress_touch | orch_progress_release
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

# Claim and touch are the same operation on the same file (a plain touch); the
# two names exist so a SKILL.md reads as "claim once, touch after each wave".
orch_progress_touch()   { touch "/tmp/claude-audit-in-progress-$(orch_hash_progress)"; }
orch_progress_claim()   { orch_progress_touch; }
orch_progress_release() { rm -f "/tmp/claude-audit-in-progress-$(orch_hash_progress)"; }

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
