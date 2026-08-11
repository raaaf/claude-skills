---
name: live-audit
description: "Scheduled live-audit pipeline for rafaelalex.de, events.rafaelalex.de, zeit.rafaelalex.de. Runs weekly via Scheduled Tasks MCP. Audits via PageSpeed Insights API (Performance, SEO, A11y, Core Web Vitals) + SSL check. New findings become GitHub Issues in the respective repo. Learns via suppress-label. Also triggered manually via /live-audit."
when_to_use: "/live-audit, run live audit, check sites, scheduled audit"
# NO disable-model-invocation here: as of Claude Code v2.1.196 that flag also blocks
# scheduled-task invocations, and this skill runs weekly via the Scheduled Tasks MCP.
# Auto-trigger risk is acceptable: narrow when_to_use, idempotent audit with issue dedup.
model: sonnet
effort: medium
allowed-tools:
  - Agent
  - Bash
  - Read
  - Write
  - WebFetch
  - TodoWrite
---

# Live Audit Pipeline

**SOFORT AUSFÜHREN — direkt mit Phase 1 beginnen.**

SKILL_DIR ist `${CLAUDE_SKILL_DIR}` (Fallback: `$HOME/.claude/skills/live-audit`).

---

## Phase 1: Konfiguration laden

```bash
SKILL_DIR="${CLAUDE_SKILL_DIR:-$HOME/.claude/skills/live-audit}"
SITES_JSON="$SKILL_DIR/sites.json"
[ -f "$SITES_JSON" ] || { echo "FEHLER: sites.json nicht gefunden unter $SITES_JSON"; exit 1; }
cat "$SITES_JSON"
```

Lies `sites.json`. Daraus: Liste aller Sites mit `url`, `github_repo`, `psi_strategy` und optional `design_reference` (benannte Referenz-Site für das Design-Verdict in Schritt 5.5 des Site-Auditors; fehlt das Feld, entfällt der Schritt für diese Site).

---

## Phase 2: Site-Agents parallel dispatchen

Für jede Site in `sites.json` einen Site-Agent dispatchen. Alle parallel in einem Agent()-Block.

```
Agent(
  prompt: "Lies $SKILL_DIR/agents/site-auditor.md und führe den Ablauf aus.
    SITE_URL={url}
    GITHUB_REPO={github_repo}
    PSI_STRATEGY={psi_strategy als JSON-Array}
    DESIGN_REFERENCE={design_reference, oder leer wenn nicht gesetzt}
    SKILL_DIR={SKILL_DIR}",
  subagent_type: general-purpose,
  model: sonnet,
  run_in_background: false
)
```

Warte bis alle drei Site-Agents fertig sind. `run_in_background: false` ist hier Pflicht: seit
v2.1.198 laufen Subagents standardmaessig im Hintergrund und liefern ihr Ergebnis erst als
Completion-Notification in einem spaeteren Turn. Dieser Skill laeuft woechentlich unbeaufsichtigt
per Scheduled Task, es gibt also niemanden, der einen spaeteren Turn ausloest: die Phasen 3 und 4
(Run-Summary, Learning-Agent) wuerden auf leere Ergebnisse laufen.

---

## Phase 3: Run-Summary ausgeben

Sammle die Outputs aller drei Site-Agents. Ausgabe:

```
## Live Audit — {DATUM}

| Site | PSI mobile | PSI desktop | SSL | Neue Issues | Suppressed |
|---|---|---|---|---|---|
| rafaelalex.de | {perf}/100 | {perf}/100 | OK / WARN | {N} | {N} |
| events.rafaelalex.de | ... | ... | ... | ... | ... |
| zeit.rafaelalex.de | ... | ... | ... | ... | ... |

Gesamt: {N} neue Issues erstellt.
```

Hat mindestens ein Site-Agent eine `DESIGN_VERDICT:`-Zeile geliefert (nicht `n/a`), unter der Tabelle auflisten: `{site}: {verdict-Zeile}`.

---

## Phase 4: Learning-Agent dispatchen

Nach allen Site-Runs den Learning-Agent starten. `run_in_background: false` ist Pflicht: seit Claude Code v2.1.198 laufen Subagents standardmaessig im Hintergrund, und ein Hintergrund-Agent liefert sein Ergebnis erst als Completion-Notification in einem spaeteren Turn, der Orchestrator kann den Output dann nicht mehr parsen und schreiben.

```
Agent(
  prompt: "Lies $SKILL_DIR/agents/learning-agent.md und führe den Ablauf aus.
    SKILL_DIR={SKILL_DIR}
    RUN_DATE={DATUM}",
  subagent_type: general-purpose,
  model: haiku,
  run_in_background: false
)
```

Learning-Agent gibt strukturierten Output zurück (zwischen `LEARNING_RESULT_START` und `LEARNING_RESULT_END`). Orchestrator schreibt daraus:
- Guideline-Vorschläge als Kommentar ausgeben (User reviewt manuell)
