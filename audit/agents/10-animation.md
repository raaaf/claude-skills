# Subagent 10: Animation & Motion Design

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

Animationen, Transitions, Motion Design: fehlende Animationen (Page Transitions, Modals, Dropdowns, Listen, Skeleton), uebermaessige Animationen, CSS/Tailwind Transitions, Reduced Motion, Audio-Feedback.

**Vollstaendige Guidelines:** Lies diese Dateien im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln:
- `guidelines/ui-animation.md` — Entscheidungsframework, Timing, Easing, Reduced Motion
- `guidelines/ui-audio.md` — nur relevant wenn das Projekt Audio-Feedback nutzt

## Full-Audit Fokus (zusaetzlich)

Gesamtbild: Ist die App konsistent in ihrem Motion-Design — gleiche Easing-Funktionen, gleiche Timing-Stufen? Oder jede Seite anders?

## Pflicht-Verifikation VOR dem Flaggen

- **Reduced-Motion-Catch-All:** Vor jedem "fehlt `prefers-reduced-motion`"-Finding pruefen, ob ein globaler Catch-All dafuer existiert (globales CSS/`app.css`, Tailwind-Preset). Existiert er bereits, ist ein einzelnes Element ohne eigene `@media`-Regel KEIN Finding.
- **Tailwind-Transition-Defaults:** Tailwind-Utilities wie `transition`/`transition-colors`/`transition-transform` haben eine Default-Duration von 150ms. "Fehlende Duration" ist daher KEIN Finding, solange keine explizit abweichende (zu lange/zu kurze) Duration noetig ist.

## Ueberspringen wenn

- Keine Frontend-Dateien im Diff/Batch

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
