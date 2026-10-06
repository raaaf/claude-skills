#!/usr/bin/env bash
#
# Shared library: the orchestrator prologue every skill used to paste.
# Sourced by the bash blocks in audit/, delegate/, ship/, plan-it/ and screens/ SKILL.md. Before
# 2026-09-16 each of them carried its own copy of helper resolution, cwd hashing and the
# in-progress marker, with variations; three audit runs named the drift as one condition, so it
# is one file now.
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
#   orch_resolve_audit_root   sets AUDIT_ROOT, AUDIT_BIN; returns 1 if none found
#   orch_helper <script.sh>   prints "$AUDIT_BIN/<script>" if it exists, else nothing (rc 1)
#   orch_hash_passed          md5 of $PWD WITHOUT newline  -> /tmp/claude-audit-passed-*
#   orch_hash_progress        md5 of pwd  WITH newline     -> /tmp/claude-audit-in-progress-*
#   orch_progress_claim | orch_progress_touch | orch_progress_release   (claim also clears the state dir; every marker access refuses a symlink or a file another user owns)
#   orch_state_save NAME...   writes each named variable's value to the run's state dir (one file per name)
#   orch_state_load           reads every saved variable back into the current shell; the answer to
#                             "a value set in an earlier block" (see the block rule below)
#   orch_state_clear          removes the state dir; called by orch_progress_claim, and by skills without a claim (ship) at their start
#   orch_tree_hash            tree object id of the working tree incl. untracked non-ignored files, built in a temp copy of the index
#   orch_marker_write         writes orch_tree_hash into /tmp/claude-audit-passed-*; the marker certifies a tree, not a moment
#   orch_marker_matches       rc 0 when the passed marker's tree equals orch_tree_hash now, rc 2 when the
#                             delta is prose-only (classify-diff.sh --paths), rc 1 otherwise
#   orch_marker_delta         prints the paths that changed since the marker's tree
#   orch_url_host <url>       prints the host of an http(s) URL (userinfo dropped, [IPv6] kept whole), else nothing
#   orch_host_public <host>   rc 0 unless loopback/private/link-local/ULA/mapped, *.local/*.internal, or a
#                             numeric host that is not a canonical dotted quad (decimal, octal, hex, short forms)
#   orch_run_log <args...>    calls run-log.sh if present; never fails the caller
#   orch_ship_value <key> [root]   prints `<key>:` from .claude/ship.md (test-command, deploy-command, health-check), else nothing (rc 1)
#   orch_test_command_declared [root]   = orch_ship_value test-command
#   orch_test_command [root]  declared value, else a manifest guess (composer/npm/swift/pytest), else nothing (rc 1)
#   orch_unaudited_record   records the base a quick-fix /ship run's unpushed commits sit on (the
#                           oldest one wins: a no-op once the file exists), so several quick fixes
#                           collect into one /audit later
#   orch_unaudited_base     prints the recorded base sha, else nothing (rc 1)
#   orch_unaudited_clear    removes the recorded base (called once /audit has covered it)
#   orch_sensitive_paths <changed>   prints the non-test changed paths on an auth/payment/privacy surface (feeds the sensitive-path checklist agent of /audit Phase 2)
#   orch_usage_start         saves AUDIT_USAGE_T0 (epoch) to the state; call right after orch_progress_claim (the claim clears the state)
#   orch_usage_report        prints `AUDIT_COST_USD=<x.xx> AUDIT_COST_WEEK_PCT=<y.y> WEEK_USD=<z> WEEK_PCT_EST=<w>` (n/a per value on error, never fails): this session plus *audit-review* sessions since T0, and the week since the last reset in ~/.claude/usage-limits.conf
#   orch_review_worktree_create <base_ref> [files]   temporary detached worktree at base_ref with the audit scope (base_ref..working tree, untracked files as intent-to-add) applied as UNCOMMITTED changes; prints its path (for the built-in /code-review)
#   orch_review_worktree_remove <path>   removes that worktree (also after a failed review)
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
    [ -n "$c" ] && [ -f "$c/bin/lib-orchestrator.sh" ] && { AUDIT_ROOT="$c"; break; }
  done
  [ -n "$AUDIT_ROOT" ] || return 1
  AUDIT_BIN="$AUDIT_ROOT/bin"
  return 0
}

orch_helper() {
  [ -n "${AUDIT_BIN:-}" ] || orch_resolve_audit_root || return 1
  [ -f "$AUDIT_BIN/$1" ] || return 1
  printf '%s' "$AUDIT_BIN/$1"
}

# Claim and touch are the same touch on the same file; claim additionally starts the
# run's variable state from empty (orch_state_clear), so the two names read as
# "claim once, touch after each wave". Release removes the marker only; saved values stay
# readable until the next claim clears them.
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
# content including untracked, non-ignored files. Untracked files are included
# because /audit often reviews a brand-new file, and after the user's
# `git add -A && git commit` that file is part of HEAD's tree; a tree without it
# would read as a code delta and the marker as stale (sprachverliebt, 2026-10-06).
# The logic lives in tree-hash.sh (temp copy of the real index), shared with the
# push guard so both hash the same tree. /ship compares after its own commit, when
# HEAD's tree is that same tree if nothing changed in between.
orch_tree_hash() { bash "$ORCH_LIB_DIR/tree-hash.sh"; }
# orch_marker_write <selected> <skipped> <incomplete> <degraded>
# /audit passes: selected = reviews run, skipped = 0, incomplete = failed reviews plus open Critical/Important findings, degraded = 0.
#
# The coverage arguments are mandatory, and that is the point: the gate used to live only in
# SKILL.md prose, so an orchestrator that misread its own run result could call this helper and
# get a green marker anyway. On 2026-09-17 three runs of the former pipeline passed their arguments by pointer
# instead of by value, 13 of 14 reviews came back `skipped`,
# and the marker was written over a diff nobody had examined. Refusing here makes the numbers
# impossible to skip past.
orch_marker_write() {
  local selected="${1-}" skipped="${2-}" incomplete="${3-}" degraded="${4-}"
  for n in "$selected" "$skipped" "$incomplete" "$degraded"; do
    case "$n" in
      ''|*[!0-9]*)
        echo "orch_marker_write: needs <selected> <skipped> <incomplete> <degraded> as counts" >&2
        return 1 ;;
    esac
  done
  [ "$selected" -gt 0 ] || { echo "orch_marker_write: refusing, no review was selected" >&2; return 1; }
  [ "$incomplete" -eq 0 ] || { echo "orch_marker_write: refusing, $incomplete review(s) or open finding(s) incomplete" >&2; return 1; }
  [ "$degraded" -eq 0 ] || { echo "orch_marker_write: refusing, $degraded review(s) degraded" >&2; return 1; }
  # One empty dimension is a repo without a frontend; most of them empty is a broken run.
  if [ $((skipped * 2)) -gt "$selected" ]; then
    echo "orch_marker_write: refusing, $skipped of $selected review(s) skipped (more than half)" >&2
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
    # shellcheck disable=SC1090
    [ -f "$ORCH_LIB_DIR/lib-git-base.sh" ] && . "$ORCH_LIB_DIR/lib-git-base.sh"
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

# Sensitive surface (decided 2026-10-02): changed non-test paths on an auth, payment or privacy surface get an
# extra checklist review (references/sensitive-checklist.md) next to the built-in /code-review. Path-based and
# deliberately broad: a miss costs a security finding, a false hit costs one review. Style/asset/prose files never count (tokens.css is a design
# token file, a privacy.md is prose). `auth` must not match author(s); CamelCase Auth* names are caught separately.
ORCH_SENSITIVE_RE='authent|authoriz|auth([^a-z]|$)|login|logout|passw(or)?d|token|session|middleware|polic(y|ies)|permission|payment|stripe|checkout|invoice|billing|webhook|gdpr|privacy|consent|personal[-_ ]?data'
orch_sensitive_paths() {
  local nontest
  nontest=$(printf '%s\n' "$1" | sed '/^$/d' |
    grep -Ev '(^|/)(tests?|spec|__tests__)/|Test\.php$|\.(test|spec)\.' |
    grep -Eiv '\.(css|scss|sass|less|styl|svg|png|jpe?g|webp|gif|ico|woff2?|md|mdx|txt)$' || true)
  { printf '%s\n' "$nontest" | grep -Ei "$ORCH_SENSITIVE_RE" || true
    printf '%s\n' "$nontest" | grep -E 'Auth[A-Z]' || true; } | sed '/^$/d' | sort -u
  return 0
}

# Review worktree (decided 2026-10-02): the built-in /code-review reviews "the current diff", so the audit
# scope is materialized as one. A detached worktree at BASE_REF gets `git diff --binary BASE_REF` of the main
# tree (commits plus uncommitted tracked changes) applied, and the untracked non-ignored files copied over
# and marked intent-to-add so `git diff` shows them. The user's tree is never touched. $2 (newline list,
# repo-root-relative) limits both parts to the audit scope; empty means the whole tree.
# The removal uses the worktree-remove form that audit/hooks/block-worktree-wide-git.sh denies when it is
# typed into a Bash call; the hook only sees the call text, so callers use these two helpers by name.
orch_review_worktree_create() {
  local base="$1" files="${2-}" root tmp wt patch p
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  tmp="${TMPDIR:-/tmp}"; tmp="${tmp%/}"
  wt=$(mktemp -d "$tmp/audit-review.XXXXXX") || return 1
  patch=$(mktemp "$tmp/audit-review-patch.XXXXXX") || return 1
  if ! git -C "$root" worktree add -q --detach "$wt" "$base" >/dev/null 2>&1; then rm -rf "$wt" "$patch"; return 1; fi
  if [ -n "$files" ]; then
    printf '%s\n' "$files" | sed '/^$/d' | tr '\n' '\0' | xargs -0 git -C "$root" diff --binary "$base" -- > "$patch" 2>/dev/null
  else
    git -C "$root" diff --binary "$base" -- > "$patch" 2>/dev/null
  fi
  if [ -s "$patch" ] && ! git -C "$wt" apply --binary "$patch" >/dev/null 2>&1; then
    rm -f "$patch"; orch_review_worktree_remove "$wt"; return 1
  fi
  rm -f "$patch"
  git -C "$root" ls-files --others --exclude-standard | while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -n "$files" ] && ! printf '%s\n' "$files" | grep -qxF -- "$p"; then continue; fi
    mkdir -p "$wt/$(dirname "$p")" && cp -p "$root/$p" "$wt/$p" && git -C "$wt" add -N -- "$p" >/dev/null 2>&1
  done
  printf '%s\n' "$wt"
}

orch_review_worktree_remove() {
  case "${1-}" in */audit-review.*) ;; *) return 0 ;; esac
  git worktree remove --force "$1" >/dev/null 2>&1 || rm -rf "$1"
  git worktree prune >/dev/null 2>&1 || true
  return 0
}

# zsh (the Bash tool's shell) has no BASH_SOURCE; ${(%):-%x} is its sourced-file path. Without this the
# dir resolved to the cwd and the lib-git-base.sh source in orch_unaudited_record failed (orch-zsh-source.test.sh).
if [ -n "${BASH_SOURCE[0]:-}" ]; then ORCH__SRC="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then eval 'ORCH__SRC=${(%):-%x}'
else ORCH__SRC="$HOME/.claude/skills/audit/bin/lib-orchestrator.sh"; fi
ORCH_LIB_DIR=$(cd "$(dirname "$ORCH__SRC")" && pwd)

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

# Usage report (2026-10-03). Prices and the 1% = 20 USD calibration: run-cost.sh and audit/CLAUDE.md.
orch_usage_start() {
  # The printed mark lands in this session's transcript (Bash tool output), so orch_usage_report can find
  # the session file even when the audited repo is not the directory the session was started in.
  AUDIT_USAGE_T0=$(date +%s)
  AUDIT_USAGE_MARK="audit-usage-${AUDIT_USAGE_T0}-$$-${RANDOM}"
  orch_state_save AUDIT_USAGE_T0 AUDIT_USAGE_MARK
  echo "AUDIT_USAGE_MARK=$AUDIT_USAGE_MARK"
}

# epoch -> formatted: BSD `date -r <epoch>` first, GNU `date -d @<epoch>` as fallback
orch__date_at() { date -r "$1" "$2" 2>/dev/null || date -d "@$1" "$2"; }

# prints the epoch of the last weekly reset (WEEK_RESET_DOW 1=Mon..7=Sun at WEEK_RESET_HOUR in WEEK_RESET_TZ)
orch__week_reset_epoch() {
  local now="$1" dow="$2" hour="$3" tz="$4" cur_dow hms secs back r
  cur_dow=$(TZ="$tz" orch__date_at "$now" +%u) || return 1
  hms=$(TZ="$tz" orch__date_at "$now" +%H:%M:%S) || return 1
  secs=$(( 10#${hms%%:*} * 3600 + 10#$(printf '%s' "$hms" | cut -d: -f2) * 60 + 10#${hms##*:} ))
  back=$(( (cur_dow - dow + 7) % 7 ))
  r=$(( now - secs - back * 86400 + hour * 3600 ))
  [ "$r" -gt "$now" ] && r=$(( r - 604800 ))
  printf '%s' "$r"
}

orch__usage_compute() (
  local root="$HOME/.claude/projects" conf="$HOME/.claude/usage-limits.conf" now t0 rc cost="n/a" week="n/a" d f usd n
  local WEEK_RESET_DOW=4 WEEK_RESET_HOUR=12 WEEK_RESET_TZ=Europe/Berlin WEEK_BUDGET_USD=2600
  export LC_NUMERIC=C
  [ -f "$conf" ] && . "$conf"
  case "$WEEK_RESET_DOW$WEEK_RESET_HOUR" in ''|*[!0-9]*) WEEK_RESET_DOW=4; WEEK_RESET_HOUR=12 ;; esac
  case "$WEEK_BUDGET_USD" in ''|*[!0-9.]*) WEEK_BUDGET_USD=2000 ;; esac
  orch_state_load
  t0="${AUDIT_USAGE_T0:-}"
  [ -n "${AUDIT_BIN:-}" ] || orch_resolve_audit_root || true
  rc="${AUDIT_BIN:-}/run-cost.sh"
  now=$(date +%s)
  if [ -f "$rc" ]; then
    if [ -n "$t0" ]; then
      f=""
      [ -n "${AUDIT_USAGE_MARK:-}" ] && f=$(grep -lF "$AUDIT_USAGE_MARK" "$root"/*/*.jsonl 2>/dev/null | head -1)
      if [ -n "$f" ]; then
        usd=$(bash "$rc" "$(dirname "$f")" "$(basename "$f" .jsonl)" --since "$t0" 2>/dev/null | sed -n 's/.* usd=\([0-9.]*\) .*/\1/p')
      else
        usd=$(bash "$rc" --latest "$root/$(pwd | sed 's#/#-#g')" --since "$t0" 2>/dev/null | sed -n 's/.* usd=\([0-9.]*\) .*/\1/p')
      fi
      if [ -n "$usd" ]; then
        cost="$usd"
        n=$(( (now - t0) / 60 + 2 ))
        for d in "$root"/*audit-review*; do
          [ -d "$d" ] || continue
          while IFS= read -r f; do
            usd=$(bash "$rc" "$d" "$(basename "$f" .jsonl)" --since "$t0" 2>/dev/null | sed -n 's/.* usd=\([0-9.]*\) .*/\1/p')
            [ -n "$usd" ] && cost=$(awk -v a="$cost" -v b="$usd" 'BEGIN{printf "%.2f", a+b}')
          done < <(find "$d" -maxdepth 1 -type f -name '*.jsonl' -mmin "-$n" 2>/dev/null)
        done
      fi
    fi
    f=$(orch__week_reset_epoch "$now" "$WEEK_RESET_DOW" "$WEEK_RESET_HOUR" "$WEEK_RESET_TZ") &&
      usd=$(bash "$rc" --window "$root" "$f" 2>/dev/null | sed -n 's/^WINDOW .* usd=\([0-9.]*\).*/\1/p') && [ -n "$usd" ] && week="$usd"
  fi
  pct() { case "$1" in n/a) printf 'n/a' ;; *) awk -v u="$1" -v b="$WEEK_BUDGET_USD" 'BEGIN{printf "%.1f", u/b*100}' ;; esac; }
  printf 'AUDIT_COST_USD=%s AUDIT_COST_WEEK_PCT=%s WEEK_USD=%s WEEK_PCT_EST=%s\n' "$cost" "$(pct "$cost")" "$week" "$(pct "$week")"
)

orch_usage_report() {
  # Always computed in bash: the Bash tool runs zsh, where an unmatched glob ("$root"/*audit-review*) aborts.
  local out="" lib="${AUDIT_BIN:-}/lib-orchestrator.sh"
  [ -f "$lib" ] || { orch_resolve_audit_root >/dev/null 2>&1 || true; lib="${AUDIT_BIN:-}/lib-orchestrator.sh"; }
  [ -f "$lib" ] && out=$(ORCH_USAGE_LIB="$lib" bash -c '. "$ORCH_USAGE_LIB"; orch__usage_compute' 2>/dev/null)
  case "$out" in AUDIT_COST_USD=*) echo "$out" ;; *) echo "AUDIT_COST_USD=n/a AUDIT_COST_WEEK_PCT=n/a WEEK_USD=n/a WEEK_PCT_EST=n/a" ;; esac
  return 0
}
