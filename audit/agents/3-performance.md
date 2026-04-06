# Subagent 3: Performance & Efficiency

- **subagent_type:** `performance-auditor`
- **model:** `haiku`
- **maxTurns:** `10`

## Fokus

N+1, Memory Leaks, Bundle Size, Re-Renders, redundante Operationen (doppelte File-Reads, wiederholte API-Calls), verpasste Concurrency (sequentiell statt parallel), Hot-Path-Bloat, TOCTOU Anti-Pattern, unbounded Data Structures. **Skalierungs-Probleme:** Code der bei 1 User funktioniert aber bei 100+ gleichzeitigen Usern bricht (fehlende Pagination, synchrone Jobs, File-basierte Sessions, unbounded SELECTs, fehlende Locks bei parallelen Schreibzugriffen).

**Vollstaendige Guidelines:** Lies `guidelines/performance.md` im Skill-Verzeichnis und pruefe den Code gegen alle dort beschriebenen Regeln.

## Full-Audit Fokus (zusaetzlich)

N+1-Queries (ORM-Relations ohne eager loading), Queries in Loops, fehlende Memoization bei teuren Operationen, wiederholte identische DB-Queries innerhalb einer Request-Lifecycle, fehlende Aggregations-Funktionen wo Subselects noetig waeren. **Skalierungspruefung der gesamten Codebase:** Connection Pooling, Queue-Nutzung, Session-Backend, Caching-Strategie, Pagination aller Listen, Index-Abdeckung, horizontale Skalierbarkeit (Stateless-Check), Bulk-Operations statt Einzeloperationen.

## Projektspezifischer Kontext

{PROJECT_CONTEXT}
