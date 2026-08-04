# Audit Log + GitHub Issues (Phase 4 Detail)

Detail for Phase 4 (write audit log and create GitHub issues).

## Audit Log Format

```bash
AUDIT_DIR="$(git rev-parse --show-toplevel)/.claude/audits"
mkdir -p "$AUDIT_DIR"
LOGFILE="$AUDIT_DIR/$(date +%Y-%m-%d_%H%M%S)-full-audit.md"
```

Format:

```markdown
# Full Audit — {DATUM}

## Scope
- Dimensions: {N}/12 — {SELECTED_DIMENSIONS}
- Mode: SINGLE | BATCHED ({N} batches)
- Backend files: X
- Frontend files: Y
- Rounds total: Z

## Result
- Critical found/fixed: A/B
- Important found/fixed: C/D
- Minor found/fixed: E/F

## Fixed Issues
- [Security] app/Foo.php:42 — XSS via {!! !!} → replaced with {{ }}

## Manual Test Plan
- (test plan steps, if visual files present)

## Open Points
- [Code Quality] app/Baz.php — refactor needed (not auto-fixable)

## Unverified
- [Dimension] file:line: description. Verification inconclusive: {REASON from D.7}

## Clean
Performance, SEO
```

### Unverified Section (Step D.7)

The `Unverified` section holds the `UNCERTAIN` verdicts from Step D.7 (audit/SKILL.md), one line per finding: dimension, file:line, the description, and the verifier's `REASON` why verification was inconclusive. Omit the heading entirely when no finding came back `UNCERTAIN` in the batch. A Critical `UNCERTAIN` additionally becomes an open point for the user, in addition to appearing here.

## Display Audit Log in Chat (MANDATORY)

Load the full content of the log file (incl. test plan) via the Read tool and output it as a markdown code block in the chat:

```
Audit Log: {LOGFILE}

---
{Content of the log file}
---
```

## Open Points: User Decision → Fix / Issue / Discard

Issues are the exception, not the default. Open points are only genuine decision points now — fixable items were fixed in the loop, unconfirmed ones were discarded. **Minor findings NEVER get issues** (they stay in the log).

**Step 1 — user decision (AskUserQuestion), MANDATORY when open points exist:**

List the points compactly (dimension, file:line, 1-sentence question), then per point or in aggregate:
- **Decide + fix now** — user gives the direction (1 sentence), fix agents implement, fix verifier checks
- **Defer as issue** — only these become issues (step 2)
- **Discard** — discard + add to the dismissed-pattern store; repeated discarding → learning agent proposes a suppression

**Step 2 — issues ONLY for explicitly deferred items:**

1. **Precheck:** `gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com` — otherwise deferred points stay in the log.
2. **Dedup per finding:** `gh issue list --state open --search "[audit] {Dimension} {datei}" --json number` — an issue that already exists → skip. Also check against `OPEN_PRS` (Phase 0.3) — if an open PR already addresses the same spot → skip + log note.
3. **Create:**
   ```bash
   gh issue create \
     --title "[audit] [{Dimension}] {datei}:{zeile} — {kurzbeschreibung}" \
     --body "{Details}

   **Entscheidung noetig:** {die konkrete Frage}

   **Quelle:** {LOGFILE}" \
     --label "audit-finding"
   ```
   Create the label via `gh label create audit-finding --color FBCA04` if needed.
4. **Output:** `{N} fixed, {M} deferred as issues: {urls}, {K} discarded`.
5. `gh` errors do NOT block — warn briefly and continue.
6. CI/headless (non-interactive): skip step 1, defer all open points directly as issues.
