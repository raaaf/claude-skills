# Subagent 10: Animation & Motion Design

- **subagent_type:** `ui-ux-reviewer`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

Animationen, Transitions, Motion Design. Gilt fuer ALLE Views.

**Vollstaendige Guidelines:** Lies `guidelines/ui-animation.md` im Skill-Verzeichnis — fokussiere auf das Entscheidungsframework und die Timing-Regeln, ueberspringe die tiefe Theorie.

Zusaetzlich: `guidelines/ui-audio.md` — nur die Checkliste, nicht die Synthese-Details.

## Pruef-Checkliste

### Fehlende Animationen
- **Page Transitions:** Gibt es Uebergaenge bei Seitenwechsel oder ist es ein harter Cut?
- **Modals/Drawers:** Fade-in/Slide-in vorhanden?
- **Dropdowns/Popovers:** Smooth open/close oder abrupt?
- **Listen-Aenderungen:** Items hinzufuegen/entfernen mit Animation oder ploetzlich da/weg?
- **Tab-Wechsel:** Content-Transition oder harter Swap?
- **Skeleton/Loading:** Shimmer-Animation auf Skeleton-Elementen?

### Uebermaessige Animationen
- Dauer > 300ms bei UI-Elementen? → Zu lang, wirkt traege
- Dauer < 100ms? → Zu kurz, kaum wahrnehmbar
- Optimaler Bereich: 150-250ms fuer Micro-Interactions, 250-400ms fuer Layout-Transitions
- Bounce/Elastic-Effekte an unpassenden Stellen (z.B. auf Tabellen, Formularen)?

### CSS/Tailwind Transitions
- `transition-*` Properties vorhanden wo Hover/Focus-States definiert sind?
- Konsistente Easing-Functions (nicht mix aus linear, ease, ease-in-out, cubic-bezier)
- `will-change` nur wo noetig (Performance)
- Transform statt Layout-Properties animieren (translate statt top/left)

### Reduced Motion
- `@media (prefers-reduced-motion: reduce)` vorhanden?
- Animationen werden reduziert oder durch Fade ersetzt, nicht komplett entfernt
- Kein Auto-Play von Animationen die nicht stoppbar sind

### Audio-Feedback (falls vorhanden)
- Sounds haben visuelle Aequivalente
- Volume-Control vorhanden
- Keine ploetzlichen lauten Sounds
- Sounds sind optional (mute-fähig)

## Full-Audit Fokus (zusaetzlich)

Gesamtbild: Ist die App konsistent in ihrem Motion-Design? Gleiche Easing-Funktionen, gleiche Timing-Stufen? Oder jede Seite anders?

## Ueberspringen wenn

- Keine Frontend-Dateien im Diff/Batch
