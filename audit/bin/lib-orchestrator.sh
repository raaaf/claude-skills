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
# first; full-audit adds the CLAUDE_PROJECT_DIR-derived candidate it needed before. The
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
#   orch_test_command_declared [root]   prints `test-command:` from .claude/ship.md, else nothing (rc 1)
#   orch_test_command [root]  declared value, else a manifest guess (composer/npm/swift/pytest), else nothing (rc 1)
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
           "${CLAUDE_PROJECT_DIR:+${CLAUDE_PROJECT_DIR%/full-audit}/audit}" \
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

orch_progress_claim()   { touch "/tmp/claude-audit-in-progress-$(orch_hash_progress)"; }
orch_progress_touch()   { touch "/tmp/claude-audit-in-progress-$(orch_hash_progress)"; }
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
orch_test_command_declared() {
  local root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" v
  v=$(sed -n 's/^test-command:[[:space:]]*//p' "$root/.claude/ship.md" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

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
