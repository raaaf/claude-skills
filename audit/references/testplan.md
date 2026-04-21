# Manueller Testplan — Generierung

Wenn visuelle Dateien im Diff sind (FRONTEND_DATEIEN oder VISUELL_RELEVANTE_DATEIEN nicht leer), generiere einen konkreten Testplan, den der User lokal durchgehen kann.

## Template

```markdown
## Manueller Testplan

**Branch:** {BRANCH}
**Geänderte visuelle Dateien:** {Liste}

### Schritte

1. [ ] **{Seitenname}** — {URL oder Route}
   - Prüfe: {was sich geändert hat, z.B. "neuer Button-Variant 'danger'"}
   - Desktop + Mobile testen
   - {Spezifischer Hinweis, z.B. "Dark Mode prüfen falls aktiv"}

2. [ ] **{Seitenname}** — {URL oder Route}
   - Prüfe: {konkrete Änderung}
   ...

### Worauf besonders achten
- {Edge Cases aus dem Diff, z.B. "Leerer Zustand wenn keine Items vorhanden"}
- {Responsive-Verhalten, z.B. "Tabelle bricht unter 768px auf Cards um"}
- {A11y-relevant, z.B. "Neue Buttons müssen per Tastatur erreichbar sein"}
```

## Regeln

- Nur Schritte für tatsächlich geänderte Stellen — kein generischer "prüfe alles"-Plan.
- URLs/Routes aus dem Framework ableiten:
  - Next.js: Dateipfad = URL
  - Laravel: `routes/web.php` konsultieren
  - Nuxt: `pages/` = URL
  - Inertia/Livewire: Controller-Routes prüfen
- Max. 10 Schritte — priorisiert nach Sichtbarkeit und Risiko.
- Rein textuell — keine externen Tools oder Server nötig.

## Wo der Testplan landet

1. Ins Audit-Log unter `## Manueller Testplan` schreiben.
2. Im Chat ausgeben (Teil der 3e-Ausgabe).
