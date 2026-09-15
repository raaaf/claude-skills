#!/usr/bin/env bash
#
# Detects the moves that lower the quality bar instead of meeting it, in the
# diff under audit:
#   1. a new suppression comment (@ts-ignore, eslint-disable, # noqa, ...)
#   2. a test newly skipped, disabled or narrowed to .only
#   3. a newly added empty catch / except-pass that swallows an error
#   4. assertions removed from a file without new ones added
#   5. a threshold key moved DOWN (coverage, budget, max-warnings, ...)
#
# Any of these makes a check pass without the underlying problem being fixed,
# which is why they are worth a deterministic pass rather than an LLM judgment.
# Each is legitimate sometimes: the output is a finding to justify, not a
# verdict. Severity guidance for the caller is in the audit log section that
# consumes this (Important by default, Minor when the same commit also removes
# the code the suppression covered).
#
# Calibrated 2026-09-15 against 343 commits of real history in two Laravel
# repos, under the rule that a hit you have to argue away is a false positive
# and the check gets fixed, not the exception documented. First version: 48
# hits over 200 commits, all refactors and published bundles. After four
# narrowings (test declarations moved, config-only thresholds, published build
# output, minified lines) the same window gives 2, both genuine instances of
# their kind. `assertions-removed` is the weakest rule: across those 343
# commits it fired once and that firing was a Pest config refactor, so treat it
# as Minor and read the diff. It stays because the class it describes (a test
# that keeps its declaration and silently loses every check) is real and is
# caught by the planted-bug test; delete it with evidence, not with impatience.
#
# Usage: bash check-silencing.sh [root]
#
# Output: one line per hit, `SILENCING_HIT <file>:<line> <kind>: <detail>`,
# then exactly one `SILENCING_RESULT=OK|HITS (N)|SKIP (reason)` line.
#
# The diff base is derived exactly as in classify-diff.sh (AUDIT_BASE_REF, then
# upstream, then the default branch) and the working tree is included, so an
# uncommitted suppression is caught too.
#
# bash 3.2 compatible (no declare -A, no readarray). BSD-safe: no grep -P, no
# \b, all parsing in awk.
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}"
cd "$ROOT" 2>/dev/null || { echo "SILENCING_RESULT=SKIP (root not readable: $ROOT)"; exit 0; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "SILENCING_RESULT=SKIP (not a git repository)"
  exit 0
fi

# Same base derivation as classify-diff.sh, same escape hatch, same guards:
# under `set -e` a bare assignment from a failing git call aborts the script.
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

# -U0: no context lines, so every `+`/`-` line in the stream is a real change
# and the hunk header alone carries the line numbers.
#
# ONE diff, against the base commit with no second ref, so the new side is the
# working tree and committed plus uncommitted work share one coordinate system.
# The earlier version concatenated `base..HEAD` and `HEAD..worktree`: two
# streams whose line numbers refer to different states of the same file, which
# made the de-duplication below unsound (a worktree hit could be dropped as a
# duplicate of an unrelated committed hit that happened to land on the same
# line number).
#
# The base is verified before use. The derivation above can land on a branch
# name that does not exist (no upstream, no origin, a default branch called
# something else), and `git diff` against a bad ref fails into the `|| true`,
# which is indistinguishable from a clean diff. The old two-stream version hid
# that behind its working-tree diff; this one says so and still checks the
# uncommitted half rather than reporting silence.
DIFF_BASE="${COMMIT_RANGE%%..*}"
if ! git rev-parse --verify --quiet "$DIFF_BASE" >/dev/null 2>&1; then
  echo "SILENCING_NOTE base '$DIFF_BASE' does not resolve, checking uncommitted changes only" >&2
  DIFF_BASE="HEAD"
fi
DIFF=$(git diff -U0 "$DIFF_BASE" 2>/dev/null || true)

if [ -z "$DIFF" ]; then
  echo "SILENCING_RESULT=SKIP (empty diff)"
  exit 0
fi

HITS=$(printf '%s\n' "$DIFF" | awk '
function emit(kind, detail) {
  # One line can match a kind only once (a hunk can restate it).
  key = file ":" lineno ":" kind
  if (key in seen) return
  seen[key] = 1
  printf "SILENCING_HIT %s:%d %s: %s\n", file, lineno, kind, detail
}
function flush_file() {
  # Rule 4 is per file, not per line: assertions removed with none added back.
  # Only when the TEST DECLARATIONS stayed put. A removed `it(`/`test(`/`func
  # testX` means the test was deleted, moved or rewritten, and its assertions
  # went with it; that is a different question from a surviving test quietly
  # losing its checks. Measured on 200 commits of a real repo: without this
  # condition the rule produced 42 hits, all of them refactors.
  if (file != "" && removed_asserts > 0 && added_asserts == 0 &&
      removed_test_decls == 0 && !(file in skipfile)) {
    printf "SILENCING_HIT %s:%d assertions-removed: %d assertion line(s) removed from a test that still exists (line = the hunk, the removed lines have none)\n", file, first_removed_assert, removed_asserts
  }
  removed_asserts = 0; added_asserts = 0; first_removed_assert = 0; removed_test_decls = 0
}
/^--- / { next }
# Only a real file header, never an added line whose own content starts with
# `++ ` (a C-style pre-increment renders as `+++ $counter;` in the diff and was
# read as a header, corrupting file/skip state for the rest of the hunk).
/^\+\+\+ (b\/|\/dev\/null)/ {
  flush_file()
  # `+++ b/path` carries the prefix, `+++ /dev/null` (deleted file) does not.
  # Blind substr($0,7) turned /dev/null into the path "ev/null" and emitted
  # hits under that name.
  if ($0 ~ /^\+\+\+ \/dev\/null/) { file = ""; skip = 1; is_config = 0; next }
  file = substr($0, 7)
  # Fixtures deliberately contain skipped tests and suppressions (they are test
  # data, never findings), same for vendored trees.
  # Published build output is third-party code the repo only carries. 27 of 38
  # hits on the first real probe of a second repo were the published JS
  # bundles of one framework.
  # The source of this script states every pattern it looks for, so it reports
  # itself on any diff that touches it. Its own path is excluded for the same
  # reason the fixtures are: defining a rule is not an instance of the rule.
  skip = (file ~ /(^|\/)check-silencing\.sh$/ ||
          file ~ /audit\/evals\/fixtures\// || file ~ /(^|\/)(vendor|node_modules|Pods|\.git)\// ||
          file ~ /(^|\/)\.claude\// ||
          file ~ /(^|\/)(dist|build|out|\.next|\.nuxt|coverage)\// ||
          file ~ /(^|\/)public\/(js|css|build|vendor)\// ||
          file ~ /\.min\.(js|css)$/)
  if (skip) skipfile[file] = 1
  # Config-shaped paths, excluding anything under a test directory.
  is_config = (file ~ /\.(json|ya?ml|toml|ini|cfg|conf|xml|properties)$/ ||
               file ~ /(^|\/)(\.[a-z]+rc|CONSTRAINTS\.md)$/ ||
               file ~ /\.config\.[a-z]+$/) &&
              file !~ /(^|\/)([Tt]ests?|__tests__|spec)\//
  next
}
/^@@ / {
  # @@ -old,count +new,count @@
  if (match($0, /\+[0-9]+/)) newline = substr($0, RSTART + 1, RLENGTH - 1) + 0
  next
}
/^-/ {
  if (skip) next
  body = substr($0, 2)
  if (body ~ /(assert|expect\(|XCTAssert|should\.|\$this->assert)/) {
    removed_asserts++
    if (first_removed_assert == 0) first_removed_assert = newline
  }
  if (body ~ /((^|[^A-Za-z_])(it|test|describe|context)[ \t]*\(|func[ \t]+test[A-Z]|def[ \t]+test_|public[ \t]+function[ \t]+test)/) removed_test_decls++
  # A removed line does not advance the new-file line counter.
  old_num[file] = body
  next
}
/^\+/ {
  if (skip) { newline++; next }
  body = substr($0, 2)
  lineno = newline
  newline++
  # A single added line this long is a bundle, not source anyone wrote.
  if (length(body) > 400) next

  if (body ~ /(@ts-ignore|@ts-expect-error|eslint-disable|#[ \t]*noqa|type:[ \t]*ignore|phpcs:ignore|@phpstan-ignore|psalm-suppress|swiftlint:disable|pylint:[ \t]*disable|@SuppressWarnings|nolint|#pragma[ \t]+warning[ \t]+disable)/) {
    emit("suppression-added", "a check is silenced at this line rather than satisfied")
  }
  if (body ~ /(\.skip\(|\.only\(|\.skip[ \t]*$|xit\(|xdescribe\(|pytest\.mark\.skip|@Disabled|\.xfail)/) {
    emit("test-disabled", "a test is disabled or narrowed to .only at declaration level")
  }
  # A runtime skip is often a legitimate precondition (`if (count <= 8)
  # markTestSkipped(...)`), and one added line carries no reliable evidence
  # either way. Reported as its own weaker kind rather than dropped: the caller
  # treats it as Minor and reads the guard above it.
  if (body ~ /(markTestSkipped|markTestIncomplete|XCTSkip|t\.Skip\()/) {
    emit("test-skipped-at-runtime", "a test skips itself at runtime, check whether the guard above it is a real precondition")
  }
  if (body ~ /catch[^{]*\{[ \t]*\}/ || body ~ /except[^:]*:[ \t]*pass[ \t]*$/ || body ~ /rescue[ \t]+nil/) {
    emit("error-swallowed", "an empty catch/except discards the error")
  }
  if (body ~ /(assert|expect\(|XCTAssert|should\.|\$this->assert)/) added_asserts++

  # Rule 5: a threshold key whose number moved down in the same hunk. Config
  # files ONLY. In source and test files the same shape is ordinary data
  # (`addHours(8)` becoming `addHours($h - 1)` read as 8 -> 1 and produced two
  # false positives on the first real-history probe), and no file-independent
  # pattern separates the two.
  if (is_config && match(body, /(coverage|threshold|minScore|min_score|maxWarnings|max-warnings|max_warnings|budget|minimum|maxSize|max_size)[^0-9]*[0-9]+(\.[0-9]+)?/)) {
    if (match(body, /[0-9]+(\.[0-9]+)?[^0-9]*$/)) newval = substr(body, RSTART, RLENGTH) + 0
    prev = old_num[file]
    if (prev != "" && match(prev, /[0-9]+(\.[0-9]+)?[^0-9]*$/)) {
      oldval = substr(prev, RSTART, RLENGTH) + 0
      if (oldval > newval && newval >= 0) {
        emit("threshold-lowered", sprintf("a threshold moved from %g down to %g", oldval, newval))
      }
    }
  }
  next
}
END { flush_file() }
') || AWK_RC=$?
AWK_RC=${AWK_RC:-0}

# `|| AWK_RC=$?`, not a bare `|| true` and not a following `AWK_RC=$?`. The
# bare `|| true` swallowed every awk runtime error and left HITS empty, which
# this script reported as OK: a broken parser and a clean diff produced the
# identical line. Assigning `$?` on the NEXT line is no better, because under
# `set -e` a failing command substitution in an assignment aborts the script
# before that line runs, and the caller then gets no RESULT line at all. Both
# were observed here, in that order.
if [ "$AWK_RC" -ne 0 ]; then
  echo "SILENCING_RESULT=FAIL (awk exited $AWK_RC, the diff was not parsed)"
  exit 0
fi

if [ -z "$HITS" ]; then
  echo "SILENCING_RESULT=OK"
  exit 0
fi

printf '%s\n' "$HITS"
COUNT=$(printf '%s\n' "$HITS" | grep -c '^SILENCING_HIT ' || true)
echo "SILENCING_RESULT=HITS ($COUNT)"
