# Subagent 3: Performance & Efficiency

- **subagent_type:** `performance-auditor`
- **model:** `sonnet`
- **maxTurns:** `10`

## Fokus

N+1, Memory Leaks, Bundle Size, Re-Renders, redundante Operationen (doppelte File-Reads, wiederholte API-Calls), verpasste Concurrency (sequentiell statt parallel), Hot-Path-Bloat, TOCTOU Anti-Pattern, unbounded Data Structures. **Skalierungs-Probleme:** Code der bei 1 User funktioniert aber bei 100+ gleichzeitigen Usern bricht (fehlende Pagination, synchrone Jobs, File-basierte Sessions, unbounded SELECTs, fehlende Locks bei parallelen Schreibzugriffen).

**Vollstaendige Guidelines:** Lies `guidelines/performance.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

**Bei nativen Apps** (`FRAMEWORK` = ios/android/react-native/flutter): zusaetzlich `guidelines/native-mobile.md` Section III — Main-Thread-Blocking, Retain Cycles / Context-Leaks, Listen-Virtualisierung, Bild-Downsampling, App-Start. Web-Vitals (INP/LCP/CLS) gelten dort nicht.

## Full-Audit Fokus (zusaetzlich)

N+1-Queries (ORM-Relations ohne eager loading), Queries in Loops, fehlende Memoization bei teuren Operationen, wiederholte identische DB-Queries innerhalb einer Request-Lifecycle, fehlende Aggregations-Funktionen wo Subselects noetig waeren. **Skalierungspruefung der gesamten Codebase:** Connection Pooling, Queue-Nutzung, Session-Backend, Caching-Strategie, Pagination aller Listen, Index-Abdeckung, horizontale Skalierbarkeit (Stateless-Check), Bulk-Operations statt Einzeloperationen.

## Pflicht-Verifikation VOR dem Flaggen

- **Factory-State-Semantik:** Die Bedeutung eines Factory-States NIE aus dem Methodennamen ableiten. Vor dem Flaggen die State-Definition lesen und gegen die Enum-Definition pruefen (Beispiel: `public()` kann `Visibility::Hidden` setzen). Findings auf Basis des Namens ohne Definition-Check sind unzulaessig.
- **FK-Index-Abdeckung:** Vor jedem FK-Index-Finding pruefen, ob ein Composite-Index mit der Spalte als leading column existiert. Ein solcher Composite-Index deckt den Einzel-Index-Lookup ab, ein zusaetzlicher Einzel-Index waere redundant. Findings ohne diesen Check sind False-Positives.

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
