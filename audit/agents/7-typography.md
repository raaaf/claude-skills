# Subagent 7: Typography

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

Typographie-Audit nach professionellen Standards. Pruefe CSS/SCSS und Template-Dateien.

**Vollstaendige Guidelines:** Lies `guidelines/typography.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

## Kurzreferenz (Pruef-Checkliste)

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

## Ueberspringen wenn

- Keine Frontend-Dateien im Diff/Batch
