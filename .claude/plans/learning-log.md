# Plan Learning Log

## Trends (as of 2026-09-05)

| Metric | Value |
|---|---|
| Plans total | 2 |
| Phase 1 rounds (last 2) | 1 -> 2 (increasing) |
| Total concerns (last 2) | 8 -> 12 |
| Top dimension (last 2) | Architecture (2x) |
| Avg concerns/plan | 10 |
| Incorporation acceptance rate | 100% |

**Recurrers (>=3 plans):**
- None yet — only 2 plans logged, insufficient data for the >=3 threshold.


Dieses Log wird automatisch nach jedem Plan aktualisiert.

---

## Retro — 2026-05-12 — Live Audit Pipeline

### Statistik
- Erster Plan im Projekt — noch keine Pattern-Erkennung möglich
- Runden Phase 1 (Verstehen): 1

### Baseline
- Concerns gesamt: 15 raw → 8 nach Dedupe
- Eingearbeitet: 8 (alle)
- Akzeptiert: 0
- Abgelehnt: 0
- Evaluator-Vorschläge: 3 (alle eingearbeitet)

### Key Findings
- **Architecture+Risk Konvergenz**: Fingerprinting-Concern wurde sowohl von Architecture als auch Risk identifiziert (Dedupe-Fall)
- **Product+Simplicity Abwägung**: Broken Links wurden in Challenge als zu kostspielig für MVP eingestuft
- **Offene Probleme**: PSI-Varianz-Schwankungen waren ungelöst, durch Toleranz-Band adressiert
- **Config-Lücke**: state.json fehlte offensichtlich als Zustandsspeicher neben sites.json

### Design Decisions
- **sites.json als Konfigurationsquelle** (statt Hardcoding)
- **state.json für Pipeline-State** (statt Scheduled-Task-Config)
- **Toleranz-Band für PSI-Varianz** (±5% range für Schwankungserkennung)
- **GitHub-native Email** für Notification-Channel
- **Gestaffelter Rollout** (alle Findings im ersten Run, danach gefiltert)

### Bemerkenswert
- Hohe Konvergenz zwischen unabhängigen Challenge-Tracks (Architecture + Risk)
- Product-Concern (Broken Links) wurde durch Simplicity-Realism überlagert
- Evaluator brachte technische Klarheit (PSI-Varianz) ein, obwohl nicht direkt nachgefragt
- Keine Rückfragen nötig — Anforderungen waren klar genug

---

## Retro — 2026-09-05 — Audit-Pipeline pro Dimension (Umbau von /audit und /full-audit)

### Statistics
- Plans in project: 2
- Phase 1 rounds (last 2): 1 -> 2
- Total concerns after dedupe (last 2): 8 -> 12
- Top dimension with concerns: Architecture (2x, both plans — Architecture+Risk resp. Architecture+Design convergence)

### What went well
- 100% incorporation rate in both plans (0 accepted-as-is, 0 rejected) — challenge concerns land as real plan changes, not friction.
- Evaluation stage caught real issues both times: plan 1 clarified PSI variance unprompted, plan 2 caught two silent CLAUDE.md violations (Opus-for-security, guideline-scoping).

### What went poorly
- Only 2 data points; too early for confident trend claims.
- Plan 2 needed 2 rounds vs 1 for plan 1 — user added a mid-turn product rule (no custom args) not surfaced by initial questions.

### Detected patterns
- Architecture dimension converges with another track (Risk, then Design) in both plans (seen in 2 plans) — worth watching as a candidate recurring blind spot in initial architecture drafts.
- User consistently picks a leaner scope than the recommendation (plan 2: dropped Testplan+Issues phases) — seen in 1 plan so far, not yet a confirmed preference (needs 2x).

### User preferences
- Not yet established — only one plan shows the "choose less than recommended" behavior; needs a second occurrence to count as a preference per the >=2x rule.

### Suggested improvements
- [ ] Phase 1 questions: add an explicit "any product-level constraints (no CLI args, no config flags, etc.)?" question, since plan 2's mid-turn correction suggests this isn't asked directly.
- [ ] Evaluation agent template: keep the CLAUDE.md-invariant checklist step (Opus-for-security, guideline-scoping) as explicit — plan 2's notable section flags this as otherwise silently missed.
