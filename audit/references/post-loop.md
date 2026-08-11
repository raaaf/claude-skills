# Post-Loop: Changelog, Linter, Tests, Test Plan, Issues, Log Display (Phase 3 Detail)

After loop end, before pre-push. Order: 3a → 3b → 3c → 3d → 3e → 3f.

## 3a. Changelog/Release Notes

Check yourself whether user-facing changes need a changelog entry. Candidate files: `CHANGELOG.md`, `changelog.md`, `release-notes/next.md`, `resources/changelog.md`, `CHANGES.md`.

Ignore: pure test changes, internal services without UI, refactors without behavior change, config, migrations without new features.

No matching entry exists → draft an entry, format follows the file's existing style, insert chronologically at the top.

## 3b. Linter & Static Analysis · 3c. Test Suite

Detection tables and commands are in `linters-and-tests.md`. Order: Formatter → Linter → Static Analysis → Tests. On failures: fix, re-run. Add unfixable test failures as Critical.

**Tests diff-scoped only:** only run tests affected by the changed files (mapping in `linters-and-tests.md`). NEVER `composer test` / `npm test` in `/audit` — the full suite runs in CI. This skill must not let runtime explode via a 2000+ test suite.

## 3d. Create Manual Test Plan

If visual files are in the diff (FRONTEND_DATEIEN or VISUELL_RELEVANTE_DATEIEN not empty), generate a test plan per `testplan.md`: template, URL derivation per framework, rules. Max 10 steps, only for actually changed spots. Write it into the audit log under `## Manual Test Plan` AND output it in chat.

## 3e. Display Audit Log in Chat (MANDATORY — after test plan)

After completing 3a-3d, load the complete content of the log file (including the test plan) via the Read tool and output it as a markdown code block in chat:

```
Audit log: {LOGFILE}

---
{content of the log file}
---
```

This gives the user the complete result including the test plan at a glance.

## 3f. Open Points: User Decision → Fix / Issue / Discard

**Goal:** issues are the exception, not the default. Open points are only genuine decision points left (architecture tradeoffs, behavior changes) — everything fixable was fixed in the loop, unconfirmed items were discarded. Minor findings NEVER become issues (they stay in the audit log and resurface at the next audit if still relevant).

**If `## Open Points` is empty:** skip 3f entirely, log `3f: n/a (no open points)`.

**Step 1 — User decision via AskUserQuestion:**

List all open points compactly (dimension, file:line, 1-sentence question). Then ask — for <= 4 points, one question per point (bundled as multiSelect-capable), for more a collective question with options:
- **Decide + fix now** — user gives the direction per point (1 sentence is enough), orchestrator dispatches fix agents with the decision as context. Fix-verifier checks as usual.
- **Defer as issue** — only these points become issues (step 2).
- **Discard** — point is discarded + `patterns-store.sh dismissed`; on repeated discards, the learning agent proposes a suppression.

**Step 2 — Issues ONLY for explicitly deferred points:**

Precheck:
```bash
gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com || echo "kein gh/github — vertagte Punkte bleiben im Log"
```

**Quoting rule (mandatory, all three commands below):** `{datei}`, `{kurzfingerprint}`, and every other repo-derived placeholder are attacker-controllable. Never interpolate them directly into a double-quoted shell string — `$(...)` and backticks are live there and execute at issue-creation time. Read the value into a variable via a quoted heredoc (`<<'EOF'` — the quoted delimiter disables all expansion of the body) first, then reference `"$VAR"`; a plain variable expansion does not get re-parsed for substitution.

1. **Dedup against issues:**
   ```bash
   read -r FP <<'EOF'
{kurzfingerprint}
EOF
   gh issue list --state open --search "[audit] $FP" --json number,title
   ```
   If an issue with this `[Dimension] datei:zeile` already exists, **skip**.
1b. **Dedup against open PRs:** check `OPEN_PRS` from Phase 0.2, fallback:
   ```bash
   read -r DATEI <<'EOF'
{datei}
EOF
   gh pr list --state open --search "$DATEI"
   ```
   If an open PR already addresses this spot, **skip** + note in the log (`deferred — covered by PR #{N}`).
2. **Create issue:**
   ```bash
   read -r TITLE <<'EOF'
[audit] [{Dimension}] {datei}:{zeile} — {kurzbeschreibung}
EOF
   gh issue create --title "$TITLE" --label "audit-finding" --body-file - <<'EOF2'
{Finding-Beschreibung}

**Entscheidung noetig:** {die konkrete Frage an den User}

**Quelle:** `{LOGFILE}` (Audit vom {DATUM}, Branch `{BRANCH}`, HEAD `{SHORT_SHA}`)
EOF2
   ```
3. Label missing in repo → `gh label create audit-finding --color FBCA04`, then retry.
4. Output: `{N} points fixed, {M} deferred as issues: {urls}, {K} discarded`.

**Important:** errors do NOT block the push. On `gh` error, report briefly and continue with Phase 4. In CI/headless (`AUDIT_SKIP_LEARNING_CHECK=1` as a proxy for non-interactive): skip step 1, defer all open points directly as issues (old behavior).
