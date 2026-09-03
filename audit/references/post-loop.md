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

## 3d.5. Post-Log-Check (mandatory, before 3e)

Two mechanical checks on the log file just written, both deterministic — no judgment call, just
grep/date-compare:

1. **Severity tags restricted to `{Critical, Important, Minor}`.** Run
   `grep -noE '\[[A-Za-z]+\]' {LOGFILE} | grep -viE '\[(Critical|Important|Minor|[A-Za-z]+)\]'`
   is not enough on its own since dimension tags also use brackets — instead check every
   `[SeverityCandidate]` token that sits in the position the audit-log-template puts severity
   (immediately after `- ` at the start of a finding line): it MUST be one of the three. A
   non-canonical tag (`[Major]`, `[Blocker]`, `[Note]`, ...) is a bug in the line that wrote it —
   fix the line to the correct one of the three, do not invent a fourth category. Reference case
   (2026-08-13): a log used `[Major]` twice, which is not a severity this skill defines, and the
   learning run had to reconstruct severities by hand afterwards. Same check for the dimension tag
   that follows the severity: it MUST be one of the 12 canonical ids `architecture`, `security`,
   `performance`, `code_quality`, `seo`, `a11y`, `typography`, `ui_design`, `ux`, `animation`,
   `docs_sync`, `copy` (case and spelling exactly as here, the display form `[Docs]`/`[A11y]`
   from the log template maps 1:1 onto these). Free variants (`accessibility`, `A11Y`, `Code
   Quality`, `docs`) have broken the "top category" metric since 2026-08-06; normalize the
   line, do not leave the variant standing.
2. **`Findings fixed: Critical N / Important N / Minor N` line present.** If `## Result` is missing
   it, write it now per `audit-log-template.md`'s "Mandatory Field" section (recompute by counting
   the itemized bullets, never hand-tally) before moving on. A log without this line breaks the
   learning log's trend computation for this run.
3. **If any `CONFIRMED` verdict occurred this run, `patterns.json` must be newer than the log file
   you are about to write.** Compare `stat -f %m` (or `date -r`) on
   `{PROJECT_ROOT}/.claude/audits/patterns.json` against the log's own write time; if the store is
   older (or the file does not exist), the per-verdict `patterns-store.sh recur` calls from
   `fix-loop.md` did not actually run. Do not silently back-fill and move on — write one line under
   `## Notes`: `Post-Log-Check: patterns.json stale/missing after N CONFIRMED findings, recur calls
   did not fire during the loop.` This is a sharper version of the Phase-5 `learning-phase.md` Step
   0.5 check (which also back-fills): catching it here, right after the loop, names the failure at
   the point it happened instead of only at the very end of the run.

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

**Step 1 — decide, do not ask:**

List all open points compactly (dimension, file:line, 1-sentence question). Then decide each one
yourself and act on it, instead of putting a menu in front of the user:
- **Default: decide + fix now** — pick the better direction from the repo's own evidence (existing patterns, `DECIDED_TRADEOFFS`, CLAUDE.md, the surrounding code) and dispatch fix agents with that decision as context. Fix-verifier checks as usual.
- **Discard** — for a point the evidence refutes; `patterns-store.sh dismissed`, on repeated discards the learning agent proposes a suppression.
- **Defer as issue** — only for a point that is genuinely undecidable here: it needs information outside the repo (a product tradeoff nobody wrote down, an external dependency, a user-facing behavior change with no precedent). This is the exception, not a menu item.

Report the decisions as one line per point (decision + one-sentence reason). Use `AskUserQuestion`
only for points in the third bucket — a point you can reason about is a point you decide.

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
1b. **Dedup against open PRs:** check `OPEN_PRS` from Phase 0 (`pre-flight-checks.md`, open issues & PRs check), fallback:
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
