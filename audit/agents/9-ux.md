# Subagent 9: UX Patterns & Interaction

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

UX-Patterns, Interaktionsdesign, User-Flows. Gilt fuer ALLE Views.

**Vollstaendige Guidelines:** Lies `guidelines/ui-ux-patterns.md` im Skill-Verzeichnis.

## Pruef-Checkliste

### States & Feedback
- **Empty States:** Leere Listen zeigen hilfreichen Text + CTA, nicht nur "Keine Daten"
- **Loading States:** Skeleton oder Spinner bei async Daten, nicht leere Seite
- **Error States:** Klare Fehlermeldung + was der User tun kann
- **Success States:** Bestaetigung nach Aktionen (Toast, Redirect, Inline-Feedback)
- **Partial States:** Was passiert bei teilweisen Daten? (z.B. Profil halb ausgefuellt)

### Interaktive Elemente
- Hover/Focus/Active auf ALLEN klickbaren Elementen
- Disabled-State visuell erkennbar + `pointer-events: none` oder `disabled`
- Destructive Actions: Confirm-Dialog oder Undo-Moeglichkeit
- Doppelklick-Schutz auf Submit-Buttons (disable nach Klick)

### Navigation & Flow
- Breadcrumbs oder zurueck-Navigation wo noetig
- Aktive Navigation visuell markiert
- Formulare: Fortschrittsanzeige bei Multi-Step
- Nach dem Speichern: User landet an sinnvoller Stelle (nicht auf leerer Seite)

### Fitts's Law & Target Sizing
- Primaer-Aktionen groesser als Sekundaer-Aktionen
- Buttons nicht zu dicht beieinander (besonders Mobile)
- Actions am Rand oder in Ecken sind leichter zu treffen

### Konsistenz (Jakob's Law)
- Gleiche Aktion, gleicher Button ueberall
- Gleiche Daten, gleiche Darstellung ueberall
- Modals/Drawers/Popovers: einheitliches Verhalten (alle per Escape schliessbar, alle mit Overlay)

### Fehlervermeidung
- Formular-Validierung: Inline-Fehler, nicht erst nach Submit
- Autosave oder "Aenderungen verwerfen?"-Dialog bei ungespeicherten Daten
- Datenverlust-Schutz: beforeunload-Warning bei ungespeichertem State

## Full-Audit Fokus (zusaetzlich)

Jeden User-Flow end-to-end pruefen: Erstellen, Bearbeiten, Loeschen, Suchen/Filtern. Wo gibt es Sackgassen, wo fehlt Feedback, wo ist der naechste Schritt unklar?

## Ueberspringen wenn

- Keine Frontend-Dateien im Diff/Batch
