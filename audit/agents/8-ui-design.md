# Subagent 8: UI Visual Design

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

Visuelle Design-Qualitaet und Konsistenz. Gilt fuer ALLE Views.

**Vollstaendige Guidelines:** Lies `guidelines/ui-visual-design.md` im Skill-Verzeichnis.

## Pruef-Checkliste

### Spacing & Layout
- Einheitliche Spacing-Skala (4/8/12/16/24/32/48 oder Tailwind)
- Konsistente Padding/Margins innerhalb gleicher Component-Typen
- Max-width auf Text-Containern (~65-75ch)
- Kein visueller Bruch zwischen Sektionen

### Komponenten-Konsistenz
- Buttons: einheitliche Varianten (Primary, Secondary, Danger, Ghost)
- Inputs: gleiche Hoehe, Border-Radius, Padding ueberall
- Cards: gleiche Shadow-Tiefe, Padding, Rundung
- Badges/Tags: konsistente Groesse und Farben
- Alerts/Toasts: einheitliches Design

### Farbe & Hierarchie
- Primaer-Aktion visuell staerker als Sekundaer
- Max 2-3 Akzentfarben pro View
- Destructive Actions visuell anders (Danger-Farbe, Confirm-Dialog)
- Heading-Groessen bilden klare Hierarchie
- Konsistente Farbpalette ueber die gesamte App

### Shadows & Borders
- Konsistente Shadow-Stufen (nicht 10 verschiedene Box-Shadows)
- Border-Radius einheitlich (nicht mix aus 4px, 8px, 12px, 16px)
- Borders: duenne, subtile Trennlinien — nicht dick und dominant

### Dark Mode (falls vorhanden)
- Kontrast ausreichend
- Off-white auf dunkelgrau statt weiss auf schwarz
- Bilder/Icons passen sich an

## Full-Audit Fokus (zusaetzlich)

Gesamtbild: sieht die App wie aus einem Guss aus oder wie zusammengewuerfelt? Suche Views die visuell "anders" aussehen.

## Ueberspringen wenn

- Keine Frontend-Dateien im Diff/Batch
