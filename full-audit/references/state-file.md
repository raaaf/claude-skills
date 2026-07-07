# Full-Audit State-Datei: Format, Resume, Loop-Modus

Persistenter Goal-Loop-Zustand fuer /full-audit nach dem /feature-audit-Muster. Der komplette Loop-Fortschritt (Batches, Runden, Findings-Zaehler, Post-Phasen) lebt in einer Datei auf Disk, nicht im Konversationskontext — er ueberlebt Session-Tod, Kontext-Kompaktierung und Unterbrechungen.

## Dateien

| Datei | Inhalt |
|---|---|
| `.claude/audits/full-audit-state.md` | Matrix + Header (die State-Datei) |
| `.claude/audits/full-audit-batches/batch-NN.txt` | Dateiliste je Batch, repo-root-relativ, eine pro Zeile |

Beides lokale Lauf-Infrastruktur (steht in `.gitignore`, wie `cache.json`). Beide Pfade sind erlaubte Orchestrator-Edits.

## Format

```
# Full-Audit State — v1
mode: BATCHED
effort: xhigh
dimensions: architecture,security,performance,code_quality
batch-dir: .claude/audits/full-audit-batches
post-phases: cross_ref=pending log=pending issues=pending
started: 2026-07-07

| ID | Verzeichnis | Dateien | Runden | C | I | M | Status | HEAD |
|---|---|---|---|---|---|---|---|---|
| 01 | app/Services | 34 | 2/3 | 1 | 3 | 5 | clean | a1b2c3d |
| 02 | resources/views | 38 | 1/3 | 0 | 0 | 0 | running | - |
| 03 | app/Models | 22 | 0/3 | 0 | 0 | 0 | pending | - |

## Blocked / Needs review
- none
```

Regeln:

- **Statuswerte:** `pending` (noch nicht auditiert) | `running` (Batch in Arbeit) | `clean` (auditiert + gefixt) | `blocked` (NO_CONVERGENCE oder Entscheidungs-Punkte).
- **Runden** = `verbraucht/max` (z.B. `2/3`). **C/I/M** = kumulierte Findings des Batches ueber alle Runden. **HEAD** = Kurz-SHA bei Batch-Abschluss (`git rev-parse --short HEAD`), sonst `-`.
- **Header-Keys maschinenlesbar** (`key: value`, eine Zeile): `mode`, `effort`, `dimensions`, `batch-dir`, `post-phases`, `started`. Resume liest Modus/Effort/Dimensionen von hier statt den User erneut zu fragen.
- **Zellen duerfen kein rohes `|` enthalten** (bricht den awk-Parser) — als `\|` escapen oder umformulieren.
- **SINGLE-Modus** = eine Batch-Zeile (ID `01`, Verzeichnis `.`).
- **Blocked-Sektion:** ein Checkbox-Bullet pro blockiertem Punkt (`- [ ] [ID] Kurzbeschreibung`). `- none` zaehlt nicht. Blocked blockt die Completion NICHT, muss aber hier UND im Audit-Log stehen.

## Scripts (bash 3.2, deterministisch — Bash entscheidet, nicht das LLM)

**`status-line.sh <STATE_FILE>`** emittiert genau eine Zeile:

```
FULL_AUDIT_STATUS batches_total=3 pending=1 running=1 clean=1 blocked=0 rounds_used=3 critical=1 important=3 minor=5 blocked_items=1 post_phases=pending
```

`post_phases=done` erst wenn ALLE Keys der `post-phases:`-Zeile `=done` sind. Fehlende Datei → Null-Zeile. Der Orchestrator entscheidet Completion NUR aus der Zeile des aktuellen Turns, nie aus dem Gedaechtnis.

**`resume-check.sh <STATE_FILE>`** prueft jede `clean`-Zeile: Batch-Liste gegen alles, was sich seit dem vermerkten HEAD geaendert hat (`git diff <head>..HEAD` + Working-Tree via `git status --porcelain`). Output pro clean-Batch: `BATCH_DIRTY id=NN files=K` oder `BATCH_CLEAN id=NN`. Fehlende Batch-Liste oder unaufloesbarer HEAD → `BATCH_DIRTY files=unknown` (fail toward re-audit). Das Script liest nur — Zeilen auf `pending` zuruecksetzen macht der Orchestrator.

## Resume-Semantik

Existiert die State-Datei beim Aufruf von /full-audit:

1. `resume-check.sh` laufen lassen. Jeden `BATCH_DIRTY` auf `pending` zuruecksetzen (Runden `0/{max}`, C/I/M nullen, HEAD `-`).
2. `running`-Zeilen (Session mitten im Batch gestorben) auf `pending` zuruecksetzen — halbe Batches werden neu auditiert, nie fortgesetzt.
3. Modus/Effort/Dimensionen aus dem Header uebernehmen, Phasen 0.3-1.5 skippen, direkt Phase 2 ab dem ersten `pending`-Batch.
4. `clean`-Batches werden NIE zur Bestaetigung re-auditiert.

**Nicht-Determinismus (wichtig):** Audit-Findings sind LLM-Urteile, keine reproduzierbaren Tests. `clean` heisst "in diesem Lauf auditiert und gefixt", nicht "re-verifizierbar gruen" — ein erneuter Worker-Lauf auf unveraendertem Code kann andere Findings produzieren. Deshalb gilt: kein Re-Audit von clean-Batches, Re-Audit ausschliesslich ueber den deterministischen Dirty-Check. (Genau hierin unterscheidet sich der Loop von /feature-audit, dessen Zeilen an echte Tests gebunden sind.)

Frisch abschliessen und neu starten: State-Datei + `full-audit-batches/` loeschen, /full-audit erneut aufrufen.

## Loop-Modus (optional)

Default bleibt single-session: alle Batches in einem Lauf, die State-Datei ist dann nur Crash-Versicherung.

Fuer sehr grosse Codebases turn-weise via `/loop /full-audit`:

- `FULL_AUDIT_BATCHES_PER_TURN=N` (Default ohne Loop: alle) — nach N Batches endet der Turn mit der `FULL_AUDIT_STATUS`-Zeile (verbatim als letzte Zeile), /loop feuert den naechsten.
- **Stop-Bedingungen** (feature-audit-Muster): derselbe Batch 3 Turns in Folge `blocked` ohne Fortschritt → Batch blocked lassen, weiter mit dem naechsten; 50 Turns gesamt → Abbruch mit Digest.
- KEIN neuer Stop-Hook (Hook-Safety-Gotcha: `audit-loop.sh` gehoert /audit; die Zeile heisst deshalb `FULL_AUDIT_STATUS`, niemals `AUDIT_STATUS`).

## Future Option (bewusst NICHT gebaut)

Datei-genaues Caching via `audit/bin/cache-check.sh`/`cache-write.sh` (sha256 pro Datei): Fix-Agents invalidieren die Hashes waehrend des Laufs permanent, Resume-Granularitaet ist der Batch. Falls Batch-Granularitaet je zu grob wird, hier ansetzen.
