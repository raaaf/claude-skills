# Live Audit Pipeline

## Problem

Drei Sites (rafaelalex.de, events.rafaelalex.de, zeit.rafaelalex.de) werden nicht regelmäßig auf Performance, SEO, Accessibility und SSL geprüft. Regressions fallen erst auf wenn Nutzer sie melden oder Google sie abstraft.

## Ziel

Wöchentlicher automatischer Audit aller drei Sites. Neue Findings landen als GitHub Issues im jeweiligen Repo. Das System lernt welche Issues bewusst unterdrückt werden und reduziert Rauschen über Zeit.

**Messbar:** Nach 4 Wochen sind keine doppelten Issues mehr vorhanden, Suppressions decken bewusst akzeptierte Findings ab.

## Nicht-Ziele

- Code-Analyse (kein Repo-Scan, kein Dependency-Check)
- Uptime-Monitoring (kein Ping alle X Minuten)
- n8n / separate Mail-Infrastruktur (GitHub-Mails reichen)
- Broken Links (eigener Service, zu viele False Positives, PSI deckt relevanteres ab)
- Mobile-only Audit (beide Strategien: mobile + desktop)

## Lösung

### Ansatz

**`sites.json`** als einzige Konfig-Quelle: `[{ "url": "...", "github_repo": "...", "psi_strategy": ["mobile", "desktop"] }]`. Alle drei Sites + Repos darin definiert, nie hartcodiert.

**PageSpeed Insights API** statt Chrome DevTools MCP für die Scheduled Runs. Die PSI API (öffentlich, kein Key nötig) gibt einen vollständigen Lighthouse-Report als JSON zurück. Bei 429: Finding skippen + Warning in Run-Summary, nicht Abort. PSI-Calls sequenziell mit 2s Delay (verhindert 429 bei Shared-IP).

**Issue-Fingerprinting** per `site|metric-id`, ohne Messwert im Titel. Stabil auch wenn Scores schwanken. Messwert kommt in den Issue-Body. Vor dem Erstellen: `gh issue list --label audit --state open` prüfen.

**Toleranz-Band**: Ein Finding wird nur als Issue erstellt wenn der Threshold in 2 aufeinanderfolgenden Runs überschritten wird. Verhindert Noise durch PSI-Messvarianz (±10-15% pro Run). State für "pending findings" in `state.json`.

**Suppressions** via explizitem `suppress`-Label. Rafael setzt das Label auf ein Issue → suppressions.json wird beim nächsten Run aktualisiert. Kein Auto-Ableitungs-Mechanismus aus geschlossenen Issues (zu fehleranfällig).

**`state.json`** in `.claude/live-audit/state.json` pro Repo: enthält `rollout_week`, `last_run`, `pending_findings` (für Toleranz-Band). Orchestrator liest und schreibt nach jedem Run.

**Audit-Log** pro Run in `.claude/audits/live-YYYY-MM-DD.md` im jeweiligen Repo. Datenbasis für den Learning-Agent.

**Heartbeat-Issue** (gepinnt, pro Repo) wird nach jedem Run mit Timestamp + Status geupdated. Wenn Timestamp mehr als 2 Runs alt: sofort sichtbar dass der Agent nicht mehr läuft.

**Gestaffelter Ersteinstieg:** Woche 1 nur Critical, ab Woche 2 Critical + Important, ab Woche 4 alle Severities. `rollout_week` in `state.json` hochzählen.

### Datenfluss

```
CronJob (weekly, via Scheduled Tasks MCP)
  └── Orchestrator Agent (main)
       ├── Liest sites.json (URL + Repo-Mapping)
       ├── Site Agent: rafaelalex.de        → raaaf/portfolio-2025
       ├── Site Agent: events.rafaelalex.de → rafaelalex-dev/events
       └── Site Agent: zeit.rafaelalex.de   → rafaelalex-dev/zeit
            │
            ├── 1. state.json lesen (rollout_week, last_run, pending_findings)
            ├── 2. PSI API → Lighthouse JSON (mobile + desktop)
            │      sequenziell, 2s Delay; bei 429: Skip + Warning
            ├── 3. SSL-Check (via WebFetch HEAD request)
            ├── 4. Suppressions lesen (suppressions.json)
            ├── 5. Issues mit `suppress`-Label → suppressions.json updaten
            ├── 6. gh issue list --label audit (offene Issues lesen)
            ├── 7. Toleranz-Band: Findings mit pending_findings vergleichen
            │      Erst beim 2. Run in Folge → Issue erstellen
            ├── 8. gh issue create für bestätigte Findings (je nach rollout_week)
            ├── 9. Heartbeat-Issue updaten (Timestamp + Findings-Count)
            ├── 10. Audit-Log schreiben (.claude/audits/live-YYYY-MM-DD.md)
            └── 11. state.json updaten (rollout_week++, pending_findings, last_run)
                     → Learning-Agent liest Logs, gibt Retro zurück
```

### Schritte

1. **Neuen Skill `live-audit` erstellen** unter `.claude/skills/live-audit/`
   - `SKILL.md` (Trigger: `/live-audit`, Scheduled-Modus)
   - `agents/site-auditor.md` (PSI API, SSL, Issue-Management, Heartbeat, Rollout-Logik)
   - `agents/learning-agent.md` (Audit-Log-Analyse, Trend-Erkennung, Retro-Output)
   - `guidelines/thresholds.md` (Schwellenwerte + Fingerprint-IDs: `lcp-threshold-exceeded`, etc.)

2. **Konfig + State initialisieren** in jedem der drei Repos
   - `sites.json` im claude-skills Repo: `[{ "url": "rafaelalex.de", "github_repo": "raaaf/portfolio-2025", "psi_strategy": ["mobile", "desktop"] }, ...]`
   - `.claude/live-audit/suppressions.json` pro Repo: `[]`
   - `.claude/live-audit/state.json` pro Repo: `{ "rollout_week": 1, "last_run": null, "pending_findings": {} }`
   - Per `gh api` schreiben

3. **GitHub Labels anlegen** in allen drei Repos
   - `audit` (blau: 0075ca) — alle Audit-Issues
   - `suppress` (gelb: e4e669) — Issues die unterdrückt werden sollen
   - `critical` / `important` / `minor` (Severity-Labels)

4. **Heartbeat-Issue anlegen** in jedem Repo
   - Gepinnt, Label `audit`
   - Titel: `[live-audit] Pipeline Status`
   - Wird nach jedem Run geupdated, kein neues Issue

5. **Scheduled Task anlegen** via `mcp__scheduled-tasks`
   - Cadence: wöchentlich, Montag 08:00
   - Rollout-Woche in Task-Config hinterlegen (wird pro Run inkrementiert)

6. **Erster manueller Run** (Woche 1)
   - Nur Critical-Findings
   - Baseline-Log wird geschrieben

7. **Learning-Loop** läuft nach jedem Run als Subagent:
   - Liest alle `.claude/audits/live-*.md` im Repo
   - Gibt strukturierte Retro zurück (Orchestrator schreibt sie)
   - Schlägt Guideline-Änderungen vor (Thresholds, Fingerprints)

### Betroffene Repos / Dateien

- `.claude/skills/live-audit/` (neu, in claude-skills Repo)
- `sites.json` (neu, in claude-skills Repo)
- `.claude/live-audit/suppressions.json` (neu, in jedem der drei Repos)
- `.claude/live-audit/state.json` (neu, in jedem der drei Repos)
- `.claude/audits/live-YYYY-MM-DD.md` (pro Run, in jedem Repo)
- GitHub Labels `audit`, `suppress`, `critical`, `important`, `minor` in allen drei Repos
- Heartbeat-Issue (gepinnt) in allen drei Repos

### Audit-Dimensionen pro Run

| Dimension | Fingerprint-ID | Quelle | Critical | Important |
|---|---|---|---|---|
| LCP | `lcp-slow` | PSI mobile | > 4s | > 2.5s |
| CLS | `cls-high` | PSI mobile | > 0.25 | > 0.1 |
| FCP | `fcp-slow` | PSI mobile | — | > 1.8s |
| Performance Score | `perf-score-low` | PSI mobile + desktop | < 50 | < 80 |
| SEO Score | `seo-score-low` | PSI | — | < 90 (Minor) |
| Accessibility Score | `a11y-score-low` | PSI | < 70 | < 90 |
| SSL | `ssl-expiring` | WebFetch HEAD | Expired | < 14d |

### Issue-Format

```
Titel: [live-audit] {site} | {fingerprint-id}
Labels: audit, {severity}

Body:
## Impact
{1-2 Sätze: Wer ist betroffen? Mobile-Nutzer, SEO, Conversion?}

## Messwert
Aktuell: {Wert}
Threshold: {Critical/Important ab X}
Run: {Datum} | Strategie: {mobile/desktop}
URL: {Live-URL}

## Fix-Hinweis
{aus guidelines/thresholds.md}

## Next
- [ ] Fix this
- [ ] Add to backlog
- [ ] Ignore (label `suppress` → system will skip next run)
```

## Edge Cases

- **PSI 429**: Finding skippen, Warning in Heartbeat-Issue-Body notieren, Audit läuft weiter. Sequenzielle Calls mit 2s Delay reduzieren Wahrscheinlichkeit.
- **PSI-Varianz**: Messwerte schwanken ±10-15%. Toleranz-Band (2 aufeinanderfolgende Runs) in `pending_findings` gefiltert.
- **Site down**: WebFetch fehlschlägt → `site-unreachable` Critical Issue + kein weiterer Audit in diesem Run.
- **Erstes Repo ohne `.claude/`**: Skill legt Struktur an via `gh api`.
- **GitHub API Auth**: `GITHUB_TOKEN` Env-Var in Scheduled Task.
- **Scheduled Agent crasht**: Heartbeat-Timestamp veraltet → sichtbar ohne weiteres Alerting.
- **Rollout-Woche**: `rollout_week` in `state.json` pro Repo, wird nach jedem Run hochgezählt. Kein Zustand in Scheduled-Task-Config nötig.
