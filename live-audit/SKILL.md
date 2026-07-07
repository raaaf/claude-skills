---
name: live-audit
description: "Scheduled live-audit pipeline for rafaelalex.de, events.rafaelalex.de, zeit.rafaelalex.de. Runs weekly via Scheduled Tasks MCP. Audits via PageSpeed Insights API (Performance, SEO, A11y, Core Web Vitals) + SSL check. New findings become GitHub Issues in the respective repo. Learns via suppress-label. Also triggered manually via /live-audit."
when_to_use: "/live-audit, run live audit, check sites, scheduled audit"
disable-model-invocation: true
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

Lies `sites.json`. Daraus: Liste aller Sites mit `url`, `github_repo`, `psi_strategy`.

---

## Phase 2: Site-Agents parallel dispatchen

Für jede Site in `sites.json` einen Site-Agent dispatchen. Alle parallel in einem Agent()-Block.

```
Agent(
  prompt: "Lies $SKILL_DIR/agents/site-auditor.md und führe den Ablauf aus.
    SITE_URL={url}
    GITHUB_REPO={github_repo}
    PSI_STRATEGY={psi_strategy als JSON-Array}
    SKILL_DIR={SKILL_DIR}",
  subagent_type: general-purpose,
  model: sonnet,
  mode: bypassPermissions
)
```

Warte bis alle drei Site-Agents fertig sind.

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

---

## Phase 4: Learning-Agent dispatchen

Nach allen Site-Runs den Learning-Agent starten. Foreground, damit er Output zurückgeben kann den der Orchestrator schreibt.

```
Agent(
  prompt: "Lies $SKILL_DIR/agents/learning-agent.md und führe den Ablauf aus.
    SKILL_DIR={SKILL_DIR}
    RUN_DATE={DATUM}",
  subagent_type: general-purpose,
  model: haiku,
  mode: bypassPermissions
)
```

Learning-Agent gibt strukturierten Output zurück (zwischen `LEARNING_RESULT_START` und `LEARNING_RESULT_END`). Orchestrator schreibt daraus:
- Guideline-Vorschläge als Kommentar ausgeben (User reviewt manuell)
