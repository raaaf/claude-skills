# Subagent 7: Typography

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

Typographie-Audit nach professionellen Standards. Pruefe CSS/SCSS, Template-Dateien und Translation-Dateien.

**Vollstaendige Guidelines:** Lies `guidelines/typography.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

## Kurzreferenz (Pruef-Checkliste)

### CSS/Templates

| Bereich | Erwartung |
|---------|-----------|
| Body font-size | 16-22px (min 15px), idealerweise `clamp()` |
| Line-height | 1.2-1.45 (120-145%) |
| Line-length | `max-width` ~36em auf Text-Containern |
| Font-Familie | Keine generischen Defaults (Arial, Inter, Roboto, Times) |
| Emphasis | Nie Bold + Italic gleichzeitig |
| ALL CAPS | Nur unter 1 Zeile, mit `letter-spacing: 0.05-0.12em` |
| Underlines | Nur auf Links |
| Paragraph-Spacing | Nie Einrueckung + Abstand gleichzeitig |
| Centered Text | Nur fuer kurze Headings/Labels |
| Dashes | Em-Dash, nicht `--` |
| Quotes | Typographische Quotes via CSS `quotes` |
| Kerning | `font-kerning: normal` |
| Tabular Nums | `font-variant-numeric: tabular-nums` in Tabellen |
| Table Borders | Minimale Borders, Whitespace statt Lines |
| Dark Mode Text | Dunkelgrau (#333) statt reines Schwarz (#000) erwaegen |
| Hyphenation | Keine Silbentrennung auf Headings |

### Translation-Dateien

Pruefe auch Translation-Dateien (`lang/`, `locales/`, `translations/`, `messages/`, `i18n/`) auf typografische Fehler.

**Dateitypen:** `*.php` (Laravel lang), `*.json` (i18n JSON), `*.yaml`/`*.yml` (Rails/Django), `*.po`/`*.pot` (gettext), `*.ts` (i18next)

| Bereich | Erwartung | Falsch | Richtig |
|---------|-----------|--------|---------|
| Gedankenstrich | Em-Dash `—`, nie `--` | `Willkommen -- wir freuen uns` | `Willkommen — wir freuen uns` |
| Anfuehrungszeichen (DE) | Typografisch `„..."` | `"Hallo Welt"` | `„Hallo Welt"` |
| Anfuehrungszeichen (EN) | Typografisch `\u201c...\u201d` | `"Hello World"` | `\u201cHello World\u201d` |
| Anfuehrungszeichen (FR) | Guillemets `\u00ab...\u00bb` | `"Bonjour"` | `\u00ab\u00a0Bonjour\u00a0\u00bb` |
| Ellipsis | Echtes Zeichen `\u2026` | `Laden...` | `Laden\u2026` |
| Geschuetzte Leerzeichen | Vor Einheiten, `%`, `\u20ac`, `:`, `?`, `!` (FR) | `50 %`, `10 EUR` | `50\u00a0%`, `10\u00a0EUR` |
| Doppelte Leerzeichen | Nie | `Hallo  Welt` | `Hallo Welt` |
| Konsistenz Satzzeichen | Entweder alle Werte mit Punkt am Ende oder keiner | `'save' => 'Speichern.', 'cancel' => 'Abbrechen'` | Einheitlich |
| Apostrophe | Typografisch `\u2019` | `it's`, `l'homme` | `it\u2019s`, `l\u2019homme` |
| Leerzeichen vor Doppelpunkt | Nur im Franzoesischen | `Achtung : wichtig` (DE) | `Achtung: wichtig` (DE) |

**Kontext-Hinweis:** Nicht alle Werte sind Prosa — Variablen-Platzhalter (`:name`, `{count}`, `%s`), HTML-Tags (`<br>`, `<a>`), und technische Strings (URLs, Dateipfade) ignorieren. Nur menschenlesbare Textfragmente pruefen.

**Spracherkennung:** Verzeichnisname oder Dateiname gibt die Sprache an (z.B. `de/`, `en/`, `fr.json`). Typografie-Regeln sind sprachspezifisch — deutsche Anfuehrungszeichen sind `„..."`, englische sind `\u201c...\u201d`, franzoesische sind Guillemets.

## Ueberspringen wenn

- Keine Frontend-Dateien und keine Translation-Dateien im Diff/Batch
