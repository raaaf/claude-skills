# Start Questions: Dimensions + Fix Scope (Phase 1.5)

Used by both `audit/SKILL.md` and `full-audit/SKILL.md`. One `AskUserQuestion` round, two
questions, unless `AUDIT_DIMENSIONS` or `AUDIT_FIX_SCOPE` is set — a set variable suppresses both
questions (headless/CI/eval-harness never hangs on a prompt).

**`payments` is a CONDITIONAL 14th dimension, not one of the 13 offered here.** It is never
presented in the Custom multi-select and never part of any preset unless `detect-stripe.sh`
reports `STRIPE=yes` for the current repo; a repo without Stripe never sees it at all. Gating and
scope resolution live in `audit/SKILL.md` Phase 1.5 and `full-audit/SKILL.md`, not in this file.

**Skip via ENV:**

```bash
if [ -n "${AUDIT_DIMENSIONS:-}" ] || [ -n "${AUDIT_FIX_SCOPE:-}" ]; then
  case "${AUDIT_DIMENSIONS:-all}" in
    all|"")
      SELECTED_DIMENSIONS="architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy,privacy"
      [ "${STRIPE:-no}" = "yes" ] && SELECTED_DIMENSIONS="$SELECTED_DIMENSIONS,payments"
      ;;
    *) SELECTED_DIMENSIONS="$AUDIT_DIMENSIONS" ;;
  esac
  case "${CLAUDE_EFFORT:-medium}" in
    low) FIX_SCOPE_DEFAULT=none ;;
    high|xhigh) FIX_SCOPE_DEFAULT=all ;;
    *) FIX_SCOPE_DEFAULT=critical ;;
  esac
  AUDIT_FIX_SCOPE="${AUDIT_FIX_SCOPE:-$FIX_SCOPE_DEFAULT}"
  echo "Dimensions via ENV: $SELECTED_DIMENSIONS | Fix scope: $AUDIT_FIX_SCOPE"
fi
```

**Otherwise via `AskUserQuestion`, one round, two questions:**

Question (a) — dimension preset:

| Option | Dimensions |
|---|---|
| Everything (default) | architecture, security, performance, code_quality, seo, a11y, typography, ui_design, ux, animation, docs_sync, copy, privacy, payments (only when `STRIPE=yes`) |
| Backend only | architecture, security, performance, code_quality, docs_sync, privacy, payments (only when `STRIPE=yes`) |
| Frontend only | seo, a11y, typography, ui_design, ux, animation, copy |
| Custom | multi-select across all 13 dimensions; `payments` joins the list only when `STRIPE=yes` |

Question (b) — fix scope, preselected from `${CLAUDE_EFFORT:-medium}` (`low` → find only,
`medium` → Critical, `high`/`xhigh` → Critical and Important):

| Option | `AUDIT_FIX_SCOPE` |
|---|---|
| Find and log only | `none` |
| Fix Critical | `critical` |
| Fix Critical and Important | `all` |

**Prose gate override:** when `DIFF_CLASS=prose` (`/audit` only), the dimension preselection
narrows to `docs_sync,copy` and the fix-scope preselection is `none`, regardless of
`CLAUDE_EFFORT` — see `references/prose-gate.md`.

**Validation:** `SELECTED_DIMENSIONS` must contain at least 1 valid dimension out of the 13, plus
`payments` when `STRIPE=yes` (14 valid values in that case). Discard invalid values.

**Display:** `Audit Scope: {N}/13 dimensions (14 when `payments` runs) — {list} | Fix scope: {none|critical|all}`.
