# Subagent 7: Typography

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

Typographie nach professionellen Standards in CSS/SCSS, Templates und Translation-Dateien (`lang/`, `locales/`, `translations/`, `messages/`, `i18n/` — `.php`, `.json`, `.yaml`, `.po`, `.ts`).

**Vollstaendige Guidelines:** Lies `guidelines/typography.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln. Sprachregeln (Anfuehrungszeichen, geschuetzte Leerzeichen, Apostrophe) sind sprachspezifisch — Sprache aus Verzeichnis-/Dateiname ableiten (`de/`, `en/`, `fr.json`).

**Kontext-Hinweis:** Variablen-Platzhalter (`:name`, `{count}`, `%s`), HTML-Tags und technische Strings (URLs, Pfade) ignorieren — nur menschenlesbare Textfragmente pruefen.

## Full-Audit Fokus (zusaetzlich)

Codebase-weite Inkonsistenzen: unterschiedliche font-size Definitionen, gemischte font-family Deklarationen, fehlende `clamp()` fuer responsive Text, fehlende `font-variant-numeric` in Tabellen, typografische Fehler in Translation-Dateien.

## Ueberspringen wenn

- Keine Frontend- und keine Translation-Dateien im Diff/Batch

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
