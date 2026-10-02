#!/usr/bin/env bash
#
# Shared library: the orchestrator prologue every skill used to paste.
# Sourced by the bash blocks in audit/, delegate/,
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
# first; every other skill uses the line above verbatim. The
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
# and the name must be saved by some scanned SKILL.md or references block (the state dir is shared
# per cwd, same hash as the in-progress marker; see the header comment below).
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
#   orch_unaudited_record   records the base a quick-fix /ship run's unpushed commits sit on (the
#                           oldest one wins: a no-op once the file exists), so several quick fixes
#                           collect into one /audit later
#   orch_unaudited_base     prints the recorded base sha, else nothing (rc 1)
#   orch_unaudited_clear    removes the recorded base (called once /audit has covered it)
#   orch_audited_record <files> <dims>   after a PASSED audit: stores path, blob sha and dims per file in the worktree's claude-audited-blobs
#   orch_audited_filter <files> <dims>   prints the files NOT already certified by a passed audit (same blob sha, dims a superset), input order kept
#   orch_backlog_add <tsv>   Minor backlog (.audit/minor-backlog.tsv, TRACKED, merge=union in .gitattributes; legacy .claude/audits/ copy read until the first write, then BACKLOG_LEGACY_FILE= is printed): appends the
#                           5-column entries dimension<TAB>file<TAB>line<TAB>first_seen<TAB>description from a FILE, key computed
#                           here, deduped by key, entries whose file no longer exists dropped; prints BACKLOG_ADDED=n
#   orch_backlog_for_files <files>   prints the stored 6-column entries (key first) whose file is in the newline list
#   orch_backlog_remove <keys>       removes the entries with those keys (newline list), drops missing files; prints BACKLOG_REMOVED=n
#   orch_backlog_oldest <n>          prints the n oldest stored entries (first_seen, then key; 6 columns, key first)
#   orch_backlog_count               prints the number of stored entries (0 when none)
#   orch_expand_dimensions <value>   `all` -> the gate set (all dimensions except typography, ui_design, animation), `all+visual` -> all 13, anything else unchanged
#   orch_visual_pass_files [ref]   nightly visual pass scope (content of ref, e.g. origin/main, when given): files changed (still existing, .audit/ and .claude/audits/ dropped) since the sha in .audit/visual-pass-head (legacy .claude/audits/ fallback), else in the last day, capped at AUDIT_VISUAL_PASS_CAP (default 40) most recently changed files
#   orch_visual_pass_overflow [ref]   number of files above the cap (reported as unchecked, never silent)
#   orch_frontend_ext_re      prints FRONTEND_EXT_RE from lib-git-base.sh (literal fallback mirrors collect-scope.sh)
#   orch_payments_guidelines <matches>   prints GUIDELINE_MATCHES with payments.md appended when missing
#   orch_payments_touched <changed> <stripe_files>   prints the non-test changed paths that sit in STRIPE_FILES (payments trigger)
#   orch_seo_surface <root>             prints yes|no (+ reason on stderr): does the repo have an SEO surface (sitemap, meta/og/JSON-LD/per-page title)
#   orch_seo_relevant <changed> <root>  prints yes|no (+ reason on stderr): SEO surface AND a frontend/routes file in the diff, never PLATFORM=native
#   orch_payments_floor <dims> <stripe_files> <root> <floor_json>   merges the payments scout floor into FLOOR_FILES
#
# There are two hash conventions, deliberately two functions with two names:
# passed and progress. `orch_hash_progress` stays md5 of bare cwd because
# pre-compact.sh independently recomputes exactly that (`pwd | md5`) to find the
# in-progress marker; it is shared on purpose across every audit-family skill run
# against the same cwd, since any of them in flight should still block compaction.
# The state dir keys off the same progress hash, so two audit-family skills
# sharing a cwd share one state dir and one claim; orch_progress_claim warns
# instead of silently wiping a sibling skill's saved cross-block variables (see
# its own comment below). Reading one family with the other's convention produces
# a different hash outright, and that exact mix-up between passed and progress
# broke /ship's audit gate once (CLAUDE.md Gotchas). Callers name the family they
# mean.

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
# Warn, never refuse: a crashed run must stay re-runnable, so a same-cwd claim from another
# audit-family skill only gets a heads-up before its cross-block state is wiped, not a block.
orch__progress_claim_warn() {
  local m mtime now age
  m=$(orch__progress_path)
  [ -f "$m" ] || return 0
  mtime=$(stat -f %m "$m" 2>/dev/null) || mtime=$(stat -c %Y "$m" 2>/dev/null) || return 0
  case "$mtime" in ''|*[!0-9]*) return 0 ;; esac
  now=$(date +%s) || return 0
  age=$((now - mtime))
  [ "$age" -ge 0 ] && [ "$age" -lt 2700 ] || return 0
  echo "orch_progress_claim: WARNING another audit-family run claimed this cwd ${age}s ago; its cross-block state is being cleared" >&2
}
orch_progress_claim()   { orch__progress_claim_warn; orch_state_clear; orch_progress_touch; }
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
  # eval, not bash's ${!n} indirection: the Bash tool may run zsh, where ${!n} is a
  # "bad substitution" (retro 2026-09-23). Safe because orch__state_name_ok admits only [A-Z0-9_].
  local d n was_set val; d="$(orch_state_dir)"
  if [ ! -e "$d" ]; then (umask 077; mkdir "$d") || return 1; fi
  orch__state_dir_ok "$d" || { echo "orch_state_save: refusing $d (not a directory owned by $USER)" >&2; return 1; }
  for n in "$@"; do
    orch__state_name_ok "$n" || { echo "orch_state_save: refusing name $n" >&2; continue; }
    eval "was_set=\${$n+x} val=\${$n-}"
    [ -n "$was_set" ] || echo "orch_state_save: $n is unset in this block (saved as empty)" >&2
    printf '%s' "$val" > "$d/$n"
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

# Where the collected-quick-fix base lives: under the git common dir (shared by
# every worktree, same reasoning as audit_store_root in lib-git-base.sh), never
# under /tmp (that's the marker/state family, keyed to cwd, cleared per run).
orch__unaudited_path() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  printf '%s/claude-unaudited-base' "$common"
}

# Records the base a quick-fix /ship run's unpushed commits sit on: @{u} when
# the branch has an upstream, else the merge-base with the default branch
# (same derivation lib-git-base.sh's resolve_base_ref uses). Only writes when
# the file does not exist yet, so the OLDEST base wins and several quick fixes
# in a row collect into one /audit later instead of each overwriting the last.
orch_unaudited_record() {
  local f base db
  f=$(orch__unaudited_path) || return 1
  [ -f "$f" ] && return 0
  base=$(git rev-parse --verify '@{u}' 2>/dev/null) || {
    local lib="${AUDIT_BIN:-$HOME/.claude/skills/audit/bin}/lib-git-base.sh"
    # shellcheck disable=SC1090
    [ -f "$lib" ] && . "$lib"
    command -v resolve_default_branch >/dev/null 2>&1 || return 1
    db=$(resolve_default_branch)
    base=$(resolve_base_ref "$db")
  }
  [ -n "$base" ] || return 1
  printf '%s\n' "$base" > "$f"
}

orch_unaudited_base() {
  local f; f=$(orch__unaudited_path) || return 1
  [ -f "$f" ] || return 1
  head -1 "$f"
}

orch_unaudited_clear() {
  local f; f=$(orch__unaudited_path) || return 0
  rm -f "$f"
}

# Content-hash memory of what a PASSED audit certified (2026-09-30: 37% of audit-find cost of
# 09-27..09-30 went to runs where over half the files had been audited before; the shop/printify
# worktree ran 13 audits in 24 h). Keyed on the blob sha of the working-tree file, so commits,
# amends and rebases do not matter. Per worktree (git-dir, not the common dir): another
# worktree's working tree is a different content state.
orch__audited_path() {
  local d
  d=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1
  printf '%s/claude-audited-blobs' "$d"
}

# Lines are path<TAB>blob-sha<TAB>dims. A re-record replaces the path's line; a listed path
# that no longer exists loses its line; every other line stays.
orch_audited_record() {
  local files="$1" dims="$2" f tmp p sha sorted line
  f=$(orch__audited_path) || return 1
  sorted=$(printf '%s' "$dims" | tr ',' '\n' | grep . | sort -u | paste -sd, -)
  tmp=$(mktemp) || return 1
  if [ -f "$f" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      p=${line%%$'\t'*}
      printf '%s\n' "$files" | grep -Fxq -- "$p" || printf '%s\n' "$line"
    done < "$f" > "$tmp"
  fi
  while IFS= read -r p; do
    [ -n "$p" ] && [ -f "$p" ] || continue
    sha=$(git hash-object -- "$p" 2>/dev/null) || continue
    printf '%s\t%s\t%s\n' "$p" "$sha" "$sorted" >> "$tmp"
  done <<EOF
$files
EOF
  mv "$tmp" "$f"
}

# Prints the files that still need an audit. Covered needs all three: a record line, an equal
# blob sha, recorded dims a superset of the requested ones. Anything else prints the file.
orch_audited_filter() {
  local files="$1" dims="$2" f p sha rec recsha recdims d ok
  f=$(orch__audited_path 2>/dev/null) || f=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    ok=0
    if [ -n "$f" ] && [ -f "$f" ] && [ -f "$p" ]; then
      sha=$(git hash-object -- "$p" 2>/dev/null) || sha=""
      rec=$(awk -F'\t' -v p="$p" '$1 == p { l = $0 } END { print l }' "$f")
      if [ -n "$sha" ] && [ -n "$rec" ]; then
        recsha=$(printf '%s' "$rec" | cut -f2)
        recdims=$(printf '%s' "$rec" | cut -f3)
        if [ "$recsha" = "$sha" ]; then
          ok=1
          for d in $(printf '%s' "$dims" | tr ',' ' '); do
            case ",$recdims," in *",$d,"*) ;; *) ok=0 ;; esac
          done
        fi
      fi
    fi
    [ "$ok" = 1 ] || printf '%s\n' "$p"
  done <<EOF
$files
EOF
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
# lib-git-base.sh (CLAUDE.md Gotchas).
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
# Prints GUIDELINE_MATCHES with the line appended when missing..
orch_payments_guidelines() {
  local matches="$1"
  if printf '%s\n' "$matches" | grep -q '^payments\.md'; then printf '%s' "$matches"
  else printf '%s\npayments.md\tmandatory\tscoped' "$matches"
  fi
}

# Payments trigger: changed paths that sit in the Stripe surface, test files excluded.
# 2026-09-30 (events): tests/Pest.php, a test helper, is in STRIPE_FILES; touching it alone
# started the payments dimension (12 agents, 41 USD, 35 findings, all in unchanged code).
# Test paths: tests/ test/ spec/ __tests__/ segments, *Test.php, *.test.*, *.spec.*.
orch_payments_touched() {
  local changed="$1" stripe="$2"
  comm -12 \
    <(printf '%s\n' "$changed" | grep -Ev '(^|/)(tests?|spec|__tests__)/|Test\.php$|\.(test|spec)\.' | sort -u) \
    <(printf '%s\n' "$stripe" | sort -u)
}

# SEO gate (decided 2026-10-01, 122 audit logs): seo cost 4% of audit-find cost for 12 Important and
# 0 Critical in 12 days (worst cost per finding), mostly on logged-in apps. It runs only where SEO can
# matter: an SEO surface exists in the repo AND the diff touches a frontend or routes file.
# Surface = a sitemap (path or route) or views emitting meta description / og: / twitter: / JSON-LD /
# a per-page <title>. public/robots.txt alone is no signal (Laravel ships one by default).
# Cheap: one find (vendor dirs pruned, 4000-file cap) and two greps that stop at the first hit.
orch_seo_surface() {
  local root="$1" files hit
  orch__backlog_libs
  files=$(find "$root" \( -name node_modules -o -name vendor -o -name .git \) -prune -o -type f \
    \( -iname '*sitemap*' -o -name '*.php' -o -name '*.html' -o -name '*.htm' -o -name '*.vue' -o -name '*.svelte' \
    -o -name '*.astro' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.ts' -o -name '*.js' -o -name '*.erb' \
    -o -name '*.twig' -o -name '*.njk' -o -name '*.hbs' -o -name '*.ejs' -o -name '*.liquid' -o -name '*.py' -o -name '*.rb' \) \
    -print 2>/dev/null | grep -Ev "$VENDOR_DIR_RE" | head -4000) || true
  hit=$(printf '%s\n' "$files" | grep -i 'sitemap' | head -1) || true
  if [ -n "$hit" ]; then echo "SEO surface: sitemap file $hit" >&2; echo yes; return 0; fi
  hit=$(printf '%s\n' "$files" | grep -E '(^|/)(routes?|urls?)[^/]*\.(php|js|ts|py|rb)$|(^|/)routes?/' | tr '\n' '\0' | xargs -0 grep -il 'sitemap' 2>/dev/null | head -1) || true
  if [ -n "$hit" ]; then echo "SEO surface: sitemap route in $hit" >&2; echo yes; return 0; fi
  hit=$(printf '%s\n' "$files" | grep -Ev '\.(ts|js|py|rb)$' | tr '\n' '\0' | xargs -0 grep -lE \
    "name=[\"']description|property=[\"']og:|name=[\"']twitter:|application/ld\+json|<title[^>]*>[^<]*(@yield|@section|\{\{|\{%|<\?|\\\$title|\\\$slot)" 2>/dev/null | head -1) || true
  if [ -n "$hit" ]; then echo "SEO surface: meta/title markup in $hit" >&2; echo yes; return 0; fi
  echo "no SEO surface (no sitemap, no meta description/og/twitter/JSON-LD/per-page title in views)" >&2
  echo no
}

orch_seo_relevant() {
  local changed="$1" root="$2" re surface
  if [ "${PLATFORM:-}" = native ]; then echo "SEO skipped: PLATFORM=native" >&2; echo no; return 0; fi
  surface=$(orch_seo_surface "$root") || true
  [ "$surface" = yes ] || { echo no; return 0; }
  re=$(orch_frontend_ext_re)
  if printf '%s\n' "$changed" | grep -Eq "$re|(^|/)routes?/|(^|/)(routes?|urls?)[^/]*\.(php|js|ts|py|rb)$"; then
    echo "SEO surface present and diff touches a frontend or routes file" >&2; echo yes
  else
    echo "SEO surface present, but the diff touches no frontend or routes file" >&2; echo no
  fi
}

# Merges the payments scout floor (computed over STRIPE_FILES, not the shared
# scope) into the FLOOR_FILES JSON. Usage:
#   FLOOR_FILES=$(orch_payments_floor "$AUDIT_DIMENSIONS" "$STRIPE_FILES" "$PROJECT_ROOT" "$FLOOR_FILES")
# No payments in the selection, or no jq: prints the input unchanged (a NOTE on
# stderr for the jq case).
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

# Minor backlog (decided 2026-10-01): Minors that did not ride along with a Critical/Important fix
# of their own file wait here and join that file's fixes (as UNCERTAIN) in a later wave. Store root:
# audit_store_root (the main checkout). The file is TRACKED (a nightly routine clears it in PRs), kept
# sorted by key so diffs stay stable; .gitattributes marks it merge=union. Every write must happen
# BEFORE orch_marker_write: the marker certifies the tracked tree.
# Line: key<TAB>dimension<TAB>file<TAB>line<TAB>first_seen<TAB>description. The key is
# file|normalize-suppression("[dimension] description"), so reworded repeats of one finding collapse.
# zsh (the Bash tool's shell) has no BASH_SOURCE; ${(%):-%x} is its sourced-file path. Without this the
# dir resolved to the cwd and every lib-git-base.sh source failed (orch-zsh-source.test.sh).
if [ -n "${BASH_SOURCE[0]:-}" ]; then ORCH__SRC="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then eval 'ORCH__SRC=${(%):-%x}'
else ORCH__SRC="$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; fi
ORCH_LIB_DIR=$(cd "$(dirname "$ORCH__SRC")" && pwd)
orch__backlog_root() { orch__backlog_libs; audit_store_root; }
orch__backlog_libs() { command -v gitignore_ensure >/dev/null 2>&1 || . "$ORCH_LIB_DIR/lib-git-base.sh"; }   # called in the main shell too: a source inside $(...) is lost
# Write target: .audit/ at the repo root (moved out of .claude/ 2026-10-02: headless sessions cannot write there).
# orch__backlog_read_path prefers it and falls back to the legacy .claude/audits/ file until the first write.
orch__backlog_path() { local r; r=$(orch__backlog_root) || return 1; printf '%s/.audit/minor-backlog.tsv' "$r"; }
orch__backlog_read_path() {
  local f l; f=$(orch__backlog_path) || return 1
  l="${f%/.audit/minor-backlog.tsv}/.claude/audits/minor-backlog.tsv"
  if [ ! -f "$f" ] && [ -f "$l" ]; then printf '%s' "$l"; else printf '%s' "$f"; fi
}

# Moves $1 over the store after dropping every entry whose file is gone; an empty result removes the store.
orch__backlog_commit() {
  local tmp="$1" f r out line file
  f=$(orch__backlog_path) || return 1
  r=$(orch__backlog_root) || return 1
  out=$(mktemp) || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    file=$(printf '%s' "$line" | cut -f3)
    [ -f "$r/$file" ] && printf '%s\n' "$line"
  done < "$tmp" > "$out"
  rm -f "$tmp"
  if [ -s "$out" ]; then mkdir -p "$(dirname "$f")" && LC_ALL=C sort -t "$(printf '\t')" -k1,1 "$out" > "$f" && rm -f "$out"; elif [ -f "$r/.claude/audits/minor-backlog.tsv" ]; then mkdir -p "$(dirname "$f")" && : > "$f"; rm -f "$out"   # empty file shadows the legacy copy
  else rm -f "$out" "$f"; fi
  return 0
}

# One line, tabs and newlines to spaces, at most 50 words (a finding text is audited-repo content: no secret values).
orch__backlog_clean() { tr '\t\r\n' '   ' | awk '{ n = (NF > 50 ? 50 : NF); s = ""; for (i = 1; i <= n; i++) s = s (i > 1 ? " " : "") $i; print s }'; }

orch_backlog_add() {
  local in="$1" f rf r tmp line dim file ln seen desc key n=0
  [ -f "$in" ] || { echo "orch_backlog_add: no such file: $in" >&2; return 1; }
  orch__backlog_libs
  f=$(orch__backlog_path) || return 1
  r=$(orch__backlog_root) || return 1
  tmp=$(mktemp) || return 1
  rf=$(orch__backlog_read_path)
  [ -f "$rf" ] && cat "$rf" > "$tmp"
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    dim=$(printf '%s' "$line" | cut -f1 | orch__backlog_clean)
    file=$(printf '%s' "$line" | cut -f2 | orch__backlog_clean)
    ln=$(printf '%s' "$line" | cut -f3 | orch__backlog_clean)
    seen=$(printf '%s' "$line" | cut -f4 | orch__backlog_clean)
    desc=$(printf '%s' "$line" | cut -f5- | orch__backlog_clean)
    [ -n "$dim" ] && [ -n "$file" ] && [ -n "$desc" ] || continue
    [ -f "$r/$file" ] || continue
    [ -n "$seen" ] || seen=$(date +%F)
    key="$file|$(printf '[%s] %s' "$dim" "$(printf '%s' "$desc" | sed -E 's/[[:punct:]]+$//')" | bash "$ORCH_LIB_DIR/normalize-suppression.sh")"
    awk -F'\t' -v k="$key" '$1 == k { found = 1 } END { exit !found }' "$tmp" && continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$dim" "$file" "$ln" "$seen" "$desc" >> "$tmp"
    n=$((n+1))
  done < "$in"
  orch__backlog_commit "$tmp" || return 1
  echo "BACKLOG_ADDED=$n"
  orch__backlog_legacy_note "$r"
  orch__backlog_repo_setup "$r"
}

# The legacy file is never deleted here (.claude/ is protected); the report tells the user to remove it.
orch__backlog_legacy_note() { [ ! -f "$1/.claude/audits/minor-backlog.tsv" ] || echo "BACKLOG_LEGACY_FILE=.claude/audits/minor-backlog.tsv (migrated to .audit/, can be deleted)"; }

# The store is tracked: drop the exact .gitignore line older versions added, make sure .gitattributes
# carries the union-merge line (appended once, file created when missing). Symlinked files are not touched.
orch__backlog_repo_setup() {
  local r="$1" rel='.audit/minor-backlog.tsv' old='.claude/audits/minor-backlog.tsv' t
  if [ -f "$r/.gitignore" ] && [ ! -L "$r/.gitignore" ] && grep -qxF "$old" "$r/.gitignore"; then
    t=$(mktemp) || return 0
    grep -vxF "$old" "$r/.gitignore" > "$t" || true
    cat "$t" > "$r/.gitignore"; rm -f "$t"
  fi
  [ -L "$r/.gitattributes" ] && return 0
  grep -qxF "$rel merge=union" "$r/.gitattributes" 2>/dev/null || printf '%s merge=union\n' "$rel" >> "$r/.gitattributes"
}

orch_backlog_for_files() {
  local f; f=$(orch__backlog_read_path) || return 0
  [ -f "$f" ] || return 0
  ORCH_LIST="$1" awk -F'\t' 'BEGIN { n = split(ENVIRON["ORCH_LIST"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1 } $3 in want' "$f"
}

orch_backlog_remove() {
  local f tmp before after
  f=$(orch__backlog_read_path) || return 0
  [ -f "$f" ] || { echo "BACKLOG_REMOVED=0"; return 0; }
  tmp=$(mktemp) || return 1
  ORCH_LIST="$1" awk -F'\t' 'BEGIN { n = split(ENVIRON["ORCH_LIST"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") drop[a[i]] = 1 } !($1 in drop)' "$f" > "$tmp"
  before=$(grep -c . "$f"); after=$(grep -c . "$tmp" || true)
  orch__backlog_commit "$tmp" || return 1
  echo "BACKLOG_REMOVED=$((before - after))"
}

orch_backlog_oldest() {
  local f; f=$(orch__backlog_read_path) || return 0
  [ -f "$f" ] || return 0
  LC_ALL=C sort -t "$(printf '\t')" -k5,5 -k1,1 "$f" | awk -v n="${1:-0}" 'NR <= n'
}

orch_backlog_count() {
  local f; f=$(orch__backlog_read_path 2>/dev/null) || { echo 0; return 0; }
  if [ -f "$f" ]; then grep -c . "$f" || true; else echo 0; fi
}

# typography, ui_design and animation left the pre-push gate for the nightly routine on 2026-10-01
# (0 Critical, cosmetic Importants over 122 audit logs); an explicit list still selects them.
orch_expand_dimensions() {
  local gate="architecture,security,performance,code_quality,seo,a11y,ux,docs_sync,copy,privacy"
  case "${1-}" in
    all) printf '%s\n' "$gate" ;;
    all+visual) printf '%s\n' "architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy,privacy" ;;
    *) printf '%s\n' "${1-}" ;;
  esac
}

# Scope of the nightly visual pass (run from the default branch checkout). The tracked file holds one
# commit sha; a missing, empty or unknown sha falls back to the last day of history (decided 2026-10-01:
# a 7-day fallback listed 949 files in one repo, 12 repos would exhaust the usage limit on night one).
# Optional $1 = a ref (e.g. origin/main): the sha file and the file existence are then read from that ref's
# content instead of HEAD and the working tree (nightly-repos.sh, which must not depend on a checkout).
# orch_visual_pass_all_files prints the uncapped scope; orch_visual_pass_files caps it to the
# AUDIT_VISUAL_PASS_CAP (default 40) most recently changed files; orch_visual_pass_overflow prints the rest.
orch_visual_pass_all_files() {
  local ref="${1:-}" sha p
  # New path .audit/visual-pass-head first, legacy .claude/audits/visual-pass-head as a read-only fallback.
  if [ -n "$ref" ]; then
    sha=$(git show "$ref:.audit/visual-pass-head" 2>/dev/null | head -1 || true)
    [ -n "$sha" ] || sha=$(git show "$ref:.claude/audits/visual-pass-head" 2>/dev/null | head -1 || true)
  else
    sha=$(head -1 .audit/visual-pass-head 2>/dev/null || true)
    [ -n "$sha" ] || sha=$(head -1 .claude/audits/visual-pass-head 2>/dev/null || true)
  fi
  {
    if [ -n "$sha" ] && git cat-file -e "$sha^{commit}" 2>/dev/null; then
      git diff --name-only "$sha" "${ref:-HEAD}" --
    else
      git log --since='1 day ago' --name-only --pretty=format: "${ref:-HEAD}" --
    fi
  } | sed '/^$/d; /^\.claude\/audits\//d; /^\.audit\//d' | sort -u | while IFS= read -r p; do
    if [ -n "$ref" ]; then git cat-file -e "$ref:$p" 2>/dev/null && printf '%s\n' "$p"
    else [ -f "$p" ] && printf '%s\n' "$p"; fi
  done
  return 0
}

orch_visual_pass_files() {
  local ref="${1:-}" cap="${AUDIT_VISUAL_PASS_CAP:-40}" all n p
  all=$(orch_visual_pass_all_files "$ref")
  n=$(printf '%s' "$all" | grep -c . || true)
  if [ "${n:-0}" -le "$cap" ]; then [ -z "$all" ] || printf '%s\n' "$all"; return 0; fi
  # Over the cap: newest commit first, ties by path.
  printf '%s\n' "$all" | while IFS= read -r p; do
    printf '%s\t%s\n' "$(git log -1 --format=%ct "${ref:-HEAD}" -- "$p")" "$p"
  done | sort -t "$(printf '\t')" -k1,1nr -k2,2 | head -n "$cap" | cut -f2
  return 0
}

orch_visual_pass_overflow() {
  local cap="${AUDIT_VISUAL_PASS_CAP:-40}" n
  n=$(orch_visual_pass_all_files "${1:-}" | grep -c . || true)
  if [ "${n:-0}" -gt "$cap" ]; then printf '%s\n' "$((n - cap))"; else printf '0\n'; fi
}

# Recurrence and dismissal feed, from a FILE the orchestrator wrote with the
# Write tool, one pattern per line. A pattern is derived from a finding, i.e.
# from audited-repo content, and must never be spliced into a command line:
# `patterns-store.sh recur {pattern}` written out by an orchestrator was a
# Critical on 2026-09-16 (same class of bug). Here
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
