# Subagent 8: UI Visual Design

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

Visuelle Design-Qualitaet und Konsistenz: Spacing-Skala, Komponenten-Konsistenz (Buttons, Inputs, Cards, Badges, Alerts), Farbe und Hierarchie, Shadows/Borders, Dark Mode.

**Vollstaendige Guidelines:** Lies `guidelines/ui-visual-design.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

**Atomic Design / Tokens:** Zusaetzlich `guidelines/atomic-design.md` — rohe Werte (Farbe/Spacing/Font/Radius/Shadow) statt vorhandener Design-Tokens, Varianten-Wildwuchs gleicher UI-Funktion, Komponenten-Konsistenz. Vor jedem Token-Finding den Token wirklich nachweisen (Pflicht-Verifikation in der Guideline).

**Bei nativen Apps** (`FRAMEWORK` = ios/android/react-native/flutter): zusaetzlich `guidelines/native-mobile.md` Section IV — HIG/Material-Konventionen, System-Komponenten vor Eigenbau, Safe Areas/Insets, Semantic Colors fuer Dark Mode.

## Pflicht-Verifikation VOR dem Flaggen

- **Kontrast-Findings:** NUR mit berechneter Kontrast-Ratio (beide Farbwerte aufloesen, Ratio nennen) UND geprueftem tatsaechlichem Hintergrund. Badges/Chips/Overlays liegen oft auf eigenem Hintergrund, nicht auf dem Seiten-Background — die umgebende Struktur lesen, bevor ein Farbpaar bewertet wird. Ohne Ratio + Hintergrund-Nachweis kein Finding.
- **Confidence-Deckel fuer Kontrast/Dark-Mode:** Kontrast- und Dark-Mode-Claims aus diesem Agent bekommen maximal `confidence: low` (Modell-Klasse dieses Agents entscheidet solche Claims nachweislich unzuverlaessig). Der Orchestrator verifiziert low-confidence gezielt nach — lieber ein nachgeprueftes Finding als ein falsches Critical.
- **Findings gegen neue Dependencies:** Vor einem Finding, das einer im Diff neu eingefuehrten Library ein Fehlverhalten unterstellt, zuerst deren Defaults pruefen (README/Docs in `node_modules/{pkg}/`, z.B. `respectMotionPreference`). Viele Libraries erledigen das Unterstellte bereits per Default.

## Full-Audit Fokus (zusaetzlich)

Gesamtbild: sieht die App wie aus einem Guss aus oder zusammengewuerfelt? Suche Views die visuell "anders" wirken als der Rest.

## Ueberspringen wenn

- Keine Frontend-Dateien im Diff/Batch

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
