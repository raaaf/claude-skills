# Start Question: Three Tiers (Phase 1.5)

Used by `audit/SKILL.md`. One `AskUserQuestion` round, one question, unless `AUDIT_DIMENSIONS` or
`AUDIT_FIX_SCOPE` is set: a set variable suppresses the question (headless/CI/eval-harness never hangs on a prompt).

**Diff profile (decided 2026-10-03).** `audit/bin/diff-profile.sh` reads the scope file list and prints `key=value`
lines: file counts per kind (backend, frontend, view, lang, migration, docs, test, config, API), `QUERY_FILES`/`LOOP_FILES`
(Eloquent/SQL patterns and collection loops, grep on the changed files), `SENSITIVE_PATHS` (`orch_sensitive_paths`),
`PAYMENTS` (`orch_payments_touched` with `STRIPE_FILES`), `SEO_RELEVANT` (`orch_seo_relevant`), the size class
(`DIFF_SIZE_RESULT`, else `diff-size-gate.sh`) and per optional dimension `SUGGEST_<dim>=yes|no` with `REASON_<dim>`:

| Dimension | Suggested when |
|---|---|
| `a11y`, `copy` | frontend or language files changed |
| `performance` | a migration, a file with query patterns, or a collection loop (`->each(`, `.reduce(`, ...) changed |
| `docs_sync` | docs/README/CLAUDE.md, config or route/API files changed |
| `seo` | `orch_seo_relevant` says yes (SEO surface and a frontend/routes change) |
| `typography`, `ui_design`, `ux`, `animation` | view or CSS files changed |
| `code_quality` | backend logic changed and the diff is not `SMALL` |

**Tiers** (built from the profile, payments is added by the Phase 1.5 block's own trigger and never listed in a tier):

| Tier | Dimensions |
|---|---|
| Günstig | security, privacy, architecture (+ payments) and the built-in `/code-review high`, plus a11y and copy when frontend or language files changed |
| Gründlich | Günstig plus every dimension with `SUGGEST_<dim>=yes` |
| Alles | all 13 dimensions |

`RECOMMENDED` (first option, labelled "(Recommended)") is always Günstig on LARGE/HUGE diffs (2026-10-03: zeit Gründlich on a
140-file HUGE diff cost ~78 M, ~3.5% of the week, against a 48 M profile estimate); otherwise Gründlich when sensitive paths
changed or at least 3 dimensions are suggested, else Günstig. The automatic "Other" option takes a custom dimension list. The tiers are advisory: they do not bypass
validation, deterministic checks, Stripe gating or push-marker rules.

**Cost estimate ("grobe Schätzung").** Weighted M tokens: the Günstig base is SMALL 8, OK 12, LARGE/HUGE 18 (measured 2026-10-02:
8.5-14.4 M per gate run incl. the code review); every dimension beyond the three gate dimensions (payments included) adds 1.5 M on a
SMALL diff, 3 M on a larger one. On LARGE/HUGE both scale with the file count N: base max(18, 0.15 N) M, per dimension
max(3, 0.04 N) M. `diff-profile.sh` prints `COST_GUENSTIG`, `COST_GRUENDLICH`, `COST_ALLES` plus `COST_<tier>_PCT` (M x 1.2 USD
/ `WEEK_BUDGET_USD` from `~/.claude/usage-limits.conf`, default 2600); the summary shows the % of the week, and on LARGE/HUGE the
current week estimate (`orch_usage_report`) and "Großer Diff: aufteilen oder Günstig empfohlen". Pinned by `bin/diff-profile.test.sh`.

**`payments` is a CONDITIONAL 14th dimension, not one of the 13 offered here.** It is never part of a tier list unless
`detect-stripe.sh` reports `STRIPE=yes` and the diff touches its surface; a repo without Stripe never sees it. Gating and scope
resolution live in `audit/SKILL.md` Phase 1.5, not in this file.

**Skip via ENV:** a set `AUDIT_DIMENSIONS` (comma list of dimension ids, `all` or `all+full`) or `AUDIT_FIX_SCOPE`
(`none|all`; unset or any other value normalizes to `all`) skips the question. The Phase 1.5 block applies them with `${NAME:-answer}`
and expands the spelling through `orch_expand_dimensions <value> <profile>`: `all` is the Günstig tier of the profile (the base gate set
`security`, `privacy`, `architecture` when there is none, so a frontend diff gets `a11y` and `copy` automatically), `all+full` is all 13
(`all+nightly` stays an accepted alias), an explicit list is unchanged; `payments` is added by the block's own `STRIPE=yes` gate,
never by the env value itself.

Every run fixes every Critical/Important finding it confirms, plus the Minors that ride along with a fix to
their own file; all other Minors go to the backlog (`minor-backlog.md`). `AUDIT_FIX_SCOPE=none`
(headless "find and log only") fixes nothing. There is no fix-scope question and nothing preselects it from the effort
level.

**Gate reduced to three dimensions (decided 2026-10-02).** The base gate runs `security`, `privacy` and `architecture` (plus `payments` automatically), the built-in `/code-review high` on every code diff (`builtin-reviews.md`). Evidence: on a blind benchmark of 5 historical diffs with 6 known audit Criticals the built-in review found all 3 security Criticals and 1 of 2 architecture Criticals, missed the privacy one (OSM tiles without consent) and one policy bypass, and found 2 serious issues the audit never reported; the dimensions cost about 40% of weekly usage. Earlier evidence for the first three optional dimensions (2026-10-01, 122 audit logs): 0 Critical, mostly cosmetic Importants, about 11% of audit-find cost per push; `copy` found destructive dialogs confirmed with "Ja" and `seo` found PIN-protected pages leaking into og: meta. Hence the optional dimensions are proposed per diff (Gründlich) instead of always running. A selection that omits a gate dimension never writes the push marker; the three base dimensions are not a "partial selection".

**Validation:** `SELECTED_DIMENSIONS` must contain at least 1 valid dimension out of the 13, plus
`payments` when `STRIPE=yes` (14 valid values in that case). Discard invalid values.

**Display:** each orchestrator's Phase 1.5 block echoes the resolved values as
`AUDIT_DIMENSIONS=... AUDIT_FIX_SCOPE=...` (`audit/SKILL.md`); there is no
separate formatted "Audit Scope: {N}/13 dimensions" line.

## Conditional and subtractive dimensions (moved from SKILL.md Phase 1.5)

**`payments` (CONDITIONAL 14th dimension):** joins `AUDIT_DIMENSIONS` only when BOTH hold:
`STRIPE=yes` (from Phase 1) AND the changed-file set intersects `STRIPE_FILES`. Once it runs, its scope is `PAYMENTS_SCOPE`:
the touched surface files plus surface files not certified for `payments` (`orch_audited_filter`); `orch_audited_add_dims`
records the certification after a passed audit (first run per repo = full surface; 2026-10-03: one touched Stripe file made
events SMALL diffs rescan the whole surface, 10-17 M each). The intersection is
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
