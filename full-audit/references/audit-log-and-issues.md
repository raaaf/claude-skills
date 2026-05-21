# Audit-Log + GitHub-Issues (Phase 4 Detail)

Detail fuer Phase 4 (Audit-Log schreiben und GitHub-Issues anlegen).

## Audit-Log-Format

```bash
AUDIT_DIR="$(git rev-parse --show-toplevel)/.claude/audits"
mkdir -p "$AUDIT_DIR"
LOGFILE="$AUDIT_DIR/$(date +%Y-%m-%d_%H%M%S)-full-audit.md"
```

Format:

```markdown
# Full Audit — {DATUM}

## Scope
- Dimensionen: {N}/11 — {SELECTED_DIMENSIONS}
- Modus: SINGLE | BATCHED ({N} Batches)
- Backend-Dateien: X
- Frontend-Dateien: Y
- Runden gesamt: Z

## Ergebnis
- Critical gefunden/gefixt: A/B
- Important gefunden/gefixt: C/D
- Minor gefunden/gefixt: E/F

## Gefixte Issues
- [Security] app/Foo.php:42 — XSS via {!! !!} → durch {{ }} ersetzt

## Manueller Testplan
- (Testplan-Schritte, falls visuelle Dateien vorhanden)

## Offene Punkte
- [Code Quality] app/Baz.php — Refactoring noetig (nicht auto-fixbar)

## Sauber
Performance, SEO
```

## Audit-Log im Chat anzeigen (PFLICHT)

Den kompletten Inhalt des Log-Files (inkl. Testplan) via Read-Tool laden und als Markdown-Codeblock im Chat ausgeben:

```
Audit-Log: {LOGFILE}

---
{Inhalt des Log-Files}
---
```

## Offene Punkte + Minor als GitHub-Issues tracken

PFLICHT bei `gh` + GitHub-Repo. Damit kein Finding verloren geht.

Fuer **jeden Offenen Punkt UND jeden verifizierten Minor-Finding der nicht gefixt wurde** ein GitHub-Issue anlegen:

1. **Precheck:** `gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com` — sonst skip.

2. **Dedup pro Finding:** `gh issue list --state open --search "[audit] {Dimension} {datei}" --json number` — bereits existierendes Issue → skip.

3. **Erstellen:**
   ```bash
   gh issue create \
     --title "[audit] [{Dimension}] {datei}:{zeile} — {kurzbeschreibung}" \
     --body "{Details}

   **Warum nicht gefixt:** {Begruendung}

   **Quelle:** {LOGFILE}" \
     --label "audit-finding"
   ```
   Label via `gh label create audit-finding --color FBCA04` bei Bedarf anlegen.

4. **Am Ende Issue-URLs ausgeben.**

5. `gh`-Fehler (offline, auth) blockieren NICHT — nur kurz warnen und weiter.

## Offene Punkte umsetzen

Wenn `## Offene Punkte` Eintraege enthaelt, User via AskUserQuestion fragen:
- **Ja, alle** — alle jetzt umsetzen
- **Einzeln entscheiden** — pro Punkt bestaetigen
- **Nein, spaeter** — im Log belassen (Issues sind ja gerade entstanden)
