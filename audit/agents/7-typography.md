# Subagent 7: Typography

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

Typographie nach professionellen Standards in CSS/SCSS, Templates und Translation-Dateien (`lang/`, `locales/`, `translations/`, `messages/`, `i18n/` — `.php`, `.json`, `.yaml`, `.po`, `.ts`).

**Vollstaendige Guidelines:** Lies `guidelines/typography.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln. Sprachregeln (Anfuehrungszeichen, geschuetzte Leerzeichen, Apostrophe) sind sprachspezifisch — Sprache aus Verzeichnis-/Dateiname ableiten (`de/`, `en/`, `fr.json`, `de.lproj/`, `values-de/`).

**Bei nativen Apps:** Translation-Files sind `Localizable.strings`/`.stringsdict` (iOS) bzw. `strings.xml` (Android) — typografische Zeichenregeln gelten dort genauso. Plus `guidelines/native-mobile.md` Section V: Dynamic Type / `sp`-Units statt fixer Groessen.

**Kontext-Hinweis:** Variablen-Platzhalter (`:name`, `{count}`, `%s`), HTML-Tags und technische Strings (URLs, Pfade) ignorieren — nur menschenlesbare Textfragmente pruefen.

## Pflicht-Verifikation VOR dem Flaggen

- **font-display-Findings:** NUR nach `grep -rn "@font-face"` im Projekt. Kein `@font-face` vorhanden (z.B. System-Font-Stack oder Font kommt aus einer Library mit eigenem Loading) → kein `font-display`-Finding.
- **Findings gegen neue Dependencies:** Vor einem Finding, das einer im Diff neu eingefuehrten Library ein Fehlverhalten unterstellt, zuerst deren Defaults pruefen (README/Docs in `node_modules/{pkg}/`). Viele Libraries erledigen das Unterstellte bereits per Default.

## Full-Audit Fokus (zusaetzlich)

Codebase-weite Inkonsistenzen: unterschiedliche font-size Definitionen, gemischte font-family Deklarationen, fehlende `clamp()` fuer responsive Text, fehlende `font-variant-numeric` in Tabellen, typografische Fehler in Translation-Dateien.

## Ueberspringen wenn

- Keine Frontend- und keine Translation-Dateien im Diff/Batch

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
