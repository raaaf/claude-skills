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
FILES=$(
  {
    git status --porcelain 2>/dev/null | sed 's/^...//'
    git diff --name-only @{u}..HEAD 2>/dev/null || true
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

EXEC_HITS=$(printf '%s\n' "$FILES" | grep -Ei "$EXEC_RE" || true)
CONF_HITS=$(printf '%s\n' "$FILES" | grep -E "$CONF_RE" || true)
TPL_HITS=$(printf '%s\n' "$FILES" | grep -Ei "$TPL_RE" || true)

# Eval fixtures are deliberately-broken test data, never shipped and never
# findings (see the repo's Audit Context). A fixture does not make a diff
# code-class, otherwise adding a test case re-triggers the full gate.
EXEC_HITS=$(printf '%s\n' "$EXEC_HITS" | grep -v '/evals/fixtures/' || true)
TPL_HITS=$(printf '%s\n' "$TPL_HITS" | grep -v '/evals/fixtures/' || true)

HAS_EXEC=0
[ -n "$(printf '%s' "$EXEC_HITS$CONF_HITS$TPL_HITS" | tr -d '[:space:]')" ] && HAS_EXEC=1

if [ "$HAS_EXEC" -eq 1 ]; then
  FIRST=$(printf '%s\n' "$EXEC_HITS$CONF_HITS$TPL_HITS" | grep -v '^$' | head -1)
  TOTAL=$(printf '%s\n' "$FILES" | grep -c . || echo 0)
  printf 'DIFF_CLASS=%q\n' code
  printf 'DIFF_CLASS_REASON=%q\n' "executing or build-relevant file in the diff (e.g. $FIRST), $TOTAL files total"
else
  TOTAL=$(printf '%s\n' "$FILES" | grep -c . || echo 0)
  printf 'DIFF_CLASS=%q\n' prose
  printf 'DIFF_CLASS_REASON=%q\n' "$TOTAL files, none of them executing, build-relevant or template"
fi
