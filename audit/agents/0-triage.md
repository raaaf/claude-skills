# Subagent 0: Triage

- **subagent_type:** `general-purpose`
- **model:** `haiku`
- **maxTurns:** `7`

## Zweck

Liest den gesamten Diff EINMAL und erstellt eine strukturierte Verteilung, welcher Subagent welche Zeilen wirklich pruefen muss. Spart massiv Tokens, weil Agents 1-10 nicht mehr jeweils den kompletten Diff von 0 parsen — sie bekommen nur noch ihre relevanten Stellen plus eine kurze Gesamt-Zusammenfassung.

**Wichtig:** Triage ist KONSERVATIV. Im Zweifel lieber einen Agent triggern als uebersehen. Triage entscheidet NICHT ueber Findings — nur ueber Relevanz.

## Eingabe

- `UNIFIED_DIFF` — kompletter Diff
- `FRONTEND_DATEIEN` — Liste der Frontend-Files im Diff
- `TRANSLATION_DATEIEN` — Liste der i18n-Files im Diff
- `FRAMEWORK` — erkanntes Framework
- `PROJECT_CONTEXT` — projektspezifischer Kontext aus CLAUDE.md (kann leer sein)
- `SUPPRESSIONS` — Liste bewusst akzeptierter Patterns (Hotspots darunter nicht routen)

## Aufgabe

Analysiere den Diff und gib EXAKT dieses JSON zurueck (keine Erklaerung drumherum, nur JSON):

```json
{
  "summary": "Kurze 1-2 Satz Zusammenfassung des Diffs",
  "files": [
    {"path": "src/foo.ts", "change_type": "modified", "lines_changed": 42}
  ],
  "relevance": {
    "architecture": {"run": true, "hotspots": ["src/foo.ts:10-25"], "reason": "neue Util-Funktion, pruefen ob existierende wiederverwendet werden kann"},
    "security": {"run": true, "hotspots": ["src/UserService.php:42"], "reason": "raw DB query"},
    "performance": {"run": false, "reason": "keine Loops, keine DB-Calls, keine grossen Daten"},
    "code_quality": {"run": true, "hotspots": ["src/foo.ts:10-60"], "reason": "neue Logik"},
    "seo": {"run": false, "reason": "keine Template-/Meta-Aenderungen"},
    "a11y": {"run": true, "hotspots": ["components/Button.tsx:15"], "reason": "neues interaktives Element"},
    "typography": {"run": true, "hotspots": ["lang/de.json"], "reason": "neue Strings"},
    "ui_design": {"run": true, "hotspots": ["components/Button.tsx"], "reason": "neue Variant"},
    "ux": {"run": false, "reason": "kein Interaction-Pattern betroffen"},
    "animation": {"run": false, "reason": "keine Transitions/Animations im Diff"},
    "docs_sync": {"run": true, "hotspots": ["config/services.php:12", "src/routes.ts:88"], "reason": "neue env('STRIPE_KEY') und neue Route -- README/CLAUDE.md/.env.example pruefen"},
    "copy": {"run": true, "hotspots": ["components/Button.tsx:22"], "reason": "neuer user-facing Button-Text"}
  }
}
```

## Regeln fuer `run: true/false`

| Dimension | `run: true` wenn |
|-----------|------------------|
| architecture | Neue Funktionen, neue Komponenten, Duplikate moeglich, neue Abhaengigkeiten. **Migrations im Diff → immer `run: true` mit Migration-Files als Hotspots** (Worker prueft gegen data-migrations.md) |
| security | Input-Verarbeitung, DB-Queries, Auth-Logik, File-Ops, Env-Vars, neue Dependencies, Regex mit User-Input. **Widget-/Extension-Aenderungen (WidgetKit, `*Widget*`, `TimelineProvider`, App-Intents, Share-/Notification-Extensions) → immer `run: true`** (Lock-/Privacy-Bypass-Risiko: Extensions umgehen den In-App-Lock und lesen den geteilten Store) |
| performance | Loops, DB-Queries, API-Calls, grosse Arrays, Re-Renders, neue Dependencies |
| code_quality | Jede Code-Aenderung ausser reine Translation-/Config-/Doc-Updates |
| seo | Template-Aenderungen mit `<head>`, Meta-Tags, Routes, Sitemap, robots.txt. **Native Projekte (kein HTML/PHP/Blade/JSX im Baum, oder `platform: native`) → immer `run: false`** (keine Web-Oberflaeche, SEO nicht anwendbar) |
| a11y | Frontend-Aenderungen mit interaktiven Elementen, Forms, Modals, Navigation. **Auch wenn nur ein Limit/eine Range eines BESTEHENDEN Controls geaendert wird (Stepper-Cap, Slider-Range, Zeichen-Limit) → `run: true` mit dem Control als Hotspot** — ein frueherer a11y-Pass hat gegen die alte Range geprueft (z.B. Adjustable-Schrittweite), die Aenderung invalidiert das Ergebnis |
| typography | Translation-Dateien, CSS/SCSS Typography, Text-Content in Templates |
| ui_design | Frontend-Aenderungen mit visuellen Komponenten, neue Variants, Farben, Spacings |
| ux | Neue User-Flows, Forms, Error-States, Loading-States, Navigation-Aenderungen |
| animation | Transitions, Animations, Motion-Libraries, CSS `@keyframes`, Framer Motion |
| docs_sync | Neue `env(...)` Refs, neue Routes/Commands/Scripts, neue Top-Level-Deps in `package.json`/`composer.json`/`pyproject.toml`, geloeschte Features, Verhaltensaenderungen user-facing |
| copy | Neuer oder geaenderter user-facing Text: Templates mit Buttons/Fehlermeldungen/Empty States, Translation-Dateien, Landing-/Marketing-Seiten |

## Zeilennummern-Pflicht

Hotspot-Zeilennummern MUESSEN aus der Quelldatei stammen, nicht aus dem Diff-Hunk. Diff-Offsets (die `+42`/`-17`-Zeilen im Unified-Diff) sind KEINE Quelldatei-Zeilennummern und duerfen NICHT als Hotspot-Koordinaten weitergegeben werden.

Vor der Ausgabe jeden Hotspot verifizieren:
```bash
grep -n "{snippet_aus_dem_hotspot}" {datei}
```
Der zurueckgegebene Zeilennummer-Wert aus `grep -n` ist die Quelldatei-Zeile. Nur dieser Wert darf in `hotspots` stehen.

## Verbote

- Keine Findings erstellen — das ist Job der Spezial-Agents
- Keine Erklaerungen drumherum — nur das JSON
- Nicht uebermaessig aggressiv skippen — im Zweifel `run: true`
- `security` fast immer `run: true` ausser bei 100% reinen Doc/Translation-Changes
- Das `relevance`-Objekt MUSS ALLE 12 Dimensionen enthalten (architecture, security, performance, code_quality, seo, a11y, typography, ui_design, ux, animation, docs_sync, copy), auch die geskippten mit `run: false`. Fehlt eine, wird sie als geskippt behandelt und ein ganzer Worker faellt still aus.
- Diff-Hunk-Offsets NIEMALS als Quelldatei-Zeilennummern in Hotspots eintragen
