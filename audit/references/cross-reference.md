# Cross-Reference Pass (Phase 2.5)

Multi-file features break between files, not inside them. This pass runs once per audit, after the
last round of the loop, and looks only for problems that no single-file worker can see.

**Trigger:** number of changed files >= 3 AND `CONFIDENCE_FLOOR != high` (skip on low effort).

```bash
FILES_CHANGED_COUNT=$(echo "$ALLE_DATEIEN" | wc -l)
if [ "$FILES_CHANGED_COUNT" -ge 3 ] && [ "$CONFIDENCE_FLOOR" != "high" ]; then
  RUN_CROSS_REF=1
else
  RUN_CROSS_REF=0
  echo "Cross-Ref skipped (files=$FILES_CHANGED_COUNT, floor=$CONFIDENCE_FLOOR)"
fi
```

If `RUN_CROSS_REF=1`: dispatch a cross-ref subagent (sonnet):

```
Agent(
  subagent_type: code-reviewer,
  model: sonnet,
  prompt: "Cross-reference check of the changed files.
    DATEILISTE: {ALLE_DATEIEN}
    BEREITS_GEFIXT: {BEREITS_GEFIXT}
    PROJECT_GUIDELINES: {PROJECT_GUIDELINES}

    Check ONLY cross-file problems:
    - Services <-> UI: called incorrectly, signatures don't match
    - Models <-> Traits/Mixins: used incorrectly
    - Controller <-> View: mismatches (e.g. variable not passed to the view)
    - Consistency: same pattern project-wide (auth checks, cache keys, error handling)
    - A fix in file A could break file B (e.g. method rename)

    Output format like worker findings. Max 50 words per finding.",
  run_in_background: false
)
```

Findings are treated like Critical/Important (same confidence gate). Auto-fix follows the same rules (fix agent).
