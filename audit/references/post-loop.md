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

## 3f. Offene Punkte + Minor als GitHub-Issues tracken

**Ziel:** Keine Finding geht verloren. Alles was nicht im Loop gefixt wurde, landet als Issue — dokumentiert, durchsuchbar, nicht im Audit-Log vergraben.

**Precheck:**
```bash
gh repo view >/dev/null 2>&1 && git remote get-url origin 2>/dev/null | grep -q github.com || echo "kein gh/github — Issue-Erstellung ueberspringen"
```

**Scope:** Fuer jeden Eintrag unter `## Offene Punkte` UND jeden verifizierten Minor-Finding der nicht gefixt wurde (Log aus Schritt E/Fix-Phase):

1. **Dedup:** `gh issue list --state open --search "[audit] {kurzfingerprint}" --json number,title` — wenn schon ein Issue mit diesem `[Dimension] datei:zeile` existiert, **skip** (keine Dublette erzeugen).
2. **Issue erstellen:**
   ```bash
   gh issue create \
     --title "[audit] [{Dimension}] {datei}:{zeile} — {kurzbeschreibung}" \
     --body "{Finding-Beschreibung}

   **Warum nicht im Audit gefixt:** {Begruendung: Minor / groesserer Refactor / architektonische Entscheidung}

   **Quelle:** \`{LOGFILE}\` (Audit vom {DATUM}, Branch \`{BRANCH}\`, HEAD \`{SHORT_SHA}\`)" \
     --label "audit-finding"
   ```
3. Wenn `--label audit-finding` fehlschlaegt (Label existiert noch nicht im Repo): Label via `gh label create audit-finding --color FBCA04` anlegen, dann Issue nochmal.
4. Issue-URLs sammeln und am Ende ausgeben: `X Issues erstellt: {urls}`.

**Wichtig:** Fehler blockieren den Push NICHT. Bei `gh`-Fehler (offline, auth expired, etc.) einfach kurz melden `WARN: Issue-Erstellung uebersprungen, siehe Offene Punkte im Log` und weiter mit Phase 4.

## Offene Punkte — sofort umsetzen? (optional)

Nach Issue-Erstellung User via AskUserQuestion fragen: "Issues erstellt. Jetzt einzelne umsetzen / alle spaeter angehen?". Bei "einzeln umsetzen": User entscheidet welches Issue pro PR.
