# Dimension Selection (Phase 0.5)

Before scope is collected, clarify which dimensions should be checked. Saves tokens and time when the user e.g. only wants Security checked.

**Skip via ENV (for CI/batch):**

```bash
if [ -n "${FULL_AUDIT_DIMENSIONS:-}" ]; then
  case "$FULL_AUDIT_DIMENSIONS" in
    all|"") SELECTED_DIMENSIONS="architecture,security,performance,code_quality,seo,a11y,typography,ui_design,ux,animation,docs_sync,copy" ;;
    *)      SELECTED_DIMENSIONS="$FULL_AUDIT_DIMENSIONS" ;;
  esac
  echo "Dimensions via ENV: $SELECTED_DIMENSIONS"
fi
```

**Otherwise via AskUserQuestion (1 or 2 questions):**

Question 1 — preset:

| Option | Dimensions |
|---|---|
| Everything (default) | architecture, security, performance, code_quality, seo, a11y, typography, ui_design, ux, animation, docs_sync, copy |
| Backend only | architecture, security, performance, code_quality, docs_sync |
| Frontend only | seo, a11y, typography, ui_design, ux, animation, copy |
| Custom | (triggers question 2) |

Question 2 (only for Custom) — multi-select across all 12 dimensions. User picks any combination.

**Validation:** `SELECTED_DIMENSIONS` must contain at least 1 valid dimension. Discard invalid values.

**Display:** `Full-Audit Scope: {N}/12 dimensions — {list}`.

---
