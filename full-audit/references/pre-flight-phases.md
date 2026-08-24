# Pre-Flight Phases 0.3 to 0.45

Three checks that run once at the start of a full audit, before any dimension work. Read and execute in order. All three are skippable via the env flags named in their sections.

## Phase 0.3: Learning Backlog Check

Identical to `/audit` Phase 0. Check whether unprocessed learning suggestions from earlier audits are still open:

```bash
LOG="$(git rev-parse --show-toplevel)/.claude/audits/learning-log.md"
[ -f "$LOG" ] && grep -c "^- \[ \] " "$LOG" 2>/dev/null || echo 0
```

If `>= 1`: implement the open suggestions without asking, then continue Full-Audit with Phase 0.5. List in one line which ones were applied. Changes go to `audit/guidelines/*.md` or `audit/agents/*.md` (these are the GLOBAL skill files affecting all projects). **IMPORTANT — edit in the source repo:** `~/.claude/skills/*` can be a sync target (symlink or unpacked `.skill` bundle) whose content gets overwritten. Before the first edit, resolve the source: check `readlink` or find the skill source repo (e.g. `~/Local Sites/claude-skills`) and edit THERE. Edits in the unpacked copy are lost on the next sync. After implementing: change `[ ]` to `[x]` in learning-log.md.

Leave a suggestion open (and name it) only when implementing it would need a decision the log does not contain. Do not put the list up for selection.

If `0`: continue without asking.

**Additionally — open audit issues & PRs** (identical to `/audit` Phase 0.2):

```bash
if gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com; then
  OPEN_AUDIT_ISSUES=$(gh issue list --state open --label audit-finding --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)
  OPEN_PRS=$(gh pr list --state open --json number,title,headRefName --jq '.[] | "#\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null || true)
fi
```

Open `audit-finding` issues → fix them along with this run without asking: feed in as verified findings in batch 1, after the fix `gh issue close` with a comment. Leave one open only when its resolution needs a decision the repo cannot answer, and name it. `OPEN_PRS` as context: Phase 4 dedup checks against it, PR file overlaps go into the log as a note.

**Skip this phase when:** ENV `AUDIT_SKIP_LEARNING_CHECK=1` OR `FULL_AUDIT_SKIP_LEARNING_CHECK=1` is set (for CI/batch runs).

---

## Phase 0.4: Test Runner Streak Check

Hard check: if a configured test runner is missing across multiple full audits, the gap escalates to a Critical finding (instead of just a gap note). Without a runner, no fix agent can verify regressions.

```bash
ROOT=$(git rev-parse --show-toplevel)
STREAK_FILE="$ROOT/.claude/audits/no-test-runner-streak"
HAS_RUNNER=0
# JS/TS runner in package.json or config files
if [ -f "$ROOT/package.json" ] && grep -Eq '"(vitest|jest|mocha)"|node:test|node --test' "$ROOT/package.json" 2>/dev/null; then HAS_RUNNER=1; fi
# find instead of glob — zsh aborts on non-matching globs
[ -n "$(find "$ROOT" -maxdepth 1 \( -name 'vitest.config.*' -o -name 'jest.config.*' \) 2>/dev/null)" ] && HAS_RUNNER=1
# PHP / Python
{ [ -f "$ROOT/phpunit.xml" ] || [ -f "$ROOT/phpunit.xml.dist" ]; } && HAS_RUNNER=1
[ -f "$ROOT/pytest.ini" ] && HAS_RUNNER=1
grep -q "\[tool.pytest" "$ROOT/pyproject.toml" 2>/dev/null && HAS_RUNNER=1

if [ "$HAS_RUNNER" -eq 1 ]; then
  rm -f "$STREAK_FILE"; TEST_RUNNER_ESCALATE=0
  echo "Test-Runner: vorhanden (Streak zurueckgesetzt)"
else
  STREAK=$(( $(cat "$STREAK_FILE" 2>/dev/null || echo 0) + 1 ))
  echo "$STREAK" > "$STREAK_FILE"
  if [ "$STREAK" -ge 3 ]; then TEST_RUNNER_ESCALATE=1; else TEST_RUNNER_ESCALATE=0; fi
  echo "Test-Runner: FEHLT (Streak=$STREAK, Escalate=$TEST_RUNNER_ESCALATE)"
fi
```

`TEST_RUNNER_ESCALATE=1` → in Phase 3c record the missing test infrastructure as **Critical** in the audit log and as a GitHub issue (Phase 4), not as a gap note. `=0` → gap note as before.

**Skip when:** ENV `FULL_AUDIT_SKIP_TESTRUNNER_CHECK=1`.

---

## Phase 0.45: Build Preflight (compiled languages)

Before the first batch, verify the unchanged HEAD actually builds. A broken build discovered only at the end (Phase 3b linter/tests) means an entire audit run's worth of fixes gets applied on top of code nobody could have compiled in the first place.

```bash
BUILD_PREFLIGHT_RESULT=SKIP
if [ -f "$ROOT/Package.swift" ] || ls "$ROOT"/*.xcodeproj >/dev/null 2>&1 || ls "$ROOT"/*.xcworkspace >/dev/null 2>&1; then
  command -v xcodebuild >/dev/null 2>&1 && BUILD_PREFLIGHT_RESULT=RUN || BUILD_PREFLIGHT_RESULT=NO_TOOLCHAIN
elif [ -f "$ROOT/Cargo.toml" ]; then
  command -v cargo >/dev/null 2>&1 && BUILD_PREFLIGHT_RESULT=RUN || BUILD_PREFLIGHT_RESULT=NO_TOOLCHAIN
elif [ -f "$ROOT/go.mod" ]; then
  command -v go >/dev/null 2>&1 && BUILD_PREFLIGHT_RESULT=RUN || BUILD_PREFLIGHT_RESULT=NO_TOOLCHAIN
elif [ -f "$ROOT/pom.xml" ] || [ -f "$ROOT/build.gradle" ] || [ -f "$ROOT/build.gradle.kts" ]; then
  { command -v gradle >/dev/null 2>&1 || command -v mvn >/dev/null 2>&1; } && BUILD_PREFLIGHT_RESULT=RUN || BUILD_PREFLIGHT_RESULT=NO_TOOLCHAIN
fi
echo "Build preflight: $BUILD_PREFLIGHT_RESULT"
```

`RUN` → run the project's normal build command against the unchanged HEAD (narrowest scope available, e.g. a single scheme/package — not a full clean build), before any fix agent has touched anything. Build fails → log it immediately as a **Critical** finding `[Build]` in batch 1; do not wait for Phase 3b to surface it. Build succeeds → continue silently, no log entry needed.

`SKIP` (no known compiled-language manifest) or `NO_TOOLCHAIN` (manifest present, toolchain missing) → gap note only, same as the Phase 0.4 test-runner gap note, not a finding.

**Skip when:** ENV `FULL_AUDIT_SKIP_BUILD_PREFLIGHT=1`.

---
