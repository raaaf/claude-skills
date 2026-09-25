# Start Question: Dimensions (Phase 1.5)

Used by both `audit/SKILL.md` and `full-audit/SKILL.md`. One `AskUserQuestion` round, one
question, unless `AUDIT_DIMENSIONS` or `AUDIT_FIX_SCOPE` is set — a set variable suppresses the
question (headless/CI/eval-harness never hangs on a prompt).

**`payments` is a CONDITIONAL 14th dimension, not one of the 13 offered here.** It is never
presented in the Custom multi-select and never part of any preset unless `detect-stripe.sh`
reports `STRIPE=yes` for the current repo; a repo without Stripe never sees it at all. Gating and
scope resolution live in `audit/SKILL.md` Phase 1.5 and `full-audit/SKILL.md`, not in this file.

**Skip via ENV:** a set `AUDIT_DIMENSIONS` (comma list of dimension ids, or `all`) or `AUDIT_FIX_SCOPE`
(`none|all`; unset or any other value normalizes to `all`) skips the question. The Phase 1.5 block
in each orchestrator (`audit/SKILL.md`, `full-audit/SKILL.md`) applies them with `${NAME:-answer}`
and expands `all` to the 13 ids; `payments` is added by the block's own `STRIPE=yes` gate, never by
the env value itself.

**Otherwise via `AskUserQuestion`, one round, one question:**

Dimension preset:

| Option | Dimensions |
|---|---|
| Everything (default) | architecture, security, performance, code_quality, seo, a11y, typography, ui_design, ux, animation, docs_sync, copy, privacy, payments (only when `STRIPE=yes`) |
| Backend only | architecture, security, performance, code_quality, docs_sync, privacy, payments (only when `STRIPE=yes`) |
| Frontend only | seo, a11y, typography, ui_design, ux, animation, copy |
| Custom | multi-select across all 13 dimensions; `payments` joins the list only when `STRIPE=yes` |

Every run fixes every finding it confirms, including Minor, unless `AUDIT_FIX_SCOPE=none` (headless
"find and log only"). There is no fix-scope question and nothing preselects it from the effort
level.

**Validation:** `SELECTED_DIMENSIONS` must contain at least 1 valid dimension out of the 13, plus
`payments` when `STRIPE=yes` (14 valid values in that case). Discard invalid values.

**Display:** `Audit Scope: {N}/13 dimensions (14 when `payments` runs) — {list} | Fix scope: {all|none}`.
