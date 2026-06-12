# Post-Loop: Changelog, Linter, Tests, Testplan, Issues, Log-Display (Phase 3 Detail)

Nach Loop-Ende, vor Pre-Push. Reihenfolge: 3a → 3b → 3c → 3d → 3e → 3f.

## 3a. Changelog/Release-Notes

Pruefe selbst ob user-facing Changes einen Changelog-Eintrag brauchen. Kandidaten-Dateien: `CHANGELOG.md`, `changelog.md`, `release-notes/next.md`, `resources/changelog.md`, `CHANGES.md`.

Ignorieren: reine Test-Aenderungen, interne Services ohne UI, Refactorings ohne Verhaltensaenderung, Config, Migrations ohne neue Features.

Existiert kein passender Eintrag → Eintrag draften, Format orientiert sich am bestehenden Stil der Datei, chronologisch oben einfuegen.

## 3b. Linter & Static Analysis · 3c. Test-Suite

Erkennungstabellen und Befehle stehen in `linters-and-tests.md`. Reihenfolge: Formatter → Linter → Static Analysis → Tests. Bei Failures: fixen, erneut laufen lassen. Unfixbare Test-Failures als Critical aufnehmen.

**Tests nur diff-scoped:** Nur Tests laufen lassen, die von den geaenderten Dateien betroffen sind (Mapping siehe `linters-and-tests.md`). NIEMALS `composer test` / `npm test` in `/audit` — die volle Suite laeuft in CI. Dieser Skill darf die Laufzeit nicht durch eine 2000+ Test-Suite explodieren lassen.

## 3d. Manueller Testplan erstellen

Wenn visuelle Dateien im Diff sind (FRONTEND_DATEIEN oder VISUELL_RELEVANTE_DATEIEN nicht leer), Testplan nach `testplan.md` generieren: Template, URL-Ableitung pro Framework, Regeln. Max 10 Schritte, nur fuer tatsaechlich geaenderte Stellen. Ins Audit-Log unter `## Manueller Testplan` schreiben UND im Chat ausgeben.

## 3e. Audit-Log im Chat anzeigen (PFLICHT — nach Testplan)

Nach Abschluss von 3a-3d den kompletten Inhalt des Log-Files (inkl. Testplan) via Read-Tool laden und als Markdown-Codeblock im Chat ausgeben:

```
Audit-Log: {LOGFILE}

---
{Inhalt des Log-Files}
---
```

So hat der User das vollstaendige Ergebnis inkl. Testplan auf einen Blick.

## 3f. Offene Punkte: User-Entscheid → fixen / Issue / verwerfen

**Ziel:** Issues sind die Ausnahme, nicht der Default. Offene Punkte sind nur noch echte Entscheidungs-Punkte (Architektur-Tradeoffs, Verhaltens-Aenderungen) — alles Fixbare wurde im Loop gefixt, Unbestaetigtes verworfen. Minor-Findings bekommen NIE Issues (sie stehen im Audit-Log und tauchen beim naechsten Audit wieder auf, falls relevant).

**Wenn `## Offene Punkte` leer ist:** 3f komplett ueberspringen, `3f: n/a (keine offenen Punkte)` loggen.

**Schritt 1 — User-Entscheid via AskUserQuestion:**

Alle Offenen Punkte kompakt auflisten (Dimension, datei:zeile, 1-Satz-Frage). Dann fragen — bei <= 4 Punkten eine Frage pro Punkt (multiSelect-faehig buendeln), bei mehr eine Sammel-Frage mit Optionen:
- **Jetzt entscheiden + fixen** — User gibt pro Punkt die Richtung vor (1 Satz reicht), Orchestrator dispatcht Fix-Agents mit der Entscheidung als Kontext. Fix-Verifier prueft wie immer.
- **Als Issue vertagen** — nur diese Punkte werden Issues (Schritt 2).
- **Verwerfen** — Punkt wird verworfen + `patterns-store.sh dismissed`; bei wiederholtem Verwerfen schlaegt der Learning-Agent eine Suppression vor.

**Schritt 2 — Issues NUR fuer explizit Vertagtes:**

Precheck:
```bash
gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com || echo "kein gh/github — vertagte Punkte bleiben im Log"
```

1. **Dedup:** `gh issue list --state open --search "[audit] {kurzfingerprint}" --json number,title` — existiert schon ein Issue mit diesem `[Dimension] datei:zeile`, **skip**.
2. **Issue erstellen:**
   ```bash
   gh issue create \
     --title "[audit] [{Dimension}] {datei}:{zeile} — {kurzbeschreibung}" \
     --body "{Finding-Beschreibung}

   **Entscheidung noetig:** {die konkrete Frage an den User}

   **Quelle:** \`{LOGFILE}\` (Audit vom {DATUM}, Branch \`{BRANCH}\`, HEAD \`{SHORT_SHA}\`)" \
     --label "audit-finding"
   ```
3. Label fehlt im Repo → `gh label create audit-finding --color FBCA04`, dann erneut.
4. Ausgabe: `{N} Punkte gefixt, {M} vertagt als Issues: {urls}, {K} verworfen`.

**Wichtig:** Fehler blockieren den Push NICHT. Bei `gh`-Fehler kurz melden und weiter mit Phase 4. In CI/Headless (`AUDIT_SKIP_LEARNING_CHECK=1` als Proxy fuer non-interactive): Schritt 1 ueberspringen, alle Offenen Punkte direkt als Issues vertagen (altes Verhalten).
