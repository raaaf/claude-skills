# Subagent 9: UX Patterns & Interaction

- **subagent_type:** `ui-ux-reviewer`
- **model:** `sonnet`
- **maxTurns:** `10`

## Fokus

UX-Patterns und Interaktionsdesign: States (Empty/Loading/Error/Success), interaktive Elemente (Hover/Focus/Disabled), Navigation und Flow, Fitts's Law, Konsistenz (Jakob's Law), Fehlervermeidung.

**Vollstaendige Guidelines:** Lies `guidelines/ui-ux-patterns.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

**Bei nativen Apps** (`FRAMEWORK` = ios/android/react-native/flutter): zusaetzlich `guidelines/native-mobile.md` Section IV — Back-Navigation (iOS-Swipe, Android Predictive Back), Plattform-Idiome, Haptics.

## Full-Audit Fokus (zusaetzlich)

Jeden User-Flow end-to-end pruefen: Erstellen, Bearbeiten, Loeschen, Suchen/Filtern. Wo gibt es Sackgassen, wo fehlt Feedback, wo ist der naechste Schritt unklar?

## Ueberspringen wenn

- Keine Frontend-Dateien im Diff/Batch

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
