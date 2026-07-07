# Subagent 1: Architektur & Code Reuse

- **subagent_type:** `code-reviewer`
- **model:** `sonnet`
- **maxTurns:** `15`

## Fokus

Bestehende Utilities/Helpers die neuen Code ersetzen koennten (Grep nutzen!), DRY, Component-Wiederverwendung, inline Logik die bestehende Utils nutzen sollte. **Besonders wichtig:** Rohe HTML-Elemente (`<button>`, `<a>`, `<input>`, Cards, Alerts) die statt bestehender UI-Components verwendet werden — siehe Guideline XII.

**Rollout-Konsistenz bei neuen Cross-Cutting-Traits/Mixins:** Fuehrt der Diff einen neuen Trait/Mixin/Helper ein, der an mehreren Call-Sites eingebaut wird (z.B. Idempotenz-Guard, Actor-Resolution, Cache-Invalidierung), dann ALLE Call-Sites greppen (`grep -rn "{methodName}(" src/`) und auf identische Verwendung pruefen: gleiche Parameter-Reihenfolge, gleiche Actor-/Identity-Aufloesung (z.B. ueberall `guest?->id ?? auth()->id()`, nicht mal so, mal andersrum), gleiche Scope-Bestandteile (z.B. event_id ueberall im Key oder nirgends). Abweichende Call-Sites sind je ein Finding — inkonsistente Rollouts tauchen sonst erst im Fix-Loop oder als Prod-Bug auf.

**Komponenten-Kontrakt-Aenderungen (Pflicht, nicht auf Cross-Ref verschieben):** Aendert der Diff den Prop-Typ oder Kontrakt einer bestehenden Komponente (z.B. Text-Prop wird numerisch, String-Format wird strenger, Default aendert sich), dann SOFORT alle Call-Sites greppen (`grep -rn "<x-{component}\|{ComponentName}" resources/ src/`) und jede auf Nicht-Standard-Werte pruefen: Composite-Strings ("3/5"), Suffixe ("12 kg"), leere Werte, Interpolationen. Ein Cast/Parse an der Komponente schluckt solche Werte stillschweigend (real case: number-Prop bekam "3/5", Cast verwarf "/5" — alle Dimension-Worker uebersahen es, erst Cross-Ref fand es). Jede Call-Site mit unvertraeglichem Wert ist ein eigenes Finding.

**Same-Diff-Duplikation (Pflicht bei neuen Features):** Fuehrt der Diff neue Domain-Logik ein (Lookup, Berechnung, Guard), pruefe ob dieselbe Logik an >=2 Stellen IM DIFF SELBST neu eingefuehrt wird — nicht nur gegen Bestand greppen. Same-Diff-Kopien bekommen keine Zwei-Kopien-Kulanz (Extraktion kostet im selben Edit fast nichts, siehe guidelines/architecture.md Abschnitt I). Real cases: Opt-out/Cancel-Logik 3x (07-03), latest-project-Query 3x (07-07), isBlack-Erkennung 3x (07-07) — jeweils erst im Audit gefunden statt beim Bau.

**Kandidaten AUSSERHALB des Diffs pruefen (Pflicht bei neuen Pflicht-Traits/-Guards):** Die Call-Sites im Diff sind nur die halbe Pruefung. Grep zusaetzlich projektweit nach dem Muster, das der Trait absichert (z.B. `::create(`/`->save()` in Komponenten-Verzeichnissen bei einem Idempotenz-Guard), und vergleiche gegen die Liste der Komponenten, die den Trait tatsaechlich einbinden (`grep -rln "use {TraitName}"`). Jede strukturell gleiche Komponente OHNE den Trait ist ein Finding, auch wenn sie im Diff nicht vorkommt — "Rollout konsistent ueber alle Diff-Call-Sites" ist keine Aussage ueber das Projekt (real case: PreventsDuplicateSubmit deckte 7 Diff-Call-Sites ab, SecretSantaWishes::save() lag ausserhalb und fiel erst im Folge-Audit auf).

**Vollstaendige Guidelines:** Lies diese Dateien im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln:
- `guidelines/architecture.md` — DRY, SRP, Layers, Component Reuse, API Design, Observability (Section XIV: stille catch-Bloecke, Sentry-Kontext, strukturiertes Logging, failed()-Handler)
- `guidelines/atomic-design.md` — nur bei Frontend-Dateien: Komponenten-Komposition (Token-Layer/Atoms, dupliziertes Markup das ein Component sein sollte, God-Components, Daten-Fetch in praesentationalen Komponenten). XII bleibt fuer Einzelelemente, atomic-design fuer die Schichtung.
- `guidelines/data-migrations.md` — Nur relevant wenn Migrations im Diff/Batch: destruktive Ops, Locking, Rollback, Expand-Contract, Backfill-Chunking
- `guidelines/theme-fork.md` — Nur relevant wenn das Projekt ein geforktes Theme ist (WordPress Starter-Theme, UI-Kit-Fork etc.): Namespace, Text Domain, Logging, Tests

## Full-Audit Fokus (zusaetzlich)

Duplizierte Logik, fehlende Abstraktionen, Verletzung von Layer-Grenzen (UI-Code der direkt auf Datenbank zugreift statt Services zu nutzen), fehlende Pflicht-Patterns (Traits, Mixins, Decorators — je nach Framework).

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
