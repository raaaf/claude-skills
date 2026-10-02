# Start Question: Dimensions (Phase 1.5)

Used by `audit/SKILL.md`. One `AskUserQuestion` round, one
question, unless `AUDIT_DIMENSIONS` or `AUDIT_FIX_SCOPE` is set — a set variable suppresses the
question (headless/CI/eval-harness never hangs on a prompt).

For interactive `/audit` only, `audit/bin/suggest-dimensions.sh` may display a path-based
recommendation immediately before the question. It is context, not a preset, does not preselect an
answer, and never changes `AUDIT_DIMENSIONS`. Everything remains the default and all existing
choices remain available. The suggestion
does not bypass dimension validation, deterministic checks, Stripe gating, or push-marker rules.

**`payments` is a CONDITIONAL 14th dimension, not one of the 13 offered here.** It is never
presented in the Custom multi-select and never part of any preset unless `detect-stripe.sh`
reports `STRIPE=yes` for the current repo; a repo without Stripe never sees it at all. Gating and
scope resolution live in `audit/SKILL.md` Phase 1.5, not in this file.

**Skip via ENV:** a set `AUDIT_DIMENSIONS` (comma list of dimension ids, or `all`) or `AUDIT_FIX_SCOPE`
(`none|all`; unset or any other value normalizes to `all`) skips the question. The Phase 1.5 block
in the orchestrator (`audit/SKILL.md`) applies them with `${NAME:-answer}`
and expands the spelling through `orch_expand_dimensions`: `all` is the gate set (`security`, `privacy`, `architecture`), `all+nightly` is all 13 (`all+visual` stays an accepted alias); `payments` is added by the block's own `STRIPE=yes` gate, never by
the env value itself.

**Otherwise via `AskUserQuestion`, one round, one question:**

Dimension preset:

| Option | Dimensions |
|---|---|
| Everything (default, the gate set) | security, privacy, architecture, payments (only when `STRIPE=yes` and the diff touches its surface) |
| Backend only | architecture, security, performance, code_quality, docs_sync, privacy, payments (only when `STRIPE=yes`) |
| Frontend only | seo, a11y, typography, ui_design, ux, animation, copy |
| Custom | multi-select across all 13 dimensions; `payments` joins the list only when `STRIPE=yes` |

Every run fixes every Critical/Important finding it confirms, plus the Minors that ride along with a fix to
their own file; all other Minors go to the backlog (`minor-backlog.md`). `AUDIT_FIX_SCOPE=none`
(headless "find and log only") fixes nothing. There is no fix-scope question and nothing preselects it from the effort
level.

**Gate reduced to three dimensions (decided 2026-10-02).** The pre-push gate runs `security`, `privacy` and `architecture` (plus `payments` automatically), the built-in `/code-review high` on every code diff (`builtin-reviews.md`). `performance`, `code_quality`, `a11y`, `ux`, `copy`, `seo`, `docs_sync`, `typography`, `ui_design` and `animation` run in the nightly run (`minor-backlog.md`). Evidence: on a blind benchmark of 5 historical diffs with 6 known audit Criticals the built-in review found all 3 security Criticals and 1 of 2 architecture Criticals, missed the privacy one (OSM tiles without consent) and one policy bypass, and found 2 serious issues the audit never reported; the dimensions cost about 40% of weekly usage. Earlier evidence for the first three nightly dimensions (2026-10-01, 122 audit logs): 0 Critical, mostly cosmetic Importants, about 11% of audit-find cost per push; `copy` found destructive dialogs confirmed with "Ja" and `seo` found PIN-protected pages leaking into og: meta, and both now get their coverage nightly. All of them stay selectable via Custom, Frontend only, an explicit `AUDIT_DIMENSIONS` list or `all+nightly`. The gate set is not a "partial selection" for the marker rule; a selection that omits a gate dimension is.

**Validation:** `SELECTED_DIMENSIONS` must contain at least 1 valid dimension out of the 13, plus
`payments` when `STRIPE=yes` (14 valid values in that case). Discard invalid values.

**Display:** each orchestrator's Phase 1.5 block echoes the resolved values as
`AUDIT_DIMENSIONS=... AUDIT_FIX_SCOPE=...` (`audit/SKILL.md`); there is no
separate formatted "Audit Scope: {N}/13 dimensions" line.

## Conditional and subtractive dimensions (moved from SKILL.md Phase 1.5)

**`payments` (CONDITIONAL 14th dimension):** joins `AUDIT_DIMENSIONS` only when BOTH hold:
`STRIPE=yes` (from Phase 1) AND the changed-file set intersects `STRIPE_FILES`. The intersection is
computed against `STRIPE_FILES`, the precomputed Stripe surface `detect-stripe.sh` already found,
never by grepping the diff text for "stripe": half of a payments checklist is about an *absent*
guard (a webhook route with no signature check, a client secret logged instead of masked), and an
absence never shows up as a line in a diff — a diff-text grep would silently miss exactly the class
of defect this dimension exists to catch. Test files (`tests/`, `spec/`, `__tests__/`, `*Test.php`,
`*.test.*`, `*.spec.*`) are excluded from the changed set before intersecting: on 2026-09-30
`tests/Pest.php` sat in `STRIPE_FILES`, a diff touching only it started payments (12 agents, 41 USD,
35 findings, all in unchanged code).

**Already-audited files are skipped (2026-09-30).** `orch_audited_filter` drops every file whose
working-tree content is byte-identical (git blob sha) to what an earlier PASSED audit in this
worktree certified, provided that audit's dimension set covers the current selection. Commits,
amends and rebases do not matter, only content does. Reason: re-running `/audit` on one branch
re-reviewed every file each time; 37% of audit-find cost from 09-27 to 09-30 went to runs where more
than half the files had been audited before (shop/printify worktree: 13 audits in 24 h, cumulative
scope 6, 21, 24, 27, 47, 71 files; events: 347 files, then 357 files with 97% already audited).
`ALLE_DATEIEN_FULL` keeps the whole list; `ALLE_DATEIEN` is the filtered set every later phase
uses. `DIFF_SIZE_RESULT` stays the Phase 1 value over the whole diff: `diff-size-gate.sh` takes no
file list, so it cannot be recomputed on the filtered set cheaply. The record is written only in
Phase 4 on the marker path.

**`seo` gate (decided 2026-10-01, `bin/orch-seo-relevant.test.sh`).** Evidence: 122 audit logs, 4% of audit-find cost, 12 Important and 0 Critical in 12 days, the worst cost per finding (4.6 M); most repos are logged-in apps. `orch_seo_relevant <changed> <root>` keeps `seo` only when BOTH hold: (1) an SEO surface exists: a sitemap (file named `*sitemap*`, or a route file mentioning it), or views emitting `<meta name="description"`, `og:`, `twitter:` meta, `application/ld+json`, or a `<title>` filled from a layout section/prop; `public/robots.txt` alone does not count (Laravel ships one); (2) the filtered diff touches a `FRONTEND_EXT_RE` file or a routes file. Never on `PLATFORM=native`. A drop prints `SEO_SKIP: <reason>`; the dropped dimension is not selected, so it is neither skipped nor incomplete at the marker gate.

**`privacy` fold (decided 2026-10-01, `workflows/find.privacyfold.test.cjs`).** Evidence: privacy was 7% of audit-find cost (1 Critical + 29 Important in 12 days) with the same agent type and files as security. With both selected, `find.js` dispatches no privacy scout, specialist or verifier: the security specialists also read `13-privacy.md` (a `PRIVACY FOLD` briefing line), may tag findings `privacy` (id prefix `privacy-`), and security's verifier checks them. The floor files of privacy join security's. `find.js` reports `dimensions.privacy = {status: 'folded', into: 'security'}`: not `skipped`, not `incomplete`, so the Phase 4 counts ignore it and security's own status gates the marker. Privacy selected without security runs its own pipeline as before. Tag the audit-log line `[privacy]` when the id starts with `privacy-`.
