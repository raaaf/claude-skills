# Messung: full-audit im events-app nach allen Optimierungen (2026-04-24)

**Session:** `d487f451-c072-4008-bfec-4cb48414dd7c`
**Projekt:** events-app
**Ergebnis:** 32 Batches **komplett** durchgelaufen, 62 Dateien geändert, PHPStan + Pint clean
**Skill-Version:** Nach Commits `5062ab6` (effort), `9e65590` (fix-agents + round-cap + skill-trim), `892b36f` (gh issues)
**Env:** `ENABLE_PROMPT_CACHING_1H=1` aktiv

## Vergleich mit Baseline

Die Baseline (`f4a3c839` vom 20.04.) wurde mid-Batch-3 abgebrochen, der neue Lauf ist über 32 Batches komplett durchgelaufen. Absolute Kosten sind deshalb nicht direkt vergleichbar — die Normalisierung auf Kosten/Batch ist der faire Maßstab.

| Metrik | Baseline (~2,5 von 3 Batches) | Neu (32 Batches) | Δ |
|--------|-------------------------------|-------------------|---|
| Total Tool Calls | 111 | 185 | — |
| **Edit (Orchestrator)** | **30** | **4** | **−87%** |
| Agent-Dispatches | 12 | 55 | — |
| Output Tokens | 186.129 | 444.886 | — |
| Cache Read Tokens | 19.820.644 | 51.971.697 | — |
| Cost absolut | $18,35 | $48,11 | — |
| **Cost pro Batch** | **~$7,34** | **~$1,50** | **−80%** |

## Verdict

**🟢 GREEN: Fix-Agent-Enforcement wirkt.** Orchestrator macht nur noch 4 Edits — und die sind Audit-Log / Context-Meta, keine Code-Edits. Das ist genau das designte Verhalten.

## Welche Optimierungen wirken

Die Kosten-pro-Batch-Reduktion von ~80% entsteht durch vier kombinierte Hebel:

1. **Fix-Agent-Enforcement** (Commit `9e65590`): Alle Code-Edits laufen über Haiku-Fix-Subagents statt Opus-Orchestrator. Haiku ist ~5× billiger bei Output.
2. **Effort `xhigh → high`** (Commit `5062ab6`): Weniger Adaptive-Thinking-Overhead auf dem Orchestrator ohne Qualitätsverlust für Koordinations-Arbeit.
3. **Runden-Cap 2** (Commit `9e65590`): Verhindert Worst-Case-Kosten bei zirkulären Findings. In diesem Lauf nicht aktiv geworden (Convergence früh).
4. **`ENABLE_PROMPT_CACHING_1H=1`**: Cache-TTL 12× länger, Cache-Create-Tokens fallen seltener an.

Die Agent-Dispatch-Liste zeigt das neue Muster:
```
Batch 1 Architecture (inherit)
Batch 1 Security (inherit)
Batch 1 Performance (inherit)
Batch 1 Code Quality (inherit)
Fix: Telescope hideRequestParameters (haiku)   <-- Haiku
Fix: buildFullName divergence (haiku)          <-- Haiku
Fix: Sentry recursive scrub (haiku)            <-- Haiku
Fix: Money redundant nullable (haiku)          <-- Haiku
Fix: AppServiceProvider trailing comment (haiku) <-- Haiku
Batch 2 Architecture (inherit)
...
```

4 Dimension-Agents auf Sonnet, dann mehrere Haiku-Fix-Agents pro Batch. Der Skill folgt dem Design exakt.

## Nächste Schritte

- **PreToolUse-Hook für Edit-Guard: nicht nötig.** Prompt-Level-Regel reicht aus.
- **Weitere Hebel bei Bedarf** (aber $1,50/Batch ist bereits gesund):
  - Diff-Fallback optional machen (Prompt-Template-Eingriff, derzeit nicht nötig)
  - Skill-Body weiter verschlanken (aktuell 492 Zeilen, unter 500 OK)
- **Monitoring:** Wenn zukünftige full-audits wieder über $2/Batch klettern, erneut messen und GREEN/YELLOW/RED-Check laufen lassen.

## Reproduktion

```bash
python3 measurements/analyze-session.py \
  ~/.claude/projects/-Users-rafael-Local-Sites-events-app/d487f451-c072-4008-bfec-4cb48414dd7c.jsonl \
  --baseline ~/.claude/projects/-Users-rafael-Local-Sites-events-app/f4a3c839-55ec-4236-81ac-55c8604b9122.jsonl
```
