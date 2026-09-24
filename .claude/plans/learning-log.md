# Plan Learning Log

## Trends (as of 2026-09-24)

| Metric | Value |
|---|---|
| Plans total | 3 |
| Phase 1 rounds (last 3) | 1 -> 2 -> 4 (increasing) |
| Total concerns (last 3) | 8 -> 12 -> 12 |
| Top dimension (last 3) | Architecture (3x) |
| Avg concerns/plan | 10.7 |
| Incorporation acceptance rate | ~94% (100%, 100%, 83%) |

**Recurrers (>=3 plans):**
- Architecture concerns converging with another challenge track: provisionally confirmed, keep observing (3/3, but plan 3's instance was unverifiable due to missing Bash)
- User overriding recommended scope (direction alternates fuller/leaner): candidate for softer scope recommendations, not a fixed default

**Override counts:**
- Scope cut overruled: 2x (of which 0x self-override)
- Defer recommendation overruled: 0x

---|---|
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
- [x] Phase 1 questions: add an explicit "any product-level constraints (no CLI args, no config flags, etc.)?" question, since plan 2's mid-turn correction suggests this isn't asked directly.
- [x] Evaluation agent template: keep the CLAUDE.md-invariant checklist step (Opus-for-security, guideline-scoping) as explicit — plan 2's notable section flags this as otherwise silently missed.

---

## Retro: 2026-09-24: /screens skill

### Statistics
- Plans in project: 3
- Phase 1 rounds (last 3): 1 -> 2 -> 4
- Total concerns after dedupe (last 3): 8 -> 12 -> 12
- Top dimension with concerns: Architecture (3x across all 3 plans)

### What went well
- Mid-plan user additions (GitHub/web prior-art check, before/after screenshot integration) were absorbed without derailing the round structure.
- The pilot-project read (existing ScreenshotTourTests) reversed a wrong driver decision before it reached the plan.

### What went poorly
- Codebase scan missed the `apps/` directory level and all native iOS apps; two challengers reported "does not exist" for wrong paths. Caught only by the orchestrator's own `ls`.
- Repo CLAUDE.md constraints (no npm deps, subagent write-block, worker-spec vs registered-agent split) were checked only after v1 was drafted, causing three corrections before the challenge round.
- Two challengers (architecture, risk) ran without Bash and could not run the mandated drift check.
- Phase 1 rounds are trending up (1 -> 2 -> 4).

### Detected patterns
- Scan-reported paths are not reliably ground-truthed before entering a plan (provisionally confirmed with plan 2's analogous miss).
- User diverges from the recommended scope in 3/3 plans; direction alternates.
- Architecture concerns co-occur with another track in 3/3 plans.

### User preferences
- Stable preference is "user overrides the recommended scope", not a fixed size.

### Suggested improvements
- [ ] Step B scan template: require one spot-check `ls` on any directory-level path the scan reports, before it enters v1.
- [ ] Step B scan template: add "read the target repo's CLAUDE.md for hard constraints" as an explicit sub-step, not a post-hoc correction.
- [ ] Challenger dispatch config: verify all 5 challenger types get Bash access when the plan mandates a drift check.
