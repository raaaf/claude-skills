#!/usr/bin/env bash
#
# Classify the diff so the audit can scale itself to what actually changed.
#
# Why this exists: /audit is a pre-push gate calibrated for code that ships to
# users. Applied at effort high to a diff that only touches prose, it still
# dispatches twelve dimensions with adversarial verification and reliably finds
# something, because that is what it is built to do. On 2026-08-05 three audits
# in one night each audited the fixes of the previous one; the first found dead
# security guards, the last found a wrong word in a comment. All correct, and
# the last one was not worth its cost.
#
# Emits two shell assignments meant to be consumed with eval. BOTH values are
# printf %q quoted: the reason contains parentheses and commas, and an unquoted
# assignment makes `eval` die with a syntax error while the caller still sees a
# plausible DIFF_CLASS from the first line. Same lesson as perf-measure.sh
# --detect; do not "simplify" this back to a bare echo.
#   DIFF_CLASS=prose | code | mixed
#   DIFF_CLASS_REASON=<one line>
#
# prose  = documentation, guidelines, agent definitions, audit logs. No file
#          that executes: no source, no script, no manifest, no lockfile, no CI
#          config, no template.
# code   = at least one executing file and no prose-only signal worth noting.
# mixed  = both. Treated as code; the gate never downgrades on a diff that
#          contains something executable.
#
# bash 3.2 compatible (macOS default). Fails OPEN: anything unclear is `code`,
# because under-auditing a code change is the expensive mistake and
# over-auditing prose is merely annoying.
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" 2>/dev/null || {
  printf 'DIFF_CLASS=%q\n' code
  printf 'DIFF_CLASS_REASON=%q\n' "not a git repository, failing open"
  exit 0
}

# Same scope the audit itself uses: unstaged + staged + untracked, plus commits
# not yet on the remote.
#
# `@{u}` only resolves on a branch that HAS an upstream. A fresh local branch
# has none, so `@{u}..HEAD` fails, the `|| true` swallows it, and the commits
# vanish from the classification. On 2026-08-13 that turned a 46-file Swift
# commit on a just-created branch into DIFF_CLASS=prose, because the only thing
# left to look at was nine markdown files in the working tree. A prose verdict
# cuts the audit to one round with no Minor fixes, so the misclassification
# silently guts the run. Fall back to the default branch when there is no
# upstream: that is the base `collect-scope.sh` uses anyway.
# Every git call here is `|| true`-guarded: the script runs under `set -e`, and
# a bare `VAR=$(git ...)` that fails aborts it silently, which is the exact
# failure mode this block exists to remove.
# AUDIT_BASE_REF override: same escape hatch as lib-git-base.sh's
# resolve_base_ref(). A caller that already substituted the diff base takes
# precedence over this script's own upstream/default-branch derivation, so
# the two never disagree on what "the base" is. Falls through when unset,
# empty, or invalid.
if [ -n "${AUDIT_BASE_REF:-}" ] && git rev-parse --verify "$AUDIT_BASE_REF" >/dev/null 2>&1; then
  COMMIT_RANGE="${AUDIT_BASE_REF}..HEAD"
else
  UPSTREAM_RANGE=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || true)
  if [ -n "$UPSTREAM_RANGE" ]; then
    COMMIT_RANGE="@{u}..HEAD"
  else
    DEFAULT_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)
    [ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH=$(git config --get init.defaultBranch 2>/dev/null || true)
    [ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH=main
    if git rev-parse --verify --quiet "origin/$DEFAULT_BRANCH" >/dev/null 2>&1; then
      COMMIT_RANGE="origin/$DEFAULT_BRANCH..HEAD"
    else
      COMMIT_RANGE="$DEFAULT_BRANCH..HEAD"
    fi
  fi
fi

FILES=$(
  {
    git status --porcelain 2>/dev/null | sed 's/^...//; s/^.* -> //'
    git diff --name-only "$COMMIT_RANGE" 2>/dev/null || true
  } | sed 's/^"//; s/"$//' | sort -u | grep -v '^$' || true
)

if [ -z "$FILES" ]; then
  printf 'DIFF_CLASS=%q\n' prose
  printf 'DIFF_CLASS_REASON=%q\n' "empty diff"
  exit 0
fi

# Anything that executes, configures a build, or is consumed by a runtime.
EXEC_RE='\.(sh|bash|zsh|ps1|php|js|mjs|cjs|jsx|ts|tsx|vue|svelte|py|rb|go|rs|java|kt|kts|swift|m|mm|c|h|cpp|cs|sql|graphql|prisma)$'
CONF_RE='(^|/)(package(-lock)?\.json|composer\.(json|lock)|yarn\.lock|pnpm-lock\.yaml|requirements\.txt|pyproject\.toml|Gemfile(\.lock)?|go\.(mod|sum)|Cargo\.(toml|lock)|Podfile(\.lock)?|Package\.swift|pubspec\.(yaml|lock)|build\.gradle.*|Makefile|Dockerfile.*|docker-compose.*\.ya?ml|\.github/workflows/.*|\.gitlab-ci\.yml|vite\.config\..*|webpack\.config\..*|tsconfig.*\.json|\.env\.example)$'
TPL_RE='\.(blade\.php|twig|erb|hbs|ejs|liquid|html|htm|css|scss|sass|less)$'
# Runtime-consumed YAML: Home Assistant automations/scripts, Ansible playbooks,
# k8s manifests. These carry triggers, conditions, Jinja templates and service
# calls, so they execute in every sense the gate cares about. Without this a repo
# whose whole codebase is YAML classifies as prose and the gate silently guts
# itself to one round (learning 2026-08-19: ~300 changed lines of automation
# logic came back "none of them executing").
RUNTIME_YAML_RE='(^|/)(automations?|scripts?|packages|playbooks|roles|manifests)/.*\.ya?ml$|(^|/)(configuration|scripts|automations|scenes|sensors|binary_sensors|lights|climates|groups|timers|notifies)\.ya?ml$'

EXEC_HITS=$(printf '%s\n' "$FILES" | grep -Ei "$EXEC_RE" || true)
CONF_HITS=$(printf '%s\n' "$FILES" | grep -E "$CONF_RE" || true)
TPL_HITS=$(printf '%s\n' "$FILES" | grep -Ei "$TPL_RE" || true)
YAML_HITS=$(printf '%s\n' "$FILES" | grep -Ei "$RUNTIME_YAML_RE" || true)

# Eval fixtures are deliberately-broken test data, never shipped and never
# findings (see the repo's Audit Context). A fixture does not make a diff
# code-class, otherwise adding a test case re-triggers the full gate.
EXEC_HITS=$(printf '%s\n' "$EXEC_HITS" | grep -v '/evals/fixtures/' || true)
TPL_HITS=$(printf '%s\n' "$TPL_HITS" | grep -v '/evals/fixtures/' || true)
YAML_HITS=$(printf '%s\n' "$YAML_HITS" | grep -v '/evals/fixtures/' || true)

HAS_EXEC=0
[ -n "$(printf '%s' "$EXEC_HITS$CONF_HITS$TPL_HITS$YAML_HITS" | tr -d '[:space:]')" ] && HAS_EXEC=1

if [ "$HAS_EXEC" -eq 1 ]; then
  FIRST=$(printf '%s\n' "$EXEC_HITS$CONF_HITS$TPL_HITS$YAML_HITS" | grep -v '^$' | head -1)
  TOTAL=$(printf '%s\n' "$FILES" | grep -c . || echo 0)
  printf 'DIFF_CLASS=%q\n' code
  printf 'DIFF_CLASS_REASON=%q\n' "executing or build-relevant file in the diff (e.g. $FIRST), $TOTAL files total"
else
  TOTAL=$(printf '%s\n' "$FILES" | grep -c . || echo 0)
  printf 'DIFF_CLASS=%q\n' prose
  printf 'DIFF_CLASS_REASON=%q\n' "$TOTAL files, none of them executing, build-relevant or template"
fi
