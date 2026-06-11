# Data-Migration Safety Guidelines

Regeln fuer Datenbank-Migrationen: destruktive Operationen, Locking, Rollback, Deploy-Reihenfolge. Gilt fuer Laravel-Migrations, aber die Prinzipien sind framework-agnostisch (Django, Rails, raw SQL).

## Contents
- I. Destruktive Operationen
- II. Locking & grosse Tabellen
- III. Rollback & Reversibilitaet
- IV. Daten-Integritaet
- V. Deploy-Reihenfolge (Expand-Contract)
- VI. Laravel-Spezifika
- VII. Audit-Checkliste

## I. Destruktive Operationen

- **`dropColumn` / `dropTable` nie im selben Release wie der Code-Entfernung-PR.** Erst Code deployen, der die Spalte nicht mehr nutzt, ein Release abwarten, DANN droppen. Sonst bricht ein Rollback des Codes auf eine Spalte, die nicht mehr existiert.
- **Renames sind Drops in Verkleidung.** `renameColumn` bricht laufenden Code zwischen Migration und Deploy. Pattern: neue Spalte adden → Code schreibt beide → Backfill → Code liest neu → alte Spalte droppen (separates Release).
- **Jeder Drop braucht eine explizite Begruendung** im Migration-Kommentar: warum ist das Datum verzichtbar, gibt es einen Export/Backup-Verweis?
- **`truncate` / `delete` ohne `where` in Migrationen:** Critical-Finding, immer.

## II. Locking & grosse Tabellen

- **`ALTER TABLE` lockt** (MySQL: je nach Operation und Version). Auf Tabellen > ~100k Rows: Lock-Dauer abschaetzen, Migration ausserhalb der Stosszeiten oder mit Online-DDL (`ALGORITHM=INPLACE`).
- **Index-Erstellung auf grossen Tabellen:** Postgres `CREATE INDEX CONCURRENTLY` (nicht in Transaktion!), MySQL Online-DDL pruefen.
- **Backfills nie als ein UPDATE:** `chunkById()` (Laravel) oder Batch-Loop mit Limit. Ein `UPDATE users SET ...` ohne Chunking auf 1M Rows haelt die Tabelle fest und sprengt Replikation.
- **Backfill gehoert in einen Command/Job, nicht in die Migration,** wenn er laenger als ~30s laufen kann. Migrationen blockieren den Deploy.

## III. Rollback & Reversibilitaet

- **`down()` muss funktionieren oder explizit leer sein mit Kommentar warum.** Ein `down()` das `dropColumn` auf eine Spalte mit Daten macht, ist kein Rollback, sondern Datenverlust — dann lieber `throw new RuntimeException('irreversible')` mit Begruendung.
- **`down()` testen gehoert zum Review:** `migrate` + `migrate:rollback` + `migrate` muss durchlaufen.
- **Daten-Migrationen (UPDATE/INSERT in Migration) sind fast nie reversibel** — explizit kennzeichnen.

## IV. Daten-Integritaet

- **NOT NULL auf bestehende Spalte:** erst Default setzen oder Backfill, dann Constraint. Reihenfolge im selben Migration-File pruefen.
- **Foreign Key auf bestehende Daten:** Orphans VOR dem Constraint bereinigen (sonst schlaegt die Migration in Prod fehl, lokal mit sauberen Testdaten nicht).
- **Unique Constraint nachtraeglich:** Duplikate-Check + Bereinigungsstrategie muss VOR dem Constraint laufen.
- **Enum-/Status-Spalten erweitern statt umbauen:** neue Werte adden ist safe, Werte entfernen braucht Daten-Pruefung.

## V. Deploy-Reihenfolge (Expand-Contract)

Zero-Downtime-Grundregel: **Code-Version N und N+1 muessen beide mit dem aktuellen Schema funktionieren.**

1. **Expand:** Schema additiv erweitern (neue Spalte/Tabelle, nullable oder mit Default)
2. **Migrate:** Code deployen der beides kann (schreibt neu, liest beides)
3. **Backfill:** Alte Daten nachziehen (chunked, im Job)
4. **Contract:** Altes Schema entfernen (separates Release, siehe I)

Audit-Signal: Migration UND Code-Aenderung die sie sofort voraussetzt im selben Diff → pruefen ob ein Deploy-Zwischenzustand bricht.

## VI. Laravel-Spezifika

- **MySQL kann DDL nicht in Transaktionen:** Bei mehreren DDL-Statements in einer Migration schlaegt Statement 3 fehl → 1+2 sind schon applied, Migration haengt halb. Grosse Migrationen splitten.
- **`Schema::hasColumn()` / `hasTable()` Guards** in Migrationen, die auf mehreren Umgebungen mit Drift laufen.
- **`$withinTransaction = false`** fuer `CREATE INDEX CONCURRENTLY` (Postgres).
- **Model-Nutzung in Migrationen vermeiden:** Models aendern sich, Migrationen sind eingefroren. `DB::table()` statt `User::` — sonst bricht die Migration, wenn das Model spaeter umzieht oder einen Global Scope bekommt.
- **`migrate:fresh` vs Produktionsrealitaet:** Eine Migration-Folge, die nur via `fresh` funktioniert (nicht inkrementell von Prod-Stand), ist kaputt.

## VII. Audit-Checkliste

| Check | Schweregrad bei Verstoss |
|---|---|
| `dropColumn`/`dropTable`/`renameColumn` im selben Diff wie Code-Nutzung-Entfernung | Important |
| `truncate`/`delete` ohne `where` in Migration | Critical |
| Unchunked UPDATE/Backfill auf potentiell grosser Tabelle | Important |
| `down()` mit Datenverlust ohne Kennzeichnung | Important |
| NOT NULL / FK / Unique auf bestehende Daten ohne Bereinigung davor | Important |
| Models statt `DB::table()` in Migration | Minor |
| Mehrere DDL-Statements in einer Migration (MySQL) | Minor |
| Backfill > 30s in Migration statt Command/Job | Important |
| Migration + abhaengiger Code im selben Deploy ohne Expand-Contract | Important (medium confidence — Deploy-Setup beruecksichtigen) |
