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

## Offene Punkte: User-Entscheid → fixen / Issue / verwerfen

Issues sind die Ausnahme, nicht der Default. Offene Punkte sind nur noch echte Entscheidungs-Punkte — Fixbares wurde im Loop gefixt, Unbestaetigtes verworfen. **Minor-Findings bekommen NIE Issues** (stehen im Log).

**Schritt 1 — User-Entscheid (AskUserQuestion), PFLICHT wenn Offene Punkte existieren:**

Punkte kompakt auflisten (Dimension, datei:zeile, 1-Satz-Frage), dann pro Punkt oder gesammelt:
- **Jetzt entscheiden + fixen** — User gibt die Richtung vor (1 Satz), Fix-Agents setzen um, Fix-Verifier prueft
- **Als Issue vertagen** — nur diese werden Issues (Schritt 2)
- **Verwerfen** — verwerfen + ins Dismissed-Pattern-Store; wiederholtes Verwerfen → Learning-Agent schlaegt Suppression vor

**Schritt 2 — Issues NUR fuer explizit Vertagtes:**

1. **Precheck:** `gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com` — sonst bleiben vertagte Punkte im Log.
2. **Dedup pro Finding:** `gh issue list --state open --search "[audit] {Dimension} {datei}" --json number` — bereits existierendes Issue → skip. Zusaetzlich gegen `OPEN_PRS` (Phase 0.3) pruefen — adressiert ein offener PR dieselbe Stelle → skip + Log-Hinweis.
3. **Erstellen:**
   ```bash
   gh issue create \
     --title "[audit] [{Dimension}] {datei}:{zeile} — {kurzbeschreibung}" \
     --body "{Details}

   **Entscheidung noetig:** {die konkrete Frage}

   **Quelle:** {LOGFILE}" \
     --label "audit-finding"
   ```
   Label via `gh label create audit-finding --color FBCA04` bei Bedarf anlegen.
4. **Ausgabe:** `{N} gefixt, {M} vertagt als Issues: {urls}, {K} verworfen`.
5. `gh`-Fehler blockieren NICHT — kurz warnen und weiter.
6. CI/Headless (non-interactive): Schritt 1 ueberspringen, alle Offenen Punkte direkt als Issues vertagen.
